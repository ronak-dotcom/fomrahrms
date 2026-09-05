import 'user_session.dart';
import '../utils/attendance_cycle.dart';

enum LeaveApprovalStatus { pending, approved, denied }

class LeaveApplication {
  final String id;
  final String employeeName;
  final String department;
  final String leaveType;
  final DateTime from;
  final DateTime to;
  final int days;
  final String reason;
  final DateTime appliedOn;

  // Single shared decision — editable by both manager and management
  LeaveApprovalStatus managerStatus = LeaveApprovalStatus.pending;
  String decidedBy        = '';
  String rejectionComment = '';
  bool   isHalfDay        = false;
  // Sickness proof attachment (Medical / Sick Leave) — URL in Supabase storage, empty if none.
  String proofUrl         = '';

  // Explicit CL/ML/EL/LOP balance the employee chose to draw this leave from.
  // Empty for older records — falls back to guessing from [leaveType] text.
  String leaveBucket = '';

  // True once management (HR/admin) has made a decision — locks manager's controls
  bool managementDecided = false;

  // Set when a decision is made; cleared on undo. Used for the 10-min undo window.
  DateTime? decidedAt;

  /// Actual deduction: 0.5 for half day, full days otherwise.
  double get effectiveDays => isHalfDay ? 0.5 : days.toDouble();

  /// The balance bucket (CL/ML/EL/LOP) this leave draws from — the
  /// employee's explicit choice if set, otherwise inferred from the label.
  String get bucket =>
      leaveBucket.isNotEmpty ? leaveBucket : LeaveStore.effectiveBucket(leaveType);

  // Aliases used by employee view (same field, kept for clarity)
  LeaveApprovalStatus get effectiveStatus => managerStatus;
  String get effectiveComment => rejectionComment;

  LeaveApplication({
    required this.id,
    required this.employeeName,
    required this.department,
    required this.leaveType,
    required this.from,
    required this.to,
    required this.days,
    required this.reason,
    required this.appliedOn,
  });
}

class LeaveStore {
  static final List<LeaveApplication> applications = [];
  static int _counter = 0;

  /// Globally unique, because the counter never could be.
  ///
  /// syncCounter() only ever saw the applications the CURRENT user could
  /// load, and RLS limits an employee to their own — so the counter restarted
  /// at zero for each person and every employee's first request was LV-001.
  /// Devaraj's request on 05/09 was generated as LV-001, which already
  /// belonged to Nirmal Kumar: the upsert either collided or was refused, and
  /// the employee was told it had been submitted either way.
  ///
  /// RLS is what saved Nirmal here — an employee cannot write another's row.
  /// Had the applicant been HR or a manager, whose policy DOES allow it, the
  /// upsert would have silently overwritten someone else's approved leave.
  static String generateId() {
    final now = DateTime.now();
    final stamp = now.microsecondsSinceEpoch.toRadixString(36).toUpperCase();
    // Employee id keeps it readable and collision-proof even if two people
    // submit in the same microsecond.
    final who = UserSession.employeeId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return 'LV-$who-$stamp';
  }

  /// Retained: older records still carry LV-001 style ids and other code
  /// calls this. It no longer feeds id generation, which is now independent
  /// of what the caller happens to have loaded.
  static void syncCounter() {
    for (final a in applications) {
      final n = int.tryParse(a.id.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n != null && n > _counter) _counter = n;
    }
  }

  /// Maps any leave-type label to its balance bucket (CL / ML / EL / LOP).
  /// All display-facing labels (Personal Leave, To Vote, Funeral, etc.) that
  /// should deduct from CL return 'CL'.
  ///
  /// HR can freely rename/add entries in the "Leave Types" dropdown config
  /// (see edit_leave_form_page.dart), so this matches by keyword rather than
  /// exact label text — an exact match breaks the moment HR edits a label
  /// (e.g. it silently miscategorizes Medical Leave as CL and hides the
  /// sickness-proof upload).
  static String effectiveBucket(String leaveType) {
    final t = leaveType.toLowerCase();
    if (t.contains('medical') || t.contains('sick')) return 'ML';
    if (t.contains('earned')) return 'EL';
    if (t.contains('lop')) return 'LOP';
    return 'CL'; // Casual, Personal, To Vote, Funeral, Maternity, Paternity…
  }

