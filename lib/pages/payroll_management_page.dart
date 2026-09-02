import 'package:flutter/material.dart';
import '../utils/el_accrual.dart';
import '../models/app_user.dart';
import '../models/attendance_store.dart';
import '../models/leave_store.dart';
import '../models/office_timing.dart';
import '../models/payslip_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../utils/checkin_status.dart';
import '../widgets/back_button.dart';
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
          _employees = users
              .where((u) => u.role == 'Employee' || u.role == 'Manager')
              .toList();
          _leaves = leaves;
          _payslipRequests = reqs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openGenerate(AppUser user, {PayslipRequest? request}) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => GeneratePayslipPage(user: user, request: request),
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

// ── Generate / review payslip page ──────────────────────────────────────────

/// A single editable earnings line driven by a dropdown of preset percentage
/// options, plus a "Custom amount" option that reveals a manual field.
class _OptionField extends StatefulWidget {
  final String label;
  final List<PayOption> options;
  final int defaultIndex;
  final double grossPay;
  final double basic;
  final ValueChanged<double> onChanged;
  const _OptionField({
    required this.label,
    required this.options,
    required this.defaultIndex,
    required this.grossPay,
    required this.basic,
    required this.onChanged,
  });

  @override
  State<_OptionField> createState() => _OptionFieldState();
}

class _OptionFieldState extends State<_OptionField> {
  static Color get _purple => AppTheme.primaryBlue;
  late int _index = widget.defaultIndex;
  bool _custom = false;
  late final TextEditingController _customCtrl = TextEditingController();

  double get _amount => _custom
      ? (double.tryParse(_customCtrl.text.trim()) ?? 0)
      : widget.options[_index].amount(widget.grossPay, widget.basic);

  @override
  void initState() {
    super.initState();
    _emit();
  }

  @override
  void didUpdateWidget(covariant _OptionField old) {
    super.didUpdateWidget(old);
    if (old.grossPay != widget.grossPay || old.basic != widget.basic) _emit();
  }

  void _emit() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(_amount);
      });

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: 2,
          child: Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<int>(
            value: _custom ? -1 : _index,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            items: [
              ...List.generate(widget.options.length, (i) =>
                  DropdownMenuItem(value: i, child: Text(widget.options[i].label, style: const TextStyle(fontSize: 12)))),
              const DropdownMenuItem(value: -1, child: Text('Custom amount', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                if (v == -1) {
                  _custom = true;
                } else {
                  _custom = false;
                  _index = v;
                }
              });
              _emit();
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: _custom
              ? TextField(
                  controller: _customCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: '₹',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _emit(),
                )
              : Text('₹${_amount.toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _purple)),
        ),
      ]),
    );
  }
}

/// An auto-computed amount row that can optionally be overridden by hand.
/// Shows the computed value with an edit icon; tapping it reveals a text
/// field. A reset icon clears the override and reverts to the auto value.
class _EditableAmount extends StatefulWidget {
  final String label;
  final double autoValue;
  final double? overrideValue;
  final ValueChanged<double?> onChanged;
  const _EditableAmount({
    required this.label,
    required this.autoValue,
    required this.overrideValue,
    required this.onChanged,
  });

  @override
  State<_EditableAmount> createState() => _EditableAmountState();
}

