import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_health_service.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_header_row.dart';

/// Management's view of what is going wrong in the app, in three tabs:
///
///  * Consistency — the nightly check's findings: figures that should agree
///    and do not (payslip against payroll, leave balance against approved
///    leave, check-ins with no check-out, failed money-rule tests).
///  * App errors — crashes and errors recorded on people's devices, and
///    database writes that failed.
///  * Problem reports — sent by staff with "Report a problem".
class AppHealthPage extends StatelessWidget {
  const AppHealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final pad = narrow ? 16.0 : 24.0;
    return DefaultTabController(
      length: 3,
      child: Material(
        color: null,
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, narrow ? 16 : 24, pad, 8),
            child: ResponsiveHeaderRow(
              icon: Icons.monitor_heart_rounded,
              color: AppTheme.primaryBlue,
              title: 'App Health',
              subtitle: 'Mismatches, errors and problem reports',
            ),
          ),
          TabBar(
            isScrollable: narrow,
            labelColor: AppTheme.primaryBlue,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primaryBlue,
            tabs: const [
              Tab(text: 'Consistency'),
              Tab(text: 'App errors'),
              Tab(text: 'Problem reports'),
            ],
          ),
          const Divider(height: 1),
          const Expanded(
            child: TabBarView(children: [
              _ConsistencyTab(),
              _IssuesTab(reports: false),
              _IssuesTab(reports: true),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────

String _fmtTime(dynamic v) {
  if (v == null) return '—';
  final dt = DateTime.tryParse(v.toString())?.toLocal();
  if (dt == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}, ${two(dt.hour)}:${two(dt.minute)}';
}

Color _severityColor(String? s) => switch (s) {
      'high' => AppTheme.error,
      'medium' => AppTheme.warning,
      _ => AppTheme.textSecondary,
    };

Widget _chip(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );

Widget _card({required Widget child, VoidCallback? onTap}) => Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );

Widget _segmented<T>({
  required T value,
  required Map<T, String> options,
  required ValueChanged<T> onChanged,
}) =>
    SegmentedButton<T>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value)),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );

Future<String?> _askNote(BuildContext context, String title, String hint) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save')),
      ],
    ),
  ).whenComplete(controller.dispose);
}

void _snack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppTheme.error : null,
  ));
}

Widget _empty(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
      ),
    );

// ── Consistency ─────────────────────────────────────────────────────────────

const _checkLabels = <String, String>{
  'payslip_generated_early': 'Payslip generated before cycle closed',
  'payslip_vs_payroll': 'Payslip does not match payroll',
  'payslip_vs_salary_master': 'Payslip gross differs from salary master',
  'payslip_identity': 'Payslip filed under wrong ID',
  'salary_components': 'Salary components do not add up',
  'profile_gross_vs_salary': 'Profile gross differs from salary master',
  'payroll_no_salary': 'On payroll with no salary structure',
  'leave_overdrawn': 'Leave balance overdrawn',
  'lop_despite_balance': 'LOP recorded although balance was available',
  'leave_figures_invalid': 'Leave figures cannot be right',
  'missing_checkout': 'Checked in, never checked out',
  'checkout_before_checkin': 'Check-out before check-in',
  'attended_on_leave': 'Checked in while on approved leave',
  'permission_charged_within_quota': 'Permission charged within quota',
  'orphaned_attendance': 'Attendance for no current employee',
  'attendance_identity_mismatch': 'Attendance under the wrong ID',
  'dangling_reporting_manager': 'Reporting manager not active',
  'money_rule_test': 'Money-rule test failed',
  'check_failed': 'A check could not run',
};

class _ConsistencyTab extends StatefulWidget {
  const _ConsistencyTab();
  @override
  State<_ConsistencyTab> createState() => _ConsistencyTabState();
}

