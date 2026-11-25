import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/user_session.dart';
import '../services/exit_service.dart';
import '../theme/app_theme.dart';

// Exit, last working day and Full & Final settlement (agreed 25 Nov 2026).
// HR records an exit on the employee's profile, Management approves it, the
// account closes automatically the night of the last working day, and the
// F&F statement is prepared by HR, approved by Management and marked paid.

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String exitFmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

String exitFmtMoney(double v) {
  final neg = v < 0;
  final whole = v.abs().round();
  final s = whole.toString();
  // Indian grouping: last three digits, then pairs.
  String out;
  if (s.length <= 3) {
    out = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    out = '${parts.join(',')},$last3';
  }
  return '${neg ? '−' : ''}₹$out';
}

bool get _isMgmt => UserSession.role == UserRole.management;
bool get _isHrOrMgmt =>
    UserSession.role == UserRole.hr || UserSession.role == UserRole.management;

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// HR policy 6.1: DGM and above 60 days, Jr. Executive to Senior Manager 30,
/// probationers 15. Same rule as exit_notice_default() in the database.
int exitDefaultNoticeDays(AppUser u) {
  if (u.onrollConfirmedAt.isEmpty) return 15;
  final d = u.designation.toLowerCase();
  const senior = ['general manager', 'chief', 'head of', 'director', 'vice president', 'dgm'];
  if (senior.any((s) => d.contains(s))) return 60;
  return 30;
}

void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    behavior: SnackBarBehavior.floating,
  ));
}

Widget _chip(String text, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );

Widget exitStatusChip(EmployeeExit x) {
  switch (x.status) {
    case 'pending':
      return _chip('Waiting for approval', Colors.orange.shade800, Colors.orange.shade50);
    case 'approved':
      return x.accountClosedAt != null
          ? _chip('Left', Colors.grey.shade800, Colors.grey.shade200)
          : _chip('Leaving', Colors.red.shade700, Colors.red.shade50);
    case 'rejected':
      return _chip('Rejected', Colors.grey.shade700, Colors.grey.shade100);
    default:
      return _chip('Withdrawn', Colors.grey.shade700, Colors.grey.shade100);
  }
}

Widget fnfStatusChip(EmployeeExit x) {
  if (x.status != 'approved') return const SizedBox.shrink();
  if (x.fnf == 'forfeit') {
    return _chip('F&F: not eligible', Colors.grey.shade700, Colors.grey.shade100);
  }
  if (x.fnf == 'hold') {
    return _chip('F&F: on hold', Colors.orange.shade800, Colors.orange.shade50);
  }
  switch (x.fnfStatus) {
    case 'paid':
      return _chip('F&F paid', Colors.green.shade800, Colors.green.shade50);
    case 'approved':
      return _chip('F&F approved, to pay', Colors.blue.shade800, Colors.blue.shade50);
    default:
      return _chip('F&F to prepare', Colors.blue.shade800, Colors.blue.shade50);
  }
}

class _Choice {
  final String value;
  final String label;
  const _Choice(this.value, this.label);
}

Widget _choices(List<_Choice> options, String selected, ValueChanged<String> onPick) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o.label, style: const TextStyle(fontSize: 12)),
            selected: selected == o.value,
            onSelected: (_) => onPick(o.value),
          ),
      ],
    );

Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(t,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
    );

Future<DateTime?> _pickDate(BuildContext context, DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? _today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(_today().year + 2, 12, 31),
    );

Widget _dateField(BuildContext context, String label, DateTime? value, ValueChanged<DateTime> onPick) =>
    OutlinedButton.icon(
      onPressed: () async {
        final d = await _pickDate(context, value);
        if (d != null) onPick(d);
      },
      icon: const Icon(Icons.event_rounded, size: 16),
      label: Text(value == null ? label : exitFmtDate(value)),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );

// ── Record exit (HR or Management) ──────────────────────────────────────────

Future<bool?> showRecordExitDialog(BuildContext context, AppUser user) =>
    showDialog<bool>(context: context, builder: (_) => _RecordExitDialog(user: user));

class _RecordExitDialog extends StatefulWidget {
  final AppUser user;
  const _RecordExitDialog({required this.user});
  @override
  State<_RecordExitDialog> createState() => _RecordExitDialogState();
}

