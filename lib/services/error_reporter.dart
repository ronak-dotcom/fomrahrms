import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/image_compress.dart';

/// Records what breaks in the app, for the App Health page.
///
/// Before this, a screen that crashed or threw on someone's phone left no
/// trace anywhere; the only record was whatever screenshot reached
/// Management. Three things now write to `app_error_logs`:
///
///  * [install] catches every uncaught error, from the Flutter framework
///    (build, layout, paint) and from async code, as kind `crash`.
///  * [log] lets code that catches a failure record it (`error`), and
///    SupabaseService records every failed write (`write_failed`).
///  * [reportProblem] is the "Report a problem" button (`report`), with the
///    user's own description and, optionally, a picture of the screen.
///
/// The database decides who the entry belongs to from the signed-in
/// session; nothing here sends a name or ID. It also rate-limits and
/// collapses repeats, so a widget that throws on every frame costs one row.
class ErrorReporter {
  ErrorReporter._();

  /// Wraps the whole app (see FomraHrmsApp.builder) so the current screen
  /// can be captured for a problem report.
  static final GlobalKey screenKey = GlobalKey(debugLabel: 'error-reporter-screen');

  /// Returns the current route, e.g. `/employee/leave/apply`. Set by app.dart,
  /// which owns the router.
  static String Function()? screenResolver;

  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0+1');

  static String get platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  static String get currentScreen {
    try {
      return screenResolver?.call() ?? '';
    } catch (_) {
      return '';
    }
  }

  static SupabaseClient? get _db {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Errors seen before Supabase finished initialising, sent once it has.
  static final List<Map<String, dynamic>> _pending = [];
  static bool _sending = false;

  /// Install the global handlers. Call once, after
  /// WidgetsFlutterBinding.ensureInitialized().
  static void install() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      // Keep the default behaviour (console output, red screen in debug).
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
      // Image and network-image failures are noise, not crashes.
      final library = details.library ?? '';
      if (library.contains('image resource service')) return;
      log('crash', details.exceptionAsString(),
          stack: details.stack,
          context: {
            if (library.isNotEmpty) 'library': library,
            if (details.context != null) 'while': details.context.toString(),
          });
    };

    final previousPlatformHandler = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      log('crash', error.toString(), stack: stack);
      return previousPlatformHandler?.call(error, stack) ?? true;
    };
  }

  /// Record a failure. Never throws and never awaits the network on the
  /// caller's behalf.
  static void log(
    String kind,
    String message, {
    StackTrace? stack,
    String? screen,
    Map<String, dynamic>? context,
  }) {
    try {
      final entry = <String, dynamic>{
        'p_kind': kind,
        'p_screen': screen ?? currentScreen,
        'p_message': message,
        'p_stack': stack?.toString(),
        'p_platform': platform,
        'p_app_version': appVersion,
        'p_context': context ?? const <String, dynamic>{},
      };
      _rememberRecent(message);
      if (_pending.length < 50) _pending.add(entry);
      unawaited(_flush());
    } catch (_) {
      // Error reporting must never cause an error of its own.
    }
  }

  static Future<void> _flush() async {
    if (_sending) return;
    final db = _db;
    if (db == null) return; // retried on the next log() or reportProblem()
    _sending = true;
    try {
      while (_pending.isNotEmpty) {
        final entry = _pending.removeAt(0);
        try {
          await db.rpc('log_app_error', params: entry);
        } catch (_) {
          // Offline or rejected: drop it rather than loop.
        }
      }
    } finally {
      _sending = false;
    }
  }

  /// A picture of the current screen, or null where the renderer cannot
  /// produce one. Call before opening any dialog, so the dialog is not in it.
  static Future<ScreenCapture?> captureScreen() async {
    try {
      final boundary =
          screenKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return null;
      // Logical pixels, capped at 1280 wide: legible, and small enough to
      // upload over a phone connection.
      final width = boundary.size.width;
      final ratio = width > 1280 ? 1280 / width : 1.0;
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      final png = data.buffer.asUint8List();
      final jpeg = await compressImage(png, 'image/png');
      return jpeg != null
          ? ScreenCapture(jpeg, 'image/jpeg', 'jpg')
          : ScreenCapture(png, 'image/png', 'png');
    } catch (_) {
      return null;
    }
  }

  /// Send a problem report. Returns null on success, or a message to show.
  static Future<String?> reportProblem({
    required String note,
    required String screen,
    ScreenCapture? screenshot,
  }) async {
    final db = _db;
    if (db == null) return 'Not connected. Please try again in a moment.';
    String? path;
    var screenshotFailed = false;
    final uid = db.auth.currentUser?.id;
    if (screenshot != null && uid != null) {
      path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${screenshot.extension}';
      try {
        await db.storage.from('problem-reports').uploadBinary(
              path,
              screenshot.bytes,
              fileOptions: FileOptions(contentType: screenshot.mimeType),
            );
      } catch (_) {
        // Send the report without the picture rather than not at all.
        path = null;
        screenshotFailed = true;
      }
    }
    try {
      await db.rpc('report_problem', params: {
        'p_screen': screen,
        'p_note': note,
        'p_screenshot_path': path,
        'p_platform': platform,
        'p_app_version': appVersion,
        'p_context': {
          if (screenshotFailed) 'screenshot': 'upload failed',
          'recent_errors': _recentMessages,
        },
      });
      unawaited(_flush());
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not send the report: $e';
    }
  }

  /// The last few errors this session, attached to a problem report so the
  /// report and the crash behind it can be matched up.
  static final List<String> _recent = [];
  static List<String> get _recentMessages => List.unmodifiable(_recent);

  static void _rememberRecent(String message) {
    _recent.add(message.length > 200 ? message.substring(0, 200) : message);
    if (_recent.length > 5) _recent.removeAt(0);
  }
}

class ScreenCapture {
  final Uint8List bytes;
  final String mimeType;
  final String extension;
  const ScreenCapture(this.bytes, this.mimeType, this.extension);
}
