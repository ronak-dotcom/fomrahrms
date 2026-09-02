import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'models/color_theme_notifier.dart';
import 'models/user_session.dart';
import 'models/task_store.dart';
import 'widgets/app_shell.dart';
import 'widgets/employee_shell.dart';
import 'widgets/notification_popup_overlay.dart';
import 'pages/login_page.dart';
import 'pages/location_history_page.dart';
import 'pages/settings_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/summary_detail_page.dart';
import 'pages/add_employee_page.dart';
import 'pages/check_in_page.dart';
import 'pages/check_out_page.dart';
import 'pages/gps_tracking_page.dart';
import 'pages/late_coming_page.dart';
import 'pages/leave_management_page.dart';
import 'pages/management_leave_page.dart';
import 'pages/apply_leave_page.dart';
import 'pages/apply_permission_page.dart';
import 'pages/apply_comp_off_page.dart';
import 'pages/apply_on_duty_page.dart';
import 'pages/leave_approvals_page.dart';
import 'pages/leave_balance_page.dart';
import 'pages/task_management_page.dart';
import 'pages/add_task_page.dart';
import 'pages/performance_management_page.dart';
import 'pages/employee_appraisal_page.dart';
import 'pages/appraisal_form_editor_page.dart';
import 'pages/employee_appraisal_request_page.dart';
import 'pages/hr_appraisals_page.dart';
import 'pages/management_appraisals_page.dart';
import 'pages/appraisal_received_page.dart';
import 'pages/kra_management_page.dart';
import 'pages/employee_kra_page.dart';
import 'pages/my_kra_page.dart';
import 'pages/kra_approvals_page.dart';
import 'pages/salary_hike_engine_page.dart';
import 'models/app_user.dart';
import 'models/appraisal_store.dart';
import 'pages/payroll_management_page.dart';
import 'pages/interview_process_page.dart';
import 'pages/candidate_application_form_page.dart';
import 'pages/employee_onboarding_page.dart';
import 'pages/onboarding_form_page.dart';
import 'pages/pre_offer_accept_page.dart';
import 'pages/set_password_page.dart';
import 'pages/reset_password_page.dart';
import 'pages/email_logs_page.dart';
import 'pages/lead_management_hub_page.dart';
import 'pages/lead_management_page.dart';
import 'pages/maintenance_management_page.dart';
import 'pages/approvals_page.dart';
import 'pages/notifications_page.dart';
import 'pages/reports_analytics_page.dart';
import 'pages/administration_page.dart';
import 'pages/employee_dashboard_page.dart';
import 'pages/my_attendance_page.dart';
import 'pages/my_attendance_and_leave_page.dart';
import 'pages/my_tasks_page.dart';
import 'pages/my_payslips_page.dart';
import 'pages/my_profile_page.dart';
import 'pages/employee_attendance_page.dart';
import 'pages/hr_attendance_records_page.dart';
import 'pages/hr_attendance_detail_page.dart';
import 'pages/hr_employee_records_page.dart';
import 'pages/reporting_managers_page.dart';
import 'pages/employee_leave_page.dart';
import 'pages/my_leave_approvals_page.dart';
import 'pages/my_leave_balance_page.dart';
import 'pages/hr_leave_records_page.dart';
import 'widgets/manager_shell.dart';
import 'pages/manager_dashboard_page.dart';
import 'pages/manager_leave_page.dart';
import 'pages/team_leave_approvals_page.dart';
import 'widgets/management_shell.dart';
import 'pages/management_dashboard_page.dart';
import 'pages/onroll_approvals_page.dart';
import 'pages/my_onboarding_form_page.dart';
import 'pages/candidate_detail_page.dart';
import 'pages/manager_interview_review_page.dart';
import 'pages/management_interview_review_page.dart';
import 'pages/edit_form_page.dart';
import 'pages/edit_leave_form_page.dart';
import 'pages/edit_onboarding_form_page.dart';
import 'pages/edit_maintenance_form_page.dart';
import 'pages/location_management_page.dart';
import 'pages/form_approvals_page.dart';
import 'pages/my_journey_page.dart';
import 'pages/employee_attendance_calendar_page.dart';
import 'widgets/staff_shell.dart';
import 'pages/staff/staff_home_page.dart';
import 'pages/staff/staff_leave_page.dart';
import 'pages/staff/staff_permission_page.dart';
import 'pages/staff/staff_profile_page.dart';
import 'constants/org_lists.dart';