class _RecordExitDialogState extends State<_RecordExitDialog> {
  String _type = 'resigned';
  DateTime? _resigned;
  DateTime? _lwd;
  late final TextEditingController _notice =
      TextEditingController(text: '${exitDefaultNoticeDays(widget.user)}');
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _notice.dispose();
    _reason.dispose();
    super.dispose();
  }

  int? get _served => (_resigned == null || _lwd == null)
      ? null
      : _lwd!.difference(_resigned!).inDays + 1;

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_lwd == null) { setState(() => _error = 'Pick the last working day.'); return; }
    if (_type == 'resigned' && _resigned == null) {
      { setState(() => _error = 'Pick the date they resigned.'); return; }
    }
    if (_type == 'resigned' && _resigned!.isAfter(_lwd!)) {
      { setState(() => _error = 'The resignation date is after the last working day.'); return; }
    }
    if (_reason.text.trim().isEmpty) {
      { setState(() => _error = 'Write the reason for the exit.'); return; }
    }
    final notice = int.tryParse(_notice.text.trim());
    if (_type == 'resigned' && (notice == null || notice < 0)) {
      { setState(() => _error = 'Notice period must be a number of days.'); return; }
    }
    setState(() => _saving = true);
    final err = await ExitService.recordExit(
      employeeId: widget.user.employeeId,
      exitType: _type,
      resignationDate: _type == 'resigned' ? _resigned : null,
      lastWorkingDay: _lwd!,
      reason: _reason.text.trim(),
      noticeDays: notice,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    Navigator.pop(context, true);
    _snack(context, 'Exit recorded for ${widget.user.name}. Sent to Management for approval.');
  }

  @override
  Widget build(BuildContext context) {
    final short = (_type == 'resigned' && _served != null)
        ? ((int.tryParse(_notice.text.trim()) ?? 0) - _served!)
        : 0;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Record exit — ${widget.user.name}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Management approves before it takes effect. ${widget.user.name.split(' ').first} '
              'keeps access until the end of the last working day; the account then closes '
              'that night and the login email is freed for reuse.',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            _label('Type of exit'),
            _choices(const [
              _Choice('resigned', 'Resigned'),
              _Choice('terminated', 'Terminated'),
              _Choice('absconded', 'Absconded'),
              _Choice('other', 'Other'),
            ], _type, (v) => setState(() => _type = v)),
            if (_type == 'resigned') ...[
              _label('Resignation date (notice starts)'),
              _dateField(context, 'Pick date', _resigned, (d) => setState(() => _resigned = d)),
            ],
            _label('Last working day'),
            _dateField(context, 'Pick date', _lwd, (d) => setState(() => _lwd = d)),
            if (_type == 'resigned') ...[
              _label('Notice period (days)'),
              TextField(
                controller: _notice,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  helperText: 'From the HR policy: 15 probation, 30 up to Sr. Manager, 60 DGM and above',
                  helperMaxLines: 2,
                ),
              ),
              if (_served != null) ...[
                const SizedBox(height: 8),
                Text(
                  short > 0
                      ? 'Notice given: $_served days, $short short. Unless Management '
                          'waives it, they are not eligible for the F&F and Management '
                          'decides on the final month\'s salary.'
                      : 'Notice given: $_served days — served in full.',
                  style: TextStyle(
                      fontSize: 12,
                      color: short > 0 ? Colors.orange.shade800 : Colors.green.shade700),
                ),
              ],
            ],
            if (_type == 'absconded')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'The final salary and the F&F are held until Management decides.',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
            _label('Reason'),
            TextField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: 'e.g. Resigned for higher studies; resignation letter dated …',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Send for approval'),
        ),
      ],
    );
  }
}

// ── Management decision ─────────────────────────────────────────────────────

Future<bool?> showExitDecisionDialog(BuildContext context, EmployeeExit x) =>
    showDialog<bool>(context: context, builder: (_) => _ExitDecisionDialog(exit: x));

class _ExitDecisionDialog extends StatefulWidget {
  final EmployeeExit exit;
  const _ExitDecisionDialog({required this.exit});
  @override
  State<_ExitDecisionDialog> createState() => _ExitDecisionDialogState();
}

class _ExitDecisionDialogState extends State<_ExitDecisionDialog> {
  late bool _waived = widget.exit.noticeWaived;
  late String _final;
  late String _fnf;
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  EmployeeExit get x => widget.exit;
  bool get _approved => x.status == 'approved';
  int get _short => x.noticeShortWith(waived: _waived);

