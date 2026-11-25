import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_hrms/models/payslip_store.dart';

/// Payslips issued by the database carry the payroll engine's totals; the
/// app shows those, not a sum of the lines (Nov 2026, agreed with HR).
void main() {
  Map<String, dynamic> row({Map<String, dynamic> extra = const {}}) => {
        'id': 'FD-06_2026-10',
        'employee_id': 'FD-06',
        'month_year': '2026-10',
        'emp_name': 'Sample',
        'working_days': 30,
        'days_worked': '30',
        'lop_days': '0',
        'gross_pay': '20207.80',
        'basic': '2751', 'da': '7353', 'hra': '1100.40', 'conveyance_allowance': '4378',
        'other_allowance': '3415', 'educational_allowance': '200', 'lta': '1010.40',
        'professional_tax': '208', 'epf': '0', 'esi': '0', 'tds': '0',
        'late_deductions': '0', 'generated_at': '2026-11-20T10:00:00Z',
        ...extra,
      };

  test('an issued payslip shows the rounded net pay HR agreed (19,999.80 -> 20,000)', () {
    final p = Payslip.fromJson(row(extra: {
      'source': 'engine', 'status': 'draft', 'net_pay': '20000',
      'gross_earned': '20207.80', 'total_deductions': '208', 'rounded_off': '0.20',
    }));
    expect(p.netPay, 20000);
    expect(p.roundedOff, closeTo(0.20, 1e-9));
    expect(p.isFromEngine, isTrue);
    expect(p.isDraft, isTrue);
  });

  // HR, 25 Nov 2026: monthly gross less PF, ESI, PT and any LOP or late
  // equals net pay. Saurabh Chandak's October 2026 payslip: 2.5 days unpaid
  // leave out of 30.
  test('an issued payslip restates as full gross less LOP and statutory deductions', () {
    final p = Payslip.fromJson({
      'id': 'FD-01_2026-10', 'employee_id': 'FD-01', 'month_year': '2026-10',
      'emp_name': 'Saurabh Chandak', 'working_days': 30, 'days_worked': '27.5',
      'lop_days': '2.5', 'gross_pay': '85208',
      'basic': '32313.42', 'da': '6740.25', 'hra': '12925.37', 'lta': '3905.37',
      'other_allowance': '10769.92', 'conveyance_allowance': '11269.5',
      'educational_allowance': '183.33', 'special_allowance': '0',
      'professional_tax': '208', 'epf': '0', 'esi': '0', 'tds': '0',
      'late_deductions': '0', 'generated_at': '2026-11-20T10:00:00Z',
      'source': 'engine', 'status': 'draft', 'gross_earned': '78107.15',
      'total_deductions': '208', 'net_pay': '77899', 'rounded_off': '-0.15',
      'leave_lop': '2.5', 'late_lop': '0', 'permission_lop': '0',
    });
    expect(p.showsFullGross, isTrue);
    final earnings = p.fullEarnings.fold<double>(0, (s, e) => s + e.$2);
    expect(earnings, closeTo(85208, 0.001));
    final c = p.payCuts;
    expect(c.lopDays, 2.5);
    expect(c.lop, closeTo(7100.85, 0.001));
    expect(c.late, 0);
    expect(c.outside, 0);
    expect(p.fullTotalDeductions, closeTo(7308.85, 0.001));
    expect(p.fullRoundedOff, closeTo(-0.15, 0.001));
    expect(p.grossPay - p.fullTotalDeductions + p.fullRoundedOff, closeTo(p.netPay, 0.001));
    expect(p.fullDeductions.first.$1, 'Loss of Pay (2.5 days)');
  });

  test('no LOP line when no day was lost, even with paise of rounding', () {
    final p = Payslip.fromJson(row(extra: {
      'source': 'engine', 'status': 'draft', 'net_pay': '20000',
      'gross_earned': '20207.80', 'total_deductions': '208', 'rounded_off': '0.20',
    }));
    expect(p.fullDeductions.any((d) => d.$1.startsWith('Loss of Pay')), isFalse);
    expect(p.grossPay - p.fullTotalDeductions + p.fullRoundedOff, closeTo(20000, 0.001));
  });

  test('an older payslip without issued totals still adds up its lines', () {
    final p = Payslip.fromJson(row());
    expect(p.netPay, closeTo(19999.80, 1e-6));
    expect(p.roundedOff, 0);
    expect(p.isFromEngine, isFalse);
    expect(p.isDraft, isFalse);
  });
}
