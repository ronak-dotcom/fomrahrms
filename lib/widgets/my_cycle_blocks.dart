import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/app_user.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../theme/app_theme.dart';
import '../utils/attendance_cycle.dart';
import 'dashboard_info_blocks.dart' show InfoCard;

// Employee-facing views of data the app already computed but only ever
// showed to management: how the current pay cycle is going, what leave is
// actually left by type, and what holidays are coming.
//
// The punctuality figures in particular come from the same
// attendance_cycle_report() the management punctuality export uses, scoped
// to the caller's own employee id — so what an employee sees about their
// own lates and LOP is the same number payroll sees, rather than a second
// calculation that could drift.

// ── My Pay Cycle ──────────────────────────────────────────────────────────

class MyCycleSummaryBlock extends StatefulWidget {
  final String viewRoute;
  final bool compact;
  const MyCycleSummaryBlock({super.key, required this.viewRoute, this.compact = false});

  @override
  State<MyCycleSummaryBlock> createState() => _MyCycleSummaryBlockState();
}

class _MyCycleSummaryBlockState extends State<MyCycleSummaryBlock> {
  bool _loading = true;
  Map<String, dynamic>? _row;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final empId = UserSession.employeeId;
    if (empId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final cycleEnd = attendanceCycleEnd(DateTime.now());
      final rows = await SupabaseService
          .fetchCycleReport(cycleEnd, employeeIds: [empId])
          .timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _row = rows.isNotEmpty ? rows.first : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _int(String key) {
    final v = _row?[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final lop = _int('lop_days');
    final lates = _int('late_count');
    final graceLates = _int('grace_late_count');
    final permissions = _int('permission_count');

    return InfoCard(
      icon: Icons.pending_actions_rounded,
      title: 'My Pay Cycle',
      accentColor: AppTheme.warning,
      compact: widget.compact,
      trailing: _Chevron(route: widget.viewRoute),
      child: _loading
          ? const _MiniLoader()
          : _row == null
              ? const Text('No attendance recorded for this cycle yet.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(attendanceCycleRange(attendanceCycleEnd(DateTime.now())),
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  // LOP first: it is the only figure here that costs money,
                  // and it's the thing people actually want to know.
                  _MetricRow(
                    label: 'Loss of Pay',
                    value: lop == 0 ? 'None' : '$lop ${lop == 1 ? 'day' : 'days'}',
                    highlight: lop > 0,
                  ),
                  const SizedBox(height: 8),
                  _MetricRow(
                    label: 'Late Arrivals',
                    // Grace-window lates are shown separately rather than
                    // hidden: they don't cost anything, but someone
                    // repeatedly at the edge of the window benefits from
                    // knowing before it becomes a deduction.
                    value: graceLates > 0 ? '$lates (+$graceLates in grace)' : '$lates',
                    highlight: lates > 0,
                  ),
                  const SizedBox(height: 8),
                  _MetricRow(
                    label: 'Permissions Used',
                    value: '$permissions',
                  ),
                  const SizedBox(height: 12),
                  _ActionLink(
                      label: 'View My Attendance',
                      route: widget.viewRoute,
                      color: AppTheme.warning),
                ]),
    );
  }
}

// ── My Leave Balance ──────────────────────────────────────────────────────

class MyLeaveBalanceBlock extends StatefulWidget {
  final String viewRoute;
  final bool compact;
  const MyLeaveBalanceBlock({super.key, required this.viewRoute, this.compact = false});

  @override
  State<MyLeaveBalanceBlock> createState() => _MyLeaveBalanceBlockState();
}

class _MyLeaveBalanceBlockState extends State<MyLeaveBalanceBlock> {
  bool _loading = true;
  AppUser? _me;
  double _usedCl = 0, _usedMl = 0, _usedEl = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final users = await UserStore.load();
      final match = users.where((u) =>
          u.email.trim().toLowerCase() == UserSession.email.trim().toLowerCase());
      final me = match.isNotEmpty ? match.first : null;

      // Usage is counted against the attendance cycle (26th->25th), not the
      // calendar month, because that is the period entitlement resets on.
      final cycleEnd = attendanceCycleEnd(DateTime.now());
      final cycleStart = attendanceCycleStart(cycleEnd);
      final leaves = await SupabaseService.fetchLeaveApplications()
          .timeout(const Duration(seconds: 8));
      final mine = leaves.where((a) =>
          a.employeeName == UserSession.name &&
          a.managerStatus == LeaveApprovalStatus.approved &&
          !a.from.isBefore(cycleStart) &&
          !a.from.isAfter(cycleEnd));

      double cl = 0, ml = 0, el = 0;
      for (final a in mine) {
        switch (a.bucket) {
          case 'CL': cl += a.effectiveDays;
          case 'ML': ml += a.effectiveDays;
          case 'EL': el += a.effectiveDays;
        }
      }

