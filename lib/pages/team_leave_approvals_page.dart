import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/org_lists.dart';
import '../models/app_user.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../widgets/back_button.dart';
import '../widgets/filter_panel.dart';
import '../widgets/filter_popup_button.dart';
import '../theme/app_theme.dart';
import 'hr_employee_records_page.dart' show EmployeeProfileDialog, EmployeeEditDialog;

enum _SortOrder { newestFirst, oldestFirst }

class TeamLeaveApprovalsPage extends StatefulWidget {
  /// isManagement: controls header label and icon (management vs manager)
  /// showAll: when true, shows every employee's leaves; when false, team only
  final bool isManagement;
  final bool showAll;
  /// When set, ignores showAll/team-membership entirely and instead shows
  /// only requests from employees whose AppUser.department is in this list
  /// (e.g. the Staff Portal's HR approval queue for Housekeeping/Support
  /// Staff, who have no reporting manager of their own).
  final List<String>? onlyDepartments;
  final String? title;
  final String? subtitle;
  const TeamLeaveApprovalsPage({
    super.key,
    this.isManagement = false,
    this.showAll = false,
    this.onlyDepartments,
    this.title,
    this.subtitle,
  });

  @override
  State<TeamLeaveApprovalsPage> createState() => _TeamLeaveApprovalsPageState();
}

