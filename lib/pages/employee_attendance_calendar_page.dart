import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/leave_store.dart';
import '../models/office_timing.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../models/attendance_store.dart';
import '../utils/checkin_status.dart';
import '../utils/csv_export.dart';
import '../utils/tenure.dart';
import '../utils/weekly_off.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

String _fmtSlash(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// One resolved day within a custom summary/export range — status mirrors
// the calendar's color precedence (attendance > holiday > leave >
// permission > comp off > absent), with '—' for days not yet reached.
class _RangeDay {
  final DateTime date;
  final String status;
  final String checkIn;
  final String checkOut;
  const _RangeDay(this.date, this.status, this.checkIn, this.checkOut);
}

// Fixed status colors — not theme-driven. Chosen as a set (not just
// pairwise) so every status stays distinguishable, including for
// colorblind users; see scripts/validate_palette.js in the dataviz skill.
Color get _blue => AppTheme.primaryBlue;
const _green   = Color(0xFF008300);
const _purple  = Color(0xFF2A78D6); // "Late Coming"
const _red     = Color(0xFFE34948); // "Absent"
const _yellow  = Color(0xFFEDA100); // "Holiday"
const _magenta = Color(0xFFE87BA4); // "Leave Applied"
const _teal    = Color(0xFF1BAF7A); // "Permission"
const _violet  = Color(0xFF4A3AA7); // "Comp Off"

class EmployeeAttendanceCalendarPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const EmployeeAttendanceCalendarPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<EmployeeAttendanceCalendarPage> createState() =>
      _EmployeeAttendanceCalendarPageState();
}

