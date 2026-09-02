import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../utils/attendance_day.dart';
import 'package:go_router/go_router.dart';
import '../constants/org_lists.dart';
import '../models/app_user.dart';
import '../models/attendance_store.dart';
import '../models/leave_store.dart';
import '../models/office_timing.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../utils/checkin_status.dart';
import '../utils/csv_export.dart';
import '../widgets/back_button.dart';
import '../widgets/employee_list_dialog.dart';
import '../widgets/filter_panel.dart';
import '../widgets/route_map_view.dart';
import '../theme/app_theme.dart';

/// Resolves [employeeName]'s designation-based schedule from [users];
/// falls back to the default timing if the employee isn't found.
OfficeTiming _scheduleForEmployee(String employeeName, List<AppUser> users) {
  final n = employeeName.trim().toLowerCase();
  final user = users.where((u) => u.name.trim().toLowerCase() == n).firstOrNull;
  return user != null ? OfficeTimingStore.scheduleForUser(user) : OfficeTimingStore.fallback;
}

CheckInRowStatus _rowStatus(AttendanceRecord r, List<LeaveApplication> leaveApps, List<AppUser> users) {
  final date = parseSlashDate(r.date);
  if (date == null) return const CheckInRowStatus(CheckInStatus.none, 0);
  return checkInStatusFor(r.checkInTime, date, r.employeeName, leaveApps,
      _scheduleForEmployee(r.employeeName, users),
      lateWaived: r.lateWaived, onDuty: r.onDuty);
}

