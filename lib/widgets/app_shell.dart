import 'package:flutter/material.dart';
import '../models/user_session.dart';
import 'breadcrumb_bar.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

const _editFormItems = <NavEntry>[
  NavEntry('Edit Leave Form', Icons.event_available_rounded, '/edit-leave-form'),
  NavEntry('Edit Permission Form', Icons.access_time_rounded, '/edit-leave-form'),
  NavEntry('Edit Comp Off Form', Icons.swap_horiz_rounded, '/edit-leave-form'),
  NavEntry('Edit Interview Form', Icons.assignment_rounded, '/edit-form'),
  NavEntry('Edit Onboarding Form', Icons.how_to_reg_rounded, '/edit-onboarding-form'),
  NavEntry('Edit Maintenance Form', Icons.build_rounded, '/edit-maintenance-form'),
  NavEntry('Location Management', Icons.location_on_rounded, '/location-management'),
];

const _navItems = [
  NavEntry('Dashboard', Icons.dashboard_rounded, '/dashboard'),

  // Approvals together. They were scattered through the list, so "what needs
  // me" meant scanning eighteen items for the four that were decisions.
  NavEntry('Approvals',        Icons.approval_rounded,        '/hr/approvals'),
  NavEntry('Staff Portal Approvals', Icons.cleaning_services_rounded, '/leave/staff-portal-approvals'),
  NavEntry('Late Review',      Icons.running_with_errors_rounded, '/late-review'),

  // Attendance and leave: the daily work.
  NavEntry('Attendance Management', Icons.access_time_rounded, '/attendance-management'),
  NavEntry('Attendance by Date Range', Icons.date_range_rounded, '/attendance-range'),
  // event_available reads as "free to book"; these are records of leave taken.
  NavEntry('Leave Records (view only)', Icons.event_note_rounded, '/leave-management'),

  // People, from hiring through to review.
  NavEntry('Employee Management', Icons.people_rounded, '/employee-management'),
  NavEntry('Employee Onboarding', Icons.how_to_reg_rounded, '/employee-onboarding'),
  NavEntry('Interview Process', Icons.record_voice_over_rounded, '/interview-process'),
  NavEntry('Appraisals', Icons.fact_check_rounded, '/appraisals'),
  // flag says nothing; KRAs are tracked objectives.
  NavEntry('KRA', Icons.track_changes_rounded, '/kra-management'),

  // Money. payments matches the icon used for salary elsewhere, so the same
  // idea does not wear two faces.
  NavEntry('Payroll Management', Icons.payments_rounded, '/payroll-management'),
  // What to credit to each person, with the breakup, and the Excel for the bank.
  NavEntry('Salary Master Sheet', Icons.table_view_rounded, '/salary-master-sheet'),

  // Everything else that is run rather than decided.
  NavEntry('Task Management', Icons.task_alt_rounded, '/task-management'),
  // leaderboard implies a ranking; these are sales leads.
  NavEntry('Lead Management', Icons.contact_phone_rounded, '/lead-management'),
  NavEntry('Maintenance Management', Icons.build_rounded, '/maintenance-management'),

  NavEntry('Notifications', Icons.notifications_rounded, '/notifications'),
  NavEntry('Reports & Analytics', Icons.bar_chart_rounded, '/reports-analytics'),
];

const _personalNavItems = [
  NavEntry('My Profile',    Icons.person_rounded,                 '/hr/my-profile'),
  NavEntry('My Attendance and Leaves', Icons.event_note_rounded,  '/hr/attendance-leaves'),
  NavEntry('My Leave Balance',      Icons.account_balance_wallet_rounded, '/leave/balance'),
  NavEntry('Apply Permission',      Icons.timer_outlined,          '/leave/permission'),
  NavEntry('Apply Comp Off',        Icons.swap_horiz_rounded,      '/leave/compoff'),
  NavEntry('My Tasks',      Icons.task_alt_rounded,               '/hr/my-tasks'),
  NavEntry('My Payslips',   Icons.account_balance_wallet_rounded, '/hr/my-payslips'),
  NavEntry('Appraisal',     Icons.fact_check_rounded,             '/hr/appraisal'),
  NavEntry('Maintenance',   Icons.build_rounded,                  '/hr/maintenance-management'),
];

// Shown only when UserSession.isReportingManager — HR can also be flagged
// as a Reporting Manager (see reporting-manager-overhaul), and previously
// had none of an RM's team-facing views. Mirrors manager_shell.dart's
// equivalent items.
const _myTeamNavItems = [
  NavEntry('Leave Approvals (approve / reject)', Icons.group_rounded, '/hr/leave/team-approvals'),
  NavEntry('Interview Review',     Icons.rate_review_rounded, '/hr/interview-review'),
  NavEntry('Appraisal Received',   Icons.fact_check_rounded,  '/hr/appraisal-received'),
];

List<BreadcrumbSection> get _breadcrumbSections =>
    [..._navItems, ..._personalNavItems, ..._myTeamNavItems]
        .map((e) => (label: e.label, route: e.route))
        .toList();

List<NavGroupSpec> get _groups => [
      const NavGroupSpec(items: _navItems),
      if (UserSession.isReportingManager)
        const NavGroupSpec(title: 'My Team', items: _myTeamNavItems),
      const NavGroupSpec(
          title: 'Edit Forms', icon: Icons.edit_note_rounded, collapsible: true, items: _editFormItems),
      const NavGroupSpec(title: 'My Space', items: _personalNavItems),
    ];

class AppShell extends StatelessWidget {
  final Widget child;
  final String location;

  const AppShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    if (isWide) {
      return DesktopShellScaffold(
        location: location,
        homeRoute: '/dashboard',
        notificationsRoute: '/notifications',
        sections: _breadcrumbSections,
        groups: _groups,
        roleLabel: 'HR',
        child: child,
      );
    }
    return MobileShellScaffold(
      location: location,
      homeRoute: '/dashboard',
      notificationsRoute: '/notifications',
      sections: _breadcrumbSections,
      drawer: AppSidebar(groups: _groups, location: location, homeRoute: '/dashboard', inSheet: true),
      child: child,
    );
  }
}
