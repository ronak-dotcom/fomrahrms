import 'package:flutter/material.dart';
import '../utils/attendance_cycle.dart';
import 'package:go_router/go_router.dart';
import '../models/app_user.dart';
import '../models/attendance_store.dart';
import '../models/leave_store.dart';
import '../models/office_timing.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../utils/checkin_status.dart';
import '../utils/tenure.dart';
import '../utils/weekly_off.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

// Fixed status colors — not theme-driven. Chosen as a set (not just
// pairwise) so every status stays distinguishable, including for
// colorblind users; see scripts/validate_palette.js in the dataviz skill.
Color get _blue    => AppTheme.primaryBlue;
const _green   = Color(0xFF008300);
const _purple  = Color(0xFF2A78D6); // "Late Coming"
const _red     = Color(0xFFE34948);
const _yellow  = Color(0xFFEDA100); // "Holiday"
const _magenta = Color(0xFFE87BA4); // "Leave Applied"
const _teal    = Color(0xFF1BAF7A); // "Permission"
const _violet  = Color(0xFF4A3AA7); // "Comp Off"

class MyAttendancePage extends StatefulWidget {
  final String checkInRoute;
  // When true, renders just the content (no Scaffold/back-button/page title)
  // so it can be embedded inside another page, e.g. MyAttendanceAndLeavePage.
  final bool embedded;
  const MyAttendancePage({
    super.key,
    this.checkInRoute = '/employee/attendance/check-in-out',
    this.embedded = false,
  });

  @override
  State<MyAttendancePage> createState() => _MyAttendancePageState();
}

class _MyAttendancePageState extends State<MyAttendancePage> {
  late DateTime _month;
  bool _loading = true;
  AttendanceRecord? _todayRecord;
  Map<int, AttendanceRecord> _attendance = {};
  Set<int> _leaveDays = {};
  Set<int> _permissionDays = {};
  Set<int> _compOffDays = {};
  Set<int> _holidayDays = {};
  List<LeaveApplication> _leaveApps = [];
  int? _selectedDay;
  int _offWeekday = DateTime.sunday;