/// Formats the gap between "HH:mm" check-in/check-out times as "Xh Ym".
/// Returns null when either side is missing, malformed, or check-out
/// precedes check-in.
String? _workDuration(String checkInTime, String checkOutTime) {
  if (checkInTime.isEmpty || checkOutTime.isEmpty) return null;
  int? toMinutes(String t) {
    final parts = t.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
  final inMinutes = toMinutes(checkInTime);
  final outMinutes = toMinutes(checkOutTime);
  if (inMinutes == null || outMinutes == null || outMinutes < inMinutes) return null;
  final total = outMinutes - inMinutes;
  return '${total ~/ 60}h ${(total % 60).toString().padLeft(2, '0')}m';
}

class HrAttendanceRecordsPage extends StatefulWidget {
  final String routePrefix;
  const HrAttendanceRecordsPage({super.key, this.routePrefix = ''});

  @override
  State<HrAttendanceRecordsPage> createState() =>
      _HrAttendanceRecordsPageState();
}

class _HrAttendanceRecordsPageState extends State<HrAttendanceRecordsPage> {
  static Color get _color => AppTheme.primaryBlue;

  String _search = '';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  List<AttendanceRecord> _records = [];
  List<LeaveApplication> _leaveApps = [];
  List<AppUser> _allUsers = [];
  String? _departmentFilter;
  Map<String, List<AttendanceRecord>> _trendByDate = {};
  DateTime? _lastUpdated;
  final _recordsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  String _dateToStr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// The 7 calendar days ending on [_selectedDate], oldest first — the
  /// window the summary card's sparklines and day-over-day deltas draw from.
  List<DateTime> get _trendDates =>
      List.generate(7, (i) => _selectedDate.subtract(Duration(days: 6 - i)));

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final trendDateStrs = _trendDates.map(_dateToStr).toList();
    final results = await Future.wait([
      SupabaseService.fetchAttendanceForDate(_dateToStr(_selectedDate)),
      UserStore.load(),
      SupabaseService.fetchLeaveApplications(),
      SupabaseService.fetchAttendanceForDates(trendDateStrs),
      SupabaseService.fetchHolidays(_selectedDate.year),
    ]);
    if (mounted) setState(() {
      _records = results[0] as List<AttendanceRecord>;
      _allUsers = (results[1] as List<AppUser>).where((u) => u.active).toList();
      _leaveApps = results[2] as List<LeaveApplication>;
      final trendRecords = results[3] as List<AttendanceRecord>;
      _trendByDate = {
        for (final d in trendDateStrs)
          d: trendRecords.where((r) => r.date == d).toList(),
      };
      // Public holidays are not absences. Without these the screen counted
      // Diwali, Independence Day and the rest as absent for everyone.
      _holidayDates = {
        for (final h in (results[4] as List<Map<String, dynamic>>))
          if ((h['holiday_date'] as String?)?.isNotEmpty ?? false)
            (h['holiday_date'] as String).substring(0, 10),
      };
      _lastUpdated = DateTime.now();
      _isLoading = false;
    });
  }

  List<String> get _departments => kDepartments;

  List<AppUser> get _summaryUsers => _departmentFilter == null
      ? _allUsers
      : _allUsers.where((u) => u.department == _departmentFilter).toList();

  void _scrollToRecords() {
    final ctx = _recordsSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  /// Public holidays for the selected year, as 'yyyy-MM-dd'. Empty until
  /// loaded; classifyMissingAttendance() degrades gracefully if so.
  Set<String> _holidayDates = {};

  /// Why each employee has no record today. "No record" is not "absent": a
  /// weekly off, a public holiday, approved leave, or being exempt from
  /// attendance altogether all produce no record and none of them is an
  /// absence. Without this, Sundays showed five people absent and the CEO
  /// appeared absent every day.
  Map<String, NonWorkingReason> get _missingReasons {
    final present = _records.map((r) => r.employeeName.toLowerCase()).toSet();
    final out = <String, NonWorkingReason>{};
    for (final u in _allUsers) {
      if (present.contains(u.name.toLowerCase())) continue;
      out[u.name] = classifyMissingAttendance(
        employee: u,
        date: _selectedDate,
        holidayDates: _holidayDates,
        leaveApps: _leaveApps,
      );
    }
    return out;
  }

  /// Attendance rows plus a synthetic row for every active employee with no
  /// record — labelled with the REASON, not blanket "Absent". Employees who
  /// are not tracked at all are omitted entirely.
  List<AttendanceRecord> get _displayRecords {
    final present = _records.map((r) => r.employeeName.toLowerCase()).toSet();
    final reasons = _missingReasons;
    final dateStr = _dateToStr(_selectedDate);
    return [
      ..._records,
      ..._allUsers
          .where((u) => !present.contains(u.name.toLowerCase()))
          .where((u) => reasons[u.name] != NonWorkingReason.notTracked)
          .map((u) => AttendanceRecord(
                id: 'absent_${u.employeeId}',
                employeeName: u.name,
                employeeId: u.employeeId,
                date: dateStr,
              )),
    ];
  }

  bool get _isToday {
    final t = DateTime.now();
    return _selectedDate.year == t.year &&
        _selectedDate.month == t.month &&
        _selectedDate.day == t.day;
  }

  bool _matches(String employee) =>
      _search.isEmpty ||
      employee.toLowerCase().contains(_search.toLowerCase());

  // AttendanceRecord has no department of its own — resolved via _allUsers,
  // same name-matching _scheduleForEmployee already relies on above.
  bool _matchesDepartment(String employeeName) {
    if (_departmentFilter == null) return true;
    final n = employeeName.trim().toLowerCase();
    final user = _allUsers.where((u) => u.name.trim().toLowerCase() == n).firstOrNull;
    return user?.department == _departmentFilter;
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  void _showDetail(AttendanceRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => _AttendanceDetailDialog(record: record),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isAfter(now) ? now : _selectedDate,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
      _loadRecords();
    }
  }

  Future<void> _exportCsv() async {
    final rows = _displayRecords
        .where((r) => _matches(r.employeeName) && _matchesDepartment(r.employeeName))
        .toList();
    final buffer = StringBuffer('Employee,Employee ID,Date,Check-In,Check-Out,Status\n');
    for (final r in rows) {
      final rowStatus = _rowStatus(r, _leaveApps, _allUsers);
      final status = r.checkInTime.isEmpty
          ? 'Absent'
          : switch (rowStatus.status) {
              CheckInStatus.onDuty => 'On Duty',
              CheckInStatus.late => 'Late',
              CheckInStatus.permission => 'Permission (${permLabel(rowStatus.permMinutes)})',
              _ => 'Present',
            };
      buffer.writeln('"${r.employeeName}","${r.employeeId}","${r.date}",'
          '"${r.checkInTime}","${r.checkOutTime}","$status"');
    }
    await exportCsv(
      'attendance_${_dateToStr(_selectedDate).replaceAll('/', '-')}.csv',
      buffer.toString(),
    );
  }

  void _showEmployeeList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeListSheet(
        routePrefix: widget.routePrefix,
        parentContext: context,
      ),
    );
  }

  Widget _buildDateNav() {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    return Container(
      height: 46,
      constraints: const BoxConstraints(minWidth: 230),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message: 'Previous day',
          child: InkWell(
            onTap: () {
              setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
              _loadRecords();
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.chevron_left_rounded, size: 20, color: _color),
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _pickDate,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.calendar_today_rounded, size: 14, color: _color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _fmtDate(_selectedDate),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: _color),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _color),
            ]),
          ),
        ),
        Tooltip(
          message: isToday ? '' : 'Next day',
          child: InkWell(
            onTap: isToday
                ? null
                : () {
                    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                    _loadRecords();
                  },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.chevron_right_rounded,
                  size: 20, color: isToday ? Colors.grey.shade400 : _color),
            ),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _displayRecords
        .where((r) => _matches(r.employeeName) && _matchesDepartment(r.employeeName))
        .toList();
    final narrow = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NavBackButton(),
            SizedBox(width: narrow ? 6 : 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Attendance Dashboard',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium),
                if (!narrow) ...[
                  const SizedBox(height: 2),
                  Text('Track and manage employee attendance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280))),
                ],
              ]),
            ),
            Tooltip(
              message: 'Refresh',
              child: InkWell(
                onTap: _isLoading ? null : _loadRecords,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _isLoading
                      ? SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _color))
                      : Icon(Icons.refresh_rounded, color: _color, size: 22),
                ),
              ),
            ),
            SizedBox(width: narrow ? 4 : 8),
            narrow
                ? IconButton(
                    tooltip: 'Export',
                    onPressed: _displayRecords.isEmpty ? null : _exportCsv,
                    icon: const Icon(Icons.file_download_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF111827),
                      foregroundColor: Colors.white,
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _displayRecords.isEmpty ? null : _exportCsv,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF111827),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    icon: const Icon(Icons.file_download_rounded, size: 18),
                    label: const Text('Export'),
                  ),
          ]),
          const SizedBox(height: 24),

          // Employee Attendance Records shortcut
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showEmployeeList(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.people_alt_rounded, color: _color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Employee Attendance Records',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                              color: _color)),
                      Text('View monthly attendance calendar per employee',
                          style: TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: _color),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Search + date row
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 560;
            final search = TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search employee...',
                prefixIcon: Icon(Icons.search_rounded, color: _color, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _color, width: 2),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            );
            final dateControl = _buildDateNav();
            return narrow
                ? Column(children: [
                    search,
                    const SizedBox(height: 10),
                    dateControl,
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: search),
                    const SizedBox(width: 12),
                    dateControl,
                  ]);
          }),
          const SizedBox(height: 16),

          if (_isLoading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(color: _color)),
            )
          else ...[
            Builder(builder: (context) {
              final summaryUsers = _summaryUsers;
              final summaryUserNames =
                  summaryUsers.map((u) => u.name.toLowerCase()).toSet();
              final summaryRecords = _departmentFilter == null
                  ? _records
                  : _records
                      .where((r) =>
                          summaryUserNames.contains(r.employeeName.toLowerCase()))
                      .toList();
              return _AttendanceSummaryCard(
                records: summaryRecords,
                allUsers: summaryUsers,
                totalUsers: summaryUsers.length,
                missingReasons: _missingReasons,
                leaveApps: _leaveApps,
                selectedDate: _selectedDate,
                isToday: _isToday,
                isRefreshing: _isLoading,
                trendByDate: _trendByDate,
                summaryUserNames:
                    _departmentFilter == null ? null : summaryUserNames,
                departments: _departments,
                departmentFilter: _departmentFilter,
                onDepartmentChanged: (v) => setState(() => _departmentFilter = v),
                onRefresh: _loadRecords,
                lastUpdated: _lastUpdated,
                onViewDetails: _scrollToRecords,
              );
            }),
            const SizedBox(height: 16),
            _Section(
              key: _recordsSectionKey,
              title: 'Attendance Records',
              subtitle: '${filtered.length} employee${filtered.length == 1 ? '' : 's'}',
              color: _color,
              child: filtered.isEmpty
                  ? _Empty()
                  : _AttendanceTable(
                      records: filtered,
                      leaveApps: _leaveApps,
                      allUsers: _allUsers,
                      color: _color,
                      onRowTap: _showDetail,
                      missingReasons: _missingReasons,
                    ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Attendance summary card ───────────────────────────────────────────────────

class _AttendanceSummaryCard extends StatelessWidget {
  final List<AttendanceRecord> records;
  final List<LeaveApplication> leaveApps;
  final List<AppUser> allUsers;
  final int totalUsers;
  final DateTime selectedDate;
  final bool isToday;
  final bool isRefreshing;
  final Map<String, List<AttendanceRecord>> trendByDate;
  // Restricts trend/comp-off day math to this set of employee names when a
  // department filter is active; null means "everyone".
  final Set<String>? summaryUserNames;
  /// employeeName -> why they have no record today. Without this the card
  /// computed absent as (totalUsers - present), which counts weekly offs,
  /// public holidays, approved leave and the CEO as absences.
  final Map<String, NonWorkingReason> missingReasons;
  final List<String> departments;
  final String? departmentFilter;
  final ValueChanged<String?> onDepartmentChanged;
  final VoidCallback onRefresh;
  final DateTime? lastUpdated;
  final VoidCallback onViewDetails;

  const _AttendanceSummaryCard({
    required this.records,
    required this.allUsers,
    required this.totalUsers,
    this.missingReasons = const {},
    required this.leaveApps,
    required this.selectedDate,
    required this.isToday,
    required this.isRefreshing,
    required this.trendByDate,
    required this.summaryUserNames,
    required this.departments,
    required this.departmentFilter,
    required this.onDepartmentChanged,
    required this.onRefresh,
    required this.lastUpdated,
    required this.onViewDetails,
  });

  static const _green  = Color(0xFF22C55E);
  static const _red    = Color(0xFFEF4444);
  static const _orange = Color(0xFFF59E0B);
  static const _purple = Color(0xFFA855F7);
  static const _gray   = Color(0xFF6B7280);
  static const _teal   = Color(0xFF15803D);

  String _dateStr(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  bool _covers(LeaveApplication a, DateTime d) =>
      !d.isBefore(DateTime(a.from.year, a.from.month, a.from.day)) &&
      !d.isAfter(DateTime(a.to.year, a.to.month, a.to.day));

  List<AttendanceRecord> _forNames(List<AttendanceRecord> recs) =>
      summaryUserNames == null
          ? recs
          : recs.where((r) => summaryUserNames!.contains(r.employeeName.toLowerCase())).toList();

  int _compOffCount(DateTime d) => leaveApps
      .where((a) =>
          a.leaveType == 'Comp Off' &&
          a.managerStatus == LeaveApprovalStatus.approved &&
          _covers(a, d) &&
          (summaryUserNames == null ||
              summaryUserNames!.contains(a.employeeName.toLowerCase())))
      .map((a) => a.employeeName.toLowerCase())
      .toSet()
      .length;

  // employeeName -> AppUser lookup, for designation subtitles in the tap-through dialogs.
  AppUser? _userFor(String name) {
    final n = name.trim().toLowerCase();
    for (final u in allUsers) {
      if (u.name.trim().toLowerCase() == n) return u;
    }
    return null;
  }

  EmployeeListItem _item(String name, {String? extra}) {
    final u = _userFor(name);
    final parts = [if (u?.designation.isNotEmpty ?? false) u!.designation, if (extra != null && extra.isNotEmpty) extra];
    return EmployeeListItem(name: name, subtitle: parts.join(' • '));
  }

  @override
  Widget build(BuildContext context) {
    final presentRecords = records.where((r) => r.checkInTime.isNotEmpty).toList();
    final present = presentRecords.length;
    final presentNames = presentRecords.map((r) => r.employeeName.trim().toLowerCase()).toSet();

    // Only a genuine unexplained absence counts. A weekly off, a public
    // holiday, approved leave, or being exempt from attendance all produce no
    // record and none of them is an absence — the old (totalUsers - present)
    // arithmetic counted all of them, which is why five people showed absent
    // every Sunday and the CEO showed absent every day.
    final absentUsers = allUsers
        .where((u) => !presentNames.contains(u.name.trim().toLowerCase()))
        .where((u) =>
            (missingReasons[u.name] ?? NonWorkingReason.absent).countsAsAbsent)
        .toList();
    final absent = absentUsers.length;

    // Employees not tracked at all are outside the percentages too, otherwise
    // "80% present" is measured against a headcount that includes someone who
    // can never check in.
    final trackedUsers = (totalUsers -
            allUsers
                .where((u) =>
                    missingReasons[u.name] == NonWorkingReason.notTracked)
                .length)
        .clamp(0, totalUsers);
    final lateRecords = records.where((r) => _rowStatus(r, leaveApps, allUsers).status == CheckInStatus.late).toList();
    final permissionRecords = records.where((r) => _rowStatus(r, leaveApps, allUsers).status == CheckInStatus.permission).toList();
    final lateArrivals = lateRecords.length;
    final onPermission = permissionRecords.length;
    final compOff = _compOffCount(selectedDate);
    final compOffApps = leaveApps.where((a) =>
        a.leaveType == 'Comp Off' &&
        a.managerStatus == LeaveApprovalStatus.approved &&
        _covers(a, selectedDate) &&
        (summaryUserNames == null || summaryUserNames!.contains(a.employeeName.toLowerCase())));
    final compOffNamesSeen = <String>{};
    final compOffItems = <EmployeeListItem>[];
    for (final a in compOffApps) {
      final key = a.employeeName.trim().toLowerCase();
      if (compOffNamesSeen.add(key)) compOffItems.add(_item(a.employeeName));
    }

    // 7-day trend (oldest→newest, ending on selectedDate) for the sparklines
    // and the "vs yesterday" delta badges.
    final trendDates = List.generate(7, (i) => selectedDate.subtract(Duration(days: 6 - i)));
    final trendDayData = trendDates.map((d) {
      final recs = _forNames(trendByDate[_dateStr(d)] ?? const []);
      final st = recs.map((r) => _rowStatus(r, leaveApps, allUsers)).toList();
      return (
        present: recs.where((r) => r.checkInTime.isNotEmpty).length,
        late: st.where((s) => s.status == CheckInStatus.late).length,
        permission: st.where((s) => s.status == CheckInStatus.permission).length,
        compOff: _compOffCount(d),
      );
    }).toList();

    double pct(int n) => trackedUsers == 0 ? 0 : n / trackedUsers * 100;
    double deltaPct(
        int Function(({int present, int late, int permission, int compOff}) d) pick) {
      if (trendDayData.length < 2) return 0;
      final today = trendDayData.last, yesterday = trendDayData[trendDayData.length - 2];
      return pct(pick(today)) - pct(pick(yesterday));
    }

    final stats = [
      _StatSpec('Present', present, pct(present), deltaPct((d) => d.present),
          Icons.check_circle_rounded, _green,
          trendDayData.map((d) => d.present.toDouble()).toList(),
          onTap: () => showEmployeeListDialog(context,
              title: 'Present Today', icon: Icons.check_circle_rounded, color: _green,
              items: presentRecords.map((r) => _item(r.employeeName, extra: r.checkInTime)).toList(),
              emptyLabel: 'No one has checked in yet')),
      _StatSpec('Absent', absent, pct(absent), -deltaPct((d) => d.present),
          Icons.cancel_rounded, _red,
          trendDayData.map((d) => (totalUsers - d.present).clamp(0, totalUsers).toDouble()).toList(),
          onTap: () => showEmployeeListDialog(context,
              title: 'Absent Today', icon: Icons.cancel_rounded, color: _red,
              items: absentUsers.map((u) => _item(u.name)).toList(),
              emptyLabel: 'Everyone has checked in')),
      _StatSpec('Late Arrivals', lateArrivals, pct(lateArrivals), deltaPct((d) => d.late),
          Icons.schedule_rounded, _orange,
          trendDayData.map((d) => d.late.toDouble()).toList(),
          onTap: () => showEmployeeListDialog(context,
              title: 'Late Arrivals', icon: Icons.schedule_rounded, color: _orange,
              items: lateRecords.map((r) => _item(r.employeeName, extra: r.checkInTime)).toList(),
              emptyLabel: 'No late arrivals')),
      _StatSpec('On Permission', onPermission, pct(onPermission), deltaPct((d) => d.permission),
          Icons.event_note_rounded, _purple,
          trendDayData.map((d) => d.permission.toDouble()).toList(),
          onTap: () => showEmployeeListDialog(context,
              title: 'On Permission', icon: Icons.event_note_rounded, color: _purple,
              items: permissionRecords.map((r) => _item(r.employeeName,
                  extra: 'Permission (${permLabel(_rowStatus(r, leaveApps, allUsers).permMinutes)})')).toList(),
              emptyLabel: 'No one is on permission today')),
      _StatSpec('Comp Off', compOff, pct(compOff), deltaPct((d) => d.compOff),
          Icons.swap_horiz_rounded, _gray,
          trendDayData.map((d) => d.compOff.toDouble()).toList(),
          onTap: () => showEmployeeListDialog(context,
              title: 'Comp Off', icon: Icons.swap_horiz_rounded, color: _gray,
              items: compOffItems,
              emptyLabel: 'No one is on comp off today')),
      _StatSpec('On Duty', 0, 0, 0, Icons.work_rounded, _teal,
          List.filled(trendDayData.length, 0.0),
          onTap: () => showEmployeeListDialog(context,
              title: 'On Duty', icon: Icons.work_rounded, color: _teal,
              items: const [],
              emptyLabel: 'No one is marked on duty')),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SummaryHeader(
            selectedDate: selectedDate,
            isToday: isToday,
            isRefreshing: isRefreshing,
            departments: departments,
            departmentFilter: departmentFilter,
            onDepartmentChanged: onDepartmentChanged,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            final cols = constraints.maxWidth > 980 ? 6
                : constraints.maxWidth > 680 ? 3
                : 2;
            final tileWidth = (constraints.maxWidth - (cols - 1) * 12) / cols;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: stats.map((s) => SizedBox(
                width: tileWidth,
                child: _StatCard(spec: s, totalUsers: totalUsers),
              )).toList(),
            );
          }),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 14),
          _SummaryFooter(
            totalUsers: totalUsers,
            lastUpdated: lastUpdated,
            onRefresh: onRefresh,
            onViewDetails: onViewDetails,
          ),
        ]),
      ),
    );
  }
}

