import 'package:flutter/material.dart';
import '../models/leave_store.dart';
import '../utils/attendance_day.dart';
import 'hr_employee_records_page.dart' show showEmployeeProfile;
import '../models/app_user.dart';
import '../models/attendance_store.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../widgets/welcome_banner.dart';
import '../widgets/attendance_shortcut_card.dart';
import '../widgets/dashboard_info_blocks.dart';
import '../widgets/employee_list_dialog.dart';
import '../widgets/fade_in.dart';
import '../widgets/milestone_confetti.dart';
import '../widgets/my_space_blocks.dart';
import '../widgets/my_team_block.dart';
import '../widgets/stat_strip.dart';
import '../widgets/task_analytics_block.dart';
import '../theme/app_theme.dart';

// ── Page ──────────────────────────────────────────────────────────────────────
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _totalEmployees = '—';
  String _present = '—';
  String _absent  = '—';
  List<AppUser> _users = [];
  List<AttendanceRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final today = DateTime.now();
    final dateStr =
        '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';

    final users   = await UserStore.load();
    final records = await SupabaseService.fetchAttendanceForDate(dateStr);
    final leaves  = await SupabaseService.fetchLeaveApplications();
    final holidayRows = await SupabaseService.fetchHolidays(today.year);
    final holidays = {
      for (final h in holidayRows)
        if ((h['holiday_date'] as String?)?.isNotEmpty ?? false)
          (h['holiday_date'] as String).substring(0, 10),
    };

    // The founder is not an employee: no joining date, no attendance, no
    // payroll, no leave. Counting him makes every percentage wrong — "5 of 6
    // present" against a denominator containing someone who can never check in.
    final tracked = users
        .where((u) => u.active && u.countsInHeadcount && !u.exemptFromAttendance)
        .toList();
    final total   = tracked.length;

    final presentNames = records
        .where((r) => r.checkInTime.isNotEmpty)
        .map((r) => r.employeeName.trim().toLowerCase())
        .toSet();
    final present = presentNames.length;

    // absent was (total - present), which counts weekly offs, public holidays
    // and approved leave as absences. FOURTH place this same arithmetic
    // appeared — after the HR attendance screen, Reports & Analytics and the
    // management dashboard.
    final absent = tracked
        .where((u) => !presentNames.contains(u.name.trim().toLowerCase()))
        .where((u) => classifyMissingAttendance(
              employee: u,
              date: today,
              holidayDates: holidays,
              leaveApps: leaves,
            ).countsAsAbsent)
        .length;

    if (mounted) {
      setState(() {
        _totalEmployees = '$total';
        _present = '$present';
        _absent  = '$absent';
        _users = users;
        _records = records;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final pad    = narrow ? 16.0 : 24.0;

    return MilestoneConfetti(
      child: Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Full-width header
            WelcomeBanner(
              subtitle: 'Fomra Housing & Infrastructure',
              avatarIcon: Icons.admin_panel_settings_rounded,
              onRefresh: _loadCount,
            ),

            Padding(
              padding: EdgeInsets.all(pad),
              child: FadeIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HrStatStrip(
                      totalEmployees: _totalEmployees,
                      present: _present,
                      absent: _absent,
                      users: _users,
                      records: _records,
                    ),
                    SizedBox(height: narrow ? 24 : 32),

                    const DashboardInfoBlocks(canEdit: true),
                    SizedBox(height: narrow ? 24 : 32),

                    _SectionLabel(icon: Icons.person_rounded, label: 'My Space'),
                    const SizedBox(height: 16),
                    MySpaceRow(children: [
                      AttendanceShortcutCard(
                        attendanceRoute: '/hr/my-attendance',
                        accentColor: AppTheme.accentBlue,
                        columns: 2,
                        extraTiles: [
                          QuickTile(label: 'Leave Request', icon: Icons.event_available_rounded,
                              color: AppTheme.primaryBlue, route: '/hr/my-leave'),
                          QuickTile(label: 'KRA', icon: Icons.flag_rounded,
                              color: AppTheme.warning, route: '/hr/my-kra'),
                        ],
                      ),
                      const MyTasksBlock(viewAllRoute: '/hr/my-tasks'),
                      const TaskAnalyticsBlock(viewAllRoute: '/hr/my-tasks'),
                    ]),
                    const SizedBox(height: 16),
                    _MySpaceRow(children: const [
                      MyLeaveBlock(applyRoute: '/hr/my-leave', compact: true),
                      MyAttendanceSummaryBlock(viewRoute: '/hr/my-attendance', compact: true),
                      MyPayslipBlock(viewRoute: '/hr/my-payslips', compact: true),
                    ]),
                    const SizedBox(height: 16),

                    if (UserSession.isReportingManager) ...[
                      const MyTeamBlock(
                        teamLeaveApprovalsRoute: '/hr/leave/team-approvals',
                        interviewReviewRoute: '/hr/interview-review',
                        appraisalReceivedRoute: '/hr/appraisal-received',
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
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

// ── Stat strip ────────────────────────────────────────────────────────────────
class _HrStatStrip extends StatelessWidget {
  final String totalEmployees;
  final String present;
  final String absent;
  final List<AppUser> users;
  final List<AttendanceRecord> records;
  const _HrStatStrip(
      {required this.totalEmployees,
      required this.present,
      required this.absent,
      required this.users,
      required this.records});

  double? _pct(String num, String denom) {
    final n = int.tryParse(num);
    final d = int.tryParse(denom);
    if (n == null || d == null || d == 0) return null;
    return (n / d).clamp(0.0, 1.0);
  }

  bool _isOffice(AppUser u) => u.workLocation == 'Office';

  String _locTag(AppUser u) => u.workLocation.isEmpty ? 'Not set' : u.workLocation;

  /// Opens the profile for [name] when it resolves to an employee record.
  /// Returns null otherwise — attendance rows store the name, not the id, so a
  /// renamed or removed employee cannot be matched, and the row is then shown
  /// without a chevron rather than looking tappable and doing nothing.
  /// [context] is passed in explicitly: this is a StatelessWidget, where
  /// `context` exists only as the build() parameter and is NOT a property of
  /// the class. Referencing it here compiled in my head and not in Dart.
  VoidCallback? _profileTap(
      BuildContext context, Map<String, AppUser> byName, String name) {
    final u = byName[name];
    if (u == null) return null;
    return () => showEmployeeProfile(context, u);
  }

  String _locTagByName(Map<String, AppUser> byName, String name) {
    final u = byName[name];
    return u == null ? 'Not set' : _locTag(u);
  }

  @override
  Widget build(BuildContext context) {
    final presentByName = {
      for (final r in records)
        if (r.checkInTime.isNotEmpty) r.employeeName: r,
    };
    // Same filter as the absent COUNT above. The count excluded oversight-only
    // and attendance-exempt accounts; this list did not, so a super-admin who
    // has no attendance appeared under Absent Today while the number beside it
    // said otherwise. Identical fault to the management dashboard — fixing one
    // and not the other is why it kept being reported.
    final sortedUsers = users
        .where((u) => u.active && u.countsInHeadcount && !u.exemptFromAttendance)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final presentList = presentByName.values.toList()
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    final absentUsers = sortedUsers.where((u) => !presentByName.containsKey(u.name)).toList();
    final onsiteUsers = sortedUsers.where((u) => !_isOffice(u)).toList();

    final totalOffice  = sortedUsers.where(_isOffice).length;
    final totalOnsite  = sortedUsers.length - totalOffice;
    final presentUsersByName = {for (final u in sortedUsers) u.name: u};
    final presentOffice = presentList.where((r) {
      final u = presentUsersByName[r.employeeName];
      return u != null && _isOffice(u);
    }).length;
    final presentOnsite = presentList.length - presentOffice;
    final absentOffice = absentUsers.where(_isOffice).length;
    final absentOnsite = absentUsers.length - absentOffice;

    return AppStatStrip(cards: [
      AppStatCard(
        title: 'Total Employees',
        value: totalEmployees,
        icon: Icons.groups_rounded,
        officeCount: totalOffice,
        onsiteCount: totalOnsite,
        onTap: () => showEmployeeListDialog(
          context,
          title: 'Total Employees',
          icon: Icons.groups_rounded,
          color: AppTheme.primaryBlue,
          items: [
            for (final u in sortedUsers)
              EmployeeListItem(
                name: u.name,
                subtitle: '${u.designation} • ${_locTag(u)}',
                workLocation: u.workLocation,
                businessUnit: u.businessUnit,
                onTap: () => showEmployeeProfile(context, u),
              ),
          ],
        ),
      ),
      AppStatCard(
        title: 'Present Today',
        value: present,
        icon: Icons.check_circle_rounded,
        gaugePercent: _pct(present, totalEmployees),
        officeCount: presentOffice,
        onsiteCount: presentOnsite,
        onTap: () => showEmployeeListDialog(
          context,
          title: 'Present Today',
          icon: Icons.check_circle_rounded,
          color: AppTheme.success,
          items: [
            for (final r in presentList)
              EmployeeListItem(
                name: r.employeeName,
                onTap: _profileTap(context, presentUsersByName, r.employeeName),
                subtitle: 'Checked in ${r.checkInTime} • ${_locTagByName(presentUsersByName, r.employeeName)}',
              ),
          ],
          emptyLabel: 'No one has checked in yet',
        ),
      ),
      AppStatCard(
        title: 'Absent Today',
        value: absent,
        icon: Icons.cancel_rounded,
        gaugePercent: _pct(absent, totalEmployees),
        officeCount: absentOffice,
        onsiteCount: absentOnsite,
        onTap: () => showEmployeeListDialog(
          context,
          title: 'Absent Today',
          icon: Icons.cancel_rounded,
          color: AppTheme.error,
          items: [
            for (final u in absentUsers)
              EmployeeListItem(
                name: u.name,
                subtitle: '${u.designation} • ${_locTag(u)}',
                workLocation: u.workLocation,
                businessUnit: u.businessUnit,
                onTap: () => showEmployeeProfile(context, u),
              ),
          ],
          emptyLabel: 'Everyone is present today',
        ),
      ),
      AppStatCard(
        title: 'On-site',
        value: '$totalOnsite',
        icon: Icons.location_on_rounded,
        color: Colors.teal,
        gaugePercent: _pct('$totalOnsite', totalEmployees),
        onTap: () => showEmployeeListDialog(
          context,
          title: 'On-site Employees',
          icon: Icons.location_on_rounded,
          color: Colors.teal,
          items: [
            for (final u in onsiteUsers)
              EmployeeListItem(
                name: u.name,
                onTap: _profileTap(context, presentUsersByName, u.name),
                subtitle: '${u.designation} • ${presentByName.containsKey(u.name) ? 'Present' : 'Absent'}',
              ),
          ],
          emptyLabel: 'No onsite employees',
        ),
      ),
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
