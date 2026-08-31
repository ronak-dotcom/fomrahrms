import 'package:flutter/material.dart';
import '../models/leave_store.dart';
import '../utils/attendance_day.dart';
import 'hr_employee_records_page.dart' show showEmployeeProfile;
import '../models/user_session.dart';
import 'package:go_router/go_router.dart';
import '../models/app_user.dart';
import '../models/attendance_store.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../theme/app_theme.dart';
import '../widgets/attendance_shortcut_card.dart';
import '../widgets/dashboard_info_blocks.dart';
import '../widgets/employee_list_dialog.dart';
import '../widgets/fade_in.dart';
import '../widgets/hover_lift.dart';
import '../widgets/milestone_confetti.dart';
import '../widgets/stat_strip.dart';
import '../widgets/welcome_banner.dart';


class _Section {
  final String title;
  final IconData icon;
  final Color color;
  final String route;
  const _Section(this.title, this.icon, this.color, this.route);
}

class _SectionGroup {
  final String label;
  final IconData icon;
  final List<_Section> sections;
  const _SectionGroup(this.label, this.icon, this.sections);
}

const _teal = Color(0xFF15803D);

// Management works from the dashboard rather than the sidebar, so every
// destination in the nav is reachable here — the previous 8-card
// "Management Overview" grid covered less than a third of them, which meant
// anything else could only be found by opening the sidebar.
//
// Grouped with the same labels and ordering as the sidebar so the two
// describe the app the same way; Approvals leads because it is the thing
// most likely to need same-day action.
const _sectionGroups = <_SectionGroup>[
  _SectionGroup('Approvals', Icons.approval_rounded, [
    _Section('All Approvals',      Icons.inbox_rounded,           _teal, '/management/approvals'),
    _Section('Leave Approvals',    Icons.event_available_rounded, _teal, '/management/leave/team-approvals'),
    _Section('On-Roll Approvals',  Icons.verified_user_rounded,   _teal, '/management/onroll-approvals'),
    _Section('KRA Approvals',      Icons.flag_rounded,            _teal, '/management/kra-approvals'),
    _Section('Form Approvals',     Icons.fact_check_rounded,      _teal, '/management/form-approvals'),
  ]),
  _SectionGroup('People', Icons.people_rounded, [
    _Section('Employee Management', Icons.badge_rounded,             _teal, '/management/employee-management'),
    _Section('Employee Onboarding', Icons.how_to_reg_rounded,        _teal, '/management/employee-onboarding'),
    _Section('Interview Process',   Icons.record_voice_over_rounded, _teal, '/management/interview-process'),
    _Section('Interview Review',    Icons.rate_review_rounded,       _teal, '/management/interview-review'),
    _Section('Appraisals',          Icons.workspace_premium_rounded, _teal, '/management/appraisals'),
    _Section('KRA',                 Icons.flag_rounded,              _teal, '/management/kra-management'),
  ]),
  _SectionGroup('Time & Attendance', Icons.access_time_rounded, [
    _Section('Attendance Records', Icons.fact_check_rounded,      _teal, '/management/attendance-management'),
    _Section('Late Coming',        Icons.watch_later_rounded,     _teal, '/management/attendance/late-coming'),
    _Section('GPS Tracking',       Icons.my_location_rounded,     _teal, '/management/attendance/gps-tracking'),
    _Section('Location History',   Icons.travel_explore_rounded,  _teal, '/management/location-history'),
    _Section('Leave Management',   Icons.event_available_rounded, _teal, '/management/leave-management'),
  ]),
  _SectionGroup('Operations', Icons.work_outline_rounded, [
    _Section('Task Management',    Icons.task_alt_rounded,        _teal, '/management/task-management'),
    _Section('Lead Management',    Icons.leaderboard_rounded,     _teal, '/management/lead-management'),
    _Section('Maintenance',        Icons.build_rounded,           _teal, '/management/maintenance-management'),
    _Section('Payroll Management', Icons.account_balance_wallet_rounded, _teal, '/management/payroll-management'),
  ]),
  _SectionGroup('Insights', Icons.bar_chart_rounded, [
    _Section('Reports & Analytics', Icons.bar_chart_rounded,      _teal, '/management/reports-analytics'),
    _Section('Notifications',       Icons.notifications_rounded,  _teal, '/management/notifications'),
  ]),
  _SectionGroup('Setup', Icons.settings_rounded, [
    _Section('Administration',      Icons.admin_panel_settings_rounded, _teal, '/management/administration'),
    _Section('Location Management', Icons.location_on_rounded,    _teal, '/management/location-management'),
    _Section('Settings',            Icons.tune_rounded,           _teal, '/management/settings'),
    _Section('Edit Forms',          Icons.edit_note_rounded,      _teal, '/management/form-approvals'),
  ]),
];



