import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/mobile_ui.dart';
import 'breadcrumb_bar.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// One screen inside a menu section, shown as a tab across the top.
class SectionTab {
  final String label;
  final String route;
  /// The page title (top bar, breadcrumbs); [label] when not given.
  final String? title;
  /// Other routes that belong to this tab (sub-pages, older links).
  final List<String> alsoMatches;
  const SectionTab(this.label, this.route, {this.title, this.alsoMatches = const []});

  String get pageTitle => title ?? label;

  /// How closely [location] belongs to this tab: the length of the matching
  /// route, 0 for none.
  int matchLength(String location) {
    var best = 0;
    for (final p in [route, ...alsoMatches]) {
      if ((location == p || location.startsWith('$p/')) && p.length > best) best = p.length;
    }
    return best;
  }
}

/// A menu section: one entry in the menu, its screens as tabs
/// (Management redesign, Ronak, 20 Nov 2026).
class SectionSpec {
  final String label;
  final IconData icon;
  final List<SectionTab> tabs;
  const SectionSpec(this.label, this.icon, this.tabs);

  String get route => tabs.first.route;
  List<String> get allRoutes => [for (final t in tabs) ...[t.route, ...t.alsoMatches]];
}

/// The section and tab [location] belongs to, if any.
({SectionSpec section, SectionTab tab})? sectionFor(String location, List<SectionSpec> sections) {
  ({SectionSpec section, SectionTab tab})? best;
  var bestLen = 0;
  for (final s in sections) {
    for (final t in s.tabs) {
      final n = t.matchLength(location);
      if (n > bestLen) {
        best = (section: s, tab: t);
        bestLen = n;
      }
    }
  }
  return best;
}

/// Puts the section's tabs above [child] when [location] is one of a
/// section's screens and the section has more than one.
class SectionTabsFrame extends StatelessWidget {
  final List<SectionSpec> sections;
  final String location;
  final Widget child;
  const SectionTabsFrame({super.key, required this.sections, required this.location, required this.child});

  @override
  Widget build(BuildContext context) {
    final hit = sectionFor(location, sections);
    if (hit == null || hit.section.tabs.length < 2) return child;
    return Column(children: [
      SectionTabStrip(tabs: hit.section.tabs, active: hit.tab),
      Expanded(child: child),
    ]);
  }
}

class SectionTabStrip extends StatelessWidget {
  final List<SectionTab> tabs;
  final SectionTab active;
  const SectionTabStrip({super.key, required this.tabs, required this.active});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: MobileUi.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: wide ? 20 : 8),
        child: Row(children: [
          for (final t in tabs) _tab(context, t, identical(t, active)),
        ]),
      ),
    );
  }

  Widget _tab(BuildContext context, SectionTab t, bool selected) => InkWell(
        onTap: selected ? null : () => context.go(t.route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppTheme.primaryBlue : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Text(
            t.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppTheme.primaryBlue : AppTheme.textSecondary,
            ),
          ),
        ),
      );
}

/// The menu for a set of sections: one entry each (lit for any of its
/// tabs), then [more] as a collapsible group.
List<NavGroupSpec> navGroupsForSections(List<SectionSpec> sections, {List<NavEntry> more = const []}) => [
      NavGroupSpec(items: [
        for (final s in sections)
          NavEntry(s.label, s.icon, s.route, alsoMatches: s.allRoutes.skip(1).toList()),
      ]),
      if (more.isNotEmpty)
        NavGroupSpec(title: 'More', icon: Icons.more_horiz_rounded, collapsible: true, items: more),
    ];

/// Page titles for every destination, for the top bar and breadcrumbs.
List<BreadcrumbSection> titlesForSections(List<SectionSpec> sections,
        {List<NavEntry> more = const [], List<BreadcrumbSection> others = const []}) =>
    [
      for (final s in sections)
        for (final t in s.tabs) (label: t.pageTitle, route: t.route),
      for (final e in more) (label: e.label, route: e.route),
      ...others,
    ];

/// A phone bottom-bar tab for a section.
MobileTab mobileTabForSection(SectionSpec s, IconData icon, IconData selected) =>
    MobileTab(s.label, icon, s.route, selectedIcon: selected, alsoMatches: s.allRoutes);
