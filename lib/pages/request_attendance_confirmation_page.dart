import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../widgets/back_button.dart';

/// Last resort when a device cannot produce the evidence check-in requires —
/// camera blocked, location denied, no GPS fix. The employee states the time
/// they arrived, their reporting manager confirms it, and HR approves
/// separately before it becomes a paid day.
///
/// Deliberately not a way around the selfie: it is capped at two days a week,
/// enforced in the database, and the resulting attendance record is marked
/// `vouched` and counted separately in the pay-cycle sheet. HR can lift the
/// cap with a dated exception where a device persistently cannot comply.
class RequestAttendanceConfirmationPage extends StatefulWidget {
  const RequestAttendanceConfirmationPage({super.key});

  @override
  State<RequestAttendanceConfirmationPage> createState() =>
      _RequestAttendanceConfirmationPageState();
}

class _RequestAttendanceConfirmationPageState
    extends State<RequestAttendanceConfirmationPage> {
  static Color get _color => Colors.indigo.shade600;

  DateTime _date = DateTime.now();
  final _timeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  bool _checking = true;
  ({bool allowed, int used, int cap, String reason})? _limit;
  List<Map<String, dynamic>> _mine = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _timeCtrl.text =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    _load();
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _checking = true);
    final limit =
        await SupabaseService.canVouchAttendance(UserSession.employeeId, _date);
    final mine = await SupabaseService.fetchAttendanceConfirmations();
    if (!mounted) return;
    setState(() {
      _limit = limit;
      _mine = mine.where((r) => r['employee_id'] == UserSession.employeeId).toList();
      _checking = false;
    });
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // Backdated only a week: this exists for a device that failed today or
      // yesterday, not for reconstructing an old pay cycle from memory.
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load();
    }
  }

  Future<void> _submit() async {
    if (_noteCtrl.text.trim().isEmpty) {
      _snack('Please say what happened when you tried to check in.');
      return;
    }
    setState(() => _busy = true);
    final err = await SupabaseService.requestAttendanceConfirmation(
      date: _date,
      claimedTime: _timeCtrl.text.trim(),
      employeeNote: _noteCtrl.text.trim(),
      failureReason: 'Reported by employee',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _snack('Could not submit: $err');
      return;
    }
    _snack('Sent to your reporting manager.');
    _noteCtrl.clear();
    _load();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  String _statusLabel(Map<String, dynamic> r) {
    final mgr = (r['status'] ?? 'pending').toString();
    final hr = (r['hr_status'] ?? 'pending').toString();
    if (mgr == 'rejected') return 'Declined by manager';
    if (hr == 'rejected') return 'Declined by HR';
    if (mgr == 'confirmed' && hr == 'approved') return 'Approved';
    if (mgr == 'confirmed') return 'With HR';
    return 'With manager';
  }

  Color _statusColor(String label) => switch (label) {
        'Approved' => Colors.green.shade700,
        'Declined by manager' || 'Declined by HR' => Colors.red.shade700,
        _ => Colors.orange.shade700,
      };

  @override
  Widget build(BuildContext context) {
    final limit = _limit;
    final blocked = limit != null && !limit.allowed;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NavBackButton(),
            const SizedBox(height: 8),
            Text('Ask Manager to Confirm Attendance',
                style: TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w700, color: _color)),
            const SizedBox(height: 6),
            const Text(
              'Use this only when the app could not record your check-in — the '
              'camera would not open, or your location could not be read. Your '
              'reporting manager confirms you were present, then HR approves. '
              'The day is recorded as manager-confirmed rather than verified.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 18),

            if (_checking)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              if (limit != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: blocked ? Colors.red.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: blocked ? Colors.red.shade200 : Colors.blue.shade200),
                  ),
                  child: Row(children: [
                    Icon(blocked ? Icons.block_rounded : Icons.info_outline_rounded,
                        size: 16,
                        color: blocked ? Colors.red.shade700 : Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        blocked
                            ? 'Cannot request for this date — ${limit.reason}. '
                              'Speak to HR if your device cannot check in at all.'
                            : '${limit.used} of ${limit.cap} used this week — ${limit.reason}.',
                        style: TextStyle(
                            fontSize: 12,
                            color: blocked ? Colors.red.shade900 : Colors.blue.shade900),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 14),

              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(_fmt(_date)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _color,
                  minimumSize: const Size(double.infinity, 46),
                  alignment: Alignment.centerLeft,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _timeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Time you arrived (HH:MM)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'What happened when you tried to check in? *',
                  hintText: 'e.g. camera would not open on my phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_busy || blocked) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _color,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(_busy ? 'Sending…' : 'Send to Manager'),
                ),
              ),
            ],

            if (_mine.isNotEmpty) ...[
              const SizedBox(height: 26),
              const Text('My Requests',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final r in _mine)
                Builder(builder: (_) {
                  final label = _statusLabel(r);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      title: Text(
                          '${r['date_iso'] ?? ''}  ·  ${r['claimed_time'] ?? ''}',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text((r['employee_note'] ?? '').toString(),
                          style: const TextStyle(fontSize: 12)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _statusColor(label).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _statusColor(label))),
                      ),
                    ),
                  );
                }),
            ],
          ]),
        ),
      ),
    );
  }
}
