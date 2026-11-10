import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_session.dart';
import '../widgets/attendance_shortcut_card.dart' show showHelpCenterDialog;
import '../theme/app_theme.dart';
import '../widgets/theme_picker_block.dart';

/// Settings.
///
/// The theme picker used to sit inline on the management dashboard, above the
/// operational content — the first thing seen on opening the app, and a
/// personal preference rather than something anyone needs at a glance. Moved
/// here so the dashboard leads with work.
///
/// The four form editors live here too. They were four separate sidebar
/// entries, which made configuration the longest group in the menu for tools
/// that are opened when a form is first set up and then left alone.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const _formEditors = <({String label, String hint, IconData icon, String route})>[
    (
      label: 'Leave, Permission & Comp Off Forms',
      hint: 'What employees are asked when they apply',
      icon: Icons.edit_calendar_rounded,
      route: '/management/edit-leave-form',
    ),
    (
      label: 'Interview Form',
      hint: 'Questions on the candidate interview form',
      icon: Icons.assignment_rounded,
      route: '/management/edit-form',
    ),
    (
      label: 'Onboarding Form',
      hint: 'Details collected from a new joiner',
      icon: Icons.assignment_ind_rounded,
      route: '/management/edit-onboarding-form',
    ),
    (
      label: 'Maintenance Form',
      hint: 'Fields on a maintenance ticket',
      icon: Icons.build_circle_rounded,
      route: '/management/edit-maintenance-form',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    // The editor routes exist under /management only, so the links are shown
    // to Management only. Anyone else would be bounced to their dashboard.
    final showForms = UserSession.role == UserRole.management;

    return SingleChildScrollView(
      padding: EdgeInsets.all(narrow ? 16 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.settings_rounded, color: AppTheme.primaryBlue, size: narrow ? 22 : 26),
            const SizedBox(width: 10),
            Text(
              'Settings',
              style: TextStyle(
                fontSize: narrow ? 20 : 24,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryBlue,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Personal preferences apply to your account only. Form changes '
            'apply to everyone.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          SizedBox(height: narrow ? 20 : 28),

          const ThemePickerBlock(),
          SizedBox(height: narrow ? 20 : 28),

          if (showForms) ...[
            Text(
              'Forms',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Edit the questions each form asks. Changes take effect for '
              'everyone who fills the form in afterwards.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _formEditors.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
                    ListTile(
                      leading: Icon(_formEditors[i].icon, color: AppTheme.primaryBlue),
                      title: Text(_formEditors[i].label,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(_formEditors[i].hint,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go(_formEditors[i].route),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: narrow ? 20 : 28),
          ],

          // Moved off the dashboard: reference material, not a daily action.
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ListTile(
              leading: Icon(Icons.help_rounded, color: AppTheme.pink),
              title: const Text('Help Center',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text('Guides and answers to common questions',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showHelpCenterDialog(context),
            ),
          ),
        ],
      ),
    );
  }
}