/// Personal, self-service pages — the things an employee does about their own
/// employment, as opposed to overseeing everyone else's.
///
/// Deliberately a suffix match on the segment after the role prefix, so it
/// applies whichever shell the path sits in and a new role shell inherits it.
/// `/management/leave-management` and `/management/attendance-management` are
/// NOT here: those are the oversight screens the CEO should keep.
bool _isSelfServicePath(String path) {
  const selfService = <String>[
    '/attendance/check-in',
    '/attendance/check-out',
    '/attendance/check-in-out',
    '/my-attendance',
    '/attendance-leaves',
    '/my-leave',
    '/leave/apply',
    '/leave/permission',
    '/leave/compoff',
    '/leave/balance',
    '/my-payslips',
    '/my-tasks',
    '/my-maintenance',
    '/my-details',
  ];
  for (final s in selfService) {
    if (path.endsWith(s)) return true;
  }
  return false;
}

String? _guard(GoRouterState state) {
  final path = state.uri.path;
  if (path == '/login') return null;
  if (path == '/candidate-application') return null; // public form
  if (path == '/candidate-detail') return null;       // accessed from within shells
  if (path == '/onboarding-form') return null;        // public joining form
  if (path.startsWith('/onboarding-form/')) return null; // tokenized joining form
  if (path.startsWith('/pre-offer/')) return null;       // public offer-accept page
  if (path.startsWith('/set-password/')) return null;    // public account activation
  if (path.startsWith('/reset-password/')) return null;  // public forgot-password reset

  if (!UserSession.loggedIn) return '/login';

  final role = UserSession.role;
  final isStaff = UserSession.isStaffPortal;
  String home() => switch (role) {
        UserRole.hr => '/dashboard',
        UserRole.employee => isStaff ? '/staff/home' : '/employee/dashboard',
        UserRole.management => '/management/dashboard',
        UserRole.reportingManager => '/manager/dashboard',
      };

  // Root path: send to the role's home
  if (path == '/' || path.isEmpty) return home();

  // Each role is confined to its own shell — no cross-role browsing.
  // Housekeeping/Support Staff (role == employee, isStaff == true) get the
  // simplified Staff Portal shell instead of the regular employee shell.
  if (path.startsWith('/management/') && role != UserRole.management) return home();

  // Oversight-only users (the CEO) hold every administrative right but have no
  // personal HR record: no check-in/out, no leave or permission of their own,
  // no payslips or personal tasks. Reports, data, analysis and configuration
  // only. Enforced here rather than only by hiding tiles, so a bookmarked or
  // hand-typed URL cannot reach a page that would create a personal record the
  // rest of the system deliberately excludes them from.
  if (UserSession.oversightOnly && _isSelfServicePath(path)) return home();
  if (path.startsWith('/staff/') && !isStaff) return home();
  if (path.startsWith('/employee/') && (role != UserRole.employee || isStaff)) return home();
  if (path.startsWith('/manager/') && role != UserRole.reportingManager) return home();
  if (!path.startsWith('/employee/') && !path.startsWith('/manager/') &&
      !path.startsWith('/management/') && !path.startsWith('/hr/') && !path.startsWith('/staff/') &&
      role != UserRole.hr) {
    return home();
  }

  return null;
}

