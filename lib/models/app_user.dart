import 'user_session.dart';

class AppUser {
  String name;
  String email;
  String employeeId;
  String designation;
  String department;
  // 'FOMRA Developers' | 'FOMRA Housing'; '' = not yet set. HR sets it once
  // directly; once set, HR can only request a change — Management
  // approves/denies it (see businessUnitPending), same pattern as workLocation.
  String businessUnit;
  String businessUnitPending;      // proposed new value awaiting Management approval; empty = none
  String businessUnitRequestedAt;  // ISO datetime the change was requested
  // Weekly off day: '' = Sunday (default, everyone). Sales department only —
  // HR can set 'Tuesday' or 'Wednesday' instead, since Sales works Sundays.
  // HR sets the first value directly; once set, changing it requires
  // Management approval (see weeklyOffDayPending), same pattern as workLocation.
  String weeklyOffDay;
  String weeklyOffDayPending;      // proposed new value awaiting Management approval; empty = none
  String weeklyOffDayRequestedAt;  // ISO datetime the change was requested; empty = no pending request
  String role; // 'Employee' | 'Manager' | 'HR' | 'Management'
  bool active;
  // Whether a password has been set (bcrypt-hashed server-side). The hash
  // itself is never fetched to the client — only this derived flag, via the
  // has_password generated column. See supabase/functions/login/index.ts.
  bool hasPassword;
  int leaveAllocation;        // total leave days per year, set by HR
  String reportingManager;    // name of the manager this employee reports to
  String reportingManagerPending;      // proposed new manager name awaiting Management approval; '' = none
  String reportingManagerRequestedAt;  // ISO datetime the change was requested; empty = no pending request
  bool   isReportingManager;           // eligible to be selected as someone's RM
  bool   isReportingManagerPending;    // proposed new flag value awaiting Management approval
  String isReportingManagerRequestedAt; // ISO datetime the change was requested; empty = no pending request
  String mobile;
  String address;
  String dateOfBirth;         // ISO date string; usually carried over from the onboarding form
  String dateOfJoining;       // ISO date string, set when management creates the user
  String onrollConfirmedAt;   // ISO datetime when Management approved on-roll; empty = probation
  String onrollRequestedAt;   // ISO datetime when employee requested on-roll confirmation; empty = no pending request
  // On-roll 3-stage review: HR and Reporting Manager decide independently, then Management.
  String onrollHrStatus;           // 'pending' | 'accepted' | 'denied'
  String onrollHrComment;
  String onrollHrDecidedAt;
  String onrollManagerStatus;      // 'pending' | 'accepted' | 'denied'
  String onrollManagerComment;
  String onrollManagerDecidedAt;
  String onrollManagementStatus;   // 'pending' | 'accepted' | 'denied'
  String onrollManagementComment;
  String onrollManagementDecidedAt;
  String elEligibleAt;        // ISO datetime when HR confirmed EL eligibility; empty = not eligible
  String elAvailRequestedAt; // ISO datetime when employee requested EL avail; empty = no pending request
  String elLastAvailedAt;    // ISO datetime when HR confirmed EL avail; empty = never availed
  double grossPay;           // monthly gross pay (Rs); HR sets it once, then changes go through Management
  double grossPayPending;    // proposed new value awaiting Management approval; 0 = none
  String grossPayRequestedAt; // ISO datetime the change was requested; empty = no pending request
  // Work location: 'Office' | 'Onsite'; empty = not yet set. Once set, HR can only
  // request a change — Management approves/denies it (see workLocationPending).
  // Purely an employment attribute now (dashboard breakdowns, records badges) —
  // every employee checks in/out via the app regardless of this value.
  String workLocation;
  String workLocationPending;      // proposed new value awaiting Management approval; empty = none
  String workLocationRequestedAt;  // ISO datetime the change was requested
  // Monthly "Permission" (late-arrival/early-departure) allowance in minutes;
  // 120 (2 hours) is the standard policy default. HR can only request a
  // change — Management approves/denies it — same pattern as workLocation.
  int permissionMinutesQuota;
  int permissionMinutesQuotaPending;      // proposed new value awaiting Management approval; 0 = none
  String permissionMinutesQuotaRequestedAt; // ISO datetime the change was requested
  // Company-issued Microsoft/Office 365 mailbox; '' = HR hasn't entered it
  // yet. This is where "Forgot Password" reset links are sent — never the
  // personal email, and never the @fomrahousing.in login username itself.
  String companyEmail;

