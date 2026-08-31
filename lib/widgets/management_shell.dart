import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_session.dart';
import '../theme/app_theme.dart';
import '../models/color_theme_notifier.dart';
import 'breadcrumb_bar.dart';
import 'logout_action.dart';
import 'shell_top_bar.dart';
import 'profile_avatar_button.dart';
import 'quick_actions_bar.dart';
import 'notification_bell_button.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.label, this.icon, this.route);
}

typedef _SubItem = ({String label, IconData icon, String route});

class _NavGroup {
  final String label;
  final IconData icon;
  final List<_SubItem> items;
  const _NavGroup(this.label, this.icon, this.items);
}

Color get _mgmtColor => AppTheme.primaryBlueDark;

// Nav is grouped by what someone is trying to DO, rather than the flat
// 21-item list this replaces. That list mixed everything at one level, so
// attendance data sat in four unrelated places, the four kinds of approval
// were scattered across the menu (one of them buried under "Edit Forms"),
// and finding anything meant reading the whole list top to bottom.
//
// Dashboard stays pinned above the groups — it's the landing page and
// shouldn't need a group opened to reach it.
const _dashboardItem =
    _NavItem('Dashboard', Icons.dashboard_rounded, '/management/dashboard');

const _navGroups = <_NavGroup>[
  _NavGroup('Approvals', Icons.approval_rounded, [
    // All four approval queues in one place. Previously: Approvals and Team
    // Leave Approvals were top-level, KRA Approvals was elsewhere in the
    // list, and Form Approvals was hidden inside the Edit Forms submenu —
    // so "what needs my decision?" meant checking four unrelated spots.
    (label: 'All Approvals',       icon: Icons.inbox_rounded,         route: '/management/approvals'),
    (label: 'Leave Approvals',     icon: Icons.event_available_rounded, route: '/management/leave/team-approvals'),
    (label: 'KRA Approvals',       icon: Icons.flag_rounded,          route: '/management/kra-approvals'),
    (label: 'Form Approvals',      icon: Icons.fact_check_rounded,    route: '/management/form-approvals'),
  ]),
  _NavGroup('People', Icons.people_rounded, [
    (label: 'Employee Management', icon: Icons.badge_rounded,          route: '/management/employee-management'),
    (label: 'Employee Onboarding', icon: Icons.how_to_reg_rounded,     route: '/management/employee-onboarding'),
    (label: 'Interview Process',   icon: Icons.record_voice_over_rounded, route: '/management/interview-process'),
    (label: 'Interview Review',    icon: Icons.rate_review_rounded,    route: '/management/interview-review'),
    (label: 'Appraisals',          icon: Icons.workspace_premium_rounded, route: '/management/appraisals'),
    (label: 'KRA',                 icon: Icons.flag_rounded,           route: '/management/kra-management'),
  ]),
  _NavGroup('Time & Attendance', Icons.access_time_rounded, [
    // Late Coming and GPS Tracking are live routes that were missing from
    // the nav entirely — reachable only by typing the URL.
    (label: 'Attendance Records',  icon: Icons.fact_check_rounded,     route: '/management/attendance-management'),
    (label: 'Late Coming',         icon: Icons.watch_later_rounded,    route: '/management/attendance/late-coming'),
    (label: 'GPS Tracking',        icon: Icons.my_location_rounded,    route: '/management/attendance/gps-tracking'),
    (label: 'Location History',    icon: Icons.travel_explore_rounded, route: '/management/location-history'),
    (label: 'Leave Management',    icon: Icons.event_available_rounded, route: '/management/leave-management'),
  ]),
  _NavGroup('Operations', Icons.work_outline_rounded, [
    (label: 'Task Management',     icon: Icons.task_alt_rounded,       route: '/management/task-management'),
    (label: 'Lead Management',     icon: Icons.leaderboard_rounded,    route: '/management/lead-management'),
    (label: 'Maintenance',         icon: Icons.build_rounded,          route: '/management/maintenance-management'),
    (label: 'Payroll Management',  icon: Icons.account_balance_wallet_rounded, route: '/management/payroll-management'),
  ]),
  _NavGroup('Setup', Icons.settings_rounded, [
    (label: 'Administration',      icon: Icons.admin_panel_settings_rounded, route: '/management/administration'),
    (label: 'Location Management', icon: Icons.location_on_rounded,    route: '/management/location-management'),
    (label: 'Settings',            icon: Icons.tune_rounded,           route: '/management/settings'),
  ]),
  _NavGroup('Edit Forms', Icons.edit_note_rounded, [
    (label: 'Edit Leave Form',       icon: Icons.event_available_rounded, route: '/management/edit-leave-form'),
    (label: 'Edit Permission Form',  icon: Icons.access_time_rounded,     route: '/management/edit-leave-form'),
    (label: 'Edit Comp Off Form',    icon: Icons.swap_horiz_rounded,      route: '/management/edit-leave-form'),
    (label: 'Edit Interview Form',   icon: Icons.assignment_rounded,      route: '/management/edit-form'),
    (label: 'Edit Onboarding Form',  icon: Icons.how_to_reg_rounded,      route: '/management/edit-onboarding-form'),
    (label: 'Edit Maintenance Form', icon: Icons.build_rounded,           route: '/management/edit-maintenance-form'),
  ]),
];