      if (mounted) {
        setState(() {
          _me = me; _usedCl = cl; _usedMl = ml; _usedEl = el;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _left(int entitled, double used) {
    if (entitled >= 9999) return 'Unlimited';
    final left = (entitled - used).clamp(0, 9999);
    return left == left.roundToDouble() ? '${left.toInt()}' : left.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return InfoCard(
      icon: Icons.event_available_rounded,
      title: 'My Leave Balance',
      accentColor: AppTheme.success,
      compact: widget.compact,
      trailing: _Chevron(route: widget.viewRoute),
      child: _loading
          ? const _MiniLoader()
          : me == null
              ? const Text('Could not load your leave entitlement.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Probation staff get one leave of any type per cycle and
                  // no permission at all — showing them a CL/ML/EL breakdown
                  // would imply an entitlement they don't have.
                  if (!me.isOnroll && !me.exemptFromLeaveRules) ...[
                    _StatusChip(label: me.leaveStatus, color: AppTheme.warning),
                    const SizedBox(height: 10),
                    _MetricRow(
                      label: 'Leaves left this cycle',
                      value: _left(AppUser.probationLeavesPerCycle, _usedCl + _usedMl + _usedEl),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'On probation: one leave per cycle, any type. Permission is '
                      'available after confirmation.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.35),
                    ),
                  ] else ...[
                    _StatusChip(label: me.leaveStatus, color: AppTheme.success),
                    const SizedBox(height: 10),
                    _MetricRow(label: 'Casual Leave', value: _left(me.monthlyCl, _usedCl)),
                    const SizedBox(height: 8),
                    _MetricRow(label: 'Medical Leave', value: _left(me.monthlyMl, _usedMl)),
                    const SizedBox(height: 8),
                    // EL only accrues once eligible, so a plain "0" would
                    // look like it was used up rather than not yet earned.
                    _MetricRow(
                      label: 'Earned Leave',
                      value: me.isElEligible ? _left(me.monthlyEl, _usedEl) : 'Not yet eligible',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _ActionLink(
                      label: 'Apply for Leave',
                      route: widget.viewRoute,
                      color: AppTheme.success),
                ]),
    );
  }
}

// ── Upcoming Holidays ─────────────────────────────────────────────────────

class UpcomingHolidaysBlock extends StatefulWidget {
  final bool compact;
  const UpcomingHolidaysBlock({super.key, this.compact = false});

  @override
  State<UpcomingHolidaysBlock> createState() => _UpcomingHolidaysBlockState();
}

class _UpcomingHolidaysBlockState extends State<UpcomingHolidaysBlock> {
  bool _loading = true;
  List<({DateTime date, String name})> _upcoming = const [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Pull next year too, so late-December doesn't show an empty card.
      final rows = [
        ...await SupabaseService.fetchHolidays(now.year),
        ...await SupabaseService.fetchHolidays(now.year + 1),
      ];
      final parsed = <({DateTime date, String name})>[];
      for (final r in rows) {
        final raw = (r['holiday_date'] as String?) ?? '';
        if (raw.isEmpty) continue;
        final d = DateTime.tryParse(raw.substring(0, 10));
        if (d == null || d.isBefore(today)) continue;
        parsed.add((date: d, name: (r['name'] as String?) ?? 'Holiday'));
      }
      parsed.sort((a, b) => a.date.compareTo(b.date));

      if (mounted) {
        setState(() { _upcoming = parsed.take(3).toList(); _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _mon = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  String _daysAway(DateTime d) {
    final now = DateTime.now();
    final days = d.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return 'in $days days';
  }

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      icon: Icons.celebration_rounded,
      title: 'Upcoming Holidays',
      accentColor: AppTheme.purple,
      compact: widget.compact,
      child: _loading
          ? const _MiniLoader()
          : _upcoming.isEmpty
              ? const Text('No holidays scheduled.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final h in _upcoming) ...[
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 40,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.purple.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(children: [
                          Text('${h.date.day}',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                  color: AppTheme.purple)),
                          Text(_mon[h.date.month - 1],
                              style: TextStyle(fontSize: 9.5, color: AppTheme.purple)),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(h.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5,
                                  fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          Text(_daysAway(h.date),
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        ]),
                      ),
                    ]),
                    if (h != _upcoming.last) const SizedBox(height: 10),
                  ],
                ]),
    );
  }
}

// ── Shared bits ───────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _MetricRow({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(
        child: Text(label,
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500)),
      ),
      const SizedBox(width: 8),
      Text(value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: highlight ? AppTheme.warning : AppTheme.textPrimary)),
    ]);
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _Chevron extends StatelessWidget {
  final String route;
  const _Chevron({required this.route});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Icon(Icons.chevron_right_rounded,
          size: 20, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
    );
  }
}

class _ActionLink extends StatelessWidget {
  final String label;
  final String route;
  final Color color;
  const _ActionLink({required this.label, required this.route, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(width: 2),
        Icon(Icons.arrow_forward_rounded, size: 13, color: color),
      ]),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: SizedBox(
          height: 18, width: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}