class _StatSpec {
  final String label;
  final int value;
  final double pctOfTotal;
  final double deltaPct;
  final IconData icon;
  final Color color;
  final List<double> trend;
  final VoidCallback? onTap;
  const _StatSpec(this.label, this.value, this.pctOfTotal, this.deltaPct,
      this.icon, this.color, this.trend, {this.onTap});
}

// ── Header: title, live date badge, department filter, refresh ────────────────

class _SummaryHeader extends StatelessWidget {
  final DateTime selectedDate;
  final bool isToday;
  final bool isRefreshing;
  final List<String> departments;
  final String? departmentFilter;
  final ValueChanged<String?> onDepartmentChanged;
  final VoidCallback onRefresh;

  const _SummaryHeader({
    required this.selectedDate,
    required this.isToday,
    required this.isRefreshing,
    required this.departments,
    required this.departmentFilter,
    required this.onDepartmentChanged,
    required this.onRefresh,
  });

  static const _months = ['January','February','March','April','May','June',
      'July','August','September','October','November','December'];
  static const _days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_months[selectedDate.month - 1]} ${selectedDate.day}, ${selectedDate.year} · '
        '${_days[selectedDate.weekday - 1]}';

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 720;
      final titleBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isToday ? 'Today Attendance Summary' : 'Attendance Summary',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                color: Color(0xFF111827))),
        const SizedBox(height: 3),
        Text(
            isToday
                ? "Real-time overview of today's attendance status"
                : 'Overview of attendance status for the selected date',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
      ]);

      final rightControls = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF6B7280)),
            const SizedBox(width: 7),
            Text(dateLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
          ]),
        ),
        if (isToday)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
              SizedBox(width: 6),
              Text('Live', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: Color(0xFF16A34A))),
            ]),
          ),
        Builder(builder: (context) {
          return FilterTriggerButton(
            hasActiveFilters: departmentFilter != null,
            onTap: () {
              String? draft = departmentFilter;
              showFilterPanel(
                context,
                title: 'Filters',
                onReset: () => draft = null,
                onApply: () => onDepartmentChanged(draft),
                builder: (context, setPanelState) => FilterDropdownField<String>(
                  label: 'Department',
                  value: draft,
                  options: departments,
                  labelOf: (d) => d,
                  allLabel: 'All Departments',
                  onChanged: (v) => setPanelState(() => draft = v),
                ),
              );
            },
          );
        }),
        Tooltip(
          message: 'Refresh',
          child: InkWell(
            onTap: isRefreshing ? null : onRefresh,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: isRefreshing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF6B7280)),
            ),
          ),
        ),
      ]);

      return narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              titleBlock,
              const SizedBox(height: 12),
              rightControls,
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 12),
              rightControls,
            ]);
    });
  }
}