class ManagementDashboardPage extends StatefulWidget {
  const ManagementDashboardPage({super.key});

  @override
  State<ManagementDashboardPage> createState() =>
      _ManagementDashboardPageState();
}

class _ManagementDashboardPageState extends State<ManagementDashboardPage> {
  String _totalEmployees = '—';
  String _present = '—';
  String _absent  = '—';
  // route → number of items waiting on a decision, shown as a badge on the
  // section card. The dashboard previously just repeated the sidebar's
  // links, so it told you where things live but never that anything needed
  // attention — you had to open each queue to find out it was empty.
  Map<String, int> _pending = const {};
  List<AppUser> _users = [];
  List<AttendanceRecord> _records = [];
  List<LeaveApplication> _leaveApps = [];

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final today   = DateTime.now();
    final dateStr = '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
    final users   = await UserStore.load();
    final records = await SupabaseService.fetchAttendanceForDate(dateStr);
    final leaves  = await SupabaseService.fetchLeaveApplications();
    final holidayRows = await SupabaseService.fetchHolidays(today.year);
    final holidays = {
      for (final h in holidayRows)
        if ((h['holiday_date'] as String?)?.isNotEmpty ?? false)
          (h['holiday_date'] as String).substring(0, 10),
    };

    // Only employees who are actually tracked. The CEO is excluded from
    // attendance entirely, so counting him in the headcount makes every
    // percentage wrong and guarantees a permanent phantom absence.
    final tracked = users.where((u) => u.active && u.countsInHeadcount && !u.exemptFromAttendance).toList();
    final presentNames =
        records.where((r) => r.checkInTime.isNotEmpty).map((r) => r.employeeName.trim().toLowerCase()).toSet();

    // absent was (total - present), which counts weekly offs, public holidays
    // and approved leave as absences. Third place this same arithmetic
    // appeared — after the HR attendance screen and Reports & Analytics.
    final absent = tracked
        .where((u) => !presentNames.contains(u.name.trim().toLowerCase()))
        .where((u) => classifyMissingAttendance(
              employee: u,
              date: today,
              holidayDates: holidays,
              leaveApps: leaves,
            ).countsAsAbsent)
        .length;

    // Counted here rather than inside the card so the card stays a dumb
    // renderer and every count comes from the same already-fetched data.
    final pendingLeaveCount = leaves
        .where((a) => a.managerStatus == LeaveApprovalStatus.pending)
        .length;
    // Same criterion onroll_approvals_page.dart counts as pending, so the
    // badge and the page can't disagree.
    final pendingOnroll = users.where((u) => u.onrollAwaitingManagement).length;

    // The same hasPending* getters approvals_page.dart uses for its own
    // counts, so the badge and the page can't disagree. Leave/permission/
    // comp-off and the form-version queues are counted on their own cards
    // rather than folded in here.
    final pendingInbox = users.where((u) =>
        u.hasPendingGrossPayChange ||
        u.hasPendingPermissionQuotaChange ||
        u.hasPendingWorkLocationChange ||
        u.hasPendingBusinessUnitChange ||
        u.hasPendingReportingManagerChange ||
        u.hasPendingRmFlagChange ||
        u.onrollAwaitingManagement).length;