  // The login credential itself. HR requests a change — Management approves
  // or denies it — same pattern as workLocation. Enforced in the database by
  // trg_protect_login_email (see
  // supabase/migrations/20260731000200_email_change_requires_approval.sql),
  // NOT just here: unlike the other Chain C fields, a direct write to `email`
  // raises rather than being silently pinned.
  // ── Rule applicability, set per employee ──────────────────────────────────
  // Separate from ROLE, which grants authority. The CEO is exempt from all of
  // these; a Head of Operations at Management level has leave and salary
  // applied and is exempt only from timing and geofencing.
  bool exemptFromTiming;       // never assessed for lateness or early departure
  bool exemptFromGeofence;
  /// Device cannot capture a selfie; check-in proceeds without one.
  bool exemptFromSelfie;     // check-in never assessed against an office radius
  bool exemptFromLeaveRules;   // no probation cap, no permission quota/durations
  bool exemptFromAttendance;   // excluded from attendance entirely, incl. reports
  bool payrollEligible;        // appears in payroll runs
  bool oversightOnly;          // full admin rights, but no personal HR record

  String emailPending;             // proposed new address awaiting Management approval; empty = none
  String emailRequestedAt;         // ISO datetime the change was requested

  AppUser({
    required this.name,
    required this.email,
    required this.employeeId,
    required this.designation,
    this.department = '',
    this.businessUnit = '',
    this.businessUnitPending = '',
    this.businessUnitRequestedAt = '',
    this.weeklyOffDay = '',
    this.weeklyOffDayPending = '',
    this.weeklyOffDayRequestedAt = '',
    required this.role,
    this.active = true,
    this.hasPassword = false,
    this.leaveAllocation = 21,
    this.reportingManager = '',
    this.reportingManagerPending = '',
    this.reportingManagerRequestedAt = '',
    this.isReportingManager = false,
    this.isReportingManagerPending = false,
    this.isReportingManagerRequestedAt = '',
    this.mobile = '',
    this.address = '',
    this.dateOfBirth = '',
    this.dateOfJoining = '',
    this.onrollConfirmedAt = '',
    this.onrollRequestedAt = '',
    this.onrollHrStatus = 'pending',
    this.onrollHrComment = '',
    this.onrollHrDecidedAt = '',
    this.onrollManagerStatus = 'pending',
    this.onrollManagerComment = '',
    this.onrollManagerDecidedAt = '',
    this.onrollManagementStatus = 'pending',
    this.onrollManagementComment = '',
    this.onrollManagementDecidedAt = '',
    this.elEligibleAt = '',
    this.elAvailRequestedAt = '',
    this.elLastAvailedAt = '',
    this.grossPay = 0,
    this.grossPayPending = 0,
    this.grossPayRequestedAt = '',
    this.workLocation = '',
    this.workLocationPending = '',
    this.workLocationRequestedAt = '',
    this.permissionMinutesQuota = 120,
    this.permissionMinutesQuotaPending = 0,
    this.permissionMinutesQuotaRequestedAt = '',
    this.companyEmail = '',
    this.exemptFromTiming = false,
    this.exemptFromGeofence = false,
    this.exemptFromSelfie = false,
    this.exemptFromLeaveRules = false,
    this.exemptFromAttendance = false,
    this.payrollEligible = true,
    this.oversightOnly = false,
    this.emailPending = '',
    this.emailRequestedAt = '',
  });