// ── One stat tile: icon, delta badge, big number, % of total, sparkline ───────

class _StatCard extends StatelessWidget {
  final _StatSpec spec;
  final int totalUsers;
  const _StatCard({required this.spec, required this.totalUsers});

  @override
  Widget build(BuildContext context) {
    final color = spec.color;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: spec.onTap,
        child: IntrinsicHeight(
        child: Row(children: [
          Container(width: 3, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(spec.icon, size: 13, color: color),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(spec.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                            color: Color(0xFF111827))),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${spec.value}',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: color, height: 1)),
                  const SizedBox(width: 5),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('${spec.pctOfTotal.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7280))),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
        ),
      ),
    );
  }
}

// ── Footer: total workforce, last updated, view detailed report ───────────────

class _SummaryFooter extends StatelessWidget {
  final int totalUsers;
  final DateTime? lastUpdated;
  final VoidCallback onRefresh;
  final VoidCallback onViewDetails;
  const _SummaryFooter({
    required this.totalUsers,
    required this.lastUpdated,
    required this.onRefresh,
    required this.onViewDetails,
  });

  String _fmtTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 620;
      final info = Wrap(spacing: 20, runSpacing: 8, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.people_alt_outlined, size: 15, color: Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Total Workforce: ',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            TextSpan(text: '$totalUsers Employees',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: Color(0xFF111827))),
          ])),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.access_time_rounded, size: 15, color: Color(0xFF6B7280)),
          const SizedBox(width: 6),
          Text(lastUpdated == null ? 'Last updated: —' : 'Last updated: ${_fmtTime(lastUpdated!)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRefresh,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF6B7280)),
            ),
          ),
        ]),
      ]);

      final button = OutlinedButton(
        onPressed: onViewDetails,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF111827),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Text('View Detailed Report',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          Icon(Icons.chevron_right_rounded, size: 16),
        ]),
      );

      return narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              info,
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: button),
            ])
          : Row(children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              button,
            ]);
    });
  }
}

