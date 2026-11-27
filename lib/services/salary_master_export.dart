import 'dart:typed_data';

import '../utils/xlsx_writer.dart';

/// The salary master sheet as an Excel workbook (Ronak, 20 Nov 2026): the
/// salary to credit to each person for a cycle, with the breakup.
///
/// Two sheets (bank details not needed, Ronak 21 Nov 2026):
///   * Master sheet: one line per person: days, leave balances (CL, ML, EL:
///     opening, availed this cycle, closing), LOP by cause, fixed monthly
///     salary, what was earned this cycle, deductions and the net pay to
///     credit, with totals.
///   * Summary: the totals by component and by department, for approval.
///
/// Every figure comes from salary_master_sheet() in the database, the same
/// rows the screen shows, so the file cannot disagree with the payslips.
class SalaryMasterExport {
  SalaryMasterExport._();

  static const _company = 'FOMRA HOUSING AND INFRASTRUCTURE PVT LTD';
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
  static const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String monthLabel(DateTime cycleEnd) => '${_months[cycleEnd.month - 1]} ${cycleEnd.year}';
  static String fileName(DateTime cycleEnd) =>
      'Salary_Master_Sheet_${_short[cycleEnd.month - 1]}_${cycleEnd.year}.xlsx';
  static String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_short[d.month - 1]} ${d.year}';

  static num n(Map<String, dynamic> r, String k) {
    final v = r[k];
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  static String? s(Map<String, dynamic> r, String k) {
    final v = r[k];
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  static DateTime? date(Map<String, dynamic> r, String k) {
    final v = s(r, k);
    if (v == null) return null;
    return DateTime.tryParse(v) ?? _dmy(v);
  }

  static DateTime? _dmy(String v) {
    final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(v);
    if (m == null) return null;
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }

  /// Rupees in Indian grouping, whole rupees: 123456 → "Rs 1,23,456".
  static String inr(num v) {
    final neg = v < 0;
    var whole = v.abs().round().toString();
    var out = '';
    if (whole.length > 3) {
      out = ',${whole.substring(whole.length - 3)}';
      whole = whole.substring(0, whole.length - 3);
      while (whole.length > 2) {
        out = ',${whole.substring(whole.length - 2)}$out';
        whole = whole.substring(0, whole.length - 2);
      }
    }
    return '${neg ? '-' : ''}Rs $whole$out';
  }

  /// People with a salary on this sheet (everyone else has no salary
  /// structure and is listed separately).
  static List<Map<String, dynamic>> payroll(List<Map<String, dynamic>> rows) =>
      rows.where((r) => r['payslip_status'] != 'no_salary_structure').toList();

  static List<Map<String, dynamic>> notOnPayroll(List<Map<String, dynamic>> rows) =>
      rows.where((r) => r['payslip_status'] == 'no_salary_structure').toList();

  static String statusLabel(Map<String, dynamic> r) {
    switch (r['payslip_status']) {
      case 'published':
        return r['records_changed'] == true ? 'Published · records changed since' : 'Published';
      case 'draft':
        return 'Draft payslip';
      default:
        return 'Payslip not issued';
    }
  }

  /// True while the cycle runs: absence is then counted only up to
  /// yesterday, and the figures change until it closes.
  static bool isRunning(List<Map<String, dynamic>> rows, DateTime cycleEnd) {
    final to = rows.isEmpty ? null : date(rows.first, 'absence_counted_to');
    return to != null && to.isBefore(DateTime(cycleEnd.year, cycleEnd.month, cycleEnd.day));
  }

  static String basisNote(List<Map<String, dynamic>> rows, DateTime cycleEnd) {
    if (isRunning(rows, cycleEnd)) {
      final to = date(rows.first, 'absence_counted_to')!;
      return 'Cycle still running: a working day without a check-in or leave counts as absent up to '
          '${_d(to)}; the rest of the cycle is assumed worked. Figures change until the cycle closes.';
    }
    return 'Published payslips are shown as published. Everyone else is calculated from the current '
        'records, and updates the moment a leave, attendance or salary record changes.';
  }

  // ── the master sheet's columns ─────────────────────────────────────────
  static final List<_Col> _cols = [
    _Col('Employee', 'S.No', '#', _K.serial, 5),
    _Col('Employee', 'Emp code', 'employee_id', _K.text, 10),
    _Col('Employee', 'Name', 'employee_name', _K.text, 24),
    _Col('Employee', 'Designation', 'designation', _K.text, 18),
    _Col('Employee', 'Department', 'department', _K.text, 16),
    _Col('Employee', 'Date of joining', 'date_of_joining', _K.date, 12),
    _Col('Employee', 'PF no', 'pf_number', _K.text, 14),
    _Col('Employee', 'ESI no', 'esi_number', _K.text, 14),
    _Col('Days', 'Cycle days', 'cycle_days', _K.days, 7),
    _Col('Days', 'Working days', 'working_days', _K.days, 8),
    _Col('Days', 'Days present', 'days_present', _K.days, 8),
    _Col('Days', 'CL', 'cl_used', _K.days, 6),
    _Col('Days', 'ML', 'ml_used', _K.days, 6),
    _Col('Days', 'EL', 'el_used', _K.days, 6),
    _Col('Days', 'Comp off', 'comp_off_used', _K.days, 7),
    _Col('Days', 'Permissions', 'permission_count', _K.days, 9),
    _Col('Days', 'Permission minutes', 'permission_minutes', _K.days, 10),
    _Col('Leave balance', 'CL opening', 'cl_opening', _K.days, 8),
    _Col('Leave balance', 'CL availed', 'cl_availed', _K.days, 8),
    _Col('Leave balance', 'CL closing', 'cl_closing', _K.days, 8),
    _Col('Leave balance', 'ML opening', 'ml_opening', _K.days, 8),
    _Col('Leave balance', 'ML availed', 'ml_availed', _K.days, 8),
    _Col('Leave balance', 'ML closing', 'ml_closing', _K.days, 8),
    _Col('Leave balance', 'EL opening', 'el_opening', _K.days, 8),
    _Col('Leave balance', 'EL availed', 'el_availed', _K.days, 8),
    _Col('Leave balance', 'EL closing', 'el_closing', _K.days, 8),
    _Col('LOP days', 'Absent without leave', 'absence_lop', _K.days, 10),
    _Col('LOP days', 'Unpaid leave', 'leave_lop', _K.days, 8),
    _Col('LOP days', 'Late LOP', 'late_lop', _K.days, 7),
    _Col('LOP days', 'Permission LOP', 'permission_lop', _K.days, 11),
    _Col('LOP days', 'Total LOP', 'days_lost', _K.daysTotal, 7),
    _Col('LOP days', 'Payable days', 'payable_days', _K.days, 8),
    _Col('Fixed monthly salary', 'Basic', 'fixed_basic', _K.money, 11),
    _Col('Fixed monthly salary', 'DA', 'fixed_da', _K.money, 10),
    _Col('Fixed monthly salary', 'HRA', 'fixed_hra', _K.money, 10),
    _Col('Fixed monthly salary', 'Conveyance', 'fixed_conveyance', _K.money, 11.5),
    _Col('Fixed monthly salary', 'Other allowance', 'fixed_other_allowance', _K.money, 10),
    _Col('Fixed monthly salary', 'Educational', 'fixed_educational', _K.money, 11.5),
    _Col('Fixed monthly salary', 'LTA', 'fixed_lta', _K.money, 10),
    _Col('Fixed monthly salary', 'Monthly gross', 'monthly_gross', _K.money, 12),
    _Col('Earned this cycle', 'Basic', 'basic', _K.money, 11),
    _Col('Earned this cycle', 'DA', 'da', _K.money, 10),
    _Col('Earned this cycle', 'HRA', 'hra', _K.money, 10),
    _Col('Earned this cycle', 'Conveyance', 'conveyance', _K.money, 11.5),
    _Col('Earned this cycle', 'Other allowance', 'other_allowance', _K.money, 10),
    _Col('Earned this cycle', 'Educational', 'educational', _K.money, 11.5),
    _Col('Earned this cycle', 'LTA', 'lta', _K.money, 10),
    _Col('Earned this cycle', 'Gross earned', 'gross_earned', _K.money, 12),
    _Col('Earned this cycle', 'Less: LOP', 'lop_amount', _K.money, 10),
    _Col('Deductions', 'EPF', 'epf', _K.money, 10),
    _Col('Deductions', 'ESI', 'esi', _K.money, 9),
    _Col('Deductions', 'Professional tax', 'professional_tax', _K.money, 12),
    _Col('Deductions', 'TDS', 'tds', _K.money, 10),
    _Col('Deductions', 'Total deductions', 'total_deductions', _K.money, 11),
    _Col('Salary to credit', 'Rounded off', 'rounded_off', _K.money, 8),
    _Col('Salary to credit', 'Net pay', 'net_pay', _K.net, 13),
    _Col('Salary to credit', 'Payslip', '!status', _K.status, 31),
  ];

  /// The column headings, in order; used by the tests.
  static List<String> get columnHeadings => [for (final c in _cols) c.header];

  static Uint8List build(List<Map<String, dynamic>> rows, DateTime cycleEnd, {DateTime? now}) {
    final paid = payroll(rows);
    final missing = notOnPayroll(rows);
    final stamp = now ?? DateTime.now();
    final cycleStart = date(rows.isEmpty ? const {} : rows.first, 'cycle_start');
    final period = '${cycleStart == null ? '' : '${_d(cycleStart)} – '}${_d(cycleEnd)}';
    final prepared = 'Prepared from the HRMS on ${_d(stamp)} at '
        '${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}.';

    return Xlsx.build([
      _master(paid, missing, cycleEnd, period, basisNote(rows, cycleEnd), prepared),
      _summary(paid, cycleEnd, period, prepared),
    ]);
  }

  static XlsxSheet _master(List<Map<String, dynamic>> paid, List<Map<String, dynamic>> missing,
      DateTime cycleEnd, String period, String basis, String prepared) {
    final sh = XlsxSheet('Master sheet')
      ..landscape = true
      ..freezeRows = 6
      ..freezeColumns = 3;
    final last = _cols.length - 1;
    sh.addRow([const XlsxCell(_company, Xlsx.title)], height: 20);
    sh.merge(0, 0, last);
    sh.addRow([XlsxCell('Salary master sheet – ${monthLabel(cycleEnd)} (attendance cycle $period)', Xlsx.subtitle)]);
    sh.merge(1, 0, last);
    sh.addRow([XlsxCell(basis, Xlsx.note)]);
    sh.merge(2, 0, last);
    sh.addRow([]);

    // Group headings, merged over their columns.
    final groupRow = <XlsxCell?>[for (final c in _cols) XlsxCell(c.group, Xlsx.group)];
    final g = sh.addRow(groupRow, height: 18);
    var start = 0;
    for (var i = 1; i <= _cols.length; i++) {
      if (i == _cols.length || _cols[i].group != _cols[start].group) {
        sh.merge(g, start, i - 1);
        start = i;
      }
    }
    sh.addRow([for (final c in _cols) XlsxCell(c.header, Xlsx.header)], height: 30);
    for (var i = 0; i < _cols.length; i++) {
      sh.width(i, _cols[i].width);
    }

    final firstData = sh.rows.length;
    for (var i = 0; i < paid.length; i++) {
      final r = paid[i];
      sh.addRow([for (final c in _cols) _cell(c, r, i + 1)]);
    }
    final lastData = sh.rows.length - 1;

    // Totals: money and LOP days are added up; counts of days are not
    // (twelve people's "30 cycle days" add up to nothing useful).
    if (paid.isNotEmpty) {
      sh.addRow([
        for (var i = 0; i < _cols.length; i++)
          if (i == 2)
            XlsxCell('Total (${paid.length} ${paid.length == 1 ? 'person' : 'people'})', Xlsx.totalText)
          else if (_cols[i].sums)
            XlsxCell(
                XlsxFormula('SUM(${Xlsx.ref(firstData, i)}:${Xlsx.ref(lastData, i)})',
                    paid.fold<num>(0, (t, r) => t + n(r, _cols[i].key))),
                _cols[i].kind == _K.daysTotal ? Xlsx.totalNumber : Xlsx.totalMoney)
          else
            const XlsxCell(null, Xlsx.totalText),
      ]);
    }

    sh.addRow([]);
    final changed = paid.where((r) => r['records_changed'] == true).toList();
    if (changed.isNotEmpty) {
      sh.addRow([
        XlsxCell('Records changed after publishing (paid as published; reissue the payslip to correct): '
            '${changed.map((r) => '${r['employee_name']} (${r['employee_id']}): now '
                '${inr(n(r, 'live_net_pay'))} (paid ${inr(n(r, 'net_pay'))})').join('; ')}', Xlsx.note),
      ]);
    }
    if (missing.isNotEmpty) {
      sh.addRow([
        XlsxCell('Not on this sheet (no salary structure): '
            '${missing.map((r) => '${r['employee_name']} (${r['employee_id']})').join(', ')}.', Xlsx.note),
      ]);
    }
    sh.addRow([
      const XlsxCell('LOP days = absent without leave + unpaid leave + late LOP + permission LOP. '
          'Earned = fixed × payable days ÷ cycle days. Net pay is rounded to the nearest rupee.', Xlsx.note),
    ]);
    sh.addRow([XlsxCell(prepared, Xlsx.note)]);
    return sh;
  }

  static XlsxCell _cell(_Col c, Map<String, dynamic> r, int serial) {
    switch (c.kind) {
      case _K.serial:
        return XlsxCell(serial, Xlsx.number);
      case _K.text:
        return XlsxCell(s(r, c.key), Xlsx.text);
      case _K.date:
        final d = date(r, c.key);
        return XlsxCell(d == null ? s(r, c.key) : _d(d), Xlsx.text);
      case _K.days:
      case _K.daysTotal:
        return XlsxCell(n(r, c.key), Xlsx.number);
      case _K.money:
        return XlsxCell(n(r, c.key), Xlsx.money);
      case _K.net:
        return XlsxCell(n(r, c.key), Xlsx.moneyBold);
      case _K.status:
        return XlsxCell(statusLabel(r), r['records_changed'] == true ? Xlsx.flagged : Xlsx.text);
    }
  }

  static XlsxSheet _summary(List<Map<String, dynamic>> paid, DateTime cycleEnd, String period, String prepared) {
    num sum(String k) => paid.fold<num>(0, (t, r) => t + n(r, k));
    final sh = XlsxSheet('Summary');
    sh.width(0, 34);
    sh.width(1, 16);
    sh.width(2, 16);
    sh.width(3, 16);
    sh.width(4, 16);
    sh.addRow([const XlsxCell(_company, Xlsx.title)], height: 20);
    sh.merge(0, 0, 4);
    sh.addRow([XlsxCell('Salary summary – ${monthLabel(cycleEnd)} (attendance cycle $period)', Xlsx.subtitle)]);
    sh.merge(1, 0, 4);
    sh.addRow([]);
    sh.addRow([const XlsxCell('Item', Xlsx.header), const XlsxCell('Amount', Xlsx.header)]);
    final lines = <(String, num, int)>[
      ('People on payroll', paid.length, Xlsx.number),
      ('Monthly gross salary (fixed)', sum('monthly_gross'), Xlsx.money),
      ('Less: loss of pay', sum('lop_amount'), Xlsx.money),
      ('Gross earned', sum('gross_earned'), Xlsx.moneyBold),
      ('EPF', sum('epf'), Xlsx.money),
      ('ESI', sum('esi'), Xlsx.money),
      ('Professional tax', sum('professional_tax'), Xlsx.money),
      ('TDS', sum('tds'), Xlsx.money),
      ('Total deductions', sum('total_deductions'), Xlsx.moneyBold),
      ('Rounded off', sum('rounded_off'), Xlsx.money),
    ];
    for (final (label, v, style) in lines) {
      sh.addRow([XlsxCell(label, Xlsx.text), XlsxCell(v, style)]);
    }
    sh.addRow([const XlsxCell('Net salary to credit', Xlsx.totalText), XlsxCell(sum('net_pay'), Xlsx.totalMoney)]);

    sh.addRow([]);
    sh.addRow([
      const XlsxCell('Department', Xlsx.header),
      const XlsxCell('People', Xlsx.header),
      const XlsxCell('Gross earned', Xlsx.header),
      const XlsxCell('Deductions', Xlsx.header),
      const XlsxCell('Net pay', Xlsx.header),
    ]);
    final byDept = <String, List<Map<String, dynamic>>>{};
    for (final r in paid) {
      byDept.putIfAbsent(s(r, 'department') ?? '—', () => []).add(r);
    }
    final depts = byDept.keys.toList()..sort();
    for (final d in depts) {
      final rs = byDept[d]!;
      num t(String k) => rs.fold<num>(0, (a, r) => a + n(r, k));
      sh.addRow([
        XlsxCell(d, Xlsx.text),
        XlsxCell(rs.length, Xlsx.number),
        XlsxCell(t('gross_earned'), Xlsx.money),
        XlsxCell(t('total_deductions'), Xlsx.money),
        XlsxCell(t('net_pay'), Xlsx.moneyBold),
      ]);
    }
    sh.addRow([]);
    sh.addRow([XlsxCell(prepared, Xlsx.note)]);
    return sh;
  }
}

enum _K { serial, text, date, days, daysTotal, money, net, status }

class _Col {
  final String group;
  final String header;
  final String key;
  final _K kind;
  final double width;
  const _Col(this.group, this.header, this.key, this.kind, this.width);

  bool get sums => kind == _K.money || kind == _K.net || kind == _K.daysTotal;
}
