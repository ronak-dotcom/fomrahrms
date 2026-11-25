import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../services/salary_master_export.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/mobile_ui.dart';
import '../utils/attendance_cycle.dart';
import '../utils/file_export.dart';
import '../widgets/back_button.dart';

/// The salary master sheet (Ronak, 20 Nov 2026): what to credit to each
/// person for a cycle, with the breakup, and the Excel file.
///
/// The figures are salary_master_sheet() in the database. A published
/// payslip is shown as published (that is what was paid). Everyone else is
/// the payroll engine's figure now, and changes the moment a leave, its LOP,
/// a check-in or a salary changes: refresh to see it. While the cycle runs,
/// a missed day counts only once it has passed.
class SalaryMasterSheetPage extends StatefulWidget {
  final DateTime? initialCycleEnd;
  const SalaryMasterSheetPage({super.key, this.initialCycleEnd});

  @override
  State<SalaryMasterSheetPage> createState() => _SalaryMasterSheetPageState();
}

class _SalaryMasterSheetPageState extends State<SalaryMasterSheetPage> {
  late DateTime _cycleEnd;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  static const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// The running cycle, then the eleven before it.
  static List<DateTime> cycleEnds({int count = 12}) {
    final now = DateTime.now();
    final end = attendanceCycleEnd(DateTime(now.year, now.month, now.day));
    return [for (var i = 0; i < count; i++) DateTime(end.year, end.month - i, 25)];
  }

  @override
  void initState() {
    super.initState();
    _cycleEnd = widget.initialCycleEnd != null
        ? attendanceCycleEnd(widget.initialCycleEnd!)
        : _defaultCycle();
    _load();
  }

  /// The latest closed cycle in its first week (when salaries are worked
  /// out), the running one after that.
  static DateTime _defaultCycle() {
    final now = DateTime.now();
    final ends = cycleEnds(count: 2);
    return now.day >= 26 || now.day <= 7 ? ends[1] : ends[0];
  }

