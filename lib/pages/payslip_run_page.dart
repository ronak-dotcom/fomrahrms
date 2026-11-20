import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/mobile_ui.dart';
import '../utils/attendance_cycle.dart';
import '../widgets/back_button.dart';

/// Payroll for one closed attendance cycle (approved with HR, Nov 2026).
///
/// 1. HR confirms the counts the system made for each person: leave by
///    type, permission, late arrivals, LOP days.
/// 2. Generate: the database calculates each payslip from the payroll engine
///    and saves it as a draft. Nobody types an amount.
/// 3. Publish: employees can then see and download it, and are notified.
///
/// A wrong count is never corrected here. It is fixed at its source (the
/// leave, permission or attendance record) and the counts update.
class PayslipRunPage extends StatefulWidget {
  /// Opens on the cycle ending on this date; defaults to the latest closed one.
  final DateTime? initialCycleEnd;
  /// Scrolls attention to this person (e.g. from a payslip request).
  final String? highlightEmployeeId;
  const PayslipRunPage({super.key, this.initialCycleEnd, this.highlightEmployeeId});

  @override
  State<PayslipRunPage> createState() => _PayslipRunPageState();
}

class _PayslipRunPageState extends State<PayslipRunPage> {
  late DateTime _cycleEnd;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _confirmed = {};

  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
  static const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Cycle ends (the 25th) that have passed, newest first.
  static List<DateTime> closedCycleEnds({int count = 12}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var end = DateTime(today.year, today.month, 25);
    if (!end.isBefore(today)) end = DateTime(end.year, end.month - 1, 25);
    return [for (var i = 0; i < count; i++) DateTime(end.year, end.month - i, 25)];
  }

  @override
  void initState() {
    super.initState();
    _cycleEnd = widget.initialCycleEnd != null
        ? attendanceCycleEnd(widget.initialCycleEnd!)
        : closedCycleEnds().first;
    _load();
  }