  /// Records for the ATTENDANCE CYCLE (26th–25th) containing the shown month.
  ///
  /// The calendar grid stays month-based — a grid is inherently a month — but
  /// the summary must count the period people are actually paid and assessed
  /// on. Kept separate rather than reusing _attendance, which is keyed by
  /// day-of-month and cannot represent a span crossing two months: the 3rd
  /// appears twice in a cycle.
  List<AttendanceRecord> _cycleRecords = [];
  DateTime? _joiningDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SupabaseService.fetchTodayAttendance(UserSession.employeeId),
      SupabaseService.fetchAttendanceForMonth(UserSession.employeeId, _month.year, _month.month),
      SupabaseService.fetchHolidays(_month.year),
      SupabaseService.fetchLeaveApplications(),
      UserStore.load(),
      SupabaseService.fetchAttendanceForRange(
        UserSession.employeeId,
        attendanceCycleStart(_month),
        attendanceCycleEnd(_month),
      ),
    ]);
    if (!mounted) return;
    // results[5]: the range fetch is appended AFTER UserStore.load(), which
    // is results[4]. Casting the user list to AttendanceRecord would throw.
    _cycleRecords = results[5] as List<AttendanceRecord>;

    final today    = results[0] as AttendanceRecord?;
    final records  = results[1] as List<AttendanceRecord>;
    final holidays = results[2] as List<Map<String, dynamic>>;
    final leaveApps = results[3] as List<LeaveApplication>;
    final users     = results[4] as List<AppUser>;
    final me = users.where((u) => u.name == UserSession.name).firstOrNull;
    final offWeekday = weeklyOffWeekdayFor(me?.effectiveWeeklyOffDay ?? 'Sunday');
    final joiningDate = parseFlexibleDate(me?.dateOfJoining ?? '');

    if (today != null && today.checkInTime.isNotEmpty && today.checkOutTime.isEmpty) {
      AttendanceStore.isCheckedIn = true;
    }

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
    // together as "on leave" (which used to make even a same-day approved
    // Permission render as a full "Absent" day).
    final Set<int> leaves = {}, permissions = {}, compOffs = {};
    for (final app in leaveApps) {
      if (app.employeeName != UserSession.name) continue;
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
      _todayRecord     = today;
      _attendance      = map;
      _leaveDays       = leaves;
      _permissionDays  = permissions;
      _compOffDays     = compOffs;
      _holidayDays     = holidayDays;
      _leaveApps       = leaveApps;
      _offWeekday      = offWeekday;
      _joiningDate     = joiningDate;
      _loading         = false;
      _selectedDay     = null;
    });
  }

  static int? _dayOf(String date) {
    try { return int.parse(date.split('/').first); } catch (_) { return null; }
  }

  CheckInRowStatus _status(int day) {
    final r = _attendance[day];
    if (r == null) return const CheckInRowStatus(CheckInStatus.none, 0);
    final date = DateTime(_month.year, _month.month, day);
    return checkInStatusFor(r.checkInTime, date, UserSession.name, _leaveApps,
        OfficeTimingStore.scheduleForCurrentUser(),
        lateWaived: r.lateWaived, onDuty: r.onDuty);
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

  // Returns the status color for a calendar day (null = no highlight).
  // Precedence: actual attendance > holiday > leave > permission > comp off > absent.
  Color? _statusColor(int day) {
    // Attendance takes visual priority (worked on holiday → show attendance color)
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
    final rec         = _attendance[day];
    final isLeave      = _leaveDays.contains(day);
    final isPermission = _permissionDays.contains(day);
    final isCompOff    = _compOffDays.contains(day);
    final missed       = _isMissedDay(day);
    if (rec == null && !isLeave && !isPermission && !isCompOff && !missed) return;

    // Was: toggle _selectedDay, which rendered the detail INLINE beneath the
    // calendar and pushed everything below it down the page. A dialog keeps
    // the grid still and gives the detail room — same reasoning as
    // announcements.
    setState(() => _selectedDay = day);
    final content = _selectedDayContent();
    if (content == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: SingleChildScrollView(child: content),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedDay = null);
    });
  }

  // Builds the inline dropdown card for the currently selected day, shown
  // right under its row in the calendar grid — null when nothing selected.
  // ── Cycle summary ────────────────────────────────────────────────────────
  // "This period: how many lates, leaves" — counted over the 26th-25th cycle,
  // which is the period people are actually paid and assessed on.

  int get _cyclePresent =>
      _cycleRecords.where((r) => r.checkInTime.isNotEmpty).length;

  int get _cycleLate => _cycleRecords.where((r) {
        if (r.checkInTime.isEmpty) return false;
        final d = _parseSlash(r.date);
        if (d == null) return false;
        return checkInStatusFor(r.checkInTime, d, UserSession.name, _leaveApps,
                OfficeTimingStore.scheduleForCurrentUser(),
                lateWaived: r.lateWaived)
            .status == CheckInStatus.late;
      }).length;

  /// Excused lateness, shown separately rather than hidden — an employee
  /// should be able to see that a late arrival was written off, not just that
  /// the count went down.
  int get _cycleWaived =>
      _cycleRecords.where((r) => r.lateWaived).length;

  double get _cycleLeaveDays {
    final start = attendanceCycleStart(_month);
    final end = attendanceCycleEnd(_month);
    return _leaveApps
        .where((a) =>
            a.employeeName == UserSession.name &&
            a.leaveType != 'Permission' &&
            a.managerStatus == LeaveApprovalStatus.approved &&
            !a.from.isAfter(end) &&
            !a.to.isBefore(start))
        .fold<double>(0, (sum, a) => sum + a.days);
  }

  int get _cyclePermissionMinutes => _leaveApps
      .where((a) =>
          a.employeeName == UserSession.name &&
          a.leaveType == 'Permission' &&
          a.managerStatus != LeaveApprovalStatus.denied &&
          sameAttendanceCycle(a.from, _month))
      .fold<int>(0, (sum, a) => sum + LeaveStore.permMinutesFromReason(a.reason));

  static DateTime? _parseSlash(String d) {
    final p = d.split('/');
    if (p.length != 3) return null;
    return DateTime.tryParse('${p[2]}-${p[1]}-${p[0]}');
  }

  Widget _cycleSummary() {
    final range = attendanceCycleRange(_month);
    final tiles = <(String, String, IconData, Color)>[
      ('Present', '$_cyclePresent', Icons.check_circle_rounded, Colors.green.shade600),
      ('Late', '$_cycleLate', Icons.running_with_errors_rounded, Colors.orange.shade700),
      ('Leaves', _cycleLeaveDays == _cycleLeaveDays.roundToDouble()
              ? '${_cycleLeaveDays.toInt()}'
              : _cycleLeaveDays.toStringAsFixed(1),
          Icons.event_busy_rounded, AppTheme.accentBlue),
      ('Permission', '${_cyclePermissionMinutes}m', Icons.timer_rounded, Colors.purple.shade400),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.insights_rounded, size: 16, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          Text('This pay cycle',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryBlue)),
          const SizedBox(width: 8),
          // The range is spelled out so the figures cannot be misread as
          // month-to-date.
          Text(range, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 12,
          children: tiles
              .map((t) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.$3, size: 15, color: t.$4),
                    const SizedBox(width: 6),
                    Text(t.$2,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: t.$4)),
                    const SizedBox(width: 4),
                    Text(t.$1,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ]))
              .toList(),
        ),
        if (_cycleWaived > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$_cycleWaived late arrival${_cycleWaived == 1 ? '' : 's'} excused by Management '
            '— not counted above.',
            style: TextStyle(fontSize: 11.5, color: Colors.green.shade700),
          ),
        ],
      ]),
    );
  }

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

  Widget _checkInOutAction(bool narrow) {
    if (narrow) {
      return IconButton(
        tooltip: 'Check In / Out',
        onPressed: () => context.go(widget.checkInRoute),
        icon: const Icon(Icons.fingerprint_rounded),
        style: IconButton.styleFrom(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: () => context.go(widget.checkInRoute),
      icon: const Icon(Icons.fingerprint_rounded, size: 16),
      label: const Text('Check In / Out', style: TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final narrow = MediaQuery.of(context).size.width < 600;
    const mNames = ['January','February','March','April','May','June',
                    'July','August','September','October','November','December'];

    final header = widget.embedded
        ? Row(children: [
            if (!narrow) ...[
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.access_time_rounded, color: _blue, size: 18),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text('Attendance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            SizedBox(width: narrow ? 4 : 8),
            _checkInOutAction(narrow),
          ])
        : Row(children: [
            const NavBackButton(),
            SizedBox(width: narrow ? 4 : 8),
            if (!narrow) ...[
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.access_time_rounded, color: _blue, size: 22),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Attendance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium),
                if (!narrow) ...[
                  const SizedBox(height: 2),
                  const Text('Attendance records',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ],
              ]),
            ),
            SizedBox(width: narrow ? 4 : 8),
            _checkInOutAction(narrow),
          ]);

    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Header ────────────────────────────────────────────────────
            header,
            const SizedBox(height: 20),

            // ── Today card ─────────────────────────────────────────────────
            _TodayCard(record: _todayRecord,
                isDark: Theme.of(context).brightness == Brightness.dark),
            const SizedBox(height: 24),

            // ── Pay-cycle summary ──────────────────────────────────────────
            // Counted over the 26th–25th cycle, not the calendar month: that
            // is the period people are paid and assessed on, and there was no
            // way to see it anywhere in the app.
            if (!_loading) _cycleSummary(),

            // ── Calendar card ──────────────────────────────────────────────
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                child: Column(children: [
                  // Month navigation
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
                          color: (_month.year == now.year && _month.month == now.month)
                              ? cs.onSurface.withValues(alpha: 0.18)
                              : cs.onSurface.withValues(alpha: 0.6)),
                      onPressed: (_month.year == now.year && _month.month == now.month)
                          ? null
                          : () {
                              _month = DateTime(_month.year, _month.month + 1);
                              _load();
                            },
                    ),
                  ]),
                  const SizedBox(height: 4),

                  // Weekday labels — the employee's weekly-off column (Sunday,
                  // unless Sales reassigned it) is tinted the holiday yellow.
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
                      holidayDays: _holidayDays,
                      onTap: _onTap,
                      selectedDay: _selectedDay,
                      // Detail now opens in a dialog; nothing renders inline.
                      selectedDayContent: null,
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
          ]);

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: null,
      body: RefreshIndicator(
        onRefresh: _load,
        color: _blue,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: content,
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
  final Set<int> holidayDays;
  final void Function(int day) onTap;
  final int? selectedDay;
  final Widget? selectedDayContent;

  const _CalendarGrid({
    required this.month,
    required this.today,
    required this.statusColor,
    required this.holidayDays,
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
    final offset      = firstDay.weekday % 7; // Sun=0 … Sat=6

    final cells = <Widget>[];
    for (int i = 0; i < offset; i++) {
      cells.add(const Expanded(child: SizedBox()));
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final isToday = today.year == month.year &&
                      today.month == month.month &&
                      today.day == day;
      final sColor = statusColor(day);

      // Status ring (green/purple/red) around the number regardless of today.
      // Today gets a small blue dot above the number instead of a solid blue circle.
      final numWidget = Container(
        width: 32, height: 32,
        decoration: sColor != null
            ? BoxDecoration(
                color: sColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: sColor, width: 1.8),
              )
            : null,
        alignment: Alignment.center,
        child: Text('$day',
            style: TextStyle(
                fontSize: 13,
                fontWeight: (isToday || sColor != null) ? FontWeight.w700 : FontWeight.w400,
                color: isToday && sColor == null
                    ? _blue
                    : sColor ?? cs.onSurface.withValues(alpha: 0.35))),
      );

      cells.add(Expanded(
        child: GestureDetector(
          onTap: () => onTap(day),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Center(
              child: isToday
                  ? Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        numWidget,
                        // Small dot above the number
                        Positioned(
                          top: -5,
                          child: Container(
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                                color: _blue, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    )
                  : numWidget,
            ),
          ),
        ),
      ));
    }

    // Trailing blanks
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
          if (status.status == CheckInStatus.permission) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.event_note_rounded, size: 13, color: _blue),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Covered by permission (${permLabel(status.permMinutes)})',
                    style: TextStyle(fontSize: 10.5, color: cs.onSurface.withValues(alpha: 0.7))),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          if (rec.checkOutTime.isNotEmpty) ...[
            _detailRow(context, Icons.logout_rounded, 'Check Out', rec.checkOutTime,
                const Color(0xFF15803D)),
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

        // The reason typed at check-in was never shown anywhere. An employee
        // explaining a late arrival or an off-site check-in had no way to see
        // that their explanation was recorded — and no way to check what it
        // said if it was later questioned.
        if ((record?.checkInNote ?? '').isNotEmpty)
          _noteRow(context, Icons.chat_bubble_outline_rounded, _blue,
              'Your reason: ${record?.checkInNote ?? ''}'),
        if ((record?.checkOutNote ?? '').isNotEmpty)
          _noteRow(context, Icons.chat_bubble_outline_rounded, _blue,
              'Check-out reason: ${record?.checkOutNote ?? ''}'),

        // A waived late arrival should say so, rather than silently not
        // counting.
        // `record` is a nullable FIELD, and Dart does not promote fields — a
        // bare record.lateWaiverReason after record! is a compile error. Read
        // it once into a local instead of scattering ! through the expression.
        if (record?.lateWaived ?? false)
          Builder(builder: (ctx) {
            final reason = record?.lateWaiverReason ?? '';
            return _noteRow(ctx, Icons.verified_rounded, _green,
                reason.isEmpty
                    ? 'Late arrival excused by Management'
                    : 'Excused by Management: $reason');
          }),
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
}

