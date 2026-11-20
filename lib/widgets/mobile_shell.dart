import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/color_theme_notifier.dart';
import '../theme/app_theme.dart';
import 'breadcrumb_bar.dart' show BreadcrumbSection;
import 'notification_bell_button.dart';
import 'profile_avatar_button.dart';
import 'quick_actions_bar.dart';
import 'report_problem_button.dart';

/// The phone layout shared by every role (approved redesign, 19 Nov 2026).
///
/// It replaces four stacked bands — a gradient title bar, a breadcrumb row,
/// a strip of four icons and the page's own repeated title — which took
/// about a third of a phone screen before any content and cut long titles
/// off ("My Pay…"). Now there is one white bar: back (or the menu), the
/// page's real name, report a problem, notifications and the profile. The
/// title was previously looked up in the menu list and fell back to
/// "Dashboard", so Check Out and Apply Leave both said "Dashboard".
///
/// With [tabs] (employees), a bottom navigation bar gives one-tap access to
/// the main areas and "More" opens the full menu.
class MobileShellScaffold extends StatelessWidget {
  final Widget child;
  final String location;
  final String homeRoute;
  final String notificationsRoute;
  final List<BreadcrumbSection> sections;
  final Widget drawer;
  final List<MobileTab> tabs;

  const MobileShellScaffold({
    super.key,
    required this.child,
    required this.location,
    required this.homeRoute,
    required this.notificationsRoute,
    required this.sections,
    required this.drawer,
    this.tabs = const [],
  });

  int? get _tabIndex {
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].matches(location)) return i;
    }
    return null;
  }

  bool get _isTabRoot => tabs.any((t) => t.route == location) || location == homeRoute;

  @override
  Widget build(BuildContext context) {
    final hasTabs = tabs.isNotEmpty;
    final atHome = location == homeRoute;
    // With tabs, inner pages get a back arrow and the menu lives under
    // "More"; without tabs the menu button stays and pages keep their own
    // back button.
    final showBack = hasTabs && !_isTabRoot;
    final title = mobileTitleFor(location, sections, homeRoute);
    final tabIndex = _tabIndex;

    return ListenableBuilder(
      listenable: colorThemeNotifier,
      builder: (context, _) => MobileChrome(
        providesBack: showBack,
        child: Scaffold(
          backgroundColor: AppTheme.pageBackground,
          drawer: Drawer(child: drawer),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            foregroundColor: AppTheme.textPrimary,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleSpacing: showBack || !hasTabs ? 4 : 16,
            automaticallyImplyLeading: false,
            shape: const Border(bottom: BorderSide(color: Color(0xFFE5E9F2))),
            leading: showBack
                ? IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.canPop() ? context.pop() : context.go(homeRoute),
                  )
                : !hasTabs
                    ? Builder(
                        builder: (ctx) => IconButton(
                          tooltip: 'Menu',
                          icon: const Icon(Icons.menu_rounded),
                          onPressed: () => Scaffold.of(ctx).openDrawer(),
                        ),
                      )
                    : null,
            title: atHome && hasTabs
                ? const _Wordmark()
                : Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Explicit colour: the app theme's AppBar title style is
                    // white, for the old gradient bar.
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2,
                        color: AppTheme.textPrimary)),
            actions: [
              ReportProblemButton(color: AppTheme.textSecondary),
              NotificationBellButton(
                notificationsRoute: notificationsRoute,
                color: AppTheme.textSecondary,
              ),
              const Padding(
                padding: EdgeInsets.only(left: 4, right: 12),
                child: ProfileAvatarButton(light: true),
              ),
            ],
          ),
          body: !hasTabs && atHome
              // Roles without the new Home keep announcements, holidays and
              // birthdays reachable from their dashboard, in a light strip.
              ? Column(children: [
                  const _LightQuickStrip(),
                  Expanded(child: child),
                ])
              : child,
          bottomNavigationBar: hasTabs
              ? NavigationBar(
                  height: 64,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  indicatorColor: AppTheme.primaryBlue.withValues(alpha: 0.10),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  // "More" is highlighted for pages that live in the menu.
                  selectedIndex: tabIndex ?? tabs.length,
                  onDestinationSelected: (i) {
                    if (i == tabs.length) {
                      _openMore(context);
                      return;
                    }
                    if (tabs[i].route != location) context.go(tabs[i].route);
                  },
                  destinations: [
                    for (final t in tabs)
                      NavigationDestination(
                        icon: Icon(t.icon, color: AppTheme.textSecondary),
                        selectedIcon: Icon(t.selectedIcon ?? t.icon, color: AppTheme.primaryBlue),
                        label: t.label,
                      ),
                    NavigationDestination(
                      icon: Icon(Icons.menu_rounded, color: AppTheme.textSecondary),
                      selectedIcon: Icon(Icons.menu_rounded, color: AppTheme.primaryBlue),
                      label: 'More',
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  void _openMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (_, controller) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: PrimaryScrollController(controller: controller, child: drawer),
        ),
      ),
    );
  }
}

