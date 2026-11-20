import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/color_theme_notifier.dart';
import '../models/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/mobile_ui.dart';
import 'breadcrumb_bar.dart' show BreadcrumbSection;
import 'logout_action.dart';
import 'mobile_shell.dart' show mobileTitleFor;
import 'notification_bell_button.dart';
import 'profile_avatar_button.dart';
import 'quick_actions_bar.dart';
import 'report_problem_button.dart';

/// One menu entry.
class NavEntry {
  final String label;
  final IconData icon;
  final String route;
  /// Other pages that belong to this entry (Check in / out under
  /// Attendance), matched with everything below them.
  final List<String> alsoMatches;
  const NavEntry(this.label, this.icon, this.route, {this.alsoMatches = const []});
}

/// A run of menu entries: under a small heading, or (collapsible) behind a
/// header that opens and closes. A collapsible group opens by itself when
/// the page shown is one of its entries.
class NavGroupSpec {
  final String? title;
  final IconData? icon;
  final bool collapsible;
  final List<NavEntry> items;
  const NavGroupSpec({this.title, this.icon, this.collapsible = false, required this.items});
}

/// The route of the menu entry for [location]: an exact match, or else the
/// longest entry the location sits under (so Apply leave keeps "Leave" lit).
String? activeNavRoute(String location, List<NavGroupSpec> groups) {
  String? best;
  var bestLen = 0;
  for (final g in groups) {
    for (final e in g.items) {
      if (location == e.route) return e.route;
      for (final p in [e.route, ...e.alsoMatches]) {
        if ((location == p || location.startsWith('$p/')) && p.length > bestLen) {
          best = e.route;
          bestLen = p.length;
        }
      }
    }
  }
  return best;
}

/// Lets a page know it is inside the desktop layout (approved redesign,
/// 20 Nov 2026), where the top bar already names the page.
class DesktopChrome extends InheritedWidget {
  const DesktopChrome({super.key, required super.child});

  static bool active(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopChrome>() != null;

  @override
  bool updateShouldNotify(DesktopChrome oldWidget) => false;
}

/// The computer layout shared by every role (approved 20 Nov 2026), in the
/// style of the phone redesign.
///
/// Before: a dark gradient bar, a breadcrumb row and a menu that stayed
/// hidden behind ☰ even on a wide screen, so every move meant opening it.
/// Now the menu stays open on the left (white, grouped as each role's menu
/// already was) and one white bar names the page, with report a problem,
/// notifications and who is signed in.
class DesktopShellScaffold extends StatelessWidget {
  final Widget child;
  final String location;
  final String homeRoute;
  final String notificationsRoute;
  final List<BreadcrumbSection> sections;
  final List<NavGroupSpec> groups;
  /// Announcements / holidays / birthdays as icons in the bar, for roles
  /// whose home page does not show them.
  final bool showQuickIcons;
  /// The person's role, under their name in the bar.
  final String roleLabel;

