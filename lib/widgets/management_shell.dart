import 'package:flutter/material.dart';
import 'breadcrumb_bar.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

// Nav is grouped by what someone is trying to DO, rather than the flat
// 21-item list this replaces. That list mixed everything at one level, so
// attendance data sat in four unrelated places, the four kinds of approval
// were scattered across the menu (one of them buried under "Edit Forms"),
// and finding anything meant reading the whole list top to bottom.
//
// Dashboard stays pinned above the groups — it's the landing page and
// shouldn't need a group opened to reach it.
const _dashboardItem =
    NavEntry('Dashboard', Icons.dashboard_rounded, '/management/dashboard');

/// The decisions, pinned above the groups.
///
/// These four are not repeated in any group. An earlier version pinned them
/// AND left them in an Approvals group, so the sidebar showed "Leave
/// Approvals" twice — which is the confusion this was meant to end.
///
/// Every group starts collapsed, so anything inside one costs two clicks:
/// open the group, then pick the item. For the handful of screens opened
/// daily that is a tax paid every single time. These four are the ones
/// actually reached most — the approvals inbox and the three places a
/// decision is made — so they sit at the top rather than behind a group.
/// They remain in their groups too: someone looking under Approvals should
/// still find them there.
const _pinnedItems = <NavEntry>[
  NavEntry('All Approvals', Icons.inbox_rounded, '/management/approvals'),
  NavEntry('Leave Approvals', Icons.event_available_rounded,
      '/management/leave/team-approvals'),
  NavEntry('Salary Approvals', Icons.request_quote_rounded,
      '/management/salary-approvals'),
  NavEntry('Late Review', Icons.running_with_errors_rounded,
      '/management/late-review'),
];

const _navGroups = <NavGroupSpec>[
  // Five groups, every screen kept. Ordered by how much each is used:
  // the three that carry the daily work first, then personal pages, then
  // More, which holds the modules that have barely been touched.

  // Everything about who came in, when and where.
  NavGroupSpec(title: 'Attendance', icon: Icons.schedule_rounded, collapsible: true, items: [
    NavEntry('Attendance Records', Icons.fact_check_rounded, '/management/attendance-management'),
    NavEntry('Attendance by Date Range', Icons.date_range_rounded, '/management/attendance-range'),
    NavEntry('Leave Records', Icons.event_note_rounded, '/management/leave-management'),
    NavEntry('Late Coming', Icons.more_time_rounded, '/management/attendance/late-coming'),
    NavEntry('Live GPS', Icons.my_location_rounded, '/management/attendance/gps-tracking'),
    NavEntry('Location History', Icons.route_rounded, '/management/location-history'),
  ]),

  // The employee lifecycle and the money that goes with it. Payroll moved
  // here when Payroll & Operations was emptied into More below — it was the
  // only screen in that group with real use.
  NavGroupSpec(title: 'People & Payroll', icon: Icons.groups_rounded, collapsible: true, items: [
    NavEntry('Employees', Icons.badge_rounded, '/management/employee-management'),
    NavEntry('Onboarding', Icons.how_to_reg_rounded, '/management/employee-onboarding'),
    NavEntry('Interviews', Icons.record_voice_over_rounded, '/management/interview-process'),
    NavEntry('Interview Review', Icons.rate_review_rounded, '/management/interview-review'),
    NavEntry('Payroll', Icons.payments_rounded, '/management/payroll-management'),
    NavEntry('Salary Master Sheet', Icons.table_view_rounded, '/management/salary-master-sheet'),
  ]),

  // Configuration. The four form editors used to sit here as well, which
  // made this the longest group in the sidebar for tools opened once at
  // setup. They are now links on the Settings page (_settingsChildItems).
  NavGroupSpec(title: 'Settings', icon: Icons.settings_rounded, collapsible: true, items: [
    NavEntry('Administration', Icons.admin_panel_settings_rounded, '/management/administration'),
    NavEntry('Office Locations', Icons.location_city_rounded, '/management/location-management'),
    NavEntry('Settings & Forms', Icons.tune_rounded, '/management/settings'),
  ]),

  // Management are employees too.
  NavGroupSpec(title: 'My Space', icon: Icons.person_rounded, collapsible: true, items: [
    NavEntry('My Profile', Icons.account_circle_rounded, '/management/my-profile'),
    NavEntry('My Attendance & Leaves', Icons.calendar_month_rounded, '/management/attendance-leaves'),
    NavEntry('My Leave Balance', Icons.account_balance_wallet_rounded, '/management/leave/balance'),
    NavEntry('My Payslips', Icons.receipt_long_rounded, '/management/my-payslips'),
  ]),

  // Modules with almost no use so far: 3 tasks, 2 appraisals, 2 KRA
  // documents and 1 maintenance ticket in the whole database as of
  // November 2026. Kept, every one of them, but out of the groups people
  // open daily. Last of the groups so it reads as the overflow it is.
  NavGroupSpec(title: 'More', icon: Icons.more_horiz_rounded, collapsible: true, items: [
    NavEntry('Tasks', Icons.task_alt_rounded, '/management/task-management'),
    NavEntry('Leads', Icons.contact_phone_rounded, '/management/lead-management'),
    NavEntry('Maintenance', Icons.handyman_rounded, '/management/maintenance-management'),
    NavEntry('Appraisals', Icons.workspace_premium_rounded, '/management/appraisals'),
    NavEntry('KRA', Icons.track_changes_rounded, '/management/kra-management'),
  ]),
];

