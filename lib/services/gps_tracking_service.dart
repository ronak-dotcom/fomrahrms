import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';
import '../models/user_session.dart';
import 'supabase_service.dart';

class GpsTrackingService {
  static StreamSubscription<Position>? _subscription;
  static Timer? _fallbackTimer;
  static double? latestLat;
  static double? latestLng;

  // Full route accumulated this session (pre-loaded from Supabase on start)
  static final List<List<double>> routePoints = [];

  static bool get isTracking => _subscription != null;

  /// Why a location fix failed, so the cause is visible instead of every
  /// failure collapsing into a bare `null`. Production had GPS null on 100%
  /// of attendance records with no way to tell whether location services were
  /// off, permission was denied, or the call threw.
  static String? lastLocationError;

  /// One-shot fix for check-in: fetch a fresh position directly instead of
  /// relying on the position stream (which may not have emitted yet). Unlike
  /// [start], this runs before tracking has ever been started this session —
  /// e.g. the very first check-in on a fresh install — so it must request
  /// permission itself rather than assume [start] already did.
  ///
  /// Returns null on failure, with [lastLocationError] set to a message that
  /// can be shown to the employee and logged.
  static Future<Position?> getCurrentLocation() async {
    lastLocationError = null;
    try {
      // On web there is no OS-level "location services" toggle to query, and
      // Geolocator.isLocationServiceEnabled() is unreliable there — in several
      // browsers it reports false (or throws) even when geolocation works
      // perfectly. The old code called it first and returned null on false,
      // which aborted before a position was ever requested. That is the most
      // likely reason production has null GPS on 100% of attendance records
      // while running entirely on the web build.
      //
      // So: on web, go straight to the permission request, which is the only
      // gate the browser actually enforces. Keep the check on mobile, where it
      // is meaningful and where a disabled GPS radio needs a distinct message.
      if (!kIsWeb) {
        bool serviceEnabled;
        try {
          serviceEnabled = await Geolocator.isLocationServiceEnabled();
        } catch (_) {
          serviceEnabled = true;   // never let the probe itself block check-in
        }
        if (!serviceEnabled) {
          lastLocationError =
              'Location services are turned off on this device. Turn on GPS / Location and try again.';
          return null;
        }
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        lastLocationError =
            'Location permission was not granted. Allow location access when your browser asks, then check in again.';
        return null;
      }
      if (perm == LocationPermission.deniedForever) {
        lastLocationError =
            'Location permission is blocked. Enable it for this site in your browser settings (the padlock icon in the address bar), then try again.';
        return null;
      }
      // Without a timeout this can hang indefinitely on a weak signal, leaving
      // the employee on a spinner with no idea anything is wrong.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      lastLocationError =
          'Could not get a GPS fix in time. Move somewhere with a clearer view of the sky and try again.';
      return null;
    } catch (e) {
      // Previously `catch (_) { return null; }` — three different causes all
      // collapsed to null, which is why the production failure was
      // undiagnosable for as long as it was.
      lastLocationError = 'Could not read your location: $e';
      // ignore: avoid_print
      print('getCurrentLocation failed: $e');
      return null;
    }
  }

  static Future<void> start() async {
    await stop();

    // Pre-load existing route from Supabase so a page refresh doesn't reset the trail
    if (UserSession.employeeId.isNotEmpty) {
      final today = DateTime.now();
      final dateStr =
          '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
      final existing = await SupabaseService.fetchGpsPoints(
        employeeId: UserSession.employeeId,
        date: dateStr,
      );
      routePoints.clear();
      routePoints.addAll(existing);
    }

    // Same web caveat as getCurrentLocation(): there is no OS location-services
    // toggle on web and this probe is unreliable there, so skipping it is what
    // lets tracking start at all in a browser.
    if (!kIsWeb) {
      bool serviceEnabled;
      try {
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
      } catch (_) {
        serviceEnabled = true;
      }
      if (!serviceEnabled) return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    // On Android, try to escalate from "while in use" to "always" so
    // tracking survives the app being backgrounded/closed. Android only
    // offers this as a second prompt after the first grant — if the user
    // declines, tracking still works while the app is open/foregrounded.
    if (defaultTargetPlatform == TargetPlatform.android &&
        perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }

    _subscription = Geolocator.getPositionStream(
      locationSettings: _platformLocationSettings(),
    ).listen(_recordPoint);

    // Movement-based updates alone leave long gaps for employees who stay
    // put for hours, so also sample on a timer to keep the trail populated
    // across the full check-in-to-check-out window.
    _fallbackTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      final pos = await getCurrentLocation();
      if (pos != null) _recordPoint(pos);
    });

    // Sends whatever has accumulated since the last flush. Kept separate
    // from the sampling timer above so recording resolution and write
    // frequency can be tuned independently.
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  static LocationSettings _platformLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'FOMRA HRMS — location tracking active',
          notificationText: 'Tracking your location while you\'re checked in.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
  }

  // Points are recorded in memory on every movement, but only written to
  // the database on this interval. Previously every 10-metre step triggered
  // two writes, and the route write re-sent the ENTIRE day's point array
  // each time — so by evening each step was rewriting hundreds of points
  // the database already had. Two field employees were generating over 200
  // writes a day each that way, growing heavier as the day went on.
  //
  // Batching changes none of the recorded detail: the same points are
  // captured at the same 10-metre resolution, they are just flushed
  // together rather than one at a time.
  static const _flushInterval = Duration(minutes: 2);
  static Timer? _flushTimer;
  static bool _dirty = false;

  static void _recordPoint(Position pos) {
    latestLat = pos.latitude;
    latestLng = pos.longitude;
    routePoints.add([pos.latitude, pos.longitude]);
    // Marks that there is something new to send; the flush timer does the
    // actual write.
    _dirty = true;
  }

  /// Writes the accumulated route if anything changed since the last flush.
  /// Safe to call when idle — it no-ops rather than issuing an empty write.
  static Future<void> _flush() async {
    if (!_dirty) return;
    if (UserSession.employeeId.isEmpty) return;
    if (latestLat == null || latestLng == null) return;

    _dirty = false;
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    await SupabaseService.updateLocation(
      employeeId: UserSession.employeeId,
      date: dateStr,
      location: '$latestLat,$latestLng',
    );
    await SupabaseService.updateGpsPoints(
      employeeId: UserSession.employeeId,
      date: dateStr,
      points: List.from(routePoints),
    );
  }

  static Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    // Flush BEFORE clearing the latest position: points recorded since the
    // last flush are still only in memory, and check-out is exactly when
    // the final stretch of the route matters. _flush() reads latestLat/Lng,
    // so nulling them first would silently drop this write.
    await _flush();
    latestLat = null;
    latestLng = null;
    // Don't clear routePoints — HR can still fetch the saved route from Supabase
  }
}
