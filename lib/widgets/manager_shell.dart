import 'package:flutter/material.dart';
import 'breadcrumb_bar.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';
import 'section_tabs.dart';

// Manager menu, in the same shape as Management's and HR's (Ronak, 21 Nov
// 2026): four sections with their screens as tabs. The manager's own pages
// (attendance, leave, payslips, tasks) are in the menu under their name,
// top right.
const _sections = <SectionSpec>[
  SectionSpec('Home', Icons.space_dashboard_rounded, [
    SectionTab('Home', '/manager/dashboard', title: 'Dashboard'),
  ]),
  SectionSpec('Approvals', Icons.inbox_rounded, [
    SectionTab('Team leave', '/manager/leave/team-approvals', title: 'Team leave approvals',
        alsoMatches: ['/manager/leave/approvals']),
    // Attendance confirmations and other requests addressed to a manager.
    SectionTab('Other requests', '/manager/approvals', title: 'Approvals'),
  ]),
  SectionSpec('Team', Icons.groups_rounded, [
    SectionTab('Employees', '/manager/employee-management', title: 'My team'),
    SectionTab('Interview review', '/manager/interview-review', title: 'Interview review',
        alsoMatches: ['/manager/candidate-detail']),
    SectionTab('Appraisals received', '/manager/appraisal-received', title: 'Appraisals received'),
  ]),
  SectionSpec('Tasks', Icons.task_alt_rounded, [
    SectionTab('Team tasks', '/manager/task-management', title: 'Team tasks'),
    SectionTab('My tasks', '/manager/my-tasks', title: 'My tasks'),
  ]),
];

/// Reached from the profile menu or the bell; listed for their titles.
const _otherTitles = <BreadcrumbSection>[
  (label: 'Notifications', route: '/manager/notifications'),
  (label: 'My profile', route: '/manager/my-profile'),
  (label: 'My attendance & leave', route: '/manager/attendance-leaves'),
  (label: 'My leave balance', route: '/manager/leave/balance'),
  (label: 'Apply permission', route: '/manager/leave/permission'),
  (label: 'Apply comp off', route: '/manager/leave/compoff'),
  (label: 'Apply on duty', route: '/manager/on-duty'),
  (label: 'Attendance issue', route: '/manager/attendance-confirmation'),
  (label: 'My payslips', route: '/manager/my-payslips'),
  (label: 'My appraisal', route: '/manager/appraisal'),
  (label: 'My maintenance requests', route: '/manager/maintenance-management'),
];

class ManagerShell extends StatelessWidget {
  final Widget child;
  final String location;
  const ManagerShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final groups = navGroupsForSections(_sections);
    final titles = titlesForSections(_sections, others: _otherTitles);
    final framed = SectionTabsFrame(sections: _sections, location: location, child: child);
    final isWide = MediaQuery.of(context).size.width >= 700;
    if (isWide) {
      return DesktopShellScaffold(
        location: location,
        homeRoute: '/manager/dashboard',
        notificationsRoute: '/manager/notifications',
        sections: titles,
        groups: groups,
        roleLabel: 'Manager',
        child: framed,
      );
    }
    return MobileShellScaffold(
      location: location,
      homeRoute: '/manager/dashboard',
      notificationsRoute: '/manager/notifications',
      sections: titles,
      drawer: AppSidebar(groups: groups, location: location, homeRoute: '/manager/dashboard', inSheet: true),
      tabs: [
        mobileTabForSection(_sections[0], Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
        mobileTabForSection(_sections[1], Icons.inbox_outlined, Icons.inbox_rounded),
        mobileTabForSection(_sections[2], Icons.groups_outlined, Icons.groups_rounded),
        mobileTabForSection(_sections[3], Icons.task_alt_outlined, Icons.task_alt_rounded),
      ],
      child: framed,
    );
  }
}
