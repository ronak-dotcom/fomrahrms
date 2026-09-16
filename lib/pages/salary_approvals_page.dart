import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../widgets/back_button.dart';

/// Where Management decides salary changes.
///
/// The pending list could only say "Gross 20,208 → 22,708", which tells you
/// the total moved but not which parts did — Basic, DA, EPF and the rest could
/// all have changed unseen. Approving that is signing for figures you have not
/// been shown.
///
/// Only the fields that actually differ are listed. Showing all thirteen every
/// time buries the two or three that moved, and a salary change is usually
/// small and specific.
class SalaryApprovalsPage extends StatefulWidget {
  const SalaryApprovalsPage({super.key});

  @override
  State<SalaryApprovalsPage> createState() => _SalaryApprovalsPageState();
}

class _SalaryApprovalsPageState extends State<SalaryApprovalsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _requests = const [];
  final Map<String, List<Map<String, dynamic>>> _history = {};

  /// Field name to label, in the order they appear on a payslip.
  static const _labels = <String, String>{
    'actual_gross': 'Gross',
    'basic': 'Basic',
    'da': 'DA',
    'hra': 'HRA',
    'conveyance': 'Conveyance',
    'other_allowance': 'Other Allowance',
    'educational': 'Educational',
    'lta': 'LTA',
    'professional_tax': 'Professional Tax',
    'epf': 'EPF',
    'esi': 'ESI',
    'tds': 'TDS',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final reqs = await SupabaseService.fetchSalaryChangeRequests();
    for (final r in reqs) {
      final id = (r['employee_id'] ?? '').toString();
      _history[id] = await SupabaseService.fetchSalaryHistory(id, limit: 5);
    }
    if (!mounted) return;
    setState(() {
      _requests = reqs;
      _loading = false;
    });
  }

  static double _n(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static String _money(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(2);

  /// Only the fields that moved.
  List<({String label, double from, double to})> _changedFields(
      Map<String, dynamic> r) {
    final now = (r['current_value'] as Map?)?.cast<String, dynamic>() ?? {};
    final next = (r['proposed'] as Map?)?.cast<String, dynamic>() ?? {};
    final out = <({String label, double from, double to})>[];
    for (final e in _labels.entries) {
      final a = _n(now[e.key]);
      final b = _n(next[e.key]);
      // Gross is listed even when unchanged: it is the figure the decision is
      // really about, and its absence would read as an oversight.
      if (a != b || e.key == 'actual_gross') {
        out.add((label: e.value, from: a, to: b));
      }
    }
    return out;
  }

  /// Added, removed or amended extras.
  List<String> _customChanges(Map<String, dynamic> r) {
    Map<String, double> asMap(dynamic list) => {
          for (final c in (list as List? ?? const []))
            (c['label'] ?? '').toString(): _n(c['amount']),
        };
    final now = asMap((r['current_value'] as Map?)?['custom_components']);
    final next = asMap((r['proposed'] as Map?)?['custom_components']);
    final out = <String>[];
    for (final e in next.entries) {
      if (!now.containsKey(e.key)) {
        out.add('Added · ${e.key} ${_money(e.value)}');
      } else if (now[e.key] != e.value) {
        out.add('${e.key}: ${_money(now[e.key]!)} → ${_money(e.value)}');
      }
    }
    for (final k in now.keys) {
      if (!next.containsKey(k)) out.add('Removed · $k');
    }
    return out;
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve salary change' : 'Reject salary change'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            approve
                ? 'This takes effect immediately and payroll will use it from '
                  'the next run.'
                : 'The current salary stays as it is.',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
                labelText: approve ? 'Note (optional)' : 'Reason',
                border: const OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    approve ? Colors.green.shade700 : Colors.red.shade700,
                foregroundColor: Colors.white),
            child: Text(approve ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // A rejection needs a reason; an approval does not. HR has to be able to
    // tell the employee why, and "Management said no" is not an answer.
    if (!approve && ctrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A reason is needed to reject.')));
      return;
    }

    final err = await SupabaseService.decideSalaryChange(
        id: r['id'].toString(), approve: approve, note: ctrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err == null
          ? (approve ? 'Approved and applied.' : 'Rejected.')
          : 'Could not save: $err'),
      backgroundColor: err == null ? Colors.teal.shade700 : Colors.red.shade700));
    if (err == null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: NavBackButton(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text('Salary Approvals',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_requests.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No salary changes awaiting approval.',
                    style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _card(_requests[i]),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final changes = _changedFields(r);
    final custom = _customChanges(r);
    final grossFrom = _n((r['current_value'] as Map?)?['actual_gross']);
    final grossTo = _n((r['proposed'] as Map?)?['actual_gross']);
    final diff = grossTo - grossFrom;
    final hist = _history[(r['employee_id'] ?? '').toString()] ?? const [];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text((r['employee_id'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Text(
              '${diff >= 0 ? '+' : ''}${_money(diff)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: diff >= 0 ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
          ]),
          // Who asked matters: a change proposed by someone for themselves, or
          // for the person they report to, is worth noticing before approving.
          Text(
            'Requested by ${r['requested_by']} · '
            '${changes.length + custom.length} field(s) changed',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280)),
          ),
          if ((r['reason'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('"${r['reason']}"',
                style: const TextStyle(
                    fontSize: 12, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 10),
          for (final c in changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(children: [
                SizedBox(
                  width: 130,
                  child: Text(c.label,
                      style: const TextStyle(fontSize: 12.5)),
                ),
                Text(_money(c.from),
                    style: const TextStyle(
                        fontSize: 12.5, color: Color(0xFF6B7280))),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 12, color: Color(0xFF9CA3AF)),
                ),
                Text(_money(c.to),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.from == c.to
                            ? const Color(0xFF6B7280)
                            : Colors.indigo.shade700)),
              ]),
            ),
          for (final c in custom)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(c,
                  style: TextStyle(fontSize: 12.5, color: Colors.indigo.shade700)),
            ),
          if (hist.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('Last ${hist.length} revision(s)',
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280))),
            for (final h in hist)
              Text(
                '${(h['changed_at'] ?? '').toString().substring(0, 10)} · '
                '${h['changed_by'] ?? '—'} · gross '
                '${_money(_n((h['new_values'] as Map?)?['actual_gross']))}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _decide(r, false),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _decide(r, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white),
                child: const Text('Approve'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