  /// Management-tier AUTHORITY — can approve at the final stage. Covers both
  /// 'Management' and 'CEO'.
  ///
  /// Authority and rule-applicability are deliberately separate. They used to
  /// be one thing, which could not express the two real cases:
  ///   CEO                — full authority, outside attendance, leave and payroll
  ///   Head of Operations — full authority, but leave and salary DO apply;
  ///                        only timing and geofencing do not
  /// Applicability lives in the exempt* flags below, set per employee.
  bool get isManagement => const ['management', 'ceo'].contains(role.trim().toLowerCase());

  bool get isCeo => role.trim().toLowerCase() == 'ceo';

  /// Whether this person is an EMPLOYEE for counting and reporting purposes.
  ///
  /// The founder is not. He has no joining date, no attendance, no payroll and
  /// no leave entitlement, and including him in a headcount makes every
  /// percentage wrong — "5 of 6 present" against a denominator containing
  /// someone who can never check in.
  ///
  /// Deliberately NOT the same as being hidden. He remains selectable as a
  /// reporting manager and as an approver, because he approves the Head of
  /// Operations' leave. This governs counting and reports only.
  bool get countsInHeadcount => !oversightOnly;

  /// Confirmed off probation. Anyone exempt from the leave rules is treated as
  /// confirmed, because probation does not apply to them.
  bool get isOnroll    => exemptFromLeaveRules || onrollConfirmedAt.isNotEmpty;
  // EL accrues only after confirmation; el_eligible_at is cleared while on
  // probation and set from the joining date when Management confirms.
  bool get isElEligible => elEligibleAt.isNotEmpty && isOnroll;
  bool get hasPendingWorkLocationChange => workLocationPending.isNotEmpty;
  bool get hasPendingEmailChange => emailPending.isNotEmpty;
  bool get hasPendingBusinessUnitChange => businessUnitPending.isNotEmpty;
  bool get hasPendingWeeklyOffChange => weeklyOffDayRequestedAt.isNotEmpty;
  /// The weekday this employee is off every week; defaults to Sunday.
  String get effectiveWeeklyOffDay => weeklyOffDay.isEmpty ? 'Sunday' : weeklyOffDay;
  bool get hasPendingGrossPayChange => grossPayRequestedAt.isNotEmpty;
  bool get hasPendingPermissionQuotaChange => permissionMinutesQuotaRequestedAt.isNotEmpty;
  bool get hasPendingReportingManagerChange => reportingManagerRequestedAt.isNotEmpty;
  bool get hasPendingRmFlagChange => isReportingManagerRequestedAt.isNotEmpty;

  // On-roll 3-stage review helpers
  bool get onrollHrAccepted       => onrollHrStatus == 'accepted';
  bool get onrollHrDenied         => onrollHrStatus == 'denied';
  bool get onrollManagerAccepted  => onrollManagerStatus == 'accepted';
  bool get onrollManagerDenied    => onrollManagerStatus == 'denied';
  bool get onrollManagementDenied => onrollManagementStatus == 'denied';

  /// True once both HR and Manager have accepted and Management hasn't decided yet.
  bool get onrollAwaitingManagement =>
      onrollRequestedAt.isNotEmpty && onrollHrAccepted && onrollManagerAccepted &&
      onrollManagementStatus == 'pending';

  /// True if the request is currently denied by any stage.
  bool get onrollDenied => onrollHrDenied || onrollManagerDenied || onrollManagementDenied;

  /// Which party issued the denial: 'HR' | 'Manager' | 'Management' | ''.
  String get onrollDeniedBy {
    if (onrollHrDenied) return 'HR';
    if (onrollManagerDenied) return 'Manager';
    if (onrollManagementDenied) return 'Management';
    return '';
  }

  /// The comment attached to whichever stage denied it; '' if none.
  String get onrollDeniedComment {
    if (onrollHrDenied) return onrollHrComment;
    if (onrollManagerDenied) return onrollManagerComment;
    if (onrollManagementDenied) return onrollManagementComment;
    return '';
  }