// ── Unified attendance table ──────────────────────────────────────────────────

class _AttendanceTable extends StatefulWidget {
  final List<AttendanceRecord> records;
  final List<LeaveApplication> leaveApps;
  final List<AppUser> allUsers;
  final Color color;
  final void Function(AttendanceRecord) onRowTap;
  /// employeeName -> why they have no record. Lets a row show 'Weekly Off',
  /// 'Holiday' or 'On Leave' instead of a blanket 'Absent'.
  final Map<String, NonWorkingReason> missingReasons;
  const _AttendanceTable({
    required this.records,
    required this.leaveApps,
    required this.allUsers,
    required this.color,
    required this.onRowTap,
    this.missingReasons = const {},
  });

  @override
  State<_AttendanceTable> createState() => _AttendanceTableState();
}

class _AttendanceTableState extends State<_AttendanceTable> {
  static const _red = Color(0xFFEF4444);
  static const _green = Color(0xFF22C55E);
  final Set<String> _selected = {};

  Widget _statusChip(AttendanceRecord r, CheckInRowStatus rs) {
    final String label;
    final Color chipColor;
    if (r.checkInTime.isEmpty) {
      // Not every missing record is an absence.
      final reason = widget.missingReasons[r.employeeName] ?? NonWorkingReason.absent;
      label = reason.label;
      chipColor = switch (reason) {
        NonWorkingReason.absent     => _red,
        NonWorkingReason.weeklyOff  => const Color(0xFF6B7280),
        NonWorkingReason.holiday    => const Color(0xFFEDA100),
        NonWorkingReason.onLeave    => AppTheme.accentBlue,
        NonWorkingReason.notTracked => const Color(0xFF9CA3AF),
      };
    } else {
      switch (rs.status) {
        case CheckInStatus.onDuty:
          // Business work outside normal hours — presence, and deliberately
          // not folded into 'Present' so HR can see which days these were.
          label = 'On Duty';
          chipColor = Colors.orange.shade700;
          break;
        case CheckInStatus.permission:
          label = 'Permission (${permLabel(rs.permMinutes)})';
          chipColor = AppTheme.accentBlue;
          break;
        case CheckInStatus.late:
          label = 'Late';
          chipColor = _red;
          break;
        case CheckInStatus.onTime:
        case CheckInStatus.none:
          label = 'Present';
          chipColor = _green;
          break;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: chipColor)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final leaveApps = widget.leaveApps;
    final records = widget.records;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: true,
        headingRowColor: WidgetStateProperty.all(color.withValues(alpha: 0.06)),
        border: TableBorder.all(
            color: Theme.of(context).dividerColor, borderRadius: BorderRadius.circular(8)),
        columns: [
          DataColumn(label: Text('Employee',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color))),
          DataColumn(label: Text('Date',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color))),
          DataColumn(label: Text('Check-In Time',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color))),
          DataColumn(label: Text('Check-Out Time',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color))),
          DataColumn(label: Text('Work Duration',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color))),
          DataColumn(label: Text('Status',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color))),
          DataColumn(label: Text('Details',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color))),
        ],
        rows: records.map((r) {
          final bothRecorded = r.checkInTime.isNotEmpty && r.checkOutTime.isNotEmpty;
          final statusText = bothRecorded
              ? 'Checked out'
              : r.checkInTime.isNotEmpty ? 'Checked in' : '—';
          final rowStatus = _rowStatus(r, leaveApps, widget.allUsers);
          final initial = r.employeeName.isNotEmpty ? r.employeeName[0].toUpperCase() : '?';
          return DataRow(
            selected: _selected.contains(r.id),
            onSelectChanged: (v) => setState(() {
              if (v ?? false) {
                _selected.add(r.id);
              } else {
                _selected.remove(r.id);
              }
            }),
            color: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return color.withValues(alpha: 0.04);
              return null;
            }),
            cells: [
              DataCell(
                Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: color.withValues(alpha: 0.1),
                    child: Text(initial,
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(r.employeeName,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface)),
                    if (r.employeeId.isNotEmpty)
                      Text(r.employeeId,
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF9CA3AF))),
                  ]),
                ]),
                onTap: () => widget.onRowTap(r),
              ),
              DataCell(Text(r.date,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                  onTap: () => widget.onRowTap(r)),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                Text(r.checkInTime.isNotEmpty ? r.checkInTime : '—',
                    style: TextStyle(fontSize: 12,
                        color: r.checkInTime.isNotEmpty
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.grey.shade400)),
                if (r.checkInNote.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: r.checkInNote,
                    child: Icon(Icons.edit_note_rounded, size: 14, color: color.withValues(alpha: 0.6)),
                  ),
                ],
              ]), onTap: () => widget.onRowTap(r)),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                Text(r.checkOutTime.isNotEmpty ? r.checkOutTime : '—',
                    style: TextStyle(fontSize: 12,
                        color: r.checkOutTime.isNotEmpty
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.grey.shade400)),
                if (r.checkOutNote.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: r.checkOutNote,
                    child: Icon(Icons.edit_note_rounded, size: 14, color: color.withValues(alpha: 0.6)),
                  ),
                ],
              ]), onTap: () => widget.onRowTap(r)),
              DataCell(Text(_workDuration(r.checkInTime, r.checkOutTime) ?? '—',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface)),
                  onTap: () => widget.onRowTap(r)),
              DataCell(_statusChip(r, rowStatus), onTap: () => widget.onRowTap(r)),
              DataCell(Row(children: [
                Text(statusText,
                    style: TextStyle(fontSize: 11.5, color: color.withValues(alpha: 0.85))),
                if (statusText != '—') ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 14, color: color.withValues(alpha: 0.5)),
                ],
              ]), onTap: () => widget.onRowTap(r)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Attendance detail dialog ──────────────────────────────────────────────────

