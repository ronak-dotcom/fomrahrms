import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../models/user_session.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/image_compress.dart';
import 'gps_tracking_service.dart';
import 'supabase_service.dart';

/// Whether the signed-in user must supply a selfie to check in or out.
///
/// Management works to no fixed hours and no fixed location, and their
/// attendance is oversight rather than a record anyone audits, so the selfie
/// adds nothing. Derived from the ROLE in ONE place rather than repeated at
/// each of the six capture sites — the late-reason prompt was raised in three
/// separate files and fixing only one of them cost several rounds.
bool get selfieRequiredForCurrentUser =>
    UserSession.role != UserRole.management && !UserSession.exemptFromSelfie;

/// Mandatory attendance selfie: opens the device camera directly (never the
/// gallery), burns the date/day/time/GPS coordinates into the photo, then
/// compresses it to the app's shared ~200KB target. Used by every
/// check-in/check-out entry point so the requirement can't be bypassed by
/// picking a different screen.
class SelfieCaptureService {
  // Remembered per device, not per session. When both the camera and the
  // photo picker fail, image_picker is simply non-functional in that browser
  // — no permission change fixes it. One employee spent 16 attempts on a
  // 120-second timeout each, over half an hour, rediscovering the same dead
  // end. Once known, the app should say so immediately and point at the
  // manager-confirmation route instead of making her wait again.
  static const _pickerBrokenKey = 'selfie_picker_unavailable';
  static bool? _pickerBrokenCache;

