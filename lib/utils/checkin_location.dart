import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/attendance_policy_store.dart';
import '../models/office_timing.dart';
import '../models/user_session.dart';
import '../services/gps_tracking_service.dart';
import '../services/supabase_service.dart';
import 'geofence.dart';

/// Everything a check-in or check-out needs to know about where the employee is.
class CheckInLocation {
  final Position? position;
  final GeofenceResult geofence;
  final String policyName;
  final String nearestLocationName;

  const CheckInLocation({
    required this.position,
    required this.geofence,
    required this.policyName,
    required this.nearestLocationName,
  });

  bool get outsideAllowedLocation => geofence.outsideAllowedLocation;

  /// Why the position could not be read, when it could not.
  String? get gpsError =>
      position == null ? GpsTrackingService.lastLocationError : null;

  double? get lat => position?.latitude;
  double? get lng => position?.longitude;

  /// Radius in metres the device reported for this fix. Discarded until now,
  /// which meant a +/-2000 m cell-tower estimate was stored identically to a
  /// +/-5 m satellite fix and both were measured against a 150 m geofence.
  double? get accuracy => position?.accuracy;
  bool? get withinRadius => position == null ? null : geofence.isWithinAnyLocation;
}

/// Resolves the employee's position and evaluates it against their geofence.
///
/// Extracted because only ONE of the three check-in paths did any of this.
/// check_in_page evaluated the geofence and required a reason when outside;
/// the dashboard quick-check-in card and employee_attendance_page did neither
/// — no geofence evaluation at all, and they never passed lat/lng to
/// saveCheckIn, so the coordinates were fetched and then discarded.
///
/// That is why every attendance record has null GPS and a null within-radius
/// verdict, and why an employee could check in from anywhere through the
/// dashboard without being asked for a reason. The configured geofences were
/// bypassed by the most convenient button in the app.
///
/// One implementation, so the three paths cannot disagree again — the same
/// mistake as the late-reason prompt, which existed in three files with only
/// one of them correct.
Future<CheckInLocation> resolveCheckInLocation() async {
  // Position FIRST, before anything that awaits the network. Safari ties the
  // geolocation prompt to the user gesture and refuses if too much has
  // happened since the tap.
  final pos = await GpsTrackingService.getCurrentLocation();

  // REFRESH, not ensureLoaded. ensureLoaded() returns immediately once the
  // store has loaded in this session, so a session that started BEFORE HR
  // assigned someone a location never sees that assignment.
  //
  // That is not hypothetical: Mithun checked in 24.5 m from Higrove Gardens,
  // inside a 150 m radius and correctly assigned to it in the database, and
  // was still told he was outside and made to type a reason. His app had
  // loaded the store before the assignment existed, so locationsForEmployee()
  // returned an empty list — which evaluateGeofence() reads as "outside
  // everywhere".
  //
  // Check-in happens about twice a day per person, so a guaranteed-fresh fetch
  // is cheap; being wrong about where someone is standing is not. Failures are
  // swallowed so a network blip cannot block attendance — the cached data is
  // still better than nothing.
  try {
    await AttendancePolicyStore.refresh();
  } catch (_) {
    await AttendancePolicyStore.ensureLoaded();
  }
  await OfficeTimingStore.ensureLoaded();

  final policy = AttendancePolicyStore.policyForEmployee(
    employeeId: UserSession.employeeId,
    department: UserSession.department,
    workLocation: UserSession.workLocation,
  );
  final locations =
      AttendancePolicyStore.locationsForEmployee(UserSession.employeeId);

  // An approved On Duty day means the person is working somewhere that is
  // deliberately not a company site — a conference, a client office, an
  // exhibition. Holding them to a geofence on such a day would demand a
  // written excuse for doing exactly what was already approved, so the
  // check is lifted. The coordinates are still recorded, so management can
  // see where they actually were.
  final onDutyToday = await SupabaseService.hasApprovedOnDuty(
    UserSession.employeeId,
    DateTime.now(),
  );

  // A failed lookup is treated as being outside every assigned location, so an
  // employee whose policy requires one still gets a check-in — with a required
  // reason — rather than silently skipping the geofence.
  final geofence = onDutyToday
      ? GeofenceResult.unrestricted
      : evaluateGeofence(
          policy: policy,
          locations: locations,
          lat: pos?.latitude,
          lng: pos?.longitude,
        );

  return CheckInLocation(
    position: pos,
    geofence: geofence,
    policyName: policy.name,
    nearestLocationName: geofence.nearestLocation?.name ?? '',
  );
}

/// Shows the "you are not at your assigned location" prompt.
///
/// Returns true when the caller should stop and let the employee type a
/// reason. Deliberately not a hard block: a genuine GPS failure must not stop
/// someone recording their attendance, and the reason is captured on the
/// record either way.
Future<bool> promptForLocationReason(
  BuildContext context,
  CheckInLocation loc, {
  required bool noteIsEmpty,
  bool isCheckOut = false,
}) async {
  if (!loc.outsideAllowedLocation || !noteIsEmpty) return false;

  final gpsError = loc.gpsError;
  final where = loc.nearestLocationName.isNotEmpty
      ? 'outside ${loc.nearestLocationName}'
      : 'outside your assigned location';
  final action = isCheckOut ? 'check out' : 'check in';

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(gpsError != null
          ? 'Could Not Check Your Location'
          : 'You Are Not At Your Assigned Location'),
      content: Text(
        gpsError != null
            ? '$gpsError\n\nYou can still $action — please enter a reason below.'
            : "You're $where. Please enter a reason below to $action from this location.",
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return true;
}