  String get _label => '${_months[_cycleEnd.month - 1]} ${_cycleEnd.year}';
  DateTime get _cycleStart => attendanceCycleStart(_cycleEnd);
  String _d(DateTime d) => '${d.day} ${_short[d.month - 1]} ${d.year}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await SupabaseService.payslipPreview(_cycleEnd);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _confirmed.removeWhere((id) => !rows.any((r) => r['employee_id'] == id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _loading = false;
      });
    }
  }

  static String _message(Object e) => e is PostgrestException ? e.message : '$e';

  // ── figures ────────────────────────────────────────────────────────────
  static num _n(Map<String, dynamic> r, String k) {
    final v = r[k];
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  static String _days(num v) =>
      v == 0 ? '–' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));

  String? _status(Map<String, dynamic> r) => r['payslip_status'] as String?;
  bool _isPublished(Map<String, dynamic> r) => _status(r) == 'published';
  bool _isDraft(Map<String, dynamic> r) => _status(r) == 'draft';

  List<Map<String, dynamic>> get _toIssue =>
      _rows.where((r) => !_isPublished(r) && _confirmed.contains(r['employee_id'])).toList();
  List<Map<String, dynamic>> get _drafts => _rows.where(_isDraft).toList();
  int get _published => _rows.where(_isPublished).length;
  /// 1 confirm, 2 generate, 3 review & publish, 4 all published. Someone
  /// still without a payslip keeps the run on steps 1-2.
  int get _step {
    if (_rows.isEmpty) return 1;
    if (_rows.every(_isPublished)) return 4;
    final notIssued = _rows.where((r) => _status(r) == null);
    if (notIssued.isNotEmpty) {
      return notIssued.any((r) => _confirmed.contains(r['employee_id'])) ? 2 : 1;
    }
    return 3;
  }

  // ── actions ────────────────────────────────────────────────────────────
  Future<void> _generate() async {
    final ids = _toIssue.map((r) => r['employee_id'] as String).toList();
    if (ids.isEmpty) return;
    await _run(() => SupabaseService.issuePayslips(_cycleEnd, employeeIds: ids),
        done: (out) => '${out.where((o) => o['outcome'] == 'draft').length} draft payslips ready to review.');
  }

  Future<void> _publish() async {
    final drafts = _drafts;
    if (drafts.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Publish ${drafts.length} payslip${drafts.length == 1 ? '' : 's'}?'),
        content: Text(
            'Each person will be able to see and download their $_label payslip, and will '
            'get a notification. Total net pay ${formatRupees(drafts.fold<num>(0, (s, r) => s + _n(r, 'net_pay')))}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
        () => SupabaseService.publishPayslips(_cycleEnd,
            employeeIds: drafts.map((r) => r['employee_id'] as String).toList()),
        done: (out) => '${out.length} payslips published. Employees have been notified.');
  }

  Future<void> _reissue(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reissue ${r['employee_name']}\'s payslip?'),
        content: const Text(
            'A new draft is calculated from the current records. The published payslip stays '
            'visible until you publish the new one, and is kept in the history after that.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reissue')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
        () => SupabaseService.issuePayslips(_cycleEnd,
            employeeIds: [r['employee_id'] as String], reissue: true),
        done: (_) => 'New draft ready. Publish it to replace the old payslip.');
  }

  Future<void> _run(Future<List<Map<String, dynamic>>> Function() call,
      {required String Function(List<Map<String, dynamic>>) done}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final out = await call();
      final missing = out
          .where((o) => o['outcome'] == 'no_salary_structure')
          .map((o) => o['employee_name'])
          .toList();
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(missing.isEmpty
            ? done(out)
            : '${done(out)} No salary structure for ${missing.join(', ')}.'),
      ));
      _confirmed.clear();
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        content: Text(_message(e)),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── layout ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: AppTheme.pageBackground,
      bottomNavigationBar: _rows.isEmpty ? null : _footer(wide),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 16, wide ? 28 : 16, 24),
          children: [
            Row(children: [
              const NavBackButton(),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Payroll – $_label',
                    style: TextStyle(fontSize: wide ? 26 : 20, fontWeight: FontWeight.w800)),
              ),
              _cyclePicker(),
              IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded)),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                  'Attendance cycle ${_d(_cycleStart)} – ${_d(_cycleEnd)} · closed'
                  '${_rows.isEmpty ? '' : ' · ${_rows.length} on payroll'}'
                  '${_published == 0 ? '' : ' · $_published published'}',
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ),
            const SizedBox(height: 16),
            _steps(wide),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              MCard(
                color: MobileUi.lopBg,
                borderColor: const Color(0xFFF5C2C2),
                child: Text('Could not load payroll: $_error', style: const TextStyle(color: MobileUi.lop)),
              )
            else if (_rows.isEmpty)
              const MCard(child: Text('No one is on payroll for this cycle.'))
            else ...[
              wide ? _table() : _cards(),
              const SizedBox(height: 14),
              MCard(
                color: const Color(0xFFFFFBEA),
                borderColor: const Color(0xFFF2DE8A),
                child: const Text.rich(TextSpan(children: [
                  TextSpan(text: 'Something wrong? Don\'t change the number here. '),
                  TextSpan(text: 'Fix the leave, permission or attendance record it comes from, then refresh: '
                      'the counts and the pay update. '),
                  TextSpan(text: 'LOP days', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' = unpaid leave + late LOP + permission LOP + days absent without leave. '
                      'Net pay is rounded to the nearest rupee.'),
                ])),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cyclePicker() => PopupMenuButton<DateTime>(
        tooltip: 'Choose cycle',
        onSelected: (d) {
          setState(() {
            _cycleEnd = d;
            _confirmed.clear();
          });
          _load();
        },
        itemBuilder: (_) => [
          for (final d in closedCycleEnds())
            PopupMenuItem(value: d, child: Text('${_months[d.month - 1]} ${d.year}')),
        ],
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
            Text(_label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_drop_down_rounded),
          ]),
        ),
      );

  Widget _steps(bool wide) {
    final step = _step;
    Widget card(int n, String title, String sub) {
      final active = step == n;
      final done = step > n;
      return MCard(
        borderColor: active ? AppTheme.primaryBlue : null,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(children: [
          if (done) ...[
            const Icon(Icons.check_circle_rounded, color: MobileUi.present, size: 20),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$n. $title', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(sub, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            ]),
          ),
        ]),
      );
    }

    final cards = [
      card(1, 'Confirm counts', 'Check each person\'s leave, permission and late counts'),
      card(2, 'Generate drafts', 'The system calculates every payslip'),
      card(3, 'Review & publish', 'Employees are notified and can download'),
    ];
    if (!wide) {
      return Column(children: [
        for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 8), child: c),
      ]);
    }
    return Row(children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(width: 12),
        Expanded(child: cards[i]),
      ],
    ]);
  }

  Widget _statusChip(Map<String, dynamic> r) {
    final s = _status(r);
    final v = _n(r, 'payslip_version').toInt();
    if (s == 'published') {
      return MChip(v > 1 ? 'Published v$v' : 'Published',
          color: MobileUi.present, background: MobileUi.presentBg);
    }
    if (s == 'draft') {
      return MChip(v > 1 ? 'Draft v$v' : 'Draft', color: MobileUi.late, background: MobileUi.lateBg);
    }
    return const MChip('Not issued', color: AppTheme.textSecondary, background: Color(0xFFEEF1F6));
  }

  Widget _confirmBox(Map<String, dynamic> r) {
    final id = r['employee_id'] as String;
    if (_isPublished(r)) {
      return PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (_) => _reissue(r),
        itemBuilder: (_) => const [PopupMenuItem(value: 'reissue', child: Text('Reissue payslip'))],
        icon: const Icon(Icons.more_vert_rounded),
      );
    }
    return Checkbox(
      value: _confirmed.contains(id),
      onChanged: _busy
          ? null
          : (v) => setState(() => v == true ? _confirmed.add(id) : _confirmed.remove(id)),
    );
  }

  String _perm(Map<String, dynamic> r) {
    final m = _n(r, 'permission_minutes').toInt();
    return m == 0 ? '–' : '$m min';
  }

  Widget _table() {
    const head = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textSecondary);
    final pending = _rows.where((r) => !_isPublished(r)).toList();
    final allConfirmed = pending.isNotEmpty && pending.every((r) => _confirmed.contains(r['employee_id']));
    DataCell num_(String text, {bool bold = false}) => DataCell(Align(
          alignment: Alignment.centerRight,
          child: Text(text, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        ));
    return MCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F6FB)),
          columnSpacing: 22,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          headingTextStyle: head,
          columns: [
            const DataColumn(label: Text('Employee')),
            const DataColumn(label: Text('Working\ndays'), numeric: true),
            const DataColumn(label: Text('Present'), numeric: true),
            const DataColumn(label: Text('CL'), numeric: true),
            const DataColumn(label: Text('ML'), numeric: true),
            const DataColumn(label: Text('EL'), numeric: true),
            const DataColumn(label: Text('Comp\noff'), numeric: true),
            const DataColumn(label: Text('Permission'), numeric: true),
            const DataColumn(label: Text('Late'), numeric: true),
            const DataColumn(label: Text('LOP\ndays'), numeric: true),
            const DataColumn(label: Text('Payable\ndays'), numeric: true),
            const DataColumn(label: Text('Net pay'), numeric: true),
            const DataColumn(label: Text('Payslip')),
            DataColumn(
              label: Row(children: [
                const Text('Confirm'),
                Checkbox(
                  value: allConfirmed,
                  onChanged: pending.isEmpty || _busy
                      ? null
                      : (v) => setState(() {
                            for (final r in pending) {
                              v == true
                                  ? _confirmed.add(r['employee_id'] as String)
                                  : _confirmed.remove(r['employee_id']);
                            }
                          }),
                ),
              ]),
            ),
          ],
          rows: [
            for (final r in _rows)
              DataRow(
                color: WidgetStateProperty.all(r['employee_id'] == widget.highlightEmployeeId
                    ? AppTheme.primaryBlue.withValues(alpha: 0.06)
                    : null),
                cells: [
                  DataCell(Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['employee_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${r['employee_id']} · ${r['department'] ?? ''}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  )),
                  num_('${_n(r, 'working_days')}'),
                  num_('${_n(r, 'days_present')}'),
                  num_(_days(_n(r, 'cl_used'))),
                  num_(_days(_n(r, 'ml_used'))),
                  num_(_days(_n(r, 'el_used'))),
                  num_(_days(_n(r, 'comp_off_used'))),
                  num_(_perm(r)),
                  num_(_days(_n(r, 'late_count'))),
                  num_(_days(_n(r, 'days_lost'))),
                  num_(_days(_n(r, 'payable_days'))),
                  num_(formatRupees(_n(r, 'net_pay')), bold: true),
                  DataCell(_statusChip(r)),
                  DataCell(Center(child: _confirmBox(r))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cards() => Column(children: [
        for (final r in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MCard(
              borderColor: r['employee_id'] == widget.highlightEmployeeId ? AppTheme.primaryBlue : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['employee_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${r['employee_id']} · ${r['department'] ?? ''}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ]),
                  ),
                  _statusChip(r),
                  _confirmBox(r),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  for (final (l, v) in [
                    ('Working', '${_n(r, 'working_days')}'),
                    ('Present', '${_n(r, 'days_present')}'),
                    ('CL', _days(_n(r, 'cl_used'))),
                    ('ML', _days(_n(r, 'ml_used'))),
                    ('EL', _days(_n(r, 'el_used'))),
                    ('Comp off', _days(_n(r, 'comp_off_used'))),
                    ('Permission', _perm(r)),
                    ('Late', _days(_n(r, 'late_count'))),
                    ('LOP days', _days(_n(r, 'days_lost'))),
                    ('Payable', _days(_n(r, 'payable_days'))),
                  ])
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '$l ', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
                      TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                    ])),
                ]),
                const SizedBox(height: 6),
                Text('Net pay ${formatRupees(_n(r, 'net_pay'))}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
          ),
      ]);

  Widget _footer(bool wide) {
    final pending = _rows.where((r) => !_isPublished(r)).length;
    final toIssue = _toIssue.length;
    final drafts = _drafts.length;
    final total = _rows.fold<num>(0, (s, r) => s + _n(r, 'net_pay'));
    return Container(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 10, wide ? 28 : 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MobileUi.line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
              pending == 0
                  ? 'All ${_rows.length} published · total net ${formatRupees(total)}'
                  : '${_confirmed.length} of $pending confirmed · total net ${formatRupees(total)}',
              style: const TextStyle(color: AppTheme.textSecondary)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (drafts > 0)
              OutlinedButton.icon(
                onPressed: _busy ? null : _publish,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text('Publish $drafts draft${drafts == 1 ? '' : 's'}'),
              ),
            if (drafts > 0) const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _busy || toIssue == 0 ? null : _generate,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.receipt_long_rounded, size: 18),
              label: Text(toIssue == 0
                  ? 'Generate payslips'
                  : 'Generate $toIssue payslip${toIssue == 1 ? '' : 's'}'),
            ),
          ]),
        ],
      ),
    );
  }
}
