import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/app_user.dart';
import '../models/attendance_store.dart';
import '../models/leave_store.dart';
import '../models/office_timing.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/salary_master_export.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../theme/app_theme.dart';
import '../theme/mobile_ui.dart';
import '../utils/attendance_cycle.dart';
import '../utils/attendance_day.dart';
import '../utils/checkin_status.dart';
import '../widgets/attendance_shortcut_card.dart' show showQuickAttendance;
import '../widgets/employee_list_dialog.dart';
import 'hr_employee_records_page.dart' show showEmployeeProfile;

/// Management's home (redesign approved by Ronak, 20 Nov 2026): what is
/// happening today, what is waiting for a decision, and where this pay
/// cycle stands. Everything else is one click away in the menu.
///
/// Replaces the dashboard that opened with a banner, a quick-access grid,
/// gauges and every section repeated as cards.
class ManagementOverviewPage extends StatefulWidget {
  const ManagementOverviewPage({super.key});

  @override
  State<ManagementOverviewPage> createState() => _ManagementOverviewPageState();
}

class _ManagementOverviewPageState extends State<ManagementOverviewPage> {
  bool _loading = true;
  List<AppUser> _users = [];
  List<AttendanceRecord> _records = [];
  List<LeaveApplication> _leaves = [];

  // Today
  List<AppUser> _present = [], _absent = [], _onLeave = [], _late = [];

  // Waiting on a decision
  List<LeaveApplication> _pendingLeave = [];
  Map<String, int> _otherQueues = {};
  final Set<String> _deciding = {};

  // Pay
  List<Map<String, dynamic>>? _runningSheet;
  List<Map<String, dynamic>>? _lastClosed;
  DateTime? _runningEnd, _closedEnd;

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
  static const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _key(String name) => name.trim().toLowerCase();

  Future<void> _load() async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final dateStr = '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
    final results = await Future.wait([
      UserStore.load(),
      SupabaseService.fetchAttendanceForDate(dateStr),
      SupabaseService.fetchLeaveApplications(),
      SupabaseService.fetchHolidays(today.year),
      OfficeTimingStore.ensureLoaded(),
    ]);
    final users = results[0] as List<AppUser>;
    final records = results[1] as List<AttendanceRecord>;
    final leaves = results[2] as List<LeaveApplication>;
    final holidays = {
      for (final h in results[3] as List<Map<String, dynamic>>)
        if ((h['holiday_date'] as String?)?.isNotEmpty ?? false) (h['holiday_date'] as String).substring(0, 10),
    };

    // Same people and rules as the attendance screens: tracked staff only;
    // weekly offs, holidays and approved leave are not absences.
    final tracked = users.where((u) => u.active && u.countsInHeadcount && !u.exemptFromAttendance).toList();
    final byName = {for (final r in records.where((r) => r.checkInTime.isNotEmpty)) _key(r.employeeName): r};
    final present = <AppUser>[], absent = <AppUser>[], onLeave = <AppUser>[], late = <AppUser>[];
    for (final u in tracked) {
      final rec = byName[_key(u.name)];
      if (rec != null) {
        present.add(u);
        final st = checkInStatusFor(rec.checkInTime, day, u.name, leaves, OfficeTimingStore.scheduleForUser(u),
            lateWaived: rec.lateWaived, onDuty: rec.onDuty);
        if (st.status == CheckInStatus.late) late.add(u);
        continue;
      }
      final why = classifyMissingAttendance(employee: u, date: day, holidayDates: holidays, leaveApps: leaves);
      if (why == NonWorkingReason.onLeave) onLeave.add(u);
      if (why.countsAsAbsent) absent.add(u);
    }

    final pendingLeave = leaves.where((a) => a.managerStatus == LeaveApprovalStatus.pending).toList()
      ..sort((a, b) => a.from.compareTo(b.from));

    // The other queues, counted the way their own pages count them.
    final queues = <String, int>{
      '/management/approvals': users.where((u) =>
          u.hasPendingGrossPayChange || u.hasPendingPermissionQuotaChange || u.hasPendingWorkLocationChange ||
          u.hasPendingBusinessUnitChange || u.hasPendingReportingManagerChange || u.hasPendingRmFlagChange).length,
      '/management/onroll-approvals': users.where((u) => u.onrollAwaitingManagement).length,
    };
    try {
      final kra = await SupabaseService.fetchKraDocuments().timeout(const Duration(seconds: 8));
      queues['/management/kra-approvals'] = kra.where((d) => d.isPending).length;
    } catch (_) {/* badge hidden */}