class MobileTab {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;
  final String route;
  /// Other routes that belong to this tab (so Apply leave keeps "Leave" lit).
  final List<String> alsoMatches;
  const MobileTab(this.label, this.icon, this.route,
      {this.selectedIcon, this.alsoMatches = const []});

  bool matches(String location) =>
      location == route ||
      alsoMatches.any((p) => location == p || location.startsWith('$p/'));
}

/// Lets a page know the phone header already shows a back arrow, so its own
/// back button can step aside instead of appearing twice.
class MobileChrome extends InheritedWidget {
  final bool providesBack;
  const MobileChrome({super.key, required this.providesBack, required super.child});

  static MobileChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MobileChrome>();

  /// True when the page is on a phone inside the new layout.
  static bool active(BuildContext context) => maybeOf(context) != null;

  @override
  bool updateShouldNotify(MobileChrome old) => old.providesBack != providesBack;
}

/// Page names for the phone header. Sub-pages that are not menu entries
/// used to fall back to "Dashboard"; these are named here.
const _titleBySuffix = <String, String>{
  '/dashboard': 'Home',
  '/leave/apply': 'Apply leave',
  '/leave/permission': 'Apply permission',
  '/leave/compoff': 'Apply comp off',
  '/leave/balance': 'Leave balance',
  '/leave/approvals': 'My leave requests',
  '/attendance/check-in-out': 'Check in / out',
  '/attendance/check-in': 'Check in',
  '/attendance/check-out': 'Check out',
  '/attendance-leaves': 'Attendance',
  '/attendance-management': 'Attendance',
  '/payslips': 'Payslips',
  '/my-payslips': 'Payslips',
  '/notifications': 'Notifications',
  '/on-duty': 'Apply on duty',
  '/attendance-confirmation': 'Attendance issue',
  '/profile': 'My profile',
  '/my-profile': 'My profile',
  '/my-details': 'My profile',
  '/app-health': 'App health',
};

String mobileTitleFor(String location, List<BreadcrumbSection> sections, String homeRoute) {
  for (final e in _titleBySuffix.entries) {
    if (location.endsWith(e.key)) return e.value;
  }
  BreadcrumbSection? best;
  for (final s in sections) {
    if (location == s.route || location.startsWith('${s.route}/')) {
      if (best == null || s.route.length > best.route.length) best = s;
    }
  }
  if (best != null && best.route == location) return best.label;
  // Deeper than any menu entry: name the last part of the address.
  final last = location.split('/').where((p) => p.isNotEmpty).lastOrNull ?? '';
  if (last.isEmpty) return best?.label ?? 'Home';
  final words = last.replaceAll(RegExp(r'[-_]'), ' ').trim();
  return words.isEmpty ? (best?.label ?? 'Home') : words[0].toUpperCase() + words.substring(1);
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/fomra_logo.png',
        height: 26,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
}

/// The four quick-action icons for roles without the new Home, styled for a
/// white page rather than the old dark band.
class _LightQuickStrip extends StatelessWidget {
  const _LightQuickStrip();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: const Align(alignment: Alignment.centerRight, child: QuickActionIcons(onLight: true)),
      );
}