class _TeamLeaveApprovalsPageState extends State<TeamLeaveApprovalsPage>
    with SingleTickerProviderStateMixin {
  static Color get _blue => AppTheme.primaryBlue;
  bool get _isMgmt   => widget.isManagement;
  bool get _showAll  => widget.showAll;

  late TabController _tabController;

  Set<String> _teamNames = {};
  List<AppUser> _users = [];
  bool _teamLoaded = false;
  String _search = '';
  LeaveApprovalStatus? _filterStatus;
  String? _departmentFilter;
  _SortOrder _sort = _SortOrder.newestFirst;
  bool _loading = false;

  bool _holidayBannerDismissed = false;
  bool _permBannerDismissed = false;

  int _page = 0;
  int _rowsPerPage = 10;

  List<LeaveApplication> get _requests {
    if (widget.onlyDepartments != null) {
      if (!_teamLoaded) return const [];
      return LeaveStore.applications
          .where((a) => widget.onlyDepartments!.contains(_userFor(a.employeeName)?.department ?? ''))
          .toList();
    }
    if (_showAll) return LeaveStore.applications;
    if (!_teamLoaded) return LeaveStore.applications;
    if (!_isMgmt) {
      // Manager: team's Permission/CompOff + regular leaves ≤ 2 days
      return LeaveStore.applications
          .where((a) => _teamNames.contains(a.employeeName) &&
              (a.leaveType == 'Permission' ||
               a.leaveType == 'Comp Off' ||
               a.effectiveDays <= 2))
          .toList();
    }
    // Management: all employees
    return LeaveStore.applications;
  }

  bool _matchesFilter(LeaveApplication r) {
    final matchSearch = _search.isEmpty ||
        r.employeeName.toLowerCase().contains(_search.toLowerCase()) ||
        r.leaveType.toLowerCase().contains(_search.toLowerCase());
    final matchStatus =
        _filterStatus == null || r.managerStatus == _filterStatus;
    final matchDept =
        _departmentFilter == null || r.department == _departmentFilter;
    return matchSearch && matchStatus && matchDept;
  }

  List<LeaveApplication> get _filtered =>
      _requests.where(_matchesFilter).toList();

  bool _isPermCompOff(LeaveApplication a) =>
      a.leaveType == 'Permission' || a.leaveType == 'Comp Off';

  List<LeaveApplication> _sorted(List<LeaveApplication> list) {
    final out = List<LeaveApplication>.from(list);
    out.sort((a, b) => _sort == _SortOrder.newestFirst
        ? b.appliedOn.compareTo(a.appliedOn)
        : a.appliedOn.compareTo(b.appliedOn));
    return out;
  }

  List<LeaveApplication> get _leaveSection {
    var src = _filtered.where((a) => !_isPermCompOff(a));
    // Manager only handles ≤ 2-day regular leaves; holidays go to Management
    if (!_isMgmt && !_showAll) src = src.where((a) => a.effectiveDays <= 2);
    return _sorted(src.toList());
  }

  List<LeaveApplication> get _permSection =>
      _sorted(_filtered.where((a) => a.leaveType == 'Permission').toList());

  List<LeaveApplication> get _compOffSection =>
      _sorted(_filtered.where((a) => a.leaveType == 'Comp Off').toList());

  List<LeaveApplication> get _currentTabList => switch (_tabController.index) {
        1 => _permSection,
        2 => _compOffSection,
        _ => _leaveSection,
      };

  // Stat cards reflect the full scope for this page (team or all), not the
  // currently-typed search/status filter — they're an overview, not a tally
  // of the visible rows.
  int get _pendingCount =>
      _requests.where((r) => r.managerStatus == LeaveApprovalStatus.pending).length;
  int get _approvedCount =>
      _requests.where((r) => r.managerStatus == LeaveApprovalStatus.approved).length;
  int get _deniedCount =>
      _requests.where((r) => r.managerStatus == LeaveApprovalStatus.denied).length;
  int get _approvalRate {
    final decided = _approvedCount + _deniedCount;
    if (decided == 0) return 100;
    return (_approvedCount / decided * 100).round();
  }

  List<String> get _departments => kDepartments;

  bool get _isStaffListTab => widget.onlyDepartments != null && _tabController.index == 2;

  // ── Staff List tab (Staff Portal / onlyDepartments mode only) ────────────
  List<AppUser> get _staffList {
    final depts = widget.onlyDepartments;
    if (depts == null) return const [];
    final q = _search.trim().toLowerCase();
    return _users.where((u) =>
        depts.contains(u.department) &&
        (q.isEmpty ||
            u.name.toLowerCase().contains(q) ||
            u.employeeId.toLowerCase().contains(q))).toList();
  }

  Future<void> _saveStaffUser(AppUser user) async {
    await UserStore.upsertOne(user);
    if (!mounted) return;
    setState(() {
      final idx = _users.indexWhere((u) => u.email == user.email);
      if (idx >= 0) {
        _users[idx] = user;
      } else {
        _users.add(user);
      }
    });
  }

  Future<void> _deleteStaffUser(AppUser user) async {
    await UserStore.deleteOne(user.email);
    if (!mounted) return;
    setState(() => _users.removeWhere((u) => u.email == user.email));
  }

  AppUser? _userFor(String name) {
    final n = name.trim().toLowerCase();
    for (final u in _users) {
      if (u.name.trim().toLowerCase() == n) return u;
    }
    return null;
  }

  void _resetPage() => setState(() => _page = 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _page = 0);
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SupabaseService.fetchLeaveApplications()
            .timeout(const Duration(seconds: 8)),
        UserStore.load(),
      ]);
      final leaves = results[0] as List<LeaveApplication>;
      final users  = results[1] as List<AppUser>;

      if (leaves.isNotEmpty) {
        LeaveStore.applications..clear()..addAll(leaves);
        LeaveStore.syncCounter();
      }

      final myTeam = users
          .where((u) => u.reportingManager == UserSession.name)
          .map((u) => u.name)
          .toSet();

      // HR also actions approvals for anyone whose reporting manager is an
      // oversight-only account, asking that manager directly. Without this
      // those requests sat with someone who does not use the system: one had
      // been pending since 08/08. Self-approval is excluded — HR standing in
      // for their own manager must not mean signing off their own leave.
      if (UserSession.role == UserRole.hr) {
        myTeam.addAll(users
            .where((u) {
              final mgr = users.where((m) =>
                  m.name.trim().toLowerCase() ==
                  u.reportingManager.trim().toLowerCase());
              return mgr.isNotEmpty && mgr.first.oversightOnly;
            })
            .map((u) => u.name)
            .where((n) => n != UserSession.name));
      }

      if (mounted) {
        setState(() {
          _teamNames  = myTeam;
          _users      = users;
          _teamLoaded = true;
          _loading    = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(LeaveApplication app) async {
    final by = UserSession.name;
    setState(() {
      app.managerStatus    = LeaveApprovalStatus.approved;
      app.decidedBy        = by;
      app.rejectionComment = '';
      app.decidedAt        = DateTime.now();
      if (_isMgmt) app.managementDecided = true;
    });
    if (_isMgmt) {
      await SupabaseService.updateLeaveManagementStatus(
          app.id, LeaveApprovalStatus.approved, decidedBy: by);
    } else {
      await SupabaseService.updateLeaveManagerStatus(
          app.id, LeaveApprovalStatus.approved, decidedBy: by);
    }
    _notifyLeaveDecision(app, true);
  }

  void _notifyLeaveDecision(LeaveApplication app, bool approved) {
    final user = _users.where((u) => u.name == app.employeeName).firstOrNull;
    if (user == null || user.email.isEmpty) return;
    NotificationService.leaveDecided(
      employeeEmail: user.email,
      leaveType: app.leaveType,
      approved: approved,
      employeeRoutePrefix: _routePrefixForRole(user.role),
      employeeName: app.employeeName,
    ).catchError((_) {});
  }

  String _routePrefixForRole(String role) {
    switch (role) {
      case 'Manager':    return '/manager';
      case 'Management': return '/management';
      case 'HR':         return '/hr';
      default:           return '/employee';
    }
  }

  Future<void> _deny(LeaveApplication app) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Deny Leave',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Reason for denial (optional):',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const SizedBox(height: 10),
          TextField(
            controller: reasonCtrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. Insufficient notice / Busy period',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
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
            child: const Text('Deny'),
          ),
        ],
      ),
    );
    if (ok != true) { reasonCtrl.dispose(); return; }
    final comment = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    final by = UserSession.name;
    setState(() {
      app.managerStatus    = LeaveApprovalStatus.denied;
      app.decidedBy        = by;
      app.rejectionComment = comment;
      app.decidedAt        = DateTime.now();
      if (_isMgmt) app.managementDecided = true;
    });
    if (_isMgmt) {
      await SupabaseService.updateLeaveManagementStatus(
          app.id, LeaveApprovalStatus.denied,
          decidedBy: by, rejectionComment: comment);
    } else {
      await SupabaseService.updateLeaveManagerStatus(
          app.id, LeaveApprovalStatus.denied,
          decidedBy: by, rejectionComment: comment);
    }
    _notifyLeaveDecision(app, false);
  }

  Future<void> _reset(LeaveApplication app) async {
    setState(() {
      app.managerStatus    = LeaveApprovalStatus.pending;
      app.decidedBy        = '';
      app.rejectionComment = '';
      app.decidedAt        = null;
      if (_isMgmt) app.managementDecided = false;
    });
    if (_isMgmt) {
      await SupabaseService.updateLeaveManagementStatus(
          app.id, LeaveApprovalStatus.pending);
    } else {
      await SupabaseService.updateLeaveManagerStatus(
          app.id, LeaveApprovalStatus.pending);
    }
  }

  // ── Detail dialog ────────────────────────────────────────────────────────

  void _showDetails(LeaveApplication req) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _blue.withValues(alpha: 0.1),
                    child: Text(
                      req.employeeName.isNotEmpty ? req.employeeName[0].toUpperCase() : '?',
                      style: TextStyle(color: _blue, fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(req.employeeName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      if (req.department.isNotEmpty)
                        Text(req.department,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ]),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _blue.withValues(alpha: 0.12)),
                  ),
                  child: Column(children: [
                    _DetailRow(Icons.label_rounded, 'Leave Type', req.leaveType),
                    const SizedBox(height: 8),
                    _DetailRow(Icons.date_range_rounded, 'Duration',
                        '${_fmtDate(req.from)}  →  ${_fmtDate(req.to)}'),
                    const SizedBox(height: 8),
                    _DetailRow(Icons.numbers_rounded, 'Days',
                        req.isHalfDay ? '½ day' : '${req.days} day${req.days == 1 ? '' : 's'}'),
                    const SizedBox(height: 8),
                    _DetailRow(Icons.calendar_today_rounded, 'Applied On', _fmtDateTime(req.appliedOn)),
                    if (req.reason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _DetailRow(Icons.notes_rounded, 'Reason', req.reason),
                    ],
                  ]),
                ),
                if (req.effectiveDays > 2) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.beach_access_rounded, size: 13, color: Colors.red.shade700),
                        const SizedBox(width: 5),
                        Text('Holiday — goes to Management',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade700)),
                      ]),
                    ),
                  ),
                ],
                if (req.leaveType == 'Permission') ...[
                  const SizedBox(height: 10),
                  Builder(builder: (ctx) {
                    final quota = _userFor(req.employeeName)?.permissionMinutesQuota ?? 120;
                    final used = LeaveStore.permUsedThisMonth(req.employeeName);
                    final remaining = (quota - used).clamp(0, quota);
                    final badgeColor = remaining == 0
                        ? Colors.red.shade700
                        : remaining <= 30 ? Colors.orange.shade700 : AppTheme.accentBlue;
                    return Row(children: [
                      Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Text('Monthly: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          remaining == 0 ? 'Limit reached' : '$remaining min left this month',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor),
                        ),
                      ),
                    ]);
                  }),
                ],
                const SizedBox(height: 16),
                if (!widget.isManagement && req.managementDecided)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(Icons.lock_rounded, size: 15, color: Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Decision locked by Management: ${_sl(req.managerStatus)}'
                          '${req.decidedBy.isNotEmpty ? ' (${req.decidedBy})' : ''}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ]),
                  )
                else if (req.managerStatus == LeaveApprovalStatus.pending)
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () { Navigator.pop(ctx); _deny(req); },
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Deny'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () { Navigator.pop(ctx); _approve(req); },
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ])
                else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _sc(req.managerStatus).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(_si(req.managerStatus), size: 16, color: _sc(req.managerStatus)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_sl(req.managerStatus)} by ${req.decidedBy.isEmpty ? 'Manager' : req.decidedBy}'
                          '${req.decidedAt != null ? ' · ${_fmtDateTime(req.decidedAt!)}' : ''}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _sc(req.managerStatus)),
                        ),
                      ),
                    ]),
                  ),
                  if (req.managerStatus == LeaveApprovalStatus.denied && req.rejectionComment.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text('Reason: ${req.rejectionComment}',
                          style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
                    ),
                  ],
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? (_showAll ? 'All Leave Approvals' : 'Team Leave Approvals');
    final subtitle = widget.subtitle ?? (_showAll
        ? 'View and edit all employee leave decisions'
        : 'Review and approve leave requests from your team');
    final narrow = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(child: Column(children: [
        // ── Fixed header ─────────────────────────────────────────────────
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const NavBackButton(),
              SizedBox(width: narrow ? 4 : 8),
              if (!narrow) ...[
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _isMgmt ? Icons.admin_panel_settings_rounded : Icons.group_rounded,
                    color: _blue, size: 22),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium),
                  if (!narrow) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                  ],
                ]),
              ),
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: IconButton(
                  tooltip: 'Refresh',
                  icon: Icon(Icons.refresh_rounded, color: _blue, size: 20),
                  onPressed: _loadData,
                ),
              ),
            ]),
            const SizedBox(height: 18),

            // ── Stat cards ──────────────────────────────────────────────
            _StatCardsRow(
              pending: _pendingCount,
              approved: _approvedCount,
              denied: _deniedCount,
              approvalRate: _approvalRate,
            ),
            const SizedBox(height: 16),

            // ── Tabs + filter toggle ───────────────────────────────────
            Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _PillTab(
                      label: 'Leave Applications',
                      count: _leaveSection.length,
                      selected: _tabController.index == 0,
                      onTap: () => setState(() { _tabController.index = 0; _page = 0; }),
                    ),
                    const SizedBox(width: 8),
                    _PillTab(
                      label: 'Permission Applications',
                      count: _permSection.length,
                      selected: _tabController.index == 1,
                      onTap: () => setState(() { _tabController.index = 1; _page = 0; }),
                    ),
                    const SizedBox(width: 8),
                    _PillTab(
                      label: widget.onlyDepartments != null ? 'Staff List' : 'Comp Off Applications',
                      count: widget.onlyDepartments != null ? _staffList.length : _compOffSection.length,
                      selected: _tabController.index == 2,
                      onTap: () => setState(() { _tabController.index = 2; _page = 0; }),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              if (!_isStaffListTab)
              FilterTriggerButton(
                hasActiveFilters: _departmentFilter != null || _filterStatus != null
                    || _sort != _SortOrder.newestFirst,
                onTap: () {
                  String? deptDraft = _departmentFilter;
                  LeaveApprovalStatus? statusDraft = _filterStatus;
                  _SortOrder sortDraft = _sort;
                  showFilterPanel(
                    context,
                    title: 'Filters',
                    onReset: () { deptDraft = null; statusDraft = null; sortDraft = _SortOrder.newestFirst; },
                    onApply: () => setState(() {
                      _departmentFilter = deptDraft; _filterStatus = statusDraft; _sort = sortDraft;
                      _resetPage();
                    }),
                    builder: (context, setPanelState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (_departments.length > 1)
                        FilterDropdownField<String>(
                          label: 'Department',
                          value: deptDraft,
                          options: _departments,
                          labelOf: (d) => d,
                          allLabel: 'All Departments',
                          onChanged: (v) => setPanelState(() => deptDraft = v),
                        ),
                      FilterChipGroup<LeaveApprovalStatus>(
                        label: 'Status',
                        value: statusDraft,
                        options: LeaveApprovalStatus.values,
                        labelOf: _sl,
                        onChanged: (v) => setPanelState(() => statusDraft = v),
                      ),
                      FilterDropdownField<_SortOrder>(
                        label: 'Sort',
                        value: sortDraft == _SortOrder.newestFirst ? null : sortDraft,
                        options: const [_SortOrder.oldestFirst],
                        labelOf: (s) => 'Oldest First',
                        allLabel: 'Newest First',
                        onChanged: (v) => setPanelState(() => sortDraft = v ?? _SortOrder.newestFirst),
                      ),
                    ]),
                  );
                },
              ),
            ]),
            const SizedBox(height: 12),

            // ── Search ────────────────────────────────────────────────
            TextField(
              onChanged: (v) { setState(() => _search = v); _resetPage(); },
              decoration: InputDecoration(
                hintText: 'Search employee or leave type...',
                prefixIcon: Icon(Icons.search_rounded, color: _blue, size: 20),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () { setState(() => _search = ''); _resetPage(); })
                    : null,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),

            if (_tabController.index == 0 && !_holidayBannerDismissed)
              _dismissibleBanner(
                'Leaves longer than 2 days are forwarded to Management for approval.',
                () => setState(() => _holidayBannerDismissed = true),
              ),
            if (_tabController.index == 1 && !_permBannerDismissed)
              _dismissibleBanner(
                'Each employee is entitled to 2 hours of permission per month by default (HR can request a higher quota for individual employees).',
                () => setState(() => _permBannerDismissed = true),
              ),
            const SizedBox(height: 4),
          ]),
        ),

        // ── Body ──────────────────────────────────────────────────────
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) => _buildBody(context),
        ),
      ])),
    );
  }

  Widget _dismissibleBanner(String text, VoidCallback onDismiss) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFF57F17)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 11, color: Color(0xFFF57F17), fontWeight: FontWeight.w500)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFF57F17)),
          ),
        ]),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isStaffListTab) {
      return _buildStaffListTab();
    }
    if (!_isMgmt && _teamLoaded && _teamNames.isEmpty) {
      return _emptyCard(
        icon: Icons.group_off_rounded,
        title: 'No employees assigned to you',
        subtitle: 'Ask Management to assign employees via Administration → Edit User → Reporting Manager.',
      );
    }
    if (_requests.isEmpty) {
      return _emptyCard(
        icon: Icons.inbox_rounded,
        title: _isMgmt ? 'No leave requests yet' : 'No leave requests from your team',
        subtitle: 'Leave requests will appear here for approval.',
      );
    }

    final list = _currentTabList;
    if (list.isEmpty) {
      return _emptyCard(
        icon: Icons.search_off_rounded,
        title: 'No requests match your filters',
        subtitle: '',
      );
    }

    final start = _page * _rowsPerPage;
    final pageItems = start >= list.length
        ? <LeaveApplication>[]
        : list.sublist(start, (start + _rowsPerPage).clamp(0, list.length));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final item in pageItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RequestRow(
                request: item,
                isManagement: _isMgmt,
                user: _userFor(item.employeeName),
                onApprove: () => _approve(item),
                onDeny: () => _deny(item),
                onReset: () => _reset(item),
                onViewDetails: () => _showDetails(item),
              ),
            ),
        ]),
      ),
      _Pagination(
        total: list.length,
        page: _page,
        rowsPerPage: _rowsPerPage,
        onPageChanged: (p) => setState(() => _page = p),
        onRowsPerPageChanged: (r) => setState(() { _rowsPerPage = r; _page = 0; }),
      ),
    ]);
  }

  Widget _buildStaffListTab() {
    final list = _staffList;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EmployeeEditDialog(user: null, allUsers: _users, onSave: _saveStaffUser),
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: const Text('Add Staff'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          _emptyCard(
            icon: Icons.groups_2_rounded,
            title: 'No staff accounts yet',
            subtitle: 'Use "Add Staff" above to create a Housekeeping / Support Staff account.',
          )
        else
          for (final u in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => EmployeeProfileDialog(
                        user: u, allUsers: _users, onSave: _saveStaffUser, onDelete: _deleteStaffUser),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: _blue.withValues(alpha: 0.1),
                    child: Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                        style: TextStyle(color: _blue, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    u.department,
                    if (u.employeeId.isNotEmpty) u.employeeId,
                    if (u.mobile.isNotEmpty) u.mobile,
                  ].join(' · ')),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (u.active ? Colors.green.shade700 : Colors.red.shade700).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: (u.active ? Colors.green.shade700 : Colors.red.shade700).withValues(alpha: 0.3)),
                    ),
                    child: Text(u.active ? 'Active' : 'Inactive',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: u.active ? Colors.green.shade700 : Colors.red.shade700)),
                  ),
                ),
              ),
            ),
      ]),
    );
  }

  Widget _emptyCard({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Builder(builder: (context) {
              final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3);
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 52, color: muted),
                const SizedBox(height: 12),
                Text(title, style: TextStyle(color: muted, fontSize: 14)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12)),
                ],
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