class _ConsistencyTabState extends State<_ConsistencyTab>
    with AutomaticKeepAliveClientMixin {
  String _state = 'open';
  bool _loading = true;
  bool _running = false;
  String? _error;
  Map<String, dynamic>? _run;
  List<Map<String, dynamic>> _rows = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        AppHealthService.latestRun(),
        AppHealthService.findings(_state),
      ]);
      if (!mounted) return;
      setState(() {
        _run = results[0] as Map<String, dynamic>?;
        _rows = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _runNow() async {
    setState(() => _running = true);
    try {
      final r = await AppHealthService.runChecksNow();
      if (!mounted) return;
      _snack(context,
          'Check finished: ${r['findings_new'] ?? 0} new, '
          '${r['findings_resolved'] ?? 0} resolved, ${r['findings_open'] ?? 0} open.');
    } catch (e) {
      if (mounted) _snack(context, 'The check could not run: $e', error: true);
    }
    if (mounted) setState(() => _running = false);
    _load();
  }

  Future<void> _toggleAck(Map<String, dynamic> f) async {
    final ack = f['acknowledged_at'] == null;
    String? note;
    if (ack) {
      note = await _askNote(context, 'Mark as known',
          'Why this is accepted, e.g. "Agreed with Management on 10 Nov"');
      if (note == null) return;
    }
    try {
      await AppHealthService.acknowledgeFinding((f['id'] as num).toInt(),
          acknowledge: ack, note: note);
      if (mounted) {
        Navigator.of(context).maybePop();
        _snack(context, ack ? 'Marked as known' : 'Reopened');
      }
    } catch (e) {
      if (mounted) _snack(context, 'Could not update: $e', error: true);
    }
    _load();
  }

  void _openDetails(Map<String, dynamic> f) {
    final details = f['details'];
    final pretty = const JsonEncoder.withIndent('  ').convert(details ?? {});
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_checkLabels[f['check_code']] ?? (f['check_code'] as String? ?? '')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(f['title'] as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if ((f['employee_name'] ?? f['employee_id']) != null)
                Text('Employee: ${f['employee_name'] ?? ''} ${f['employee_id'] != null ? '(${f['employee_id']})' : ''}'),
              Text('First seen: ${_fmtTime(f['first_seen_at'])}'),
              Text('Last seen: ${_fmtTime(f['last_seen_at'])}'),
              if (f['resolved_at'] != null) Text('Resolved: ${_fmtTime(f['resolved_at'])}'),
              if (f['acknowledged_at'] != null)
                Text('Marked as known by ${f['acknowledged_by'] ?? ''} on '
                    '${_fmtTime(f['acknowledged_at'])}'
                    '${(f['ack_note'] as String?)?.isNotEmpty == true ? ': ${f['ack_note']}' : ''}'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(pretty,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          if (f['resolved_at'] == null)
            FilledButton(
              onPressed: () => _toggleAck(f),
              child: Text(f['acknowledged_at'] == null ? 'Mark as known' : 'Reopen'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final run = _run;
    final testsFailed = (run?['tests_failed'] as num?)?.toInt() ?? 0;
    final testsPassed = (run?['tests_passed'] as num?)?.toInt() ?? 0;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(run == null ? 'The check has not run yet' : 'Last check: ${_fmtTime(run['started_at'])}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    run == null
                        ? 'It runs every night at 01:30.'
                        : '${run['findings_open'] ?? 0} open · ${run['findings_new'] ?? 0} new · '
                          '${run['findings_resolved'] ?? 0} resolved · runs nightly at 01:30',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ]),
                if (run != null)
                  _chip('Money-rule tests: $testsPassed passed'
                        '${testsFailed > 0 ? ', $testsFailed failed' : ''}',
                      testsFailed > 0 ? AppTheme.error : AppTheme.success),
                FilledButton.icon(
                  onPressed: _running ? null : _runNow,
                  icon: _running
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(_running ? 'Running…' : 'Run now'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: _segmented<String>(
              value: _state,
              options: const {'open': 'Open', 'acknowledged': 'Known', 'resolved': 'Resolved'},
              onChanged: (v) { setState(() => _state = v); _load(); },
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            _empty('Could not load findings: $_error')
          else if (_rows.isEmpty)
            _empty(_state == 'open' ? 'Nothing open. Everything that should agree does.' : 'Nothing here.')
          else
            for (final f in _rows) ...[
              _card(
                onTap: () => _openDetails(f),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 4, height: 40,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: _severityColor(f['severity'] as String?),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(f['title'] as String? ?? '',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        [
                          _checkLabels[f['check_code']] ?? f['check_code'],
                          if (f['employee_name'] != null) f['employee_name'],
                          'since ${_fmtTime(f['first_seen_at'])}',
                        ].join('  ·  '),
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  _chip((f['severity'] as String? ?? '').toUpperCase(),
                      _severityColor(f['severity'] as String?)),
                ]),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

// ── App errors and problem reports ──────────────────────────────────────────

class _IssuesTab extends StatefulWidget {
  final bool reports;
  const _IssuesTab({required this.reports});
  @override
  State<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<_IssuesTab> with AutomaticKeepAliveClientMixin {
  String _status = 'open';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await AppHealthService.issues(reports: widget.reports, status: _status);
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Errors that are the same failure (same kind, screen and first line)
  /// are shown once with a count; reports are always shown one by one.
  List<List<Map<String, dynamic>>> get _groups {
    if (widget.reports) return [for (final r in _rows) [r]];
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      final key = (r['fingerprint'] as String?) ?? 'id-${r['id']}';
      byKey.putIfAbsent(key, () => []).add(r);
    }
    return byKey.values.toList();
  }

  Future<void> _toggleResolved(List<Map<String, dynamic>> group) async {
    final resolve = group.first['status'] != 'resolved';
    String? note;
    if (resolve) {
      note = await _askNote(context, 'Mark as resolved', 'What was done (optional)');
      if (note == null) return;
    }
    try {
      for (final r in group) {
        await AppHealthService.resolveIssue((r['id'] as num).toInt(),
            resolved: resolve, note: note);
      }
      if (mounted) {
        Navigator.of(context).maybePop();
        _snack(context, resolve ? 'Marked as resolved' : 'Reopened');
      }
    } catch (e) {
      if (mounted) _snack(context, 'Could not update: $e', error: true);
    }
    _load();
  }

  void _openDetails(List<Map<String, dynamic>> group) {
    final r = group.first;
    final path = r['screenshot_path'] as String?;
    final context0 = r['context'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.reports ? 'Problem report' : _kindLabel(r['kind'] as String?)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              SelectableText(
                  (widget.reports ? r['user_note'] : r['message']) as String? ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('From: ${r['employee_name'] ?? r['user_email'] ?? 'not signed in'}'
                  '${r['employee_id'] != null ? ' (${r['employee_id']})' : ''}'
                  '${r['user_role'] != null ? ' · ${r['user_role']}' : ''}'),
              Text('Screen: ${(r['screen'] as String?)?.isNotEmpty == true ? r['screen'] : '—'}'),
              Text('When: ${_fmtTime(r['occurred_at'])}'
                  '${group.length > 1 ? '  (${group.length} times, first ${_fmtTime(group.last['occurred_at'])})' : ''}'),
              Text('Device: ${r['platform'] ?? '—'} · app ${r['app_version'] ?? '—'}'),
              if (r['status'] == 'resolved')
                Text('Resolved by ${r['resolved_by'] ?? ''} on ${_fmtTime(r['resolved_at'])}'
                    '${(r['resolution_note'] as String?)?.isNotEmpty == true ? ': ${r['resolution_note']}' : ''}'),
              if (group.length > 1) ...[
                const SizedBox(height: 6),
                Text('Seen by: ${{for (final g in group) g['employee_name'] ?? g['user_email'] ?? 'not signed in'}.join(', ')}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ],
              if (path != null) ...[
                const SizedBox(height: 12),
                FutureBuilder<String?>(
                  future: AppHealthService.screenshotUrl(path),
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()));
                    }
                    final url = snap.data;
                    if (url == null) return const Text('Screenshot could not be loaded.');
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(url, fit: BoxFit.contain),
                    );
                  },
                ),
              ],
              if ((r['stack'] as String?)?.isNotEmpty == true ||
                  (context0 is Map && context0.isNotEmpty)) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    [
                      if (context0 is Map && context0.isNotEmpty)
                        const JsonEncoder.withIndent('  ').convert(context0),
                      if ((r['stack'] as String?)?.isNotEmpty == true) r['stack'] as String,
                    ].join('\n\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () => _toggleResolved(group),
            child: Text(r['status'] == 'resolved' ? 'Reopen' : 'Mark as resolved'),
          ),
        ],
      ),
    );
  }

  static String _kindLabel(String? kind) => switch (kind) {
        'crash' => 'Crash',
        'write_failed' => 'Save failed',
        _ => 'Error',
      };

  static Color _kindColor(String? kind) => switch (kind) {
        'crash' => AppTheme.error,
        'write_failed' => AppTheme.warning,
        _ => AppTheme.purple,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final groups = _groups;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            _segmented<String>(
              value: _status,
              options: const {'open': 'Open', 'resolved': 'Resolved', 'all': 'All'},
              onChanged: (v) { setState(() => _status = v); _load(); },
            ),
            const Spacer(),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
          ]),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            _empty('Could not load: $_error')
          else if (groups.isEmpty)
            _empty(widget.reports
                ? 'No problem reports. Staff can send one with the bug icon at the top of any screen.'
                : 'No errors recorded.')
          else
            for (final g in groups) ...[
              _card(
                onTap: () => _openDetails(g),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!widget.reports) ...[
                    _chip(_kindLabel(g.first['kind'] as String?), _kindColor(g.first['kind'] as String?)),
                    const SizedBox(width: 10),
                  ] else if (g.first['screenshot_path'] != null) ...[
                    Icon(Icons.image_outlined, size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        ((widget.reports ? g.first['user_note'] : g.first['message']) as String? ?? '')
                            .split('\n').first,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          g.first['employee_name'] ?? g.first['user_email'] ?? 'not signed in',
                          if ((g.first['screen'] as String?)?.isNotEmpty == true) g.first['screen'],
                          _fmtTime(g.first['occurred_at']),
                        ].join('  ·  '),
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ]),
                  ),
                  if (g.length > 1) ...[
                    const SizedBox(width: 8),
                    _chip('×${g.length}', AppTheme.textSecondary),
                  ],
                ]),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}
