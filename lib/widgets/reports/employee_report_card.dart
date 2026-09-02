import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../models/attendance_store.dart';
import '../../models/leave_store.dart';
import '../../models/office_timing.dart';
import '../../theme/app_theme.dart';
import '../../utils/attendance_day.dart';
import '../../utils/checkin_status.dart';

/// One employee's record over the selected range.
///
/// Reports & Analytics could only be narrowed by department, so there was no
/// way to look at an individual — the headline counts were the only view of
/// anybody. This is the day-by-day detail behind those counts, matching the
/// columns of the attendance sheet HR keeps by hand: days worked, leave taken,
/// LOP, late arrivals and permission.
class EmployeeReportCard extends StatelessWidget {
  final AppUser employee;
  final DateTimeRange range;
  final List<AttendanceRecord> records;
  final List<LeaveApplication> leaveApps;
  final Set<String> holidayIsoDates;

  const EmployeeReportCard({
    super.key,
    required this.employee,
    required this.range,
    required this.records,
    required this.leaveApps,
    required this.holidayIsoDates,
  });

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _slash(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// One row per day in the range, with what happened and why.
  List<_Day> _days() {
    final byDate = {for (final r in records) r.date: r};
    final schedule = OfficeTimingStore.scheduleForUser(employee);
    final out = <_Day>[];

    for (var d = range.start;
        !d.isAfter(range.end);
        d = d.add(const Duration(days: 1))) {
      final rec = byDate[_slash(d)];

      if (rec != null && rec.checkInTime.isNotEmpty) {
        final st = checkInStatusFor(
            rec.checkInTime, d, employee.name, leaveApps, schedule,
            lateWaived: rec.lateWaived, onDuty: rec.onDuty);
        final late = st.status == CheckInStatus.late;
        out.add(_Day(
          date: d,
          label: late ? 'Late' : 'Present',
          detail: '${rec.checkInTime}'
              '${rec.checkOutTime.isNotEmpty ? ' – ${rec.checkOutTime}' : ''}'
              '${rec.lateWaived ? '  · excused' : ''}',
          color: late ? Colors.orange.shade700 : Colors.green.shade700,
          isLate: late,
          worked: true,
        ));
        continue;
      }

      // No attendance row — the reason matters, and "absent" is only one of
      // the possibilities.
      final reason = classifyMissingAttendance(
        employee: employee,
        date: d,
        holidayDates: holidayIsoDates,
        leaveApps: leaveApps,
      );
      out.add(switch (reason) {
        NonWorkingReason.weeklyOff => _Day(
            date: d,
            label: 'Weekly Off',
            color: Colors.grey.shade500),
        NonWorkingReason.holiday => _Day(
            date: d, label: 'Holiday', color: const Color(0xFFEDA100)),
        NonWorkingReason.onLeave => _Day(
            date: d,
            label: 'Leave',
            color: AppTheme.accentBlue,
            onLeave: true),
        NonWorkingReason.notTracked => _Day(
            date: d, label: 'Not tracked', color: Colors.grey.shade400),
        NonWorkingReason.absent => _Day(
            date: d, label: 'Absent', color: Colors.red.shade600, absent: true),
      });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final days = _days();
    final worked = days.where((d) => d.worked).length;
    final late = days.where((d) => d.isLate).length;
    final onLeave = days.where((d) => d.onLeave).length;
    final absent = days.where((d) => d.absent).length;

    // Leave and LOP come from the applications, not the day rows: a single
    // request can carry sandwiched days and LOP that no attendance row shows.
    final inRange = leaveApps.where((a) =>
        a.employeeName.trim().toLowerCase() ==
            employee.name.trim().toLowerCase() &&
        a.managerStatus == LeaveApprovalStatus.approved &&
        !a.from.isAfter(range.end) &&
        !a.to.isBefore(range.start));
    final leaveDays =
        inRange.where((a) => a.leaveType != 'Permission').fold<double>(0, (s, a) => s + a.days);
    final permissionCount =
        inRange.where((a) => a.leaveType == 'Permission').length;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
              child: Text(
                employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(employee.name,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
                Text(
                  [
                    employee.employeeId,
                    if (employee.department.isNotEmpty) employee.department,
                    if (employee.designation.isNotEmpty) employee.designation,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ]),
            ),
          ]),
        ),

        // Totals, in the same terms as the sheet HR keeps by hand.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 18, runSpacing: 10, children: [
            _stat('Days Worked', '$worked', Colors.green.shade700),
            _stat('Late', '$late', Colors.orange.shade700),
            _stat('Leave', leaveDays == leaveDays.roundToDouble()
                ? '${leaveDays.toInt()}'
                : leaveDays.toStringAsFixed(1), AppTheme.accentBlue),
            _stat('Permission', '$permissionCount', Colors.purple.shade400),
            _stat('Absent', '$absent', Colors.red.shade600),
            _stat('On Leave (days)', '$onLeave', Colors.blueGrey),
          ]),
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: Colors.grey.shade200),

        // Day by day. Capped so a long range cannot render thousands of rows;
        // the totals above still cover the whole period.
        ...days.take(62).map((d) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(children: [
                SizedBox(
                  width: 92,
                  child: Text(_slash(d.date),
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: d.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(d.label,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: d.color)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(d.detail,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
              ]),
            )),
        if (days.length > 62)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Showing the first 62 days. Narrow the date range to see the rest — '
              'the totals above cover the whole period.',
              style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic),
            ),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ]);
}

class _Day {
  final DateTime date;
  final String label;
  final String detail;
  final Color color;
  final bool worked;
  final bool isLate;
  final bool onLeave;
  final bool absent;

  const _Day({
    required this.date,
    required this.label,
    required this.color,
    this.detail = '',
    this.worked = false,
    this.isLate = false,
    this.onLeave = false,
    this.absent = false,
  });
}