// ── Formatting helpers ──────────────────────────────────────────────────────

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _fmtDateShort(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
}

String _fmtDateTime(DateTime d) => '${_fmtDateShort(d)}, ${_fmtTime(d)}';

Color _sc(LeaveApprovalStatus s) => switch (s) {
      LeaveApprovalStatus.approved => Colors.green.shade700,
      LeaveApprovalStatus.denied   => Colors.red.shade700,
      LeaveApprovalStatus.pending  => Colors.orange.shade700,
    };
IconData _si(LeaveApprovalStatus s) => switch (s) {
      LeaveApprovalStatus.approved => Icons.check_circle_rounded,
      LeaveApprovalStatus.denied   => Icons.cancel_rounded,
      LeaveApprovalStatus.pending  => Icons.hourglass_empty_rounded,
    };
String _sl(LeaveApprovalStatus s) => switch (s) {
      LeaveApprovalStatus.approved => 'Approved',
      LeaveApprovalStatus.denied   => 'Denied',
      LeaveApprovalStatus.pending  => 'Pending',
    };

// ── Stat cards ───────────────────────────────────────────────────────────────

class _StatCardsRow extends StatelessWidget {
  final int pending;
  final int approved;
  final int denied;
  final int approvalRate;
  const _StatCardsRow({
    required this.pending,
    required this.approved,
    required this.denied,
    required this.approvalRate,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _StatTile(
        icon: Icons.hourglass_top_rounded,
        color: AppTheme.warning,
        value: '$pending',
        label: 'Pending',
        sublabel: 'Needs your action',
      ),
      _StatTile(
        icon: Icons.check_circle_rounded,
        color: AppTheme.success,
        value: '$approved',
        label: 'Approved',
        sublabel: 'This month',
      ),
      _StatTile(
        icon: Icons.cancel_rounded,
        color: AppTheme.error,
        value: '$denied',
        label: 'Denied',
        sublabel: 'This month',
      ),
      _StatTile(
        icon: Icons.trending_up_rounded,
        color: AppTheme.primaryBlue,
        value: '$approvalRate%',
        label: 'Approval Rate',
        sublabel: 'This month',
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 640;
      if (wide) {
        return Row(children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tiles[i]),
          ],
        ]);
      }
      return Wrap(
        spacing: 12, runSpacing: 12,
        children: [for (final t in tiles) SizedBox(width: 160, child: t)],
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String sublabel;
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
              Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF111827))),
              Text(sublabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Pill tab ─────────────────────────────────────────────────────────────────

class _PillTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _PillTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$label  $count',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }
}

