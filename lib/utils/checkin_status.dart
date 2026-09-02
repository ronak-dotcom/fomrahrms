import '../models/leave_store.dart';
import '../models/office_timing.dart';

// onDuty sits alongside the timing outcomes rather than among them: a day
// worked outside normal hours for business reasons (BTL, site/project work)
// is presence, and the late/early rules simply do not apply to it. It takes
// precedence over `late` so an 8pm BTL start is not reported as a late
// arrival, while still being visibly distinct from an ordinary on-time day.
enum CheckInStatus { none, onTime, permission, late, onDuty }

class CheckInRowStatus {
  final CheckInStatus status;
  final int permMinutes;
  const CheckInRowStatus(this.status, this.permMinutes);
}

/// Minutes granted by an approved 'Permission' leave application for
/// [employeeName] covering [date]; 0 if none.
int approvedPermissionMinutesFor(
    List<LeaveApplication> leaveApps, String employeeName, DateTime date) {
  for (final a in leaveApps) {
    if (a.leaveType != 'Permission') continue;
    if (a.employeeName != employeeName) continue;
    if (a.managerStatus != LeaveApprovalStatus.approved) continue;
    if (a.from.year == date.year && a.from.month == date.month && a.from.day == date.day) {
      return LeaveStore.permMinutesFromReason(a.reason);
    }
  }
  return 0;
}

int? _minutesOf(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Determines whether [checkInTime] (a "HH:mm" string) on [date] for
/// [employeeName] is on time, late-but-covered-by-approved-permission, or
/// genuinely late against [schedule] (the employee's designation-based
/// office timing), checking [leaveApps] for a same-day approved Permission.
CheckInRowStatus checkInStatusFor(String checkInTime, DateTime date, String employeeName,
    List<LeaveApplication> leaveApps, OfficeTiming schedule,
    {bool lateWaived = false, bool onDuty = false}) {
  // Business work outside normal hours — the timing rules do not apply, but
  // the day stays visibly distinct rather than being folded into "on time",
  // so management can still see it was an on-duty day on the calendar.
  // Checked before lateWaived because on duty is a property of the day
  // itself, not an excused exception to it.
  if (onDuty) return const CheckInRowStatus(CheckInStatus.onDuty, 0);

  // Management has excused this arrival — normally because the app itself
  // prevented a timely check-in. Handled here, at the single point every
  // screen goes through, rather than at each of the eight call sites: the
  // late-reason prompt lived in three files and only one of them was right.
  if (lateWaived) return const CheckInRowStatus(CheckInStatus.onTime, 0);

  // Management has no fixed hours, so a check-in is never late. Handled here
  // rather than at each of the seven call sites, so no view can disagree with
  // another about whether the same person was late.
  if (schedule.noFixedTiming) return const CheckInRowStatus(CheckInStatus.onTime, 0);

  final minutes = _minutesOf(checkInTime);
  if (minutes == null) return const CheckInRowStatus(CheckInStatus.none, 0);
  if (minutes <= schedule.checkInMinutes) return const CheckInRowStatus(CheckInStatus.onTime, 0);

  final permMinutes = approvedPermissionMinutesFor(leaveApps, employeeName, date);
  if (permMinutes > 0 && minutes <= schedule.checkInMinutes + permMinutes) {
    return CheckInRowStatus(CheckInStatus.permission, permMinutes);
  }
  return const CheckInRowStatus(CheckInStatus.late, 0);
}

/// True when [checkInTime] ("HH:mm") is past [schedule]'s check-in time at
/// all — used for the compulsory-note prompt on check-in, before permission
/// is factored in.
bool isLateCheckIn(String checkInTime, OfficeTiming schedule) {
  // No fixed hours -> never late. Without this a no-fixed-timing schedule
  // (stored as 00:00-23:59) would make EVERY check-in after midnight "late",
  // which is worse than the default it replaces.
  if (schedule.noFixedTiming) return false;
  final minutes = _minutesOf(checkInTime);
  if (minutes == null) return false;
  return minutes > schedule.checkInMinutes;
}

/// True when [checkOutTime] ("HH:mm") is earlier than [schedule]'s
/// check-out time, adjusted by any same-day approved Permission minutes.
bool isEarlyCheckOut(String checkOutTime, OfficeTiming schedule, int permissionMinutes) {
  if (schedule.noFixedTiming) return false;   // no fixed hours -> never early
  final minutes = _minutesOf(checkOutTime);
  if (minutes == null) return false;
  return minutes < (schedule.checkOutMinutes - permissionMinutes);
}

/// True when a genuinely-late [checkInTime] ("HH:mm") still falls within
/// [schedule]'s forgivable grace window — only meaningful for records where
/// [checkInStatusFor] already returned [CheckInStatus.late].
bool isGraceLate(String checkInTime, OfficeTiming schedule) {
  final minutes = _minutesOf(checkInTime);
  if (minutes == null) return false;
  return minutes > schedule.checkInMinutes && minutes <= schedule.graceEndMinutes;
}

/// True when a late [checkInTime] ("HH:mm") is past [schedule]'s grace
/// window — always incurs the compulsory half-day deduction, no matter how
/// many grace excuses the employee has left that month.
bool isSevereLate(String checkInTime, OfficeTiming schedule) {
  final minutes = _minutesOf(checkInTime);
  if (minutes == null) return false;
  return minutes > schedule.graceEndMinutes;
}

/// Parses a "dd/MM/yyyy" date string (the format used by [AttendanceRecord.date]).
DateTime? parseSlashDate(String s) {
  final p = s.split('/');
  if (p.length != 3) return null;
  final d = int.tryParse(p[0]), mo = int.tryParse(p[1]), y = int.tryParse(p[2]);
  if (d == null || mo == null || y == null) return null;
  return DateTime(y, mo, d);
}

String permLabel(int minutes) {
  switch (minutes) {
    case 30: return '30m';
    case 60: return '1h';
    case 90: return '1.5h';
    case 120: return '2h';
    default: return '${minutes}m';
  }
}