// Reports and Notifications stay flat: single destinations that don't
// belong under any group, and both are frequent enough to want one click.
const _flatTailItems = [
  NavEntry('Reports & Analytics', Icons.bar_chart_rounded,     '/management/reports-analytics'),
  NavEntry('Notifications',       Icons.notifications_rounded, '/management/notifications'),
  NavEntry('App Health',          Icons.monitor_heart_rounded, '/management/app-health'),
];

/// Reached from the Settings page rather than the sidebar. Listed here so
/// their pages still get a title and a breadcrumb.
const _settingsChildItems = <({String label, String route})>[
  (label: 'Leave, Permission & Comp Off Forms', route: '/management/edit-leave-form'),
  (label: 'Interview Form',   route: '/management/edit-form'),
  (label: 'Onboarding Form',  route: '/management/edit-onboarding-form'),
  (label: 'Maintenance Form', route: '/management/edit-maintenance-form'),
];

// Breadcrumbs resolve a route to a label, so this has to stay a flat list
// of every reachable destination regardless of how the sidebar groups them.
List<BreadcrumbSection> get _breadcrumbSections => [
      (label: _dashboardItem.label, route: _dashboardItem.route),
      // Pinned items included: Salary Approvals sits only here, so without
      // this its page would render with no breadcrumb label.
      for (final i in _pinnedItems) (label: i.label, route: i.route),
      for (final g in _navGroups)
        for (final i in g.items) (label: i.label, route: i.route),
      for (final i in _flatTailItems) (label: i.label, route: i.route),
      for (final i in _settingsChildItems) (label: i.label, route: i.route),
    ];

List<NavGroupSpec> get _groups => [
      const NavGroupSpec(items: [_dashboardItem, ..._pinnedItems]),
      ..._navGroups,
      const NavGroupSpec(title: 'Insights', items: _flatTailItems),
    ];

class ManagementShell extends StatelessWidget {
  final Widget child;
  final String location;
  const ManagementShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    if (isWide) {
      return DesktopShellScaffold(
        location: location,
        homeRoute: '/management/dashboard',
        notificationsRoute: '/management/notifications',
        sections: _breadcrumbSections,
        groups: _groups,
        roleLabel: 'Management',
        child: child,
      );
    }
    return MobileShellScaffold(
      location: location,
      homeRoute: '/management/dashboard',
      notificationsRoute: '/management/notifications',
      sections: _breadcrumbSections,
      drawer: AppSidebar(groups: _groups, location: location, homeRoute: '/management/dashboard', inSheet: true),
      child: child,
    );
  }
}
