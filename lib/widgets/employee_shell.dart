import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_session.dart';
import '../theme/app_theme.dart';
import '../models/color_theme_notifier.dart';
import 'breadcrumb_bar.dart';
import 'logout_action.dart';
import 'shell_top_bar.dart';
import 'quick_actions_bar.dart';
import 'notification_bell_button.dart';
import 'profile_avatar_button.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.label, this.icon, this.route);
}

const _baseEmpNavItems = [
  _NavItem('Dashboard',            Icons.dashboard_rounded,               '/employee/dashboard'),
  _NavItem('My Profile',           Icons.person_rounded,                  '/employee/profile'),
  _NavItem('My Attendance and Leaves', Icons.event_note_rounded,          '/employee/attendance-leaves'),
  // Leave Balance, Permission and Comp Off were all live routes with no
  // nav entry — reachable only by typing the URL, despite "how much leave
  // do I have left?" being the most common reason to open the app at all.
  _NavItem('My Leave Balance',     Icons.account_balance_wallet_rounded,  '/employee/leave/balance'),
  _NavItem('Apply Permission',     Icons.schedule_rounded,                '/employee/leave/permission'),
  _NavItem('Apply Comp Off',       Icons.swap_horiz_rounded,              '/employee/leave/compoff'),
  _NavItem('Apply On Duty',        Icons.work_history_rounded,            '/employee/on-duty'),
  _NavItem('My Payslips',          Icons.receipt_long_rounded,            '/employee/payslips'),
  _NavItem('My Tasks',             Icons.task_alt_rounded,                '/employee/tasks'),
  _NavItem('Appraisal',            Icons.fact_check_rounded,              '/employee/appraisal'),
  _NavItem('My Journey',           Icons.timeline_rounded,                '/employee/my-journey'),
  _NavItem('Maintenance',          Icons.build_rounded,                   '/employee/maintenance-management'),
  _NavItem('My Notifications',     Icons.notifications_rounded,           '/employee/notifications'),
];

// Extra "My Team" nav for anyone flagged isReportingManager, even if their
// role isn't Manager (see reporting-manager-overhaul).
const _myTeamNavItems = [
  _NavItem('My Team',              Icons.groups_rounded,                  '/employee/my-team/records'),
  _NavItem('Team Leave Approvals', Icons.event_available_rounded,         '/employee/my-team/leave-approvals'),
  _NavItem('Interview Review',     Icons.rate_review_rounded,             '/employee/my-team/interview-review'),
  _NavItem('Appraisal Received',   Icons.fact_check_rounded,              '/employee/my-team/appraisal-received'),
];

List<_NavItem> get _empNavItems => [
      ..._baseEmpNavItems,
      if (UserSession.isReportingManager) ..._myTeamNavItems,
    ];

List<BreadcrumbSection> get _breadcrumbSections =>
    _empNavItems.map((e) => (label: e.label, route: e.route)).toList();

class EmployeeShell extends StatelessWidget {
  final Widget child;
  final String location;
  const EmployeeShell({super.key, required this.child, required this.location});

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
            homeRoute: '/employee/dashboard',
            notificationsRoute: '/employee/notifications',
            hideProfile: widget.location == '/employee/dashboard',
          ),
          BreadcrumbBar(
            location: widget.location,
            homeRoute: '/employee/dashboard',
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
    final item = _empNavItems.firstWhere(
      (i) => i.route == location,
      orElse: () => _empNavItems.first,
    );
    return item.label;
  }

  @override
  Widget build(BuildContext context) {
    // The dashboard already shows a large, functional profile avatar in the
    // WelcomeBanner below — repeating it here would be a second, redundant
    // profile icon on screen at once.
    final hideProfile = location == '/employee/dashboard';
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
              notificationsRoute: '/employee/notifications',
              color: Colors.white,
            ),
            if (!hideProfile) ...[
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: ProfileAvatarButton(),
              ),
            ] else
              const SizedBox(width: 12),
          ],
        ),
        drawer: Drawer(child: _DrawerContent(location: location)),
        body: Column(children: [
          BreadcrumbBar(location: location, homeRoute: '/employee/dashboard', sections: _breadcrumbSections),
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
                children: _empNavItems.map((item) {
                  final selected = location == item.route ||
                      location.startsWith('${item.route}/');
                  return _SidebarTile(item: item, selected: selected);
                }).toList(),
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
      decoration: BoxDecoration(color: AppTheme.primaryBlueDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go('/employee/dashboard'),
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
                backgroundColor: AppTheme.accentBlue,
                child: const Icon(Icons.person, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        UserSession.name.isNotEmpty ? UserSession.name : 'Employee',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text('Staff Member',
                        style:
                            TextStyle(color: AppTheme.sidebarMuted, fontSize: 11)),
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
            color: selected ? Colors.white : AppTheme.sidebarMuted, size: 20),
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
          if (closeDrawer) Navigator.of(context).pop();
          context.go(item.route);
        },
      ),
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
              children: _empNavItems.map((item) {
                final selected = location == item.route;
                return _SidebarTile(
                    item: item, selected: selected, closeDrawer: true);
              }).toList(),
            ),
          ),
          _SidebarFooter(),
        ],
      ),
    );
  }
}
