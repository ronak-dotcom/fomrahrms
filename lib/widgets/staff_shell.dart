import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/staff_strings.dart';
import '../models/language_notifier.dart';
import '../models/user_session.dart';
import '../theme/app_theme.dart';
import 'fomra_logo.dart';
import 'logout_action.dart';
import 'report_problem_button.dart';

class _StaffTab {
  final String labelKey;   // sidebar / bottom-nav label
  final String titleKey;   // top bar page heading (more specific, e.g. "Apply Leave")
  final IconData icon;
  final String route;
  const _StaffTab(this.labelKey, this.titleKey, this.icon, this.route);
}

const _staffTabs = [
  _StaffTab('tab_home',       'tab_home',         Icons.home_rounded,        '/staff/home'),
  _StaffTab('tab_leave',      'apply_leave',       Icons.event_busy_rounded,  '/staff/leave'),
  _StaffTab('tab_permission', 'apply_permission',  Icons.access_time_rounded, '/staff/permission'),
  _StaffTab('tab_profile',    'my_profile',        Icons.person_rounded,      '/staff/profile'),
];

const _wideBreakpoint = 900.0;

/// Shell for Housekeeping/Support Staff: a fixed left sidebar + top bar on
/// desktop-width screens, falling back to the original bottom-tab-bar
/// layout on phones/narrow windows where staff actually check in.
///
/// Also owns the Staff Portal's language switcher (English/Hindi/Tamil) —
/// the choice persists per employee (see LanguageNotifier) so it's only
/// picked once, and can be changed anytime from the globe icon here.
class StaffShell extends StatelessWidget {
  final Widget child;
  final String location;
  const StaffShell({super.key, required this.child, required this.location});

  static int _currentIndex(String location) {
    final i = _staffTabs.indexWhere((t) => location.startsWith(t.route));
    return i == -1 ? 0 : i;
  }

  static Future<void> _logout(BuildContext context) =>
      performLogout(context, extraReset: staffLanguageNotifier.reset);

  static Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(st('logout_title')),
        content: Text(st('logout_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(st('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error, foregroundColor: Colors.white),
            child: Text(st('log_out')),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) _logout(context);
  }

  static Future<void> _pickLanguage(BuildContext context) async {
    final picked = await showDialog<AppLanguage>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(st('choose_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final lang in AppLanguage.values)
              RadioListTile<AppLanguage>(
                value: lang,
                groupValue: staffLanguageNotifier.value,
                activeColor: AppTheme.primaryBlue,
                title: Text(languageDisplayName(lang),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(st('cancel'))),
        ],
      ),
    );
    if (picked != null) staffLanguageNotifier.setLanguage(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: staffLanguageNotifier,
      builder: (context, _) {
        final isWide = MediaQuery.of(context).size.width >= _wideBreakpoint;
        return isWide ? _WideLayout(child: child, location: location) : _NarrowLayout(child: child, location: location);
      },
    );
  }
}

// ── Wide (desktop) layout: fixed sidebar + top bar ─────────────────────────

class _WideLayout extends StatelessWidget {
  final Widget child;
  final String location;
  const _WideLayout({required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final tab = _staffTabs[StaffShell._currentIndex(location)];
    return Scaffold(
      body: Row(children: [
        _Sidebar(location: location),
        Expanded(
          child: Column(children: [
            _TopBar(titleKey: tab.titleKey),
            Expanded(
              child: Container(
                color: AppTheme.pageBackground,
                child: child,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String location;
  const _Sidebar({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FomraLogoMark(wordmarkSize: 26, showCaption: false),
            const SizedBox(height: 6),
            Text('STAFF PORTAL',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary, letterSpacing: 1.2)),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (int i = 0; i < _staffTabs.length; i++)
                _SidebarTile(
                  icon: _staffTabs[i].icon,
                  label: st(_staffTabs[i].labelKey),
                  selected: i == StaffShell._currentIndex(location),
                  onTap: () {
                    if (i == StaffShell._currentIndex(location)) return;
                    context.go(_staffTabs[i].route);
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Divider(color: AppTheme.borderSubtle, height: 1),
            const SizedBox(height: 12),
            _SidebarTile(
              icon: Icons.bug_report_outlined,
              label: st('report_problem'),
              selected: false,
              onTap: () => showReportProblemDialog(context),
            ),
            _SidebarTile(
              icon: Icons.translate_rounded,
              label: st('language'),
              selected: false,
              onTap: () => StaffShell._pickLanguage(context),
            ),
            _SidebarTile(
              icon: Icons.logout_rounded,
              label: st('log_out'),
              selected: false,
              iconColor: AppTheme.error,
              textColor: AppTheme.error,
              onTap: () => StaffShell._confirmLogout(context),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;
  const _SidebarTile({
    required this.icon, required this.label, required this.selected, required this.onTap,
    this.iconColor, this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppTheme.primaryBlue : (iconColor ?? AppTheme.textSecondary);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: selected ? AppTheme.lightBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? AppTheme.primaryBlue : (textColor ?? AppTheme.textPrimary))),
          ]),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String titleKey;
  const _TopBar({required this.titleKey});

  @override
  Widget build(BuildContext context) {
    final name = UserSession.name.isNotEmpty ? UserSession.name : 'Staff';
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(children: [
        Expanded(child: Text(st(titleKey), style: AppTheme.sectionHeading)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.pageBackground,
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: AppTheme.primaryBlue,
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Text(name, style: AppTheme.bodyText.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}

// ── Narrow (phone) layout: app bar + bottom nav ─────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final Widget child;
  final String location;
  const _NarrowLayout({required this.child, required this.location});

  @override
  Widget build(BuildContext context) {
    final currentIndex = StaffShell._currentIndex(location);
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Row(children: [
          const FomraLogoMark(wordmarkSize: 26, showCaption: false),
          const SizedBox(width: 10),
          Expanded(
            child: Text(UserSession.name.isNotEmpty ? UserSession.name : 'Staff',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: st('report_problem'),
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => showReportProblemDialog(context),
          ),
          IconButton(
            tooltip: st('language'),
            icon: const Icon(Icons.translate_rounded),
            onPressed: () => StaffShell._pickLanguage(context),
          ),
          IconButton(
            tooltip: st('logout_tooltip'),
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => StaffShell._confirmLogout(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(top: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) {
          if (i == currentIndex) return;
          context.go(_staffTabs[i].route);
        },
        destinations: [
          for (final t in _staffTabs)
            NavigationDestination(icon: Icon(t.icon), label: st(t.labelKey)),
        ],
      ),
    );
  }
}
