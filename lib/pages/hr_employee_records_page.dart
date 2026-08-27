import 'dart:async';
import '../utils/attendance_cycle.dart';
import '../utils/checkin_status.dart';
import '../models/office_timing.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/org_lists.dart';
import '../models/app_user.dart';
import '../models/appraisal_store.dart' show visibleManagersForPicker;
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../utils/tenure.dart';
import '../widgets/back_button.dart';
import '../widgets/employee_list_dialog.dart';
import '../widgets/filter_panel.dart';
import 'employee_onboarding_page.dart' show OnboardingFormReadOnlyBody;
import 'candidate_detail_page.dart' show CandidateDetailBody;
import '../theme/app_theme.dart';

enum _SortOrder { newestFirst, oldestFirst, alphabetical, joinOldNew, joinNewOld }
enum _StatusFilter { all, onroll, probation, eligible, deactivated }

const _sortLabels = {
  _SortOrder.newestFirst:  'Recently Added',
  _SortOrder.oldestFirst:  'Added First',
  _SortOrder.alphabetical: 'A → Z',
  _SortOrder.joinOldNew:   'Join Date ↑',
  _SortOrder.joinNewOld:   'Join Date ↓',
};

// dateOfJoining/dateOfBirth are stored as either ISO or dd/MM/yyyy (see
// tenure.dart's parseFlexibleDate) — normalize to dd/MM/yyyy for display so
// a raw ISO timestamp never shows up unformatted. Falls back to the raw
// value if it doesn't parse, rather than hiding it.
String _fmtDate(String value) {
  if (value.isEmpty) return '';
  final d = parseFlexibleDate(value);
  if (d == null) return value;
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class HrEmployeeRecordsPage extends StatefulWidget {
  const HrEmployeeRecordsPage({super.key});

  @override
  State<HrEmployeeRecordsPage> createState() => _HrEmployeeRecordsPageState();
}

class _HrEmployeeRecordsPageState extends State<HrEmployeeRecordsPage> {
  static Color get _color => AppTheme.primaryBlue;
  List<AppUser> _all = [];
  // Same population as _all but without the role != 'Management' exclusion —
  // Management accounts aren't employees so they stay out of the Employee
  // Management table/stats, but they (like HR) can always be picked as
  // someone's Reporting Manager, so the manager-picker dropdown needs them.
  List<AppUser> _managerPool = [];
  List<AppUser> _filtered = [];
  List<LeaveApplication> _leaveApps = [];
  bool _loading = true;
  String _search = '';
  _SortOrder _sort = _SortOrder.newestFirst;
  _StatusFilter _statusFilter = _StatusFilter.all;
  String? _deptFilter;
  String? _designationFilter;
  String? _workLocationFilter;
  String? _businessUnitFilter;

  List<String> get _departmentOptions =>
      (_all.map((u) => u.department).where((d) => d.isNotEmpty).toSet().toList()..sort());
  List<String> get _designationOptions =>
      (_all.map((u) => u.designation).where((d) => d.isNotEmpty).toSet().toList()..sort());

  int get _countActive      => _all.where((u) => u.active).length;
  int get _countOnroll      => _all.where((u) => u.isOnroll).length;
  int get _countProbation   => _all.where((u) => !u.isOnroll).length;
  int get _countEligible    => _all.where((u) => u.isElEligible).length;
  int get _countDeactivated => _all.where((u) => !u.active).length;

  List<AppUser> get _onLeaveTodayUsers {
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    final onLeaveNames = _leaveApps
        .where((a) =>
            a.managerStatus == LeaveApprovalStatus.approved &&
            !d.isBefore(DateTime(a.from.year, a.from.month, a.from.day)) &&
            !d.isAfter(DateTime(a.to.year, a.to.month, a.to.day)))
        .map((a) => a.employeeName.toLowerCase())
        .toSet();
    return _all.where((u) => onLeaveNames.contains(u.name.toLowerCase())).toList();
  }

  int get _countOnLeaveToday => _onLeaveTodayUsers.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      UserStore.load(),
      SupabaseService.fetchLeaveApplications(),
    ]);
    if (!mounted) return;
    final raw = results[0] as List<AppUser>;
    setState(() {
      _all = _baseList(raw);
      _managerPool = _managerCandidatesList(raw);
      _leaveApps = results[1] as List<LeaveApplication>;
      _applyFilter();
      _loading = false;
    });
  }

  // HR/Management see everyone; anyone flagged as a reporting manager (any
  // role) sees only the employees assigned to them. Housekeeping/Support
  // Staff (Staff Portal accounts) are managed from Staff Portal Approvals
  // instead, so they're excluded from this list entirely — and Management
  // (e.g. Director) accounts aren't employees at all (see role_hierarchy
  // notes: Management manages/decides but doesn't participate in
  // employee-level flows), so they don't belong in Employee Management either.
  List<AppUser> _baseList(List<AppUser> users) {
    final withoutStaffPortal = users
        .where((u) => !kStaffPortalDepartments.contains(u.department) && u.role != 'Management')
        .toList();
    final isHrOrMgmt = UserSession.role == UserRole.hr || UserSession.role == UserRole.management;
    if (isHrOrMgmt) return withoutStaffPortal;
    if (!UserSession.isReportingManager) return const [];
    final me = UserSession.name.trim().toLowerCase();
    if (me.isEmpty) return const [];
    return withoutStaffPortal
        .where((u) => u.reportingManager.trim().toLowerCase() == me)
        .toList();
  }

  // Same viewer-scoping as _baseList, but keeps Management accounts in —
  // they're not employees, but (like HR) are always valid Reporting Manager
  // choices. Feeds visibleManagersForPicker() via EmployeeEditDialog instead
  // of the Management-free _all.
  List<AppUser> _managerCandidatesList(List<AppUser> users) {
    final withoutStaffPortal =
        users.where((u) => !kStaffPortalDepartments.contains(u.department)).toList();
    final isHrOrMgmt = UserSession.role == UserRole.hr || UserSession.role == UserRole.management;
    if (isHrOrMgmt) return withoutStaffPortal;
    if (!UserSession.isReportingManager) return const [];
    final me = UserSession.name.trim().toLowerCase();
    if (me.isEmpty) return const [];
    return withoutStaffPortal
        .where((u) => u.reportingManager.trim().toLowerCase() == me)
        .toList();
  }

  // dateOfJoining is stored as either ISO or dd/MM/yyyy (see tenure.dart's
  // parseFlexibleDate) — this used to only handle dd/MM/yyyy, so every
  // account created after the ISO-format switch sorted to the very end
  // regardless of its actual join date.
  static DateTime _parseJoin(AppUser u) =>
      parseFlexibleDate(u.dateOfJoining) ?? DateTime(2099); // unknown → sort to end

  void _applyFilter() {
    List<AppUser> list = List.from(_all);

    // Status classification
    switch (_statusFilter) {
      case _StatusFilter.onroll:
        list = list.where((u) => u.isOnroll).toList();
      case _StatusFilter.probation:
        list = list.where((u) => !u.isOnroll).toList();
      case _StatusFilter.eligible:
        list = list.where((u) => u.isElEligible).toList();
      case _StatusFilter.deactivated:
        list = list.where((u) => !u.active).toList();
      case _StatusFilter.all:
        break;
    }

    if (_deptFilter != null) list = list.where((u) => u.department == _deptFilter).toList();
    if (_designationFilter != null) list = list.where((u) => u.designation == _designationFilter).toList();
    if (_workLocationFilter != null) list = list.where((u) => u.workLocation == _workLocationFilter).toList();
    if (_businessUnitFilter != null) list = list.where((u) => u.businessUnit == _businessUnitFilter).toList();

    // Search
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((u) =>
          u.name.toLowerCase().contains(q) ||
          u.employeeId.toLowerCase().contains(q) ||
          u.designation.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q)).toList();
    }

    // Sort
    switch (_sort) {
      case _SortOrder.newestFirst:
        list = list.reversed.toList();
      case _SortOrder.oldestFirst:
        break; // keep original insertion order
      case _SortOrder.alphabetical:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _SortOrder.joinOldNew:
        list.sort((a, b) => _parseJoin(a).compareTo(_parseJoin(b)));
      case _SortOrder.joinNewOld:
        list.sort((a, b) => _parseJoin(b).compareTo(_parseJoin(a)));
    }

    // Active on top, deactivated at bottom
    final active   = list.where((u) =>  u.active).toList();
    final inactive = list.where((u) => !u.active).toList();
    _filtered = [...active, ...inactive];
  }

  Future<void> _saveUser(AppUser user) async {
    await UserStore.upsertOne(user);
    if (!mounted) return;
    setState(() {
      final idx = _all.indexWhere((u) => u.email == user.email);
      if (idx >= 0) {
        _all[idx] = user;
      } else {
        _all.add(user);
      }
      _applyFilter();
    });
  }

  // Staff Portal users (Housekeeping/Support Staff) are entirely HR-owned —
  // unlike the general employee roster, HR can delete them directly here
  // with no Management approval. General employee deletion stays
  // Management-only via the Administration page.
  Future<void> _deleteUser(AppUser user) async {
    await UserStore.deleteOne(user.email);
    if (!mounted) return;
    setState(() {
      _all.removeWhere((u) => u.email == user.email);
      _applyFilter();
    });
  }

  void _openProfile(AppUser user) {
    showDialog(
      context: context,
      builder: (_) => EmployeeProfileDialog(
          user: user, allUsers: _all, managerCandidates: _managerPool,
          onSave: _saveUser, onDelete: _deleteUser),
    );
  }

  void _openCreate() {
    showDialog(
      context: context,
      builder: (_) => EmployeeEditDialog(
          user: null, allUsers: _all, managerCandidates: _managerPool, onSave: _saveUser),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: null,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, (_loading || _filtered.isEmpty) ? 24 : 0),
            sliver: SliverToBoxAdapter(
              child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Builder(builder: (context) {
              final narrow = MediaQuery.of(context).size.width < 600;
              final canManage = UserSession.role == UserRole.hr ||
                  UserSession.role == UserRole.management;
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const NavBackButton(),
                SizedBox(width: narrow ? 4 : 8),
                if (!narrow) ...[
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.people_alt_rounded, color: _color, size: 22),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Employee Directory',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium),
                    if (!narrow) ...[
                      const SizedBox(height: 2),
                      Text('Manage and view employee information',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                    ],
                  ]),
                ),
                SizedBox(width: narrow ? 4 : 8),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: IconButton(
                    tooltip: 'Refresh',
                    icon: Icon(Icons.refresh_rounded, color: _color, size: 20),
                    onPressed: _load,
                  ),
                ),
                if (canManage) ...[
                  SizedBox(width: narrow ? 4 : 8),
                  narrow
                      ? IconButton(
                          tooltip: 'Reporting Managers',
                          onPressed: () => context.push(UserSession.role == UserRole.management
                              ? '/management/employee-management/reporting-managers'
                              : '/employee-management/reporting-managers'),
                          icon: Icon(Icons.account_tree_rounded, color: _color),
                          style: IconButton.styleFrom(
                            side: BorderSide(color: _color.withValues(alpha: 0.4)),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => context.push(UserSession.role == UserRole.management
                              ? '/management/employee-management/reporting-managers'
                              : '/employee-management/reporting-managers'),
                          icon: const Icon(Icons.account_tree_rounded, size: 16),
                          label: const Text('Reporting Managers'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _color,
                            side: BorderSide(color: _color.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                ],
                if (canManage) ...[
                  SizedBox(width: narrow ? 4 : 8),
                  narrow
                      ? IconButton(
                          tooltip: 'Add New Employee',
                          onPressed: _openCreate,
                          icon: const Icon(Icons.add_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: _color,
                            foregroundColor: Colors.white,
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: _openCreate,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add New Employee'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _color,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                ],
              ]);
            }),
            const SizedBox(height: 20),

            // ── Stat cards ───────────────────────────────────────────────
            _StatCardsRow(
              total: _all.length,
              active: _countActive,
              probation: _countProbation,
              onLeave: _countOnLeaveToday,
              deactivated: _countDeactivated,
              allUsers: _all,
              onLeaveUsers: _onLeaveTodayUsers,
            ),

            const SizedBox(height: 20),

            // ── Search + sort ────────────────────────────────────────────
            LayoutBuilder(builder: (context, constraints) {
              final search = TextField(
                onChanged: (v) => setState(() {
                  _search = v;
                  _applyFilter();
                }),
                decoration: InputDecoration(
                  hintText: 'Search by name, ID, designation, email...',
                  prefixIcon: Icon(Icons.search_rounded,
                      color: _color, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: _color, width: 2),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              );
              final filterBtn = FilterTriggerButton(
                hasActiveFilters: _statusFilter != _StatusFilter.all || _sort != _SortOrder.newestFirst ||
                    _deptFilter != null || _designationFilter != null ||
                    _workLocationFilter != null || _businessUnitFilter != null,
                onTap: () {
                  _StatusFilter statusDraft = _statusFilter;
                  _SortOrder sortDraft = _sort;
                  String? deptDraft = _deptFilter;
                  String? designationDraft = _designationFilter;
                  String? workLocationDraft = _workLocationFilter;
                  String? businessUnitDraft = _businessUnitFilter;
                  showFilterPanel(
                    context,
                    title: 'Filters',
                    onReset: () {
                      statusDraft = _StatusFilter.all; sortDraft = _SortOrder.newestFirst;
                      deptDraft = null; designationDraft = null;
                      workLocationDraft = null; businessUnitDraft = null;
                    },
                    onApply: () => setState(() {
                      _statusFilter = statusDraft; _sort = sortDraft;
                      _deptFilter = deptDraft; _designationFilter = designationDraft;
                      _workLocationFilter = workLocationDraft; _businessUnitFilter = businessUnitDraft;
                      _applyFilter();
                    }),
                    builder: (context, setPanelState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      FilterChipGroup<_StatusFilter>(
                        label: 'Status',
                        value: statusDraft == _StatusFilter.all ? null : statusDraft,
                        options: const [_StatusFilter.onroll, _StatusFilter.probation,
                            _StatusFilter.eligible, _StatusFilter.deactivated],
                        labelOf: (s) => switch (s) {
                          _StatusFilter.all => 'All (${_all.length})',
                          _StatusFilter.onroll => 'On-Roll ($_countOnroll)',
                          _StatusFilter.probation => 'Probation ($_countProbation)',
                          _StatusFilter.eligible => 'EL Eligible ($_countEligible)',
                          _StatusFilter.deactivated => 'Deactivated ($_countDeactivated)',
                        },
                        onChanged: (v) => setPanelState(() => statusDraft = v ?? _StatusFilter.all),
                      ),
                      if (_departmentOptions.isNotEmpty)
                        FilterChipGroup<String>(
                          label: 'Department',
                          value: deptDraft,
                          options: _departmentOptions,
                          labelOf: (d) => d,
                          onChanged: (v) => setPanelState(() => deptDraft = v),
                        ),
                      if (_designationOptions.isNotEmpty)
                        FilterChipGroup<String>(
                          label: 'Designation',
                          value: designationDraft,
                          options: _designationOptions,
                          labelOf: (d) => d,
                          onChanged: (v) => setPanelState(() => designationDraft = v),
                        ),
                      FilterChipGroup<String>(
                        label: 'Work Location',
                        value: workLocationDraft,
                        options: const ['Office', 'Onsite', 'Field'],
                        labelOf: (d) => d,
                        onChanged: (v) => setPanelState(() => workLocationDraft = v),
                      ),
                      FilterChipGroup<String>(
                        label: 'Company',
                        value: businessUnitDraft,
                        options: const ['FOMRA Developers', 'FOMRA Housing'],
                        labelOf: (d) => d,
                        onChanged: (v) => setPanelState(() => businessUnitDraft = v),
                      ),
                      FilterChipGroup<_SortOrder>(
                        label: 'Sort',
                        value: sortDraft == _SortOrder.newestFirst ? null : sortDraft,
                        options: const [_SortOrder.oldestFirst, _SortOrder.alphabetical,
                            _SortOrder.joinOldNew, _SortOrder.joinNewOld],
                        labelOf: (s) => _sortLabels[s]!,
                        onChanged: (v) => setPanelState(() => sortDraft = v ?? _SortOrder.newestFirst),
                      ),
                    ]),
                  );
                },
              );
              if (constraints.maxWidth < 560) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Card(child: Padding(padding: const EdgeInsets.all(16), child: search)),
                  const SizedBox(height: 10),
                  filterBtn,
                ]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                  child: Card(child: Padding(padding: const EdgeInsets.all(16), child: search)),
                ),
                const SizedBox(width: 12),
                filterBtn,
              ]);
            }),
            const SizedBox(height: 16),

            // ── List ─────────────────────────────────────────────────────
            if (_loading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_filtered.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.people_outline_rounded,
                          size: 52, color: Colors.grey.shade300),
                      const SizedBox(height: 10),
                      Text(
                        _all.isEmpty
                            ? 'No employee records yet. Tap "Add New" to add one.'
                            : 'No results for "$_search"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey.shade400, fontSize: 14),
                      ),
                    ]),
                  ),
                ),
              ),
            ],
              ),
            ),
          ),
          if (!_loading && _filtered.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final u = _filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _UserCard(user: u, onTap: () => _openProfile(u)),
                    );
                  },
                  childCount: _filtered.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Employee card ─────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;
  const _UserCard({required this.user, required this.onTap});

  static Color _roleColor(String role) {
    switch (role) {
      case 'HR':         return const Color(0xFF2563EB);
      case 'Manager':    return const Color(0xFF111827);
      case 'Management': return const Color(0xFF1D4ED8);
      default:           return const Color(0xFF22C55E);
    }
  }

  static IconData _locationIcon(String loc) =>
      loc == 'Onsite' ? Icons.location_on_rounded : Icons.apartment_rounded;

  Widget _infoColumn(String label, Widget value) => SizedBox(
        width: 118,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          value,
        ]),
      );

  Widget _nameBlock({bool showWorkLocationBadge = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
    Row(children: [
      Expanded(
        child: Text(user.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827))),
      ),
      if (!user.active)
        _Badge('Inactive', Colors.red.shade50,
            Colors.red.shade200, Colors.red.shade600),
    ]),
    const SizedBox(height: 4),
    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (user.employeeId.isNotEmpty) _IdChip(user.employeeId),
      _RoleChip(user.role, _roleColor(user.role)),
      if (user.businessUnit.isNotEmpty)
        _Badge(user.businessUnit, Colors.purple.shade50,
            Colors.purple.shade200, Colors.purple.shade700),
      if (user.isElEligible) _Badge('EL Eligible', AppTheme.primaryBlue.withValues(alpha: 0.08),
          AppTheme.primaryBlue.withValues(alpha: 0.3), AppTheme.primaryBlue),
      if (showWorkLocationBadge && user.workLocation.isNotEmpty)
        _Badge(user.workLocation,
            user.workLocation == 'Onsite' ? Colors.teal.shade50 : Colors.indigo.shade50,
            user.workLocation == 'Onsite' ? Colors.teal.shade200 : Colors.indigo.shade200,
            user.workLocation == 'Onsite' ? Colors.teal.shade700 : Colors.indigo.shade700),
      if (user.onrollRequestedAt.isNotEmpty && !user.isOnroll &&
          !user.onrollDenied &&
          fullMonthsSince(user.dateOfJoining) >= 6)
        _Badge('On-Roll Requested', Colors.orange.shade50,
            Colors.orange.shade200, Colors.orange.shade800),
      if (user.hasPendingWorkLocationChange)
        _Badge('Location Change Requested', Colors.orange.shade50,
            Colors.orange.shade200, Colors.orange.shade800),
      if (user.hasPendingGrossPayChange &&
          (UserSession.role == UserRole.hr || UserSession.role == UserRole.management))
        _Badge('Pay Change Requested', Colors.orange.shade50,
            Colors.orange.shade200, Colors.orange.shade800),
    ]),
    if (user.designation.isNotEmpty) ...[
      const SizedBox(height: 4),
      Text(user.designation,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
    ],
    if (user.email.isNotEmpty || user.mobile.isNotEmpty) ...[
      const SizedBox(height: 6),
      Wrap(spacing: 14, runSpacing: 2, children: [
        if (user.email.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.email_rounded, size: 12, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(user.email, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ]),
        if (user.mobile.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.phone_rounded, size: 12, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(user.mobile, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ]),
      ]),
    ],
  ]);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth > 760;
            final avatar = CircleAvatar(
              radius: 24,
              backgroundColor: _roleColor(user.role).withValues(alpha: 0.12),
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: TextStyle(
                    color: _roleColor(user.role), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            );
            if (!wide) {
              return Row(children: [
                avatar,
                const SizedBox(width: 14),
                Expanded(child: _nameBlock(showWorkLocationBadge: true)),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 20),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              avatar,
              const SizedBox(width: 14),
              Expanded(flex: 3, child: _nameBlock()),
              const SizedBox(width: 12),
              _infoColumn('Department', Text(
                  user.department.isNotEmpty ? user.department : '—',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: Color(0xFF111827)))),
              _infoColumn('Joined On', Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_today_rounded, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 5),
                Flexible(child: Text(
                    user.dateOfJoining.isNotEmpty ? _fmtDate(user.dateOfJoining) : '—',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                        color: Color(0xFF111827)))),
              ])),
              _infoColumn('Work Location', user.workLocation.isEmpty
                  ? Text('—', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_locationIcon(user.workLocation), size: 13, color: Colors.grey.shade500),
                      const SizedBox(width: 5),
                      Text(user.workLocation,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                              color: Color(0xFF111827))),
                    ])),
              _infoColumn('Status', _StatusPill(user.leaveStatus)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400, size: 20),
            ]);
          }),
        ),
      ),
    );
  }
}