  const DesktopShellScaffold({
    super.key,
    required this.child,
    required this.location,
    required this.homeRoute,
    required this.notificationsRoute,
    required this.sections,
    required this.groups,
    this.showQuickIcons = true,
    this.roleLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = MediaQuery.of(context).size.width >= 1100 ? 248.0 : 220.0;
    return ListenableBuilder(
      listenable: colorThemeNotifier,
      builder: (context, _) => Scaffold(
        backgroundColor: AppTheme.pageBackground,
        body: Row(children: [
          Container(
            width: sidebarWidth,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: MobileUi.line)),
            ),
            child: AppSidebar(groups: groups, location: location, homeRoute: homeRoute),
          ),
          Expanded(
            child: Column(children: [
              _TopBar(
                location: location,
                homeRoute: homeRoute,
                notificationsRoute: notificationsRoute,
                sections: sections,
                showQuickIcons: showQuickIcons,
                roleLabel: roleLabel,
              ),
              Expanded(child: DesktopChrome(child: child)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String location;
  final String homeRoute;
  final String notificationsRoute;
  final List<BreadcrumbSection> sections;
  final bool showQuickIcons;
  final String roleLabel;
  const _TopBar({
    required this.location,
    required this.homeRoute,
    required this.notificationsRoute,
    required this.sections,
    required this.showQuickIcons,
    required this.roleLabel,
  });

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];

  @override
  Widget build(BuildContext context) {
    final atHome = location == homeRoute;
    final now = DateTime.now();
    final first = UserSession.name.trim().split(' ').first;
    final greeting = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
    final title = atHome && first.isNotEmpty ? '$greeting, $first' : mobileTitleFor(location, sections, homeRoute);

    // The menu section this page sits under, as a link back to it.
    BreadcrumbSection? parent;
    for (final s in sections) {
      if (location != s.route && location.startsWith('${s.route}/') &&
          (parent == null || s.route.length > parent.route.length)) {
        parent = s;
      }
    }

    const muted = TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w500);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: MobileUi.line)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3,
                  color: AppTheme.textPrimary)),
        ),
        if (atHome)
          Text('${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}', style: muted)
        else if (parent != null)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => context.go(parent!.route),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.arrow_back_rounded, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(parent.label, style: muted),
              ]),
            ),
          ),
        const SizedBox(width: 8),
        if (showQuickIcons) ...[
          const QuickActionIcons(onLight: true),
          const SizedBox(width: 4),
        ],
        ReportProblemButton(color: AppTheme.textSecondary),
        NotificationBellButton(notificationsRoute: notificationsRoute, color: AppTheme.textSecondary),
        Container(
          margin: const EdgeInsets.only(left: 10),
          padding: const EdgeInsets.only(left: 14),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: MobileUi.line))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const ProfileAvatarButton(light: true),
            if (MediaQuery.of(context).size.width >= 1000) ...[
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(UserSession.name,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text(
                      [
                        if (UserSession.employeeId.isNotEmpty) UserSession.employeeId,
                        if (roleLabel.isNotEmpty) roleLabel,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// The menu: on the left of the computer layout, and in the phone's "More"
/// sheet and drawer ([inSheet]: closes itself when an entry is chosen).
class AppSidebar extends StatefulWidget {
  final List<NavGroupSpec> groups;
  final String location;
  final String homeRoute;
  final bool inSheet;
  const AppSidebar({
    super.key,
    required this.groups,
    required this.location,
    required this.homeRoute,
    this.inSheet = false,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final Set<String> _open = {};

  @override
  void initState() {
    super.initState();
    _openActive();
  }

  @override
  void didUpdateWidget(AppSidebar old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location) _openActive();
  }

  void _openActive() {
    final active = activeNavRoute(widget.location, widget.groups);
    for (final g in widget.groups) {
      if (g.collapsible && g.title != null && g.items.any((e) => e.route == active)) {
        _open.add(g.title!);
      }
    }
  }

  void _go(String route) {
    final router = GoRouter.of(context);
    if (widget.inSheet) Navigator.of(context).pop();
    router.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final active = activeNavRoute(widget.location, widget.groups);
    return Material(
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, widget.inSheet ? 14 : 20, 16, 10),
          child: Row(children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _go(widget.homeRoute),
              child: Image.asset('assets/images/fomra_logo.png',
                  height: 26, fit: BoxFit.contain, filterQuality: FilterQuality.high),
            ),
          ]),
        ),
        if (widget.inSheet && UserSession.name.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 6),
            child: Text(UserSession.name,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            children: [
              for (final g in widget.groups) ..._group(g, active),
            ],
          ),
        ),
        const Divider(height: 1, color: MobileUi.line),
        _Tile(
          icon: Icons.logout_rounded,
          label: 'Sign out',
          selected: false,
          onTap: () => performLogout(context),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }

  List<Widget> _group(NavGroupSpec g, String? active) {
    if (g.collapsible && g.title != null) {
      final open = _open.contains(g.title);
      return [
        _Tile(
          icon: g.icon ?? Icons.folder_rounded,
          label: g.title!,
          selected: false,
          trailing: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18, color: AppTheme.textSecondary),
          onTap: () => setState(() => open ? _open.remove(g.title) : _open.add(g.title!)),
        ),
        if (open)
          for (final e in g.items)
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: _Tile(
                icon: e.icon,
                label: e.label,
                selected: e.route == active,
                small: true,
                onTap: () => _go(e.route),
              ),
            ),
      ];
    }
    return [
      if (g.title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
          child: Text(g.title!.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7,
                  color: AppTheme.textSecondary)),
        ),
      for (final e in g.items)
        _Tile(icon: e.icon, label: e.label, selected: e.route == active, onTap: () => _go(e.route)),
    ];
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool small;
  final Widget? trailing;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.small = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primaryBlue : const Color(0xFF334155);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? AppTheme.primaryBlue.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: small ? 36 : 40,
            child: Row(children: [
              const SizedBox(width: 10),
              Icon(icon, size: small ? 18 : 20, color: selected ? AppTheme.primaryBlue : AppTheme.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: small ? 13 : 13.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: color)),
              ),
              if (trailing != null) trailing!,
              const SizedBox(width: 8),
            ]),
          ),
        ),
      ),
    );
  }
}
