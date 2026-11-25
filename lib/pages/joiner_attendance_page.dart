import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

/// New joiners, first month: working days between the date of joining and
/// the day the app account opened that have no attendance. Until HR marks
/// a day Present it is unpaid like any other absence. Found every morning
/// by find_joiner_attendance_gaps(), which also notifies HR (rule agreed
/// with Ronak, 25 Nov 2026).
class JoinerAttendancePage extends StatefulWidget {
  const JoinerAttendancePage({super.key});
  @override
  State<JoinerAttendancePage> createState() => _JoinerAttendancePageState();
}

class _Gap {
  final String employeeId;
  final String name;
  final DateTime day;
  final DateTime? joined;
  final DateTime? accountOn;
  final String? resolution;
  final String resolvedBy;
  final String note;
  _Gap(this.employeeId, this.name, this.day, this.joined, this.accountOn, this.resolution,
      this.resolvedBy, this.note);

  factory _Gap.fromMap(Map<String, dynamic> m) {
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    return _Gap(
      (m['employee_id'] as String?) ?? '',
      (m['employee_name'] as String?) ?? '',
      d(m['day']) ?? DateTime.now(),
      d(m['date_of_joining']),
      d(m['account_active_on']),
      m['resolution'] as String?,
      (m['resolved_by'] as String?) ?? '',
      (m['note'] as String?) ?? '',
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _fmt(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

class _JoinerAttendancePageState extends State<JoinerAttendancePage> {
  List<_Gap> _gaps = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('joiner_attendance_gaps')
          .select()
          .order('day', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _gaps = (rows as List)
            .map((r) => _Gap.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the list. Pull down to try again.';
      });
    }
  }

  String _key(_Gap g) => '${g.employeeId}|${g.day.toIso8601String()}';

  Future<void> _decide(_Gap g, bool present) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(present ? 'Mark present' : 'Mark absent'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            present
                ? '${g.name} worked on ${_fmt(g.day)}. The day is recorded at office hours and paid.'
                : '${g.name} did not work on ${_fmt(g.day)}. The day stays unpaid.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: note,
            decoration: const InputDecoration(
                labelText: 'Note (optional)', border: OutlineInputBorder(), isDense: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(_key(g)));
    String? err;
    try {
      await Supabase.instance.client.rpc('resolve_joiner_gap', params: {
        'p_employee_id': g.employeeId,
        'p_day': '${g.day.year.toString().padLeft(4, '0')}-${g.day.month.toString().padLeft(2, '0')}-'
            '${g.day.day.toString().padLeft(2, '0')}',
        'p_present': present,
        'p_note': note.text.trim(),
      });
    } catch (e) {
      err = e is PostgrestException && e.message.trim().isNotEmpty
          ? e.message.trim()
          : 'Something went wrong. Please try again.';
    }
    if (!mounted) return;
    setState(() => _busy.remove(_key(g)));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? (present ? 'Marked present.' : 'Marked absent.')),
      backgroundColor: err == null ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
    if (err == null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final open = _gaps.where((g) => g.resolution == null).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    final done = _gaps.where((g) => g.resolution != null).toList();
    final byPerson = <String, List<_Gap>>{};
    for (final g in open) {
      byPerson.putIfAbsent(g.employeeId, () => []).add(g);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(narrow ? 16 : 28),
        children: [
          Text('New joiners: days before the account opened',
              style: TextStyle(
                  fontSize: narrow ? 19 : 23, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue)),
          const SizedBox(height: 6),
          const Text(
            'A new joiner can only check in once their app account is open. For their first month, '
            'each working day from the joining date to the day before the account opened that has no '
            'attendance or leave is listed here, and HR is notified every morning. Mark the days they '
            'worked as Present; until then the day is unpaid.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: TextStyle(color: Colors.red.shade700))
          else ...[
            if (byPerson.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: Text('Nothing to confirm.', style: TextStyle(color: AppTheme.textSecondary))),
              ),
            for (final entry in byPerson.entries)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${entry.value.first.name}  ·  ${entry.key}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      'Joined ${entry.value.first.joined == null ? '-' : _fmt(entry.value.first.joined!)}'
                      ' · account opened ${entry.value.first.accountOn == null ? '-' : _fmt(entry.value.first.accountOn!)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    for (final g in entry.value)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text(_fmt(g.day), style: const TextStyle(fontSize: 13))),
                          if (_busy.contains(_key(g)))
                            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          else ...[
                            OutlinedButton(
                              onPressed: () => _decide(g, false),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                              child: const Text('Absent'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _decide(g, true),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                              child: const Text('Present'),
                            ),
                          ],
                        ]),
                      ),
                  ]),
                ),
              ),
            if (done.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Decided',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              for (final g in done)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${g.name} · ${_fmt(g.day)}', style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      '${g.resolution == 'present' ? 'Present' : 'Absent'} · ${g.resolvedBy}'
                      '${g.note.isNotEmpty ? ' · ${g.note}' : ''}',
                      style: const TextStyle(fontSize: 12)),
                  trailing: Icon(
                      g.resolution == 'present' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: g.resolution == 'present' ? Colors.green.shade600 : Colors.red.shade400,
                      size: 18),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