final _router = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/login',
  redirect: (_, state) => _guard(state),
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: AppTheme.primaryBlue),
        const SizedBox(height: 16),
        const Text('Page not found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => context.go('/login'),
          child: const Text('Go to Login'),
        ),
      ]),
    ),
  ),
  routes: [
    // ── Public routes (no login required) ─────────────────────────────────
    GoRoute(
      path: '/login',
      builder: (_, state) => LoginPage(flashMessage: state.extra as String?),
    ),
    GoRoute(
      path: '/candidate-application',
      builder: (_, state) => CandidateApplicationFormPage(
        version: state.uri.queryParameters['v'],
      ),
    ),
    GoRoute(path: '/onboarding-form', builder: (_, __) => const OnboardingFormPage()),
    GoRoute(
      path: '/onboarding-form/:token',
      builder: (_, state) => OnboardingFormPage(token: state.pathParameters['token']),
    ),
    GoRoute(
      path: '/pre-offer/:token',
      builder: (_, state) => PreOfferAcceptPage(token: state.pathParameters['token']!),
    ),
    GoRoute(
      path: '/set-password/:token',
      builder: (_, state) => SetPasswordPage(token: state.pathParameters['token']!),
    ),
    GoRoute(
      path: '/reset-password/:token',
      builder: (_, state) => ResetPasswordPage(token: state.pathParameters['token']!),
    ),

    // ── HR Shell ───────────────────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(child: child, location: state.uri.path),
      routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => const DashboardPage()),
        GoRoute(
          path: '/summary/:sectionId',
          builder: (_, state) => SummaryDetailPage(
            sectionId: state.pathParameters['sectionId'] ?? '',
          ),
        ),
        GoRoute(path: '/employee-management',             builder: (_, __) => const HrEmployeeRecordsPage()),
        GoRoute(path: '/employee-management/add',         builder: (_, __) => const AddEmployeePage()),
        // EmployeeProfilePage is an empty form template that takes no
        // employee — it renders blank fields for whoever opens it. Nothing
        // links here any more (employee_management_page.dart, which did, is
        // unreachable dead code), but the route was still typeable and led to
        // a page that looked broken. Send it to the real records list, where
        // an employee can be picked and their actual profile opened.
        GoRoute(path: '/employee-management/profile',     redirect: (_, __) => '/employee-management'),
        GoRoute(path: '/attendance-management',           builder: (_, __) => const HrAttendanceRecordsPage(routePrefix: '')),
        GoRoute(path: '/attendance/employee-attendance-calendar', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EmployeeAttendanceCalendarPage(
            employeeId:   extra['employeeId']   as String,
            employeeName: extra['employeeName'] as String,
          );
        }),
        GoRoute(path: '/attendance/check-in',             builder: (_, __) => const CheckInPage()),
        GoRoute(path: '/attendance/check-out',            builder: (_, __) => const CheckOutPage()),
        GoRoute(path: '/attendance/gps-tracking',         builder: (_, __) => const GpsTrackingPage()),
        GoRoute(path: '/attendance/late-coming',           builder: (_, __) => const LateComingPage()),
        GoRoute(path: '/attendance/employee-records', builder: (_, __) => const HrAttendanceRecordsPage(routePrefix: '')),
        GoRoute(path: '/attendance/hr/check-in',      builder: (_, __) => HrAttendanceDetailPage(
          title: 'Check In', icon: Icons.login_rounded, color: AppTheme.primaryBlue,
          columns: ['Employee', 'Date', 'Check-In Time', 'GPS Location', 'Status'],
        )),
        GoRoute(path: '/attendance/hr/check-out',     builder: (_, __) => HrAttendanceDetailPage(
          title: 'Check Out', icon: Icons.logout_rounded, color: AppTheme.accentBlue,
          columns: ['Employee', 'Date', 'Check-Out Time', 'GPS Location', 'Status'],
        )),
        GoRoute(path: '/attendance/hr/gps-tracking',  builder: (_, __) => HrAttendanceDetailPage(
          title: 'GPS Tracking', icon: Icons.location_on_rounded, color: AppTheme.accentBlue,
          columns: ['Employee', 'Date', 'Last Location', 'Route Points', 'Time'],
        )),
        GoRoute(path: '/attendance/hr/late-coming',   builder: (_, __) => const HrAttendanceDetailPage(
          title: 'Late Coming', icon: Icons.watch_later_rounded, color: Color(0xFF111827),
          columns: ['Employee', 'Date', 'Arrival Time', 'Late By', 'Deduction'],
        )),
        GoRoute(path: '/employee-management/records', builder: (_, __) => const HrEmployeeRecordsPage()),
        GoRoute(path: '/employee-management/reporting-managers', builder: (_, __) => const ReportingManagersPage()),
        GoRoute(path: '/kra-management',          builder: (_, __) => const KraManagementPage()),
        GoRoute(path: '/kra-management/employee', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EmployeeKraPage(employee: extra['employee'] as AppUser);
        }),
        GoRoute(path: '/leave-management',                builder: (_, __) {
          if (UserSession.role == UserRole.hr) return const HrLeaveRecordsPage();
          if (UserSession.role == UserRole.management) {
            return const TeamLeaveApprovalsPage(isManagement: true, showAll: true);
          }
          return const LeaveManagementPage();
        }),
        GoRoute(path: '/leave/apply',                     builder: (_, __) => const ApplyLeavePage()),
        GoRoute(path: '/leave/permission',                builder: (_, __) => const ApplyPermissionPage()),
        GoRoute(path: '/leave/compoff',                   builder: (_, __) => const ApplyCompOffPage()),
        GoRoute(path: '/leave/approvals',                 builder: (_, __) => const LeaveApprovalsPage()),
        GoRoute(path: '/leave/balance',                   builder: (_, __) => const LeaveBalancePage()),
        GoRoute(path: '/leave/employee-records',          builder: (_, __) => const HrLeaveRecordsPage()),
        GoRoute(path: '/leave/staff-portal-approvals',    builder: (_, __) => const TeamLeaveApprovalsPage(
          isManagement: true,
          onlyDepartments: kStaffPortalDepartments,
          title: 'Staff Portal Approvals',
          subtitle: 'Staff roster, and leave & permission requests, for Housekeeping / Support Staff',
        )),
        GoRoute(path: '/task-management',                 builder: (_, state) =>
            TaskManagementPage(initialStatus: taskStatusFromName(state.uri.queryParameters['status']))),
        GoRoute(path: '/task-management/add',             builder: (_, __) => const AddTaskPage()),
        GoRoute(path: '/performance-management',          builder: (_, __) => const PerformanceManagementPage()),
        GoRoute(path: '/performance-management/employee', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EmployeeAppraisalPage(
            employee: extra['employee'] as AppUser,
            allUsers: (extra['allUsers'] as List<AppUser>?) ?? const [],
          );
        }),
        GoRoute(path: '/performance-management/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(
            employee: extra['employee'] as AppUser,
            existing: extra['existing'] as AppraisalForm?,
            allUsers: (extra['allUsers'] as List<AppUser>?) ?? const [],
          );
        }),
        GoRoute(path: '/appraisals',                      builder: (_, __) => const HrAppraisalsPage()),
        GoRoute(path: '/appraisals/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(
            existing: extra['existing'] as AppraisalForm?,
            allUsers: (extra['allUsers'] as List<AppUser>?) ?? const [],
          );
        }),
        GoRoute(path: '/salary-hike-engine',              builder: (_, __) => const SalaryHikeEnginePage()),
        GoRoute(path: '/payroll-management',              builder: (_, __) => const PayrollManagementPage()),
        GoRoute(path: '/interview-process',               builder: (_, __) => const InterviewProcessPage()),
        GoRoute(path: '/email-logs',                      builder: (_, __) => const EmailLogsPage()),
        GoRoute(path: '/edit-form',                       builder: (_, __) => const EditFormPage()),
        GoRoute(path: '/edit-leave-form',                 builder: (_, __) => const EditLeaveFormPage()),
        GoRoute(path: '/edit-onboarding-form',            builder: (_, __) => const EditOnboardingFormPage()),
        GoRoute(path: '/edit-maintenance-form',           builder: (_, __) => const EditMaintenanceFormPage()),
        GoRoute(path: '/location-management',             builder: (_, __) => const LocationManagementPage()),
        GoRoute(path: '/candidate-detail',                builder: (_, __) => const CandidateDetailPage()),
        GoRoute(path: '/employee-onboarding',             builder: (_, __) => const EmployeeOnboardingPage()),
        GoRoute(path: '/lead-management',
            builder: (_, __) => const LeadManagementHubPage(basePath: '/lead-management')),
        GoRoute(path: '/lead-management/leads', builder: (_, s) {
          final x = s.extra as Map<String, String>? ?? {};
          return LeadManagementPage(url: x['url'] ?? '', name: x['name'] ?? 'Leads');
        }),
        GoRoute(path: '/maintenance-management',          builder: (_, __) => const MaintenanceManagementPage()),
        GoRoute(path: '/notifications',                   builder: (_, __) => const NotificationsPage()),
        GoRoute(path: '/reports-analytics',               builder: (_, __) => const ReportsAnalyticsPage()),
        // HR personal pages (My Space)
        GoRoute(path: '/hr/my-details',             builder: (_, __) => const MyProfilePage()),
        GoRoute(path: '/hr/my-attendance',            builder: (_, __) => const MyAttendancePage(checkInRoute: '/hr/attendance/check-in-out')),
        GoRoute(path: '/hr/attendance/check-in-out', builder: (_, __) => const EmployeeAttendancePage(prefix: '')),
        GoRoute(path: '/hr/my-leave',               builder: (_, __) => const EmployeeLeavePage(prefix: '')),
        GoRoute(path: '/hr/attendance-leaves',       builder: (_, __) => const MyAttendanceAndLeavePage(checkInRoute: '/hr/attendance/check-in-out', leavePrefix: '')),
        GoRoute(path: '/hr/my-tasks',               builder: (_, state) =>
            MyTasksPage(initialStatus: taskStatusFromName(state.uri.queryParameters['status']))),
        GoRoute(path: '/hr/my-payslips',            builder: (_, __) => const MyPayslipsPage()),
        GoRoute(path: '/hr/my-kra',                 builder: (_, __) => const MyKraPage()),
        GoRoute(path: '/hr/my-profile',             builder: (_, __) => const MyProfilePage()),
        GoRoute(path: '/hr/interview-form',         builder: (_, __) => const CandidateDetailPage()),
        GoRoute(path: '/hr/employee-onboarding',    builder: (_, __) => const MyOnboardingFormPage()),
        GoRoute(path: '/hr/maintenance-management', builder: (_, __) => const MaintenanceManagementPage(personalView: true)),
        // "My Team" — only shown/relevant when UserSession.isReportingManager (see app_shell.dart).
        GoRoute(path: '/hr/leave/team-approvals',   builder: (_, __) => const TeamLeaveApprovalsPage()),
        GoRoute(path: '/hr/interview-review',       builder: (_, __) => const ManagerInterviewReviewPage()),
        GoRoute(path: '/hr/appraisal',               builder: (_, __) =>
            const EmployeeAppraisalRequestPage(formRoute: '/hr/appraisal/form')),
        GoRoute(path: '/hr/appraisal/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(existing: extra['existing'] as AppraisalForm?);
        }),
        GoRoute(path: '/hr/appraisal-received',     builder: (_, __) => const AppraisalReceivedPage()),
        GoRoute(path: '/hr/appraisal-received/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(existing: extra['existing'] as AppraisalForm?);
        }),
      ],
    ),

    // ── Employee Shell ─────────────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) =>
          EmployeeShell(child: child, location: state.uri.path),
      routes: [
        GoRoute(path: '/employee/dashboard',               builder: (_, __) => const EmployeeDashboardPage()),
        GoRoute(path: '/employee/my-details',              builder: (_, __) => const MyProfilePage()),
        GoRoute(path: '/employee/attendance-management',        builder: (_, __) => const MyAttendancePage(checkInRoute: '/employee/attendance/check-in-out')),
        GoRoute(path: '/employee/attendance-leaves',            builder: (_, __) => const MyAttendanceAndLeavePage(checkInRoute: '/employee/attendance/check-in-out', leavePrefix: '/employee')),
        GoRoute(path: '/employee/attendance/check-in-out',      builder: (_, __) => const EmployeeAttendancePage()),
        GoRoute(path: '/employee/attendance/check-in',     builder: (_, __) => const CheckInPage()),
        GoRoute(path: '/employee/attendance/check-out',    builder: (_, __) => const CheckOutPage()),
        GoRoute(path: '/employee/attendance/gps-tracking', builder: (_, __) => const GpsTrackingPage()),
        GoRoute(path: '/employee/attendance/late-coming',  builder: (_, __) => const LateComingPage()),
        GoRoute(path: '/employee/attendance',              builder: (_, __) => const MyAttendancePage()),
        GoRoute(path: '/employee/leave-management',        builder: (_, __) => const EmployeeLeavePage()),
        GoRoute(path: '/employee/leave/apply',             builder: (_, __) => const ApplyLeavePage()),
        GoRoute(path: '/employee/leave/permission',        builder: (_, __) => const ApplyPermissionPage()),
        GoRoute(path: '/employee/leave/compoff',           builder: (_, __) => const ApplyCompOffPage()),
        GoRoute(path: '/employee/on-duty',                 builder: (_, __) => const ApplyOnDutyPage()),
        GoRoute(path: '/employee/leave/approvals',         builder: (_, __) => const MyLeaveApprovalsPage()),
        GoRoute(path: '/employee/leave/balance',           builder: (_, __) => const MyLeaveBalancePage()),
        GoRoute(path: '/employee/leave',                   builder: (_, __) => const ApplyLeavePage()),
        GoRoute(path: '/employee/tasks',                    builder: (_, state) =>
            MyTasksPage(initialStatus: taskStatusFromName(state.uri.queryParameters['status']))),
        GoRoute(path: '/employee/tasks/add',                builder: (_, __) => const AddTaskPage(selfAssign: true)),
        GoRoute(path: '/employee/payslips',                 builder: (_, __) => const MyPayslipsPage()),
        GoRoute(path: '/employee/kra',                      builder: (_, __) => const MyKraPage()),
        GoRoute(path: '/employee/appraisal',                builder: (_, __) => const EmployeeAppraisalRequestPage()),
        GoRoute(path: '/employee/appraisal/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(existing: extra['existing'] as AppraisalForm?);
        }),
        GoRoute(path: '/employee/profile',                  builder: (_, __) => const MyProfilePage()),
        GoRoute(path: '/employee/maintenance-management',   builder: (_, __) => const MaintenanceManagementPage()),
        GoRoute(path: '/employee/employee-onboarding',      builder: (_, __) => const MyOnboardingFormPage()),
        GoRoute(path: '/employee/interview-form',           builder: (_, __) => const CandidateDetailPage()),
        GoRoute(path: '/employee/my-journey',               builder: (_, __) => const MyJourneyPage()),
        GoRoute(path: '/employee/notifications',            builder: (_, __) => const NotificationsPage()),
        // "My Team" — reachable by anyone flagged isReportingManager, even
        // if their role isn't Manager (see reporting-manager-overhaul).
        GoRoute(path: '/employee/my-team/records',          builder: (_, __) => const HrEmployeeRecordsPage()),
        GoRoute(path: '/employee/my-team/leave-approvals',  builder: (_, __) => const TeamLeaveApprovalsPage()),
        GoRoute(path: '/employee/my-team/interview-review', builder: (_, __) => const ManagerInterviewReviewPage()),
        GoRoute(path: '/employee/my-team/appraisal-received', builder: (_, __) => const AppraisalReceivedPage()),
        GoRoute(path: '/employee/my-team/appraisal-received/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(existing: extra['existing'] as AppraisalForm?);
        }),
      ],
    ),

    // ── Reporting Manager Shell ────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) =>
          ManagerShell(child: child, location: state.uri.path),
      routes: [
        GoRoute(path: '/manager/dashboard',               builder: (_, __) => const ManagerDashboardPage()),
        // HR-side pages
        GoRoute(path: '/manager/employee-management',     builder: (_, __) => const HrEmployeeRecordsPage()),
        GoRoute(path: '/manager/attendance-management',   builder: (_, __) => const HrAttendanceRecordsPage(routePrefix: '/manager')),
        GoRoute(path: '/manager/attendance/employee-attendance-calendar', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EmployeeAttendanceCalendarPage(
            employeeId:   extra['employeeId']   as String,
            employeeName: extra['employeeName'] as String,
          );
        }),
        GoRoute(path: '/manager/leave-management',        builder: (_, __) => const ManagerLeavePage()),
        GoRoute(path: '/manager/leave/apply',             builder: (_, __) => const ApplyLeavePage()),
        GoRoute(path: '/manager/leave/permission',        builder: (_, __) => const ApplyPermissionPage()),
        GoRoute(path: '/manager/leave/compoff',           builder: (_, __) => const ApplyCompOffPage()),
        GoRoute(path: '/manager/leave/approvals',         builder: (_, __) => const MyLeaveApprovalsPage()),
        GoRoute(path: '/manager/leave/balance',           builder: (_, __) => const MyLeaveBalancePage()),
        GoRoute(path: '/manager/leave/team-approvals',    builder: (_, __) => const TeamLeaveApprovalsPage()),
        GoRoute(path: '/manager/attendance/check-in',     builder: (_, __) => const CheckInPage()),
        GoRoute(path: '/manager/attendance/check-out',    builder: (_, __) => const CheckOutPage()),
        GoRoute(path: '/manager/attendance/gps-tracking', builder: (_, __) => const GpsTrackingPage()),
        GoRoute(path: '/manager/attendance/late-coming',  builder: (_, __) => const LateComingPage()),
        GoRoute(path: '/manager/task-management',         builder: (_, state) =>
            TaskManagementPage(initialStatus: taskStatusFromName(state.uri.queryParameters['status']))),
        GoRoute(path: '/manager/task-management/add',     builder: (_, __) => const AddTaskPage()),
        GoRoute(path: '/manager/performance-management',  builder: (_, __) => const PerformanceManagementPage()),
        GoRoute(path: '/manager/performance-management/employee', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EmployeeAppraisalPage(
            employee: extra['employee'] as AppUser,
            allUsers: (extra['allUsers'] as List<AppUser>?) ?? const [],
          );
        }),
        GoRoute(path: '/manager/performance-management/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(
            employee: extra['employee'] as AppUser,
            existing: extra['existing'] as AppraisalForm?,
            allUsers: (extra['allUsers'] as List<AppUser>?) ?? const [],
          );
        }),
        GoRoute(path: '/manager/appraisal',               builder: (_, __) =>
            const EmployeeAppraisalRequestPage(formRoute: '/manager/appraisal/form')),
        GoRoute(path: '/manager/appraisal/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(existing: extra['existing'] as AppraisalForm?);
        }),
        GoRoute(path: '/manager/appraisal-received',      builder: (_, __) => const AppraisalReceivedPage()),
        GoRoute(path: '/manager/appraisal-received/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(existing: extra['existing'] as AppraisalForm?);
        }),
        GoRoute(path: '/manager/salary-hike-engine',      builder: (_, __) => const SalaryHikeEnginePage()),
        GoRoute(path: '/manager/interview-process',       builder: (_, __) => const InterviewProcessPage()),
        GoRoute(path: '/manager/interview-review',        builder: (_, __) => const ManagerInterviewReviewPage()),
        GoRoute(path: '/manager/candidate-detail',        builder: (_, __) => const CandidateDetailPage()),
        GoRoute(path: '/manager/employee-onboarding',     builder: (_, __) => const MyOnboardingFormPage()),
        GoRoute(path: '/manager/maintenance-management',  builder: (_, __) => const MaintenanceManagementPage()),
        GoRoute(path: '/manager/approvals',               builder: (_, __) => const ApprovalsPage()),
        GoRoute(path: '/manager/notifications',           builder: (_, __) => const NotificationsPage()),
        GoRoute(path: '/manager/reports-analytics',       builder: (_, __) => const ReportsAnalyticsPage()),
        // Personal pages
        GoRoute(path: '/manager/my-details',              builder: (_, __) => const MyProfilePage()),
        GoRoute(path: '/manager/my-attendance',                  builder: (_, __) => const MyAttendancePage(checkInRoute: '/manager/attendance/check-in-out')),
        GoRoute(path: '/manager/attendance-leaves',              builder: (_, __) => const MyAttendanceAndLeavePage(checkInRoute: '/manager/attendance/check-in-out', leavePrefix: '/manager')),
        GoRoute(path: '/manager/attendance/check-in-out',        builder: (_, __) => const EmployeeAttendancePage(prefix: '/manager')),
        GoRoute(path: '/manager/my-leave',                builder: (_, __) => const EmployeeLeavePage(prefix: '/manager')),
        GoRoute(path: '/manager/my-tasks',                builder: (_, state) =>
            MyTasksPage(initialStatus: taskStatusFromName(state.uri.queryParameters['status']))),
        GoRoute(path: '/manager/my-tasks/add',            builder: (_, __) => const AddTaskPage(selfAssign: true)),
        GoRoute(path: '/manager/my-payslips',             builder: (_, __) => const MyPayslipsPage()),
        GoRoute(path: '/manager/my-kra',                  builder: (_, __) => const MyKraPage()),
        GoRoute(path: '/manager/my-profile',              builder: (_, __) => const MyProfilePage()),
        GoRoute(path: '/manager/interview-form',          builder: (_, __) => const CandidateDetailPage()),
        GoRoute(path: '/manager/my-journey',              builder: (_, __) => const MyJourneyPage()),
      ],
    ),
    // ── Management Shell ──────────────────────────────────────────────────────
    ShellRoute(
      builder: (context, state, child) =>
          ManagementShell(child: child, location: state.uri.path),
      routes: [
        GoRoute(path: '/management/dashboard',              builder: (_, __) => const ManagementDashboardPage()),
        GoRoute(path: '/management/employee-management',    builder: (_, __) => const HrEmployeeRecordsPage()),
        GoRoute(path: '/management/employee-management/add',builder: (_, __) => const AddEmployeePage()),
        GoRoute(path: '/management/employee-management/profile', redirect: (_, __) => '/management/employee-management'),
        GoRoute(path: '/management/employee-management/reporting-managers', builder: (_, __) => const ReportingManagersPage()),
        GoRoute(path: '/management/attendance-management',  builder: (_, __) => const HrAttendanceRecordsPage(routePrefix: '/management')),
        GoRoute(path: '/management/attendance/employee-attendance-calendar', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EmployeeAttendanceCalendarPage(
            employeeId:   extra['employeeId']   as String,
            employeeName: extra['employeeName'] as String,
          );
        }),
        GoRoute(path: '/management/attendance/check-in',    builder: (_, __) => const CheckInPage()),
        GoRoute(path: '/management/attendance/check-out',   builder: (_, __) => const CheckOutPage()),
        GoRoute(path: '/management/attendance/gps-tracking',builder: (_, __) => const GpsTrackingPage()),
        GoRoute(path: '/management/attendance/late-coming', builder: (_, __) => const LateComingPage()),
        GoRoute(path: '/management/leave-management',       builder: (_, __) => const ManagementLeavePage()),
        GoRoute(path: '/management/leave/overview',         builder: (_, __) => const TeamLeaveApprovalsPage(isManagement: true, showAll: true)),
        GoRoute(path: '/management/leave/apply',            builder: (_, __) => const ApplyLeavePage()),
        GoRoute(path: '/management/leave/permission',       builder: (_, __) => const ApplyPermissionPage()),
        GoRoute(path: '/management/leave/compoff',          builder: (_, __) => const ApplyCompOffPage()),
        GoRoute(path: '/management/leave/approvals',        builder: (_, __) => const LeaveApprovalsPage()),
        GoRoute(path: '/management/leave/balance',          builder: (_, __) => const LeaveBalancePage()),
        GoRoute(path: '/management/leave/team-approvals',   builder: (_, __) => const TeamLeaveApprovalsPage(isManagement: true, showAll: false)),
        GoRoute(path: '/management/leave/employee-records', builder: (_, __) => const HrLeaveRecordsPage()),
        GoRoute(path: '/management/onroll-approvals',       builder: (_, __) => const OnrollApprovalsPage()),
        GoRoute(path: '/management/kra-management',          builder: (_, __) => const KraManagementPage()),
        GoRoute(path: '/management/kra-management/employee', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EmployeeKraPage(employee: extra['employee'] as AppUser);
        }),
        GoRoute(path: '/management/kra-approvals',            builder: (_, __) => const KraApprovalsPage()),
        GoRoute(path: '/management/task-management',        builder: (_, state) =>
            TaskManagementPage(initialStatus: taskStatusFromName(state.uri.queryParameters['status']))),
        GoRoute(path: '/management/task-management/add',    builder: (_, __) => const AddTaskPage()),
        GoRoute(path: '/management/performance-management', builder: (_, __) => const PerformanceManagementPage()),
        GoRoute(path: '/management/performance-management/employee', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EmployeeAppraisalPage(
            employee: extra['employee'] as AppUser,
            allUsers: (extra['allUsers'] as List<AppUser>?) ?? const [],
          );
        }),
        GoRoute(path: '/management/performance-management/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(
            employee: extra['employee'] as AppUser,
            existing: extra['existing'] as AppraisalForm?,
            allUsers: (extra['allUsers'] as List<AppUser>?) ?? const [],
          );
        }),
        GoRoute(path: '/management/appraisals',              builder: (_, __) => const ManagementAppraisalsPage()),
        GoRoute(path: '/management/appraisals/form', builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>;
          return AppraisalFormEditorPage(
            existing: extra['existing'] as AppraisalForm?,
            allUsers: (extra['allUsers'] as List<AppUser>?) ?? const [],
          );
        }),
        GoRoute(path: '/management/salary-hike-engine',     builder: (_, __) => const SalaryHikeEnginePage()),
        GoRoute(path: '/management/payroll-management',     builder: (_, __) => const PayrollManagementPage()),
        GoRoute(path: '/management/interview-process',      builder: (_, __) => const InterviewProcessPage()),
        GoRoute(path: '/management/interview-review',       builder: (_, __) => const ManagementInterviewReviewPage()),
        GoRoute(path: '/management/edit-form',              builder: (_, __) => const EditFormPage()),
        GoRoute(path: '/management/edit-leave-form',        builder: (_, __) => const EditLeaveFormPage()),
        GoRoute(path: '/management/form-approvals',         builder: (_, __) => const FormApprovalsPage()),
        GoRoute(path: '/management/candidate-detail',       builder: (_, __) => const CandidateDetailPage()),
        GoRoute(path: '/management/employee-onboarding',    builder: (_, __) => const EmployeeOnboardingPage()),
        GoRoute(path: '/management/edit-onboarding-form',   builder: (_, __) => const EditOnboardingFormPage()),
        GoRoute(path: '/management/edit-maintenance-form',  builder: (_, __) => const EditMaintenanceFormPage()),
        GoRoute(path: '/management/location-management',    builder: (_, __) => const LocationManagementPage()),
        GoRoute(path: '/management/lead-management',
            builder: (_, __) => const LeadManagementHubPage(basePath: '/management/lead-management')),
        GoRoute(path: '/management/lead-management/leads', builder: (_, s) {
          final x = s.extra as Map<String, String>? ?? {};
          return LeadManagementPage(url: x['url'] ?? '', name: x['name'] ?? 'Leads');
        }),
        GoRoute(path: '/management/maintenance-management', builder: (_, __) => const MaintenanceManagementPage()),
        GoRoute(path: '/management/approvals',              builder: (_, __) => const ApprovalsPage()),
        GoRoute(path: '/management/notifications',          builder: (_, __) => const NotificationsPage()),
        GoRoute(path: '/management/reports-analytics',      builder: (_, __) => const ReportsAnalyticsPage()),
        GoRoute(path: '/management/administration',         builder: (_, __) => const AdministrationPage()),
        GoRoute(path: '/management/settings',               builder: (_, __) => const SettingsPage()),
        // Location history is Management-only by placement here. The view
        // underneath has security_invoker on, so RLS applies regardless — an
        // employee reaching it would see only their own movements.
        GoRoute(path: '/management/location-history',       builder: (_, __) => const LocationHistoryPage()),
        GoRoute(path: '/management/my-details',             builder: (_, __) => const MyProfilePage()),
        GoRoute(path: '/management/my-attendance',               builder: (_, __) => const MyAttendancePage(checkInRoute: '/management/attendance/check-in-out')),
        GoRoute(path: '/management/attendance/check-in-out',     builder: (_, __) => const EmployeeAttendancePage()),
        GoRoute(path: '/management/my-leave',               builder: (_, __) => const EmployeeLeavePage()),
        GoRoute(path: '/management/attendance-leaves',       builder: (_, __) => const MyAttendanceAndLeavePage(checkInRoute: '/management/attendance/check-in-out')),
        GoRoute(path: '/management/my-tasks',               builder: (_, state) =>
            MyTasksPage(initialStatus: taskStatusFromName(state.uri.queryParameters['status']))),
        GoRoute(path: '/management/my-payslips',            builder: (_, __) => const MyPayslipsPage()),
        GoRoute(path: '/management/my-profile',             builder: (_, __) => const MyProfilePage()),
        GoRoute(path: '/management/my-maintenance',         builder: (_, __) => const MaintenanceManagementPage()),
      ],
    ),
    // ── Staff Portal Shell (Housekeeping / Support Staff) ──────────────────
    ShellRoute(
      builder: (context, state, child) =>
          StaffShell(child: child, location: state.uri.path),
      routes: [
        GoRoute(path: '/staff/home',       builder: (_, __) => const StaffHomePage()),
        GoRoute(path: '/staff/leave',      builder: (_, __) => const StaffLeavePage()),
        GoRoute(path: '/staff/permission', builder: (_, __) => const StaffPermissionPage()),
        GoRoute(path: '/staff/profile',    builder: (_, __) => const StaffProfilePage()),
      ],
    ),
  ],
);

class FomraHrmsApp extends StatelessWidget {
  const FomraHrmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: colorThemeNotifier,
      builder: (_, __) => MaterialApp.router(
        title: 'FOMRA HRMS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        routerConfig: _router,
      ),
    );
  }
}
