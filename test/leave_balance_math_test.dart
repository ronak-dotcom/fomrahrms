import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_hrms/models/leave_store.dart';
import 'package:fomra_hrms/utils/leave_balance_math.dart';
import 'package:fomra_hrms/utils/leave_deduction.dart';

LeaveApplication _leave({
  required DateTime from,
  DateTime? to,
  int days = 1,
  String bucket = 'CL',
  LeaveApprovalStatus status = LeaveApprovalStatus.pending,
  bool halfDay = false,
  double lop = 0,
}) {
  final a = LeaveApplication(
    id: 'l-${from.toIso8601String()}-$bucket',
    employeeName: 'Test Person',
    department: 'Accounts',
    leaveType: 'Casual Leave',
    from: from,
    to: to ?? from,
    days: days,
    reason: 'test',
    appliedOn: DateTime(2026, 11, 1),
  )
    ..managerStatus = status
    ..leaveBucket = bucket
    ..isHalfDay = halfDay
    ..lopDays = lop;
  return a;
}

void main() {
  final today = DateTime(2026, 11, 14, 15, 30);

  group('usableAfterOutstanding — what the apply-leave form offers', () {
    test('days carried forward are offered in full: no false LOP warning', () {
      // leave_balance says 2 CL usable (one carried forward). The old
      // estimate allowed one CL per cycle and warned that a second day was
      // unpaid.
      final r = usableAfterOutstanding(
          usable: {'CL': 2, 'ML': 1, 'EL': 0}, myLeaves: const [], today: today);
      expect(r['CL'], 2);
    });

    test('a pending request is taken off before the next one is judged', () {
      final r = usableAfterOutstanding(
        usable: {'CL': 2},
        myLeaves: [_leave(from: DateTime(2026, 11, 20))],
        today: today,
      );
      expect(r['CL'], 1);
    });

    test('approved leave that has not started yet is taken off', () {
      final r = usableAfterOutstanding(
        usable: {'CL': 2},
        myLeaves: [_leave(from: DateTime(2026, 11, 20), status: LeaveApprovalStatus.approved)],
        today: today,
      );
      expect(r['CL'], 1);
    });

    test('approved leave already started is in leave_balance and not taken off twice', () {
      final r = usableAfterOutstanding(
        usable: {'CL': 2},
        myLeaves: [
          _leave(from: DateTime(2026, 11, 14), status: LeaveApprovalStatus.approved),
          _leave(from: DateTime(2026, 11, 3), status: LeaveApprovalStatus.approved),
        ],
        today: today,
      );
      expect(r['CL'], 2);
    });

    test('denied requests are ignored', () {
      final r = usableAfterOutstanding(
        usable: {'CL': 2},
        myLeaves: [_leave(from: DateTime(2026, 11, 20), status: LeaveApprovalStatus.denied)],
        today: today,
      );
      expect(r['CL'], 2);
    });

    test('a half day takes off half a day', () {
      final r = usableAfterOutstanding(
        usable: {'CL': 2},
        myLeaves: [_leave(from: DateTime(2026, 11, 20), halfDay: true)],
        today: today,
      );
      expect(r['CL'], 1.5);
    });

    test('only the paid part of a request is taken off, as leave_balance does', () {
      // Three days with one LOP draws two from CL.
      final r = usableAfterOutstanding(
        usable: {'CL': 5},
        myLeaves: [_leave(from: DateTime(2026, 11, 20), to: DateTime(2026, 11, 22), days: 3, lop: 1)],
        today: today,
      );
      expect(r['CL'], 3);
    });

    test('each bucket is kept separately, and never goes below zero', () {
      final r = usableAfterOutstanding(
        usable: {'CL': 1, 'ML': 4},
        myLeaves: [
          _leave(from: DateTime(2026, 11, 20), to: DateTime(2026, 11, 21), days: 2),
          _leave(from: DateTime(2026, 11, 24), bucket: 'ML'),
        ],
        today: today,
      );
      expect(r['CL'], 0);
      expect(r['ML'], 3);
    });

    test('buckets the balance does not report are left out', () {
      final r = usableAfterOutstanding(
        usable: {'CL': 2},
        myLeaves: [_leave(from: DateTime(2026, 11, 20), bucket: 'LOP')],
        today: today,
      );
      expect(r.keys, ['CL']);
    });
  });

  group('previewLeaveDeduction — must agree with apply_sandwich_policy()', () {
    // These two cases are also run against the database by
    // run_money_rule_tests(); if one side changes, both tests say so.
    test('Saturday to Monday is 3 days with the Sunday, the third is LOP', () {
      final d = previewLeaveDeduction(
        from: DateTime(2030, 10, 12),
        to: DateTime(2030, 10, 14),
        isHalfDay: false,
        employee: null,
        holidayIsoDates: const {},
        existingLeaves: const [],
      );
      expect(d.totalDays, 3);
      expect(d.sandwichDays, 1);
      expect(d.lopDays, 1);
    });

    test('a half day is 0.5 with nothing pulled in', () {
      final d = previewLeaveDeduction(
        from: DateTime(2030, 10, 8),
        to: DateTime(2030, 10, 8),
        isHalfDay: true,
        employee: null,
        holidayIsoDates: const {},
        existingLeaves: const [],
      );
      expect(d.totalDays, 0.5);
      expect(d.lopDays, 0);
    });

    test('two weekday days are two days with no LOP', () {
      final d = previewLeaveDeduction(
        from: DateTime(2030, 10, 8),
        to: DateTime(2030, 10, 9),
        isHalfDay: false,
        employee: null,
        holidayIsoDates: const {},
        existingLeaves: const [],
      );
      expect(d.totalDays, 2);
      expect(d.lopDays, 0);
    });

    test('Monday leave after a Saturday leave pulls in the Sunday between', () {
      final saturday = _leave(from: DateTime(2030, 10, 12), status: LeaveApprovalStatus.approved);
      final d = previewLeaveDeduction(
        from: DateTime(2030, 10, 14),
        to: DateTime(2030, 10, 14),
        isHalfDay: false,
        employee: null,
        holidayIsoDates: const {},
        existingLeaves: [saturday],
      );
      expect(d.totalDays, 2);
      expect(d.sandwichDays, 1);
    });
  });
}
