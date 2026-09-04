class CheckInRecord {
  final String employee;
  final String date;
  final String time;
  final String location;
  const CheckInRecord({required this.employee, required this.date, required this.time, required this.location});
}

class CheckOutRecord {
  final String employee;
  final String date;
  final String time;
  final String location;
  const CheckOutRecord({required this.employee, required this.date, required this.time, required this.location});
}

class LateComingRecord {
  final String employee;
  final String date;
  final String arrivalTime;
  final String reason;
  const LateComingRecord({required this.employee, required this.date, required this.arrivalTime, required this.reason});
}

class AttendanceStore {
  static final List<CheckInRecord>    checkIns   = [];
  static final List<CheckOutRecord>   checkOuts  = [];
  static final List<LateComingRecord> lateComing = [];

  static bool isCheckedIn = false;
}

// Persistent record loaded from / saved to Supabase
class AttendanceRecord {
  final String id;
  final String employeeName;
  final String employeeId;
  final String date;
  final String checkInTime;
  final String checkOutTime;
  final String location;
  final List<List<double>> gpsPoints; // [[lat,lng], ...] route
  final String checkInNote;
  final String checkOutNote;
  // Storage object paths (not URLs) in the private `attendance-selfies`
  // bucket — never a public URL. HR/Management pages exchange these for a
  // short-lived signed URL on demand via SupabaseService.attendanceSelfieUrl.
  final String checkInSelfiePath;
  final String checkOutSelfiePath;
  // Structured GPS + geofence outcome, recorded separately for check-in and
  // check-out so checking out doesn't overwrite the check-in point (unlike
  // the legacy `location` string, which is a single shared field). Null
  // withinRadius means the employee's policy didn't require a location.
  final double? checkInLat;
  final double? checkInLng;
  final bool? checkInWithinRadius;

  /// Lateness excused by Management — typically a system fault, such as the
  /// browser refusing the location permission so the employee could not
  /// complete check-in until after their start time. The recorded time is
  /// deliberately left alone; this flag sits alongside it.
  final bool lateWaived;
  final String lateWaiverReason;
  /// Day worked outside normal hours for business reasons (BTL activity,
  /// site or project work). Presence, not absence — the timing rules are
  /// skipped and the day is shown in its own colour. No hours accounting.
  final bool onDuty;
  final String onDutyReason;
  /// 'device' (GPS + selfie as normal) or 'vouched' (a manager confirmed
  /// presence and HR approved; nothing on the device verified it).
  final String verification;
  final String vouchedBy;
  final double? checkOutLat;
  final double? checkOutLng;
  final bool? checkOutWithinRadius;
  final String locationPolicyName;

  const AttendanceRecord({
    required this.id,
    required this.employeeName,
    required this.employeeId,
    required this.date,
    this.checkInTime = '',
    this.checkOutTime = '',
    this.location = '',
    this.gpsPoints = const [],
    this.checkInNote = '',
    this.checkOutNote = '',
    this.checkInSelfiePath = '',
    this.checkOutSelfiePath = '',
    this.checkInLat,
    this.checkInLng,
    this.checkInWithinRadius,
    this.lateWaived = false,
    this.lateWaiverReason = '',
    this.onDuty = false,
    this.onDutyReason = '',
    this.verification = 'device',
    this.vouchedBy = '',
    this.checkOutLat,
    this.checkOutLng,
    this.checkOutWithinRadius,
    this.locationPolicyName = '',
  });
}