class _EditableAmountState extends State<_EditableAmount> {
  static Color get _purple => AppTheme.primaryBlue;
  bool _editing = false;
  late final TextEditingController _ctrl = TextEditingController(
      text: (widget.overrideValue ?? widget.autoValue).toStringAsFixed(0));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text.trim());
    widget.onChanged(v);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.overrideValue ?? widget.autoValue;
    final overridden = widget.overrideValue != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(flex: 2, child: Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        Expanded(
          flex: 3,
          child: Text(overridden ? 'edited' : '(auto)',
              style: TextStyle(fontSize: 11, color: overridden ? _purple : Colors.grey.shade400)),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: _editing
              ? TextField(
                  controller: _ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixText: '₹',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _commit(),
                )
              : Text('₹${value.toStringAsFixed(0)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _purple)),
        ),
        SizedBox(
          width: 28,
          child: _editing
              ? IconButton(
                  icon: const Icon(Icons.check_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  color: _purple,
                  onPressed: _commit,
                )
              : IconButton(
                  icon: Icon(Icons.edit_outlined, size: 15, color: Colors.grey.shade500),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _editing = true),
                ),
        ),
        if (overridden)
          SizedBox(
            width: 28,
            child: IconButton(
              icon: Icon(Icons.restart_alt_rounded, size: 15, color: Colors.grey.shade500),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: 'Reset to auto',
              onPressed: () {
                widget.onChanged(null);
                setState(() {
                  _editing = false;
                  _ctrl.text = widget.autoValue.toStringAsFixed(0);
                });
              },
            ),
          ),
      ]),
    );
  }
}

class GeneratePayslipPage extends StatefulWidget {
  final AppUser user;
  final PayslipRequest? request;
  const GeneratePayslipPage({super.key, required this.user, this.request});

  @override
  State<GeneratePayslipPage> createState() => _GeneratePayslipPageState();
}

class _GeneratePayslipPageState extends State<GeneratePayslipPage> {
  static Color get _purple => AppTheme.primaryBlue;

  late String _monthYear;
  bool _loading = true;
  bool _saving = false;

  int _workingDays = 0;
  int _daysInMonth = 0; // fixed calendar days; basis for one-day salary
  int _lopDays = 0;
  int _graceLateDays = 0;
  int _severeLateDays = 0;
  bool _daysWorkedManual = false;
  late final TextEditingController _workingDaysCtrl;
  late final TextEditingController _lopDaysCtrl;
  late final TextEditingController _daysWorkedCtrl;
  late final TextEditingController _specialCtrl = TextEditingController();
  late final TextEditingController _cugCtrl = TextEditingController();

  double _basic = 0, _educational = 0, _lta = 0, _conveyance = 0;
  List<LeaveDetailRow> _leaveDetails = [];

  // CL/ML/EL days taken beyond the employee's balance for the month.
  double _clExcess = 0, _mlExcess = 0, _elExcess = 0;
  bool _deductElExcess = false;

  // Manual overrides for otherwise auto-computed fields (null = use auto value).
  double? _hraOverride;
  double? _otherAllowanceOverride;
  double? _epfOverride;
  double? _professionalTaxOverride;
  double? _tdsOverride;
  double? _lateDeductionOverride;
  double? _excessLeaveDeductionOverride;

  @override
  void initState() {
    super.initState();
    _monthYear = widget.request?.monthYear ?? _currentMonthYear();
    _workingDaysCtrl = TextEditingController();
    _lopDaysCtrl = TextEditingController();
    _daysWorkedCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _workingDaysCtrl.dispose();
    _lopDaysCtrl.dispose();
    _daysWorkedCtrl.dispose();
    _specialCtrl.dispose();
    _cugCtrl.dispose();
    super.dispose();
  }

