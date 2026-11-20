import 'package:flutter/material.dart';

import '../models/leave_form_config.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Correcting a leave request: HR proposes, Management approves.
///
/// A request filed under the wrong type (Jose's 19 Nov 2026 leave, filed as
/// CL when it should have been ML) could only be rejected, and the rejection
/// then blocked him from applying again. Now HR proposes the correct type,
/// balance, dates or half / full day, with a reason, and Management approves
/// it, optionally approving the leave in the same step. The database keeps
/// the original and the correction (leave_corrections) and re-applies every
/// leave rule to the corrected request.

const _buckets = ['CL', 'ML', 'EL', 'LOP'];

List<String> _typesFor(LeaveApplication req) => {
      ...LeaveFormConfig.defaultLeaveTypes,
      'Comp Off',
      req.leaveType,
    }.toList();

String _fmtDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
             'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

/// HR's side. Returns true when a correction was sent to Management.
Future<bool> showProposeLeaveCorrection(BuildContext context, LeaveApplication req) async {
  String type = req.leaveType;
  String bucket = _buckets.contains(req.bucket) ? req.bucket : 'CL';
  DateTime from = req.from;
  DateTime to = req.to;
  bool half = req.isHalfDay;
  final reasonCtrl = TextEditingController();
  String? error;
  bool saving = false;

  final sent = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(builder: (dctx, setS) {
      Future<void> pick(bool isFrom) async {
        final picked = await showDatePicker(
          context: dctx,
          initialDate: isFrom ? from : to,
          firstDate: DateTime(from.year - 1),
          lastDate: DateTime(to.year + 1, 12, 31),
        );
        if (picked == null) return;
        setS(() {
          if (isFrom) {
            from = picked;
            if (to.isBefore(from)) to = from;
          } else {
            to = picked.isBefore(from) ? from : picked;
          }
          if (from != to) half = false;
          error = null;
        });
      }

      Widget dateBox(String label, DateTime d, bool isFrom) => Expanded(
            child: InkWell(
              onTap: saving ? null : () => pick(isFrom),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                child: Text(_fmtDate(d), style: const TextStyle(fontSize: 13)),
              ),
            ),
          );

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Propose a correction',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${req.employeeName} · now ${req.leaveType} (${req.bucket}), '
                  '${_fmtDate(req.from)}${req.to != req.from ? ' – ${_fmtDate(req.to)}' : ''}'
                  '${req.isHalfDay ? ', half day' : ''}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 6),
                Text('Management approves the correction before it takes effect.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: type,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Leave type',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    for (final t in _typesFor(req)) DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: saving
                      ? null
                      : (v) => setS(() {
                            type = v ?? type;
                            bucket = LeaveStore.effectiveBucket(type);
                            error = null;
                          }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: bucket,
                  decoration: InputDecoration(
                    labelText: 'Draws from balance',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [for (final b in _buckets) DropdownMenuItem(value: b, child: Text(b))],
                  onChanged: saving ? null : (v) => setS(() => bucket = v ?? bucket),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  dateBox('From', from, true),
                  const SizedBox(width: 10),
                  dateBox('To', to, false),
                ]),
                CheckboxListTile(
                  value: half,
                  onChanged: (saving || from != to) ? null : (v) => setS(() => half = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Half day'),
                  subtitle: from != to ? const Text('Only for a single date') : null,
                ),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  enabled: !saving,
                  decoration: InputDecoration(
                    labelText: 'Reason for the correction',
                    hintText: 'e.g. Filed as CL; it is medical leave',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: saving
                ? null
                : () async {
                    final unchanged = type == req.leaveType &&
                        bucket == req.bucket &&
                        from == req.from &&
                        to == req.to &&
                        half == req.isHalfDay;
                    if (unchanged) {
                      setS(() => error = 'Nothing has been changed.');
                      return;
                    }
                    if (reasonCtrl.text.trim().isEmpty) {
                      setS(() => error = 'Please give a reason for the correction.');
                      return;
                    }
                    setS(() => saving = true);
                    final err = await SupabaseService.proposeLeaveCorrection(
                      leaveId: req.id,
                      leaveType: type,
                      bucket: bucket,
                      from: from,
                      to: to,
                      halfDay: half,
                      reason: reasonCtrl.text.trim(),
                    );
                    if (!dctx.mounted) return;
                    if (err != null) {
                      setS(() {
                        saving = false;
                        error = err;
                      });
                      return;
                    }
                    Navigator.pop(dctx, true);
                  },
            child: const Text('Send to Management'),
          ),
        ],
      );
    }),
  );
  reasonCtrl.dispose();
  return sent == true;
}

/// What a pending correction changes, and, for Management, the buttons to
/// decide it. [onDecided] runs after a decision is saved.
class PendingLeaveCorrection extends StatefulWidget {
  final Map<String, dynamic> correction;
  final VoidCallback onDecided;
  const PendingLeaveCorrection({super.key, required this.correction, required this.onDecided});

  @override
  State<PendingLeaveCorrection> createState() => _PendingLeaveCorrectionState();
}

class _PendingLeaveCorrectionState extends State<PendingLeaveCorrection> {
  bool _saving = false;
  String? _error;

  static String _describe(Map p) {
    final from = DateTime.tryParse('${p['from_date']}');
    final to = DateTime.tryParse('${p['to_date']}');
    final dates = from == null
        ? ''
        : ' · ${_fmtDate(from)}${to != null && to != from ? ' – ${_fmtDate(to)}' : ''}';
    return '${p['leave_type']} (${p['leave_bucket'] ?? ''})$dates'
        '${p['is_half_day'] == true ? ' · half day' : ''}';
  }

  Future<void> _decide({required bool approve, bool approveLeave = false}) async {
    String? note;
    if (!approve) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Reject the correction'),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
                hintText: 'Reason (optional)', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Reject')),
          ],
        ),
      );
      note = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await SupabaseService.decideLeaveCorrection(
      id: (widget.correction['id'] as num).toInt(),
      approve: approve,
      approveLeave: approveLeave,
      note: note,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    widget.onDecided();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.correction;
    final isMgmt = UserSession.role == UserRole.management;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.edit_note_rounded, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Correction waiting for Management',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.orange.shade900)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('From: ${_describe(c['previous'] as Map)}', style: const TextStyle(fontSize: 12.5)),
        Text('To:     ${_describe(c['proposed'] as Map)}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Reason: ${c['reason']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        Text('Proposed by ${c['proposed_by']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
        ],
        if (isMgmt) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton(
              onPressed: _saving ? null : () => _decide(approve: true, approveLeave: true),
              child: const Text('Approve correction and leave'),
            ),
            OutlinedButton(
              onPressed: _saving ? null : () => _decide(approve: true),
              child: const Text('Approve correction only'),
            ),
            TextButton(
              onPressed: _saving ? null : () => _decide(approve: false),
              child: const Text('Reject'),
            ),
          ]),
        ],
      ]),
    );
  }
}