  /// ISO timestamp of whichever stage denied it; drives the 7-day resubmit cooldown.
  String get onrollDeniedAt {
    if (onrollHrDenied) return onrollHrDecidedAt;
    if (onrollManagerDenied) return onrollManagerDecidedAt;
    if (onrollManagementDenied) return onrollManagementDecidedAt;
    return '';
  }

  /// True once 7 days have passed since the denial, i.e. the employee may resubmit.
  bool get onrollCanResubmit {
    if (!onrollDenied) return false;
    final ts = onrollDeniedAt;
    if (ts.isEmpty) return true;
    try {
      return DateTime.now().difference(DateTime.parse(ts)) >= const Duration(days: 7);
    } catch (_) {
      return true;
    }
  }

  /// Overall stage, used to drive UI without duplicating conditionals across pages.
  /// 'not_requested' | 'pending_both' | 'pending_hr' | 'pending_manager' |
  /// 'awaiting_management' | 'denied' | 'confirmed'
  String get onrollStage {
    if (isOnroll) return 'confirmed';
    if (onrollDenied) return 'denied';
    if (onrollRequestedAt.isEmpty) return 'not_requested';
    if (onrollAwaitingManagement) return 'awaiting_management';
    final hrDone = onrollHrStatus != 'pending';
    final mgrDone = onrollManagerStatus != 'pending';
    if (hrDone && !mgrDone) return 'pending_manager';
    if (!hrDone && mgrDone) return 'pending_hr';
    return 'pending_both';
  }

  // Leave entitlement per ATTENDANCE CYCLE (26th -> 25th).
  //
  // CL, ML, EL and every other leave type are for CONFIRMED employees only.
  // While on probation an employee gets ONE leave per cycle, of any type, and
  // no permission at all.
  int get monthlyCl => exemptFromLeaveRules ? 9999 : (isOnroll ? 1 : 0);
  int get monthlyMl => exemptFromLeaveRules ? 9999 : (isOnroll ? 1 : 0);
  int get monthlyEl => exemptFromLeaveRules ? 9999 : ((isOnroll && isElEligible) ? 1 : 0);

  /// Total leaves allowed per cycle while on probation, any type.
  static const probationLeavesPerCycle = 1;

  /// Permission is a confirmed-employee benefit. Enforced in the database by
  /// enforce_probation_leave_rules(); mirrored here so the UI can disable the
  /// button rather than let someone fill in a form that will be rejected.
  bool get canApplyForPermission => exemptFromLeaveRules || isOnroll;

  /// Leaves this employee may take in a cycle, before type-specific limits.
  int get leavesPerCycle => isOnroll ? monthlyCl + monthlyMl + monthlyEl : probationLeavesPerCycle;

  String get leaveStatus {
    if (exemptFromLeaveRules) return isCeo ? 'CEO' : 'Exempt';
    if (isElEligible) return 'EL Eligible';
    if (isOnroll)     return 'On-Roll';
    return 'Probation';
  }

  /// Plain-English summary of what this employee is entitled to, for the
  /// leave screens — so probation staff understand the limit up front rather
  /// than discovering it when a request is refused.
  String get entitlementSummary => exemptFromLeaveRules
      ? '${isCeo ? 'CEO' : 'Exempt'} — not subject to the leave cycle or permission limits'
      : isOnroll
          ? 'Confirmed — full leave entitlement and 120 minutes of permission per cycle'
          : 'On probation — one leave per cycle, and permission is not available until confirmation';

  static UserRole userRoleFor(String role) {
    final normalized = role.trim().toLowerCase();
    switch (normalized) {
      case 'hr':
        return UserRole.hr;
      case 'manager':
        return UserRole.reportingManager;
      case 'management':
      // The CEO carries the same authority as Management. Kept as a distinct
      // role string so exemptions can differ (see the exempt* flags): the CEO
      // is outside attendance, leave and payroll, whereas a Head of
      // Operations at Management level has leave and salary applied and is
      // exempt only from timing and geofencing.
      case 'ceo':
        return UserRole.management;
      default:
        return UserRole.employee;
    }
  }

