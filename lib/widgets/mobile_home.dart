import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/attendance_store.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/mobile_ui.dart';
import '../utils/leave_balance_math.dart';
import '../utils/attendance_cycle.dart';
import 'attendance_shortcut_card.dart' show showHrPolicy;
import 'quick_actions_bar.dart' show AroundFomraCard;
import 'desktop_shell.dart' show DesktopChrome;

/// The employee Home on a phone (approved redesign, 19 Nov 2026).
///
/// Today's status and the check-in / check-out button come first, then leave
/// balance, this pay cycle, quick actions, anything waiting for approval and
/// "Around FOMRA". The old phone Home opened with a greeting banner that
/// filled a third of the screen, and showed empty "No pending tasks" cards.
class MobileHome extends StatefulWidget {
  const MobileHome({super.key});

  @override
  State<MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<MobileHome> {
  static const _attendanceRoute = '/employee/attendance/check-in-out';

  bool _loading = true;
  AttendanceRecord? _today;
  Map<String, Map<String, dynamic>> _balance = {};
  /// The balance less requests waiting for approval and approved leave not
  /// yet taken — the same figure Apply leave shows, so the two screens agree.
  Map<String, double> _bookable = {};
  Map<String, dynamic>? _cycle;
  List<LeaveApplication> _waiting = [];
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // Keeps "worked" current while the screen is open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final empId = UserSession.employeeId;
    if (empId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        SupabaseService.fetchTodayAttendance(empId),
        SupabaseService.fetchLeaveBalance(empId),
        SupabaseService.fetchCycleReport(attendanceCycleEnd(DateTime.now()), employeeIds: [empId]),
        SupabaseService.fetchLeaveApplications(),
      ]).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      final balanceRows = (results[1] as List).cast<Map<String, dynamic>>();
      final cycleRows = (results[2] as List).cast<Map<String, dynamic>>();
      final leaves = (results[3] as List).cast<LeaveApplication>();
      setState(() {
        _today = results[0] as AttendanceRecord?;
        _balance = {for (final r in balanceRows) (r['bucket'] as String): r};
        _bookable = usableAfterOutstanding(
          usable: {
            for (final r in balanceRows)
              (r['bucket'] as String): ((r['usable'] as num?) ?? 0).toDouble(),
          },
          myLeaves: leaves.where((a) => a.employeeName == UserSession.name),
          today: DateTime.now(),
        );
        _cycle = cycleRows.isNotEmpty ? cycleRows.first : null;
        _waiting = leaves
            .where((a) =>
                a.employeeName == UserSession.name &&
                a.managerStatus == LeaveApprovalStatus.pending)
            .toList()
          ..sort((a, b) => a.from.compareTo(b.from));
        _loading = false;
      });
      final rec = _today;
      if (rec != null && rec.checkInTime.isNotEmpty && rec.checkOutTime.isEmpty) {
        AttendanceStore.isCheckedIn = true;
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
  static const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  num _num(Map<String, dynamic>? m, String k) => (m?[k] as num?) ?? 0;

  List<Widget> _waitingList() => [
        for (final a in _waiting.take(3)) ...[
          _waitingCard(a),
          const SizedBox(height: 8),
        ],
      ];

  /// The computer layout (approved 20 Nov 2026): today and quick actions on
  /// the left; balance, this cycle, requests and company news on the right.
  /// The greeting is in the top bar.
  Widget _buildDesktop(BuildContext context) {
    final now = DateTime.now();
    final cycle = MSection('This pay cycle · ${attendanceCycleRange(attendanceCycleEnd(now))}');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: LayoutBuilder(builder: (context, c) {
                if (c.maxWidth < 900) {
                  // Narrow window: the phone order, one column.
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const SizedBox(height: 14),
                    _todayCard(),
                    const MSection('Leave balance'),
                    _balanceTiles(),
                    cycle,
                    _cycleStats(),
                    const MSection('Quick actions'),
                    _quickActions(),
                    if (_waiting.isNotEmpty) ...[const MSection('Waiting for approval'), ..._waitingList()],
                    const MSection('Around FOMRA'),
                    const AroundFomraCard(),
                  ]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 380,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SizedBox(height: 14),
                      _todayCard(),
                      const MSection('Quick actions'),
                      _quickActions(),
                    ]),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const MSection('Leave balance'),
                      _balanceTiles(),
                      cycle,
                      _cycleStats(),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_waiting.isNotEmpty) ...[
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              const MSection('Waiting for approval'),
                              ..._waitingList(),
                            ]),
                          ),
                          const SizedBox(width: 18),
                        ],
                        const Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            MSection('Around FOMRA'),
                            AroundFomraCard(),
                          ]),
                        ),
                      ]),
                    ]),
                  ),
                ]);
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (DesktopChrome.active(context)) return _buildDesktop(context);
    final now = DateTime.now();
    final first = UserSession.name.split(' ').first;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text('${_greeting()}${first.isEmpty ? '' : ', $first'}',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          const SizedBox(height: 2),
          Text('${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}',
              style: const TextStyle(fontSize: 13.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 14),
          _todayCard(),
          const MSection('Leave balance'),
          _balanceTiles(),
          MSection('This pay cycle · ${attendanceCycleRange(attendanceCycleEnd(now))}'),
          _cycleStats(),
          const MSection('Quick actions'),
          _quickActions(),
          if (_waiting.isNotEmpty) ...[
            const MSection('Waiting for approval'),
            ..._waitingList(),
          ],
          const MSection('Around FOMRA'),
          const AroundFomraCard(),
        ],
      ),
    );
  }

  Widget _todayCard() {
    final rec = _today;
    final checkedIn = rec != null && rec.checkInTime.isNotEmpty;
    final done = checkedIn && rec.checkOutTime.isNotEmpty;
    final (chipText, chipColor, chipBg, chipIcon) = _loading
        ? ('Loading…', AppTheme.textSecondary, const Color(0xFFEEF1F6), Icons.hourglass_empty_rounded)
        : done
            ? ('Done for today', MobileUi.present, MobileUi.presentBg, Icons.task_alt_rounded)
            : checkedIn
                ? ('Checked in', MobileUi.present, MobileUi.presentBg, Icons.check_circle_rounded)
                : ('Not checked in', MobileUi.late, MobileUi.lateBg, Icons.schedule_rounded);

    Widget figure(String label, String value, {Color color = AppTheme.textPrimary}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary, letterSpacing: 0.4)),
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: color)),
          ],
        );

    return MCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          MChip(chipText, color: chipColor, background: chipBg, icon: chipIcon),
          const Spacer(),
          if (checkedIn && rec.location.isNotEmpty)
            Flexible(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(rec.location,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                ),
              ]),
            ),
        ]),
        if (checkedIn) ...[
          const SizedBox(height: 12),
          Row(children: [
            figure('IN AT', rec.checkInTime),
            if (done) ...[
              const SizedBox(width: 24),
              figure('OUT AT', rec.checkOutTime),
            ],
          ]),
        ],
        if (!done && !_loading) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: checkedIn ? MobileUi.present : AppTheme.primaryBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              onPressed: () async {
                await context.push(_attendanceRoute);
                _load();
              },
              icon: Icon(checkedIn ? Icons.logout_rounded : Icons.login_rounded),
              label: Text(checkedIn ? 'Check out' : 'Check in'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _balanceTiles() {
    Widget tile(String label, String bucket) {
      final r = _balance[bucket];
      final rawUsable = (r?['usable'] as num?) ?? 0;
      final usable = _bookable[bucket] ?? rawUsable;
      final booked = rawUsable - usable;
      final available = (r?['available'] as num?) ?? 0;
      final accrued = (r?['accrued'] as num?) ?? 0;
      final String sub;
      if (r == null) {
        sub = _loading ? '' : '—';
      } else if (accrued == 0) {
        sub = 'after confirmation';
      } else if (accrued >= 9999) {
        sub = 'not limited';
      } else if (booked > 0) {
        sub = '${LeaveStore.fmtDays(booked)} booked';
      } else if (bucket == 'CL' && available > usable) {
        sub = '${LeaveStore.fmtDays(available)} saved';
      } else {
        sub = 'available';
      }
      return Expanded(
        child: MCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          onTap: () => context.go('/employee/leave-management'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            const SizedBox(height: 2),
            Text(r == null ? (_loading ? '…' : '—') : (accrued >= 9999 ? '∞' : LeaveStore.fmtDays(usable)),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
          ]),
        ),
      );
    }

    return Row(children: [
      tile('Casual (CL)', 'CL'),
      const SizedBox(width: 8),
      tile('Medical (ML)', 'ML'),
      const SizedBox(width: 8),
      tile('Earned (EL)', 'EL'),
    ]);
  }

  Widget _cycleStats() {
    final c = _cycle;
    String n(String k) => c == null ? (_loading ? '…' : '0') : LeaveStore.fmtDays(_num(c, k));
    final lop = _num(c, 'lop_days');
    return Column(children: [
      MStats([
        (n('days_worked'), 'Present', MobileUi.present),
        (n('late_count'), 'Late', MobileUi.late),
        (n('leave_taken'), 'Leave', MobileUi.leave),
        (n('permission_count'), 'Permissions', MobileUi.permission),
      ]),
      if (lop > 0) ...[
        const SizedBox(height: 8),
        MCard(
          color: MobileUi.lopBg,
          borderColor: const Color(0xFFF5C2C2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            const Icon(Icons.money_off_rounded, color: MobileUi.lop, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${LeaveStore.fmtDays(lop)} day${lop == 1 ? '' : 's'} of loss of pay so far this cycle',
                  style: const TextStyle(color: MobileUi.lop, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _quickActions() {
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppTheme.primaryBlue),
                ),
                const SizedBox(height: 6),
                Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
              ]),
            ),
          ),
        );
    return Row(children: [
      action(Icons.event_available_rounded, 'Apply leave', () => context.push('/employee/leave/apply')),
      action(Icons.schedule_rounded, 'Permission', () => context.push('/employee/leave/permission')),
      action(Icons.swap_horiz_rounded, 'Comp off', () => context.push('/employee/leave/compoff')),
      action(Icons.policy_outlined, 'HR policy', () => showHrPolicy(context)),
    ]);
  }

  Widget _waitingCard(LeaveApplication a) {
    final isPermission = a.leaveType == 'Permission';
    final date = '${a.from.day} ${_shortMonths[a.from.month - 1]}'
        '${a.to != a.from ? ' – ${a.to.day} ${_shortMonths[a.to.month - 1]}' : ''}';
    return MCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => context.go('/employee/leave-management'),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isPermission ? MobileUi.permissionBg : MobileUi.leaveBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(isPermission ? Icons.schedule_rounded : Icons.event_rounded,
              color: isPermission ? MobileUi.permission : MobileUi.leave, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a.leaveType} · $date',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(a.isHalfDay && !isPermission ? 'Half day' : 'Waiting for approval',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
          ]),
        ),
        const MChip('Pending', color: MobileUi.late, background: MobileUi.lateBg),
      ]),
    );
  }
}
