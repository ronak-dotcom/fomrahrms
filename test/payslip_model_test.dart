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

  test('an older payslip without issued totals still adds up its lines', () {
    final p = Payslip.fromJson(row());
    expect(p.netPay, closeTo(19999.80, 1e-6));
    expect(p.roundedOff, 0);
    expect(p.isFromEngine, isFalse);
    expect(p.isDraft, isFalse);
  });
}