  Map<String, dynamic> toJson() => {
    'name':                  name,
    'email':                 email,
    'employeeId':            employeeId,
    'designation':           designation,
    'department':            department,
    'businessUnit':          businessUnit,
    'businessUnitPending':   businessUnitPending,
    'businessUnitRequestedAt': businessUnitRequestedAt,
    'weeklyOffDay':          weeklyOffDay,
    'weeklyOffDayPending':   weeklyOffDayPending,
    'weeklyOffDayRequestedAt': weeklyOffDayRequestedAt,
    'role':                  role,
    'active':                active,
    'hasPassword':           hasPassword,
    'leaveAllocation':       leaveAllocation,
    'reportingManager':      reportingManager,
    'reportingManagerPending':     reportingManagerPending,
    'reportingManagerRequestedAt': reportingManagerRequestedAt,
    'isReportingManager':          isReportingManager,
    'isReportingManagerPending':   isReportingManagerPending,
    'isReportingManagerRequestedAt': isReportingManagerRequestedAt,
    'mobile':                mobile,
    'address':               address,
    'dateOfBirth':           dateOfBirth,
    'dateOfJoining':         dateOfJoining,
    'onrollConfirmedAt':     onrollConfirmedAt,
    'onrollRequestedAt':     onrollRequestedAt,
    'onrollHrStatus':            onrollHrStatus,
    'onrollHrComment':           onrollHrComment,
    'onrollHrDecidedAt':         onrollHrDecidedAt,
    'onrollManagerStatus':       onrollManagerStatus,
    'onrollManagerComment':      onrollManagerComment,
    'onrollManagerDecidedAt':    onrollManagerDecidedAt,
    'onrollManagementStatus':    onrollManagementStatus,
    'onrollManagementComment':   onrollManagementComment,
    'onrollManagementDecidedAt': onrollManagementDecidedAt,
    'elEligibleAt':          elEligibleAt,
    'elAvailRequestedAt':    elAvailRequestedAt,
    'elLastAvailedAt':       elLastAvailedAt,
    'grossPay':              grossPay,
    'grossPayPending':       grossPayPending,
    'grossPayRequestedAt':   grossPayRequestedAt,
    'workLocation':          workLocation,
    'workLocationPending':   workLocationPending,
    'workLocationRequestedAt': workLocationRequestedAt,
    'permissionMinutesQuota':          permissionMinutesQuota,
    'permissionMinutesQuotaPending':   permissionMinutesQuotaPending,
    'permissionMinutesQuotaRequestedAt': permissionMinutesQuotaRequestedAt,
    'companyEmail':          companyEmail,
    'exemptFromTiming':      exemptFromTiming,
    'exemptFromGeofence':    exemptFromGeofence,
    'exemptFromSelfie':      exemptFromSelfie,
    'exemptFromLeaveRules':  exemptFromLeaveRules,
    'exemptFromAttendance':  exemptFromAttendance,
    'payrollEligible':       payrollEligible,
    'oversightOnly':         oversightOnly,
    'emailPending':          emailPending,
    'emailRequestedAt':      emailRequestedAt,
  };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
    name:                 j['name']                 as String? ?? '',
    email:                j['email']                as String? ?? '',
    employeeId:           j['employeeId']           as String? ?? '',
    designation:          j['designation']          as String? ?? '',
    department:           j['department']           as String? ?? '',
    businessUnit:         j['businessUnit']         as String? ?? '',
    businessUnitPending:      j['businessUnitPending']      as String? ?? '',
    businessUnitRequestedAt:  j['businessUnitRequestedAt']  as String? ?? '',
    weeklyOffDay:             j['weeklyOffDay']             as String? ?? '',
    weeklyOffDayPending:      j['weeklyOffDayPending']      as String? ?? '',
    weeklyOffDayRequestedAt:  j['weeklyOffDayRequestedAt']  as String? ?? '',
    role:                 j['role']                 as String? ?? 'Employee',
    active:               j['active']               as bool?   ?? true,
    hasPassword:          j['hasPassword']          as bool?   ?? false,
    leaveAllocation:      j['leaveAllocation']      as int?    ?? 21,
    reportingManager:     j['reportingManager']     as String? ?? '',
    reportingManagerPending:     j['reportingManagerPending']     as String? ?? '',
    reportingManagerRequestedAt: j['reportingManagerRequestedAt'] as String? ?? '',
    isReportingManager:            j['isReportingManager']            as bool?   ?? false,
    isReportingManagerPending:     j['isReportingManagerPending']     as bool?   ?? false,
    isReportingManagerRequestedAt: j['isReportingManagerRequestedAt'] as String? ?? '',
    mobile:               j['mobile']               as String? ?? '',
    address:              j['address']              as String? ?? '',
    dateOfBirth:          j['dateOfBirth']          as String? ?? '',
    dateOfJoining:        j['dateOfJoining']        as String? ?? '',
    onrollConfirmedAt:    j['onrollConfirmedAt']    as String? ?? '',
    onrollRequestedAt:    j['onrollRequestedAt']    as String? ?? '',
    onrollHrStatus:            j['onrollHrStatus']            as String? ?? 'pending',
    onrollHrComment:           j['onrollHrComment']           as String? ?? '',
    onrollHrDecidedAt:         j['onrollHrDecidedAt']         as String? ?? '',
    onrollManagerStatus:       j['onrollManagerStatus']       as String? ?? 'pending',
    onrollManagerComment:      j['onrollManagerComment']      as String? ?? '',
    onrollManagerDecidedAt:    j['onrollManagerDecidedAt']    as String? ?? '',
    onrollManagementStatus:    j['onrollManagementStatus']    as String? ?? 'pending',
    onrollManagementComment:   j['onrollManagementComment']   as String? ?? '',
    onrollManagementDecidedAt: j['onrollManagementDecidedAt'] as String? ?? '',
    elEligibleAt:         j['elEligibleAt']         as String? ?? '',
    elAvailRequestedAt:   j['elAvailRequestedAt']   as String? ?? '',
    elLastAvailedAt:      j['elLastAvailedAt']       as String? ?? '',
    grossPay:             (j['grossPay'] as num?)?.toDouble() ?? 0,
    grossPayPending:      (j['grossPayPending'] as num?)?.toDouble() ?? 0,
    grossPayRequestedAt:  j['grossPayRequestedAt'] as String? ?? '',
    workLocation:            j['workLocation']            as String? ?? '',
    workLocationPending:     j['workLocationPending']     as String? ?? '',
    workLocationRequestedAt: j['workLocationRequestedAt'] as String? ?? '',
    permissionMinutesQuota:          (j['permissionMinutesQuota'] as num?)?.toInt() ?? 120,
    permissionMinutesQuotaPending:   (j['permissionMinutesQuotaPending'] as num?)?.toInt() ?? 0,
    permissionMinutesQuotaRequestedAt: j['permissionMinutesQuotaRequestedAt'] as String? ?? '',
    companyEmail:           j['companyEmail']          as String? ?? '',
    exemptFromTiming:       j['exemptFromTiming']      as bool? ?? false,
    exemptFromGeofence:     j['exemptFromGeofence']    as bool? ?? false,
    exemptFromSelfie:       j['exemptFromSelfie']      as bool? ?? false,
    exemptFromLeaveRules:   j['exemptFromLeaveRules']  as bool? ?? false,
    exemptFromAttendance:   j['exemptFromAttendance']  as bool? ?? false,
    payrollEligible:        j['payrollEligible']       as bool? ?? true,
    oversightOnly:          j['oversightOnly']         as bool? ?? false,
    emailPending:           j['emailPending']          as String? ?? '',
    emailRequestedAt:       j['emailRequestedAt']      as String? ?? '',
  );
}