  static String _currentMonthYear() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  (int, int) _parseMonthYear() {
    final parts = _monthYear.split('-');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (year, month) = _parseMonthYear();
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final results = await Future.wait([
      SupabaseService.fetchAttendanceForMonth(widget.user.employeeId, year, month),
      SupabaseService.fetchLeaveApplications().timeout(const Duration(seconds: 8)),
    ]);
    final attendance = results[0] as List<AttendanceRecord>;
    final leaves = results[1] as List<LeaveApplication>;

    // Late days: check-in after 9:30 AM, excluding days covered by an approved
    // permission. Split into the forgivable 09:31–09:41 grace window (a few
    // free passes a month) vs. genuinely severe (09:42+, always deducted) —
    // see PayslipCalc.lateDeduction.
    final schedule = OfficeTimingStore.scheduleForUser(widget.user);
    var graceLateDays = 0;
    var severeLateDays = 0;
    for (final r in attendance) {
      final date = parseSlashDate(r.date);
      if (date == null) continue;
      final status = checkInStatusFor(r.checkInTime, date, widget.user.name, leaves, schedule, lateWaived: r.lateWaived, onDuty: r.onDuty);
      if (status.status != CheckInStatus.late) continue;
      if (isSevereLate(r.checkInTime, schedule)) {
        severeLateDays++;
      } else if (isGraceLate(r.checkInTime, schedule)) {
        graceLateDays++;
      }
    }

    // LOP days: approved 'LOP or Others' leave for this employee in this month
    final myLeaves = leaves.where((a) => a.employeeName == widget.user.name).toList();
    final lopDays = myLeaves
        .where((a) =>
            a.bucket == 'LOP' &&
            a.managerStatus == LeaveApprovalStatus.approved &&
            a.from.year == year && a.from.month == month)
        .fold(0.0, (s, a) => s + a.effectiveDays)
        .round();

    // Leave details (CL/ML monthly allocation, EL accrued-to-date)
    double takenFor(String bucket) => myLeaves
        .where((a) =>
            a.bucket == bucket &&
            a.managerStatus == LeaveApprovalStatus.approved &&
            a.from.year == year && a.from.month == month)
        .fold(0.0, (s, a) => s + a.effectiveDays);

    final refStr = widget.user.elLastAvailedAt.isNotEmpty
        ? widget.user.elLastAvailedAt
        : widget.user.elEligibleAt;
    var elAccrued = 0.0;
    if (refStr.isNotEmpty) {
      final ref = DateTime.tryParse(refStr);
      if (ref != null) {
        final monthEnd = DateTime(year, month, daysInMonth);
        final months = (monthEnd.year - ref.year) * 12 + (monthEnd.month - ref.month);
        elAccrued = (months * widget.user.monthlyEl).clamp(0, 9999).toDouble();
      }
    }

    final clTaken = takenFor('CL');
    final mlTaken = takenFor('ML');
    final elTaken = takenFor('EL');
    final clExcess = (clTaken - widget.user.monthlyCl).clamp(0, double.infinity).toDouble();
    final mlExcess = (mlTaken - widget.user.monthlyMl).clamp(0, double.infinity).toDouble();
    final elExcess = (elTaken - elAccrued).clamp(0, double.infinity).toDouble();
    final daysWorkedDefault = (daysInMonth - lopDays).clamp(0, daysInMonth);

    if (!mounted) return;
    setState(() {
      _workingDays = daysInMonth;
      _daysInMonth = daysInMonth;
      _lopDays = lopDays;
      _graceLateDays = graceLateDays;
      _severeLateDays = severeLateDays;
      _workingDaysCtrl.text = '$daysInMonth';
      _lopDaysCtrl.text = '$lopDays';
      _daysWorkedCtrl.text = '$daysWorkedDefault';
      _daysWorkedManual = false;
      _clExcess = clExcess;
      _mlExcess = mlExcess;
      _elExcess = elExcess;
      _deductElExcess = false;
      _hraOverride = null;
      _otherAllowanceOverride = null;
      _epfOverride = null;
      _professionalTaxOverride = null;
      _tdsOverride = null;
      _lateDeductionOverride = null;
      _excessLeaveDeductionOverride = null;
      _leaveDetails = [
        LeaveDetailRow(type: 'Casual Leave', opening: widget.user.monthlyCl.toDouble(), taken: clTaken),
        LeaveDetailRow(type: 'Medical Leave', opening: widget.user.monthlyMl.toDouble(), taken: mlTaken),
        LeaveDetailRow(type: 'Earned Leave', opening: elAccrued, taken: elTaken),
      ];
      _loading = false;
    });
  }