  @override
  void initState() {
    super.initState();
    // Same defaults as approve_exit() in the database.
    if (_approved) {
      _final = x.finalSalary;
      _fnf = x.fnf == 'forfeit' ? 'pay' : x.fnf;
    } else {
      final short = x.noticeShortWith(waived: x.noticeWaived);
      _final = x.exitType == 'absconded'
          ? 'hold'
          : (x.exitType == 'resigned' && short > 0) ? 'hold' : 'pay';
      _fnf = x.exitType == 'absconded' ? 'hold' : 'pay';
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _approve() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final err = await ExitService.approveExit(
      x.id,
      noticeWaived: x.fnfStatus == 'draft' ? _waived : null,
      finalSalary: _final,
      fnf: x.fnfStatus == 'draft' ? (_short > 0 ? null : _fnf) : null,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    Navigator.pop(context, true);
    _snack(context, _approved ? 'Decision saved.' : 'Exit approved for ${x.employeeName}.');
  }

  Future<void> _reject() async {
    if (_note.text.trim().isEmpty) {
      setState(() => _error = 'Write why it is rejected, so HR knows.');
      return;
    }
    setState(() => _saving = true);
    final err = await ExitService.rejectExit(x.id, _note.text.trim());
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    Navigator.pop(context, true);
    _snack(context, 'Exit rejected.');
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 130,
              child: Text(k, style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final passed = x.lastWorkingDay.isBefore(_today());
    final fnfLocked = x.fnfStatus != 'draft';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(_approved ? 'Exit decision — ${x.employeeName}' : 'Approve exit — ${x.employeeName}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            _row('Employee', '${x.employeeName} (${x.employeeId})'),
            _row('Type', x.typeLabel),
            if (x.resignationDate != null) _row('Resigned on', exitFmtDate(x.resignationDate!)),
            _row('Last working day', exitFmtDate(x.lastWorkingDay)),
            if (x.exitType == 'resigned')
              _row('Notice', '${x.noticeServed ?? '-'} of ${x.noticeDaysRequired} days given'),
            _row('Reason', x.reason),
            if (x.requestedBy.isNotEmpty) _row('Recorded by', x.requestedBy),
            if (x.exitType == 'resigned' && x.noticeShortWith(waived: false) > 0) ...[
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _waived,
                onChanged: fnfLocked ? null : (v) => setState(() => _waived = v ?? false),
                title: Text(
                    'Waive the ${x.noticeShortWith(waived: false)} days of notice not served',
                    style: const TextStyle(fontSize: 13)),
                subtitle: const Text('Agreed early relief. Counts as notice served, so they stay eligible for the F&F.',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ],
            _label('Final month\'s salary (days up to the last working day)'),
            _choices(const [
              _Choice('pay', 'Pay'),
              _Choice('hold', 'Hold'),
              _Choice('withhold', 'Withhold'),
              _Choice('settled', 'Settled outside the app'),
            ], _final, (v) => setState(() => _final = v)),
            if (_final == 'hold')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('The payslip is drafted but cannot be published until you change this.',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
              ),
            _label('Full & Final settlement'),
            if (_short > 0)
              Text('Not eligible: resigned without serving $_short days of notice.',
                  style: TextStyle(fontSize: 12.5, color: Colors.orange.shade800))
            else if (fnfLocked)
              Text('Already ${x.fnfStatus == 'paid' ? 'paid' : 'approved'}.',
                  style: const TextStyle(fontSize: 12.5))
            else
              _choices(const [
                _Choice('pay', 'Pay'),
                _Choice('hold', 'Hold'),
              ], _fnf, (v) => setState(() => _fnf = v)),
            _label('Note (optional; required to reject)'),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
            if (!_approved && passed)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('The last working day has passed, so the account closes as soon as you approve.',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        if (!_approved)
          TextButton(
            onPressed: _saving ? null : _reject,
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Reject'),
          ),
        ElevatedButton(
          onPressed: _saving ? null : _approve,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_approved ? 'Save decision' : 'Approve'),
        ),
      ],
    );
  }
}

// ── Full & Final statement ──────────────────────────────────────────────────

Future<bool?> showFnfDialog(BuildContext context, EmployeeExit x) =>
    showDialog<bool>(context: context, builder: (_) => _FnfDialog(exit: x));

class _FnfDialog extends StatefulWidget {
  final EmployeeExit exit;
  const _FnfDialog({required this.exit});
  @override
  State<_FnfDialog> createState() => _FnfDialogState();
}

class _FnfDialogState extends State<_FnfDialog> {
  late EmployeeExit x = widget.exit;
  List<FnfLine> _lines = [];
  List<FnfItem> _items = [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  final _label_ = TextEditingController();
  final _amount = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _recovery = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _label_.dispose();
    _amount.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await ExitService.fetchExits(employeeId: x.employeeId);
      final me = fresh.where((e) => e.id == x.id).toList();
      if (me.isNotEmpty) x = me.first;
      final lines = await ExitService.fnfStatement(x.id);
      final items = await ExitService.fnfItems(x.id);
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ExitService.message(e);
      });
    }
  }

