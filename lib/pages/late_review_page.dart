import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../utils/attendance_cycle.dart';
import '../widgets/back_button.dart';

/// Where HR decides what a cycle's unabsorbed lates actually cost.
///
/// The rule alone produces half a day's unpaid leave for someone who was late
/// once after their permission ran out. That is often the right answer and
/// sometimes plainly not — a hospital visit, a transport strike — and HR knows
/// which. Rather than leaving them to argue with a payslip after it is issued,
/// the decision is made here before payroll reads it.
///
/// Doing nothing is a valid choice: with no decision recorded the days are
/// unpaid, which is the rule working as written.
///
/// HR's decision takes effect only once Management approves it (Ronak, 27
/// Nov 2026); until then payroll keeps the earlier decision, or the rule.
/// Management's own decisions apply at once.
class LateReviewPage extends StatefulWidget {
  const LateReviewPage({super.key});

  @override
  State<LateReviewPage> createState() => _LateReviewPageState();
}

class _LateReviewPageState extends State<LateReviewPage> {
  bool _loading = true;
  DateTime _cycleEnd = attendanceCycleEnd(DateTime.now());
  List<AppUser> _users = const [];
  Map<String, Map<String, dynamic>> _costs = const {};
  Map<String, Map<String, dynamic>> _decisions = const {};

  static const _actions = <String, String>{
    'lop': 'Unpaid (loss of pay)',
    'CL': 'Deduct from Casual Leave',
    'ML': 'Deduct from Medical Leave',
    'EL': 'Deduct from Earned Leave',
    'waive': 'Waive — no deduction',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await UserStore.load();
    // Only people the cycle actually applies to: an oversight-only account has
    // no attendance, so listing it invites a decision about nothing.
    final tracked = users
        .where((u) => u.active && u.countsInHeadcount && !u.exemptFromAttendance)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final costs = await SupabaseService.fetchLateCosts(
        tracked.map((u) => u.employeeId).toList(), _cycleEnd);

    final decisions =
        await SupabaseService.fetchLateDecisions(attendanceCycleLabel(_cycleEnd));

    if (!mounted) return;
    setState(() {
      _users = tracked;
      _costs = costs;
      _decisions = decisions;
      _loading = false;
    });
  }

  Future<void> _setAction(AppUser u, String action) async {
    final noteCtrl = TextEditingController();
    if (action != 'lop') {
      // A reason is required for anything other than the default, because
      // those are the ones someone may later have to justify.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_actions[action] ?? action),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${u.name} — ${_raw(u).toStringAsFixed(1)} day(s) from lates',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Reason', border: OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text(UserSession.isManagement ? 'Apply' : 'Send for approval')),
          ],
        ),
      );
      if (ok != true) return;
      if (noteCtrl.text.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('A reason is needed for anything other than unpaid.')));
        return;
      }
    }

    final err = await SupabaseService.setLateDecision(
      employeeId: u.employeeId,
      cycleLabel: attendanceCycleLabel(_cycleEnd),
      action: action,
      note: noteCtrl.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save: $err'),
          backgroundColor: Colors.red.shade700));
      return;
    }
    if (!UserSession.isManagement) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sent to Management. It applies once they approve.')));
    }
    await _load();
  }

  Future<void> _decide(AppUser u, bool approve) async {
    final err = await SupabaseService.decideLateRequest(
      employeeId: u.employeeId,
      cycleLabel: attendanceCycleLabel(_cycleEnd),
      approve: approve,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err != null
            ? 'Could not save: $err'
            : approve ? 'Approved for ${u.name}.' : 'Rejected for ${u.name}.'),
        backgroundColor: err != null ? Colors.red.shade700 : null));
    await _load();
  }

  Map<String, dynamic>? _pending(AppUser u) {
    final d = _decisions[u.employeeId];
    return d != null && d['status'] == 'pending' ? d : null;
  }

  double _raw(AppUser u) =>
      ((_costs[u.employeeId]?['raw_days'] as num?) ?? 0).toDouble();
  double _shortfall(AppUser u) =>
      ((_costs[u.employeeId]?['shortfall_days'] as num?) ?? 0).toDouble();
  String _action(AppUser u) =>
      (_costs[u.employeeId]?['action'] as String?) ?? 'lop';

  @override
  Widget build(BuildContext context) {
    // Only people who actually have lates to decide about.
    final withLates = _users
        .where((u) => _raw(u) > 0 || _pending(u) != null)
        .toList()
      // Requests waiting on Management first.
      ..sort((a, b) => (_pending(a) != null ? 0 : 1).compareTo(_pending(b) != null ? 0 : 1));

    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: NavBackButton(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text('Late Review — ${attendanceCycleLabel(_cycleEnd)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'The first 3 lates each cycle are free. After that the time comes '
              'out of the 2-hour permission allowance, and once that is gone '
              'each further late costs half a day. Change what it comes out of '
              'below — leaving it alone means unpaid. HR\'s changes apply '
              'once Management approves them.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (withLates.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No lates to decide this cycle.',
                    style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: withLates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final u = withLates[i];
                    final shortfall = _shortfall(u);
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(u.name,
                                    style: const TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600)),
                              ),
                              Text('${_raw(u).toStringAsFixed(1)} day(s)',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.orange.shade800)),
                            ]),
                            const SizedBox(height: 8),
                            if (_pending(u) != null) ...[
                              _PendingBanner(
                                request: _pending(u)!,
                                label: _actions[_pending(u)!['requested_action']] ??
                                    '${_pending(u)!['requested_action']}',
                                canDecide: UserSession.isManagement,
                                onApprove: () => _decide(u, true),
                                onReject: () => _decide(u, false),
                              ),
                              const SizedBox(height: 8),
                            ] else if (_decisions[u.employeeId]?['status'] == 'rejected') ...[
                              Text(
                                'Management rejected the last request — '
                                '${_actions[_decisions[u.employeeId]!['requested_action']] ?? ''}.',
                                style: TextStyle(fontSize: 11.5, color: Colors.red.shade700),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Text('In force for payroll:',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              key: ValueKey('${u.employeeId}-${_action(u)}-${_pending(u)?['requested_action']}'),
                              initialValue: _action(u),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                              items: _actions.entries
                                  .map((e) => DropdownMenuItem(
                                        value: e.key,
                                        child: Text(e.value,
                                            style: const TextStyle(fontSize: 12.5)),
                                      ))
                                  .toList(),
                              onChanged: (v) { if (v != null) _setAction(u, v); },
                            ),
                            // A bucket that cannot cover the whole amount
                            // leaves a remainder, and that remainder is still
                            // unpaid — saying so here avoids HR believing the
                            // deduction was fully absorbed.
                            if (shortfall > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Only part could be taken from that balance — '
                                '${shortfall.toStringAsFixed(1)} day(s) remain unpaid.',
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.red.shade700),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  final Map<String, dynamic> request;
  final String label;
  final bool canDecide;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _PendingBanner({
    required this.request,
    required this.label,
    required this.canDecide,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final by = (request['decided_by'] as String?) ?? '';
    final note = ((request['note'] as String?) ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF5D08A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          canDecide ? 'Needs your approval: $label' : 'Waiting for Management: $label',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        if (by.isNotEmpty || note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              [if (by.isNotEmpty) 'Asked by $by', if (note.isNotEmpty) note].join(' · '),
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
            ),
          ),
        if (canDecide) ...[
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton(onPressed: onApprove, child: const Text('Approve')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onReject, child: const Text('Reject')),
          ]),
        ],
      ]),
    );
  }
}
