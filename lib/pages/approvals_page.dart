import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/app_user.dart';
import '../models/kra_store.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../utils/month_picker.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

/// Central inbox for Management: every approval type in the system, piled
/// up under its own heading. Each section is actionable inline where the
/// underlying decision is a simple approve/deny; a "View all" link jumps to
/// the dedicated page for deeper history/filtering.
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  List<AppUser> _users = [];
  List<Map<String, dynamic>> _leaveVersions = [];
  List<Map<String, dynamic>> _interviewVersions = [];
  List<Map<String, dynamic>> _onboardingVersions = [];
  List<Map<String, dynamic>> _policyVersions = [];
  List<Map<String, dynamic>> _maintenanceVersions = [];
  List<KraDocument> _kraDocs = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // Employee-raised On Duty requests awaiting a decision. RLS already
  // narrows this to the caller's own reports, or everything for HR and
  // Management, so no extra filtering is needed here.
  List<Map<String, dynamic>> _onDutyRequests = const [];

  Future<void> _decideOnDuty(Map<String, dynamic> r, bool approve) async {
    await SupabaseService.decideOnDutyRequest(
        r['id'].toString(), approve, decidedBy: UserSession.email);
    await _load();
  }

  _CategoryInfo get _onDutyCategory => _CategoryInfo(
        icon: Icons.work_history_rounded,
        color: Colors.orange.shade700,
        label: 'On Duty Requests',
        pending: _onDutyRequests.length,
        approved: 0,
        rejected: 0,
        total: _onDutyRequests.length,
        onViewAll: () => _showPendingSheet(
          label: 'On Duty Requests',
          color: Colors.orange.shade700,
          buildCards: (refresh) => _onDutyRequests
              .map((r) => _ApprovalCard(
                    title: (r['employee_name'] ?? '').toString(),
                    subtitle: (r['date_iso'] ?? '').toString(),
                    details: [(r['reason'] ?? '').toString()],
                    meta: _fmtIso((r['requested_at'] ?? '').toString()),
                    onApprove: () async { await _decideOnDuty(r, true); refresh(); },
                    onDeny: () async { await _decideOnDuty(r, false); refresh(); },
                  ))
              .toList(),
        ),
      );

  // Manager-vouched attendance for days a device could not verify. Two
  // separate queues on purpose: the reporting manager confirms presence
  // because they are the one who knows, and HR approves afterwards because a
  // vouched day has no GPS and no selfie behind it — one signature should not
  // turn that into pay.
  List<Map<String, dynamic>> _attendanceConfirmations = const [];

  List<Map<String, dynamic>> get _pendingManagerVouch =>
      _attendanceConfirmations.where((r) => (r['status'] ?? '') == 'pending').toList();

  // Reaches HR only once the manager has confirmed.
  //
  // Excludes anything the current user confirmed themselves. Where an
  // employee's reporting manager IS the HR role holder — which is the case in
  // the HR department — one person would otherwise see both queues and could
  // confirm and then approve their own confirmation, collapsing the two
  // signatures into one. Those fall to Management instead, and the database
  // rejects a same-person approval regardless of which screen it comes from.
  List<Map<String, dynamic>> get _pendingHrVouch => _attendanceConfirmations
      .where((r) => (r['status'] ?? '') == 'confirmed'
                 && (r['hr_status'] ?? '') == 'pending'
                 && (r['decided_by'] ?? '').toString().toLowerCase()
                    != UserSession.email.toLowerCase())
      .toList();

  /// Confirmed but still awaiting a second signature.
  ///
  /// Where the reporting manager IS the HR role holder this now auto-approves
  /// — no action means approved, rather than the employee losing the day to
  /// an org chart they did not choose. So anything still sitting here has a
  /// real separate HR approver who has simply not acted yet, and Management
  /// can step in if it stalls.
  List<Map<String, dynamic>> get _vouchNeedingManagement => _attendanceConfirmations
      .where((r) => (r['status'] ?? '') == 'confirmed'
                 && (r['hr_status'] ?? '') == 'pending')
      .toList();

  _CategoryInfo get _vouchMgmtApprovalCategory => _CategoryInfo(
        icon: Icons.gavel_rounded,
        color: Colors.indigo.shade700,
        label: 'Attendance — Second Approval',
        pending: _vouchNeedingManagement.length,
        approved: 0, rejected: 0,
        total: _vouchNeedingManagement.length,
        onViewAll: () => _showPendingSheet(
          label: 'Attendance — Second Approval',
          color: Colors.indigo.shade700,
          buildCards: (refresh) => _vouchNeedingManagement
              .map((r) => _vouchCard(r, hrStage: true,
                  onApprove: () async { await _hrDecideVouch(r, true); refresh(); },
                  onDeny: () async { await _hrDecideVouch(r, false); refresh(); }))
              .toList(),
        ),
      );

  Future<void> _decideVouch(Map<String, dynamic> r, bool ok) async {
    await SupabaseService.decideAttendanceConfirmation(r['id'].toString(), ok);
    // HR is told only now, when it is actually their turn. Notifying them at
    // the moment the employee raised it filled their inbox with items nobody
    // could act on until the manager had confirmed.
    NotificationService.attendanceConfirmationManagerDecided(
      employeeName: (r['employee_name'] ?? '').toString(),
      dateLabel: (r['date_iso'] ?? '').toString(),
      managerName: UserSession.name,
      confirmed: ok,
    );
    await _load();
  }

  Future<void> _hrDecideVouch(Map<String, dynamic> r, bool ok) async {
    await SupabaseService.hrDecideAttendanceConfirmation(r['id'].toString(), ok);
    if (ok) {
      // Both signatures are in and the day has become attendance, so
      // Management is told now rather than earlier.
      final email = _users
          .where((u) => u.name == (r['employee_name'] ?? '').toString())
          .map((u) => u.email)
          .firstOrNull ?? '';
      NotificationService.attendanceConfirmationHrApproved(
        employeeName: (r['employee_name'] ?? '').toString(),
        employeeEmail: email,
        dateLabel: (r['date_iso'] ?? '').toString(),
        hrName: UserSession.name,
      );
    }
    await _load();
  }

  Widget _vouchCard(Map<String, dynamic> r,
      {required VoidCallback onApprove, required VoidCallback onDeny, bool hrStage = false}) {
    return _ApprovalCard(
      title: (r['employee_name'] ?? '').toString(),
      subtitle: '${r['date_iso'] ?? ''} · claims ${r['claimed_time'] ?? ''}',
      details: [
        if ((r['employee_note'] ?? '').toString().isNotEmpty)
          'Employee: ${r['employee_note']}',
        // The actual failure, not the employee's account of it.
        if ((r['failure_reason'] ?? '').toString().isNotEmpty)
          'App reported: ${r['failure_reason']}',
        if (hrStage && (r['decided_by_name'] ?? '').toString().isNotEmpty)
          'Confirmed by ${r['decided_by_name']}',
        'No GPS or selfie for this day — it will be recorded as manager-confirmed.',
      ],
      meta: _fmtIso((r['requested_at'] ?? '').toString()),
      onApprove: onApprove,
      onDeny: onDeny,
    );
  }

  _CategoryInfo get _vouchCategory => _CategoryInfo(
        icon: Icons.how_to_reg_rounded,
        color: Colors.indigo.shade600,
        label: 'Attendance Confirmations',
        pending: _pendingManagerVouch.length,
        approved: 0, rejected: 0,
        total: _pendingManagerVouch.length,
        onViewAll: () => _showPendingSheet(
          label: 'Attendance Confirmations',
          color: Colors.indigo.shade600,
          buildCards: (refresh) => _pendingManagerVouch
              .map((r) => _vouchCard(r,
                  onApprove: () async { await _decideVouch(r, true); refresh(); },
                  onDeny: () async { await _decideVouch(r, false); refresh(); }))
              .toList(),
        ),
      );

  // Fully approved confirmations, shown to Management for oversight. They
  // are not a required signature — the day is already attendance — so these
  // are presented as decided, with the option to overturn if something
  // breached policy. Already-overturned entries drop out.
  List<Map<String, dynamic>> get _vouchedForOversight => _attendanceConfirmations
      .where((r) => (r['status'] ?? '') == 'confirmed'
                 && (r['hr_status'] ?? '') == 'approved'
                 && (r['mgmt_status'] ?? 'none') != 'overturned')
      .toList();

  Future<void> _overturnVouch(Map<String, dynamic> r) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Overturn this confirmation?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${r['employee_name']} — ${r['date_iso']}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'The attendance recorded from this confirmation will be removed. '
            'Use this only where the confirmation breached policy.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'Reason', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white),
            child: const Text('Overturn'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SupabaseService.overturnAttendanceConfirmation(
        r['id'].toString(),
        ctrl.text.trim().isEmpty ? 'Overturned by Management' : ctrl.text.trim());
    await _load();
  }

  _CategoryInfo get _vouchOversightCategory => _CategoryInfo(
        icon: Icons.visibility_rounded,
        color: Colors.blueGrey.shade600,
        label: 'Vouched Attendance (for information)',
        // Zero pending: nothing is waiting on Management. Counting these as
        // pending would imply an action is required and inflate the badge.
        pending: 0,
        approved: _vouchedForOversight.length,
        rejected: 0,
        total: _vouchedForOversight.length,
        onViewAll: () => _showPendingSheet(
          label: 'Vouched Attendance',
          color: Colors.blueGrey.shade600,
          buildCards: (refresh) => _vouchedForOversight
              .map((r) => _ApprovalCard(
                    title: (r['employee_name'] ?? '').toString(),
                    subtitle: '${r['date_iso'] ?? ''} · ${r['claimed_time'] ?? ''}',
                    details: [
                      if ((r['employee_note'] ?? '').toString().isNotEmpty)
                        'Employee: ${r['employee_note']}',
                      'Confirmed by ${r['decided_by_name'] ?? '—'}, '
                          'approved by ${r['hr_decided_by_name'] ?? '—'}',
                      'No GPS or selfie for this day.',
                    ],
                    meta: _fmtIso((r['hr_decided_at'] ?? '').toString()),
                    // Approve is absent on purpose: it is already approved.
                    denyLabel: 'Overturn',
                    onDeny: () async { await _overturnVouch(r); refresh(); },
                  ))
              .toList(),
        ),
      );

  _CategoryInfo get _vouchHrCategory => _CategoryInfo(
        icon: Icons.verified_user_rounded,
        color: Colors.indigo.shade400,
        label: 'Attendance — HR Approval',
        pending: _pendingHrVouch.length,
        approved: 0, rejected: 0,
        total: _pendingHrVouch.length,
        onViewAll: () => _showPendingSheet(
          label: 'Attendance — HR Approval',
          color: Colors.indigo.shade400,
          buildCards: (refresh) => _pendingHrVouch
              .map((r) => _vouchCard(r, hrStage: true,
                  onApprove: () async { await _hrDecideVouch(r, true); refresh(); },
                  onDeny: () async { await _hrDecideVouch(r, false); refresh(); }))
              .toList(),
        ),
      );

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SupabaseService.fetchLeaveApplications().timeout(const Duration(seconds: 8)),
        UserStore.load(),
        SupabaseService.fetchLeaveFormVersions(),
        SupabaseService.fetchFormVersions(),
        SupabaseService.fetchOnboardingFormVersions(),
        SupabaseService.fetchHRPolicyVersions(),
        SupabaseService.fetchMaintenanceFormVersions(),
        SupabaseService.fetchKraDocuments(),
        SupabaseService.fetchOnDutyRequests(status: 'pending'),
        SupabaseService.fetchAttendanceConfirmations(),
      ]);
      final leaves = results[0] as List<LeaveApplication>;
      if (leaves.isNotEmpty) {
        LeaveStore.applications
          ..clear()
          ..addAll(leaves);
        LeaveStore.syncCounter();
      }
      if (!mounted) return;
      setState(() {
        _users = results[1] as List<AppUser>;
        _leaveVersions = results[2] as List<Map<String, dynamic>>;
        _interviewVersions = results[3] as List<Map<String, dynamic>>;
        _onboardingVersions = results[4] as List<Map<String, dynamic>>;
        _policyVersions = results[5] as List<Map<String, dynamic>>;
        _maintenanceVersions = results[6] as List<Map<String, dynamic>>;
        _kraDocs = results[7] as List<KraDocument>;
        _onDutyRequests = results[8] as List<Map<String, dynamic>>;
        _attendanceConfirmations = results[9] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Pending slices ──────────────────────────────────────────────────────

  bool _isPermCompOff(LeaveApplication a) =>
      a.leaveType == 'Permission' || a.leaveType == 'Comp Off';

  List<LeaveApplication> get _pendingLeave => LeaveStore.applications
      .where((a) => !_isPermCompOff(a) && a.managerStatus == LeaveApprovalStatus.pending)
      .toList();
  List<LeaveApplication> get _pendingPermission => LeaveStore.applications
      .where((a) => a.leaveType == 'Permission' && a.managerStatus == LeaveApprovalStatus.pending)
      .toList();
  List<LeaveApplication> get _pendingCompOff => LeaveStore.applications
      .where((a) => a.leaveType == 'Comp Off' && a.managerStatus == LeaveApprovalStatus.pending)
      .toList();

  List<AppUser> get _pendingOnroll =>
      _users.where((u) => u.onrollAwaitingManagement).toList();
  List<AppUser> get _pendingGrossPay =>
      _users.where((u) => u.hasPendingGrossPayChange).toList();
  List<AppUser> get _pendingPermissionQuota =>
      _users.where((u) => u.hasPendingPermissionQuotaChange).toList();
  List<AppUser> get _pendingWorkLocation =>
      _users.where((u) => u.hasPendingWorkLocationChange).toList();
  List<AppUser> get _pendingBusinessUnit =>
      _users.where((u) => u.hasPendingBusinessUnitChange).toList();
  List<AppUser> get _pendingReportingManager =>
      _users.where((u) => u.hasPendingReportingManagerChange).toList();
  List<AppUser> get _pendingRmFlag =>
      _users.where((u) => u.hasPendingRmFlagChange).toList();

  List<Map<String, dynamic>> _pendingOf(List<Map<String, dynamic>> versions) =>
      versions.where((v) => (v['status'] as String?) == 'pending').toList();

  List<KraDocument> get _pendingKra => _kraDocs.where((d) => d.isPending).toList();

  // ── Past (decided) slices ───────────────────────────────────────────────

  List<LeaveApplication> _decidedSorted(Iterable<LeaveApplication> src) {
    final list = src.where((a) => a.managerStatus != LeaveApprovalStatus.pending).toList();
    list.sort((a, b) => (b.decidedAt ?? DateTime(0)).compareTo(a.decidedAt ?? DateTime(0)));
    return list;
  }

  List<LeaveApplication> get _historyLeave =>
      _decidedSorted(LeaveStore.applications.where((a) => !_isPermCompOff(a)));
  List<LeaveApplication> get _historyPermission =>
      _decidedSorted(LeaveStore.applications.where((a) => a.leaveType == 'Permission'));
  List<LeaveApplication> get _historyCompOff =>
      _decidedSorted(LeaveStore.applications.where((a) => a.leaveType == 'Comp Off'));

  int get _totalPending =>
      _pendingLeave.length +
      _pendingPermission.length +
      _pendingCompOff.length +
      _pendingOnroll.length +
      _pendingGrossPay.length +
      _pendingPermissionQuota.length +
      _pendingWorkLocation.length +
      _pendingBusinessUnit.length +
      _pendingReportingManager.length +
      _pendingRmFlag.length +
      _pendingOf(_leaveVersions).length +
      _pendingOf(_interviewVersions).length +
      _pendingOf(_onboardingVersions).length +
      _pendingOf(_policyVersions).length +
      _pendingOf(_maintenanceVersions).length +
      _pendingKra.length;

  // ── This-month approval-rate stats (banner) ─────────────────────────────
  // Only categories that retain a permanent, timestamped decision record can
  // feed this — gross pay / work location changes clear their pending flag
  // on decision without keeping a dated history entry, so they're excluded.

  DateTime _statsMonth = DateTime.now();

  Iterable<(bool approved, DateTime? when)> get _allDecisions sync* {
    for (final a in LeaveStore.applications.where((a) => a.managerStatus != LeaveApprovalStatus.pending)) {
      yield (a.managerStatus == LeaveApprovalStatus.approved, a.decidedAt);
    }
    for (final u in _users.where((u) => u.onrollManagementStatus != 'pending')) {
      yield (u.onrollManagementStatus == 'accepted', DateTime.tryParse(u.onrollManagementDecidedAt));
    }
    for (final versions in [_leaveVersions, _interviewVersions, _onboardingVersions, _policyVersions, _maintenanceVersions]) {
      for (final v in versions.where((v) => (v['status'] as String?) != 'pending')) {
        yield ((v['status'] as String?) == 'approved', DateTime.tryParse(v['created_at']?.toString() ?? ''));
      }
    }
    for (final d in _kraDocs.where((d) => !d.isPending)) {
      yield (d.isApproved, DateTime.tryParse(d.decidedAt));
    }
  }

  Iterable<(bool approved, DateTime? when)> get _decisionsThisMonth => _allDecisions.where(
      (d) => d.$2 != null && d.$2!.year == _statsMonth.year && d.$2!.month == _statsMonth.month);

  int get _approvedThisMonth => _decisionsThisMonth.where((d) => d.$1).length;
  int get _rejectedThisMonth => _decisionsThisMonth.where((d) => !d.$1).length;
  double get _approvalRateThisMonth {
    final total = _approvedThisMonth + _rejectedThisMonth;
    return total == 0 ? 100 : (_approvedThisMonth / total) * 100;
  }

  // ── Gross Pay / Work Location actions ────────────────────────────────────

  Future<void> _decideGrossPay(AppUser u, bool approve) async {
    setState(() {
      if (approve) u.grossPay = u.grossPayPending;
      u.grossPayPending = 0;
      u.grossPayRequestedAt = '';
    });
    await UserStore.upsertOne(u);
  }

  Future<void> _decidePermissionQuota(AppUser u, bool approve) async {
    setState(() {
      if (approve) u.permissionMinutesQuota = u.permissionMinutesQuotaPending;
      u.permissionMinutesQuotaPending = 0;
      u.permissionMinutesQuotaRequestedAt = '';
    });
    await UserStore.upsertOne(u);
  }

  Future<void> _decideWorkLocation(AppUser u, bool approve) async {
    setState(() {
      if (approve) u.workLocation = u.workLocationPending;
      u.workLocationPending = '';
      u.workLocationRequestedAt = '';
    });
    await UserStore.upsertOne(u);
  }

  Future<void> _decideBusinessUnit(AppUser u, bool approve) async {
    setState(() {
      if (approve) u.businessUnit = u.businessUnitPending;
      u.businessUnitPending = '';
      u.businessUnitRequestedAt = '';
    });
    await UserStore.upsertOne(u);
  }

  Future<void> _decideReportingManager(AppUser u, bool approve) async {
    setState(() {
      if (approve) u.reportingManager = u.reportingManagerPending;
      u.reportingManagerPending = '';
      u.reportingManagerRequestedAt = '';
    });
    await UserStore.upsertOne(u);
  }

  Future<void> _decideRmFlag(AppUser u, bool approve) async {
    setState(() {
      if (approve) u.isReportingManager = u.isReportingManagerPending;
      u.isReportingManagerPending = false;
      u.isReportingManagerRequestedAt = '';
    });
    await UserStore.upsertOne(u);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  _CategoryInfo get _leaveCategory => _CategoryInfo(
        icon: Icons.event_note_rounded,
        color: const Color(0xFF111827),
        label: 'Leave Applications',
        pending: _pendingLeave.length,
        approved: _historyLeave.where((a) => a.managerStatus == LeaveApprovalStatus.approved).length,
        rejected: _historyLeave.where((a) => a.managerStatus == LeaveApprovalStatus.denied).length,
        total: LeaveStore.applications.where((a) => !_isPermCompOff(a)).length,
        onViewAll: () => context.push('/management/leave/overview'),
      );

  _CategoryInfo get _permissionCategory => _CategoryInfo(
        icon: Icons.access_time_rounded,
        color: AppTheme.accentBlue,
        label: 'Permission Applications',
        pending: _pendingPermission.length,
        approved: _historyPermission.where((a) => a.managerStatus == LeaveApprovalStatus.approved).length,
        rejected: _historyPermission.where((a) => a.managerStatus == LeaveApprovalStatus.denied).length,
        total: LeaveStore.applications.where((a) => a.leaveType == 'Permission').length,
        onViewAll: () => context.push('/management/leave/overview'),
      );

  _CategoryInfo get _compOffCategory => _CategoryInfo(
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFF22C55E),
        label: 'Comp Off Applications',
        pending: _pendingCompOff.length,
        approved: _historyCompOff.where((a) => a.managerStatus == LeaveApprovalStatus.approved).length,
        rejected: _historyCompOff.where((a) => a.managerStatus == LeaveApprovalStatus.denied).length,
        total: LeaveStore.applications.where((a) => a.leaveType == 'Comp Off').length,
        onViewAll: () => context.push('/management/leave/overview'),
      );

  _CategoryInfo get _onrollCategory {
    final approved = _users.where((u) => u.onrollManagementStatus == 'accepted').length;
    final rejected = _users.where((u) => u.onrollManagementStatus == 'denied').length;
    return _CategoryInfo(
      icon: Icons.verified_user_rounded,
      color: AppTheme.sidebarSelectedBg,
      label: 'On-Roll Requests',
      pending: _pendingOnroll.length,
      approved: approved,
      rejected: rejected,
      total: approved + rejected + _pendingOnroll.length,
      onViewAll: () => context.push('/management/onroll-approvals'),
    );
  }

  _CategoryInfo get _grossPayCategory => _CategoryInfo(
        icon: Icons.currency_rupee_rounded,
        color: Colors.indigo.shade700,
        label: 'Gross Pay Change Requests',
        pending: _pendingGrossPay.length,
        approved: 0,
        rejected: 0,
        total: _pendingGrossPay.length,
        onViewAll: () => _showPendingSheet(
          label: 'Gross Pay Change Requests',
          color: Colors.indigo.shade700,
          buildCards: (refresh) => _pendingGrossPay
              .map((u) => _grossPayCard(u,
                  onApprove: () async { await _decideGrossPay(u, true); refresh(); },
                  onDeny: () async { await _decideGrossPay(u, false); refresh(); }))
              .toList(),
        ),
      );

  _CategoryInfo get _permissionQuotaCategory => _CategoryInfo(
        icon: Icons.timer_outlined,
        color: Colors.indigo.shade400,
        label: 'Permission Quota Change Requests',
        pending: _pendingPermissionQuota.length,
        approved: 0,
        rejected: 0,
        total: _pendingPermissionQuota.length,
        onViewAll: () => _showPendingSheet(
          label: 'Permission Quota Change Requests',
          color: Colors.indigo.shade400,
          buildCards: (refresh) => _pendingPermissionQuota
              .map((u) => _permissionQuotaCard(u,
                  onApprove: () async { await _decidePermissionQuota(u, true); refresh(); },
                  onDeny: () async { await _decidePermissionQuota(u, false); refresh(); }))
              .toList(),
        ),
      );

  _CategoryInfo get _workLocationCategory => _CategoryInfo(
        icon: Icons.location_on_rounded,
        color: Colors.teal.shade700,
        label: 'Work Location Change Requests',
        pending: _pendingWorkLocation.length,
        approved: 0,
        rejected: 0,
        total: _pendingWorkLocation.length,
        onViewAll: () => _showPendingSheet(
          label: 'Work Location Change Requests',
          color: Colors.teal.shade700,
          buildCards: (refresh) => _pendingWorkLocation
              .map((u) => _workLocationCard(u,
                  onApprove: () async { await _decideWorkLocation(u, true); refresh(); },
                  onDeny: () async { await _decideWorkLocation(u, false); refresh(); }))
              .toList(),
        ),
      );

  _CategoryInfo get _businessUnitCategory => _CategoryInfo(
        icon: Icons.corporate_fare_rounded,
        color: Colors.purple.shade700,
        label: 'Company Change Requests',
        pending: _pendingBusinessUnit.length,
        approved: 0,
        rejected: 0,
        total: _pendingBusinessUnit.length,
        onViewAll: () => _showPendingSheet(
          label: 'Company Change Requests',
          color: Colors.purple.shade700,
          buildCards: (refresh) => _pendingBusinessUnit
              .map((u) => _businessUnitCard(u,
                  onApprove: () async { await _decideBusinessUnit(u, true); refresh(); },
                  onDeny: () async { await _decideBusinessUnit(u, false); refresh(); }))
              .toList(),
        ),
      );

  _CategoryInfo get _reportingManagerCategory => _CategoryInfo(
        icon: Icons.manage_accounts_rounded,
        color: Colors.deepPurple.shade700,
        label: 'Reporting Manager Change Requests',
        pending: _pendingReportingManager.length,
        approved: 0,
        rejected: 0,
        total: _pendingReportingManager.length,
        onViewAll: () => _showPendingSheet(
          label: 'Reporting Manager Change Requests',
          color: Colors.deepPurple.shade700,
          buildCards: (refresh) => _pendingReportingManager
              .map((u) => _reportingManagerCard(u,
                  onApprove: () async { await _decideReportingManager(u, true); refresh(); },
                  onDeny: () async { await _decideReportingManager(u, false); refresh(); }))
              .toList(),
        ),
      );

  _CategoryInfo get _rmFlagCategory => _CategoryInfo(
        icon: Icons.supervisor_account_rounded,
        color: Colors.brown.shade600,
        label: '"Is Reporting Manager" Requests',
        pending: _pendingRmFlag.length,
        approved: 0,
        rejected: 0,
        total: _pendingRmFlag.length,
        onViewAll: () => _showPendingSheet(
          label: '"Is Reporting Manager" Requests',
          color: Colors.brown.shade600,
          buildCards: (refresh) => _pendingRmFlag
              .map((u) => _rmFlagCard(u,
                  onApprove: () async { await _decideRmFlag(u, true); refresh(); },
                  onDeny: () async { await _decideRmFlag(u, false); refresh(); }))
              .toList(),
        ),
      );

  _CategoryInfo get _kraCategory => _CategoryInfo(
        icon: Icons.flag_rounded,
        color: Colors.orange.shade700,
        label: 'KRA Approvals',
        pending: _pendingKra.length,
        approved: _kraDocs.where((d) => d.isApproved).length,
        rejected: _kraDocs.where((d) => d.isRejected).length,
        total: _kraDocs.length,
        onViewAll: () => context.push('/management/kra-approvals'),
      );

  _CategoryInfo _formCategory(String label, List<Map<String, dynamic>> versions) => _CategoryInfo(
        icon: Icons.description_rounded,
        color: AppTheme.primaryBlue,
        label: label,
        pending: _pendingOf(versions).length,
        approved: versions.where((v) => (v['status'] as String?) == 'approved').length,
        rejected: versions.where((v) => (v['status'] as String?) == 'rejected').length,
        total: versions.length,
        onViewAll: () => context.push('/management/form-approvals'),
      );

  _CategoryInfo get _leaveFormCategory =>
      _formCategory('Leave / Permission / Comp Off Form Approvals', _leaveVersions);
  _CategoryInfo get _interviewFormCategory => _formCategory('Interview Form Approvals', _interviewVersions);
  _CategoryInfo get _onboardingFormCategory => _formCategory('Onboarding Form Approvals', _onboardingVersions);
  _CategoryInfo get _policyCategory => _formCategory('HR Policy Approvals', _policyVersions);
  _CategoryInfo get _maintenanceFormCategory => _formCategory('Maintenance Form Approvals', _maintenanceVersions);

  List<_CategoryInfo> get _allCategories => [
        _leaveCategory, _permissionCategory, _compOffCategory, _onDutyCategory,
        // Scoped by role. Management sees every confirmation through RLS, so
        // without this Ronak was shown four overlapping attendance queues —
        // including HR's, which is not his to action.
        if (UserSession.isReportingManager) _vouchCategory,
        if (UserSession.role == UserRole.hr) _vouchHrCategory,
        // Oversight only — shown to Management, who can overturn but are not
        // a required signature. On other roles it would be a card with
        // nothing to do.
        if (UserSession.role == UserRole.management) ...[
          _vouchMgmtApprovalCategory,
          _vouchOversightCategory,
        ],
        _onrollCategory, _grossPayCategory, _permissionQuotaCategory, _workLocationCategory,
        _businessUnitCategory,
        _reportingManagerCategory, _rmFlagCategory, _kraCategory,
        _leaveFormCategory, _interviewFormCategory, _onboardingFormCategory,
        _policyCategory, _maintenanceFormCategory,
      ];

  // [buildCards] is re-invoked on every [refresh] call so that approving or
  // denying an item inside the open sheet removes it from the list right
  // away — the sheet lives in the Navigator's overlay, not this widget's
  // subtree, so it never rebuilds on its own when this State calls setState.
  void _showPendingSheet({
    required String label,
    required Color color,
    required List<Widget> Function(void Function() refresh) buildCards,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final cards = buildCards(() => setSheetState(() {}));
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            expand: false,
            builder: (ctx, scrollController) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.pending_actions_rounded, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color))),
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                ]),
                const Divider(),
                Expanded(
                  child: cards.isEmpty
                      ? Center(child: Text('Nothing pending',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13)))
                      : ListView(controller: scrollController, children: cards),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _tabView(List<_CategoryInfo> categories, {bool pendingOnly = false}) {
    final visible = pendingOnly ? categories.where((c) => c.pending > 0).toList() : categories;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: visible.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text('Nothing pending in this view',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
              ),
            )
          : Wrap(
              spacing: 16,
              runSpacing: 16,
              children: visible.map((c) => SizedBox(width: 300, child: _CategorySummaryCard(info: c))).toList(),
            ),
    );
  }

  static const _tabIcons = [
    Icons.grid_view_rounded,
    Icons.pending_actions_rounded,
    Icons.event_note_rounded,
    Icons.payments_rounded,
    Icons.group_add_rounded,
    Icons.list_alt_rounded,
    Icons.edit_document,
  ];
  static const _tabLabels = ['All', 'Pending', 'Leave', 'Payroll', 'Onboarding', 'Requests', 'Form Edit'];

  Future<void> _pickStatsMonth() async {
    final picked = await showMonthPicker(context, _statsMonth);
    if (picked != null && mounted) setState(() => _statsMonth = picked);
  }

  @override
  Widget build(BuildContext context) {
    final categories = _allCategories;
    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(children: [
            const NavBackButton(),
            const SizedBox(width: 8),
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlueDark.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.person_rounded, color: AppTheme.primaryBlueDark, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Approvals',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium),
                const Text('Review and take action on pending requests',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              ]),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh_rounded, color: AppTheme.primaryBlueDark),
              onPressed: _load,
            ),
          ]),
        ),
        const SizedBox(height: 16),
        if (!_loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _summaryBanner(),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: AppTheme.primaryBlueDark,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primaryBlueDark,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
              tabs: [
                for (var i = 0; i < _tabLabels.length; i++)
                  Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_tabIcons[i], size: 15),
                    const SizedBox(width: 6),
                    Text(i == 1 ? 'Pending ($_totalPending)' : _tabLabels[i]),
                  ])),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: OutlinedButton.icon(
              onPressed: _pickStatsMonth,
              icon: const Icon(Icons.filter_list_rounded, size: 16),
              label: Text(monthLabel(_statsMonth)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF374151),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
        _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            : switch (_tabs.index) {
                0 => _tabView(categories),
                1 => _tabView(categories, pendingOnly: true),
                2 => _tabView([_leaveCategory, _permissionCategory, _compOffCategory, _onDutyCategory,
                               if (UserSession.isReportingManager) _vouchCategory,
                               if (UserSession.role == UserRole.hr) _vouchHrCategory,
                               if (UserSession.role == UserRole.management) ...[
                                 _vouchMgmtApprovalCategory,
                                 _vouchOversightCategory,
                               ]]),
                3 => _tabView([_grossPayCategory]),
                4 => _tabView([_onrollCategory]),
                5 => _tabView([_permissionQuotaCategory, _workLocationCategory, _businessUnitCategory, _reportingManagerCategory, _rmFlagCategory, _kraCategory]),
                _ => _tabView([
                    _leaveFormCategory, _interviewFormCategory, _onboardingFormCategory,
                    _policyCategory, _maintenanceFormCategory,
                  ]),
              },
      ])),
    );
  }

  Widget _summaryBanner() {
    final caughtUp = _totalPending == 0;
    return Card(
      color: caughtUp ? const Color(0xFFF0FDF4) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: caughtUp ? const Color(0xFFBBF7D0) : const Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(builder: (context, constraints) {
          final message = Row(children: [
            Icon(caughtUp ? Icons.celebration_rounded : Icons.pending_actions_rounded,
                color: caughtUp ? Colors.green.shade400 : Colors.orange.shade600, size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(caughtUp ? "You're all caught up!" : '$_totalPending item${_totalPending == 1 ? '' : 's'} need your attention',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                const SizedBox(height: 2),
                Text(
                    caughtUp ? 'No pending approvals at the moment.' : 'Review the categories below to take action.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.schedule_rounded, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Last updated just now', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ]),
              ]),
            ),
          ]);
          final stats = Wrap(spacing: 10, runSpacing: 10, children: [
            _MiniStat(icon: Icons.hourglass_top_rounded, color: Colors.orange.shade700,
                value: '$_totalPending', label: 'Pending'),
            _MiniStat(icon: Icons.check_circle_rounded, color: const Color(0xFF22C55E),
                value: '$_approvedThisMonth', label: 'Approved This Month'),
            _MiniStat(icon: Icons.cancel_rounded, color: const Color(0xFFEF4444),
                value: '$_rejectedThisMonth', label: 'Rejected This Month'),
            _MiniStat(icon: Icons.donut_large_rounded, color: AppTheme.primaryBlue,
                value: '${_approvalRateThisMonth.toStringAsFixed(0)}%', label: 'Approval Rate This Month'),
          ]);
          if (constraints.maxWidth < 760) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              message, const SizedBox(height: 16), stats,
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: message),
            const SizedBox(width: 16),
            stats,
          ]);
        }),
      ),
    );
  }

  // ── Category-specific compact cards ──────────────────────────────────────

  Widget _grossPayCard(AppUser u, {required VoidCallback onApprove, required VoidCallback onDeny}) {
    return _ApprovalCard(
      title: u.name,
      subtitle: u.designation,
      details: [
        '₹${u.grossPay.toStringAsFixed(0)}/month → ₹${u.grossPayPending.toStringAsFixed(0)}/month',
      ],
      meta: _fmtIso(u.grossPayRequestedAt),
      onApprove: onApprove,
      onDeny: onDeny,
    );
  }

  static String _fmtMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Widget _permissionQuotaCard(AppUser u, {required VoidCallback onApprove, required VoidCallback onDeny}) {
    return _ApprovalCard(
      title: u.name,
      subtitle: u.designation,
      details: [
        '${_fmtMinutes(u.permissionMinutesQuota)}/month → ${_fmtMinutes(u.permissionMinutesQuotaPending)}/month',
      ],
      meta: _fmtIso(u.permissionMinutesQuotaRequestedAt),
      onApprove: onApprove,
      onDeny: onDeny,
    );
  }

  Widget _workLocationCard(AppUser u, {required VoidCallback onApprove, required VoidCallback onDeny}) {
    return _ApprovalCard(
      title: u.name,
      subtitle: u.designation,
      details: ['${u.workLocation.isEmpty ? '—' : u.workLocation} → ${u.workLocationPending}'],
      meta: _fmtIso(u.workLocationRequestedAt),
      onApprove: onApprove,
      onDeny: onDeny,
    );
  }

  Widget _businessUnitCard(AppUser u, {required VoidCallback onApprove, required VoidCallback onDeny}) {
    return _ApprovalCard(
      title: u.name,
      subtitle: u.designation,
      details: ['${u.businessUnit.isEmpty ? '—' : u.businessUnit} → ${u.businessUnitPending}'],
      meta: _fmtIso(u.businessUnitRequestedAt),
      onApprove: onApprove,
      onDeny: onDeny,
    );
  }

  Widget _reportingManagerCard(AppUser u, {required VoidCallback onApprove, required VoidCallback onDeny}) {
    return _ApprovalCard(
      title: u.name,
      subtitle: u.designation,
      details: [
        '${u.reportingManager.isEmpty ? '—' : u.reportingManager} → '
        '${u.reportingManagerPending.isEmpty ? 'None' : u.reportingManagerPending}',
      ],
      meta: _fmtIso(u.reportingManagerRequestedAt),
      onApprove: onApprove,
      onDeny: onDeny,
    );
  }

  Widget _rmFlagCard(AppUser u, {required VoidCallback onApprove, required VoidCallback onDeny}) {
    return _ApprovalCard(
      title: u.name,
      subtitle: u.designation,
      details: [
        '${u.isReportingManager ? 'Is RM' : 'Not RM'} → '
        '${u.isReportingManagerPending ? 'Make RM' : 'Remove RM'}',
      ],
      meta: _fmtIso(u.isReportingManagerRequestedAt),
      onApprove: onApprove,
      onDeny: onDeny,
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _fmtIso(String iso) {
    if (iso.isEmpty) return '';
    try {
      return _fmt(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }
}

// ── Category summary (dashboard card) ────────────────────────────────────

class _CategoryInfo {
  final IconData icon;
  final Color color;
  final String label;
  final int pending;
  final int approved;
  final int rejected;
  final int total;
  final VoidCallback onViewAll;
  const _CategoryInfo({
    required this.icon,
    required this.color,
    required this.label,
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.total,
    required this.onViewAll,
  });
}

class _CategorySummaryCard extends StatelessWidget {
  final _CategoryInfo info;
  const _CategorySummaryCard({required this.info});

  Widget _stat(String value, String label, Color color) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = info.color;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c, width: 3))),
        child: InkWell(
          onTap: info.onViewAll,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                  child: Icon(info.icon, color: c, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(info.label,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: info.pending > 0 ? Colors.orange.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${info.pending} Pending',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w700,
                          color: info.pending > 0 ? Colors.orange.shade700 : Colors.grey.shade500)),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                _stat('${info.approved}', 'Approved', const Color(0xFF22C55E)),
                _stat('${info.rejected}', 'Rejected', const Color(0xFFEF4444)),
                _stat('${info.total}', 'Total', const Color(0xFF6B7280)),
              ]),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(children: [
                Text('View all', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 14, color: c),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Mini stat tile (summary banner) ──────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _MiniStat({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
            Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }
}

// ── Generic compact approval card (used by the gross pay / work location
// pending sheets, which have no dedicated management page of their own) ───

class _ApprovalCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> details;
  final String meta;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;
  /// 'Deny' for a pending request; 'Overturn' where the decision is already
  /// made and Management is reversing it.
  final String denyLabel;
  const _ApprovalCard({
    required this.title,
    required this.subtitle,
    required this.details,
    required this.meta,
    this.onApprove,
    this.onDeny,
    this.denyLabel = 'Deny',
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
            child: Text(title.isNotEmpty ? title[0].toUpperCase() : '?',
                style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
                ),
                if (meta.isNotEmpty)
                  Text(meta, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ]),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              for (final d in details) ...[
                const SizedBox(height: 4),
                Text(d, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
              ],
              const SizedBox(height: 10),
              Row(children: [
                // Both buttons were always rendered, so a card with only one
                // action showed the other greyed out and looking broken. The
                // Management oversight card has no Approve: the request is
                // already approved, it can only be overturned.
                if (onDeny != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDeny,
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: Text(denyLabel),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (onDeny != null && onApprove != null)
                  const SizedBox(width: 10),
                if (onApprove != null)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check_rounded, size: 14),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