// Reports and Notifications stay flat: single destinations that don't
// belong under any group, and both are frequent enough to want one click.
const _flatTailItems = [
  _NavItem('Reports & Analytics', Icons.bar_chart_rounded,     '/management/reports-analytics'),
  _NavItem('Notifications',       Icons.notifications_rounded, '/management/notifications'),
];

// Breadcrumbs resolve a route to a label, so this has to stay a flat list
// of every reachable destination regardless of how the sidebar groups them.
List<BreadcrumbSection> get _breadcrumbSections => [
      (label: _dashboardItem.label, route: _dashboardItem.route),
      for (final g in _navGroups)
        for (final i in g.items) (label: i.label, route: i.route),
      for (final i in _flatTailItems) (label: i.label, route: i.route),
    ];

// Built once and shared by the wide sidebar and the narrow drawer so the two
// can't drift apart — they previously repeated the same list construction.
List<Widget> _buildNavChildren(String location, {required bool closeDrawer}) {
  return [
    _SidebarTile(
      item: _dashboardItem,
      selected: location == _dashboardItem.route,
      closeDrawer: closeDrawer,
    ),
    for (final group in _navGroups)
      _ExpandableNavGroup(
        label: group.label,
        icon: group.icon,
        items: group.items,
        location: location,
        closeDrawer: closeDrawer,
      ),
    const _SectionDivider(label: 'Insights'),
    for (final item in _flatTailItems)
      _SidebarTile(
        item: item,
        selected: location == item.route || location.startsWith('${item.route}/'),
        closeDrawer: closeDrawer,
      ),
  ];
}

class ManagementShell extends StatelessWidget {
  final Widget child;
  final String location;
  const ManagementShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    if (isWide) return _WideLayout(child: child, location: location);
    return _NarrowLayout(child: child, location: location);
  }
}

class _WideLayout extends StatefulWidget {
  final Widget child;
  final String location;
  const _WideLayout({required this.child, required this.location});

