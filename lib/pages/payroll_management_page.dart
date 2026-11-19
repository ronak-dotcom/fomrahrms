import 'package:flutter/material.dart';
import '../utils/el_accrual.dart';
import '../models/app_user.dart';
import '../models/leave_store.dart';
import '../models/payslip_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../widgets/back_button.dart';
import 'payslip_run_page.dart';
import '../theme/app_theme.dart';

class PayrollManagementPage extends StatefulWidget {
  const PayrollManagementPage({super.key});

  @override
  State<PayrollManagementPage> createState() => _PayrollManagementPageState();
}

class _PayrollManagementPageState extends State<PayrollManagementPage> {
  static Color get _color => AppTheme.primaryBlue;
  static Color get _purple => AppTheme.primaryBlue;

  bool _loading = true;
  bool _elExpanded = false;
  bool _payslipsExpanded = false;
  List<AppUser> _employees = [];
  /// Deactivated accounts: people who have left, and new joiners who have not
  /// activated yet. Kept off the main list but still reachable, because a
  /// leaver can be owed a final payslip for the days they worked.
  List<AppUser> _inactive = [];
  List<LeaveApplication> _leaves = [];
  List<PayslipRequest> _payslipRequests = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        UserStore.load(),
        SupabaseService.fetchLeaveApplications().timeout(const Duration(seconds: 8)),
        SupabaseService.fetchPayslipRequests(),
      ]);
      final users  = results[0] as List<AppUser>;
      final leaves = results[1] as List<LeaveApplication>;
      final reqs   = results[2] as List<PayslipRequest>;
      if (mounted) {
        setState(() {
          // The list was filtered by role alone, so deactivated accounts
          // sat in it looking exactly like current staff.
          final onPayroll = users
              .where((u) => u.role == 'Employee' || u.role == 'Manager')
              .toList();
          _employees = onPayroll.where((u) => u.active).toList();
          _inactive  = onPayroll.where((u) => !u.active).toList();
          _leaves = leaves;
          _payslipRequests = reqs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Payslips are issued for a whole closed cycle from the payroll screen
  /// (HR confirms the counts; the database calculates and HR publishes).
  /// The per-person form that let amounts be typed in is no longer used:
  /// every payslip it produced disagreed with payroll.
  Future<void> _openGenerate(AppUser user, {PayslipRequest? request}) async {
    DateTime? cycleEnd;
    final parts = (request?.monthYear ?? '').split('-');
    if (parts.length == 2) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null) cycleEnd = DateTime(y, m, 25);
    }
    await _openPayroll(cycleEnd: cycleEnd, employeeId: user.employeeId);
  }

  Future<void> _openPayroll({DateTime? cycleEnd, String? employeeId}) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => PayslipRunPage(initialCycleEnd: cycleEnd, highlightEmployeeId: employeeId),
    ));
    _reload();
  }

  Future<void> _rejectPayslipRequest(PayslipRequest req, AppUser user) async {
    final commentCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deny Payslip Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${req.employeeName} · ${_payslipMonthLabel(req.monthYear)}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const SizedBox(height: 12),
          TextField(
            controller: commentCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Reason (optional)…',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deny Request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final reason = commentCtrl.text.trim();
    await SupabaseService.decidePayslipRequest(
        req.id, PayslipRequestStatus.rejected, UserSession.name, rejectionComment: reason);
    if (user.email.isNotEmpty) {
      NotificationService.payslipRequestDenied(
        employeeEmail: user.email,
        monthYear: req.monthYear,
        employeeRoutePrefix: NotificationService.routePrefixForRole(AppUser.userRoleFor(user.role)),
        reason: reason,
      );
    }
    _reload();
  }

  double _elUsed(AppUser u) {
    final refStr = u.elLastAvailedAt.isNotEmpty ? u.elLastAvailedAt : u.elEligibleAt;
    final cutoff = refStr.isNotEmpty ? DateTime.tryParse(refStr) : null;
    return _leaves.where((a) =>
        a.employeeName == u.name &&
        a.leaveType == 'Earned Leave' &&
        a.managerStatus == LeaveApprovalStatus.approved &&
        (cutoff == null || a.from.isAfter(cutoff)))
    .fold(0.0, (s, a) => s + a.effectiveDays);
  }

  int _elAccrued(AppUser u) => elAccruedFor(u);

  Future<void> _confirmAvail(AppUser user) async {
    await SupabaseService.confirmElAvail(user.email);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final elEmployees = _employees.where((u) => u.isElEligible).toList();
    final pendingCount = elEmployees.where((u) => u.elAvailRequestedAt.isNotEmpty).length;
    final narrow = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(child: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: EdgeInsets.fromLTRB(narrow ? 12 : 24, narrow ? 16 : 24, narrow ? 12 : 24, 16),
          child: Row(children: [
            const NavBackButton(),
            SizedBox(width: narrow ? 4 : 8),
            if (!narrow) ...[
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.account_balance_wallet_rounded, color: _color, size: 26),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Payroll Management',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium),
                if (!narrow) ...[
                  const Text('HR Management', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ]),
            ),
            FilledButton.icon(
              onPressed: () => _openPayroll(),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: Text(narrow ? 'Payslips' : 'Issue payslips'),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh_rounded, color: _color),
              onPressed: _reload,
            ),
          ]),
        ),
        const Divider(height: 1),

        // ── Body ────────────────────────────────────────────────────────────
        _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // ── EL Encashment button/section ─────────────────────
                    GestureDetector(
                      onTap: () => setState(() => _elExpanded = !_elExpanded),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: _elExpanded
                              ? _purple.withValues(alpha: 0.1)
                              : _purple.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _purple.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          Container(
                            width: 38, height: 38,
                            decoration: BoxDecoration(
                              color: _purple.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.card_giftcard_rounded, color: _purple, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('EL Encashment',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _purple)),
                              Text(
                                elEmployees.isEmpty
                                    ? 'No EL-eligible employees'
                                    : pendingCount > 0
                                        ? '$pendingCount pending request${pendingCount > 1 ? 's' : ''} · ${elEmployees.length} eligible'
                                        : '${elEmployees.length} eligible employee${elEmployees.length > 1 ? 's' : ''}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                              ),
                            ]),
                          ),
                          if (pendingCount > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.shade300),
                              ),
                              child: Text('$pendingCount pending',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                      color: Colors.orange.shade800)),
                            ),
                          Icon(
                            _elExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: _purple, size: 22,
                          ),
                        ]),
                      ),
                    ),

                    // ── EL-eligible employees (expanded) ─────────────────
                    if (_elExpanded) ...[
                      const SizedBox(height: 10),
                      if (elEmployees.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _purple.withValues(alpha: 0.15)),
                          ),
                          child: Row(children: [
                            Icon(Icons.info_outline_rounded, color: Colors.grey.shade400, size: 20),
                            const SizedBox(width: 10),
                            Text('No employees have EL eligibility yet.',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                          ]),
                        )
                      else
                        ...elEmployees.map((u) {
                          final accrued   = _elAccrued(u);
                          final used      = _elUsed(u);
                          final available = (accrued - used).clamp(0.0, accrued.toDouble());
                          final hasPending = u.elAvailRequestedAt.isNotEmpty;
                          final lastAvailed = u.elLastAvailedAt.isNotEmpty
                              ? DateTime.tryParse(u.elLastAvailedAt) : null;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _purple.withValues(alpha: 0.15)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              // Employee row
                              Row(children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: _purple.withValues(alpha: 0.12),
                                  child: Text(
                                    u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                    style: TextStyle(color: _purple,
                                        fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(u.name,
                                      style: const TextStyle(fontSize: 13,
                                          fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                                  Text(
                                    u.designation.isEmpty ? u.role : '${u.designation} · ${u.role}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                                  ),
                                ])),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _purple.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: _purple.withValues(alpha: 0.25)),
                                  ),
                                  child: Text('EL Eligible',
                                      style: TextStyle(fontSize: 10, color: _purple,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                              const SizedBox(height: 12),

                              // EL balance row
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: _purple.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(children: [
                                  _BalanceStat(
                                    label: 'Accrued',
                                    value: '$accrued d',
                                    color: const Color(0xFF6B7280),
                                  ),
                                  _Divider(),
                                  _BalanceStat(
                                    label: 'Used',
                                    value: used % 1 == 0
                                        ? '${used.toInt()} d'
                                        : '${used.toStringAsFixed(1)} d',
                                    color: Colors.orange.shade700,
                                  ),
                                  _Divider(),
                                  _BalanceStat(
                                    label: 'Available',
                                    value: available % 1 == 0
                                        ? '${available.toInt()} d'
                                        : '${available.toStringAsFixed(1)} d',
                                    color: Colors.green.shade700,
                                  ),
                                  if (lastAvailed != null) ...[
                                    _Divider(),
                                    _BalanceStat(
                                      label: 'Last Encashed',
                                      value: _fmtDate(lastAvailed),
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ],
                                ]),
                              ),
                              const SizedBox(height: 10),

                              // Encashment action
                              if (hasPending)
                                Row(children: [
                                  Icon(Icons.hourglass_empty_rounded,
                                      size: 14, color: Colors.orange.shade700),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text('Encash EL request pending confirmation',
                                        style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                                  ),
                                  _ConfirmButton(
                                    onConfirm: () => _confirmAvail(u),
                                  ),
                                ])
                              else
                                Text('No pending encashment request',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                            ]),
                          );
                        }),
                    ],

                    const SizedBox(height: 20),

                    // ── Payslip requests button/section ──────────────────
                    _PayslipRequestsHeader(
                      requests: _payslipRequests,
                      expanded: _payslipsExpanded,
                      onTap: () => setState(() => _payslipsExpanded = !_payslipsExpanded),
                    ),
                    if (_payslipsExpanded) ...[
                      const SizedBox(height: 10),
                      if (_payslipRequests.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _purple.withValues(alpha: 0.15)),
                          ),
                          child: Row(children: [
                            Icon(Icons.info_outline_rounded, color: Colors.grey.shade400, size: 20),
                            const SizedBox(width: 10),
                            Text('No payslip requests yet.',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                          ]),
                        )
                      else
                        ..._payslipRequests.map((req) {
                          AppUser? match;
                          for (final u in _employees) {
                            if (u.employeeId == req.employeeId) { match = u; break; }
                          }
                          return _PayslipRequestTile(
                            request: req,
                            user: match,
                            onReview: match == null
                                ? null
                                : () => _openGenerate(match!, request: req),
                            onReject: match == null
                                ? null
                                : () => _rejectPayslipRequest(req, match!),
                          );
                        }),
                    ],

                    const SizedBox(height: 20),

                    // ── All employees list ────────────────────────────────
                    Text('All Employees',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text('Tap an employee to generate or view their payslip.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                    const SizedBox(height: 10),
                    ..._employees.map((u) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => _openGenerate(u),
                        child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _color.withValues(alpha: 0.12),
                            child: Text(
                              u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                              style: TextStyle(color: _color,
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(u.name,
                                style: const TextStyle(fontSize: 13,
                                    fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                            Text(
                              u.designation.isEmpty ? u.role : '${u.designation} · ${u.role}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                            ),
                          ])),
                          _StatusChip(u.leaveStatus),
                        ]),
                      ),
                      ),
                    )),

                    // Deactivated accounts, collapsed. Not dropped outright:
                    // someone who left mid-cycle may still be owed a final
                    // payslip, and hiding them would leave no way to raise it.
                    if (_inactive.isNotEmpty)
                      Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            'Inactive accounts (${_inactive.length})',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade600),
                          ),
                          subtitle: Text(
                            'Exited, or not activated yet. Open one only to '
                            'raise a final payslip.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade400),
                          ),
                          children: [
                            for (final u in _inactive)
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: Colors.grey.shade50,
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.person_off_rounded,
                                      color: Colors.grey.shade500),
                                  title: Text(u.name,
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700)),
                                  subtitle: Text(
                                      '${u.employeeId} · inactive',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade500)),
                                  trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                      size: 18),
                                  onTap: () => _openGenerate(u),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ]),
                ),
      ])),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ── Balance stat ───────────────────────────────────────────────────────────────