class _AttendanceDetailDialog extends StatefulWidget {
  final AttendanceRecord record;
  const _AttendanceDetailDialog({required this.record});
  @override
  State<_AttendanceDetailDialog> createState() => _AttendanceDetailDialogState();
}

class _AttendanceDetailDialogState extends State<_AttendanceDetailDialog> {
  static Color get _color => AppTheme.primaryBlue;

  late bool _waived = widget.record.lateWaived;
  late String _waiverReason = widget.record.lateWaiverReason;
  bool _busy = false;

  /// Excuse a late arrival. Management only — the RPC refuses anyone else, so
  /// the button is hidden rather than shown-and-refused.
  Future<void> _waive() async {
    final ctrl = TextEditingController(
        text: 'App fault — could not complete check-in on time.');
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excuse this late arrival'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'The recorded time is not changed — it is when the system accepted '
            'the check-in. This records that the lateness is excused, and why.',
            style: TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Reason', border: OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Excuse'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    setState(() => _busy = true);
    final err = await SupabaseService.waiveLate(widget.record.id, reason);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) { _waived = true; _waiverReason = reason; }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? 'Late arrival excused'),
      backgroundColor: err == null ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final hasCheckOut = r.checkOutTime.isNotEmpty;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.access_time_rounded, color: _color, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Attendance Record',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, size: 20, color: Colors.grey.shade600),
                  ),
                ),
              ]),

              // Late waiver. Shown when already excused so the reason and who
              // granted it are visible; offered to Management otherwise.
              if (_waived) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.verified_rounded, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Late arrival excused',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade800)),
                        if (_waiverReason.isNotEmpty)
                          Text(_waiverReason,
                              style: TextStyle(fontSize: 11.5, color: Colors.green.shade900)),
                      ]),
                    ),
                  ]),
                ),
              ] else if (UserSession.role == UserRole.management &&
                  r.checkInTime.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _waive,
                    icon: const Icon(Icons.timer_off_rounded, size: 16),
                    label: const Text('Excuse late arrival'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber.shade800,
                      side: BorderSide(color: Colors.amber.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
              _InfoRow(Icons.person_rounded, 'Employee', r.employeeName),
              if (r.employeeId.isNotEmpty) ...[
                const SizedBox(height: 10),
                _InfoRow(Icons.badge_rounded, 'Employee ID', r.employeeId),
              ],
              const SizedBox(height: 10),
              _InfoRow(Icons.calendar_today_rounded, 'Date', r.date),
              const SizedBox(height: 10),
              _InfoRow(Icons.login_rounded, 'Check-In', r.checkInTime.isNotEmpty ? r.checkInTime : '—'),
              if (r.checkInTime.isNotEmpty && r.checkInWithinRadius != null) ...[
                const SizedBox(height: 6),
                _GeofenceBadge(withinRadius: r.checkInWithinRadius!, policyName: r.locationPolicyName),
              ],
              if (r.checkInNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                _NoteBlock(label: 'Check-in note', text: r.checkInNote),
              ],
              const SizedBox(height: 10),
              _InfoRow(Icons.logout_rounded, 'Check-Out', hasCheckOut ? r.checkOutTime : '—'),
              if (hasCheckOut && r.checkOutWithinRadius != null) ...[
                const SizedBox(height: 6),
                _GeofenceBadge(withinRadius: r.checkOutWithinRadius!, policyName: r.locationPolicyName),
              ],
              if (r.checkOutNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                _NoteBlock(label: 'Check-out note', text: r.checkOutNote),
              ],
              if (r.checkInSelfiePath.isNotEmpty || r.checkOutSelfiePath.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SelfieSection(record: r),
              ],
              if (r.gpsPoints.isNotEmpty || r.location.isNotEmpty) ...[
                const SizedBox(height: 16),
                _RouteSection(record: r),
              ],
              if (r.checkInTime.isNotEmpty && hasCheckOut) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: Colors.green.shade600),
                    const SizedBox(width: 8),
                    Text('Full day attendance recorded',
                        style: TextStyle(fontSize: 13, color: Colors.green.shade700,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ] else if (r.checkInTime.isNotEmpty && !hasCheckOut) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(children: [
                    Icon(Icons.pending_rounded, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text('Employee not yet checked out',
                        style: TextStyle(fontSize: 13, color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Selfies are never visible to the employee themselves — this dialog only
// renders on HR/Management-facing pages, and the signed URL fetch below is
// additionally rejected server-side (storage RLS) for any other role.
class _SelfieSection extends StatelessWidget {
  final AttendanceRecord record;
  const _SelfieSection({required this.record});

  @override
  Widget build(BuildContext context) {
    final hasIn = record.checkInSelfiePath.isNotEmpty;
    final hasOut = record.checkOutSelfiePath.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.camera_alt_rounded, color: AppTheme.primaryBlue, size: 16),
        const SizedBox(width: 8),
        const Text('Selfie', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hasIn)
          Expanded(child: _SelfieThumbnail(path: record.checkInSelfiePath, label: 'Check-In')),
        if (hasIn && hasOut) const SizedBox(width: 10),
        if (hasOut)
          Expanded(child: _SelfieThumbnail(path: record.checkOutSelfiePath, label: 'Check-Out')),
      ]),
    ]);
  }
}

class _SelfieThumbnail extends StatefulWidget {
  final String path;
  final String label;
  const _SelfieThumbnail({required this.path, required this.label});

  @override
  State<_SelfieThumbnail> createState() => _SelfieThumbnailState();
}

class _SelfieThumbnailState extends State<_SelfieThumbnail> {
  late final Future<String?> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = SupabaseService.attendanceSelfieUrl(widget.path);
  }

  void _openFullScreen(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox.expand(
          child: Stack(children: [
            // InteractiveViewer needs a bounded/sized child to zoom/pan
            // correctly — a bare Image.network here would render at zero
            // size in some cases, making the dialog look like it did
            // nothing when tapped.
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorBuilder: (context, error, stack) => const Center(
                    child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8, right: 8,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _urlFuture,
      builder: (context, snap) {
        final url = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        final error = snap.hasError ? snap.error.toString() : null;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                  color: Color(0xFF9CA3AF))),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: url != null
                ? () => _openFullScreen(url)
                : error != null
                    ? () => showDialog<void>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Could not load selfie'),
                            content: Text(error),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        )
                    : null,
            child: Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                color: const Color(0xFFF8FAFC),
              ),
              clipBehavior: Clip.antiAlias,
              child: loading
                  ? const Center(
                      child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : error != null
                      ? const Center(
                          child: Icon(Icons.error_outline_rounded,
                              color: Colors.redAccent, size: 22))
                      : url == null
                          ? const Center(
                              child: Icon(Icons.no_photography_rounded,
                                  color: Color(0xFF9CA3AF), size: 22))
                          : Image.network(url, fit: BoxFit.cover, width: double.infinity),
            ),
          ),
        ]);
      },
    );
  }
}

