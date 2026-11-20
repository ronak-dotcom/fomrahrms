import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_hrms/models/leave_store.dart';

/// permMinutesFromReason() reads a permission's duration out of its reason
/// string, built in apply_permission_page.dart as:
///
///     'Permission: $duration | $reasonText | $description'
///
/// The earlier version scanned the whole string, so the employee's own
/// description could steer the charge ("2 Hours | back in 30 Minutes" was
/// charged 30) and anything unrecognised defaulted to an hour. It now reads
/// only the part before the first '|', rejects the withdrawn 90-minute slot,
/// and returns 0 for anything it does not recognise. These tests were
/// characterisation tests for those bugs; they now pin the fix.
///
/// The database (set_and_check_permission_minutes) is the authority for the
/// minutes actually charged; this is the client-side reading.
void main() {
  group('permMinutesFromReason', () {
    test('reads each permitted duration', () {
      expect(LeaveStore.permMinutesFromReason('Permission: 30 Minutes | Bank Work'), 30);
      expect(LeaveStore.permMinutesFromReason('Permission: 1 Hour | Bank Work'), 60);
      expect(LeaveStore.permMinutesFromReason('Permission: 2 Hours | Bank Work'), 120);
    });

    test('the permitted durations are 30, 60 and 120 minutes', () {
      expect(LeaveStore.permittedPermissionMinutes, [30, 60, 120]);
    });

    test('the employee\'s description cannot change the charge', () {
      const asWritten = 'Permission: 2 Hours | Personal Work | back in 30 Minutes';
      expect(LeaveStore.permMinutesFromReason(asWritten), 120);
    });

    test('an approved 2-hour permission covers a 90-minute late arrival', () {
      const approved = 'Permission: 2 Hours | Doctor / Medical | should be back in 30 Minutes';
      expect(LeaveStore.permMinutesFromReason(approved) >= 90, isTrue);
    });

    test('the withdrawn 90-minute slot is rejected, however it is written', () {
      expect(LeaveStore.permMinutesFromReason('Permission: 1½ Hours | X'), 0);
      expect(LeaveStore.permMinutesFromReason('Permission: 1 Hour 30 Minutes | X'), 0);
      expect(LeaveStore.permMinutesFromReason('Permission: 90 Minutes | X'), 0);
    });

    test('an unrecognised duration is 0, not a silent hour', () {
      expect(LeaveStore.permMinutesFromReason('Permission: 45 Minutes | X'), 0);
      expect(LeaveStore.permMinutesFromReason(''), 0);
    });

    test('the cycle quota adds up what was actually taken', () {
      const twoHours = 'Permission: 2 Hours | Personal Work | 30 Minutes tops';
      final charged = List.filled(4, twoHours)
          .map(LeaveStore.permMinutesFromReason)
          .fold<int>(0, (a, b) => a + b);
      expect(charged, 4 * 120);
    });
  });
}