class _EmployeeAttendanceCalendarPageState
    extends State<EmployeeAttendanceCalendarPage> {
  late DateTime _month;
  bool _loading = true;
  Map<int, AttendanceRecord> _attendance = {};
  Set<int> _leaveDays = {};
  Set<int> _permissionDays = {};
  Set<int> _compOffDays = {};
  Set<int> _holidayDays = {};
  List<LeaveApplication> _leaveApps = [];
  int? _selectedDay;
  int _offWeekday = DateTime.sunday;
  DateTime? _joiningDate;
  OfficeTiming _schedule = OfficeTimingStore.fallback;

  // ── Summary / export range (independent of the calendar month above —
  // lets HR pull a custom cycle like "25th to 26th") ─────────────────────
  late DateTime _rangeFrom;
  late DateTime _rangeTo;
  bool _rangeLoading = false;
  List<_RangeDay> _rangeRows = [];

  int get _presentCount => _rangeRows.where((r) => r.status == 'Present').length;
  int get _lateCount    => _rangeRows.where((r) => r.status == 'Late Coming').length;
  int get _absentCount  => _rangeRows.where((r) => r.status == 'Absent').length;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _rangeFrom = DateTime(now.year, now.month, 1);
    _rangeTo   = DateTime(now.year, now.month + 1, 0);
    _load();
    _loadSummary();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SupabaseService.fetchAttendanceForMonth(widget.employeeId, _month.year, _month.month),
      SupabaseService.fetchHolidays(_month.year),
      SupabaseService.fetchLeaveApplications(),
      UserStore.load(),
    ]);
    if (!mounted) return;

    final records  = results[0] as List<AttendanceRecord>;
    final holidays = results[1] as List<Map<String, dynamic>>;
    final leaveApps = results[2] as List<LeaveApplication>;
    final users      = results[3] as List<AppUser>;
    final emp = users.where((u) => u.name == widget.employeeName).firstOrNull;
    final schedule = emp != null
        ? OfficeTimingStore.scheduleForUser(emp)
        : OfficeTimingStore.fallback;
    final offWeekday = weeklyOffWeekdayFor(emp?.effectiveWeeklyOffDay ?? 'Sunday');
    final joiningDate = parseFlexibleDate(emp?.dateOfJoining ?? '');

    final Map<int, AttendanceRecord> map = {};
    for (final r in records) {
      final d = _dayOf(r.date);
      if (d != null) map[d] = r;
    }

    // Build holiday set for current month (HR-entered holidays + this
    // employee's weekly off day — Sunday for everyone except Sales, who can
    // be assigned Tuesday or Wednesday instead; see AppUser.weeklyOffDay).
    final Set<int> holidayDays = {};
    for (final h in holidays) {
      final date = DateTime.tryParse(h['holiday_date'] as String? ?? '');
      if (date != null && date.year == _month.year && date.month == _month.month) {
        holidayDays.add(date.day);
      }
    }
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    for (int d = 1; d <= daysInMonth; d++) {
      if (DateTime(_month.year, _month.month, d).weekday == offWeekday) {
        holidayDays.add(d);
      }
    }

    // Approved leave/permission/comp-off days — exclude weekends and holidays.
    // Permission and Comp Off are distinct leaveType values from a regular
    // full-day Leave, so each gets its own set rather than lumping them
    // together as "on leave".
    final Set<int> leaves = {}, permissions = {}, compOffs = {};
    for (final app in leaveApps) {
      if (app.employeeName != widget.employeeName) continue;
      if (app.managerStatus != LeaveApprovalStatus.approved) continue;
      final target = switch (app.leaveType) {
        'Permission' => permissions,
        'Comp Off'   => compOffs,
        _            => leaves,
      };
      var d = app.from;
      while (!d.isAfter(app.to)) {
        if (d.year == _month.year && d.month == _month.month) {
          final wd = d.weekday;
          if (wd != DateTime.saturday && wd != offWeekday && !holidayDays.contains(d.day)) {
            target.add(d.day);
          }
        }
        d = d.add(const Duration(days: 1));
      }
    }

    setState(() {
      _attendance     = map;
      _leaveDays      = leaves;
      _permissionDays = permissions;
      _compOffDays    = compOffs;
      _holidayDays    = holidayDays;
      _leaveApps      = leaveApps;
      _offWeekday     = offWeekday;
      _joiningDate    = joiningDate;
      _schedule       = schedule;
      _loading        = false;
      _selectedDay    = null;
    });
  }

  static int? _dayOf(String date) {
    try { return int.parse(date.split('/').first); } catch (_) { return null; }
  }

  // Distinct (year, month) pairs spanned by [from]..[to], inclusive.
  static List<(int, int)> _monthsInRange(DateTime from, DateTime to) {
    final out = <(int, int)>[];
    var cur = DateTime(from.year, from.month);
    final end = DateTime(to.year, to.month);
    while (!cur.isAfter(end)) {
      out.add((cur.year, cur.month));
      cur = DateTime(cur.year, cur.month + 1);
    }
    return out;
  }

  Future<void> _loadSummary() async {
    setState(() => _rangeLoading = true);
    final months = _monthsInRange(_rangeFrom, _rangeTo);
    final years  = months.map((m) => m.$1).toSet();
    final results = await Future.wait([
      Future.wait(months.map(
          (m) => SupabaseService.fetchAttendanceForMonth(widget.employeeId, m.$1, m.$2))),
      Future.wait(years.map(SupabaseService.fetchHolidays)),
      SupabaseService.fetchLeaveApplications(),
      UserStore.load(),
    ]);
    if (!mounted) return;

    final byDate = <String, AttendanceRecord>{
      for (final list in results[0] as List<List<AttendanceRecord>>)
        for (final r in list) r.date: r,
    };

    final rangeUsers = results[3] as List<AppUser>;
    final rangeEmp = rangeUsers.where((u) => u.name == widget.employeeName).firstOrNull;
    final rangeSchedule = rangeEmp != null
        ? OfficeTimingStore.scheduleForUser(rangeEmp)
        : OfficeTimingStore.fallback;
    final rangeOffWeekday = weeklyOffWeekdayFor(rangeEmp?.effectiveWeeklyOffDay ?? 'Sunday');
    final rangeJoiningDate = parseFlexibleDate(rangeEmp?.dateOfJoining ?? '');

    final holidayDateStrs = <String>{};
    for (final list in results[1] as List<List<Map<String, dynamic>>>) {
      for (final h in list) {
        final d = DateTime.tryParse(h['holiday_date'] as String? ?? '');
        if (d != null && !d.isBefore(_rangeFrom) && !d.isAfter(_rangeTo)) {
          holidayDateStrs.add(_fmtSlash(d));
        }
      }
    }
    for (var d = _rangeFrom; !d.isAfter(_rangeTo); d = d.add(const Duration(days: 1))) {
      if (d.weekday == rangeOffWeekday) holidayDateStrs.add(_fmtSlash(d));
    }

    final leaveApps = results[2] as List<LeaveApplication>;
    final leaveDates = <String>{}, permissionDates = <String>{}, compOffDates = <String>{};
    for (final app in leaveApps) {
      if (app.employeeName != widget.employeeName) continue;
      if (app.managerStatus != LeaveApprovalStatus.approved) continue;
      final target = switch (app.leaveType) {
        'Permission' => permissionDates,
        'Comp Off'   => compOffDates,
        _            => leaveDates,
      };
      var d = app.from;
      while (!d.isAfter(app.to)) {
        if (!d.isBefore(_rangeFrom) && !d.isAfter(_rangeTo)) {
          final ds = _fmtSlash(d);
          if (d.weekday != DateTime.saturday && d.weekday != rangeOffWeekday &&
              !holidayDateStrs.contains(ds)) {
            target.add(ds);
          }
        }
        d = d.add(const Duration(days: 1));
      }
    }

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final rows = <_RangeDay>[];
    for (var d = _rangeFrom; !d.isAfter(_rangeTo); d = d.add(const Duration(days: 1))) {
      final ds = _fmtSlash(d);
      final rec = byDate[ds];
      if (rec != null && rec.checkInTime.isNotEmpty) {
        final st = checkInStatusFor(rec.checkInTime, d, widget.employeeName, leaveApps,
            rangeSchedule, lateWaived: rec.lateWaived);
        rows.add(_RangeDay(
            d, st.status == CheckInStatus.late ? 'Late Coming' : 'Present',
            rec.checkInTime, rec.checkOutTime));
      } else if (holidayDateStrs.contains(ds)) {
        rows.add(_RangeDay(d, 'Holiday', '', ''));
      } else if (leaveDates.contains(ds)) {
        rows.add(_RangeDay(d, 'Leave Applied', '', ''));
      } else if (permissionDates.contains(ds)) {
        rows.add(_RangeDay(d, 'Permission', '', ''));
      } else if (compOffDates.contains(ds)) {
        rows.add(_RangeDay(d, 'Comp Off', '', ''));
      } else if (rangeJoiningDate != null &&
          d.isBefore(DateTime(rangeJoiningDate.year, rangeJoiningDate.month, rangeJoiningDate.day))) {
        rows.add(_RangeDay(d, '—', '', ''));
      } else if (d.isBefore(todayDate)) {
        rows.add(_RangeDay(d, 'Absent', '', ''));
      } else {
        rows.add(_RangeDay(d, '—', '', ''));
      }
    }

    setState(() {
      _rangeRows    = rows;
      _rangeLoading = false;
    });
  }

  Future<void> _pickRangeFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeFrom,
      firstDate: DateTime(2020),
      lastDate: _rangeTo,
    );
    if (picked == null || !mounted) return;
    setState(() => _rangeFrom = picked);
    _loadSummary();
  }

  Future<void> _pickRangeTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _rangeTo,
      firstDate: _rangeFrom,
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _rangeTo = picked);
    _loadSummary();
  }

  Future<void> _exportRangeCsv() async {
    final buffer = StringBuffer('Date,Status,Check-In,Check-Out\n');
    for (final r in _rangeRows) {
      buffer.writeln('"${_fmtSlash(r.date)}","${r.status}","${r.checkIn}","${r.checkOut}"');
    }
    await exportCsv(
      'attendance_${widget.employeeName.replaceAll(RegExp(r'[^\w]'), '_')}'
      '_${_fmtSlash(_rangeFrom).replaceAll('/', '-')}_${_fmtSlash(_rangeTo).replaceAll('/', '-')}.csv',
      buffer.toString(),
    );
  }

  CheckInRowStatus _status(int day) {
    final r = _attendance[day];
    if (r == null) return const CheckInRowStatus(CheckInStatus.none, 0);
    final date = DateTime(_month.year, _month.month, day);
    return checkInStatusFor(r.checkInTime, date, widget.employeeName, _leaveApps, _schedule, lateWaived: r.lateWaived, onDuty: r.onDuty);
  }

  // True when a day has no check-in, no approved leave/permission/comp-off,
  // and isn't a holiday, but has already passed — i.e. no entry was ever
  // made for it. Days before the employee's joining date are never "missed"
  // — they simply weren't employed yet.
  bool _isMissedDay(int day) {
    final r = _attendance[day];
    if (r != null && r.checkInTime.isNotEmpty) return false;
    if (_leaveDays.contains(day)) return false;
    if (_permissionDays.contains(day)) return false;
    if (_compOffDays.contains(day)) return false;
    if (_holidayDays.contains(day)) return false;
    final date = DateTime(_month.year, _month.month, day);
    final joined = _joiningDate;
    if (joined != null && date.isBefore(DateTime(joined.year, joined.month, joined.day))) {
      return false;
    }
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return date.isBefore(todayDate);
  }

  // Precedence: actual attendance > holiday > leave > permission > comp off > absent.
  Color? _statusColor(int day) {
    final r = _attendance[day];
    if (r != null && r.checkInTime.isNotEmpty) {
      final st = _status(day).status;
      // On-duty days get their own colour so a night/BTL day is visible at a
      // glance on the calendar rather than blending into an ordinary present
      // day — management asked to be able to see which days these were.
      if (st == CheckInStatus.onDuty) return Colors.orange.shade700;
      return st == CheckInStatus.late ? _purple : _green;
    }
    if (_holidayDays.contains(day)) return _yellow;
    if (_leaveDays.contains(day)) return _magenta;
    if (_permissionDays.contains(day)) return _teal;
    if (_compOffDays.contains(day)) return _violet;
    if (_isMissedDay(day)) return _red;
    return null;
  }

  void _onTap(int day) {
    final rec          = _attendance[day];
    final isLeave       = _leaveDays.contains(day);
    final isPermission  = _permissionDays.contains(day);
    final isCompOff     = _compOffDays.contains(day);
    final missed        = _isMissedDay(day);
    if (rec == null && !isLeave && !isPermission && !isCompOff && !missed) return;

    setState(() => _selectedDay = _selectedDay == day ? null : day);
  }

  // Builds the inline dropdown card for the currently selected day, shown
  // right under its row in the calendar grid — null when nothing selected.
  Widget? _selectedDayContent() {
    final day = _selectedDay;
    if (day == null) return null;
    final rec         = _attendance[day];
    final isLeave      = _leaveDays.contains(day);
    final isPermission = _permissionDays.contains(day);
    final isCompOff    = _compOffDays.contains(day);
    final missed       = _isMissedDay(day);

    final dayDate = DateTime(_month.year, _month.month, day);
    const mon = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const dow = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final label = '${dow[dayDate.weekday - 1]}, $day ${mon[dayDate.month - 1]} ${dayDate.year}';

    return _DaySheet(
      label: label,
      record: rec,
      isLeave: isLeave,
      isPermission: isPermission,
      isCompOff: isCompOff,
      isAbsent: missed,
      status: rec != null ? _status(day) : const CheckInRowStatus(CheckInStatus.none, 0),
      onClose: () => setState(() => _selectedDay = null),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Summary & Export',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
            ),
            OutlinedButton.icon(
              onPressed: _rangeLoading || _rangeRows.isEmpty ? null : _exportRangeCsv,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Export CSV'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: BorderSide(color: _blue.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _RangeDateChip(label: 'From', date: _rangeFrom, onTap: _pickRangeFrom),
            _RangeDateChip(label: 'To', date: _rangeTo, onTap: _pickRangeTo),
          ]),
          const SizedBox(height: 16),
          if (_rangeLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              final tiles = [
                _SummaryStatTile(label: 'Present', count: _presentCount, color: _green),
                _SummaryStatTile(label: 'Late Coming', count: _lateCount, color: _purple),
                _SummaryStatTile(label: 'Absent', count: _absentCount, color: _red),
              ];
              if (constraints.maxWidth > 420) {
                return Row(children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: tiles[i]),
                  ],
                ]);
              }
              return Wrap(spacing: 12, runSpacing: 12,
                  children: [for (final t in tiles) SizedBox(width: 140, child: t)]);
            }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final now = DateTime.now();
    const mNames = ['January','February','March','April','May','June',
                    'July','August','September','October','November','December'];

    return Scaffold(
      backgroundColor: null,
      body: RefreshIndicator(
        onRefresh: _load,
        color: _blue,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Header ────────────────────────────────────────────────────
            Row(children: [
              const NavBackButton(),
              const SizedBox(width: 8),
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.access_time_rounded, color: _blue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const Text('Attendance Calendar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ]),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Summary + date-range export card ─────────────────────────────
            _buildSummaryCard(context),
            const SizedBox(height: 16),

            // ── Calendar card ──────────────────────────────────────────────
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      icon: Icon(Icons.chevron_left_rounded,
                          color: cs.onSurface.withValues(alpha: 0.6)),
                      onPressed: () {
                        _month = DateTime(_month.year, _month.month - 1);
                        _load();
                      },
                    ),
                    Expanded(
                      child: Text(
                        '${mNames[_month.month - 1]} ${_month.year}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            color: cs.onSurface),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.chevron_right_rounded,
                          color: cs.onSurface.withValues(alpha: 0.6)),
                      onPressed: () {
                        _month = DateTime(_month.year, _month.month + 1);
                        _load();
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    for (final wd in const [
                      (DateTime.sunday, 'Sun'), (DateTime.monday, 'Mon'), (DateTime.tuesday, 'Tue'),
                      (DateTime.wednesday, 'Wed'), (DateTime.thursday, 'Thu'), (DateTime.friday, 'Fri'),
                      (DateTime.saturday, 'Sat'),
                    ])
                      _WDay(wd.$2, color: wd.$1 == _offWeekday ? _yellow : null),
                  ]),
                  const SizedBox(height: 4),
                  Divider(height: 1, color: cs.outlineVariant),
                  const SizedBox(height: 4),

                  if (_loading)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator(color: _blue, strokeWidth: 2)),
                    )
                  else
                    _CalendarGrid(
                      month: _month,
                      today: now,
                      statusColor: _statusColor,
                      onTap: _onTap,
                      selectedDay: _selectedDay,
                      selectedDayContent: _selectedDayContent(),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // ── Legend ─────────────────────────────────────────────────────
            Wrap(spacing: 20, runSpacing: 8, children: const [
              _Legend(color: _green,  label: 'Present'),
              _Legend(color: _purple, label: 'Late Coming'),
              _Legend(color: _magenta, label: 'Leave Applied'),
              _Legend(color: _teal,   label: 'Permission'),
              _Legend(color: _violet, label: 'Comp Off'),
              _Legend(color: _red,    label: 'Absent'),
              _Legend(color: _yellow, label: 'Holiday'),
            ]),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

// ── Calendar grid ─────────────────────────────────────────────────────────────
class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final Color? Function(int day) statusColor;
  final void Function(int day) onTap;
  final int? selectedDay;
  final Widget? selectedDayContent;

  const _CalendarGrid({
    required this.month,
    required this.today,
    required this.statusColor,
    required this.onTap,
    this.selectedDay,
    this.selectedDayContent,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) => _buildGrid(context, constraints));
  }

  Widget _buildGrid(BuildContext context, BoxConstraints constraints) {
    final cs          = Theme.of(context).colorScheme;
    final firstDay    = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final offset      = firstDay.weekday % 7;

    final cells = <Widget>[];
    for (int i = 0; i < offset; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final isToday = today.year == month.year &&
                      today.month == month.month &&
                      today.day == day;
      final sColor = statusColor(day);

      final decoration = isToday
          ? BoxDecoration(color: _blue, shape: BoxShape.circle)
          : sColor != null
              ? BoxDecoration(
                  color: sColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: sColor, width: 1.5),
                )
              : null;

      final textColor = isToday
          ? Colors.white
          : sColor != null
              ? sColor
              : cs.onSurface.withValues(alpha: 0.35);

      cells.add(Expanded(
        child: GestureDetector(
          onTap: () => onTap(day),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Center(
              child: Container(
                width: 32, height: 32,
                decoration: decoration,
                alignment: Alignment.center,
                child: Text('$day',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: (isToday || sColor != null)
                            ? FontWeight.w700 : FontWeight.w400,
                        color: textColor)),
              ),
            ),
          ),
        ),
      ));
    }

    final rem = (offset + daysInMonth) % 7;
    if (rem != 0) {
      for (int i = 0; i < 7 - rem; i++) {
        cells.add(const Expanded(child: SizedBox()));
      }
    }

    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      rows.add(Row(children: cells.sublist(i, i + 7)));
    }

    // Spliced directly into the row list (rather than floated via
    // Stack/Positioned) so its height pushes everything below it — the
    // legend row, etc. — down instead of overlapping it.
    final day = selectedDay;
    if (day != null && selectedDayContent != null) {
      final dayIndex = offset + day - 1;
      final rowIndex = dayIndex ~/ 7;
      final colIndex = dayIndex % 7;
      const cardWidth = 250.0;
      final colWidth  = constraints.maxWidth / 7;
      final maxLeft   = (constraints.maxWidth - cardWidth).clamp(0.0, double.infinity);
      final left      = (colIndex * colWidth + colWidth / 2 - cardWidth / 2)
          .clamp(0.0, maxLeft);
      rows.insert(rowIndex + 1, SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: left),
              child: SizedBox(width: cardWidth, child: selectedDayContent!),
            ),
          ),
        ),
      ));
    }

    return Column(children: rows);
  }
}

