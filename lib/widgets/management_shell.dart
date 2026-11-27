import 'package:flutter/material.dart';
import 'breadcrumb_bar.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';
import 'section_tabs.dart';

// Management menu (redesign approved by Ronak, 20 Nov 2026): seven plain
// sections, each one entry in the menu with its screens as tabs across the
// top, instead of about 35 entries in pinned items and five groups. Every
// screen and link is kept; only the grouping changed. Rarely used modules
// sit under More; Management's own attendance, leave and payslips are in
// the menu under their name (top right).
const _sections = <SectionSpec>[
  SectionSpec('Overview', Icons.space_dashboard_rounded, [
    SectionTab('Overview', '/management/dashboard'),
  ]),
  SectionSpec('Approvals', Icons.inbox_rounded, [
    SectionTab('Leave', '/management/leave/team-approvals', title: 'Leave approvals',
        alsoMatches: ['/management/leave/approvals']),
    SectionTab('Salary', '/management/salary-approvals', title: 'Salary approvals'),
    SectionTab('Late arrivals', '/management/late-review', title: 'Late review'),
    SectionTab('Confirmations', '/management/onroll-approvals', title: 'Confirmations'),
    SectionTab('KRA', '/management/kra-approvals', title: 'KRA approvals'),
    SectionTab('Forms', '/management/form-approvals', title: 'Form approvals'),
    SectionTab('Other requests', '/management/approvals', title: 'Other requests'),
  ]),
  SectionSpec('Attendance', Icons.schedule_rounded, [
    SectionTab('Records', '/management/attendance-management', title: 'Attendance records',
        alsoMatches: ['/management/attendance/employee-attendance-calendar']),
    SectionTab('Date range', '/management/attendance-range', title: 'Attendance by date range'),
    SectionTab('Leave', '/management/leave-management', title: 'Leave records',
        alsoMatches: ['/management/leave/employee-records', '/management/leave/overview']),
    SectionTab('Late coming', '/management/attendance/late-coming', title: 'Late coming'),
    SectionTab('New joiners', '/management/joiner-attendance', title: 'New joiners: days before the account opened'),
    SectionTab('Live location', '/management/attendance/gps-tracking', title: 'Live location'),
    SectionTab('Location history', '/management/location-history', title: 'Location history'),
  ]),
  SectionSpec('People', Icons.groups_rounded, [
    SectionTab('Employees', '/management/employee-management', title: 'Employees'),
    SectionTab('Onboarding', '/management/employee-onboarding', title: 'Onboarding'),
    SectionTab('Exits', '/management/exits', title: 'Exits & F&F'),
    SectionTab('Interviews', '/management/interview-process', title: 'Interviews',
        alsoMatches: ['/management/candidate-detail']),
    SectionTab('Interview review', '/management/interview-review', title: 'Interview review'),
  ]),
  SectionSpec('Payroll', Icons.payments_rounded, [
    SectionTab('Payslips', '/management/payroll-management', title: 'Payroll'),
    SectionTab('Master sheet', '/management/salary-master-sheet', title: 'Salary master sheet'),
    SectionTab('Salary review', '/management/salary-hike-engine', title: 'Salary review'),
  ]),
  SectionSpec('Reports', Icons.bar_chart_rounded, [
    SectionTab('Reports', '/management/reports-analytics', title: 'Reports'),
  ]),
  SectionSpec('Settings', Icons.settings_rounded, [
    SectionTab('General', '/management/settings', title: 'Settings',
        alsoMatches: ['/management/edit-leave-form', '/management/edit-form',
            '/management/edit-onboarding-form', '/management/edit-maintenance-form']),
    SectionTab('Administration', '/management/administration', title: 'Administration'),
    SectionTab('Offices', '/management/location-management', title: 'Office locations'),
    SectionTab('App health', '/management/app-health', title: 'App health'),
  ]),
];

/// Modules with little use so far, out of the main list.
const _more = <NavEntry>[
  NavEntry('Tasks', Icons.task_alt_rounded, '/management/task-management'),
  NavEntry('Leads', Icons.contact_phone_rounded, '/management/lead-management'),
  NavEntry('Maintenance', Icons.handyman_rounded, '/management/maintenance-management'),
  NavEntry('Appraisals', Icons.workspace_premium_rounded, '/management/appraisals'),
  NavEntry('KRA', Icons.track_changes_rounded, '/management/kra-management'),
];

/// Reached from the profile menu, the bell or a Settings link rather than
/// the menu; listed so their pages still get a title.
const _otherTitles = <({String label, String route})>[
  (label: 'Notifications', route: '/management/notifications'),
  (label: 'My attendance & leave', route: '/management/attendance-leaves'),
  (label: 'My leave balance', route: '/management/leave/balance'),
  (label: 'My payslips', route: '/management/my-payslips'),
  (label: 'My profile', route: '/management/my-profile'),
  (label: 'Leave, permission & comp off forms', route: '/management/edit-leave-form'),
  (label: 'Interview form', route: '/management/edit-form'),
  (label: 'Onboarding form', route: '/management/edit-onboarding-form'),
  (label: 'Maintenance form', route: '/management/edit-maintenance-form'),
];

// Breadcrumbs resolve a route to a title: every destination, flat.
List<BreadcrumbSection> get _breadcrumbSections => [
      for (final s in _sections)
        for (final t in s.tabs) (label: t.pageTitle, route: t.route),
      for (final e in _more) (label: e.label, route: e.route),
      ..._otherTitles,
    ];

List<NavGroupSpec> get _groups => [
      NavGroupSpec(items: [
        for (final s in _sections)
          NavEntry(s.label, s.icon, s.route, alsoMatches: s.allRoutes.skip(1).toList()),
      ]),
      const NavGroupSpec(title: 'More', icon: Icons.more_horiz_rounded, collapsible: true, items: _more),
    ];

SectionSpec _section(String label) => _sections.firstWhere((s) => s.label == label);

class ManagementShell extends StatelessWidget {
  final Widget child;
  final String location;
  const ManagementShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    final framed = SectionTabsFrame(sections: _sections, location: location, child: child);
    if (isWide) {
      return DesktopShellScaffold(
        location: location,
        homeRoute: '/management/dashboard',
        notificationsRoute: '/management/notifications',
        sections: _breadcrumbSections,
        groups: _groups,
        roleLabel: 'Management',
        child: framed,
      );
    }
    MobileTab tab(String label, IconData icon, IconData selected) {
      final s = _section(label);
      return MobileTab(label, icon, s.route, selectedIcon: selected, alsoMatches: s.allRoutes);
    }
    return MobileShellScaffold(
      location: location,
      homeRoute: '/management/dashboard',
      notificationsRoute: '/management/notifications',
      sections: _breadcrumbSections,
      drawer: AppSidebar(groups: _groups, location: location, homeRoute: '/management/dashboard', inSheet: true),
      tabs: [
        tab('Overview', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
        tab('Approvals', Icons.inbox_outlined, Icons.inbox_rounded),
        tab('Attendance', Icons.schedule_outlined, Icons.schedule_rounded),
        tab('Payroll', Icons.payments_outlined, Icons.payments_rounded),
      ],
      child: framed,
    );
  }
}
