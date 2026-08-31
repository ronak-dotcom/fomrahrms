import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../theme/app_theme.dart';
import '../widgets/attendance_shortcut_card.dart';
import '../widgets/dashboard_info_blocks.dart';
import '../widgets/fade_in.dart';
import '../widgets/milestone_confetti.dart';
import '../widgets/my_cycle_blocks.dart';
import '../widgets/my_space_blocks.dart';
import '../widgets/my_team_block.dart';
import '../widgets/task_analytics_block.dart';
import '../widgets/welcome_banner.dart';

class EmployeeDashboardPage extends StatefulWidget {
  const EmployeeDashboardPage({super.key});

  @override
  State<EmployeeDashboardPage> createState() => _EmployeeDashboardPageState();
}

class _EmployeeDashboardPageState extends State<EmployeeDashboardPage> {
  int _refreshKey = 0;

  Future<void> _refresh() async {
    setState(() => _refreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final pad    = narrow ? 16.0 : 24.0;

    return MilestoneConfetti(
      child: Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WelcomeBanner(
              avatarIcon: Icons.person_rounded,
            ),
            Padding(
              padding: EdgeInsets.all(pad),
              child: FadeIn(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(icon: Icons.person_rounded, label: 'My Space'),
                  const SizedBox(height: 16),
                  MySpaceRow(children: [
                    AttendanceShortcutCard(
                      attendanceRoute: '/employee/attendance-management',
                      accentColor: AppTheme.primaryBlue,
                      columns: 2,
                      extraTiles: [
                        QuickTile(label: 'Leave Request', icon: Icons.event_available_rounded,
                            color: AppTheme.primaryBlue, route: '/employee/leave-management'),
                        QuickTile(label: 'KRA', icon: Icons.flag_rounded,
                            color: AppTheme.warning, route: '/employee/kra'),
                      ],
                    ),
                    const MyTasksBlock(viewAllRoute: '/employee/tasks', modern: true),
                    const TaskAnalyticsBlock(modern: true, viewAllRoute: '/employee/tasks'),
                  ]),
                  const SizedBox(height: 16),
                  _MySpaceRow(children: const [
                    MyLeaveBlock(applyRoute: '/employee/leave-management', compact: true),
                    MyAttendanceSummaryBlock(viewRoute: '/employee/attendance-management', compact: true),
                    MyPayslipBlock(viewRoute: '/employee/payslips', compact: true),
                  ]),
                  const SizedBox(height: 16),
                  // The figures that decide this month's pay, plus what
                  // leave is actually left by type — both were computed by
                  // the app already but only ever shown to management, so
                  // employees had to ask someone to find out where they
                  // stood.
                  _MySpaceRow(children: const [
                    MyCycleSummaryBlock(viewRoute: '/employee/attendance-management', compact: true),
                    MyLeaveBalanceBlock(viewRoute: '/employee/leave-management', compact: true),
                    UpcomingHolidaysBlock(compact: true),
                  ]),
                  const SizedBox(height: 16),

                  if (UserSession.isReportingManager) ...[
                    const MyTeamBlock(
                      teamLeaveApprovalsRoute: '/employee/my-team/leave-approvals',
                      interviewReviewRoute: '/employee/my-team/interview-review',
                      appraisalReceivedRoute: '/employee/my-team/appraisal-received',
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
              ),
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: cs.primary, size: 20),
      ),
      const SizedBox(width: 12),
      Text(label,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(width: 16),
      Expanded(child: Divider(color: cs.outlineVariant)),
    ]);
  }
}

// ── My Space responsive row ────────────────────────────────────────────────────
class _MySpaceRow extends StatelessWidget {
  final List<Widget> children;
  const _MySpaceRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 900;
      if (wide) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: children[i]),
              ],
            ],
          ),
        );
      }
      return Column(children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          children[i],
        ],
      ]);
    });
  }
}
