import 'package:flutter/material.dart';
import '../services/payslip_pdf_service.dart';
import '../utils/el_accrual.dart';
import '../models/app_user.dart';
import '../models/leave_store.dart';
import '../models/payslip_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

class MyPayslipsPage extends StatefulWidget {
  const MyPayslipsPage({super.key});

  @override
  State<MyPayslipsPage> createState() => _MyPayslipsPageState();
}

class _MyPayslipsPageState extends State<MyPayslipsPage> {
  static Color get _color => AppTheme.primaryBlue;

  bool _loading = false;
  bool _elAvailLoading = false;
  bool _requesting = false;
  AppUser? _appUser;
  List<PayslipRequest> _requests = [];
  List<Payslip> _payslips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SupabaseService.fetchLeaveApplications().timeout(const Duration(seconds: 8)),
        UserStore.load(),
      ]);
      final leaves = results[0] as List;
      final users  = results[1] as List<AppUser>;

      if (leaves.isNotEmpty) {
        LeaveStore.applications
          ..clear()
          ..addAll(leaves.cast());
        LeaveStore.syncCounter();
      }

      final match = users.where((u) => u.name == UserSession.name).toList();
      final user = match.isNotEmpty ? match.first : null;

      List<PayslipRequest> requests = [];
      List<Payslip> payslips = [];
      if (user != null && user.employeeId.isNotEmpty) {
        final more = await Future.wait([
          SupabaseService.fetchPayslipRequestsFor(user.employeeId),
          SupabaseService.fetchPayslips(user.employeeId),
        ]);
        requests = more[0] as List<PayslipRequest>;
        payslips = more[1] as List<Payslip>;
      }

      if (mounted) setState(() {
        _appUser  = user;
        _requests = requests;
        _payslips = payslips;
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestPayslip(String monthYear) async {
    final user = _appUser;
    if (user == null || user.employeeId.isEmpty) return;
    setState(() => _requesting = true);
    await SupabaseService.requestPayslip(PayslipRequest(
      id: '${user.employeeId}_$monthYear',
      employeeId: user.employeeId,
      employeeName: user.name,
      monthYear: monthYear,
      requestedAt: DateTime.now(),
    ));
    NotificationService.payslipRequested(employeeName: user.name, monthYear: monthYear);
    await _load();
    if (mounted) setState(() => _requesting = false);
  }

  Future<void> _requestElAvail() async {
    if (_appUser == null) return;
    setState(() => _elAvailLoading = true);
    await SupabaseService.requestElAvail(_appUser!.email);
    NotificationService.elEncashmentRequested(employeeName: _appUser!.name);
    await _load();
  }

  // EL accrued = whole months since (elLastAvailedAt ?? elEligibleAt) × 1/month
  int _elAccrued(AppUser user) => elAccruedFor(user);

  // EL used = approved EL leaves since the same reference date
  double _elUsed(AppUser user) {
    final refStr = user.elLastAvailedAt.isNotEmpty
        ? user.elLastAvailedAt
        : user.elEligibleAt;
    final cutoff = refStr.isNotEmpty ? DateTime.tryParse(refStr) : null;
    return LeaveStore.applications
        .where((a) =>
            a.employeeName == user.name &&
            a.leaveType == 'Earned Leave' &&
            a.managerStatus == LeaveApprovalStatus.approved &&
            (cutoff == null || a.from.isAfter(cutoff)))
        .fold(0.0, (s, a) => s + a.effectiveDays);
  }

  @override
  Widget build(BuildContext context) {
    final user = _appUser;

    return Scaffold(
      backgroundColor: null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(children: [
                    const NavBackButton(),
                    const SizedBox(width: 8),
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: _color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.account_balance_wallet_rounded,
                          color: _color, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text('My Payslips',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: Icon(Icons.refresh_rounded, color: _color),
                      onPressed: _load,
                    ),
                  ]),
                  const SizedBox(height: 24),

                  if (user == null)
                    const Text('Employee record not found.',
                        style: TextStyle(color: Color(0xFF6B7280)))
                  else ...[
                    if (user.isElEligible) ...[
                      // ── EL section ────────────────────────────────────────
                      _ElBalanceCard(
                        accrued: _elAccrued(user),
                        used:    _elUsed(user),
                        user:    user,
                        loading: _elAvailLoading,
                        onRequest: _requestElAvail,
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Payslip request + history ────────────────────────────
                    _PayslipSection(
                      requests: _requests,
                      payslips: _payslips,
                      requesting: _requesting,
                      onRequest: _requestPayslip,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

// ── EL Balance card ────────────────────────────────────────────────────────────
class _ElBalanceCard extends StatelessWidget {
  final int    accrued;
  final double used;
  final AppUser user;
  final bool   loading;
  final VoidCallback onRequest;
  const _ElBalanceCard({
    required this.accrued,
    required this.used,
    required this.user,
    required this.loading,
    required this.onRequest,
  });

  static Color get _purple => AppTheme.primaryBlue;

  static String _fmt(double d) =>
      d % 1 == 0 ? '${d.toInt()}' : d.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final available   = (accrued - used).clamp(0.0, accrued.toDouble());
    final hasPending  = user.elAvailRequestedAt.isNotEmpty;
    final lastAvailed = user.elLastAvailedAt.isNotEmpty
        ? DateTime.tryParse(user.elLastAvailedAt)
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _purple.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Title row
        Row(children: [
          Icon(Icons.card_giftcard_rounded, color: _purple, size: 20),
          const SizedBox(width: 8),
          Text('Earned Leave (EL)',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _purple)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _purple.withValues(alpha: 0.2)),
            ),
            child: Text('EL Eligible',
                style: TextStyle(
                    fontSize: 10, color: _purple, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 20),

        // Big balance display
        Row(children: [
          // Available
          Expanded(
            child: Column(children: [
              Text(_fmt(available),
                  style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade700)),
              const SizedBox(height: 2),
              Text('day${available == 1 ? '' : 's'} available',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
          ),
          Container(width: 1, height: 48, color: _purple.withValues(alpha: 0.15)),
          // Accrued
          Expanded(
            child: Column(children: [
              Text('$accrued',
                  style: const TextStyle(
                      fontSize: 36, fontWeight: FontWeight.w800,
                      color: Color(0xFF6B7280))),
              const SizedBox(height: 2),
              const Text('days accrued',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
          ),
          Container(width: 1, height: 48, color: _purple.withValues(alpha: 0.15)),
          // Used
          Expanded(
            child: Column(children: [
              Text(_fmt(used),
                  style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange.shade700)),
              const SizedBox(height: 2),
              const Text('days used',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
          ),
        ]),

        if (lastAvailed != null) ...[
          const SizedBox(height: 12),
          Text('Last encashed: ${_fmtDate(lastAvailed)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
        ],

        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),

        // Avail EL section
        if (hasPending)
          Row(children: [
            Icon(Icons.hourglass_empty_rounded,
                size: 16, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Encash EL request submitted. Awaiting HR confirmation.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Text('Pending',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600)),
            ),
          ])
        else
          Row(children: [
            Expanded(
              child: Text(
                available > 0
                    ? 'You have ${_fmt(available)} EL day${available == 1 ? '' : 's'} to encash. Once confirmed by HR, your balance will reset.'
                    : 'No EL days available to encash yet.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ),
            const SizedBox(width: 12),
            if (available > 0)
              ElevatedButton.icon(
                onPressed: loading ? null : onRequest,
                icon: loading
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.redeem_rounded, size: 16),
                label: const Text('Encash EL'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ]),
      ]),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ── Payslip request + history section ───────────────────────────────────────
const _monthNames = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];

/// Last 12 months as (key='YYYY-MM', label='Mon YYYY'), newest first.
List<(String, String)> _recentMonths() {
  final now = DateTime.now();
  return List.generate(12, (i) {
    final d = DateTime(now.year, now.month - i, 1);
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    return (key, '${_monthNames[d.month - 1]} ${d.year}');
  });
}

String _monthLabel(String monthYear) {
  final parts = monthYear.split('-');
  if (parts.length != 2) return monthYear;
  final m = int.tryParse(parts[1]);
  if (m == null || m < 1 || m > 12) return monthYear;
  return '${_monthNames[m - 1]} ${parts[0]}';
}

class _PayslipSection extends StatefulWidget {
  final List<PayslipRequest> requests;
  final List<Payslip> payslips;
  final bool requesting;
  final Future<void> Function(String monthYear) onRequest;
  const _PayslipSection({
    required this.requests,
    required this.payslips,
    required this.requesting,
    required this.onRequest,
  });

  @override
  State<_PayslipSection> createState() => _PayslipSectionState();
}

class _PayslipSectionState extends State<_PayslipSection> {
  static Color get _purple => AppTheme.primaryBlue;
  late String _selectedMonth = _recentMonths().first.$1;

  PayslipRequest? get _existingRequest {
    for (final r in widget.requests) {
      if (r.monthYear == _selectedMonth) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final months = _recentMonths();
    final existing = _existingRequest;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _purple.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _purple.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.receipt_long_rounded, color: _purple, size: 20),
            const SizedBox(width: 8),
            Text('Request Payslip',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _purple)),
          ]),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedMonth,
                decoration: InputDecoration(
                  labelText: 'Month',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: months
                    .map((m) => DropdownMenuItem(value: m.$1, child: Text(m.$2)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedMonth = v);
                },
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: (widget.requesting || existing != null)
                  ? null
                  : () => widget.onRequest(_selectedMonth),
              icon: widget.requesting
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 16),
              label: const Text('Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
          if (existing != null) ...[
            const SizedBox(height: 12),
            _RequestStatusRow(request: existing),
          ],
        ]),
      ),
      const SizedBox(height: 20),
      Text('Payslip History',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
      const SizedBox(height: 10),
      if (widget.payslips.isEmpty)
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
            Text('No payslips generated yet.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ]),
        )
      else
        ...widget.payslips.map((p) => _PayslipListTile(payslip: p)),
    ]);
  }
}

class _RequestStatusRow extends StatelessWidget {
  final PayslipRequest request;
  const _RequestStatusRow({required this.request});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (request.status) {
      PayslipRequestStatus.pending => (
          Icons.hourglass_empty_rounded, Colors.orange.shade700, 'Pending HR approval'),
      PayslipRequestStatus.approved => (
          Icons.check_circle_rounded, Colors.green.shade700, 'Approved — see history below'),
      PayslipRequestStatus.rejected => (
          Icons.cancel_rounded, Colors.red.shade700, 'Rejected'),
    };
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text('${_monthLabel(request.monthYear)}: $label',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

class _PayslipListTile extends StatelessWidget {
  final Payslip payslip;
  const _PayslipListTile({required this.payslip});

  static Color get _purple => AppTheme.primaryBlue;

  static String _fmtRs(double v) => '₹${v.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: _purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.description_rounded, color: _purple, size: 20),
        ),
        title: Text(_monthLabel(payslip.monthYear),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        subtitle: Text('Net Pay: ${_fmtRs(payslip.netPay)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // The PDF generator and its download() existed all along; no screen
          // ever offered it, so a payslip could be viewed and never saved.
          IconButton(
            icon: Icon(Icons.download_rounded, size: 20, color: _purple),
            tooltip: 'Download PDF',
            onPressed: () => _downloadPayslip(context, payslip),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF6B7280)),
        ]),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PayslipDetailPage(payslip: payslip))),
      ),
    );
  }
}

/// Generates and downloads the payslip PDF, reporting failure rather than
/// doing nothing — a button that silently fails reads as broken.
Future<void> _downloadPayslip(BuildContext context, Payslip p) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await PayslipPdfService.download(p);
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('Could not download the payslip: $e'),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

// ── Full payslip detail view ────────────────────────────────────────────────
class PayslipDetailPage extends StatelessWidget {
  final Payslip payslip;
  const PayslipDetailPage({super.key, required this.payslip});

  static Color get _purple => AppTheme.primaryBlue;

  static String _fmtRs(double v) =>
      '₹${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
              flex: 2,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
          Expanded(
              flex: 3,
              child: Text(value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _amountRow(String label, double value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
          Text(_fmtRs(value),
              style: TextStyle(
                  fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = payslip;
    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(
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
              child: Icon(Icons.description_rounded, color: _purple, size: 26),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Text('Pay Slip — ${_monthLabel(p.monthYear)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(width: 8),
            // Also offered here: someone reading a payslip is the most likely
            // person to want to keep a copy of it.
            ElevatedButton.icon(
              onPressed: () => _downloadPayslip(context, p),
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _purple.withValues(alpha: 0.15)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Profile header ──────────────────────────────────────────
              _infoRow('Emp Code', p.employeeId),
              _infoRow('Employee Name', p.empName),
              _infoRow('Department', p.department),
              _infoRow('Designation', p.designation),
              if (p.band.isNotEmpty) _infoRow('Band', p.band),
              _infoRow('Date of Joining', p.dateOfJoining),
              _infoRow('No. of Working Days', '${p.workingDays}'),
              _infoRow('No of Days Worked', Payslip.fmtDays(p.daysWorked)),
              _infoRow('No of LOP Days', Payslip.fmtDays(p.lopDays)),
              _infoRow('Gross Pay (Rs)', _fmtRs(p.grossPay)),
              const Divider(height: 28),

              // ── Earnings / Deductions ────────────────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Earnings',
                        style: TextStyle(fontWeight: FontWeight.w700, color: _purple)),
                    const SizedBox(height: 6),
                    _amountRow('Basic', p.basic),
                    if (p.da > 0) _amountRow('Dearness Allowance', p.da),
                    _amountRow('House Rent Allowance', p.hra),
                    _amountRow('Educational Allowance', p.educationalAllowance),
                    _amountRow('LTA', p.lta),
                    _amountRow('Other Allowance', p.otherAllowance),
                    _amountRow('Conveyance Allowance', p.conveyanceAllowance),
                    if (p.specialAllowance > 0)
                      _amountRow('Special Allowance', p.specialAllowance),
                    const Divider(),
                    _amountRow('Actual Gross Pay (Rs)', p.actualGrossPay, bold: true),
                  ]),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Deductions',
                        style: TextStyle(fontWeight: FontWeight.w700, color: _purple)),
                    const SizedBox(height: 6),
                    _amountRow('EPF', p.epf),
                    if (p.esi > 0) _amountRow('ESI', p.esi),
                    _amountRow('Professional Tax', p.professionalTax),
                    _amountRow('TDS', p.tds),
                    _amountRow('Late Deductions', p.lateDeductions),
                    if (p.excessLeaveDeduction > 0)
                      _amountRow('Excess Leave Deduction', p.excessLeaveDeduction),
                    if (p.cug > 0) _amountRow('CUG', p.cug),
                    const Divider(),
                    _amountRow('Total Deductions', p.totalDeductions, bold: true),
                  ]),
                ),
              ]),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _amountRow('Net Pay (Rs)', p.netPay, bold: true),
              ),

              if (p.leaveDetails.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Leave Details',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _purple)),
                const SizedBox(height: 8),
                Table(
                  border: TableBorder.all(color: const Color(0xFFE5E7EB)),
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(1),
                  },
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: Color(0xFFF8FAFC)),
                      children: [
                        Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Leave Type',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                        Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Opening',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                        Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Taken',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                        Padding(
                            padding: EdgeInsets.all(8),
                            child: Text('Closing',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                      ],
                    ),
                    for (final row in p.leaveDetails)
                      TableRow(children: [
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(row.type, style: const TextStyle(fontSize: 12))),
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('${row.opening}', style: const TextStyle(fontSize: 12))),
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('${row.taken}', style: const TextStyle(fontSize: 12))),
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('${row.closing}', style: const TextStyle(fontSize: 12))),
                      ]),
                  ],
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