// ── Filter toggle button ───────────────────────────────────────────────────


// ── Pagination ───────────────────────────────────────────────────────────────

class _Pagination extends StatelessWidget {
  final int total;
  final int page;
  final int rowsPerPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;

  const _Pagination({
    required this.total,
    required this.page,
    required this.rowsPerPage,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final totalPages = (total / rowsPerPage).ceil().clamp(1, 999999);
    final start = total == 0 ? 0 : page * rowsPerPage + 1;
    final end = ((page + 1) * rowsPerPage).clamp(0, total);

    // Windowed page numbers: first, last, and up to 2 neighbours of current.
    final pages = <int>{0, totalPages - 1};
    for (var p = page - 1; p <= page + 1; p++) {
      if (p >= 0 && p < totalPages) pages.add(p);
    }
    final sortedPages = pages.toList()..sort();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 640;
        final summary = Text('Showing $start to $end of $total',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600));

        final pager = Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            iconSize: 18,
            onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          for (var i = 0; i < sortedPages.length; i++) ...[
            if (i > 0 && sortedPages[i] - sortedPages[i - 1] > 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('…', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
              ),
            _PageNumberButton(
              number: sortedPages[i] + 1,
              selected: sortedPages[i] == page,
              onTap: () => onPageChanged(sortedPages[i]),
            ),
          ],
          IconButton(
            iconSize: 18,
            onPressed: page < totalPages - 1 ? () => onPageChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ]);

        final rowsDropdown = FilterPopupButton<int>(
          value: rowsPerPage,
          options: const [10, 20, 50],
          labelOf: (v) => '$v per page',
          icon: Icons.list_rounded,
          tooltip: 'Rows per page',
          onChanged: (v) => onRowsPerPageChanged(v ?? rowsPerPage),
        );

        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            summary,
            const SizedBox(height: 8),
            Row(children: [Expanded(child: Center(child: pager)), rowsDropdown]),
          ]);
        }
        return Row(children: [
          summary,
          const Spacer(),
          pager,
          const Spacer(),
          rowsDropdown,
        ]);
      }),
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  final int number;
  final bool selected;
  final VoidCallback onTap;
  const _PageNumberButton({required this.number, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 30, height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? AppTheme.primaryBlue : const Color(0xFFE5E7EB)),
          ),
          child: Text('$number',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF6B7280))),
        ),
      ),
    );
  }
}