// ── Day detail dropdown card ──────────────────────────────────────────────────
class _DaySheet extends StatelessWidget {
  final String label;
  final AttendanceRecord? record;
  final bool isLeave;
  final bool isPermission;
  final bool isCompOff;
  final bool isAbsent;
  final CheckInRowStatus status;
  final VoidCallback onClose;

  const _DaySheet({
    required this.label,
    required this.record,
    required this.isLeave,
    this.isPermission = false,
    this.isCompOff = false,
    this.isAbsent = false,
    required this.status,
    required this.onClose,
  });

  static String? _dur(String inT, String outT) {
    try {
      final i = inT.split(':'), o = outT.split(':');
      final diff = (int.parse(o[0]) * 60 + int.parse(o[1])) -
                   (int.parse(i[0]) * 60 + int.parse(i[1]));
      if (diff <= 0) return null;
      final h = diff ~/ 60, m = diff % 60;
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final rec    = record;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hasAttendance = rec != null && rec.checkInTime.isNotEmpty;

    final String statusLabel;
    final Color  statusColor;
    if (hasAttendance) {
      statusLabel = switch (status.status) {
        CheckInStatus.onDuty => 'On Duty',
        CheckInStatus.late   => 'Late Coming',
        _                    => 'Present',
      };
      statusColor = switch (status.status) {
        CheckInStatus.onDuty => Colors.orange.shade700,
        CheckInStatus.late   => _purple,
        _                    => _green,
      };
    } else if (isLeave) {
      statusLabel = 'Leave Applied';
      statusColor = _magenta;
    } else if (isPermission) {
      statusLabel = 'Permission';
      statusColor = _teal;
    } else if (isCompOff) {
      statusLabel = 'Comp Off';
      statusColor = _violet;
    } else {
      statusLabel = 'Absent';
      statusColor = _red;
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 14, offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
          ),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 15,
                  color: cs.onSurface.withValues(alpha: 0.4)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(statusLabel,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: statusColor)),
        ),
        const SizedBox(height: 10),
        if (hasAttendance) ...[
          _detailRow(context, Icons.login_rounded, 'Check In', rec.checkInTime, _green),
          if (rec.checkInNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            _noteBlock(context, rec.checkInNote),
          ],
          if (status.status == CheckInStatus.permission) ...[
            const SizedBox(height: 6),
            _noteBlock(context,
                'Covered by permission (${permLabel(status.permMinutes)})'),
          ],
          const SizedBox(height: 8),
          if (rec.checkOutTime.isNotEmpty) ...[
            _detailRow(context, Icons.logout_rounded, 'Check Out', rec.checkOutTime,
                const Color(0xFF15803D)),
            if (rec.checkOutNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              _noteBlock(context, rec.checkOutNote),
            ],
            const SizedBox(height: 8),
            if (_dur(rec.checkInTime, rec.checkOutTime) != null)
              _detailRow(context, Icons.timelapse_rounded, 'Duration',
                  _dur(rec.checkInTime, rec.checkOutTime)!, _blue),
          ] else
            _detailRow(context, Icons.logout_rounded, 'Check Out', '— not recorded',
                cs.onSurface.withValues(alpha: 0.4)),
        ] else if (isLeave) ...[
          _noteRow(context, Icons.event_busy_rounded, _magenta, 'On approved leave'),
        ] else if (isPermission) ...[
          _noteRow(context, Icons.event_note_rounded, _teal, 'Approved permission — no attendance recorded'),
        ] else if (isCompOff) ...[
          _noteRow(context, Icons.swap_horiz_rounded, _violet, 'On approved Comp Off'),
        ] else if (isAbsent) ...[
          _noteRow(context, Icons.event_busy_rounded, _red, 'No attendance recorded'),
        ],
      ]),
    );
  }

  Widget _noteRow(BuildContext context, IconData icon, Color color, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, style: TextStyle(fontSize: 11.5,
            color: cs.onSurface.withValues(alpha: 0.7))),
      ),
    ]);
  }

  Widget _detailRow(BuildContext context, IconData icon, String label,
      String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 13, color: color),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 9.5,
            color: cs.onSurface.withValues(alpha: 0.5))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
            fontFamily: 'monospace', color: color)),
      ]),
    ]);
  }

  Widget _noteBlock(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 34),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5,
          color: cs.onSurface.withValues(alpha: 0.7))),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────
class _WDay extends StatelessWidget {
  final String label;
  final Color? color;
  const _WDay(this.label, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Text(label,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45))),
  );
}

class _RangeDateChip extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  const _RangeDateChip({required this.label, required this.date, required this.onTap});

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_rounded, size: 14, color: _blue),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text(_fmt(date),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _SummaryStatTile extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryStatTile({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$count',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85))),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 18, height: 18,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
    ),
    const SizedBox(width: 6),
    Text(label, style: TextStyle(fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65))),
  ]);
}