  double get _grossPay => widget.user.grossPay;
  int get _daysWorked =>
      int.tryParse(_daysWorkedCtrl.text.trim()) ?? (_workingDays - _lopDays).clamp(0, _workingDays);
  double get _hra => _hraOverride ?? PayslipCalc.hra(_basic);
  double get _otherAllowance => _otherAllowanceOverride ?? PayslipCalc.otherAllowance(_grossPay);
  double get _epf => _epfOverride ?? PayslipCalc.epf;
  double get _professionalTax => _professionalTaxOverride ?? PayslipCalc.professionalTax;
  double get _tds => _tdsOverride ?? PayslipCalc.tds(_grossPay);
  double get _lateDeduction => _lateDeductionOverride ?? PayslipCalc.lateDeduction(
      grossPay: _grossPay, daysInMonth: _daysInMonth,
      graceLateDays: _graceLateDays, severeLateDays: _severeLateDays);
  double get _excessLeaveDays => _clExcess + _mlExcess + (_deductElExcess ? _elExcess : 0);
  double get _excessLeaveDeduction => _excessLeaveDeductionOverride ?? PayslipCalc.excessLeaveDeduction(
      grossPay: _grossPay, daysInMonth: _daysInMonth, excessDays: _excessLeaveDays);
  double get _special => double.tryParse(_specialCtrl.text.trim()) ?? 0;
  double get _cug => double.tryParse(_cugCtrl.text.trim()) ?? 0;

  double get _actualGrossPay =>
      _basic + _hra + _educational + _lta + _otherAllowance + _conveyance + _special;
  double get _totalDeductions =>
      _epf + _professionalTax + _tds + _lateDeduction + _excessLeaveDeduction + _cug;
  double get _netPay => _actualGrossPay - _totalDeductions;

  void _syncDaysWorked() {
    final workingDays = int.tryParse(_workingDaysCtrl.text.trim()) ?? _workingDays;
    final lopDays = int.tryParse(_lopDaysCtrl.text.trim()) ?? _lopDays;
    _daysWorkedCtrl.text = '${(workingDays - lopDays).clamp(0, workingDays)}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final workingDays = int.tryParse(_workingDaysCtrl.text.trim()) ?? _workingDays;
    final lopDays = int.tryParse(_lopDaysCtrl.text.trim()) ?? _lopDays;
    final daysWorked = _daysWorked;
    final payslip = Payslip(
      id: '${widget.user.employeeId}_$_monthYear',
      employeeId: widget.user.employeeId,
      monthYear: _monthYear,
      empName: widget.user.name,
      department: widget.user.designation, // no separate department field on AppUser
      designation: widget.user.designation,
      dateOfJoining: widget.user.dateOfJoining,
      workingDays: workingDays,
      daysWorked: daysWorked,
      lopDays: lopDays,
      grossPay: _grossPay,
      basic: _basic,
      hra: _hra,
      educationalAllowance: _educational,
      lta: _lta,
      otherAllowance: _otherAllowance,
      conveyanceAllowance: _conveyance,
      specialAllowance: _special,
      epf: _epf,
      professionalTax: _professionalTax,
      tds: _tds,
      lateDeductions: _lateDeduction,
      excessLeaveDeduction: _excessLeaveDeduction,
      cug: _cug,
      leaveDetails: _leaveDetails,
      generatedAt: DateTime.now(),
      generatedBy: UserSession.name,
    );
    await SupabaseService.savePayslip(payslip);
    if (widget.user.email.isNotEmpty) {
      NotificationService.payslipReady(
        employeeEmail: widget.user.email,
        monthYear: _monthYear,
        employeeRoutePrefix: NotificationService.routePrefixForRole(AppUser.userRoleFor(widget.user.role)),
      );
    }
    if (widget.request != null) {
      await SupabaseService.decidePayslipRequest(
          widget.request!.id, PayslipRequestStatus.approved, UserSession.name);
    }
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payslip generated for ${widget.user.name}'),
          backgroundColor: _purple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Widget _readOnlyAmount(String label, double value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(
            flex: 3,
            child: Text('(auto)', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text('₹${value.toStringAsFixed(0)}',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _purple)),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final locked = widget.request != null;
    return Scaffold(
      backgroundColor: null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const NavBackButton(),
                  const SizedBox(width: 8),
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: _purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.receipt_long_rounded, color: _purple, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Generate Payslip',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium),
                      Text('${widget.user.name} · ${_payslipMonthLabel(_monthYear)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    ]),
                  ),
                ]),
                const SizedBox(height: 20),

                if (!locked) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<String>(
                      value: _monthYear,
                      decoration: InputDecoration(
                        labelText: 'Month',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true, fillColor: Colors.white,
                      ),
                      items: List.generate(12, (i) {
                        final now = DateTime.now();
                        final d = DateTime(now.year, now.month - i, 1);
                        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
                        return DropdownMenuItem(value: key, child: Text(_payslipMonthLabel(key)));
                      }),
                      onChanged: (v) {
                        if (v != null) setState(() { _monthYear = v; });
                        _load();
                      },
                    ),
                  ),
                ],

