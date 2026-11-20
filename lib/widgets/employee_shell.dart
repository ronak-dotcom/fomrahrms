import 'package:flutter/material.dart';
import '../models/user_session.dart';
import 'breadcrumb_bar.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

// The staff menu, grouped as on the redesigned computer layout. Every entry
// of the old flat list is kept.
List<NavGroupSpec> get _groups => [
      NavGroupSpec(title: 'My work', items: [
        NavEntry('Home',                Icons.home_rounded,                    '/employee/dashboard'),
        NavEntry('Attendance',          Icons.fingerprint_rounded,             '/employee/attendance-leaves',
            alsoMatches: ['/employee/attendance', '/employee/attendance-management']),
        // The phone's Leave tab; it had no menu entry on a computer.
        NavEntry('Leave',               Icons.event_available_rounded,         '/employee/leave-management',
            alsoMatches: ['/employee/leave']),
        NavEntry('Payslips',            Icons.receipt_long_rounded,            '/employee/payslips'),
        NavEntry('My Tasks',            Icons.task_alt_rounded,                '/employee/tasks'),
      ]),
      const NavGroupSpec(title: 'Requests', items: [
        // Leave Balance, Permission and Comp Off were all live routes with no
        // nav entry — reachable only by typing the URL.
        NavEntry('My Leave Balance',    Icons.account_balance_wallet_rounded,  '/employee/leave/balance'),
        NavEntry('Apply Permission',    Icons.schedule_rounded,                '/employee/leave/permission'),
        NavEntry('Apply Comp Off',      Icons.swap_horiz_rounded,              '/employee/leave/compoff'),
        NavEntry('Apply On Duty',       Icons.work_history_rounded,            '/employee/on-duty'),
        // Last resort when the app itself could not record a check-in.
        NavEntry('Attendance Issue',    Icons.report_problem_rounded,          '/employee/attendance-confirmation'),
      ]),
      // For anyone flagged isReportingManager, even if their role isn't
      // Manager (see reporting-manager-overhaul).
      if (UserSession.isReportingManager)
        const NavGroupSpec(title: 'My team', items: [
          NavEntry('My Team',              Icons.groups_rounded,               '/employee/my-team/records'),
          NavEntry('Team Leave Approvals', Icons.event_available_rounded,      '/employee/my-team/leave-approvals'),
          NavEntry('Interview Review',     Icons.rate_review_rounded,          '/employee/my-team/interview-review'),
          NavEntry('Appraisal Received',   Icons.fact_check_rounded,           '/employee/my-team/appraisal-received'),
        ]),
      const NavGroupSpec(title: 'Me', items: [
        NavEntry('My Profile',          Icons.person_rounded,                  '/employee/profile'),
        NavEntry('Appraisal',           Icons.fact_check_rounded,              '/employee/appraisal'),
        NavEntry('My Journey',          Icons.timeline_rounded,                '/employee/my-journey'),
        NavEntry('Maintenance',         Icons.build_rounded,                   '/employee/maintenance-management'),
        NavEntry('My Notifications',    Icons.notifications_rounded,           '/employee/notifications'),
      ]),
    ];

List<BreadcrumbSection> get _breadcrumbSections => [
      for (final g in _groups)
        for (final e in g.items) (label: e.label, route: e.route),
    ];

class EmployeeShell extends StatelessWidget {
  final Widget child;
  final String location;
  const EmployeeShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    if (isWide) {
      return DesktopShellScaffold(
        location: location,
        homeRoute: '/employee/dashboard',
        notificationsRoute: '/employee/notifications',
        sections: _breadcrumbSections,
        groups: _groups,
        // Staff Home shows announcements, holidays and birthdays itself.
        showQuickIcons: false,
        roleLabel: 'Staff',
        child: child,
      );
    }
    return MobileShellScaffold(
      location: location,
      homeRoute: '/employee/dashboard',
      notificationsRoute: '/employee/notifications',
      sections: _breadcrumbSections,
      drawer: AppSidebar(
        groups: _groups,
        location: location,
        homeRoute: '/employee/dashboard',
        inSheet: true,
      ),
      tabs: const [
        MobileTab('Home', Icons.home_outlined, '/employee/dashboard',
            selectedIcon: Icons.home_rounded),
        MobileTab('Attendance', Icons.fingerprint_rounded, '/employee/attendance-leaves',
            alsoMatches: ['/employee/attendance', '/employee/attendance-management']),
        MobileTab('Leave', Icons.event_available_outlined, '/employee/leave-management',
            selectedIcon: Icons.event_available_rounded, alsoMatches: ['/employee/leave']),
        MobileTab('Payslips', Icons.receipt_long_outlined, '/employee/payslips',
            selectedIcon: Icons.receipt_long_rounded),
      ],
      child: child,
    );
  }
}