// ── Request row (compact) ───────────────────────────────────────────────────

class _RequestRow extends StatefulWidget {
  final LeaveApplication request;
  final bool isManagement;
  final AppUser? user;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onReset;
  final VoidCallback onViewDetails;

  const _RequestRow({
    required this.request,
    required this.isManagement,
    required this.user,
    required this.onApprove,
    required this.onDeny,
    required this.onReset,
    required this.onViewDetails,
  });

  @override
  State<_RequestRow> createState() => _RequestRowState();
}

class _RequestRowState extends State<_RequestRow> {
  static const _undoWindow = Duration(minutes: 10);
  Timer? _timer;

  // Who else from this department is already off across the same dates.
  // The question every approver actually asks, and answering it previously
  // meant leaving the screen and reading the leave list by eye — so in
  // practice it was not asked at all, and clashes surfaced later.
  List<String>? _clash;

  Future<void> _loadClash() async {
    if (widget.request.managerStatus != LeaveApprovalStatus.pending) return;
    final dept = widget.user?.department ?? '';
    if (dept.isEmpty) return;
    final names = await SupabaseService.teamMembersOnLeave(
      department: dept,
      from: widget.request.from,
      to: widget.request.to,
      excludeName: widget.request.employeeName,
    );
    if (mounted) setState(() => _clash = names);
  }

