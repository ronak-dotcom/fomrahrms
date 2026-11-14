import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/color_theme_notifier.dart';
import '../theme/app_theme.dart';
import 'profile_avatar_button.dart';
import 'quick_actions_bar.dart';
import 'notification_bell_button.dart';
import 'report_problem_button.dart';

class ShellTopBar extends StatelessWidget {
  final bool sidebarOpen;
  final VoidCallback onToggle;
  final String homeRoute;
  final String notificationsRoute;
  final bool hideProfile;
  // Hovering the toggle previews the sidebar open; moving off it (and off
  // the sidebar itself) closes the preview again. onToggle (click) still
  // works as before, independently — it pins the sidebar open/closed.
  final VoidCallback? onSidebarHoverEnter;
  final VoidCallback? onSidebarHoverExit;

  const ShellTopBar({
    super.key,
    required this.sidebarOpen,
    required this.onToggle,
    required this.homeRoute,
    required this.notificationsRoute,
    this.hideProfile = false,
    this.onSidebarHoverEnter,
    this.onSidebarHoverExit,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: colorThemeNotifier,
      builder: (context, _) => _bar(context),
    );
  }

  Widget _bar(BuildContext context) {
    final toggleAccent = AppTheme.accentBlue;
    return Container(
      height: 60,
      decoration: BoxDecoration(gradient: AppTheme.headerGradient),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        // Sidebar toggle
        MouseRegion(
          key: const Key('sidebar-toggle'),
          onEnter: (_) => onSidebarHoverEnter?.call(),
          onExit: (_) => onSidebarHoverExit?.call(),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: toggleAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: toggleAccent.withValues(alpha: 0.25),
                    width: 0.8),
              ),
              child: Icon(
                sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
                size: 22,
                color: toggleAccent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Logo + name as home button
        InkWell(
          onTap: () => context.go(homeRoute),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text('FOMRA HOUSING AND INFRASTRUCTURE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4)),
          ),
        ),
        const Spacer(),
        // Quick actions
        const QuickActionIcons(),
        const SizedBox(width: 8),
        ReportProblemButton(
          color: Colors.white,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 8),
        // Notifications bell
        NotificationBellButton(
          notificationsRoute: notificationsRoute,
          badgeBorderColor: AppTheme.primaryBlueDark,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 8),
        // Profile avatar + dropdown
        if (!hideProfile) const ProfileAvatarButton(),
        if (!hideProfile) const SizedBox(width: 12),
      ]),
    );
  }
}