  /// True when this device has already proved it cannot produce a selfie.
  static Future<bool> isPickerUnavailable() async {
    if (_pickerBrokenCache != null) return _pickerBrokenCache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      _pickerBrokenCache = prefs.getBool(_pickerBrokenKey) ?? false;
    } catch (_) {
      _pickerBrokenCache = false;
    }
    return _pickerBrokenCache!;
  }

  static Future<void> _markPickerUnavailable() async {
    _pickerBrokenCache = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pickerBrokenKey, true);
    } catch (_) {/* remembering is an optimisation, not a requirement */}
  }

  /// Cleared on a successful capture, so a device that starts working again
  /// — a browser update, a different browser — is not held to an old verdict.
  static Future<void> _clearPickerUnavailable() async {
    if (_pickerBrokenCache == false) return;
    _pickerBrokenCache = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pickerBrokenKey);
    } catch (_) {}
  }

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  /// Returns the final compressed JPEG bytes, or null if the employee
  /// cancelled the camera, the shot couldn't be processed, or it couldn't be
  /// compressed under the size cap — callers must treat null as "selfie
  /// required" and block the check-in/out rather than proceeding without one.
  /// Why the last capture returned null. Every failure path here used to
  /// return a bare null, so a blocked check-in showed no reason at all —
  /// one employee had zero selfies on record while colleagues had hundreds,
  /// and nothing anywhere said which step was failing for her.
  static String? lastFailure;

  /// True when the last capture came from the photo picker rather than a
  /// direct camera launch. Recorded rather than hidden: a picker selection
  /// could be an existing photo, so HR should be able to tell the two apart
  /// even though both are watermarked identically.
  static bool lastUsedFallback = false;

  static Future<Uint8List?> capture({required String label}) async {
    lastFailure = null;
    lastUsedFallback = false;

    // Already proved unable on this device: fail straight away rather than
    // spending another 120s on the camera and 120s on the picker to reach
    // the same answer. The employee gets the alternative route immediately.
    if (await isPickerUnavailable()) {
      lastFailure = 'This browser will not open the camera or photo library. '
          'Use "Attendance Issue" in the menu to have your manager confirm '
          'your attendance, or try a different browser.';
      return null;
    }

    XFile? shot;
    try {
      // Timed out because this can never resolve on iOS Safari: if the
      // camera sheet is dismissed in certain ways, or the browser refuses to
      // open it, pickImage() simply never completes. The caller has already
      // set _submitting = true by then, so the check-in button greys out and
      // stays that way — "nothing happens, it's just stuck". Two minutes is
      // generous for actually taking a photo while still bounded.
      shot = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1600,
        imageQuality: 90,
      ).timeout(const Duration(seconds: 120));
    } on TimeoutException {
      shot = await _fallbackPick();
      if (shot == null) return null;
    } catch (_) {
      // iOS Safari refuses a direct camera launch on some devices - one
      // employee could not check in for over a week because of it. Rather
      // than waive the selfie, which is the control itself, fall back to the
      // photo picker: on iOS that sheet still offers "Take Photo", so a live
      // selfie is usually still what gets captured.
      shot = await _fallbackPick();
      if (shot == null) return null;
    }
    if (shot == null) {
      // pickImage returning null WITHOUT throwing is the commonest way this
      // fails on iOS Safari: the browser declines to open the camera and
      // reports it as a cancellation rather than an error. The fallback used
      // to trigger only on a timeout or an exception, so this - the most
      // frequent failure in the attempt log - skipped it entirely and the
      // employee never saw a picker at all.
      shot = await _fallbackPick();
      if (shot == null) return null;
    }

    final pos = await GpsTrackingService.getCurrentLocation();
    final Uint8List rawBytes;
    try {
      rawBytes = await shot.readAsBytes();
    } catch (e) {
      lastFailure = 'Could not read the photo: $e';
      return null;
    }

    Uint8List watermarked;
    try {
      watermarked = await _drawWatermark(rawBytes, _lines(label, DateTime.now(), pos));
    } catch (e) {
      lastFailure = 'Could not stamp the photo: $e';
      return null;
    }

    try {
      await _clearPickerUnavailable();
      return compressImage(watermarked, 'image/png');
    } catch (e) {
      lastFailure = 'Could not compress the photo: $e';
      return null;
    }
  }

  /// Captures + uploads in one step, for the three check-in/out entry
  /// points that all need identical "no selfie, no check-in/out" behavior.
  /// Returns the storage path, or null if the employee cancelled the camera
  /// or the shot couldn't be captured/compressed/uploaded — callers must
  /// treat null as a hard stop, not a skip.
  static Future<String?> captureAndUpload({
    required String employeeId,
    required String date, // 'dd/MM/yyyy'
    required String kind, // 'checkin' | 'checkout'
    required String label, // 'Check-In' | 'Check-Out'
  }) async {
    final bytes = await capture(label: label);
    if (bytes == null) {
      // capture() has already set lastFailure with the specific step.
      unawaited(SupabaseService.logCheckInAttempt(
        kind: kind == 'checkout' ? 'check_out' : 'check_in',
        outcome: 'selfie_failed',
        reason: lastFailure ?? 'selfie capture failed',
      ));
      return null;
    }
    // Also bounded: an upload stalling on a weak connection would leave the
    // button greyed just as surely as a camera that never opens.
    String? path;
    try {
      path = await SupabaseService.uploadAttendanceSelfie(
        employeeId: employeeId,
        date: date,
        kind: kind,
        bytes: bytes,
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      path = null;
    }
    if (path == null) {
      lastFailure = 'Photo taken but upload failed';
      unawaited(SupabaseService.logCheckInAttempt(
        kind: kind == 'checkout' ? 'check_out' : 'check_in',
        outcome: 'selfie_failed',
        reason: lastFailure!,
      ));
    }
    return path;
  }

  /// Photo picker fallback for devices whose browser will not open the
  /// camera directly. Flags the result so it is distinguishable from a
  /// direct capture.
  static Future<XFile?> _fallbackPick() async {
    try {
      final shot = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 90)
          .timeout(const Duration(seconds: 120));
      if (shot == null) {
        lastFailure = 'No photo was selected. A selfie is required to check in.';
        return null;
      }
      lastUsedFallback = true;
      await _clearPickerUnavailable();
      return shot;
    } on TimeoutException {
      // Both routes failed: image_picker does not work in this browser at
      // all. Remembered so the next attempt does not repeat the wait.
      await _markPickerUnavailable();
      lastFailure = 'This browser will not open the camera or photo library. '
          'Use "Attendance Issue" in the menu to have your manager confirm '
          'your attendance, or try a different browser.';
      return null;
    } catch (e) {
      lastFailure = 'Could not open the camera or photo picker: $e';
      return null;
    }
  }

  static List<String> _lines(String label, DateTime now, Position? pos) {
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final day = _days[now.weekday - 1];
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final loc = pos != null
        ? 'GPS: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}'
        : 'GPS: unavailable';
    return ['$label — $date', day, time, loc];
  }

  static Future<Uint8List> _drawWatermark(Uint8List sourceBytes, List<String> lines) async {
    final codec = await ui.instantiateImageCodec(sourceBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width.toDouble();
    final h = image.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(image, Offset.zero, Paint());

    final fontSize = (w * 0.032).clamp(14.0, 34.0);
    final textPainter = TextPainter(
      text: TextSpan(
        text: lines.join('\n'),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.35,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 24);

    final bandHeight = textPainter.height + 24;
    canvas.drawRect(
      Rect.fromLTWH(0, h - bandHeight, w, bandHeight),
      Paint()..color = const Color(0xB3000000),
    );
    textPainter.paint(canvas, Offset(12, h - bandHeight + 12));

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(image.width, image.height);
    final byteData = await outImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
