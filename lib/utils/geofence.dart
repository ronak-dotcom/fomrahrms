import 'dart:math' as math;
import '../models/attendance_location.dart';

/// Distance/containment calculations against HR-configured [OfficeLocation]s.
/// Replaces the single hardcoded point/radius that used to live in
/// office_geofence.dart.
class Geofence {
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}

/// Outcome of checking a GPS fix against everywhere an employee is allowed
/// to be, per their resolved [AttendancePolicy].
class GeofenceResult {
  /// Whether this policy has any location concept at all (false for
  /// unrestricted policies) — drives whether a note can ever be required.
  final bool requiresLocation;
  final bool isWithinAnyLocation;
  final OfficeLocation? nearestLocation;
  final double? nearestDistanceMeters;

  const GeofenceResult({
    required this.requiresLocation,
    required this.isWithinAnyLocation,
    this.nearestLocation,
    this.nearestDistanceMeters,
  });

  /// True only when the policy demands a location AND the given position
  /// isn't near any of them (including a missing/unreadable GPS fix).
  bool get outsideAllowedLocation => requiresLocation && !isWithinAnyLocation;

  static const unrestricted = GeofenceResult(requiresLocation: false, isWithinAnyLocation: true);
}

/// Evaluates [position] (nullable — a failed GPS read counts as "outside")
/// against [locations] under [policy]. [locations] should already be
/// filtered to the employee's assigned, active locations.
GeofenceResult evaluateGeofence({
  required AttendancePolicy policy,
  required List<OfficeLocation> locations,
  required double? lat,
  required double? lng,
  double? accuracy,
}) {
  if (!policy.requiresLocation) return GeofenceResult.unrestricted;

  // No assigned locations at all is a setup gap, not a violation. This used
  // to fall through to "outside allowed location", which permanently
  // flagged the employee as off-site wherever they stood and demanded a
  // mandatory explanation note on every single check-in — an employee who
  // was never assigned a location on their first day simply could not check
  // in, with nothing on screen explaining why.
  //
  // Treating it as unrestricted lets them work while HR assigns a location;
  // an employee who has one is still held to it exactly as before.
  if (locations.isEmpty) return GeofenceResult.unrestricted;

  if (lat == null || lng == null) {
    return const GeofenceResult(
      requiresLocation: true,
      isWithinAnyLocation: false,
    );
  }

  OfficeLocation? nearest;
  double? nearestDist;
  bool within = false;
  for (final loc in locations) {
    final d = Geofence.distanceMeters(lat, lng, loc.latitude, loc.longitude);
    if (nearestDist == null || d < nearestDist) {
      nearestDist = d;
      nearest = loc;
    }
    if (d <= loc.radiusMeters) within = true;
    // A reading is only evidence of being outside if it is precise enough to
    // tell. Deepak was measured 566 m from Head Office — 66 m past a 500 m
    // radius — on a fix accurate to +/-2000 m: a cell-tower estimate, not
    // GPS. His true position was anywhere in a 4 km-wide circle, so calling
    // that "not at the office" states as fact something the data cannot
    // support. Where the margin of error covers the boundary, the reading is
    // inconclusive and the employee gets the benefit of the doubt. The raw
    // coordinates and accuracy are still recorded, so a genuinely distant
    // check-in remains visible to HR.
    if (accuracy != null && d <= loc.radiusMeters + accuracy) within = true;
  }

  return GeofenceResult(
    requiresLocation: true,
    isWithinAnyLocation: within,
    nearestLocation: nearest,
    nearestDistanceMeters: nearestDist,
  );
}
