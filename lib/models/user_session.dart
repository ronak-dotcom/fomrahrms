import 'package:flutter/foundation.dart';
import '../constants/org_lists.dart';

enum UserRole { hr, employee, reportingManager, management }

class UserSession {
  static bool     loggedIn        = false;
  static UserRole role            = UserRole.hr;
  static String   name            = '';
  static String   employeeId      = '';
  static String   email           = '';
  static String   designation     = '';
  static String   department      = '';
  static String   reportingManager= '';
  static bool     isReportingManager = false;
  static String   workLocation    = ''; // 'Office' | 'Onsite' | ''
  static int      permissionMinutesQuota = 120; // Permission allowance per attendance cycle

  /// True once Management has confirmed employment (onroll_confirmed_at set).
  /// While false the employee is on probation: ONE leave per attendance cycle
  /// of any type, and no permission at all. Enforced authoritatively by
  /// enforce_probation_leave_rules() in the database; held here so the UI can
  /// explain the limit instead of letting a request be rejected.
  static bool     isOnroll        = false;

  /// Outside attendance entirely — no check-in, and excluded from attendance
  /// dashboards and reports. True for the CEO. Per-employee rather than
  /// per-role, so a Head of Operations at Management level is still tracked.
  static bool     exemptFromAttendance = false;

  /// No fixed working hours — never assessed for lateness or early departure.
  /// True for the CEO and the Head of Operations. Consulted by
  /// OfficeTimingStore.scheduleForCurrentUser(); without it an exempt user
  /// with no department falls through to the 09:30 default and is asked for a
  /// late reason.
  static bool     exemptFromTiming = false;

  /// Full administrative rights, but no personal HR record: no check-in/out,
  /// no own leave or permission, no payslips or personal tasks. Reports, data,
  /// analysis and configuration only. True for the CEO.
  ///
  /// Deliberately its own flag rather than inferred from the exemptions above —
  /// "exempt from attendance and leave and payroll" is true of the CEO today
  /// by coincidence of three unrelated settings, and a future auditor or
  /// consultant could match that pattern without being oversight-only.
  static bool     oversightOnly = false;

  /// Set by HR/Management when the employee's device genuinely cannot produce
  /// a selfie — a browser that refuses to open the camera, for instance. The
  /// selfie is otherwise mandatory and blocks check-in outright, which left
  /// one employee unable to record attendance at all for over a week. GPS and
  /// timing rules still apply; only the photo is waived.
  static bool     exemptFromSelfie = false;

  /// Management is an oversight role, exempt from the leave cycle, permission
  /// limits, fixed timings and payroll. Derived from [role].
  static bool get isManagement => role == UserRole.management;

  /// Not subject to probation limits: confirmed employees, and Management.
  static bool get hasFullLeaveEntitlement => isManagement || isOnroll;

  /// Housekeeping/Support Staff employees use a separate, simplified
  /// "Staff Portal" shell instead of the regular employee shell — same
  /// UserRole.employee, just routed differently. See lib/app.dart's guard.
  static bool get isStaffPortal =>
      role == UserRole.employee && kStaffPortalDepartments.contains(department);

  // Backed by a ValueNotifier so widgets built before the background photo
  // fetch (e.g. after a page refresh) can still update once the URL arrives.
  static final ValueNotifier<String> photoUrlNotifier = ValueNotifier<String>('');
  static String get photoUrl => photoUrlNotifier.value;
  static set photoUrl(String value) => photoUrlNotifier.value = value;

  static String get profileRoute {
    switch (role) {
      case UserRole.hr:               return '/hr/my-profile';
      case UserRole.reportingManager: return '/manager/my-profile';
      case UserRole.management:       return '/management/my-profile';
      case UserRole.employee:         return '/employee/profile';
    }
  }

  static void clear() {
    loggedIn         = false;
    role             = UserRole.hr;
    name             = '';
    employeeId       = '';
    email            = '';
    designation      = '';
    department       = '';
    reportingManager = '';
    isReportingManager = false;
    workLocation     = '';
    permissionMinutesQuota = 120;
    photoUrl         = '';
    // Exemptions are per-person privileges. Left set, they would carry to
    // whoever logs in next on a shared device — someone else's phone, or a
    // site tablet — silently waiving a requirement for the wrong employee.
    exemptFromSelfie     = false;
    exemptFromAttendance = false;
    exemptFromTiming     = false;
    oversightOnly        = false;
  }
}
