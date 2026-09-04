import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/app_user.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../theme/app_theme.dart';
import '../utils/attendance_cycle.dart';
import '../widgets/back_button.dart';

/// What the employee actually has left, per leave type.
///
/// This page previously showed three EMPTY text boxes asking the employee to
/// type in their own available, used and pending leave. It displayed no real
/// data and saved nowhere — the numbers existed only inside apply_leave_page,
/// computed correctly but never surfaced, so "how much leave do I have?"
/// could only be answered by starting an application and reading the form.
class LeaveBalancePage extends StatefulWidget {
  const LeaveBalancePage({super.key});

  @override
  State<LeaveBalancePage> createState() => _LeaveBalancePageState();
}

class _LeaveBalancePageState extends State<LeaveBalancePage> {
  bool _loading = true;
  AppUser? _me;
  double _usedCl = 0, _usedMl = 0, _usedEl = 0;
  int _pending = 0;
  List<LeaveApplication> _recent = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        UserStore.load(),
        SupabaseService.fetchLeaveApplications(),
      ]);
      final users = (results[0] as List).cast<AppUser>();
      final leaves = (results[1] as List).cast<LeaveApplication>();

      final match = users.where((u) =>
          u.email.trim().toLowerCase() == UserSession.email.trim().toLowerCase());
      final me = match.isNotEmpty ? match.first : null;

      // Entitlement resets on the attendance cycle (26th->25th), not the
      // calendar month, so usage is counted over the same window. Counting a
      // calendar month here would show a remaining figure that disagrees with
      // what apply_leave_page actually permits.
      final cycleEnd = attendanceCycleEnd(DateTime.now());
      final cycleStart = attendanceCycleStart(cycleEnd);

      final mine = leaves
          .where((a) => a.employeeName == UserSession.name)
          .toList()
        ..sort((a, b) => b.from.compareTo(a.from));

      double cl = 0, ml = 0, el = 0;
      for (final a in mine) {
        if (a.managerStatus != LeaveApprovalStatus.approved) continue;
        if (a.from.isBefore(cycleStart) || a.from.isAfter(cycleEnd)) continue;
        switch (a.bucket) {
          case 'CL': cl += a.effectiveDays;
          case 'ML': ml += a.effectiveDays;
          case 'EL': el += a.effectiveDays;
        }
      }

      if (!mounted) return;
      setState(() {
        _me = me;
        _usedCl = cl;
        _usedMl = ml;
        _usedEl = el;
        _pending = mine
            .where((a) => a.managerStatus == LeaveApprovalStatus.pending)
            .length;
        _recent = mine.take(5).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final onProbation = me != null && !me.isOnroll && !me.exemptFromLeaveRules;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const NavBackButton(),
              const SizedBox(height: 8),
              Text('My Leave Balance',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryBlue)),
              const SizedBox(height: 4),
              Text(attendanceCycleRange(attendanceCycleEnd(DateTime.now())),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 18),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (me == null)
                const Text('Could not load your leave entitlement.',
                    style: TextStyle(color: AppTheme.textSecondary))
              else ...[
                if (onProbation)
                  // A CL/ML/EL breakdown would imply an entitlement probation
                  // staff do not have: they get one leave of any type.
                  _BalanceCard(
                    label: 'Leave this cycle',
                    note: 'On probation — one leave per cycle, any type. '
                        'Permission becomes available after confirmation.',
                    entitled: AppUser.probationLeavesPerCycle.toDouble(),
                    used: _usedCl + _usedMl + _usedEl,
                    color: AppTheme.warning,
                  )
                else ...[
                  _BalanceCard(
                    label: 'Casual Leave',
                    entitled: me.monthlyCl.toDouble(),
                    used: _usedCl,
                    color: AppTheme.primaryBlue,
                  ),
                  const SizedBox(height: 10),
                  _BalanceCard(
                    label: 'Medical Leave',
                    entitled: me.monthlyMl.toDouble(),
                    used: _usedMl,
                    color: Colors.teal.shade600,
                  ),
                  const SizedBox(height: 10),
                  // EL only accrues once eligible; a bare 0 reads as "used
                  // up" rather than "not yet earned".
                  _BalanceCard(
                    label: 'Earned Leave',
                    note: me.isElEligible ? null : 'Not yet eligible',
                    entitled: me.isElEligible ? me.monthlyEl.toDouble() : 0,
                    used: _usedEl,
                    color: Colors.deepPurple.shade400,
                    disabled: !me.isElEligible,
                  ),
                ],

                if (_pending > 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.pending_actions_rounded,
                          size: 16, color: AppTheme.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_pending request${_pending == 1 ? '' : 's'} awaiting '
                          'approval — not yet deducted above.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/employee/leave/apply'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Apply for Leave'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                    ),
                  ),
                ),

                if (_recent.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Recent Requests',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final a in _recent) _RequestTile(app: a),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String label;
  final String? note;
  final double entitled;
  final double used;
  final Color color;
  final bool disabled;

  const _BalanceCard({
    required this.label,
    required this.entitled,
    required this.used,
    required this.color,
    this.note,
    this.disabled = false,
  });

  static String _f(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final unlimited = entitled >= 9999;
    final left = (entitled - used).clamp(0.0, 9999.0);
    final ratio =
        (entitled <= 0 || unlimited) ? 0.0 : (used / entitled).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: disabled
                        ? AppTheme.textSecondary
                        : AppTheme.textPrimary)),
          ),
          Text(
            disabled ? '—' : (unlimited ? 'Unlimited' : _f(left)),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: disabled ? AppTheme.textSecondary : color),
          ),
          if (!disabled && !unlimited)
            const Padding(
              padding: EdgeInsets.only(left: 4, top: 6),
              child: Text('left',
                  style:
                      TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ),
        ]),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note!,
              style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textSecondary,
                  height: 1.35)),
        ],
        if (!disabled && !unlimited) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text('${_f(used)} of ${_f(entitled)} used this cycle',
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ]),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final LeaveApplication app;
  const _RequestTile({required this.app});

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (app.managerStatus) {
      LeaveApprovalStatus.approved => ('Approved', AppTheme.success),
      LeaveApprovalStatus.denied => ('Denied', AppTheme.error),
      _ => ('Pending', AppTheme.warning),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        title: Text('${app.leaveType} · ${_d(app.from)}–${_d(app.to)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('${app.effectiveDays} day(s) · ${app.bucket}',
            style: const TextStyle(fontSize: 11.5)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ),
      ),
    );
  }
}