  String get _label => SalaryMasterExport.monthLabel(_cycleEnd);
  String _d(DateTime d) => '${d.day} ${_short[d.month - 1]} ${d.year}';
  static num _n(Map<String, dynamic> r, String k) => SalaryMasterExport.n(r, k);
  static String _days(num v) =>
      v == 0 ? '–' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));
  static String _rs(num v) => formatRupees(v);
  static String _rsp(num v) => formatRupees(v, paise: true);

  List<Map<String, dynamic>> get _paid => SalaryMasterExport.payroll(_rows);
  List<Map<String, dynamic>> get _missing => SalaryMasterExport.notOnPayroll(_rows);
  bool get _running => SalaryMasterExport.isRunning(_rows, _cycleEnd);
  num _sum(String k) => _paid.fold<num>(0, (t, r) => t + _n(r, k));

  // ── Gross minus deductions (HR, 25 Nov 2026) ──────────────────────────
  // Read as: monthly gross, less LOP / late and PF, ESI, PT, TDS, equals
  // net pay. The engine pays earnings in proportion to payable days, so the
  // sheet used to show a reduced "gross earned" and deductions that left
  // LOP out, and gross minus deductions did not come to net pay. Same
  // restatement as Payslip.payCuts; net pay is unchanged.
  static double _r2(num v) => (v * 100).roundToDouble() / 100;

  static ({double lopDays, double lop, double lateDays, double late, double outsideDays, double outside})
      _cuts(Map<String, dynamic> r) {
    final gross = _n(r, 'monthly_gross').toDouble();
    final cycle = _n(r, 'cycle_days').toDouble();
    final lateDays = (_n(r, 'late_lop') + _n(r, 'permission_lop')).toDouble();
    final lost = _n(r, 'days_lost').toDouble();
    final lopDays = lost - lateDays < 0 ? 0.0 : lost - lateDays;
    var outsideDays = cycle - _n(r, 'payable_days').toDouble() - lost;
    if (outsideDays < 0.0001) outsideDays = 0;
    if (gross <= 0 || cycle <= 0) {
      return (lopDays: lopDays, lop: 0.0, lateDays: lateDays, late: 0.0, outsideDays: outsideDays, outside: 0.0);
    }
    final perDay = gross / cycle;
    var lop = _r2(perDay * lopDays);
    var late = _r2(perDay * lateDays);
    var outside = _r2(perDay * outsideDays);
    final residual = _r2(_r2(gross - _n(r, 'gross_earned')) - (lop + late + outside));
    // Only onto a cut that has days behind it; otherwise the paise fall into
    // "Rounded off" rather than showing a 0-day loss of pay.
    if (residual != 0) {
      if (lopDays > 0 && lop >= late && lop >= outside) {
        lop = _r2(lop + residual);
      } else if (lateDays > 0 && late >= outside) {
        late = _r2(late + residual);
      } else if (outsideDays > 0) {
        outside = _r2(outside + residual);
      } else if (lopDays > 0) {
        lop = _r2(lop + residual);
      } else if (lateDays > 0) {
        late = _r2(late + residual);
      }
    }
    return (lopDays: lopDays, lop: lop, lateDays: lateDays, late: late, outsideDays: outsideDays, outside: outside);
  }

  /// LOP, late and days outside employment, in rupees.
  static double _cutTotal(Map<String, dynamic> r) {
    final c = _cuts(r);
    return _r2(c.lop + c.late + c.outside);
  }

  /// Everything taken off the monthly gross.
  static double _dedFromGross(Map<String, dynamic> r) => _r2(_cutTotal(r) +
      _n(r, 'epf') + _n(r, 'esi') + _n(r, 'professional_tax') + _n(r, 'tds'));

  double _sumBy(double Function(Map<String, dynamic>) f) =>
      _paid.fold<double>(0, (t, r) => t + f(r));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SupabaseService.salaryMasterSheet(_cycleEnd);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is PostgrestException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Fresh figures for the file, not what was on screen a while ago.
      final rows = await SupabaseService.salaryMasterSheet(_cycleEnd);
      final bytes = SalaryMasterExport.build(rows, _cycleEnd);
      final name = SalaryMasterExport.fileName(_cycleEnd);
      await exportBytes(name, bytes,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      SupabaseService.logAuditEvent('salary_master_sheet_downloaded',
          targetType: 'payroll', targetId: _cycleEnd.toIso8601String().substring(0, 10),
          details: {'people': SalaryMasterExport.payroll(rows).length});
      if (mounted) setState(() => _rows = rows);
      messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('$name downloaded.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        content: Text('Could not make the sheet: ${e is PostgrestException ? e.message : e}'),
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── layout ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final start = attendanceCycleStart(_cycleEnd);
    return Scaffold(
      backgroundColor: AppTheme.pageBackground,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 16, wide ? 28 : 16, 24),
          children: [
            Row(children: [
              const NavBackButton(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(wide ? 'Salary master sheet – $_label' : 'Master sheet',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: wide ? 26 : 20, fontWeight: FontWeight.w800)),
              ),
              _cyclePicker(wide),
              IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded)),
              if (wide) ...[
                const SizedBox(width: 4),
                _downloadButton(),
              ],
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                  'Attendance cycle ${_d(start)} – ${_d(_cycleEnd)} · ${_running ? 'running' : 'closed'}'
                  '${_paid.isEmpty ? '' : ' · ${_paid.length} on payroll'}',
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            if (!wide) ...[
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: _downloadButton()),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              MCard(
                color: MobileUi.lopBg,
                borderColor: const Color(0xFFF5C2C2),
                child: Text('Could not load the master sheet: $_error',
                    style: const TextStyle(color: MobileUi.lop)),
              )
            else if (_paid.isEmpty)
              const MCard(child: Text('No one is on payroll for this cycle.'))
            else ...[
              _basis(),
              const SizedBox(height: 12),
              _totals(wide),
              const SizedBox(height: 12),
              ..._warnings(),
              wide ? _table() : _cards(),
              const SizedBox(height: 14),
              const MCard(
                color: Color(0xFFFFFBEA),
                borderColor: Color(0xFFF2DE8A),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'LOP days', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' = days absent without leave + unpaid leave + late LOP + permission LOP. '
                      'Each component is earned for the payable days: fixed × payable ÷ cycle days. '
                      'Net pay is rounded to the nearest rupee. A wrong figure is fixed at its source '
                      '(the leave, permission or attendance record) and this sheet follows.'),
                ])),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _downloadButton() => FilledButton.icon(
        onPressed: _exporting || _loading || _paid.isEmpty ? null : _download,
        icon: _exporting
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.download_rounded, size: 18),
        label: const Text('Download Excel'),
      );

  Widget _cyclePicker(bool wide) => PopupMenuButton<DateTime>(
        tooltip: 'Choose cycle',
        onSelected: (d) {
          setState(() => _cycleEnd = d);
          _load();
        },
        itemBuilder: (_) {
          final ends = cycleEnds();
          return [
            for (var i = 0; i < ends.length; i++)
              PopupMenuItem(
                value: ends[i],
                child: Text('${SalaryMasterExport.monthLabel(ends[i])}${i == 0 ? ' (running)' : ''}'),
              ),
          ];
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: MobileUi.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_month_rounded, size: 18, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(wide ? _label : '${_short[_cycleEnd.month - 1]} ${_cycleEnd.year}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_drop_down_rounded),
          ]),
        ),
      );

  Widget _basis() {
    final running = _running;
    return MCard(
      color: running ? MobileUi.lateBg : MobileUi.permissionBg,
      borderColor: running ? const Color(0xFFF3D19C) : const Color(0xFFC9D7F8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(running ? Icons.timelapse_rounded : Icons.verified_rounded,
            size: 20, color: running ? MobileUi.late : MobileUi.permission),
        const SizedBox(width: 10),
        Expanded(
          child: Text(SalaryMasterExport.basisNote(_rows, _cycleEnd),
              style: TextStyle(fontSize: 13, color: running ? MobileUi.late : MobileUi.permission)),
        ),
      ]),
    );
  }

  Widget _totals(bool wide) {
    Widget tile(String label, String value, {Color? color, bool big = false}) => MCard(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(fontSize: big ? 22 : 18, fontWeight: FontWeight.w800, color: color)),
          ]),
        );
    final tiles = [
      tile('Net salary to credit', _rs(_sum('net_pay')), color: MobileUi.present, big: true),
      tile('Gross (monthly)', _rs(_sum('monthly_gross'))),
      tile('LOP & late', _rs(_sumBy(_cutTotal)), color: _sumBy(_cutTotal) > 0 ? MobileUi.lop : null),
      tile('Total deductions', _rs(_sumBy(_dedFromGross))),
    ];
    final statutory = Text(
        'Gross less deductions = net pay. Deductions: LOP & late ${_rsp(_sumBy(_cutTotal))} · '
        'EPF ${_rsp(_sum('epf'))} · ESI ${_rs(_sum('esi'))} · '
        'Professional tax ${_rs(_sum('professional_tax'))} · TDS ${_rs(_sum('tds'))}',
        style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary));
    if (wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tiles[i]),
          ],
        ]),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(left: 4), child: statutory),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      tiles[0],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: tiles[1]),
        const SizedBox(width: 8),
        Expanded(child: tiles[2]),
      ]),
      const SizedBox(height: 8),
      tiles[3],
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.only(left: 4), child: statutory),
    ]);
  }

  List<Widget> _warnings() {
    final out = <Widget>[];
    Widget warn(IconData icon, String text, {bool red = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: MCard(
            color: red ? MobileUi.lopBg : const Color(0xFFFFFBEA),
            borderColor: red ? const Color(0xFFF5C2C2) : const Color(0xFFF2DE8A),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: red ? MobileUi.lop : MobileUi.late),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            ]),
          ),
        );
    final changed = _paid.where((r) => r['records_changed'] == true).toList();
    if (changed.isNotEmpty) {
      out.add(warn(Icons.sync_problem_rounded,
          'Records changed after publishing for ${changed.map((r) => '${r['employee_name']} '
              '(paid ${_rs(_n(r, 'net_pay'))}, now ${_rs(_n(r, 'live_net_pay'))})').join(', ')}. '
              'The sheet shows what was published; reissue the payslip from Payroll to correct it.',
          red: true));
    }
    if (_missing.isNotEmpty) {
      out.add(warn(Icons.person_off_rounded,
          'Not on this sheet, no salary structure: '
          '${_missing.map((r) => '${r['employee_name']} (${r['employee_id']})').join(', ')}.'));
    }
    return out;
  }

  Widget _statusChip(Map<String, dynamic> r) {
    final s = r['payslip_status'];
    if (r['records_changed'] == true) {
      return const MChip('Changed since', color: MobileUi.lop, background: MobileUi.lopBg);
    }
    if (s == 'published') return const MChip('Published', color: MobileUi.present, background: MobileUi.presentBg);
    if (s == 'draft') return const MChip('Draft', color: MobileUi.late, background: MobileUi.lateBg);
    return const MChip('Not issued', color: AppTheme.textSecondary, background: Color(0xFFEEF1F6));
  }

  String _lopTip(Map<String, dynamic> r) =>
      'Absent without leave ${_days(_n(r, 'absence_lop'))} · unpaid leave ${_days(_n(r, 'leave_lop'))} · '
      'late ${_days(_n(r, 'late_lop'))} · permission ${_days(_n(r, 'permission_lop'))}';

  Widget _table() {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary);
    DataCell numCell(String text, {bool bold = false, Color? color, String? tip}) {
      final t = Text(text, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color));
      return DataCell(Align(
        alignment: Alignment.centerRight,
        child: tip == null ? t : Tooltip(message: tip, child: t),
      ));
    }

    // Net pay first: it is what this sheet is for. Then the totals, then the
    // components; a component nobody has (all zero) is left off the screen
    // (the Excel file keeps every column).
    final paid = _paid;
    final breakup = <(String, String)>[
      // Full monthly rates: they add up to the monthly gross.
      ('Basic', 'fixed_basic'),
      ('DA', 'fixed_da'),
      ('HRA', 'fixed_hra'),
      ('Conv.', 'fixed_conveyance'),
      ('Other', 'fixed_other_allowance'),
      ('Edu.', 'fixed_educational'),
      ('LTA', 'fixed_lta'),
      ('EPF', 'epf'),
      ('ESI', 'esi'),
      ('PT', 'professional_tax'),
      ('TDS', 'tds'),
    ].where((c) => paid.any((r) => _n(r, c.$2) != 0)).toList();
    return MCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F6FB)),
          columnSpacing: 18,
          horizontalMargin: 14,
          dataRowMinHeight: 50,
          dataRowMaxHeight: 58,
          headingTextStyle: head,
          columns: [
            const DataColumn(label: Text('Employee')),
            const DataColumn(label: Text('Paid\ndays'), numeric: true),
            const DataColumn(label: Text('LOP\ndays'), numeric: true),
            const DataColumn(label: Text('Net pay\nto credit'), numeric: true),
            const DataColumn(label: Text('Payslip')),
            const DataColumn(label: Text('Gross\n(monthly)'), numeric: true),
            const DataColumn(label: Text('LOP &\nlate'), numeric: true),
            const DataColumn(label: Text('Total\ndeductions'), numeric: true),
            for (final (l, _) in breakup) DataColumn(label: Text(l), numeric: true),
          ],
          rows: [
            for (final r in paid)
              DataRow(cells: [
                DataCell(Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['employee_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${r['employee_id']} · ${r['department'] ?? ''}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                )),
                numCell('${_days(_n(r, 'payable_days'))} / ${_n(r, 'cycle_days')}'),
                numCell(_days(_n(r, 'days_lost')),
                    color: _n(r, 'days_lost') > 0 ? MobileUi.lop : null, tip: _lopTip(r)),
                numCell(_rs(_n(r, 'net_pay')), bold: true),
                DataCell(_statusChip(r)),
                numCell(_rs(_n(r, 'monthly_gross'))),
                numCell(_cutTotal(r) == 0 ? '–' : _rsp(_cutTotal(r)),
                    color: _cutTotal(r) > 0 ? MobileUi.lop : null, tip: _lopTip(r)),
                numCell(_rsp(_dedFromGross(r))),
                for (final (_, k) in breakup) numCell(_n(r, k) == 0 ? '–' : _rsp(_n(r, k))),
              ]),
            DataRow(
              color: WidgetStateProperty.all(const Color(0xFFFFF8E5)),
              cells: [
                DataCell(Text('Total (${paid.length})', style: const TextStyle(fontWeight: FontWeight.w800))),
                const DataCell(SizedBox()),
                numCell(_days(_sum('days_lost')), bold: true),
                numCell(_rs(_sum('net_pay')), bold: true),
                const DataCell(SizedBox()),
                numCell(_rs(_sum('monthly_gross')), bold: true),
                numCell(_rsp(_sumBy(_cutTotal)), bold: true),
                numCell(_rsp(_sumBy(_dedFromGross)), bold: true),
                for (final (_, k) in breakup) numCell(_rsp(_sum(k)), bold: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cards() => Column(children: [
        for (final r in _paid)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MCard(
              padding: EdgeInsets.zero,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  title: Text('${r['employee_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r['employee_id']} · paid ${_days(_n(r, 'payable_days'))} of ${_n(r, 'cycle_days')} days'
                        '${_n(r, 'days_lost') > 0 ? ' · LOP ${_days(_n(r, 'days_lost'))}' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text(_rs(_n(r, 'net_pay')),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.black87)),
                      const SizedBox(width: 8),
                      _statusChip(r),
                    ]),
                  ]),
                  children: [_breakup(r)],
                ),
              ),
            ),
          ),
      ]);

  Widget _breakup(Map<String, dynamic> r) {
    Widget line(String l, num v, {bool bold = false, bool minus = false, bool days = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(
                child: Text(l, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
            Text(days ? _days(v) : '${minus && v != 0 ? '− ' : ''}${_rsp(v)}',
                style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
    Widget head(String t) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(t.toUpperCase(),
              style: const TextStyle(fontSize: 11, letterSpacing: 0.6, color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      head('Days'),
      line('Working days', _n(r, 'working_days'), days: true),
      line('Present', _n(r, 'days_present'), days: true),
      line('Leave (CL / ML / EL / comp off)',
          _n(r, 'cl_used') + _n(r, 'ml_used') + _n(r, 'el_used') + _n(r, 'comp_off_used'), days: true),
      line('LOP: absent without leave', _n(r, 'absence_lop'), days: true),
      line('LOP: unpaid leave', _n(r, 'leave_lop'), days: true),
      line('LOP: late / permission', _n(r, 'late_lop') + _n(r, 'permission_lop'), days: true),
      line('Payable days', _n(r, 'payable_days'), days: true, bold: true),
      head('Gross (monthly)'),
      line('Basic', _n(r, 'fixed_basic')),
      line('DA', _n(r, 'fixed_da')),
      line('HRA', _n(r, 'fixed_hra')),
      line('Conveyance', _n(r, 'fixed_conveyance')),
      line('Other allowance', _n(r, 'fixed_other_allowance')),
      line('Educational', _n(r, 'fixed_educational')),
      line('LTA', _n(r, 'fixed_lta')),
      line('Gross salary', _n(r, 'monthly_gross'), bold: true),
      head('Deductions'),
      if (_cuts(r).lop != 0) line('Loss of pay (${_days(_cuts(r).lopDays)} days)', _cuts(r).lop, minus: true),
      if (_cuts(r).late != 0) line('Late / permission (${_days(_cuts(r).lateDays)} days)', _cuts(r).late, minus: true),
      if (_cuts(r).outside != 0)
        line('Before joining / after leaving (${_days(_cuts(r).outsideDays)} days)', _cuts(r).outside, minus: true),
      line('EPF', _n(r, 'epf'), minus: true),
      line('ESI', _n(r, 'esi'), minus: true),
      line('Professional tax', _n(r, 'professional_tax'), minus: true),
      line('TDS', _n(r, 'tds'), minus: true),
      line('Total deductions', _dedFromGross(r), bold: true, minus: true),
      if (_r2(_n(r, 'net_pay') - (_n(r, 'monthly_gross') - _dedFromGross(r))) != 0)
        line('Rounded off', _r2(_n(r, 'net_pay') - (_n(r, 'monthly_gross') - _dedFromGross(r)))),
      const Divider(height: 14),
      line('Net pay to credit', _n(r, 'net_pay'), bold: true),
    ]);
  }
}