  /// Minutes charged for a Permission request.
  ///
  /// Only 30, 60 and 120 are permitted — the 120-minute monthly allowance is
  /// availed as 4x30, 2x60 or 1x120. Returns 0 for anything else, and the
  /// database rejects such a row outright
  /// (set_and_check_permission_minutes).
  ///
  /// Two things this deliberately does differently from the old version:
  ///
  ///  * It reads the DURATION SEGMENT ONLY — the text before the first '|'.
  ///    The stored string is 'Permission: $duration | $reason | $description'
  ///    and contains the employee's own free text, so the previous whole
  ///    string match let a 2-hour permission described as "back in 30 Minutes"
  ///    be charged 30 — under-spending quota and, worse, under-crediting an
  ///    approved permission so the arrival counted as late and cost half a
  ///    day's pay.
  ///
  ///  * Retired 90-minute phrasings are rejected BEFORE the substring tests.
  ///    '1 Hour 30 Minutes' contains '1 Hour', and the old order matched
  ///    '30 Minutes' first, so the Staff Portal's 1h30m option was charged 30.
  static int permMinutesFromReason(String reason) {
    final duration = reason.split('|').first;
    final r = duration.toLowerCase();

    // Withdrawn slot — reject rather than round to a neighbouring value.
    if (r.contains('1½') ||
        r.contains('1 1/2') ||
        r.contains('90') ||
        r.contains('1 hour 30') ||
        r.contains('1 hr 30')) {
      return 0;
    }

    if (r.contains('2 hours') || r.contains('2 hrs') || r.contains('120')) return 120;
    if (r.contains('1 hour') || r.contains('1 hr') || r.contains('60')) return 60;
    if (r.contains('30 minutes') || r.contains('30 mins') || r.contains('30')) return 30;
    return 0;
  }

  /// The three permitted permission durations, in minutes.
  static const permittedPermissionMinutes = [30, 60, 120];

  /// Minutes used in the CURRENT ATTENDANCE CYCLE (26th -> 25th), not the
  /// calendar month. Comparing calendar months put 26 July and 3 August in
  /// different windows when they are in the same cycle, which let an employee
  /// spend a full 120-minute allowance twice in eleven days.
  static int permUsedThisCycle(String employeeName) {
    final now = DateTime.now();
    return applications
        .where((a) =>
            a.leaveType == 'Permission' &&
            a.employeeName == employeeName &&
            sameAttendanceCycle(a.from, now) &&
            a.managerStatus != LeaveApprovalStatus.denied)
        .fold<int>(0, (sum, a) => sum + permMinutesFromReason(a.reason));
  }

  @Deprecated('Use permUsedThisCycle — the cycle runs 26th to 25th')
  static int permUsedThisMonth(String employeeName) => permUsedThisCycle(employeeName);

  /// Count-based monthly cap used by the Staff Portal (max 2 permission
  /// requests/month, regardless of duration) — distinct from the regular
  /// employee portal's minute-based cap in [permUsedThisMonth].
  static int permCountThisCycle(String employeeName) {
    final now = DateTime.now();
    return applications
        .where((a) =>
            a.leaveType == 'Permission' &&
            a.employeeName == employeeName &&
            sameAttendanceCycle(a.from, now) &&
            a.managerStatus != LeaveApprovalStatus.denied)
        .length;
  }

  @Deprecated('Use permCountThisCycle — the cycle runs 26th to 25th')
  static int permCountThisMonth(String employeeName) => permCountThisCycle(employeeName);

  /// Staff Portal holiday allowance: 1 per calendar month, fixed (no
  /// HR-configurable "days / year" allocation like regular employees, and
  /// unused days don't carry over) — a fresh count each month. Staff still
  /// pick which of these two it's for (shown to HR), but both draw from the
  /// same single monthly slot — there's no separate CL/ML bucket for staff.
  static const int staffCycleHolidayAllowance = 1;

  @Deprecated('Use staffCycleHolidayAllowance — resets per 26th-to-25th cycle')
  static const int staffMonthlyHolidayAllowance = staffCycleHolidayAllowance;
  static const staffLeaveTypes = ['Casual Leave', 'Medical Leave'];

  /// True for staff-portal leave applications — the plain 'Leave' label from
  /// before staff had a type picker, plus the current Casual/Medical labels.
  static bool isStaffLeaveType(String leaveType) =>
      leaveType == 'Leave' || staffLeaveTypes.contains(leaveType);

  static int staffLeaveCountThisCycle(String employeeName) {
    final now = DateTime.now();
    return applications
        .where((a) =>
            isStaffLeaveType(a.leaveType) &&
            a.employeeName == employeeName &&
            sameAttendanceCycle(a.from, now) &&
            a.managerStatus != LeaveApprovalStatus.denied)
        .length;
  }

  @Deprecated('Use staffLeaveCountThisCycle — the cycle runs 26th to 25th')
  static int staffLeaveCountThisMonth(String employeeName) =>
      staffLeaveCountThisCycle(employeeName);
}
