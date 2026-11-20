import 'package:flutter/material.dart';
import 'breadcrumb_bar.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

const _hrNavItems = [
  NavEntry('Dashboard',            Icons.dashboard_rounded,     '/manager/dashboard'),
  NavEntry('Employee Management',  Icons.people_alt_rounded,    '/manager/employee-management'),
  NavEntry('Interview Review',     Icons.rate_review_rounded,   '/manager/interview-review'),
  NavEntry('Team Leave Approvals', Icons.group_rounded,         '/manager/leave/team-approvals'),
  // Attendance confirmations and other approvals. The route existed but
  // was not in this menu, so a manager notified of a request could not
  // reach the screen to approve or reject it.
  NavEntry('Approvals',            Icons.approval_rounded,      '/manager/approvals'),
  NavEntry('Appraisal Received',   Icons.fact_check_rounded,    '/manager/appraisal-received'),
  NavEntry('Task Management',      Icons.task_alt_rounded,      '/manager/task-management'),
  NavEntry('Notifications',        Icons.notifications_rounded, '/manager/notifications'),
];

const _personalNavItems = [
  NavEntry('My Profile',    Icons.person_rounded,                  '/manager/my-profile'),
  NavEntry('My Attendance and Leaves', Icons.event_note_rounded,   '/manager/attendance-leaves'),
  NavEntry('My Leave Balance',     Icons.account_balance_wallet_rounded, '/manager/leave/balance'),
  NavEntry('Apply Permission',     Icons.timer_outlined,           '/manager/leave/permission'),
  NavEntry('Apply Comp Off',       Icons.swap_horiz_rounded,       '/manager/leave/compoff'),
  NavEntry('My Tasks',      Icons.task_alt_rounded,                '/manager/my-tasks'),
  NavEntry('My Payslips',   Icons.account_balance_wallet_rounded,  '/manager/my-payslips'),
  NavEntry('Appraisal',     Icons.fact_check_rounded,              '/manager/appraisal'),
  NavEntry('Maintenance',   Icons.build_rounded,                   '/manager/maintenance-management'),
];

List<BreadcrumbSection> get _breadcrumbSections =>
    [..._hrNavItems, ..._personalNavItems]
        .map((e) => (label: e.label, route: e.route))
        .toList();

List<NavGroupSpec> get _groups => const [
      NavGroupSpec(items: _hrNavItems),
      NavGroupSpec(title: 'My Space', items: _personalNavItems),
    ];

class ManagerShell extends StatelessWidget {
  final Widget child;
  final String location;
  const ManagerShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    if (isWide) {
      return DesktopShellScaffold(
        location: location,
        homeRoute: '/manager/dashboard',
        notificationsRoute: '/manager/notifications',
        sections: _breadcrumbSections,
        groups: _groups,
        roleLabel: 'Manager',
        child: child,
      );
    }
    return MobileShellScaffold(
      location: location,
      homeRoute: '/manager/dashboard',
      notificationsRoute: '/manager/notifications',
      sections: _breadcrumbSections,
      drawer: AppSidebar(groups: _groups, location: location, homeRoute: '/manager/dashboard', inSheet: true),
      child: child,
    );
  }
}
