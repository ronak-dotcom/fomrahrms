import 'package:flutter/material.dart';
import '../models/user_session.dart';
import 'breadcrumb_bar.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';
import 'section_tabs.dart';

// HR menu, in the same shape as Management's (Ronak, 21 Nov 2026): a few
// plain sections, each with its screens as tabs across the top, instead of
// a list of about 30 entries. Every screen and link is kept. HR's own pages
// (attendance, leave, payslips, tasks) are in the menu under their name,
// top right.
List<SectionSpec> get _sections => [
      const SectionSpec('Home', Icons.space_dashboard_rounded, [
        SectionTab('Home', '/dashboard', title: 'Dashboard'),
      ]),
      SectionSpec('Approvals', Icons.inbox_rounded, [
        const SectionTab('Requests', '/hr/approvals', title: 'Approvals'),
        const SectionTab('Staff portal', '/leave/staff-portal-approvals', title: 'Staff portal approvals'),
        const SectionTab('Late arrivals', '/late-review', title: 'Late review'),
        // HR flagged as a reporting manager also decides their team's leave.
        if (UserSession.isReportingManager)
          const SectionTab('Team leave', '/hr/leave/team-approvals', title: 'Team leave approvals'),
      ]),
      const SectionSpec('Attendance', Icons.schedule_rounded, [
        SectionTab('Records', '/attendance-management', title: 'Attendance records'),
        SectionTab('Date range', '/attendance-range', title: 'Attendance by date range'),
        SectionTab('Leave', '/leave-management', title: 'Leave records'),
      ]),
      SectionSpec('People', Icons.groups_rounded, [
        const SectionTab('Employees', '/employee-management', title: 'Employees'),
        const SectionTab('Onboarding', '/employee-onboarding', title: 'Onboarding'),
        const SectionTab('Interviews', '/interview-process', title: 'Interviews',
            alsoMatches: ['/candidate-detail']),
        const SectionTab('Appraisals', '/appraisals', title: 'Appraisals'),
        const SectionTab('KRA', '/kra-management', title: 'KRA'),
        if (UserSession.isReportingManager) ...[
          const SectionTab('Interview review', '/hr/interview-review', title: 'Interview review'),
          const SectionTab('Appraisals received', '/hr/appraisal-received', title: 'Appraisals received'),
        ],
      ]),
      const SectionSpec('Payroll', Icons.payments_rounded, [
        SectionTab('Payslips', '/payroll-management', title: 'Payroll'),
        SectionTab('Master sheet', '/salary-master-sheet', title: 'Salary master sheet'),
      ]),
      const SectionSpec('Reports', Icons.bar_chart_rounded, [
        SectionTab('Reports', '/reports-analytics', title: 'Reports'),
      ]),
      const SectionSpec('Forms & offices', Icons.tune_rounded, [
        SectionTab('Leave forms', '/edit-leave-form', title: 'Leave, permission & comp off forms'),
        SectionTab('Interview form', '/edit-form', title: 'Interview form'),
        SectionTab('Onboarding form', '/edit-onboarding-form', title: 'Onboarding form'),
        SectionTab('Maintenance form', '/edit-maintenance-form', title: 'Maintenance form'),
        SectionTab('Offices', '/location-management', title: 'Office locations'),
      ]),
    ];

const _more = <NavEntry>[
  NavEntry('Tasks', Icons.task_alt_rounded, '/task-management'),
  NavEntry('Leads', Icons.contact_phone_rounded, '/lead-management'),
  NavEntry('Maintenance', Icons.build_rounded, '/maintenance-management'),
];

/// Reached from the profile menu or the bell; listed for their titles.
const _otherTitles = <BreadcrumbSection>[
  (label: 'Notifications', route: '/notifications'),
  (label: 'My profile', route: '/hr/my-profile'),
  (label: 'My attendance & leave', route: '/hr/attendance-leaves'),
  (label: 'My leave balance', route: '/leave/balance'),
  (label: 'Apply permission', route: '/leave/permission'),
  (label: 'Apply comp off', route: '/leave/compoff'),
  (label: 'My tasks', route: '/hr/my-tasks'),
  (label: 'My payslips', route: '/hr/my-payslips'),
  (label: 'My appraisal', route: '/hr/appraisal'),
  (label: 'My maintenance requests', route: '/hr/maintenance-management'),
];

class AppShell extends StatelessWidget {
  final Widget child;
  final String location;

  const AppShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    final groups = navGroupsForSections(sections, more: _more);
    final titles = titlesForSections(sections, more: _more, others: _otherTitles);
    final framed = SectionTabsFrame(sections: sections, location: location, child: child);
    final isWide = MediaQuery.of(context).size.width >= 700;
    if (isWide) {
      return DesktopShellScaffold(
        location: location,
        homeRoute: '/dashboard',
        notificationsRoute: '/notifications',
        sections: titles,
        groups: groups,
        roleLabel: 'HR',
        child: framed,
      );
    }
    SectionSpec s(String label) => sections.firstWhere((x) => x.label == label);
    return MobileShellScaffold(
      location: location,
      homeRoute: '/dashboard',
      notificationsRoute: '/notifications',
      sections: titles,
      drawer: AppSidebar(groups: groups, location: location, homeRoute: '/dashboard', inSheet: true),
      tabs: [
        mobileTabForSection(s('Home'), Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
        mobileTabForSection(s('Approvals'), Icons.inbox_outlined, Icons.inbox_rounded),
        mobileTabForSection(s('Attendance'), Icons.schedule_outlined, Icons.schedule_rounded),
        mobileTabForSection(s('Payroll'), Icons.payments_outlined, Icons.payments_rounded),
      ],
      child: framed,
    );
  }
}