class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _BalanceStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280))),
      ]),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: AppTheme.primaryBlue.withValues(alpha: 0.1),
          margin: const EdgeInsets.symmetric(horizontal: 4));
}

// ── Confirm button with loading ────────────────────────────────────────────────
class _ConfirmButton extends StatefulWidget {
  final Future<void> Function() onConfirm;
  const _ConfirmButton({required this.onConfirm});

  @override
  State<_ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<_ConfirmButton> {
  static Color get _purple => AppTheme.primaryBlue;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _loading ? null : () async {
        setState(() => _loading = true);
        await widget.onConfirm();
        if (mounted) setState(() => _loading = false);
      },
      icon: _loading
          ? const SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check_rounded, size: 14),
      label: const Text('Confirm', style: TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ── Status chip ────────────────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'EL Eligible' => AppTheme.primaryBlue,
      'On-Roll'     => const Color(0xFF22C55E),
      _             => const Color(0xFF6B7280),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(status,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Payslip requests header/tile ────────────────────────────────────────────
String _payslipMonthLabel(String monthYear) {
  const names = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
  final parts = monthYear.split('-');
  if (parts.length != 2) return monthYear;
  final m = int.tryParse(parts[1]);
  if (m == null || m < 1 || m > 12) return monthYear;
  return '${names[m - 1]} ${parts[0]}';
}

class _PayslipRequestsHeader extends StatelessWidget {
  final List<PayslipRequest> requests;
  final bool expanded;
  final VoidCallback onTap;
  const _PayslipRequestsHeader(
      {required this.requests, required this.expanded, required this.onTap});

  static Color get _purple => AppTheme.primaryBlue;

  @override
  Widget build(BuildContext context) {
    final pending = requests.where((r) => r.status == PayslipRequestStatus.pending).length;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: expanded ? _purple.withValues(alpha: 0.1) : _purple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _purple.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.receipt_long_rounded, color: _purple, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Payslip Requests',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _purple)),
              Text(
                requests.isEmpty
                    ? 'No requests yet'
                    : pending > 0
                        ? '$pending pending · ${requests.length} total'
                        : '${requests.length} total',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ]),
          ),
          if (pending > 0)
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Text('$pending pending',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: Colors.orange.shade800)),
            ),
          Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: _purple, size: 22),
        ]),
      ),
    );
  }
}

