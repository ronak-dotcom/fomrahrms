import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/csv_export.dart';

import '../models/app_user.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../widgets/back_button.dart';

/// Attendance for any date range, for one person or several.
///
/// The records screen answers "who was in on this day" and the cycle report
/// answers "how did this cycle go". Neither answers "these three people, from
/// 1 May to 7 July" — that had to be assembled by opening each person and each
/// cycle in turn, which is not a report so much as a morning's work.
class AttendanceRangePage extends StatefulWidget {
  const AttendanceRangePage({super.key});

  @override
  State<AttendanceRangePage> createState() => _AttendanceRangePageState();
}

class _AttendanceRangePageState extends State<AttendanceRangePage> {
  bool _loading = false;
  List<AppUser> _users = const [];
  final Set<String> _selected = {};
  DateTimeRange _range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  List<Map<String, dynamic>> _rows = const [];
  bool _ran = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final all = await UserStore.load();
    if (!mounted) return;
    setState(() {
      _users = all
          .where((u) =>
              u.active && u.countsInHeadcount && !u.exemptFromAttendance)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _pickEmployees() async {
    // Edited on a copy so Cancel genuinely cancels rather than leaving half a
    // selection behind.
    final working = Set<String>.from(_selected);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Select employees'),
          content: SizedBox(
            width: 340,
            height: 400,
            child: Column(children: [
              Row(children: [
                TextButton(
                  onPressed: () => setS(working.clear),
                  child: const Text('All employees', style: TextStyle(fontSize: 12)),
                ),
                const Spacer(),
                Text('${working.length} selected',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
              ]),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (final u in _users)
                      CheckboxListTile(
                        dense: true,
                        value: working.contains(u.employeeId),
                        title: Text(u.name, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(u.employeeId,
                            style: const TextStyle(fontSize: 11)),
                        onChanged: (on) => setS(() => on == true
                            ? working.add(u.employeeId)
                            : working.remove(u.employeeId)),
                      ),
                  ],
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Done')),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _selected
          ..clear()
          ..addAll(working);
      });
    }
  }

  /// Rows as CSV. Excel opens this directly.
  String _csv() {
    String esc(Object? v) {
      final t = (v ?? '').toString();
      // Quote anything containing a separator, or a name with a comma splits
      // into two columns and every column after it shifts.
      return t.contains(',') || t.contains('"') || t.contains('\n')
          ? '"${t.replaceAll('"', '""')}"'
          : t;
    }

    final b = StringBuffer()
      ..writeln('Employee,Employee ID,Department,Date,Day,Check In,Check Out,'
          'Hours,Status,Verification,Note');
    for (final r in _rows) {
      b.writeln([
        esc(r['employee_name']), esc(r['employee_id']), esc(r['department']),
        esc(r['date_iso']), esc(r['day_name']),
        esc(r['check_in_time']), esc(r['check_out_time']),
        esc(r['hours_worked']), esc(r['status']),
        esc(r['verification']), esc(r['note']),
      ].join(','));
    }
    return b.toString();
  }

  Future<void> _exportCsv() async {
    await exportCsv(
      'attendance_${_fileStamp(_range.start)}_to_${_fileStamp(_range.end)}.csv',
      _csv(),
    );
  }

  Future<void> _exportPdf() async {
    final doc = pw.Document();
    // Grouped by person in the PDF as well, so a printed copy reads the same
    // way as the screen.
    final byPerson = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      byPerson.putIfAbsent((r['employee_name'] ?? '').toString(), () => []).add(r);
    }
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              'Attendance  ${_d(_range.start)} – ${_d(_range.end)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
          for (final e in byPerson.entries) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              '${e.key}   '
              '${e.value.where((r) => r['status'] == 'Present').length}P  '
              '${e.value.where((r) => r['status'] == 'Late').length}L  '
              '${e.value.where((r) => r['status'] == 'Absent').length}A',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle:
                  pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              headers: const ['Date', 'Day', 'In', 'Out', 'Hours', 'Status'],
              data: [
                for (final r in e.value)
                  [
                    (r['date_iso'] ?? '').toString(),
                    (r['day_name'] ?? '').toString(),
                    (r['check_in_time'] ?? '').toString(),
                    (r['check_out_time'] ?? '').toString(),
                    (r['hours_worked'] ?? '').toString(),
                    (r['status'] ?? '').toString(),
                  ],
              ],
            ),
          ],
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename:
          'attendance_${_fileStamp(_range.start)}_to_${_fileStamp(_range.end)}.pdf',
    );
  }

  static String _fileStamp(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _run() async {
    setState(() => _loading = true);
    final rows = await SupabaseService.fetchAttendanceRange(
      from: _range.start,
      to: _range.end,
      // Empty means everyone, which is a useful default rather than an error.
      employeeIds: _selected.isEmpty ? null : _selected.toList(),
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
      _ran = true;
    });
  }

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Color _statusColour(String s) {
    if (s == 'Present') return Colors.green.shade700;
    if (s == 'Late') return Colors.orange.shade800;
    if (s == 'Absent') return Colors.red.shade700;
    if (s == 'On Duty') return Colors.indigo.shade600;
    if (s.contains('Off') || s.contains('Holiday')) return Colors.grey.shade500;
    return Colors.blue.shade700; // leave types
  }

  @override
  Widget build(BuildContext context) {
    // Grouped by person: a flat list of 200 rows across three people is
    // harder to read than three blocks, and the question is usually about a
    // person rather than a date.
    final byPerson = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      byPerson.putIfAbsent((r['employee_name'] ?? '').toString(), () => [])
          .add(r);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: NavBackButton(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text('Attendance by Date Range',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              _selected.isEmpty
                  ? 'All employees · ${_d(_range.start)} to ${_d(_range.end)}'
                  : '${_selected.length} selected · '
                    '${_d(_range.start)} to ${_d(_range.end)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_rounded, size: 16),
                  label: const Text('Dates'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _run,
                  icon: const Icon(Icons.search_rounded, size: 16),
                  label: Text(_loading ? 'Loading…' : 'Run'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          // A picker rather than a row of chips: sixteen chips scroll off
          // screen, so you cannot see who you have already selected — which
          // defeats the point when the task is choosing three specific people.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: _pickEmployees,
              icon: const Icon(Icons.people_alt_outlined, size: 16),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _selected.isEmpty
                      ? 'All employees'
                      : _users
                          .where((u) => _selected.contains(u.employeeId))
                          .map((u) => u.name)
                          .join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
          // Only once there is something to export. Buttons that produce an
          // empty file are worse than no buttons.
          if (_ran && _rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.table_view_rounded, size: 16),
                    label: const Text('Excel (CSV)',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: const Text('PDF', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (!_ran)
            const Expanded(
              child: Center(
                child: Text('Choose dates and people, then Run.',
                    style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else if (_rows.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No records in that range.',
                    style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  for (final entry in byPerson.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Row(children: [
                        Expanded(
                          child: Text(entry.key,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                        // A per-person tally, because the reason for asking is
                        // usually to compare people rather than read every row.
                        Text(
                          '${entry.value.where((r) => r['status'] == 'Present').length}P · '
                          '${entry.value.where((r) => r['status'] == 'Late').length}L · '
                          '${entry.value.where((r) => r['status'] == 'Absent').length}A',
                          style: const TextStyle(
                              fontSize: 11.5, color: Color(0xFF6B7280)),
                        ),
                      ]),
                    ),
                    for (final r in entry.value)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              '${(r['date_iso'] ?? '').toString().substring(8, 10)}/'
                              '${(r['date_iso'] ?? '').toString().substring(5, 7)} '
                              '${r['day_name'] ?? ''}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          SizedBox(
                            width: 96,
                            child: Text(
                              (r['check_in_time'] ?? '').toString().isEmpty
                                  ? '—'
                                  : '${r['check_in_time']} – '
                                    '${(r['check_out_time'] ?? '').toString().isEmpty ? '?' : r['check_out_time']}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                          SizedBox(
                            width: 46,
                            child: Text(
                              r['hours_worked'] == null
                                  ? ''
                                  : '${r['hours_worked']}h',
                              style: const TextStyle(
                                  fontSize: 11.5, color: Color(0xFF6B7280)),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              (r['status'] ?? '').toString(),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _statusColour(
                                      (r['status'] ?? '').toString())),
                            ),
                          ),
                        ]),
                      ),
                    const Divider(height: 18),
                  ],
                ],
              ),
            ),
        ]),
      ),
    );
  }
}