  @override
  State<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<_WideLayout> {
  // Click pins the sidebar open/closed (original behavior); hovering the
  // hamburger or the sidebar itself previews it open and auto-closes on
  // mouse-leave, independent of the pinned state.
  bool _pinned = false;
  bool _hovering = false;
  Timer? _closeTimer;

  bool get _sidebarOpen => _pinned || _hovering;

  @override
  void didUpdateWidget(_WideLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location && _sidebarOpen) {
      _closeTimer?.cancel();
      setState(() { _pinned = false; _hovering = false; });
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _onHoverEnter() {
    _closeTimer?.cancel();
    if (!_hovering) setState(() => _hovering = true);
  }

  void _onHoverExit() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _hovering = false);
    });
  }

  void _onToggleClick() {
    _closeTimer?.cancel();
    setState(() { _pinned = !_pinned; _hovering = false; });
  }

  void _closeAll() {
    _closeTimer?.cancel();
    setState(() { _pinned = false; _hovering = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ShellTopBar(
            sidebarOpen: _sidebarOpen,
            onToggle: _onToggleClick,
            onSidebarHoverEnter: _onHoverEnter,
            onSidebarHoverExit: _onHoverExit,
            homeRoute: '/management/dashboard',
            notificationsRoute: '/management/notifications',
            hideProfile: widget.location == '/management/dashboard',
          ),
          BreadcrumbBar(
            location: widget.location,
            homeRoute: '/management/dashboard',
            sections: _breadcrumbSections,
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: widget.child),
                IgnorePointer(
                  ignoring: !_sidebarOpen,
                  child: AnimatedOpacity(
                    opacity: _sidebarOpen ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: GestureDetector(
                      onTap: _closeAll,
                      child: Container(color: Colors.black54),
                    ),
                  ),
                ),
                AnimatedSlide(
                  offset: _sidebarOpen ? Offset.zero : const Offset(-1, 0),
                  duration: const Duration(milliseconds: 280),
                  curve: _sidebarOpen ? Curves.easeOut : Curves.easeIn,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MouseRegion(
                      key: const Key('sidebar-panel'),
                      onEnter: (_) => _onHoverEnter(),
                      onExit: (_) => _onHoverExit(),
                      child: SizedBox(
                        width: 260,
                        child: _Sidebar(location: widget.location),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  final Widget child;
  final String location;
  const _NarrowLayout({required this.child, required this.location});

  String get _currentTitle {
    for (final s in _breadcrumbSections) {
      if (s.route == location) return s.label;
    }
    return _dashboardItem.label;
  }

  @override
  Widget build(BuildContext context) {
    // The dashboard already shows a large, functional profile avatar in the
    // WelcomeBanner below — repeating it here would be a second, redundant
    // profile icon on screen at once.
    final hideProfile = location == '/management/dashboard';
    return ListenableBuilder(
      listenable: colorThemeNotifier,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_currentTitle),
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(decoration: BoxDecoration(gradient: AppTheme.headerGradient)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            const NotificationBellButton(
              notificationsRoute: '/management/notifications',
              color: Colors.white,
            ),
            if (!hideProfile) ...[
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: ProfileAvatarButton(),
              ),
            ] else
              const SizedBox(width: 8),
          ],
        ),
        drawer: Drawer(child: _DrawerContent(location: location)),
        body: Column(children: [
          BreadcrumbBar(location: location, homeRoute: '/management/dashboard', sections: _breadcrumbSections),
          Expanded(child: QuickActionsBody(child: child)),
        ]),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String location;
  const _Sidebar({required this.location});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Material(
        color: AppTheme.sidebarBg,
        elevation: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SidebarHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _buildNavChildren(location, closeDrawer: false),
              ),
            ),
            _SidebarFooter(),
          ],
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      decoration: BoxDecoration(color: _mgmtColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go('/management/dashboard'),
            child: SizedBox(
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerLeft,
                // The light variant: the sidebar is primaryBlueDark, and the
                // wordmark is near-black (#231F20), which all but disappears
                // against it. Only the text is recoloured — the blue swoosh is
                // the brand colour and reads fine on dark.
                child: Image.asset('assets/images/fomra_logo_light.png',
                    height: 110, fit: BoxFit.contain,
                    filterQuality: FilterQuality.high),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primaryBlue,
                child: const Icon(Icons.person, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UserSession.name.isNotEmpty ? UserSession.name : 'Management',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    Text('Management',
                        style: TextStyle(color: AppTheme.sidebarMuted, fontSize: 11)),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final bool closeDrawer;
  const _SidebarTile(
      {required this.item, required this.selected, this.closeDrawer = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? AppTheme.sidebarSelectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(item.icon,
            color: selected ? Colors.white : AppTheme.sidebarMuted,
            size: 20),
        title: Text(
          item.label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.sidebarMuted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          final router = GoRouter.of(context);
          if (closeDrawer) Navigator.of(context).pop();
          router.go(item.route);
        },
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        const Expanded(child: Divider(color: Colors.white12, height: 1)),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                color: Color(0xFF6B7280), fontSize: 10, letterSpacing: 1)),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: Colors.white12, height: 1)),
      ]),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12))),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => performLogout(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(Icons.logout_rounded, color: AppTheme.sidebarMuted, size: 18),
            const SizedBox(width: 10),
            Text('Sign Out',
                style: TextStyle(color: AppTheme.sidebarMuted, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

// ── Expandable nav group ───────────────────────────────────────────────────
class _ExpandableNavGroup extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<_SubItem> items;
  final String location;
  final bool closeDrawer;
  const _ExpandableNavGroup({
    required this.label,
    required this.icon,
    required this.items,
    required this.location,
    this.closeDrawer = false,
  });

  @override
  State<_ExpandableNavGroup> createState() => _ExpandableNavGroupState();
}

class _ExpandableNavGroupState extends State<_ExpandableNavGroup> {
  late bool _expanded;

  // Sub-pages (e.g. /management/employee-management/add) should still count
  // as "inside this group", otherwise opening a detail page collapses the
  // group and loses the sense of where you are.
  static bool _matches(String location, String route) =>
      location == route || location.startsWith('$route/');

  bool get _hasActiveItem =>
      widget.items.any((i) => _matches(widget.location, i.route));

  @override
  void initState() {
    super.initState();
    _expanded = _hasActiveItem;
  }

  @override
  void didUpdateWidget(_ExpandableNavGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      if (_hasActiveItem && !_expanded) setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: _expanded ? Colors.white10 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(widget.icon,
              color: _expanded ? Colors.white : AppTheme.sidebarMuted,
              size: 20),
          title: Text(widget.label,
              style: TextStyle(
                  color: _expanded ? Colors.white : AppTheme.sidebarMuted,
                  fontSize: 13,
                  fontWeight: _expanded ? FontWeight.w600 : FontWeight.normal)),
          trailing: Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: AppTheme.sidebarMuted,
              size: 18),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
      ),
      if (_expanded)
        ...widget.items.map((item) {
          final selected = _matches(widget.location, item.route);
          return Container(
            margin: const EdgeInsets.only(left: 20, right: 8, bottom: 2),
            decoration: BoxDecoration(
              color: selected ? AppTheme.sidebarSelectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(item.icon,
                  color: selected ? Colors.white : AppTheme.sidebarMuted,
                  size: 17),
              title: Text(item.label,
                  style: TextStyle(
                      color: selected ? Colors.white : AppTheme.sidebarMuted,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onTap: () {
                if (widget.closeDrawer) Navigator.of(context).pop();
                GoRouter.of(context).go(item.route);
              },
            ),
          );
        }),
    ]);
  }
}

class _DrawerContent extends StatelessWidget {
  final String location;
  const _DrawerContent({required this.location});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SidebarHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _buildNavChildren(location, closeDrawer: true),
            ),
          ),
          _SidebarFooter(),
        ],
      ),
    );
  }
}