class _PayslipRequestTile extends StatelessWidget {
  final PayslipRequest request;
  final AppUser? user;
  final VoidCallback? onReview;
  final VoidCallback? onReject;
  const _PayslipRequestTile({
    required this.request,
    required this.user,
    required this.onReview,
    this.onReject,
  });

  static Color get _purple => AppTheme.primaryBlue;

  @override
  Widget build(BuildContext context) {
    final (chipColor, chipLabel) = switch (request.status) {
      PayslipRequestStatus.pending  => (Colors.orange.shade700, 'Pending'),
      PayslipRequestStatus.approved => (Colors.green.shade700, 'Approved'),
      PayslipRequestStatus.rejected => (Colors.red.shade700, 'Rejected'),
    };
    final isPending = request.status == PayslipRequestStatus.pending;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _purple.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _purple.withValues(alpha: 0.12),
            child: Text(
              request.employeeName.isNotEmpty ? request.employeeName[0].toUpperCase() : '?',
              style: TextStyle(color: _purple, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.employeeName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              Text(_payslipMonthLabel(request.monthYear),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: chipColor.withValues(alpha: 0.3)),
            ),
            child: Text(chipLabel,
                style: TextStyle(fontSize: 10, color: chipColor, fontWeight: FontWeight.w700)),
          ),
          if (isPending)
            TextButton(
              onPressed: onReject,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              child: const Text('Deny', style: TextStyle(fontSize: 12)),
            ),
          ElevatedButton(
            onPressed: onReview,
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Review', style: TextStyle(fontSize: 12)),
          ),
        ]),
        if (request.status == PayslipRequestStatus.rejected && request.rejectionComment.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Reason: ${request.rejectionComment}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }
}
