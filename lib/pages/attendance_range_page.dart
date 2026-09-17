import 'package:flutter/material.dart';

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
          // Chips rather than a dropdown: picking three people from a list of
          // sixteen is the whole point, and a single-select control was what
          // made this impossible before.
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final u in _users)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(u.name, style: const TextStyle(fontSize: 11.5)),
                      selected: _selected.contains(u.employeeId),
                      onSelected: (on) => setState(() => on
                          ? _selected.add(u.employeeId)
                          : _selected.remove(u.employeeId)),
                    ),
                  ),
              ],
            ),
          ),
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