  Future<void> _run(Future<String?> Function() op, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await op();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _changed = true;
    _snack(context, done);
    await _load();
  }

  Future<void> _addLine() async {
    final amt = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_label_.text.trim().isEmpty || amt == null || amt <= 0) {
      setState(() => _error = 'Give a description and an amount.');
      return;
    }
    await _run(
      () => ExitService.addFnfItem(
          x.id, _label_.text.trim(), _recovery ? -amt : amt, _noteCtrl.text.trim()),
      'Line added.',
    );
    if (_error == null) {
      _label_.clear();
      _amount.clear();
      _noteCtrl.clear();
    }
  }

  Future<void> _markPaid() async {
    final ref = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark F&F paid'),
        content: TextField(
          controller: ref,
          decoration: const InputDecoration(
              labelText: 'Payment reference (e.g. NEFT UTR, cheque no.)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark paid')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ExitService.markFnfPaid(x.id, ref.text.trim()), 'F&F marked paid.');
  }

  Widget _line(FnfLine l) {
    final isTotal = l.kind == 'total';
    final isInfo = l.kind == 'info';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isTotal ? 8 : 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.label,
                style: TextStyle(
                    fontSize: isTotal ? 14 : 13,
                    fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
                    color: isInfo ? AppTheme.textSecondary : AppTheme.textPrimary)),
            if (l.note.isNotEmpty)
              Text(l.note, style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
          ]),
        ),
        if (!isInfo)
          Text(exitFmtMoney(l.amount),
              style: TextStyle(
                  fontSize: isTotal ? 15 : 13,
                  fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                  color: l.amount < 0 ? Colors.red.shade700 : AppTheme.textPrimary)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = x.status == 'approved' && x.fnfStatus == 'draft';
    final canEdit = draft && _isHrOrMgmt && x.fnf != 'forfeit';
    final total = _lines.where((l) => l.kind == 'total').toList();
    final totalAmt = total.isEmpty ? 0.0 : total.first.amount;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Full & Final — ${x.employeeName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${x.employeeId} · ${x.typeLabel} · last working day ${exitFmtDate(x.lastWorkingDay)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [exitStatusChip(x), fnfStatusChip(x)]),
      ]),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  if (x.status != 'approved')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('The F&F can be prepared once Management approves the exit.',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                    ),
                  for (final l in _lines) ...[
                    if (l.kind == 'total' || (l.kind == 'info' && l.sort == 90)) const Divider(height: 14),
                    _line(l),
                  ],
                  if (totalAmt < 0)
                    Text('A negative total is owed by ${x.employeeName.split(' ').first} to the company.',
                        style: TextStyle(fontSize: 11.5, color: Colors.red.shade700)),
                  if (x.fnfStatus == 'paid')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                          'Paid${x.fnfPaidAt != null ? ' on ${exitFmtDate(x.fnfPaidAt!)}' : ''}'
                          '${x.fnfPaymentNote.isNotEmpty ? ' · ${x.fnfPaymentNote}' : ''}',
                          style: TextStyle(fontSize: 12.5, color: Colors.green.shade800)),
                    ),
                  if (canEdit) ...[
                    const Divider(height: 22),
                    const Text('Other lines',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    const Text(
                        'Company property lost or damaged, advance outstanding, bonus due, and so on.',
                        style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
                    for (final i in _items)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(i.label, style: const TextStyle(fontSize: 13)),
                        subtitle: i.note.isEmpty ? null : Text(i.note, style: const TextStyle(fontSize: 11.5)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(exitFmtMoney(i.amount), style: const TextStyle(fontSize: 13)),
                          IconButton(
                            tooltip: 'Remove line',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _busy
                                ? null
                                : () => _run(() => ExitService.voidFnfItem(i.id), 'Line removed.'),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    _choices(const [
                      _Choice('recovery', 'Recovery (deduct)'),
                      _Choice('payment', 'Payment (add)'),
                    ], _recovery ? 'recovery' : 'payment',
                        (v) => setState(() => _recovery = v == 'recovery')),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _label_,
                      decoration: const InputDecoration(
                          isDense: true, border: OutlineInputBorder(), labelText: 'Description'),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                              isDense: true, border: OutlineInputBorder(), labelText: 'Amount (₹)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _noteCtrl,
                          decoration: const InputDecoration(
                              isDense: true, border: OutlineInputBorder(), labelText: 'Note'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addLine,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add line'),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
                  ],
                ]),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: const Text('Close'),
        ),
        if (_isMgmt && x.status == 'approved' && (x.fnf == 'hold' || x.finalSalary == 'hold'))
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await showExitDecisionDialog(context, x);
                    if (ok == true) {
                      _changed = true;
                      await _load();
                    }
                  },
            child: const Text('Decide on hold'),
          ),
        if (_isMgmt && draft && x.fnf != 'hold')
          ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(() => ExitService.approveFnf(x.id), 'F&F approved.'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Approve F&F'),
          ),
        if (_isHrOrMgmt && x.fnfStatus == 'approved')
          ElevatedButton(
            onPressed: _busy ? null : _markPaid,
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            child: const Text('Mark paid'),
          ),
      ],
    );
  }
}

