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

// Sub-item used inside expandable groups
typedef _SubItem = ({String label, IconData icon, String route});

const _editFormItems = <_SubItem>[
  (label: 'Edit Leave Form',      icon: Icons.event_available_rounded,  route: '/edit-leave-form'),
  (label: 'Edit Permission Form', icon: Icons.access_time_rounded,      route: '/edit-leave-form'),
  (label: 'Edit Comp Off Form',   icon: Icons.swap_horiz_rounded,       route: '/edit-leave-form'),
  (label: 'Edit Interview Form',  icon: Icons.assignment_rounded,       route: '/edit-form'),
  (label: 'Edit Onboarding Form', icon: Icons.how_to_reg_rounded,       route: '/edit-onboarding-form'),
  (label: 'Edit Maintenance Form', icon: Icons.build_rounded,           route: '/edit-maintenance-form'),
  (label: 'Location Management',   icon: Icons.location_on_rounded,     route: '/location-management'),
];

const _navItems = [
  _NavItem('Dashboard', Icons.dashboard_rounded, '/dashboard'),
  _NavItem('Employee Management', Icons.people_rounded, '/employee-management'),
  _NavItem('Attendance Management', Icons.access_time_rounded, '/attendance-management'),
  _NavItem('Leave Management', Icons.event_available_rounded, '/leave-management'),
  _NavItem('Approvals',        Icons.approval_rounded,        '/hr/approvals'),
  _NavItem('Staff Portal Approvals', Icons.cleaning_services_rounded, '/leave/staff-portal-approvals'),
  _NavItem('Task Management', Icons.task_alt_rounded, '/task-management'),
  _NavItem('Appraisals', Icons.fact_check_rounded, '/appraisals'),
  _NavItem('Payroll Management', Icons.account_balance_wallet_rounded, '/payroll-management'),
  _NavItem('Interview Process', Icons.record_voice_over_rounded, '/interview-process'),
  _NavItem('Employee Onboarding', Icons.how_to_reg_rounded, '/employee-onboarding'),
  _NavItem('Lead Management', Icons.leaderboard_rounded, '/lead-management'),
  _NavItem('Maintenance Management', Icons.build_rounded, '/maintenance-management'),
  _NavItem('KRA', Icons.flag_rounded, '/kra-management'),
  _NavItem('Notifications', Icons.notifications_rounded, '/notifications'),
  _NavItem('Reports & Analytics', Icons.bar_chart_rounded, '/reports-analytics'),
];

const _personalNavItems = [
  _NavItem('My Profile',    Icons.person_rounded,                 '/hr/my-profile'),
  _NavItem('My Attendance and Leaves', Icons.event_note_rounded,  '/hr/attendance-leaves'),
  _NavItem('My Tasks',      Icons.task_alt_rounded,               '/hr/my-tasks'),
  _NavItem('My Payslips',   Icons.account_balance_wallet_rounded, '/hr/my-payslips'),
  _NavItem('Appraisal',     Icons.fact_check_rounded,             '/hr/appraisal'),
  _NavItem('Maintenance',   Icons.build_rounded,                  '/hr/maintenance-management'),
];

// Shown only when UserSession.isReportingManager — HR can also be flagged
// as a Reporting Manager (see reporting-manager-overhaul), and previously
// had none of an RM's team-facing views. Mirrors manager_shell.dart's
// equivalent items.
const _myTeamNavItems = [
  _NavItem('Team Leave Approvals', Icons.group_rounded,       '/hr/leave/team-approvals'),
  _NavItem('Interview Review',     Icons.rate_review_rounded, '/hr/interview-review'),
  _NavItem('Appraisal Received',   Icons.fact_check_rounded,  '/hr/appraisal-received'),
];

List<BreadcrumbSection> get _breadcrumbSections =>
    [..._navItems, ..._personalNavItems, ..._myTeamNavItems]
        .map((e) => (label: e.label, route: e.route))
        .toList();

class AppShell extends StatelessWidget {
  final Widget child;
  final String location;