                // ── Profile (read-only) ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _purple.withValues(alpha: 0.15)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Emp Code: ${widget.user.employeeId}', style: const TextStyle(fontSize: 12)),
                    Text('Designation: ${widget.user.designation}', style: const TextStyle(fontSize: 12)),
                    Text('Date of Joining: ${widget.user.dateOfJoining}', style: const TextStyle(fontSize: 12)),
                    Text('Gross Pay: ₹${_grossPay.toStringAsFixed(0)}/month',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 16),

                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _workingDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: 'Working Days',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                      onChanged: (_) => setState(() {
                        if (!_daysWorkedManual) _syncDaysWorked();
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _lopDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: 'LOP Days',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                      onChanged: (_) => setState(() {
                        if (!_daysWorkedManual) _syncDaysWorked();
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _daysWorkedCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: 'Days Worked',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          suffixIcon: _daysWorkedManual
                              ? IconButton(
                                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                                  tooltip: 'Reset to auto',
                                  onPressed: () => setState(() {
                                    _daysWorkedManual = false;
                                    _syncDaysWorked();
                                  }),
                                )
                              : null),
                      onChanged: (_) => setState(() => _daysWorkedManual = true),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                Text('Earnings', style: TextStyle(fontWeight: FontWeight.w700, color: _purple)),
                const SizedBox(height: 8),
                _OptionField(
                  label: 'Basic',
                  options: PayslipCalc.basicOptions,
                  defaultIndex: PayslipCalc.defaultBasicIndex,
                  grossPay: _grossPay,
                  basic: _basic,
                  onChanged: (v) => setState(() => _basic = v),
                ),
                _EditableAmount(
                  label: 'House Rent Allowance (50% of Basic)',
                  autoValue: PayslipCalc.hra(_basic),
                  overrideValue: _hraOverride,
                  onChanged: (v) => setState(() => _hraOverride = v),
                ),
                _OptionField(
                  label: 'Educational Allowance',
                  options: PayslipCalc.educationalOptions,
                  defaultIndex: PayslipCalc.defaultEducationalIndex,
                  grossPay: _grossPay,
                  basic: _basic,
                  onChanged: (v) => setState(() => _educational = v),
                ),
                _OptionField(
                  label: 'LTA',
                  options: PayslipCalc.ltaOptions,
                  defaultIndex: PayslipCalc.defaultLtaIndex,
                  grossPay: _grossPay,
                  basic: _basic,
                  onChanged: (v) => setState(() => _lta = v),
                ),
                _EditableAmount(
                  label: 'Other Allowance (2% of Gross)',
                  autoValue: PayslipCalc.otherAllowance(_grossPay),
                  overrideValue: _otherAllowanceOverride,
                  onChanged: (v) => setState(() => _otherAllowanceOverride = v),
                ),
                _OptionField(
                  label: 'Conveyance Allowance',
                  options: PayslipCalc.conveyanceOptions,
                  defaultIndex: PayslipCalc.defaultConveyanceIndex,
                  grossPay: _grossPay,
                  basic: _basic,
                  onChanged: (v) => setState(() => _conveyance = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _specialCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                        labelText: 'Special Allowance (optional)',
                        prefixText: '₹',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const Divider(),
                _readOnlyAmount('Actual Gross Pay', _actualGrossPay),
                const SizedBox(height: 16),

                Text('Deductions', style: TextStyle(fontWeight: FontWeight.w700, color: _purple)),
                const SizedBox(height: 8),
                _EditableAmount(
                  label: 'EPF',
                  autoValue: PayslipCalc.epf,
                  overrideValue: _epfOverride,
                  onChanged: (v) => setState(() => _epfOverride = v),
                ),
                _EditableAmount(
                  label: 'Professional Tax',
                  autoValue: PayslipCalc.professionalTax,
                  overrideValue: _professionalTaxOverride,
                  onChanged: (v) => setState(() => _professionalTaxOverride = v),
                ),
                _EditableAmount(
                  label: 'TDS${PayslipCalc.tdsApplicable(_grossPay) ? '' : ' (not applicable)'}',
                  autoValue: PayslipCalc.tds(_grossPay),
                  overrideValue: _tdsOverride,
                  onChanged: (v) => setState(() => _tdsOverride = v),
                ),
                _EditableAmount(
                  label: 'Late Deductions ($_graceLateDays grace-window late'
                      '${_graceLateDays == 1 ? '' : 's'} (${PayslipCalc.lateGraceExcuses} excused), '
                      '$_severeLateDays after 09:41)',
                  autoValue: PayslipCalc.lateDeduction(
                      grossPay: _grossPay, daysInMonth: _daysInMonth,
                      graceLateDays: _graceLateDays, severeLateDays: _severeLateDays),
                  overrideValue: _lateDeductionOverride,
                  onChanged: (v) => setState(() => _lateDeductionOverride = v),
                ),
                if (_clExcess > 0 || _mlExcess > 0 || _elExcess > 0) ...[
                  _EditableAmount(
                    label:
                        'Excess Leave Deduction (CL ${_clExcess.toStringAsFixed(0)}, ML ${_mlExcess.toStringAsFixed(0)}'
                        '${_deductElExcess ? ', EL ${_elExcess.toStringAsFixed(0)}' : ''})',
                    autoValue: PayslipCalc.excessLeaveDeduction(
                        grossPay: _grossPay, daysInMonth: _daysInMonth, excessDays: _excessLeaveDays),
                    overrideValue: _excessLeaveDeductionOverride,
                    onChanged: (v) => setState(() => _excessLeaveDeductionOverride = v),
                  ),
                  if (_elExcess > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: CheckboxListTile(
                        value: _deductElExcess,
                        onChanged: (v) => setState(() {
                          _deductElExcess = v ?? false;
                          _excessLeaveDeductionOverride = null;
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                            'Also deduct ${_elExcess.toStringAsFixed(0)} excess EL day${_elExcess == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _cugCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                        labelText: 'CUG (optional)',
                        prefixText: '₹',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ),
                const Divider(),
                _readOnlyAmount('Total Deductions', _totalDeductions),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Expanded(
                        child: Text('Net Pay', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    Text('₹${_netPay.toStringAsFixed(0)}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _purple)),
                  ]),
                ),
                const SizedBox(height: 24),

                Text('Leave Details', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                ..._leaveDetails.map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(child: Text(r.type, style: const TextStyle(fontSize: 12))),
                        Text('Open ${r.opening}  ·  Taken ${r.taken}  ·  Close ${r.closing}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      ]),
                    )),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(locked ? 'Approve & Generate' : 'Generate Payslip'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ]),
            ),
    );
  }
}