    if (!mounted) return;
    setState(() {
      _users = users;
      _records = records;
      _leaves = leaves;
      _present = present;
      _absent = absent;
      _onLeave = onLeave;
      _late = late;
      _pendingLeave = pendingLeave;
      _otherQueues = queues;
      _loading = false;
    });
    _loadPay();
  }

  /// Pay figures load after the page shows: they take the longest and the
  /// rest of the page does not depend on them.
  Future<void> _loadPay() async {
    final now = DateTime.now();
    final running = attendanceCycleEnd(DateTime(now.year, now.month, now.day));
    final closed = DateTime(running.year, running.month - 1, 25);
    try {
      final r = await SupabaseService.salaryMasterSheet(running);
      final c = await SupabaseService.payslipPreview(closed);
      if (!mounted) return;
      setState(() {
        _runningEnd = running;
        _closedEnd = closed;
        _runningSheet = r;
        _lastClosed = c;
      });
    } catch (_) {
      if (mounted) setState(() => _runningSheet = const []);
    }
  }

  // ── leave decisions ────────────────────────────────────────────────────
  Future<void> _decide(LeaveApplication app, bool approve) async {
    var comment = '';
    if (!approve) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Reject ${app.employeeName}\'s ${app.leaveType.toLowerCase()}?'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason (shown to the employee)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MobileUi.lop),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      comment = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true) return;
    }
    setState(() => _deciding.add(app.id));
    final status = approve ? LeaveApprovalStatus.approved : LeaveApprovalStatus.denied;
    await SupabaseService.updateLeaveManagementStatus(app.id, status,
        decidedBy: UserSession.name, rejectionComment: comment);
    final user = _users.where((u) => u.name == app.employeeName).firstOrNull;
    if (user != null && user.email.isNotEmpty) {
      NotificationService.leaveDecided(
        employeeEmail: user.email,
        leaveType: app.leaveType,
        approved: approve,
        employeeRoutePrefix: switch (user.role) {
          'Manager' => '/manager',
          'Management' => '/management',
          'HR' => '/hr',
          _ => '/employee',
        },
        employeeName: app.employeeName,
      ).catchError((_) {});
    }
    if (!mounted) return;
    setState(() {
      _deciding.remove(app.id);
      _pendingLeave.remove(app);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('${app.employeeName}\'s ${app.leaveType.toLowerCase()} ${approve ? 'approved' : 'rejected'}.'),
    ));
  }

  // ── layout ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final wide = w >= 1000;
    final now = DateTime.now();
    final pad = w >= 700 ? 28.0 : 16.0;
    return Material(
      color: AppTheme.pageBackground,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 28),
          children: [
            Row(children: [
              Expanded(
                child: Text('${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              ),
              IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary)),
            ]),
            const SizedBox(height: 4),
            if (_loading)
              const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator()))
            else ...[
              if (!UserSession.oversightOnly) ...[_myDay(), const SizedBox(height: 16)],
              _section('Today'),
              _today(w),
              const SizedBox(height: 24),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: _waiting()),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: _pay()),
                ])
              else ...[
                _waiting(),
                const SizedBox(height: 24),
                _pay(),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(String label, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Row(children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          ),
          if (trailing != null) trailing,
        ]),
      );

  /// Management check in like everyone else (most days, 28 check-ins in 45).
  Widget _myDay() {
    final mine = _records.where((r) => _key(r.employeeName) == _key(UserSession.name)).firstOrNull;
    final inAt = mine?.checkInTime ?? '';
    final outAt = mine?.checkOutTime ?? '';
    final String text;
    final String? action;
    if (inAt.isEmpty) {
      text = 'You have not checked in today.';
      action = 'Check in';
    } else if (outAt.isEmpty) {
      text = 'Checked in at $inAt.';
      action = 'Check out';
    } else {
      text = 'Checked in at $inAt, out at $outAt.';
      action = null;
    }
    return MCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(children: [
        Icon(inAt.isEmpty ? Icons.fingerprint_rounded : Icons.check_circle_rounded,
            color: inAt.isEmpty ? AppTheme.textSecondary : MobileUi.present, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        if (action != null)
          FilledButton(
            onPressed: () => showQuickAttendance(context,
                record: mine, attendanceRoute: '/management/my-attendance', onDone: _load),
            child: Text(action),
          ),
      ]),
    );
  }

  Widget _today(double w) {
    Widget tile(String label, List<AppUser> people, Color color, IconData icon, String subtitle(AppUser u)) {
      return MCard(
        onTap: () => showEmployeeListDialog(
          context,
          title: '$label today',
          icon: icon,
          color: color,
          items: [
            for (final u in people)
              EmployeeListItem(
                name: u.name,
                subtitle: subtitle(u),
                workLocation: u.workLocation,
                businessUnit: u.businessUnit,
                onTap: () => showEmployeeProfile(context, u),
              ),
          ],
          emptyLabel: 'No one',
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Text('${people.length}',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color, height: 1.1)),
            ]),
          ),
          Icon(icon, color: color.withValues(alpha: 0.5), size: 26),
        ]),
      );
    }

    String checkedIn(AppUser u) {
      final r = _records.where((r) => _key(r.employeeName) == _key(u.name)).firstOrNull;
      return 'Checked in ${r?.checkInTime ?? ''} · ${u.designation}';
    }

    String leaveOf(AppUser u) {
      final a = _leaves.where((a) => a.employeeName == u.name && a.managerStatus == LeaveApprovalStatus.approved)
          .where((a) => !DateTime.now().isBefore(a.from) && !DateTime.now().isAfter(a.to.add(const Duration(days: 1))))
          .firstOrNull;
      return a == null ? u.designation : a.leaveType;
    }

    final tiles = [
      tile('Present', _present, MobileUi.present, Icons.how_to_reg_rounded, checkedIn),
      tile('Absent', _absent, MobileUi.lop, Icons.person_off_rounded, (u) => u.designation),
      tile('On leave', _onLeave, MobileUi.leave, Icons.beach_access_rounded, leaveOf),
      tile('Late', _late, MobileUi.late, Icons.schedule_rounded, checkedIn),
    ];
    if (w >= 700) {
      return Row(children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tiles[i]),
        ],
      ]);
    }
    return Column(children: [
      Row(children: [Expanded(child: tiles[0]), const SizedBox(width: 10), Expanded(child: tiles[1])]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: tiles[2]), const SizedBox(width: 10), Expanded(child: tiles[3])]),
    ]);
  }

  String _range(LeaveApplication a) {
    String d(DateTime x) => '${x.day} ${_short[x.month - 1]}';
    final same = a.from.year == a.to.year && a.from.month == a.to.month && a.from.day == a.to.day;
    final days = a.leaveType == 'Permission'
        ? ''
        : ' · ${LeaveStore.fmtDays(a.effectiveDays)} day${a.effectiveDays == 1 ? '' : 's'}';
    return '${same ? d(a.from) : '${d(a.from)} – ${d(a.to)}'}$days';
  }

  Widget _waiting() {
    const queueLabels = {
      '/management/approvals': 'Other requests (salary, location, manager changes)',
      '/management/onroll-approvals': 'Confirmations',
      '/management/kra-approvals': 'KRA approvals',
    };
    final queues = _otherQueues.entries.where((e) => e.value > 0).toList();
    final total = _pendingLeave.length + queues.fold<int>(0, (t, e) => t + e.value);
    final shown = _pendingLeave.take(6).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(total == 0 ? 'Waiting on you' : 'Waiting on you · $total',
          trailing: _pendingLeave.isEmpty
              ? null
              : TextButton(
                  onPressed: () => context.go('/management/leave/team-approvals'),
                  child: const Text('All leave requests'),
                )),
      if (total == 0)
        const MCard(
          child: Row(children: [
            Icon(Icons.task_alt_rounded, color: MobileUi.present),
            SizedBox(width: 10),
            Text('Nothing is waiting for a decision.'),
          ]),
        )
      else
        MCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: MobileUi.line),
              _leaveRow(shown[i]),
            ],
            if (_pendingLeave.length > shown.length) ...[
              const Divider(height: 1, color: MobileUi.line),
              ListTile(
                dense: true,
                title: Text('${_pendingLeave.length - shown.length} more leave request'
                    '${_pendingLeave.length - shown.length == 1 ? '' : 's'}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.go('/management/leave/team-approvals'),
              ),
            ],
            for (final e in queues) ...[
              if (shown.isNotEmpty || e != queues.first) const Divider(height: 1, color: MobileUi.line),
              ListTile(
                title: Text(queueLabels[e.key] ?? e.key, style: const TextStyle(fontSize: 14)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  MChip('${e.value}', color: MobileUi.late, background: MobileUi.lateBg),
                  const Icon(Icons.chevron_right_rounded),
                ]),
                onTap: () => context.go(e.key),
              ),
            ],
          ]),
        ),
    ]);
  }

  Widget _leaveRow(LeaveApplication a) {
    final busy = _deciding.contains(a.id);
    final narrow = MediaQuery.of(context).size.width < 520;
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(a.employeeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 2),
      Text('${a.leaveType} · ${_range(a)}',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
      if (a.reason.split('|').length > 1 || (a.leaveType != 'Permission' && a.reason.isNotEmpty))
        Text(
          (a.leaveType == 'Permission' ? a.reason.split('|').skip(1).join(' · ') : a.reason).trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
        ),
    ]);
    final buttons = Row(mainAxisSize: MainAxisSize.min, children: [
      OutlinedButton(
        onPressed: busy ? null : () => _decide(a, false),
        style: OutlinedButton.styleFrom(foregroundColor: MobileUi.lop, visualDensity: VisualDensity.compact),
        child: const Text('Reject'),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: busy ? null : () => _decide(a, true),
        style: FilledButton.styleFrom(backgroundColor: MobileUi.present, visualDensity: VisualDensity.compact),
        child: busy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Approve'),
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              info,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: buttons),
            ])
          : Row(children: [Expanded(child: info), const SizedBox(width: 12), buttons]),
    );
  }

  Widget _pay() {
    final running = _runningSheet;
    Widget line(String l, String v, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(l, style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary))),
            Text(v, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
          ]),
        );
    if (running == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _section('This pay cycle'),
        const MCard(child: SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
      ]);
    }
    final paid = SalaryMasterExport.payroll(running);
    num sum(String k) => paid.fold<num>(0, (t, r) => t + SalaryMasterExport.n(r, k));
    final lopPeople = paid.where((r) => SalaryMasterExport.n(r, 'days_lost') > 0).length;
    final closed = _lastClosed ?? const [];
    final published = closed.where((r) => r['payslip_status'] == 'published').length;
    final drafts = closed.where((r) => r['payslip_status'] == 'draft').length;
    final notIssued = closed.length - published - drafts;
    final changed = closed.where((r) => r['records_changed'] == true).length;
    final runStart = _runningEnd == null ? null : attendanceCycleStart(_runningEnd!);
    String d(DateTime x) => '${x.day} ${_short[x.month - 1]}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section('This pay cycle',
          trailing: TextButton(
            onPressed: () => context.go('/management/salary-master-sheet'),
            child: const Text('Master sheet'),
          )),
      MCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (runStart != null)
            Text('${d(runStart)} – ${d(_runningEnd!)} · so far',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(formatRupees(sum('net_pay')),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const Text('net salary to credit if the rest of the cycle is worked',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
          const Divider(height: 22, color: MobileUi.line),
          line('People on payroll', '${paid.length}'),
          line('Loss of pay so far', '${LeaveStore.fmtDays(sum('days_lost'))} days · $lopPeople people',
              color: sum('days_lost') > 0 ? MobileUi.lop : null),
          line('Deductions (EPF, ESI, PT, TDS)', formatRupees(sum('total_deductions'))),
        ]),
      ),
      if (_closedEnd != null && closed.isNotEmpty) ...[
        const SizedBox(height: 12),
        MCard(
          onTap: () => context.go('/management/payroll-management'),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_months[_closedEnd!.month - 1]} payslips',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (published > 0) '$published published',
                    if (drafts > 0) '$drafts draft${drafts == 1 ? '' : 's'} to publish',
                    if (notIssued > 0) '$notIssued not issued',
                    if (changed > 0) '$changed changed since publishing',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: changed > 0 ? MobileUi.lop : AppTheme.textSecondary),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
          ]),
        ),
      ],
    ]);
  }
}