  const AppShell({super.key, required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 700;
    if (isWide) {
      return _WideLayout(child: child, location: location);
    }
    return _NarrowLayout(child: child, location: location);
  }
}

// ── Wide layout (web): permanent left sidebar ──────────────────────────────
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
            homeRoute: '/dashboard',
            notificationsRoute: '/notifications',
            hideProfile: widget.location == '/dashboard',
          ),
          BreadcrumbBar(
            location: widget.location,
            homeRoute: '/dashboard',
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

// ── Narrow layout (mobile): hamburger + drawer ─────────────────────────────
class _NarrowLayout extends StatelessWidget {
  final Widget child;
  final String location;
  const _NarrowLayout({required this.child, required this.location});

  String get _currentTitle {
    final item = _navItems.firstWhere(
      (i) => i.route == location,
      orElse: () => _navItems.first,
    );
    return item.label;
  }

  @override
  Widget build(BuildContext context) {
    // The dashboard already shows a large, functional profile avatar in the
    // WelcomeBanner below — repeating it here would be a second, redundant
    // profile icon on screen at once.
    final hideProfile = location == '/dashboard';
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
              notificationsRoute: '/notifications',
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
        drawer: Drawer(
          child: _DrawerContent(location: location),
        ),
        body: Column(children: [
          BreadcrumbBar(location: location, homeRoute: '/dashboard', sections: _breadcrumbSections),
          Expanded(child: QuickActionsBody(child: child)),
        ]),
      ),
    );
  }
}

// ── Sidebar widget ─────────────────────────────────────────────────────────
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
                children: [
                  ..._navItems.map((item) {
                    final selected = location == item.route;
                    return _SidebarTile(item: item, selected: selected);
                  }),
                  if (UserSession.isReportingManager) ...[
                    const _SectionDivider(label: 'My Team'),
                    ..._myTeamNavItems.map((item) => _SidebarTile(item: item, selected: location == item.route)),
                  ],
                  const _SectionDivider(label: 'Edit Forms'),
                  _ExpandableNavGroup(
                    label: 'Edit Forms',
                    icon: Icons.edit_note_rounded,
                    items: _editFormItems,
                    location: location,
                  ),
                  const _SectionDivider(label: 'My Space'),
                  ..._personalNavItems.map((item) {
                    final selected = location == item.route ||
                        location.startsWith('${item.route}/');
                    return _SidebarTile(item: item, selected: selected);
                  }),
                ],
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
      decoration: BoxDecoration(
        color: AppTheme.primaryBlueDark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go('/dashboard'),
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
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.accentBlue,
                  child: const Icon(Icons.person, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        UserSession.name.isNotEmpty ? UserSession.name : 'HR Admin',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text('HR Administrator', style: TextStyle(color: AppTheme.sidebarMuted, fontSize: 11)),
                    ],
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

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final bool closeDrawer;
  const _SidebarTile({required this.item, required this.selected, this.closeDrawer = false});

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
        leading: Icon(
          item.icon,
          color: selected ? Colors.white : AppTheme.sidebarMuted,
          size: 20,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.sidebarMuted,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selectedTileColor: AppTheme.sidebarSelectedBg,
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
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => performLogout(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(Icons.logout_rounded, color: AppTheme.sidebarMuted, size: 18),
            const SizedBox(width: 10),
            Text('Sign Out', style: TextStyle(color: AppTheme.sidebarMuted, fontSize: 13)),
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

  @override
  void initState() {
    super.initState();
    // Auto-expand if any child route is active
    _expanded = widget.items.any((i) => widget.location == i.route);
  }

  @override
  void didUpdateWidget(_ExpandableNavGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      final active = widget.items.any((i) => widget.location == i.route);
      if (active && !_expanded) setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Group header
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

      // Sub-items
      if (_expanded)
        ...widget.items.map((item) {
          final selected = widget.location == item.route;
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
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal)),
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

// ── Drawer for mobile ──────────────────────────────────────────────────────
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
              children: [
                ..._navItems.map((item) {
                  final selected = location == item.route;
                  return _SidebarTile(
                      item: item, selected: selected, closeDrawer: true);
                }),
                if (UserSession.isReportingManager) ...[
                  const _SectionDivider(label: 'My Team'),
                  ..._myTeamNavItems.map((item) => _SidebarTile(
                      item: item, selected: location == item.route, closeDrawer: true)),
                ],
                const _SectionDivider(label: 'Edit Forms'),
                _ExpandableNavGroup(
                  label: 'Edit Forms',
                  icon: Icons.edit_note_rounded,
                  items: _editFormItems,
                  location: location,
                  closeDrawer: true,
                ),
                const _SectionDivider(label: 'My Space'),
                ..._personalNavItems.map((item) {
                  final selected = location == item.route;
                  return _SidebarTile(
                      item: item, selected: selected, closeDrawer: true);
                }),
              ],
            ),
          ),
          _SidebarFooter(),
        ],
      ),
    );
  }
}
