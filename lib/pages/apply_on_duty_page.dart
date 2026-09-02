import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../widgets/back_button.dart';

/// Employee-raised request to record a day as On Duty — business work
/// outside normal hours, such as BTL activity or site/project work.
///
/// Deliberately not part of the leave pages: On Duty is presence, not
/// absence. Routing it through leave_applications would have deducted a
/// casual leave, because an unrecognised leave type falls through
/// LeaveStore.effectiveBucket() to 'CL'.
class ApplyOnDutyPage extends StatefulWidget {
  const ApplyOnDutyPage({super.key});

  @override
  State<ApplyOnDutyPage> createState() => _ApplyOnDutyPageState();
}

class _ApplyOnDutyPageState extends State<ApplyOnDutyPage> {
  static Color get _color => Colors.orange.shade700;

  static const _reasons = [
    'BTL Activity',
    'Site Visit',
    'Project Work',
    'Client Meeting',
    'Event / Exhibition',
    'Others',
  ];

  DateTime? _date;
  String _reason = _reasons.first;
  final _detailController = TextEditingController();
  bool _busy = false;
  List<Map<String, dynamic>> _mine = const [];

  bool get _isOthers => _reason == 'Others';

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    final rows = await SupabaseService.fetchOnDutyRequests();
    if (!mounted) return;
    setState(() => _mine = rows);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      // Backdated requests are allowed: night work is often only recorded
      // the following morning. Bounded at 30 days so it can't be used to
      // rewrite an old pay cycle.
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_date == null) { _snack('Please select the date.'); return; }
    if (_isOthers && _detailController.text.trim().isEmpty) {
      _snack('Please describe the work.'); return;
    }
    final detail = _detailController.text.trim();
    final reason = _isOthers ? detail : (detail.isEmpty ? _reason : '$_reason — $detail');

    setState(() => _busy = true);
    final err = await SupabaseService.requestOnDuty(
      employeeId: UserSession.employeeId,
      employeeName: UserSession.name,
      date: _date!,
      reason: reason,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (err != null) {
      _snack('Could not submit: $err');
      return;
    }
    _snack('On Duty request submitted for approval.');
    setState(() { _date = null; _reason = _reasons.first; });
    _detailController.clear();
    _loadMine();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Color _statusColor(String s) => switch (s) {
        'approved' => Colors.green.shade700,
        'denied' => Colors.red.shade700,
        _ => Colors.orange.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const NavBackButton(),
            const SizedBox(height: 8),
            Text('Apply for On Duty',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: _color)),
            const SizedBox(height: 6),
            const Text(
              'For work outside normal hours on company business. This is not '
              'leave — the day counts as present, and late or early timing '
              'rules will not be applied to it once approved.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: Text(_date == null ? 'Select date' : _fmt(_date!)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _color,
                side: BorderSide(color: Colors.orange.shade300),
                minimumSize: const Size(double.infinity, 48),
                alignment: Alignment.centerLeft,
              ),
            ),
            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
              items: _reasons
                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                  .toList(),
              onChanged: (v) => setState(() => _reason = v ?? _reasons.first),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _detailController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _isOthers ? 'Describe the work *' : 'Details (optional)',
                hintText: 'e.g. BTL campaign at Higrove until 10pm',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(_busy ? 'Submitting…' : 'Submit Request'),
              ),
            ),

            if (_mine.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text('My Requests',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final r in _mine)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text((r['date_iso'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    subtitle: Text((r['reason'] ?? '').toString(),
                        style: const TextStyle(fontSize: 12)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor((r['status'] ?? '').toString())
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        (r['status'] ?? '').toString().toUpperCase(),
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _statusColor((r['status'] ?? '').toString())),
                      ),
                    ),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}
