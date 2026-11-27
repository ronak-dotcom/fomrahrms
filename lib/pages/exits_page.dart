import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/exit_service.dart';
import '../theme/app_theme.dart';
import '../widgets/exit_widgets.dart';

/// Every exit in one place: waiting for Management, people still serving
/// notice, F&F statements to prepare or pay, and those who have left.
/// An exit is recorded from the employee's profile (People → Employees).
class ExitsPage extends StatefulWidget {
  const ExitsPage({super.key});
  @override
  State<ExitsPage> createState() => _ExitsPageState();
}

class _ExitsPageState extends State<ExitsPage> {
  List<EmployeeExit> _all = [];
  bool _loading = true;
  String? _error;
  String _filter = 'open';

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
      final rows = await ExitService.fetchExits();
      if (!mounted) return;
      setState(() {
        _all = rows;
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

  bool _needsFnf(EmployeeExit x) =>
      x.status == 'approved' && x.fnf != 'forfeit' && x.fnfStatus != 'paid';

  List<EmployeeExit> get _shown {
    switch (_filter) {
      case 'pending':
        return _all.where((x) => x.status == 'pending').toList();
      case 'fnf':
        return _all.where(_needsFnf).toList();
      case 'left':
        return _all.where((x) => x.status == 'approved' && x.accountClosedAt != null).toList();
      case 'all':
        return _all;
      default:
        return _all
            .where((x) => x.status == 'pending' || (x.status == 'approved' &&
                (x.accountClosedAt == null || _needsFnf(x) || x.finalSalary == 'hold')))
            .toList();
    }
  }

  Future<void> _open(EmployeeExit x) async {
    bool? changed;
    if (x.status == 'pending' && UserSession.role == UserRole.management) {
      changed = await showExitDecisionDialog(context, x);
    } else if (x.status == 'approved') {
      changed = await showFnfDialog(context, x);
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(x.employeeName),
          content: Text(
            '${x.typeLabel} · last working day ${exitFmtDate(x.lastWorkingDay)}\n\n'
            '${x.reason}'
            '${x.status == 'pending' ? '\n\nWaiting for Management to approve.' : ''}'
            '${x.decisionNote.isNotEmpty ? '\n\nNote: ${x.decisionNote}' : ''}',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    }
    if (changed == true) await _load();
  }

  Widget _card(EmployeeExit x) {
    final short = x.noticeShort;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(x),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${x.employeeName}  ·  ${x.employeeId}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
            ]),
            const SizedBox(height: 4),
            Text(
              '${x.typeLabel} · last working day ${exitFmtDate(x.lastWorkingDay)}'
              '${x.exitType == 'resigned' && x.noticeServed != null ? ' · notice ${x.noticeServed}/${x.noticeDaysRequired} days' : ''}'
              '${x.noticeWaived ? ' (waived)' : ''}',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            if (short > 0)
              Text('$short days of notice short',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              exitStatusChip(x),
              if (x.status == 'approved' && x.finalSalary != 'pay')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                      'Final salary: ${EmployeeExit.finalSalaryLabels[x.finalSalary] ?? x.finalSalary}',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
                ),
              fnfStatusChip(x),
              if (x.fnfStatus != 'draft' && x.fnfTotal != null)
                Text('  ${exitFmtMoney(x.fnfTotal!)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final pendingCount = _all.where((x) => x.status == 'pending').length;
    final fnfCount = _all.where(_needsFnf).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(narrow ? 16 : 28),
        children: [
          Text('Exits & Full and Final',
              style: TextStyle(
                  fontSize: narrow ? 20 : 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryBlue)),
          const SizedBox(height: 6),
          const Text(
            'Record an exit from the employee\'s profile (People → Employees). '
            'Management approves it; the account closes by itself the night of the last '
            'working day and the login email is freed. The final month is paid in payroll '
            'up to the last working day; the F&F statement covers EL encashment, gratuity and '
            'any recoveries.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in [
              ('open', 'Open'),
              ('pending', 'To approve ($pendingCount)'),
              ('fnf', 'F&F to settle ($fnfCount)'),
              ('left', 'Left'),
              ('all', 'All'),
            ])
              ChoiceChip(
                label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                selected: _filter == f.$1,
                onSelected: (_) => setState(() => _filter = f.$1),
              ),
          ]),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(_error!, style: TextStyle(color: Colors.red.shade700))
          else if (_shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text('Nothing here.',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            for (final x in _shown) _card(x),
        ],
      ),
    );
  }
}
