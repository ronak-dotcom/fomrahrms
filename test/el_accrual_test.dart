import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_hrms/models/app_user.dart';
import 'package:fomra_hrms/utils/el_accrual.dart';

AppUser _eligibleFrom(String isoOrSlashDate, {String lastAvailed = ''}) => AppUser(
      name: 'Test',
      email: 'test@example.invalid',
      employeeId: 'TEST001',
      designation: 'Test Designation',
      role: 'Employee',
      elEligibleAt: isoOrSlashDate,
      elLastAvailedAt: lastAvailed,
      onrollConfirmedAt: '2020-01-01',
    );

void main() {
  group('elAccruedFor — the month-boundary defect this replaces', () {
    // The old arithmetic was:
    //   (now.year - ref.year) * 12 + (now.month - ref.month)
    // which counts a month as soon as the month NUMBER changes.

    test('eligible 31 Jan has NOT accrued a month by 1 Feb', () {
      final user = _eligibleFrom('2026-01-31');
      // Old behaviour returned 1 here — a full month's leave after one day.
      expect(elAccruedFor(user, asOf: DateTime(2026, 2, 1)), 0);
    });

    test('eligible 1 Jan HAS accrued a month by 1 Feb', () {
      final user = _eligibleFrom('2026-01-01');
      expect(elAccruedFor(user, asOf: DateTime(2026, 2, 1)), 1);
    });

    test('eligible 1 Jan has NOT accrued by 31 Jan', () {
      final user = _eligibleFrom('2026-01-01');
      // Old behaviour also returned 0 here, so a 31-Jan and a 1-Jan employee
      // were treated 30 days apart for the sake of one calendar day.
      expect(elAccruedFor(user, asOf: DateTime(2026, 1, 31)), 0);
    });

    test('two employees one day apart are no longer a month apart', () {
      final jan31 = _eligibleFrom('2026-01-31');
      final feb01 = _eligibleFrom('2026-02-01');
      final asOf = DateTime(2026, 2, 15);

      expect(elAccruedFor(jan31, asOf: asOf), elAccruedFor(feb01, asOf: asOf));
    });
  });

  group('elAccruedFor — month-length edge cases', () {
    test('eligible 31 Jan completes on 28 Feb, the last day of a short month', () {
      final user = _eligibleFrom('2026-01-31');
      expect(elAccruedFor(user, asOf: DateTime(2026, 2, 27)), 0);
      expect(elAccruedFor(user, asOf: DateTime(2026, 2, 28)), 1);
    });

    test('accrues one per month thereafter', () {
      final user = _eligibleFrom('2026-01-15');
      expect(elAccruedFor(user, asOf: DateTime(2026, 4, 15)), 3);
      expect(elAccruedFor(user, asOf: DateTime(2027, 1, 15)), 12);
    });
  });

  group('elAccruedFor — inputs', () {
    test('accepts dd/MM/yyyy as well as ISO', () {
      // These columns hold ISO for some employees and dd/MM/yyyy for others.
      // DateTime.tryParse returns null on the latter, which silently zeroed
      // the accrual for anyone stored in slash format.
      final iso = _eligibleFrom('2026-01-15');
      final slash = _eligibleFrom('15/01/2026');
      final asOf = DateTime(2026, 4, 15);

      expect(elAccruedFor(slash, asOf: asOf), elAccruedFor(iso, asOf: asOf));
      expect(elAccruedFor(slash, asOf: asOf), 3);
    });

    test('last-availed date takes precedence over the eligibility date', () {
      final user = _eligibleFrom('2026-01-01', lastAvailed: '2026-03-01');
      expect(elAccruedFor(user, asOf: DateTime(2026, 5, 1)), 2);
    });

    test('no eligibility date means no accrual', () {
      expect(elAccruedFor(_eligibleFrom(''), asOf: DateTime(2026, 5, 1)), 0);
    });

    test('an unparseable date accrues nothing rather than throwing', () {
      expect(elAccruedFor(_eligibleFrom('not a date'), asOf: DateTime(2026, 5, 1)), 0);
    });

    test('a null user accrues nothing', () {
      expect(elAccruedFor(null), 0);
    });

    test('a future eligibility date never accrues negatively', () {
      final user = _eligibleFrom('2027-01-01');
      expect(elAccruedFor(user, asOf: DateTime(2026, 5, 1)), 0);
    });
  });
}
