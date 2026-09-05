import 'package:flutter/material.dart';

/// Month grid for picking a leave range, with holidays and the employee's
/// weekly off visibly marked.
///
/// Flutter's showDatePicker offers no hook for styling individual days, so
/// non-working days could not be shown while choosing. People built a request
/// across a holiday and only saw the reduced deduction afterwards, which read
/// as the app miscounting. Selecting them is still allowed — leave spanning a
/// holiday is legitimate, and the deduction already excludes them — they are
/// simply no longer invisible.
class LeaveMonthCalendar extends StatefulWidget {
  final DateTime? from;
  final DateTime? to;
  final DateTime firstDate;
  final DateTime lastDate;
  final Color color;

  /// True for a holiday or the employee's weekly off.
  final bool Function(DateTime) isNonWorking;

  /// Half-day requests occupy a single date, so the range end is suppressed.
  final bool singleDate;

  final void Function(DateTime from, DateTime? to) onRangeChanged;

  const LeaveMonthCalendar({
    super.key,
    required this.from,
    required this.to,
    required this.firstDate,
    required this.lastDate,
    required this.color,
    required this.isNonWorking,
    required this.onRangeChanged,
    this.singleDate = false,
  });

  @override
  State<LeaveMonthCalendar> createState() => _LeaveMonthCalendarState();
}

class _LeaveMonthCalendarState extends State<LeaveMonthCalendar> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final anchor = widget.from ?? DateTime.now();
    _month = DateTime(anchor.year, anchor.month);
  }

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime day) {
    final f = widget.from, t = widget.to;
    if (f == null || t == null) return false;
    final d = _d(day);
    return !d.isBefore(_d(f)) && !d.isAfter(_d(t));
  }

  bool _selectable(DateTime day) {
    final d = _d(day);
    return !d.isBefore(_d(widget.firstDate)) && !d.isAfter(_d(widget.lastDate));
  }

  void _tap(DateTime day) {
    final d = _d(day);
    if (!_selectable(d)) return;

    if (widget.singleDate) {
      widget.onRangeChanged(d, d);
      return;
    }
    // First tap sets the start; the next tap completes the range. Tapping a
    // date before the current start restarts rather than producing a backwards
    // range, which is what people do when they mis-tap.
    final f = widget.from, t = widget.to;
    if (f == null || t != null || d.isBefore(_d(f))) {
      widget.onRangeChanged(d, null);
    } else {
      widget.onRangeChanged(f, d);
    }
  }

  void _shift(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  static const _dow = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // DateTime.weekday is 1=Mon..7=Sun, and the grid starts on Monday.
    final leadingBlanks = firstOfMonth.weekday - 1;

    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _DayCell(
          date: DateTime(_month.year, _month.month, day),
          color: widget.color,
          isNonWorking: widget.isNonWorking(DateTime(_month.year, _month.month, day)),
          selectable: _selectable(DateTime(_month.year, _month.month, day)),
          isStart: _sameDay(widget.from, DateTime(_month.year, _month.month, day)),
          isEnd: _sameDay(widget.to, DateTime(_month.year, _month.month, day)),
          inRange: _inRange(DateTime(_month.year, _month.month, day)),
          onTap: () => _tap(DateTime(_month.year, _month.month, day)),
        ),
    ];

    return Column(children: [
      Row(children: [
        IconButton(
          onPressed: () => _shift(-1),
          icon: const Icon(Icons.chevron_left_rounded),
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: Text('${_monthNames[_month.month - 1]} ${_month.year}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          onPressed: () => _shift(1),
          icon: const Icon(Icons.chevron_right_rounded),
          visualDensity: VisualDensity.compact,
        ),
      ]),
      Row(
        children: [
          for (final d in _dow)
            Expanded(
              child: Center(
                child: Text(d,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF))),
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.1,
        children: cells,
      ),
      const SizedBox(height: 8),
      // A key, because a shaded cell means nothing on its own.
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Key(color: widget.color, label: 'Selected'),
        const SizedBox(width: 14),
        _Key(color: const Color(0xFFFEE2E2), label: 'Holiday / week off', border: true),
      ]),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final Color color;
  final bool isNonWorking, selectable, isStart, isEnd, inRange;
  final VoidCallback onTap;

  const _DayCell({
    required this.date,
    required this.color,
    required this.isNonWorking,
    required this.selectable,
    required this.isStart,
    required this.isEnd,
    required this.inRange,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEdge = isStart || isEnd;
    final Color bg;
    final Color fg;

    if (isEdge) {
      bg = color;
      fg = Colors.white;
    } else if (inRange) {
      bg = color.withValues(alpha: 0.16);
      fg = const Color(0xFF111827);
    } else if (isNonWorking) {
      // Distinct from selection so a holiday inside a chosen range still
      // reads as a holiday.
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFF991B1B);
    } else {
      bg = Colors.transparent;
      fg = selectable ? const Color(0xFF111827) : const Color(0xFFD1D5DB);
    }

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: selectable ? onTap : null,
          child: Center(
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isEdge ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final Color color;
  final String label;
  final bool border;
  const _Key({required this.color, required this.label, this.border = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: border ? Border.all(color: const Color(0xFFFCA5A5)) : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7280))),
        ],
      );
}