    if (mounted) {
      setState(() {
        _totalEmployees = '${tracked.length}';
        _present = '${presentNames.length}';
        _absent  = '$absent';
        _users = users;
        _records = records;
        _leaveApps = leaves;
        _pending = {
          '/management/approvals': pendingInbox,
          '/management/leave/team-approvals': pendingLeaveCount,
          '/management/onroll-approvals': pendingOnroll,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final pad = narrow ? 16.0 : 24.0;

    return MilestoneConfetti(
      child: Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WelcomeBanner(
              avatarIcon: Icons.manage_accounts_rounded,
              onRefresh: _loadCount,
            ),
            Padding(
              padding: EdgeInsets.all(pad),
              child: FadeIn(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MgmtStatStrip(
                    totalEmployees: _totalEmployees,
                    present: _present,
                    absent: _absent,
                    users: _users,
                    records: _records,
                    leaveApps: _leaveApps,
                  ),
                  SizedBox(height: narrow ? 24 : 32),

                  // Oversight-only users (the CEO) have no personal HR record:
                  // no check-in/out, no leave of their own, no payslips or
                  // personal tasks. The card's remaining tiles are all
                  // oversight actions, so keep it for everyone else and drop
                  // it entirely for them. The router blocks the underlying
                  // routes too, so a typed URL cannot reach them either.
                  if (!UserSession.oversightOnly) AttendanceShortcutCard(
                    attendanceRoute: '/management/my-attendance',
                    accentColor: AppTheme.accentBlue,
                    extraTiles: [
                      QuickTile(label: 'View Reports', icon: Icons.bar_chart_rounded,
                          color: AppTheme.purple, route: '/management/reports-analytics'),
                      QuickTile(label: 'Add Employee', icon: Icons.person_add_alt_1_rounded,
                          color: AppTheme.success, route: '/management/employee-management/add'),
                      QuickTile(label: 'Attendance Sheet', icon: Icons.fact_check_rounded,
                          color: AppTheme.warning, route: '/management/attendance-management'),
                      // Help Center moved to Settings — reference material
                      // rather than a daily action, so it does not need a
                      // dashboard tile.
                    ],
                  ),
                  if (!UserSession.oversightOnly) SizedBox(height: narrow ? 24 : 32),

                  const DashboardInfoBlocks(canEdit: true),
                  SizedBox(height: narrow ? 24 : 32),

                  // Theme moved to Settings. It is a personal preference, and
                  // sitting inline here made it the first thing seen on
                  // opening the app, above the operational content.
                  SizedBox(height: narrow ? 24 : 32),

                  // Every nav destination, grouped. Management works from
                  // this page rather than the sidebar, so anything missing
                  // here is effectively missing from the app for them.
                  for (final group in _sectionGroups) ...[
                    _SectionLabel(icon: group.icon, label: group.label),
                    const SizedBox(height: 16),
                    _SectionGrid(sections: group.sections, pending: _pending),
                    SizedBox(height: narrow ? 24 : 32),
                  ],

                  const SizedBox(height: 8),
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

class _MgmtStatStrip extends StatelessWidget {
  final String totalEmployees;
  final String present;
  final String absent;
  final List<AppUser> users;
  final List<AttendanceRecord> records;
  final List<LeaveApplication> leaveApps;
  const _MgmtStatStrip(
      {required this.totalEmployees,
      required this.present,
      required this.absent,
      required this.users,
      required this.records,
      this.leaveApps = const []});

  double? _pct(String num, String denom) {
    final n = int.tryParse(num);
    final d = int.tryParse(denom);
    if (n == null || d == null || d == 0) return null;
    return (n / d).clamp(0.0, 1.0);
  }

  bool _isOffice(AppUser u) => u.workLocation == 'Office';

  String _locTag(AppUser u) => u.workLocation.isEmpty ? 'Not set' : u.workLocation;

  /// '12 Aug' for a single day, '12–14 Aug' for a span — the dates are the
  /// point of a leave request, so they belong in the row.
  String _fmtRange(DateTime from, DateTime to) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final f = '${from.day} ${m[from.month - 1]}';
    if (from.year == to.year && from.month == to.month && from.day == to.day) return f;
    return '$f – ${to.day} ${m[to.month - 1]}';
  }

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
    final sortedUsers = [...users]..sort((a, b) => a.name.compareTo(b.name));
    final presentList = presentByName.values.toList()
      ..sort((a, b) => a.employeeName.compareTo(b.employeeName));
    final absentUsers = sortedUsers.where((u) => !presentByName.containsKey(u.name)).toList();
    final usersByName = {for (final u in sortedUsers) u.name: u};

    // Waiting on a decision. Denied and approved are done; only pending needs
    // anyone's attention.
    final pendingLeaves = leaveApps
        .where((a) => a.managerStatus == LeaveApprovalStatus.pending)
        .toList()
      ..sort((a, b) => a.from.compareTo(b.from));

    final totalOffice = sortedUsers.where(_isOffice).length;
    final totalOnsite = sortedUsers.length - totalOffice;
    final presentOffice = presentList.where((r) {
      final u = usersByName[r.employeeName];
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
                onTap: _profileTap(context, usersByName, r.employeeName),
                subtitle: 'Checked in ${r.checkInTime} • ${_locTagByName(usersByName, r.employeeName)}',
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
      // Was hardcoded to '—': the card existed but was never wired to any
      // data, so it showed a dash regardless of how many requests were
      // waiting.
      AppStatCard(
        title: 'Pending Leaves',
        value: '${pendingLeaves.length}',
        icon: Icons.event_busy_rounded,
        color: AppTheme.warning,
        gaugePercent: 0,
        onTap: () => showEmployeeListDialog(
          context,
          title: 'Pending Leave Requests',
          icon: Icons.event_busy_rounded,
          color: AppTheme.warning,
          items: [
            // A leave request is not a person: the same employee can have more
            // than one waiting, so each row carries its dates and type rather
            // than only a name.
            for (final a in pendingLeaves)
              EmployeeListItem(
                name: a.employeeName,
                subtitle: '${a.leaveType} • ${_fmtRange(a.from, a.to)}',
                onTap: _profileTap(context, usersByName, a.employeeName),
              ),
          ],
          emptyLabel: 'No leave requests waiting',
        ),
      ),
    ]);
  }
}

class _SectionGrid extends StatelessWidget {
  final List<_Section> sections;
  final Map<String, int> pending;
  const _SectionGrid({required this.sections, required this.pending});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 600;
      final cols = wide ? 4 : 2;
      final rows = <Widget>[];
      for (int i = 0; i < sections.length; i += cols) {
        final end = (i + cols) > sections.length ? sections.length : i + cols;
        final rowItems = sections.sublist(i, end);
        final missing = cols - rowItems.length;
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...rowItems.map((s) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: (s == rowItems.last && missing == 0) ? 0 : 12,
                  bottom: 12,
                ),
                child: _SectionCard(section: s, pendingCount: pending[s.route] ?? 0),
              ),
            )),
            for (int j = 0; j < missing; j++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: j < missing - 1 ? 12 : 0),
                  child: const SizedBox(),
                ),
              ),
          ],
        ));
      }
      return Column(children: rows);
    });
  }
}

class _SectionCard extends StatelessWidget {
  final _Section section;
  final int pendingCount;
  const _SectionCard({required this.section, this.pendingCount = 0});

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: Card(
        color: AppTheme.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          side: const BorderSide(color: AppTheme.borderSubtle),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          onTap: () => context.go(section.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: section.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(section.icon, color: section.color, size: 20),
                ),
                const Spacer(),
                // Only drawn when something is actually waiting — a "0"
                // badge on every card would be noise and would stop the
                // real ones from standing out.
                if (pendingCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.warning,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$pendingCount pending',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 12),
              Text(section.title,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 6),
              Icon(Icons.arrow_upward_rounded, size: 16, color: section.color.withValues(alpha: 0.55)),
            ]),
          ),
        ),
      ),
    );
  }
}

