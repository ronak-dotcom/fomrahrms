import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fomra_hrms/services/salary_master_export.dart';
import 'package:fomra_hrms/utils/xlsx_writer.dart';

/// Rows shaped as salary_master_sheet() returns them.
Map<String, dynamic> _row(String id, String name, {
  String? status = 'draft',
  num net = 20000,
  num gross = 20000,
  num deductions = 0,
  num lost = 0,
  String? bank,
  bool changed = false,
  num liveNet = 20000,
}) =>
    {
      'employee_id': id, 'employee_name': name, 'designation': 'Executive', 'department': 'Sales',
      'date_of_joining': '2025-04-01', 'bank_account': bank, 'ifsc': bank == null ? null : 'HDFC0001234',
      'pf_number': null, 'esi_number': null,
      'cycle_start': '2026-09-26', 'cycle_end': '2026-10-25',
      'cycle_days': 30, 'working_days': 25, 'days_present': 25,
      'cl_used': 0, 'ml_used': 0, 'el_used': 0, 'comp_off_used': 0, 'lop_leave': 0,
      'absence_lop': lost, 'leave_lop': 0, 'late_lop': 0, 'permission_lop': 0,
      'days_lost': lost, 'payable_days': 30 - lost,
      'monthly_gross': 20000, 'fixed_basic': 10000, 'fixed_da': 0, 'fixed_hra': 5000,
      'fixed_conveyance': 0, 'fixed_other_allowance': 5000, 'fixed_educational': 0, 'fixed_lta': 0,
      'basic': gross / 2, 'da': 0, 'hra': gross / 4, 'conveyance': 0, 'other_allowance': gross / 4,
      'educational': 0, 'lta': 0, 'gross_earned': gross, 'lop_amount': 20000 - gross,
      'epf': 0, 'esi': 0, 'professional_tax': deductions, 'tds': 0, 'total_deductions': deductions,
      'rounded_off': 0, 'net_pay': net,
      'payslip_status': status, 'payslip_version': status == null ? null : 1,
      'live_net_pay': liveNet, 'records_changed': changed, 'absence_counted_to': '2026-10-25',
    };

Map<String, String> _unzip(List<int> bytes) {
  final a = ZipDecoder().decodeBytes(bytes);
  return {for (final f in a.files) f.name: utf8.decode(f.content as List<int>)};
}

void main() {
  group('xlsx writer', () {
    test('column letters', () {
      expect(Xlsx.col(0), 'A');
      expect(Xlsx.col(25), 'Z');
      expect(Xlsx.col(26), 'AA');
      expect(Xlsx.col(47), 'AV');
      expect(Xlsx.ref(5, 2), 'C6');
    });

    test('a workbook has its parts, escaped text, numbers, merges and formulas', () {
      final sh = XlsxSheet('Pay & days')..freezeRows = 1;
      sh.addRow([const XlsxCell('R&D <team>', Xlsx.header), const XlsxCell(1234.5, Xlsx.money)]);
      sh.addRow([const XlsxCell(null, Xlsx.text), const XlsxCell(XlsxFormula('SUM(B1:B1)', 1234.5), Xlsx.totalMoney)]);
      sh.merge(0, 0, 1);
      final files = _unzip(Xlsx.build([sh]));
      expect(files.keys, containsAll(<String>[
        '[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels', 'xl/styles.xml', 'xl/worksheets/sheet1.xml',
      ]));
      final x = files['xl/worksheets/sheet1.xml']!;
      expect(x, contains('R&amp;D &lt;team&gt;'));
      expect(x, contains('<v>1234.5</v>'));
      expect(x, contains('<f>SUM(B1:B1)</f>'));
      expect(x, contains('<mergeCell ref="A1:B1"/>'));
      expect(x, contains('state="frozen"'));
      expect(files['xl/workbook.xml'], contains('name="Pay &amp; days"'));
    });
  });

  group('salary master sheet', () {
    final rows = [
      _row('FD-01', 'Asha', net: 19000, gross: 19208, deductions: 208, lost: 1, bank: '50100012345678'),
      _row('FD-02', 'Bala', status: 'published', net: 20000, changed: true, liveNet: 19333),
      _row('FD-03', 'Chitra', status: 'no_salary_structure', net: 0, gross: 0),
    ];

    test('only people with a salary are on the sheet; the rest are listed', () {
      expect(SalaryMasterExport.payroll(rows).map((r) => r['employee_id']), ['FD-01', 'FD-02']);
      expect(SalaryMasterExport.notOnPayroll(rows).map((r) => r['employee_id']), ['FD-03']);
    });

    test('status says when a published payslip no longer matches its records', () {
      expect(SalaryMasterExport.statusLabel(rows[0]), 'Draft payslip');
      expect(SalaryMasterExport.statusLabel(rows[1]), 'Published · records changed since');
    });

    test('a running cycle is recognised from how far absence is counted', () {
      final running = [_row('FD-01', 'Asha')..['absence_counted_to'] = '2026-11-19'];
      expect(SalaryMasterExport.isRunning(running, DateTime(2026, 11, 25)), isTrue);
      expect(SalaryMasterExport.isRunning(rows, DateTime(2026, 10, 25)), isFalse);
    });

    test('the workbook has the master sheet and the summary, with totals; no bank details', () {
      final files = _unzip(SalaryMasterExport.build(rows, DateTime(2026, 10, 25), now: DateTime(2026, 11, 20, 10, 5)));
      final wb = files['xl/workbook.xml']!;
      expect(wb, contains('name="Master sheet"'));
      expect(wb, isNot(contains('Bank transfer')));
      expect(wb, contains('name="Summary"'));

      final master = files['xl/worksheets/sheet1.xml']!;
      expect(SalaryMasterExport.columnHeadings.length, 46);
      expect(SalaryMasterExport.columnHeadings, isNot(contains('Bank account')));
      // Net pay is column 45 (AS); data rows are 7 and 8; the total is 39,000.
      expect(master, contains('<f>SUM(AS7:AS8)</f><v>39000</v>'));
      expect(master, contains('Total (2 people)'));
      expect(master, contains('Not on this sheet (no salary structure): Chitra (FD-03).'));
      expect(master, contains('Records changed after publishing'));

      final summary = files['xl/worksheets/sheet2.xml']!;
      expect(summary, contains('Net salary to credit'));
      expect(summary, contains('<v>39000</v>'));
    });

    test('rupees in Indian grouping', () {
      expect(SalaryMasterExport.inr(580025), 'Rs 5,80,025');
      expect(SalaryMasterExport.inr(999), 'Rs 999');
      expect(SalaryMasterExport.inr(1234567.6), 'Rs 12,34,568');
    });

    test('file name names the month', () {
      expect(SalaryMasterExport.fileName(DateTime(2026, 11, 25)), 'Salary_Master_Sheet_Nov_2026.xlsx');
    });
  });
}
