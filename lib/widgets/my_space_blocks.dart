import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/app_user.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../models/payslip_store.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../theme/app_theme.dart';
import '../utils/attendance_time.dart';
import 'dashboard_info_blocks.dart' show InfoCard;

const _months = ['January', 'February', 'March', 'April', 'May', 'June',
                  'July', 'August', 'September', 'October', 'November', 'December'];

// ── My Space row (shared across HR/Employee/Manager dashboards) ───────────────

// Every card in the dashboard's top "My Space" row (Quick Access / My Tasks /
// Task Analytics) sizes to its own content — none of them scroll internally
// or overflow — but on a wide screen they're stretched to match the row's
// tallest card (via IntrinsicHeight) so the row still reads as one even
// strip instead of a ragged bottom edge. None of the three cards contain a
// ListView/CustomScrollView/LayoutBuilder anymore, so this is safe — those
// are the widgets that can't report an intrinsic height.
class MySpaceRow extends StatelessWidget {
  final List<Widget> children;
  const MySpaceRow({super.key, required this.children});

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

// ── My Leave ──────────────────────────────────────────────────────────────────

class MyLeaveBlock extends StatefulWidget {
  final String applyRoute;
  final bool showIcon;
  final bool compact;
  const MyLeaveBlock({super.key, required this.applyRoute, this.showIcon = true, this.compact = false});

  @override
  State<MyLeaveBlock> createState() => _MyLeaveBlockState();
}

class _MyLeaveBlockState extends State<MyLeaveBlock> {
  bool _loading = true;
  int? _clAvail;
  int _pending = 0;

  @override
  void initState() { super.initState(); _load(); }

  bool _isThisMonth(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month;
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        SupabaseService.fetchLeaveApplications().timeout(const Duration(seconds: 8)),
        UserStore.load(),
      ]);
      final leaves = results[0] as List<LeaveApplication>;
      final users  = results[1] as List<AppUser>;
      final mine = leaves.where((a) => a.employeeName == UserSession.name).toList();
      final match = users.where((u) => u.name == UserSession.name).toList();
      final user = match.isNotEmpty ? match.first : null;

      final usedCl = mine
          .where((a) =>
              a.managerStatus == LeaveApprovalStatus.approved &&
              _isThisMonth(a.from) &&
              a.bucket == 'CL')
          .fold(0.0, (s, a) => s + a.effectiveDays);
      final pending = mine.where((a) => a.effectiveStatus == LeaveApprovalStatus.pending).length;

      if (mounted) setState(() {
        _clAvail = LeaveStore.availableFor('CL') ??
            (user != null ? (user.monthlyCl - usedCl).clamp(0, 99).toInt() : null);
        _pending = pending;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      icon: Icons.event_available_rounded,
      title: 'My Leave',
      accentColor: AppTheme.success,
      showIcon: widget.showIcon,
      compact: widget.compact,
      trailing: widget.compact ? _HeaderChevron(route: widget.applyRoute) : null,
      child: _loading
          ? const _MiniLoader()
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StatRow('Available Leaves', _clAvail != null ? '$_clAvail Day${_clAvail == 1 ? '' : 's'}' : '—', compact: widget.compact),
              SizedBox(height: widget.compact ? 8 : 12),
              _StatRow('Pending Requests', '$_pending', compact: widget.compact),
              SizedBox(height: widget.compact ? 10 : 14),
              _ActionLink(label: 'Apply Leave', route: widget.applyRoute, color: AppTheme.success),
            ]),
    );
  }
}

// ── My Payslips ───────────────────────────────────────────────────────────────

class MyPayslipBlock extends StatefulWidget {
  final String viewRoute;
  final bool showIcon;
  final bool compact;
  const MyPayslipBlock({super.key, required this.viewRoute, this.showIcon = true, this.compact = false});

  @override
  State<MyPayslipBlock> createState() => _MyPayslipBlockState();
}