  bool get _canUndo {
    final da = widget.request.decidedAt;
    if (da == null || widget.request.managerStatus == LeaveApprovalStatus.pending) return false;
    return DateTime.now().difference(da) < _undoWindow;
  }

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
    _loadClash();
  }

  @override
  void didUpdateWidget(covariant _RequestRow old) {
    super.didUpdateWidget(old);
    _timer?.cancel();
    _maybeStartTimer();
  }

  void _maybeStartTimer() {
    if (!_canUndo) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_canUndo) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final status = req.managerStatus;
    final locked = !widget.isManagement && req.managementDecided;

    final nameBlock = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
        child: Text(
          req.employeeName.isNotEmpty ? req.employeeName[0].toUpperCase() : '?',
          style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(req.employeeName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          if (widget.user?.designation.isNotEmpty ?? false)
            Text(widget.user!.designation,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          if (widget.user?.employeeId.isNotEmpty ?? false)
            Text(widget.user!.employeeId,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
        ]),
      ),
    ]);

    final leaveBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _LeaveTypeChip(req.leaveType),
      const SizedBox(height: 4),
      Text('${_fmtDate(req.from)} – ${_fmtDate(req.to)}',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
      Text(req.isHalfDay ? '½ Day' : '${req.days} Day${req.days == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
    ]);

    final reasonBlock = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.notes_rounded, size: 13, color: Colors.grey.shade500),
      const SizedBox(width: 5),
      Expanded(
        child: Text(req.reason.isEmpty ? '—' : req.reason,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
      ),
    ]);

    final appliedBlock = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey.shade500),
      const SizedBox(width: 5),
      Expanded(
        child: Text(_fmtDateTime(req.appliedOn),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
      ),
    ]);

    final statusBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _StatusPill(_sl(status), _sc(status), _si(status)),
      if (status != LeaveApprovalStatus.pending) ...[
        const SizedBox(height: 4),
        Text('by ${req.decidedBy.isEmpty ? 'Manager' : req.decidedBy}',
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
        if (req.decidedAt != null)
          Text(_fmtDateTime(req.decidedAt!),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
      ],
    ]);

    // Shown only when there IS a clash: a "nobody else is off" line on every
    // card would be noise and would stop the real warnings standing out.
    final clashBanner = (_clash == null || _clash!.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.groups_rounded, size: 13, color: Colors.orange.shade800),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Also off these dates: ${_clash!.join(', ')}',
                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900),
                ),
              ),
            ]),
          );

    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      if (locked)
        Icon(Icons.lock_rounded, size: 16, color: Colors.grey.shade400)
      else if (status == LeaveApprovalStatus.pending) ...[
        SizedBox(
          height: 32,
          child: ElevatedButton(
            onPressed: widget.onApprove,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: const Text('Approve'),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 32,
          child: OutlinedButton(
            onPressed: widget.onDeny,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade600,
              side: BorderSide(color: Colors.red.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: const Text('Reject'),
          ),
        ),
      ] else
        SizedBox(
          height: 32,
          child: OutlinedButton.icon(
            onPressed: widget.onViewDetails,
            icon: const Icon(Icons.visibility_outlined, size: 14),
            label: const Text('View Details'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      if (!locked)
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, size: 18, color: Colors.grey.shade500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (v) {
            if (v == 'details') widget.onViewDetails();
            if (v == 'reset') widget.onReset();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'details', child: Text('View Details')),
            if (_canUndo)
              const PopupMenuItem(value: 'reset', child: Text('Reset to Pending')),
          ],
        ),
    ]);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: nameBlock), statusBlock]),
                const SizedBox(height: 10),
                leaveBlock,
                const SizedBox(height: 8),
                reasonBlock,
                const SizedBox(height: 6),
                appliedBlock,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actions),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: nameBlock),
              Expanded(flex: 2, child: leaveBlock),
              Expanded(flex: 3, child: reasonBlock),
              Expanded(flex: 2, child: appliedBlock),
              Expanded(flex: 2, child: statusBlock),
              actions,
            ]);
          }),
          // After the LayoutBuilder so it appears once, on both the narrow
          // and wide arrangements, rather than being duplicated into each.
          clashBanner,
          if (status == LeaveApprovalStatus.denied && req.rejectionComment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                Icon(Icons.close_rounded, size: 13, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Reason: ${req.rejectionComment}',
                      style: TextStyle(fontSize: 11.5, color: Colors.red.shade800)),
                ),
              ]),
            ),
          ],
          if (locked) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Decision locked by Management: ${_sl(status)}'
                '${req.decidedBy.isNotEmpty ? ' (${req.decidedBy})' : ''}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Leave type chip ─────────────────────────────────────────────────────────

class _LeaveTypeChip extends StatelessWidget {
  final String type;
  const _LeaveTypeChip(this.type);

  IconData get _icon => switch (type) {
        'Permission' => Icons.access_time_rounded,
        'Comp Off'   => Icons.swap_horiz_rounded,
        _            => Icons.event_note_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(_icon, size: 13, color: AppTheme.primaryBlue),
      const SizedBox(width: 5),
      Flexible(
        child: Text(type,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryBlue)),
      ),
    ]);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Colors.grey.shade500),
      const SizedBox(width: 8),
      Text('$label: ',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
      Expanded(
        child: Text(value,
            style: TextStyle(fontSize: 12, color: AppTheme.primaryBlue, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusPill(this.label, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}