// ── Exit block on the employee profile ──────────────────────────────────────

/// Shown on the employee profile for HR and Management. Replaces the plain
/// Deactivate button for active staff: an exit has a date, a reason and an
/// approval, and closes the account itself on the last working day.
class ExitSection extends StatefulWidget {
  final AppUser user;
  final VoidCallback? onChanged;
  const ExitSection({super.key, required this.user, this.onChanged});
  @override
  State<ExitSection> createState() => _ExitSectionState();
}

class _ExitSectionState extends State<ExitSection> {
  EmployeeExit? _exit;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.user.employeeId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final x = await ExitService.fetchLatestFor(widget.user.employeeId);
      if (!mounted) return;
      setState(() {
        _exit = x;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _after(bool? changed) async {
    if (changed == true) {
      await _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _withdraw(EmployeeExit x) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw exit'),
        content: TextField(
          controller: note,
          decoration: const InputDecoration(
              labelText: 'Why (e.g. resignation taken back)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ExitService.cancelExit(x.id, note.text.trim());
    if (!mounted) return;
    if (err != null) {
      _snack(context, err, error: true);
      return;
    }
    _snack(context, 'Exit withdrawn.');
    await _after(true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isHrOrMgmt) return const SizedBox.shrink();
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    final x = _exit;
    if (x == null || !x.isOpen) {
      if (!widget.user.active) return const SizedBox.shrink();
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async => _after(await showRecordExitDialog(context, widget.user)),
          icon: const Icon(Icons.logout_rounded, size: 16),
          label: const Text('Record exit (last working day)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    final closed = x.accountClosedAt != null;
    final headline = x.status == 'pending'
        ? 'Exit waiting for Management approval'
        : closed
            ? 'Left — last working day ${exitFmtDate(x.lastWorkingDay)}'
            : 'Leaving — last working day ${exitFmtDate(x.lastWorkingDay)}';
    final sub = x.status == 'pending'
        ? '${x.typeLabel} · last working day ${exitFmtDate(x.lastWorkingDay)}'
        : closed
            ? 'Account closed on ${exitFmtDate(x.accountClosedAt!)}'
            : 'Access ends the night of the last working day';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: x.status == 'pending' ? Colors.orange.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: x.status == 'pending' ? Colors.orange.shade200 : Colors.red.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.logout_rounded,
              size: 16,
              color: x.status == 'pending' ? Colors.orange.shade800 : Colors.red.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(headline,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(sub, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        if (x.reason.isNotEmpty)
          Text(x.reason, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        if (x.status == 'approved') ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip('Final salary: ${EmployeeExit.finalSalaryLabels[x.finalSalary] ?? x.finalSalary}',
                Colors.grey.shade800, Colors.white),
            fnfStatusChip(x),
          ]),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (x.status == 'pending' && _isMgmt)
            ElevatedButton(
              onPressed: () async => _after(await showExitDecisionDialog(context, x)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue, foregroundColor: Colors.white),
              child: const Text('Review'),
            ),
          if (x.status == 'approved')
            OutlinedButton(
              onPressed: () async => _after(await showFnfDialog(context, x)),
              child: const Text('Full & Final'),
            ),
          if (x.status == 'approved' && _isMgmt)
            TextButton(
              onPressed: () async => _after(await showExitDecisionDialog(context, x)),
              child: const Text('Change decision'),
            ),
          if (!closed)
            TextButton(
              onPressed: () => _withdraw(x),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              child: const Text('Withdraw'),
            ),
        ]),
      ]),
    );
  }
}