class _MyPayslipBlockState extends State<MyPayslipBlock> {
  bool _loading = true;
  Payslip? _latest;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await SupabaseService.fetchPayslips(UserSession.employeeId);
    if (mounted) setState(() {
      _latest = list.isNotEmpty ? list.first : null;
      _loading = false;
    });
  }

  String? get _monthLabel {
    final p = _latest?.monthYear.split('-');
    if (p == null || p.length != 2) return null;
    final m = int.tryParse(p[1]);
    if (m == null || m < 1 || m > 12) return null;
    return '${_months[m - 1]} ${p[0]}';
  }

  String get _amountLabel {
    final p = _latest;
    if (p == null) return '—';
    return '₹${p.netPay.round()}';
  }

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      icon: Icons.receipt_long_rounded,
      title: 'My Payslips',
      accentColor: AppTheme.warning,
      showIcon: widget.showIcon,
      compact: widget.compact,
      trailing: widget.compact ? _HeaderChevron(route: widget.viewRoute) : null,
      child: _loading
          ? const _MiniLoader()
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StatRow('Latest Payslip', _monthLabel ?? 'None yet', compact: widget.compact),
              SizedBox(height: widget.compact ? 8 : 12),
              _StatRow('Amount', _amountLabel, compact: widget.compact),
              SizedBox(height: widget.compact ? 10 : 14),
              _ActionLink(label: 'View Payslips', route: widget.viewRoute, color: AppTheme.warning),
            ]),
    );
  }
}

// ── My Attendance ─────────────────────────────────────────────────────────────

class MyAttendanceSummaryBlock extends StatefulWidget {
  final String viewRoute;
  final bool showIcon;
  final bool compact;
  const MyAttendanceSummaryBlock({super.key, required this.viewRoute, this.showIcon = true, this.compact = false});

  @override
  State<MyAttendanceSummaryBlock> createState() => _MyAttendanceSummaryBlockState();
}

class _MyAttendanceSummaryBlockState extends State<MyAttendanceSummaryBlock> {
  bool _loading = true;
  int _todayMinutes = 0;
  int _weekMinutes = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final empId = UserSession.employeeId;
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));

    final today = await SupabaseService.fetchTodayAttendance(empId);
    final todayMin = today != null
        ? attendanceMinutesBetween(today.checkInTime, today.checkOutTime) ?? 0
        : 0;

    final months = <(int, int)>{(now.year, now.month), (weekStart.year, weekStart.month)};
    final recordLists = await Future.wait(
        months.map((m) => SupabaseService.fetchAttendanceForMonth(empId, m.$1, m.$2)));
    var weekMin = 0;
    for (final list in recordLists) {
      for (final rec in list) {
        final parts = rec.date.split('/');
        if (parts.length != 3) continue;
        final d = DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
        if (d == null || d.isBefore(weekStart) || d.isAfter(now)) continue;
        weekMin += attendanceMinutesBetween(rec.checkInTime, rec.checkOutTime) ?? 0;
      }
    }

    if (mounted) setState(() {
      _todayMinutes = todayMin;
      _weekMinutes = weekMin;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return InfoCard(
      icon: Icons.access_time_filled_rounded,
      title: 'My Attendance',
      accentColor: AppTheme.primaryBlue,
      showIcon: widget.showIcon,
      compact: widget.compact,
      trailing: widget.compact ? _HeaderChevron(route: widget.viewRoute) : null,
      child: _loading
          ? const _MiniLoader()
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StatRow("Today's Hours", formatHoursMinutes(_todayMinutes), compact: widget.compact),
              SizedBox(height: widget.compact ? 8 : 12),
              _StatRow('This Week', formatHoursMinutes(_weekMinutes), compact: widget.compact),
              SizedBox(height: widget.compact ? 10 : 14),
              _ActionLink(label: 'View Attendance', route: widget.viewRoute, color: AppTheme.primaryBlue),
            ]),
    );
  }
}

// ── Shared presentational bits ────────────────────────────────────────────────

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool compact;
  const _StatRow(this.label, this.value, {this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: compact ? 16 : 19, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
    ]);
  }
}

// Small ">" affordance shown in the header of compact cards instead of a
// refresh icon, hinting the whole card leads to its detail route.
class _HeaderChevron extends StatelessWidget {
  final String route;
  const _HeaderChevron({required this.route});

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
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: BorderRadius.circular(6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 4),
        Icon(Icons.arrow_forward_rounded, size: 14, color: color),
      ]),
    );
  }
}

class _MiniLoader extends StatelessWidget {
  const _MiniLoader();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
}