// ── Today's status card ───────────────────────────────────────────────────────
class _TodayCard extends StatelessWidget {
  final AttendanceRecord? record;
  final bool isDark;
  const _TodayCard({required this.record, required this.isDark});

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
    final rec = record;

    if (rec == null || rec.checkInTime.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.orange.withValues(alpha: 0.1) : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? Colors.orange.shade700 : Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(Icons.schedule_rounded, size: 16,
              color: isDark ? Colors.orange.shade300 : Colors.orange.shade700),
          const SizedBox(width: 8),
          Text('Today — Not checked in yet',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.orange.shade200 : Colors.orange.shade800)),
        ]),
      );
    }

    if (rec.checkOutTime.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.green.withValues(alpha: 0.1) : Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? Colors.green.shade700 : Colors.green.shade200),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_rounded, size: 16,
              color: isDark ? Colors.green.shade300 : _green),
          const SizedBox(width: 8),
          Text('Checked in at ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: isDark ? Colors.green.shade200 : _green)),
          Text(rec.checkInTime, style: TextStyle(fontSize: 15,
              fontWeight: FontWeight.w800, fontFamily: 'monospace',
              color: isDark ? Colors.green.shade100 : Colors.green.shade900)),
          const Spacer(),
          Container(width: 7, height: 7,
              decoration: BoxDecoration(color: Colors.green.shade400,
                  shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text('Active', style: TextStyle(fontSize: 11,
              color: isDark ? Colors.green.shade400 : Colors.green.shade600)),
        ]),
      );
    }

    final dur  = _dur(rec.checkInTime, rec.checkOutTime);
    final blue = isDark ? Colors.blue.shade300 : _blue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? _blue.withValues(alpha: 0.1) : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? Colors.blue.shade700 : Colors.blue.shade200),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_rounded, size: 14, color: blue),
          const SizedBox(width: 6),
          Text('Today — Attendance Complete',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: blue)),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _tb('Check In',  rec.checkInTime,  blue),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: blue),
          ),
          _tb('Check Out', rec.checkOutTime, blue),
          if (dur != null) ...[
            const SizedBox(width: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.blue.withValues(alpha: 0.2)
                    : Colors.blue.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(dur, style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700, color: blue)),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _tb(String label, String time, Color color) => Column(children: [
    Text(label, style: TextStyle(fontSize: 10,
        color: color.withValues(alpha: 0.7))),
    const SizedBox(height: 2),
    Text(time, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
        fontFamily: 'monospace', color: color)),
  ]);
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