class _NoteBlock extends StatelessWidget {
  final String label;
  final String text;
  const _NoteBlock({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 26),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF))),
        const SizedBox(height: 2),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF374151))),
      ]),
    );
  }
}

/// Whether a check-in/check-out fell inside the employee's assigned
/// location radius, per the resolved Attendance Policy at the time — see
/// lib/models/attendance_policy_store.dart and location_management_page.dart.
class _GeofenceBadge extends StatelessWidget {
  final bool withinRadius;
  final String policyName;
  const _GeofenceBadge({required this.withinRadius, required this.policyName});

  @override
  Widget build(BuildContext context) {
    final color = withinRadius ? Colors.green.shade600 : Colors.orange.shade700;
    final label = withinRadius ? 'Within assigned location' : 'Outside assigned location';
    return Container(
      margin: const EdgeInsets.only(left: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(withinRadius ? Icons.check_circle_rounded : Icons.location_off_rounded, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          policyName.isNotEmpty ? '$label · $policyName' : label,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: color),
        ),
      ]),
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
    return Row(children: [
      Icon(icon, size: 16, color: AppTheme.primaryBlue),
      const SizedBox(width: 10),
      Text('$label:',
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280))),
      const SizedBox(width: 8),
      Text(value,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827))),
    ]);
  }
}