// ── Profile detail dialog ─────────────────────────────────────────────────────

class EmployeeProfileDialog extends StatefulWidget {
  final AppUser user;
  final List<AppUser> allUsers;
  // Pool the Reporting Manager picker chooses from, forwarded to the Edit
  // dialog it opens. Defaults to allUsers when the caller doesn't supply a
  // separate pool (e.g. Staff Portal, whose allUsers already includes
  // Management) — see HrEmployeeRecordsPage._managerPool for why Employee
  // Management needs a distinct one.
  final List<AppUser>? managerCandidates;
  final Future<void> Function(AppUser) onSave;
  final Future<void> Function(AppUser)? onDelete;
  const EmployeeProfileDialog(
      {required this.user, required this.allUsers, this.managerCandidates,
       required this.onSave, this.onDelete});

  @override
  State<EmployeeProfileDialog> createState() => EmployeeProfileDialogState();
}

class EmployeeProfileDialogState extends State<EmployeeProfileDialog> {
  static const _undoWindow = Duration(minutes: 10);
  late AppUser _user;
  Timer? _onrollTimer;
  Timer? _elTimer;
  bool _saving = false;

  static Color _roleColor(String role) {
    switch (role) {
      case 'HR':         return const Color(0xFF2563EB);
      case 'Manager':    return const Color(0xFF111827);
      case 'Management': return const Color(0xFF1D4ED8);
      default:           return const Color(0xFF22C55E);
    }
  }

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _startTimers();
  }

  @override
  void dispose() {
    _onrollTimer?.cancel();
    _elTimer?.cancel();
    super.dispose();
  }

  void _startTimers() {
    if (_canUndoHr || _canUndoManager || _canUndoConfirmed) {
      _onrollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!_canUndoHr && !_canUndoManager && !_canUndoConfirmed) _onrollTimer?.cancel();
      });
    }
    if (_canUndoEl) {
      _elTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!_canUndoEl) _elTimer?.cancel();
      });
    }
  }

  bool _canUndo(String status, String decidedAt) {
    if (status == 'pending' || decidedAt.isEmpty) return false;
    try {
      return DateTime.now().difference(DateTime.parse(decidedAt)) < _undoWindow;
    } catch (_) { return false; }
  }

  bool get _canUndoHr => _canUndo(_user.onrollHrStatus, _user.onrollHrDecidedAt);
  bool get _canUndoManager => _canUndo(_user.onrollManagerStatus, _user.onrollManagerDecidedAt);

  bool get _canUndoConfirmed {
    if (_user.onrollConfirmedAt.isEmpty) return false;
    try {
      return DateTime.now().difference(DateTime.parse(_user.onrollConfirmedAt)) < _undoWindow;
    } catch (_) { return false; }
  }

  bool get _canUndoEl {
    if (_user.elEligibleAt.isEmpty) return false;
    try {
      return DateTime.now().difference(DateTime.parse(_user.elEligibleAt)) < _undoWindow;
    } catch (_) { return false; }
  }

  String _countdown(String ts) {
    try {
      final remaining = _undoWindow - DateTime.now().difference(DateTime.parse(ts));
      if (remaining.isNegative) return '';
      final m = remaining.inMinutes;
      final s = remaining.inSeconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  Future<String?> _promptDenyComment(String title) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Reason for denial (optional):',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. Attendance concerns / Performance',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Deny'),
          ),
        ],
      ),
    );
    final result = (ok == true) ? ctrl.text.trim() : null;
    ctrl.dispose();
    return result;
  }

  /// Prompts for a positive Rs/month amount. Returns null if cancelled or invalid.
  Future<double?> _promptAmount(String title, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: 'e.g. 35000',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }

  Future<void> _setGrossPayDirect() async {
    final v = await _promptAmount(
        _user.grossPay > 0 ? 'Change Gross Pay' : 'Set Gross Pay',
        initial: _user.grossPay > 0 ? _user.grossPay.toStringAsFixed(0) : '');
    if (v == null) return;
    setState(() => _saving = true);
    _user.grossPay = v;
    _user.grossPayPending = 0;
    _user.grossPayRequestedAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestGrossPayChange() async {
    final v = await _promptAmount('Request Gross Pay Change',
        initial: _user.grossPay.toStringAsFixed(0));
    if (v == null) return;
    setState(() => _saving = true);
    _user.grossPayPending = v;
    _user.grossPayRequestedAt = DateTime.now().toIso8601String();
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decideGrossPay(bool approve) async {
    setState(() => _saving = true);
    if (approve) _user.grossPay = _user.grossPayPending;
    _user.grossPayPending = 0;
    _user.grossPayRequestedAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _grossPayBlock({required bool isHr, required bool isManagement}) {
    if (_user.grossPay <= 0) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _saving ? null : _setGrossPayDirect,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Set Gross Pay'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.currency_rupee_rounded, size: 15, color: Colors.indigo.shade700),
        const SizedBox(width: 8),
        Text('₹${_user.grossPay.toStringAsFixed(0)}/month',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
      ]),
    );

    if (_user.hasPendingGrossPayChange) {
      final pendingChip = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(Icons.hourglass_top_rounded, size: 15, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Change requested → ₹${_user.grossPayPending.toStringAsFixed(0)}/month (awaiting Management approval)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800)),
          ),
        ]),
      );
      if (isManagement) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          chip,
          const SizedBox(height: 8),
          pendingChip,
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _decideGrossPay(false),
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
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : () => _decideGrossPay(true),
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
          ]),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [chip, const SizedBox(height: 8), pendingChip]);
    }

    // Set, no pending request.
    if (isHr) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _requestGrossPayChange,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Request Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    if (isManagement) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _setGrossPayDirect,
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    return chip;
  }

  static String _fmtMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// Prompts for a positive whole-minute duration. Returns null if cancelled or invalid.
  Future<int?> _promptMinutes(String title, {String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            suffixText: 'min / month',
            hintText: 'e.g. 180 (for 3 hours)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }

  Future<void> _changePermissionQuotaDirect() async {
    final v = await _promptMinutes('Change Permission Quota',
        initial: _user.permissionMinutesQuota.toString());
    if (v == null) return;
    setState(() => _saving = true);
    _user.permissionMinutesQuota = v;
    _user.permissionMinutesQuotaPending = 0;
    _user.permissionMinutesQuotaRequestedAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestPermissionQuotaChange() async {
    final v = await _promptMinutes('Request Permission Quota Change',
        initial: _user.permissionMinutesQuota.toString());
    if (v == null) return;
    setState(() => _saving = true);
    _user.permissionMinutesQuotaPending = v;
    _user.permissionMinutesQuotaRequestedAt = DateTime.now().toIso8601String();
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decidePermissionQuota(bool approve) async {
    setState(() => _saving = true);
    if (approve) _user.permissionMinutesQuota = _user.permissionMinutesQuotaPending;
    _user.permissionMinutesQuotaPending = 0;
    _user.permissionMinutesQuotaRequestedAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _permissionQuotaBlock({required bool isHr, required bool isManagement}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, size: 15, color: Colors.indigo.shade700),
        const SizedBox(width: 8),
        Text('${_fmtMinutes(_user.permissionMinutesQuota)} / month',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
      ]),
    );

    if (_user.hasPendingPermissionQuotaChange) {
      final pendingChip = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(Icons.hourglass_top_rounded, size: 15, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Change requested → ${_fmtMinutes(_user.permissionMinutesQuotaPending)} / month (awaiting Management approval)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800)),
          ),
        ]),
      );
      if (isManagement) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          chip,
          const SizedBox(height: 8),
          pendingChip,
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _decidePermissionQuota(false),
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
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : () => _decidePermissionQuota(true),
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
          ]),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [chip, const SizedBox(height: 8), pendingChip]);
    }

    // Set, no pending request.
    if (isHr) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _requestPermissionQuotaChange,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Request Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    if (isManagement) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _changePermissionQuotaDirect,
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    return chip;
  }

  Future<void> _setBusinessUnit(String unit) async {
    setState(() => _saving = true);
    _user.businessUnit = unit;
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestBusinessUnitChange() async {
    final target = _user.businessUnit == 'FOMRA Developers' ? 'FOMRA Housing' : 'FOMRA Developers';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Request Company Change',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
            'Send a request to Management to change ${_user.name}\'s company from ${_user.businessUnit} to $target?',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    _user.businessUnitPending = target;
    _user.businessUnitRequestedAt = DateTime.now().toIso8601String();
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decideBusinessUnit(bool approve) async {
    setState(() => _saving = true);
    if (approve) _user.businessUnit = _user.businessUnitPending;
    _user.businessUnitPending = '';
    _user.businessUnitRequestedAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _businessUnitBlock({required bool canEdit, required bool isHr, required bool isManagement}) {
    if (_user.businessUnit.isEmpty) {
      if (!canEdit) {
        return Text('Not set',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic));
      }
      return Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _setBusinessUnit('FOMRA Developers'),
            icon: const Icon(Icons.developer_mode_rounded, size: 16),
            label: const Text('FOMRA Developers'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purple.shade700,
              side: BorderSide(color: Colors.purple.shade300),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _setBusinessUnit('FOMRA Housing'),
            icon: const Icon(Icons.apartment_rounded, size: 16),
            label: const Text('FOMRA Housing'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.teal.shade700,
              side: BorderSide(color: Colors.teal.shade300),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]);
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.corporate_fare_rounded, size: 15, color: Colors.purple.shade700),
        const SizedBox(width: 8),
        Text(_user.businessUnit,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.purple.shade700)),
      ]),
    );

    if (_user.hasPendingBusinessUnitChange) {
      final pendingChip = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(Icons.hourglass_top_rounded, size: 15, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Change requested → ${_user.businessUnitPending} (awaiting Management approval)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800)),
          ),
        ]),
      );
      if (isManagement) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          chip,
          const SizedBox(height: 8),
          pendingChip,
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _decideBusinessUnit(false),
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
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : () => _decideBusinessUnit(true),
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
          ]),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [chip, const SizedBox(height: 8), pendingChip]);
    }

    // Set, no pending request.
    if (isHr) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _requestBusinessUnitChange,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Request Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    return chip;
  }

  // ── Weekly Off Day ────────────────────────────────────────────────────
  // Default is Sunday for everyone. Sales works EVERY Sunday, so a Sales
  // employee must be given an explicit weekly off on another day — decided
  // per person by the reporting manager and HR. Land Acquisition does not
  // work Sundays and keeps the default.
  //
  // Previously only Tuesday and Wednesday were offered, so a sales person
  // whose off day was any other weekday could not be configured at all —
  // weeklyOffWeekdayFor() has always supported all seven. HR sets the first
  // value directly; any change after that needs Management approval, same
  // pattern as Work Location.
  static const _weeklyOffChoices = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  ];

  Future<String?> _pickWeeklyOffDay(String current) {
    String selected = current;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Weekly Off Day',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final d in _weeklyOffChoices)
                RadioListTile<String>(
                  value: d,
                  groupValue: selected,
                  dense: true,
                  title: Text(d),
                  onChanged: (v) => setS(() => selected = v!),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setWeeklyOffDirect(String day) async {
    setState(() => _saving = true);
    _user.weeklyOffDay = day == 'Sunday' ? '' : day;
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestWeeklyOffChange() async {
    final current = _user.effectiveWeeklyOffDay;
    final picked = await _pickWeeklyOffDay(current);
    if (picked == null || picked == current) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Request Weekly Off Change',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
            'Send a request to Management to change ${_user.name}\'s weekly off from $current to $picked?',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    _user.weeklyOffDayPending = picked;
    _user.weeklyOffDayRequestedAt = DateTime.now().toIso8601String();
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decideWeeklyOff(bool approve) async {
    setState(() => _saving = true);
    if (approve) {
      _user.weeklyOffDay = _user.weeklyOffDayPending == 'Sunday' ? '' : _user.weeklyOffDayPending;
    }
    _user.weeklyOffDayPending = '';
    _user.weeklyOffDayRequestedAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Management resolves pending requests via Approve/Deny above; this is
  // for changing the value directly with no approval step, since Management
  // is the approver already.
  Future<void> _changeWeeklyOffDirect() async {
    final current = _user.effectiveWeeklyOffDay;
    final picked = await _pickWeeklyOffDay(current);
    if (picked == null || picked == current) return;
    setState(() => _saving = true);
    _user.weeklyOffDay = picked == 'Sunday' ? '' : picked;
    _user.weeklyOffDayPending = '';
    _user.weeklyOffDayRequestedAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _weeklyOffBlock({required bool canEdit, required bool isHr, required bool isManagement}) {
    if (_user.weeklyOffDay.isEmpty) {
      final salesNeedsOff = _user.department == 'Sales';
      if (!canEdit) {
        return Text(
          salesNeedsOff
              ? 'Not set — Sales works Sundays, so a weekly off day is required'
              : 'Sunday (default)',
          style: TextStyle(
              fontSize: 12,
              color: salesNeedsOff ? Colors.red.shade600 : Colors.grey.shade500,
              fontStyle: FontStyle.italic),
        );
      }
      // Was two hardcoded buttons (Tuesday / Wednesday), leaving every other
      // weekday unreachable — even though weeklyOffWeekdayFor() supports all
      // seven and the off day is decided per sales person by their reporting
      // manager and HR.
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (salesNeedsOff)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Sales works every Sunday. Set this employee\'s weekly off day.',
              style: TextStyle(fontSize: 11.5, color: Colors.red.shade600),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () async {
                  final picked = await _pickWeeklyOffDay(_user.weeklyOffDay);
                  if (picked != null) await _setWeeklyOffDirect(picked);
                },
          icon: const Icon(Icons.event_busy_rounded, size: 16),
          label: Text(salesNeedsOff ? 'Set weekly off day' : 'Change weekly off day'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.amber.shade800,
            side: BorderSide(color: Colors.amber.shade300),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.event_busy_rounded, size: 15, color: Colors.amber.shade800),
        const SizedBox(width: 8),
        Text(_user.weeklyOffDay,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade800)),
      ]),
    );

    if (_user.hasPendingWeeklyOffChange) {
      final pendingChip = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(Icons.hourglass_top_rounded, size: 15, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Change requested → ${_user.weeklyOffDayPending} (awaiting Management approval)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800)),
          ),
        ]),
      );
      if (isManagement) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          chip,
          const SizedBox(height: 8),
          pendingChip,
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _decideWeeklyOff(false),
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
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : () => _decideWeeklyOff(true),
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
          ]),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [chip, const SizedBox(height: 8), pendingChip]);
    }

    // Set, no pending request.
    if (isHr) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _requestWeeklyOffChange,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Request Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    if (isManagement) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _changeWeeklyOffDirect,
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    return chip;
  }

  Future<void> _decideHr(bool accept, {String comment = ''}) async {
    setState(() => _saving = true);
    _user.onrollHrStatus = accept ? 'accepted' : 'denied';
    _user.onrollHrComment = comment;
    _user.onrollHrDecidedAt = DateTime.now().toIso8601String();
    try {
      await widget.onSave(_user);
      NotificationService.onrollStageDecided(
        employeeEmail: _user.email, stage: 'HR', accepted: accept,
      );
      if (accept && _user.onrollAwaitingManagement) {
        NotificationService.onrollReachedManagement(employeeName: _user.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) { setState(() => _saving = false); _startTimers(); }
    }
  }

  Future<void> _decideManager(bool accept, {String comment = ''}) async {
    setState(() => _saving = true);
    _user.onrollManagerStatus = accept ? 'accepted' : 'denied';
    _user.onrollManagerComment = comment;
    _user.onrollManagerDecidedAt = DateTime.now().toIso8601String();
    try {
      await widget.onSave(_user);
      NotificationService.onrollStageDecided(
        employeeEmail: _user.email, stage: 'Manager', accepted: accept,
      );
      if (accept && _user.onrollAwaitingManagement) {
        NotificationService.onrollReachedManagement(employeeName: _user.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) { setState(() => _saving = false); _startTimers(); }
    }
  }

  Future<void> _undoOnrollStage(String stage) async {
    setState(() => _saving = true);
    _onrollTimer?.cancel();
    if (stage == 'hr') {
      _user.onrollHrStatus = 'pending';
      _user.onrollHrComment = '';
      _user.onrollHrDecidedAt = '';
    } else if (stage == 'manager') {
      _user.onrollManagerStatus = 'pending';
      _user.onrollManagerComment = '';
      _user.onrollManagerDecidedAt = '';
    }
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) { setState(() => _saving = false); _startTimers(); }
    }
  }

  Future<void> _undoFinalOnroll() async {
    setState(() => _saving = true);
    _onrollTimer?.cancel();
    _elTimer?.cancel();
    _user.onrollConfirmedAt = '';
    _user.onrollManagementStatus = 'pending';
    _user.onrollManagementComment = '';
    _user.onrollManagementDecidedAt = '';
    _user.elEligibleAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _resubmitDate(String deniedAtIso) {
    try {
      final d = DateTime.parse(deniedAtIso).add(const Duration(days: 7));
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  Widget _onrollStageBlock({
    required String label,
    required String status,
    required String comment,
    required bool canAct,
    required bool canUndo,
    required String countdown,
    required VoidCallback onAccept,
    required VoidCallback onDeny,
    required VoidCallback onUndo,
  }) {
    if (status == 'pending') {
      if (!canAct) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            Icon(Icons.pending_actions_rounded, size: 15, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Awaiting $label review',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800)),
            ),
          ]),
        );
      }
      return Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : onDeny,
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
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _saving ? null : onAccept,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: Text('Accept as $label'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]);
    }

    final accepted = status == 'accepted';
    final color = accepted ? Colors.green : Colors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.shade200),
            ),
            child: Row(children: [
              Icon(accepted ? Icons.verified_rounded : Icons.cancel_rounded,
                  size: 15, color: color.shade700),
              const SizedBox(width: 8),
              Text('$label: ${accepted ? 'Accepted' : 'Denied'}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.shade700)),
            ]),
          ),
        ),
        if (canUndo && canAct) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _saving ? null : onUndo,
            icon: const Icon(Icons.undo_rounded, size: 14),
            label: Text('Undo ($countdown)', style: const TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
          ),
        ],
      ]),
      if (!accepted && comment.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(comment, style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
          ),
        ),
    ]);
  }

  // The "Unrestricted Check-in" attendance policy — no geofence, GPS still
  // recorded. Field employees are pinned to it via a per-employee override so
  // check-in stops requiring them to be within any office/site radius.
  static const String _fieldPolicyId = 'a240ee6b-8b0a-4696-92f0-012a46062a0f';

  static MaterialColor _locationColor(String loc) => switch (loc) {
        'Onsite' => Colors.teal,
        'Field' => Colors.orange,
        _ => Colors.indigo,
      };
  static IconData _locationIcon(String loc) => switch (loc) {
        'Onsite' => Icons.location_on_rounded,
        'Field' => Icons.directions_walk_rounded,
        _ => Icons.apartment_rounded,
      };

  // Keeps the employee's attendance-policy override in sync with their work
  // location: moving TO Field lifts the geofence via the Unrestricted
  // Check-in policy; moving AWAY from Field clears that override so the
  // employee falls back to their department/location default again.
  Future<void> _syncFieldPolicyOverride(String from, String to) async {
    if (to == 'Field' && from != 'Field') {
      await SupabaseService.setEmployeePolicyOverride(_user.employeeId, _fieldPolicyId);
    } else if (from == 'Field' && to != 'Field') {
      await SupabaseService.clearEmployeePolicyOverride(_user.employeeId);
    }
  }

  Future<void> _setWorkLocation(String loc) async {
    setState(() => _saving = true);
    final previous = _user.workLocation;
    _user.workLocation = loc;
    try {
      await widget.onSave(_user);
      await _syncFieldPolicyOverride(previous, loc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static const List<String> _workLocationChoices = ['Office', 'Onsite', 'Field'];

  Future<String?> _pickWorkLocation({required String excluding, required String title}) {
    final choices = _workLocationChoices.where((l) => l != excluding).toList();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, children: choices
            .map((loc) => ListTile(
                  leading: Icon(_locationIcon(loc), color: _locationColor(loc).shade700),
                  title: Text(loc),
                  subtitle: loc == 'Field'
                      ? const Text('No GPS/geofence restriction on check-in', style: TextStyle(fontSize: 11.5))
                      : null,
                  onTap: () => Navigator.pop(ctx, loc),
                ))
            .toList()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _requestWorkLocationChange() async {
    final target = await _pickWorkLocation(
        excluding: _user.workLocation, title: 'Request Work Location Change');
    if (target == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Request Work Location Change',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
            'Send a request to Management to change ${_user.name}\'s work location from ${_user.workLocation} to $target?',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    _user.workLocationPending = target;
    _user.workLocationRequestedAt = DateTime.now().toIso8601String();
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _decideWorkLocation(bool approve) async {
    setState(() => _saving = true);
    final previous = _user.workLocation;
    if (approve) _user.workLocation = _user.workLocationPending;
    _user.workLocationPending = '';
    _user.workLocationRequestedAt = '';
    try {
      await widget.onSave(_user);
      if (approve) await _syncFieldPolicyOverride(previous, _user.workLocation);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeWorkLocationDirect() async {
    final target = await _pickWorkLocation(
        excluding: _user.workLocation, title: 'Change Work Location');
    if (target == null) return;
    setState(() => _saving = true);
    final previous = _user.workLocation;
    _user.workLocation = target;
    _user.workLocationPending = '';
    _user.workLocationRequestedAt = '';
    try {
      await widget.onSave(_user);
      await _syncFieldPolicyOverride(previous, target);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _locationChip(String loc) {
    final c = _locationColor(loc);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.shade200),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_locationIcon(loc), size: 15, color: c.shade700),
        const SizedBox(width: 8),
        Text(loc, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.shade700)),
      ]),
    );
  }

  // ── Login email (Management-approved) ────────────────────────────────────
  // Unlike the other Chain C fields, this one is enforced by the database:
  // trg_protect_login_email raises on any direct write to `email`, so the
  // request/approve RPCs are the only route. See
  // supabase/migrations/20260731000200_email_change_requires_approval.sql.

  Future<void> _requestEmailChange() async {
    final ctrl = TextEditingController(text: _user.email);
    final newEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Login Email'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'This is the address the employee signs in with, and where password '
            'reset links are sent. The change takes effect only once Management '
            'approves it — the current address keeps working until then.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'New login email',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
    if (newEmail == null || newEmail.isEmpty) return;
    if (newEmail.toLowerCase() == _user.email.toLowerCase()) {
      _snack('That is already the login email.', error: true);
      return;
    }
    setState(() => _saving = true);
    final err = await SupabaseService.requestLoginEmailChange(
      _user.email,
      newEmail: newEmail,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      _snack(err, error: true);
      return;
    }
    setState(() {
      _user.emailPending = newEmail.toLowerCase();
      _user.emailRequestedAt = DateTime.now().toIso8601String();
      _saving = false;
    });
    _snack('Request sent to Management for approval.');
  }

  Future<void> _decideEmailChange(bool approve) async {
    setState(() => _saving = true);
    if (approve) {
      final r = await SupabaseService.approveLoginEmailChange(_user.email);
      if (!mounted) return;
      if (r.error != null) {
        setState(() => _saving = false);
        _snack(r.error!, error: true);
        return;
      }
      setState(() {
        _user.email = r.newEmail!;
        _user.companyEmail = r.newEmail!;
        _user.emailPending = '';
        _user.emailRequestedAt = '';
        _saving = false;
      });
      _snack('Login email updated. The employee must use the new address to sign in.');
    } else {
      final err = await SupabaseService.rejectLoginEmailChange(_user.email);
      if (!mounted) return;
      if (err != null) {
        setState(() => _saving = false);
        _snack(err, error: true);
        return;
      }
      setState(() {
        _user.emailPending = '';
        _user.emailRequestedAt = '';
        _saving = false;
      });
      _snack('Request denied. The current login email is unchanged.');
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Widget _loginEmailBlock({required bool isHr, required bool isManagement}) {
    final rows = <Widget>[
      _InfoRow(Icons.email_rounded, 'Login ID', _user.email),
    ];

    if (_user.hasPendingEmailChange) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            Icon(Icons.hourglass_top_rounded, size: 15, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Change requested → ${_user.emailPending} (awaiting Management approval)',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
              ),
            ),
          ]),
        ),
      ));

      if (isManagement) {
        rows.add(Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saving ? null : () => _decideEmailChange(false),
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
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _saving ? null : () => _decideEmailChange(true),
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
        ]));
      }
    } else if (isHr || isManagement) {
      rows.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _saving ? null : _requestEmailChange,
          icon: const Icon(Icons.edit_rounded, size: 15),
          label: Text(isManagement ? 'Change login email' : 'Request login email change',
              style: const TextStyle(fontSize: 12.5)),
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _workLocationBlock({required bool canEdit, required bool isHr, required bool isManagement}) {
    if (_user.workLocation.isEmpty) {
      if (!canEdit) {
        return Text('Not set',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic));
      }
      return Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _setWorkLocation('Office'),
            icon: const Icon(Icons.apartment_rounded, size: 16),
            label: const Text('Office'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.indigo.shade700,
              side: BorderSide(color: Colors.indigo.shade300),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _setWorkLocation('Onsite'),
            icon: const Icon(Icons.location_on_rounded, size: 16),
            label: const Text('Onsite'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.teal.shade700,
              side: BorderSide(color: Colors.teal.shade300),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _setWorkLocation('Field'),
            icon: const Icon(Icons.directions_walk_rounded, size: 16),
            label: const Text('Field'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange.shade700,
              side: BorderSide(color: Colors.orange.shade300),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]);
    }

    final chip = _locationChip(_user.workLocation);

    if (_user.hasPendingWorkLocationChange) {
      final pendingChip = Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(Icons.hourglass_top_rounded, size: 15, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Change requested → ${_user.workLocationPending} (awaiting Management approval)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800)),
          ),
        ]),
      );
      if (isManagement) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          chip,
          const SizedBox(height: 8),
          pendingChip,
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : () => _decideWorkLocation(false),
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
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : () => _decideWorkLocation(true),
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
          ]),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [chip, const SizedBox(height: 8), pendingChip]);
    }

    // Set, no pending request.
    if (isHr) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _requestWorkLocationChange,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Request Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    if (isManagement) {
      return Row(children: [
        Expanded(child: chip),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _saving ? null : _changeWorkLocationDirect,
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]);
    }
    return chip;
  }

  Future<void> _confirmEl() async {
    setState(() => _saving = true);
    _user.elEligibleAt = DateTime.now().toIso8601String();
    try {
      await widget.onSave(_user);
      if (_user.email.isNotEmpty) {
        NotificationService.elMarkedEligible(
          employeeEmail: _user.email,
          employeeRoutePrefix: NotificationService.routePrefixForRole(AppUser.userRoleFor(_user.role)),
        );
      }
      _elTimer?.cancel();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) { setState(() => _saving = false); _startTimers(); }
    }
  }

  Future<void> _undoEl() async {
    setState(() => _saving = true);
    _elTimer?.cancel();
    _user.elEligibleAt = '';
    try {
      await widget.onSave(_user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _roleColor(_user.role);
    final canEdit = UserSession.role == UserRole.hr ||
        UserSession.role == UserRole.management;
    final isHr = UserSession.role == UserRole.hr;
    final isManagement = UserSession.role == UserRole.management;
    // On-roll requests go to HR and the employee's own reporting manager, independently.
    // Management only acts on the separate On-Roll Approvals page once both have accepted.
    // "Reporting manager" here is flag-based, not role-based — any flagged RM
    // (Employee/HR/Management role) named on this record can act as manager stage.
    final isReportingManager = UserSession.isReportingManager &&
        UserSession.name.trim().toLowerCase() == _user.reportingManager.trim().toLowerCase();
    final canActHr = isHr;
    final canActManager = isReportingManager;
    final canSeeOnrollSection = isHr || isManagement || isReportingManager;
    // Employees can only request On-Roll after 6 months; ignore any request
    // recorded before that (e.g. stale data) so probation employees never
    // show Accept/Deny controls.
    final onrollEligibleByTenure = fullMonthsSince(_user.dateOfJoining) >= 6;
    final showOnrollSection = canSeeOnrollSection &&
        (_user.isOnroll || (_user.onrollRequestedAt.isNotEmpty && onrollEligibleByTenure));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: c.withValues(alpha: 0.12),
                child: Text(
                  _user.name.isNotEmpty ? _user.name[0].toUpperCase() : '?',
                  style: TextStyle(color: c, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_user.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                          color: Color(0xFF111827))),
                  if (_user.designation.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(_user.designation,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  ],
                  const SizedBox(height: 5),
                  Row(children: [
                    _RoleChip(_user.role, c),
                    const SizedBox(width: 6),
                    _StatusPill(_user.leaveStatus),
                    if (!_user.active) ...[
                      const SizedBox(width: 6),
                      _Badge('Inactive', Colors.red.shade50,
                          Colors.red.shade200, Colors.red.shade600),
                    ],
                  ]),
                ]),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Color(0xFF6B7280)),
              ),
            ]),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            _InfoRow(Icons.badge_rounded,           'Employee ID',       _user.employeeId),
            _loginEmailBlock(isHr: isHr, isManagement: isManagement),
            _InfoRow(Icons.phone_rounded,           'Mobile',            _user.mobile),
            _InfoRow(Icons.location_on_rounded,     'Address',           _user.address),
            _InfoRow(Icons.cake_rounded,            'Date of Birth',     _fmtDate(_user.dateOfBirth)),
            _InfoRow(Icons.calendar_today_rounded,  'Date of Joining',   _fmtDate(_user.dateOfJoining)),
            _InfoRow(Icons.hourglass_bottom_rounded, 'Time with Company', tenureLabel(_user.dateOfJoining)),
            _InfoRow(Icons.manage_accounts_rounded, 'Reporting Manager', _user.reportingManager),

            // ── Work location ────────────────────────────────────────────
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.location_city_rounded, size: 14, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              const Text('Work Location',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
            ]),
            const SizedBox(height: 10),
            _workLocationBlock(canEdit: canEdit, isHr: isHr, isManagement: isManagement),
            const SizedBox(height: 4),

            // ── Company ───────────────────────────────────────────────────
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.corporate_fare_rounded, size: 14, color: Color(0xFF6B7280)),
              const SizedBox(width: 6),
              const Text('Company',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
            ]),
            const SizedBox(height: 10),
            _businessUnitBlock(canEdit: canEdit, isHr: isHr, isManagement: isManagement),
            const SizedBox(height: 4),

            // ── Weekly Off Day (Sales department only) ─────────────────────
            if (_user.department == 'Sales') ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.event_busy_rounded, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                const Text('Weekly Off Day',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280))),
              ]),
              const SizedBox(height: 10),
              _weeklyOffBlock(canEdit: canEdit, isHr: isHr, isManagement: isManagement),
              const SizedBox(height: 4),
            ],

            // ── Compensation ─────────────────────────────────────────────
            if (canEdit) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.currency_rupee_rounded, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                const Text('Compensation',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280))),
              ]),
              const SizedBox(height: 10),
              _grossPayBlock(isHr: isHr, isManagement: isManagement),
              const SizedBox(height: 4),
            ],

            // ── Permission Quota ────────────────────────────────────────────
            if (canEdit) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                const Text('Permission Quota',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280))),
              ]),
              const SizedBox(height: 10),
              _permissionQuotaBlock(isHr: isHr, isManagement: isManagement),
              const SizedBox(height: 4),
            ],

            // ── Employment status management ──────────────────────────────
            if (showOnrollSection) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.work_history_rounded, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                const Text('Employment Status',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280))),
              ]),
              const SizedBox(height: 10),

              // On-Roll — 3-stage review: HR + Reporting Manager independently, then Management.
              // Once already confirmed on-roll, the individual stage cards are no longer
              // relevant (they may still read 'pending' for employees confirmed before the
              // review flow existed) — just show the confirmed banner below.
              if (!_user.isOnroll) ...[
                _onrollStageBlock(
                  label: 'HR',
                  status: _user.onrollHrStatus,
                  comment: _user.onrollHrComment,
                  canAct: canActHr,
                  canUndo: _canUndoHr,
                  countdown: _countdown(_user.onrollHrDecidedAt),
                  onAccept: () => _decideHr(true),
                  onDeny: () async {
                    final c = await _promptDenyComment('Deny HR On-Roll Request');
                    if (c != null) await _decideHr(false, comment: c);
                  },
                  onUndo: () => _undoOnrollStage('hr'),
                ),
                const SizedBox(height: 8),
                _onrollStageBlock(
                  label: 'Reporting Manager',
                  status: _user.onrollManagerStatus,
                  comment: _user.onrollManagerComment,
                  canAct: canActManager,
                  canUndo: _canUndoManager,
                  countdown: _countdown(_user.onrollManagerDecidedAt),
                  onAccept: () => _decideManager(true),
                  onDeny: () async {
                    final c = await _promptDenyComment('Deny Manager On-Roll Request');
                    if (c != null) await _decideManager(false, comment: c);
                  },
                  onUndo: () => _undoOnrollStage('manager'),
                ),
                const SizedBox(height: 8),
              ],

              // Management stage — read-only here; actioned from the On-Roll Approvals page.
              if (_user.isOnroll)
                Row(children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(children: [
                        Icon(Icons.verified_rounded, size: 15, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Text('On-Roll confirmed (unlocks ML + CL)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: Colors.green.shade700)),
                      ]),
                    ),
                  ),
                  if (_canUndoConfirmed && canEdit) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _saving ? null : _undoFinalOnroll,
                      icon: const Icon(Icons.undo_rounded, size: 14),
                      label: Text('Undo (${_countdown(_user.onrollConfirmedAt)})',
                          style: const TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                    ),
                  ],
                ])
              else if (_user.onrollManagementDenied)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.cancel_rounded, size: 15, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _user.onrollManagementComment.isNotEmpty
                            ? 'Denied by Management: "${_user.onrollManagementComment}"'
                            : 'Denied by Management',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: Colors.red.shade700),
                      ),
                    ),
                  ]),
                )
              else if (_user.onrollAwaitingManagement)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.hourglass_top_rounded, size: 15, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Awaiting Management review',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700)),
                    ),
                  ]),
                ),

              if (_user.onrollDenied && !_user.onrollCanResubmit)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Employee can resubmit on ${_resubmitDate(_user.onrollDeniedAt)}.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                  ),
                ),

              // EL Eligibility (HR/Management only, once on-roll)
              if (_user.isOnroll && canEdit) ...[
                const SizedBox(height: 8),
                if (!_user.isElEligible)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _confirmEl,
                      icon: const Icon(Icons.event_available_rounded, size: 16),
                      label: const Text('Confirm EL Eligibility (1 year on-roll)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purple.shade700,
                        side: BorderSide(color: Colors.purple.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  )
                else
                  Row(children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple.shade200),
                        ),
                        child: Row(children: [
                          Icon(Icons.event_available_rounded, size: 15, color: Colors.purple.shade700),
                          const SizedBox(width: 8),
                          Text('EL eligible',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                  color: Colors.purple.shade700)),
                        ]),
                      ),
                    ),
                    if (_canUndoEl) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _saving ? null : _undoEl,
                        icon: const Icon(Icons.undo_rounded, size: 14),
                        label: Text('Undo (${_countdown(_user.elEligibleAt)})',
                            style: const TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade400),
                      ),
                    ],
                  ]),
              ],
              const SizedBox(height: 4),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => FullProfileDialog(user: _user),
                ),
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('Interview & Onboarding Records'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accentBlue,
                  side: BorderSide(color: AppTheme.accentBlue),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (canEdit) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () async {
                    final wasActive = _user.active;
                    setState(() => _saving = true);
                    _user.active = !wasActive;
                    try {
                      await widget.onSave(_user);
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      _user.active = wasActive;
                      if (mounted) {
                        setState(() => _saving = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Failed to save: $e'),
                          backgroundColor: Colors.red.shade700,
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    }
                  },
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(_user.active ? Icons.person_off_rounded : Icons.person_rounded, size: 16),
                  label: Text(_user.active ? 'Deactivate Account' : 'Activate Account'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _user.active ? Colors.red : Colors.green,
                    side: BorderSide(color: _user.active ? Colors.red : Colors.green),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (_) => EmployeeEditDialog(
                        user: _user,
                        allUsers: widget.allUsers,
                        managerCandidates: widget.managerCandidates,
                        onSave: widget.onSave,
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              // Staff Portal users (Housekeeping/Support Staff) are HR-owned
              // end to end — HR can delete them here with no Management
              // approval, unlike the rest of the workforce.
              if (widget.onDelete != null && kStaffPortalDepartments.contains(_user.department)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_rounded, size: 16),
                    label: const Text('Delete Staff Portal User'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                      side: const BorderSide(color: Color(0xFFB91C1C)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete User',
            style: TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            children: [
              const TextSpan(text: 'Are you sure you want to permanently delete '),
              TextSpan(text: _user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: '? This action cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C), foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    await widget.onDelete?.call(_user);
    if (context.mounted) Navigator.pop(context);
  }
}

// ── Full profile: interview + onboarding data ─────────────────────────────────

/// Read-only profile: personal details, onboarding submission and interview
/// record. Made public so a name in a metric breakdown can open it — that is
/// what "click the name and see the profile" means, and this already existed.
class FullProfileDialog extends StatefulWidget {
  final AppUser user;
  const FullProfileDialog({super.key, required this.user});
  @override
  State<FullProfileDialog> createState() => _FullProfileDialogState();
}

/// Opens the read-only profile for [user].
Future<void> showEmployeeProfile(BuildContext context, AppUser user) =>
    showDialog<void>(context: context, builder: (_) => FullProfileDialog(user: user));

class _FullProfileDialogState extends State<FullProfileDialog>
    with SingleTickerProviderStateMixin {
  static Color get _c => AppTheme.primaryBlue;
  late final TabController _tabs;
  Map<String, dynamic>? _onboarding;
  Map<String, dynamic>? _interview;
  bool _loading = true;

  // This cycle's attendance picture. The dialog opened straight onto the
  // onboarding form and the interview record — useful when hiring, useless
  // when you have just clicked a name in "Absent Today" and want to know how
  // this person is actually doing.
  int _presentDays = 0;
  int _lateDays = 0;
  int _leavesTaken = 0;
  int _permissionMinutes = 0;
  int _permissionQuota = 120;
  String _cycleLabel = '';

  @override
  void initState() {
    super.initState();
    // Summary first: it is what someone arriving from a metric wants.
    _tabs = TabController(length: 3, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// At-a-glance figures for the current attendance cycle.
  ///
  /// Someone arriving here from "Absent Today" or "Late Arrivals" wants to
  /// know how this person is doing, not to read their onboarding form. The
  /// onboarding and interview tabs remain for the hiring case.
  Widget _summaryTab() {
    final exempt = widget.user.exemptFromAttendance;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.date_range_rounded, size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text('Cycle $_cycleLabel',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        ]),
        const SizedBox(height: 4),
        Text('The attendance cycle runs 26th to 25th, not the calendar month.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 16),

        if (exempt)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${widget.user.name} is not tracked for attendance — no check-in, '
              'no timings and no leave cycle apply.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          )
        else ...[
          Wrap(spacing: 10, runSpacing: 10, children: [
            _summaryTile('Days Present', '$_presentDays', Icons.check_circle_rounded,
                AppTheme.success),
            _summaryTile('Late Arrivals', '$_lateDays',
                Icons.running_with_errors_rounded,
                _lateDays == 0 ? AppTheme.success : AppTheme.warning),
            _summaryTile('Leaves Taken', '$_leavesTaken', Icons.event_busy_rounded,
                AppTheme.accentBlue),
            _summaryTile(
                'Permission',
                '$_permissionMinutes / $_permissionQuota min',
                Icons.timer_rounded,
                _permissionMinutes >= _permissionQuota
                    ? AppTheme.error
                    : AppTheme.primaryBlue),
          ]),
          const SizedBox(height: 14),
          if (_lateDays == 0 && _presentDays > 0)
            Text('No late arrivals this cycle.',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600)),
          if (_permissionMinutes >= _permissionQuota)
            Text('Permission allowance for this cycle is fully used.',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.error, fontWeight: FontWeight.w600)),
        ],

        const SizedBox(height: 20),
        Text('Employment',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        _InfoRow(Icons.badge_rounded, 'Employee ID', widget.user.employeeId),
        _InfoRow(Icons.work_rounded, 'Designation', widget.user.designation),
        _InfoRow(Icons.account_tree_rounded, 'Department',
            widget.user.department.isEmpty ? '—' : widget.user.department),
        _InfoRow(Icons.manage_accounts_rounded, 'Reports To',
            widget.user.reportingManager.isEmpty ? '—' : widget.user.reportingManager),
        _InfoRow(Icons.calendar_today_rounded, 'Date of Joining',
            widget.user.dateOfJoining.isEmpty ? '—' : widget.user.dateOfJoining),
        _InfoRow(Icons.verified_user_rounded, 'Status', widget.user.leaveStatus),
      ]),
    );
  }

  Widget _summaryTile(String label, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  Future<void> _fetchData() async {
    final db = Supabase.instance.client;
    final name = widget.user.name;
    final email = widget.user.email;
    try {
      final ob = await db.from('onboarding_forms').select().or('name.ilike.%$name%,phone_number.eq.$email').limit(1);
      final ca = await db.from('candidate_applications').select().or('name.ilike.%$name%,email.eq.$email').limit(1);

      // This attendance cycle (26th -> 25th), not the calendar month.
      final now = DateTime.now();
      final cycleStart = attendanceCycleStart(now);
      final cycleEnd = attendanceCycleEnd(now);
      _cycleLabel = attendanceCycleRange(now);

      // date_iso is the generated DATE column; the text `date` sorts
      // lexically and cannot be range-queried.
      final att = await db
          .from('attendance_records')
          .select()
          .eq('employee_id', widget.user.employeeId)
          .gte('date_iso', cycleStart.toIso8601String().substring(0, 10))
          .lte('date_iso', cycleEnd.toIso8601String().substring(0, 10));

      final leaves = await db
          .from('leave_applications')
          .select()
          .eq('employee_name', name)
          .gte('from_date', cycleStart.toIso8601String().substring(0, 10))
          .lte('from_date', cycleEnd.toIso8601String().substring(0, 10));

      final schedule = OfficeTimingStore.scheduleFor(
        exemptFromTiming: widget.user.exemptFromTiming || widget.user.isManagement,
        department: widget.user.department,
      );

      _presentDays = (att as List)
          .where((r) => ((r['check_in_time'] as String?) ?? '').isNotEmpty)
          .length;

      _lateDays = (att)
          .where((r) => isLateCheckIn((r['check_in_time'] as String?) ?? '', schedule))
          .length;

      final leaveRows = (leaves as List);
      _leavesTaken = leaveRows
          .where((a) =>
              (a['leave_type'] as String?) != 'Permission' &&
              (a['manager_status'] as String?) == 'approved')
          .fold<int>(0, (sum, a) => sum + (((a['days'] as num?) ?? 1).toInt()));

      _permissionMinutes = leaveRows
          .where((a) =>
              (a['leave_type'] as String?) == 'Permission' &&
              (a['manager_status'] as String?) != 'denied')
          .fold<int>(0, (sum, a) => sum + (((a['permission_minutes'] as num?) ?? 0).toInt()));

      _permissionQuota = widget.user.permissionMinutesQuota;
      setState(() {
        if ((ob as List).isNotEmpty) {
          final row = Map<String, dynamic>.from(ob.first as Map);
          final fd  = row['form_data'];
          if (fd is Map) row.addAll(Map<String, dynamic>.from(fd));
          _onboarding = row;
        } else {
          _onboarding = null;
        }
        _interview  = (ca as List).isNotEmpty ? ca.first : null;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Widget _row(String label, dynamic value) {
    final v = (value?.toString() ?? '').trim();
    if (v.isEmpty || v == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 170,
            child: Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 12, color: Color(0xFF111827)))),
      ]),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    final nonEmpty = rows.whereType<Padding>().toList();
    if (nonEmpty.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 14),
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _c)),
      const Divider(height: 8),
      ...rows,
    ]);
  }

  // Approval-workflow status isn't part of the candidate's own submitted
  // data, so it's shown separately above the full application below.
  Widget _reviewStatusView(Map<String, dynamic> d) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section('HR Review', [
        _row('HR Status', d['hr_status']), _row('HR Comment', d['hr_comment']),
        _row('Manager Status', d['manager_status']), _row('Manager Comment', d['manager_comment']),
        _row('Management Status', d['management_status']),
      ]),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _c,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.user.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text(widget.user.designation,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          TabBar(
            controller: _tabs,
            indicatorColor: _c,
            labelColor: _c,
            unselectedLabelColor: Colors.grey,
            tabs: const [
              Tab(icon: Icon(Icons.insights_rounded, size: 18), text: 'Summary'),
              Tab(icon: Icon(Icons.assignment_ind_rounded, size: 18), text: 'Onboarding'),
              Tab(icon: Icon(Icons.work_history_rounded, size: 18), text: 'Interview'),
            ],
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: _c))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _summaryTab(),
                      _onboarding != null
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: OnboardingFormReadOnlyBody(data: _onboarding!))
                          : const Center(child: Text('No onboarding form found for this employee.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey))),
                      _interview != null
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _reviewStatusView(_interview!),
                                CandidateDetailBody(data: _interview!),
                              ]))
                          : const Center(child: Text('No interview application found for this employee.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey))),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}

// ── Edit / Create dialog ──────────────────────────────────────────────────────

class EmployeeEditDialog extends StatefulWidget {
  final AppUser? user; // null = creating new
  final List<AppUser> allUsers;
  // See EmployeeProfileDialog.managerCandidates.
  final List<AppUser>? managerCandidates;
  final Future<void> Function(AppUser) onSave;
  const EmployeeEditDialog(
      {required this.user, required this.allUsers, this.managerCandidates,
       required this.onSave});

  @override
  State<EmployeeEditDialog> createState() => EmployeeEditDialogState();
}

class EmployeeEditDialogState extends State<EmployeeEditDialog> {
  static Color get _color => AppTheme.primaryBlue;
  static const _domain = '@fomrahousing.in';

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _empIdCtrl;
  late String? _designation;
  late String? _department;
  late String? _businessUnit;
  static const _businessUnits = ['FOMRA Developers', 'FOMRA Housing'];
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _companyEmailCtrl;
  late final TextEditingController _dobCtrl;
  late final TextEditingController _joiningCtrl;
  late final TextEditingController _leaveCtrl;
  late final TextEditingController _grossPayCtrl;
  late String _role;
  late String _manager;
  late bool _active;
  late bool _isRmFlag;
  bool _saving = false;

  static String _prefix(String email) => email.endsWith(_domain)
      ? email.substring(0, email.length - _domain.length)
      : email;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _nameCtrl    = TextEditingController(text: u?.name ?? '');
    _emailCtrl   = TextEditingController(text: u != null ? _prefix(u.email) : '');
    _empIdCtrl   = TextEditingController(text: u?.employeeId ?? '');
    _designation = (u?.designation.isNotEmpty ?? false) ? u!.designation : null;
    _department  = (u?.department.isNotEmpty ?? false) ? u!.department : null;
    _businessUnit = (u?.businessUnit.isNotEmpty ?? false) ? u!.businessUnit : null;
    _mobileCtrl  = TextEditingController(text: u?.mobile ?? '');
    _addressCtrl = TextEditingController(text: u?.address ?? '');
    _companyEmailCtrl = TextEditingController(text: u?.companyEmail ?? '');
    _dobCtrl     = TextEditingController(text: _fmtDate(u?.dateOfBirth ?? ''));
    _joiningCtrl = TextEditingController(text: _fmtDate(u?.dateOfJoining ?? ''));
    _leaveCtrl   = TextEditingController(
        text: (u?.leaveAllocation ?? 21).toString());
    _grossPayCtrl = TextEditingController(
        text: u != null && u.grossPay > 0 ? u.grossPay.toStringAsFixed(0) : '');
    _role    = u?.role ?? 'Employee';
    _manager = u?.reportingManager ?? '';
    _active  = u?.active ?? true;
    _isRmFlag = u?.isReportingManager ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _emailCtrl, _empIdCtrl,
      _mobileCtrl, _addressCtrl, _companyEmailCtrl, _dobCtrl, _joiningCtrl, _leaveCtrl, _grossPayCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isNew => widget.user == null;

  Future<void> _save() async {
    final name   = _nameCtrl.text.trim();
    final prefix = _emailCtrl.text.trim();
    if (name.isEmpty || prefix.isEmpty) return;

    // HR's quick "Add Employee" only creates Staff Portal (Housekeeping /
    // Support Staff) accounts now — everyone else goes through the
    // Interview & Onboarding pipeline instead. Role is forced to Employee
    // for these (see the hidden Role dropdown below).
    if (_isNew && !kStaffPortalDepartments.contains(_department)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please select Housekeeping or Support Staff as the department.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    setState(() => _saving = true);

    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final joiningVal = _joiningCtrl.text.trim();
    final existingJoining = _fmtDate(widget.user?.dateOfJoining ?? '');

    // Reporting manager: a brand-new employee, or a first-time assignment
    // (currently empty), saves directly. Changing an already-set value
    // requires Management approval — same convention as grossPay/workLocation.
    final roleHasMgr = ['Employee', 'Manager', 'HR'].contains(_role);
    final requestedMgr = roleHasMgr ? _manager : '';
    final prevMgr = widget.user?.reportingManager ?? '';
    final mgrIsChange = roleHasMgr && widget.user != null &&
        prevMgr.isNotEmpty && requestedMgr != prevMgr;
    final finalMgr = mgrIsChange ? prevMgr : requestedMgr;
    final mgrPending = mgrIsChange
        ? requestedMgr
        : (roleHasMgr ? (widget.user?.reportingManagerPending ?? '') : '');
    final mgrPendingAt = mgrIsChange
        ? now.toIso8601String()
        : (roleHasMgr ? (widget.user?.reportingManagerRequestedAt ?? '') : '');

    // "Is Reporting Manager" flag: always requires Management approval to
    // change (never saved directly), regardless of current value.
    final prevFlag = widget.user?.isReportingManager ?? false;
    final flagIsChange = widget.user != null && _isRmFlag != prevFlag;
    final finalFlag = flagIsChange ? prevFlag : _isRmFlag;
    final flagPending = flagIsChange
        ? _isRmFlag
        : (widget.user?.isReportingManagerPending ?? false);
    final flagPendingAt = flagIsChange
        ? now.toIso8601String()
        : (widget.user?.isReportingManagerRequestedAt ?? '');

    final updated = AppUser(
      name:             name,
      email:            '$prefix$_domain',
      employeeId:       _empIdCtrl.text.trim(),
      designation:      _designation ?? '',
      department:       _department ?? '',
      businessUnit:     _businessUnit ?? '',
      role:             _role,
      active:           _active,
      hasPassword:      widget.user?.hasPassword ?? false,
      leaveAllocation:  int.tryParse(_leaveCtrl.text.trim()) ??
                        (widget.user?.leaveAllocation ?? 21),
      reportingManager: finalMgr,
      reportingManagerPending:      mgrPending,
      reportingManagerRequestedAt:  mgrPendingAt,
      isReportingManager:           finalFlag,
      isReportingManagerPending:    flagPending,
      isReportingManagerRequestedAt: flagPendingAt,
      mobile:           _mobileCtrl.text.trim(),
      address:          _addressCtrl.text.trim(),
      companyEmail:     _companyEmailCtrl.text.trim(),
      dateOfBirth:      _dobCtrl.text.trim(),
      dateOfJoining:    joiningVal.isNotEmpty
                            ? joiningVal
                            : (existingJoining.isNotEmpty
                                ? existingJoining
                                : today),
      onrollConfirmedAt:  widget.user?.onrollConfirmedAt ?? '',
      onrollRequestedAt:  widget.user?.onrollRequestedAt ?? '',
      onrollHrStatus:            widget.user?.onrollHrStatus ?? 'pending',
      onrollHrComment:           widget.user?.onrollHrComment ?? '',
      onrollHrDecidedAt:         widget.user?.onrollHrDecidedAt ?? '',
      onrollManagerStatus:       widget.user?.onrollManagerStatus ?? 'pending',
      onrollManagerComment:      widget.user?.onrollManagerComment ?? '',
      onrollManagerDecidedAt:    widget.user?.onrollManagerDecidedAt ?? '',
      onrollManagementStatus:    widget.user?.onrollManagementStatus ?? 'pending',
      onrollManagementComment:   widget.user?.onrollManagementComment ?? '',
      onrollManagementDecidedAt: widget.user?.onrollManagementDecidedAt ?? '',
      elEligibleAt:       widget.user?.elEligibleAt ?? '',
      elAvailRequestedAt: widget.user?.elAvailRequestedAt ?? '',
      elLastAvailedAt:    widget.user?.elLastAvailedAt ?? '',
      // Gross pay is only entered directly here on first set (field hidden once set);
      // subsequent changes go through the Compensation approval flow on the profile page.
      grossPay:         double.tryParse(_grossPayCtrl.text.trim()) ??
                        (widget.user?.grossPay ?? 0),
      grossPayPending:     widget.user?.grossPayPending ?? 0,
      grossPayRequestedAt: widget.user?.grossPayRequestedAt ?? '',
      workLocation:            widget.user?.workLocation ?? '',
      workLocationPending:     widget.user?.workLocationPending ?? '',
      workLocationRequestedAt: widget.user?.workLocationRequestedAt ?? '',
      permissionMinutesQuota:            widget.user?.permissionMinutesQuota ?? 120,
      permissionMinutesQuotaPending:     widget.user?.permissionMinutesQuotaPending ?? 0,
      permissionMinutesQuotaRequestedAt: widget.user?.permissionMinutesQuotaRequestedAt ?? '',
      businessUnitPending:     widget.user?.businessUnitPending ?? '',
      businessUnitRequestedAt: widget.user?.businessUnitRequestedAt ?? '',
    );

    await widget.onSave(updated);
    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.user == null
              ? '${updated.name} added successfully'
              : 'Profile updated'),
          backgroundColor: _color,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  List<String> get _managerNames =>
      visibleManagersForPicker(widget.managerCandidates ?? widget.allUsers)
          .map((u) => u.name)
          .toList();

  Widget _field(TextEditingController ctrl, String label, IconData icon, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffix,
    Color? fillColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        readOnly: readOnly,
        onTap: onTap,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: _color, size: 20),
          suffixIcon: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _color, width: 2),
          ),
          filled: true,
          fillColor: fillColor ?? Colors.white,
          labelStyle: const TextStyle(color: Color(0xFF6B7280)),
        ),
      ),
    );
  }

  InputDecoration _dropDeco(BuildContext context, String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: _color, size: 20),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: _color, width: 2),
    ),
    filled: true,
    fillColor: Theme.of(context).colorScheme.surface,
    labelStyle: const TextStyle(color: Color(0xFF6B7280)),
  );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.user == null;
    final mgrs  = _managerNames;

    return AlertDialog(
      title: Text(
        isNew ? 'Add Employee' : 'Edit Profile',
        style:
            TextStyle(color: _color, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(_nameCtrl, 'Full Name', Icons.person_rounded),

            // Email with @fomrahousing.in suffix
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                readOnly: !isNew,
                decoration: InputDecoration(
                  labelText: isNew ? 'Username' : 'Login ID',
                  prefixIcon: Icon(Icons.email_rounded,
                      color: _color, size: 20),
                  suffix: Text('@fomrahousing.in',
                      style: TextStyle(
                          color: _color,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: _color, width: 2),
                  ),
                  filled: true,
                  fillColor:
                      isNew ? Colors.white : const Color(0xFFF8FAFC),
                  labelStyle:
                      const TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
            ),

            if (isNew) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add Employee only creates Housekeeping / Support Staff accounts. '
                      'Other new hires go through Interview & Onboarding.',
                      style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900),
                    ),
                  ),
                ]),
              ),
            ],
            // Employee ID is generated, not typed. It was previously a plain
            // free-text box with no uniqueness check on either side, which is
            // how two employees ended up sharing FHIPL-08. The database now
            // enforces uniqueness and fills a blank ID in automatically
            // (assign_employee_id / next_employee_id).
            if (isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextField(
                  controller: _empIdCtrl,
                  decoration: InputDecoration(
                    labelText: 'Employee ID',
                    prefixIcon: const Icon(Icons.badge_rounded),
                    border: const OutlineInputBorder(),
                    helperText: _empIdCtrl.text.trim().isEmpty
                        ? 'Leave blank to assign the next ID automatically'
                        : 'Must be unique',
                    suffixIcon: IconButton(
                      tooltip: 'Suggest next available ID',
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      onPressed: () async {
                        final next = await SupabaseService.nextEmployeeId(
                          businessUnit: _businessUnit ?? '',
                        );
                        if (next != null && mounted) {
                          setState(() => _empIdCtrl.text = next);
                        }
                      },
                    ),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                ),
              )
            else
              _field(_empIdCtrl, 'Employee ID', Icons.badge_rounded),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: DropdownButtonFormField<String>(
                value: _department != null &&
                        (isNew ? kStaffPortalDepartments : kDepartments).contains(_department)
                    ? _department
                    : null,
                decoration: _dropDeco(context, 'Department', Icons.account_tree_rounded),
                hint: _department != null ? Text(_department!) : null,
                items: (isNew ? kStaffPortalDepartments : kDepartments)
                    .map((dep) => DropdownMenuItem(value: dep, child: Text(dep)))
                    .toList(),
                onChanged: (v) => setState(() => _department = v),
              ),
            ),
            // Only offered here for the initial entry; once set, further
            // changes must go through the Request Change flow on the
            // profile page (Management approval), same as Work Location.
            if ((widget.user?.businessUnit ?? '').isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  value: _businessUnit != null && _businessUnits.contains(_businessUnit) ? _businessUnit : null,
                  hint: const Text('Select company'),
                  decoration: _dropDeco(context, 'Company', Icons.corporate_fare_rounded),
                  items: _businessUnits.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                  onChanged: (v) => setState(() => _businessUnit = v),
                ),
              ),
            if (!isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  value: _designation != null && kDesignations.contains(_designation) ? _designation : null,
                  decoration: _dropDeco(context, 'Designation', Icons.work_rounded),
                  hint: _designation != null ? Text(_designation!) : null,
                  items: kDesignations.map((des) =>
                      DropdownMenuItem(value: des, child: Text(des))).toList(),
                  onChanged: (v) => setState(() => _designation = v),
                ),
              ),
            _field(_mobileCtrl,  'Mobile',                    Icons.phone_rounded,
                keyboard: TextInputType.phone),
            _field(_addressCtrl, 'Address',                   Icons.location_on_rounded,
                maxLines: 2),
            // The Company Mail free-text field was removed here. It wrote
            // company_email directly, and company_email is now kept in step
            // with the login email by approve_login_email_change(). Editing
            // the address goes through Request → Management approval on the
            // employee's detail view instead.

            // Date of birth — usually carried over from the onboarding form,
            // but HR can set/correct it here too.
            _field(
              _dobCtrl, 'Date of Birth',
              Icons.cake_rounded,
              readOnly: true,
              suffix: const Icon(Icons.arrow_drop_down_rounded,
                  color: Color(0xFF6B7280)),
              onTap: () async {
                final today = DateTime.now();
                DateTime initial = DateTime(today.year - 25, today.month, today.day);
                if (_dobCtrl.text.isNotEmpty) {
                  final p = _dobCtrl.text.split('/');
                  if (p.length == 3) {
                    try {
                      initial = DateTime(
                          int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
                    } catch (_) {}
                  }
                }
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(1950),
                  lastDate: today,
                );
                if (picked != null) {
                  _dobCtrl.text =
                      '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                }
              },
            ),

            // Date of joining
            _field(
              _joiningCtrl, 'Date of Joining',
              Icons.calendar_today_rounded,
              readOnly: true,
              suffix: const Icon(Icons.arrow_drop_down_rounded,
                  color: Color(0xFF6B7280)),
              onTap: () async {
                DateTime initial = DateTime.now();
                if (_joiningCtrl.text.isNotEmpty) {
                  final p = _joiningCtrl.text.split('/');
                  if (p.length == 3) {
                    try {
                      initial = DateTime(
                          int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
                    } catch (_) {}
                  }
                }
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  _joiningCtrl.text =
                      '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                }
              },
            ),

            // Housekeeping/Support Staff don't have a CL/ML/EL-style annual
            // allocation — they get a fixed 1-holiday-per-month allowance
            // that doesn't carry over, shown read-only in the Staff Portal
            // instead of set here.
            // Leave Allocation removed. It was a single annual number (21 for
            // most people, 12 for one) and the HR policy has no such concept:
            // entitlement is 1 CL + 1 ML credited per month, EL accruing at
            // 1/month after confirmation, and probation is a flat 1 day per
            // month. HR was being asked for a figure that governed nothing.
            //
            // The column stays for now so nothing that reads it breaks; it is
            // simply no longer presented as something to set.

            // Only offered here for the initial entry; once set, further changes
            // must go through the Compensation approval flow on the profile page.
            if ((widget.user?.grossPay ?? 0) <= 0)
              _field(_grossPayCtrl, 'Gross Pay (Rs / month)',
                  Icons.account_balance_wallet_rounded,
                  keyboard: TextInputType.number),

            // Role dropdown — hidden when adding a new employee: Staff
            // Portal accounts created here are always role 'Employee'
            // (already the default). Still editable for existing records.
            if (!isNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  value: _role,
                  decoration: _dropDeco(context, 'Role', Icons.shield_rounded),
                  items: ['Employee', 'Manager', 'HR', 'Management']
                      .map((r) =>
                          DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),
              ),

            // Reporting manager (Employee / Manager / HR roles)
            if (['Employee', 'Manager', 'HR'].contains(_role) &&
                mgrs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: DropdownButtonFormField<String>(
                  value: mgrs.contains(_manager) ? _manager : null,
                  decoration: _dropDeco(
                      context, 'Reporting Manager',
                      Icons.manage_accounts_rounded),
                  hint: const Text('None assigned'),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('None')),
                    ...mgrs.map((m) =>
                        DropdownMenuItem(value: m, child: Text(m))),
                  ],
                  onChanged: (v) => setState(() => _manager = v ?? ''),
                ),
              ),
              if (widget.user?.hasPendingReportingManagerChange ?? false)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Pending Management approval → '
                    '${widget.user!.reportingManagerPending.isEmpty ? 'None' : widget.user!.reportingManagerPending}',
                    style: TextStyle(
                        fontSize: 11.5, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                  ),
                )
              else
                const SizedBox(height: 10),
            ],

            // "Is Reporting Manager" flag — only meaningful once the record
            // exists; new employees default to false and can be flagged after
            // creation. Flipping this always requires Management approval.
            if (widget.user != null) ...[
              Card(
                color: null,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                child: SwitchListTile(
                  value: _isRmFlag,
                  activeColor: _color,
                  // Keep role and flag in step. They are two representations of
                  // the same fact and could disagree — Sijo had role 'Manager'
                  // with the flag false, so he was missing from every manager
                  // picker while his record said Manager. HR and Management
                  // keep their own role; the switch only governs whether they
                  // can be picked as someone's reporting manager.
                  onChanged: (v) => setState(() {
                    _isRmFlag = v;
                    if (v && _role == 'Employee') {
                      _role = 'Manager';
                    } else if (!v && _role == 'Manager') {
                      _role = 'Employee';
                    }
                  }),
                  title: const Text('Is Reporting Manager',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Builder(builder: (_) {
                    final pending = widget.user!.hasPendingRmFlagChange;
                    // Management IS the approving authority, so a change it
                    // makes takes effect at once — saying "awaiting
                    // Management" to Management is what made this look broken.
                    final isMgmt = UserSession.role == UserRole.management;
                    if (pending) {
                      return Text(
                        'Requested: ${widget.user!.isReportingManagerPending ? 'Make RM' : 'Remove RM'} — awaiting Management approval',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade800),
                      );
                    }
                    return Text(
                      isMgmt
                          ? 'Eligible to be picked as someone’s reporting manager. Takes effect immediately.'
                          : 'Eligible to be picked as someone’s reporting manager. Needs Management approval.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    );
                  }),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Active toggle
            Card(
              color: null,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side:
                    const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              child: SwitchListTile(
                value: _active,
                activeColor: _color,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(
                    _active ? 'User can log in' : 'Login disabled',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF6B7280))),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: _color,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(isNew ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

// ── Stat cards ─────────────────────────────────────────────────────────────────

class _StatCardsRow extends StatelessWidget {
  final int total;
  final int active;
  final int probation;
  final int onLeave;
  final int deactivated;
  final List<AppUser> allUsers;
  final List<AppUser> onLeaveUsers;
  const _StatCardsRow({
    required this.total,
    required this.active,
    required this.probation,
    required this.onLeave,
    required this.deactivated,
    required this.allUsers,
    required this.onLeaveUsers,
  });

  String _pct(int count) =>
      total == 0 ? '0%' : '${(count / total * 100).toStringAsFixed(1)}%';

  List<EmployeeListItem> _items(List<AppUser> users) => users
      .map((u) => EmployeeListItem(
            name: u.name,
            subtitle: u.designation,
            workLocation: u.workLocation,
            businessUnit: u.businessUnit,
          ))
      .toList();

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _StatTile(
        icon: Icons.groups_rounded,
        iconColor: AppTheme.primaryBlue,
        label: 'Total Employees',
        value: '$total',
        sublabel: 'All registered',
        subColor: Colors.grey.shade500,
        onTap: () => showEmployeeListDialog(context,
            title: 'Total Employees', icon: Icons.groups_rounded, color: AppTheme.primaryBlue,
            items: _items(allUsers)),
      ),
      _StatTile(
        icon: Icons.person_rounded,
        iconColor: const Color(0xFF22C55E),
        label: 'Active Employees',
        value: '$active',
        sublabel: '${_pct(active)} of total',
        subColor: const Color(0xFF22C55E),
        onTap: () => showEmployeeListDialog(context,
            title: 'Active Employees', icon: Icons.person_rounded, color: const Color(0xFF22C55E),
            items: _items(allUsers.where((u) => u.active).toList()),
            emptyLabel: 'No active employees'),
      ),
      _StatTile(
        icon: Icons.access_time_filled_rounded,
        iconColor: Colors.orange.shade700,
        label: 'On Probation',
        value: '$probation',
        sublabel: '${_pct(probation)} of total',
        subColor: Colors.orange.shade700,
        onTap: () => showEmployeeListDialog(context,
            title: 'On Probation', icon: Icons.access_time_filled_rounded, color: Colors.orange.shade700,
            items: _items(allUsers.where((u) => !u.isOnroll).toList()),
            emptyLabel: 'No one is on probation'),
      ),
      _StatTile(
        icon: Icons.event_busy_rounded,
        iconColor: Colors.purple.shade600,
        label: 'On Leave',
        value: '$onLeave',
        sublabel: '${_pct(onLeave)} of total',
        subColor: Colors.purple.shade600,
        onTap: () => showEmployeeListDialog(context,
            title: 'On Leave', icon: Icons.event_busy_rounded, color: Colors.purple.shade600,
            items: _items(onLeaveUsers),
            emptyLabel: 'No one is on leave today'),
      ),
      _StatTile(
        icon: Icons.person_off_rounded,
        iconColor: Colors.grey.shade500,
        label: 'Deactivated',
        value: '$deactivated',
        sublabel: '${_pct(deactivated)} of total',
        subColor: Colors.grey.shade500,
        onTap: () => showEmployeeListDialog(context,
            title: 'Deactivated', icon: Icons.person_off_rounded, color: Colors.grey.shade500,
            items: _items(allUsers.where((u) => !u.active).toList()),
            emptyLabel: 'No deactivated employees'),
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 900;
      if (wide) {
        return Row(children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tiles[i]),
          ],
        ]);
      }
      final cols = constraints.maxWidth > 480 ? 3 : 2;
      final tileWidth = (constraints.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final t in tiles) SizedBox(width: tileWidth, child: t),
        ],
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sublabel;
  final Color subColor;
  final VoidCallback? onTap;
  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sublabel,
    required this.subColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                      color: Color(0xFF111827))),
              const SizedBox(height: 1),
              Text(sublabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        ),
      ),
    );
  }
}

// ── Small shared widgets ──────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);

  Color get _color => switch (status) {
    'EL Eligible' => AppTheme.primaryBlue,
    'On-Roll'     => const Color(0xFF22C55E),
    _             => Colors.orange.shade700,
  };

  IconData get _icon => switch (status) {
    'EL Eligible' => Icons.event_available_rounded,
    'On-Roll'     => Icons.verified_rounded,
    _             => Icons.timelapse_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon, size: 11, color: c),
        const SizedBox(width: 4),
        Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String label;
  final Color color;
  const _RoleChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _IdChip extends StatelessWidget {
  final String id;
  const _IdChip(this.id);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(id,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryBlue)),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color border;
  final Color text;
  const _Badge(this.label, this.bg, this.border, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: text, fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: AppTheme.primaryBlue),
        const SizedBox(width: 10),
        SizedBox(
          width: 140,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF263238))),
        ),
      ]),
    );
  }
}