// ── Route map section ────────────────────────────────────────────────────────

class _RouteSection extends StatelessWidget {
  final AttendanceRecord record;
  const _RouteSection({required this.record});

  List<List<double>> get _points {
    if (record.gpsPoints.isNotEmpty) return record.gpsPoints;
    // Fallback: single point from location field
    final parts = record.location.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) return [[lat, lng]];
    }
    return [];
  }

  // The map is an embedded Leaflet iframe on web, which swallows pointer
  // events before a wrapping GestureDetector ever sees them — so "tap the
  // map to enlarge" doesn't work here the way it does for a plain image.
  // An explicit expand button avoids that instead of relying on a tap
  // gesture the iframe would eat.
  void _openFullMap(BuildContext context, List<List<double>> pts) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 700,
          height: 600,
          child: Stack(children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: RouteMapView(
                  points: pts,
                  recordId: record.id,
                  keyPrefix: 'hr_route_full',
                  height: 600,
                ),
              ),
            ),
            Positioned(
              top: 8, right: 8,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    if (pts.isEmpty) return const SizedBox.shrink();

    final last = pts.last;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.route_rounded, size: 15, color: AppTheme.accentBlue),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            pts.length > 1 ? 'Route (${pts.length} points)' : 'Last Known Location',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
          ),
        ),
        InkWell(
          onTap: () => _openFullMap(context, pts),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.open_in_full_rounded, size: 15, color: AppTheme.accentBlue),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      RouteMapView(points: pts, recordId: record.id, keyPrefix: 'hr_route'),
      const SizedBox(height: 6),
      Text(
        'Last: ${last[0].toStringAsFixed(6)}, ${last[1].toStringAsFixed(6)}',
        style: TextStyle(fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
      ),
    ]);
  }
}

// ── Employee list bottom sheet ────────────────────────────────────────────────
class _EmployeeListSheet extends StatefulWidget {
  final String routePrefix;
  final BuildContext parentContext;
  const _EmployeeListSheet({required this.routePrefix, required this.parentContext});

  @override
  State<_EmployeeListSheet> createState() => _EmployeeListSheetState();
}

class _EmployeeListSheetState extends State<_EmployeeListSheet> {
  static Color get _color => AppTheme.primaryBlue;
  List<AppUser> _all = [];
  List<AppUser> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await UserStore.load();
    if (!mounted) return;
    final active = users.where((u) => u.active && u.countsInHeadcount).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    setState(() {
      _all      = active;
      _filtered = active;
      _loading  = false;
    });
  }

  void _filter(String q) {
    setState(() {
      _filtered = _all
          .where((u) => u.name.toLowerCase().contains(q.toLowerCase()) ||
                        u.designation.toLowerCase().contains(q.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle + header
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.people_alt_rounded, color: _color, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Select Employee',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: cs.onSurface.withValues(alpha: 0.5)),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              autofocus: false,
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: 'Search by name or designation...',
                prefixIcon: Icon(Icons.search_rounded, color: _color, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: _color, width: 2),
                ),
                filled: true,
                fillColor: cs.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: cs.outlineVariant, height: 1),

          // List
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: _color, strokeWidth: 2))
                : _filtered.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.search_off_rounded, size: 40,
                              color: cs.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(height: 8),
                          Text('No employees found',
                              style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.4),
                                  fontSize: 13)),
                        ]),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                        itemBuilder: (_, i) {
                          final emp = _filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _color.withValues(alpha: 0.1),
                              child: Text(
                                emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
                                style: TextStyle(
                                    color: _color, fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ),
                            title: Text(emp.name,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: emp.designation.isNotEmpty
                                ? Text(emp.designation,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)))
                                : null,
                            trailing: Icon(Icons.chevron_right_rounded, color: _color),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.parentContext.go(
                                '${widget.routePrefix}/attendance/employee-attendance-calendar',
                                extra: {
                                  'employeeId':   emp.employeeId,
                                  'employeeName': emp.name,
                                },
                              );
                            },
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final Widget child;
  const _Section(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: Color(0xFF111827))),
            const SizedBox(width: 8),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ]),
          const SizedBox(height: 14),
          child,
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(children: [
          Icon(Icons.inbox_rounded, size: 36, color: Colors.grey.shade300),
          const SizedBox(height: 4),
          Text('No records for this day',
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ]),
      ),
    );
  }
}

