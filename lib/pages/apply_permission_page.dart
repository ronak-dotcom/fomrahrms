import 'package:flutter/material.dart';
import '../models/leave_form_config.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

class ApplyPermissionPage extends StatefulWidget {
  const ApplyPermissionPage({super.key});

  @override
  State<ApplyPermissionPage> createState() => _ApplyPermissionPageState();
}

class _ApplyPermissionPageState extends State<ApplyPermissionPage> {
  static Color get _color => AppTheme.accentBlue;

  // Populated from Supabase config; falls back to LeaveFormConfig defaults.
  List<String> _durations = List<String>.from(LeaveFormConfig.defaultPermissionDurations);
  List<String> _reasons   = List<String>.from(LeaveFormConfig.defaultPermissionReasons);

  DateTime? _date;
  String _duration = '1 Hour';
  String _reason   = 'Doctor / Medical';
  final _otherController = TextEditingController();
  final _descController  = TextEditingController();

  bool get _isOther => _reason == 'Other';

  @override
  void initState() {
    super.initState();
    _loadFormConfig();
  }

  Future<void> _loadFormConfig() async {
    try {
      Map<String, dynamic> cfg;
      if (LeaveFormConfig.cached != null) {
        cfg = LeaveFormConfig.cached!;
      } else {
        final active = await SupabaseService.fetchActiveLeaveFormConfig();
        cfg = active != null
            ? Map<String, dynamic>.from(active['form_config'] as Map)
            : LeaveFormConfig.defaults();
        LeaveFormConfig.setCache(cfg);
      }
      final durations = LeaveFormConfig.getPermissionDurations(cfg);
      final reasons   = LeaveFormConfig.getPermissionReasons(cfg);
      if (mounted) setState(() {
        _durations = durations;
        _reasons   = reasons;
        if (!_durations.contains(_duration)) _duration = _durations.first;
        if (!_reasons.contains(_reason))     _reason   = _reasons.first;
      });
    } catch (_) {}
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void dispose() {
    _otherController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: ColorScheme.light(primary: _color)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_date == null) {
      _snack('Please select a date.'); return;
    }
    if (_isOther && _otherController.text.trim().isEmpty) {
      _snack('Please specify the reason.'); return;
    }

    // Permission is a confirmed-employee benefit. The database refuses these
    // outright (enforce_probation_leave_rules), so catch it here to give a
    // clear reason rather than a rejected request.
    if (!UserSession.hasFullLeaveEntitlement) {
      _snack('Permission is not available during probation. '
             'It becomes available once your employment is confirmed.');
      return;
    }

    // Permission limit per ATTENDANCE CYCLE (26th -> 25th), not calendar month
    final name  = UserSession.name.isEmpty ? 'Employee' : UserSession.name;
    final quota = UserSession.permissionMinutesQuota;
    final used  = LeaveStore.permUsedThisCycle(name);
    final want  = LeaveStore.permMinutesFromReason(_duration);
    if (want == 0) {
      _snack('Permission must be 30 minutes, 1 hour or 2 hours.');
      return;
    }
    if (used + want > quota) {
      final left = (quota - used).clamp(0, quota);
      _snack(left == 0
          ? 'Monthly permission limit (${quota ~/ 60}h ${quota % 60}m) reached.'
          : 'Only ${left} min remaining this month. Cannot apply $_duration.');
      return;
    }

    final reasonText = _isOther ? _otherController.text.trim() : _reason;
    final desc       = _descController.text.trim();
    final note = 'Permission: $_duration | $reasonText'
        '${desc.isNotEmpty ? ' | $desc' : ''}';

    final app = LeaveApplication(
      id:           LeaveStore.generateId(),
      employeeName: UserSession.name.isEmpty ? 'Employee' : UserSession.name,
      department:   '',
      leaveType:    'Permission',
      from:         _date!,
      to:           _date!,
      days:         1,
      reason:       note,
      appliedOn:    DateTime.now(),
    )..isHalfDay = true;

    // Awaited: the same fire-and-forget pattern lost a leave request today
    // while the employee was told it succeeded.
    final err = await SupabaseService.saveLeaveApplication(app);
    if (!mounted) return;
    if (err != null) { _snack('Could not submit: $err'); return; }

    LeaveStore.applications.add(app);
    if (UserSession.reportingManager.isNotEmpty) {
      NotificationService.leaveSubmitted(
        employeeName: app.employeeName,
        leaveType: app.leaveType,
        reportingManagerName: UserSession.reportingManager,
      );
    }

    _snack('Permission request submitted successfully.');
    _clear();
  }

  void _clear() {
    setState(() {
      _date = null;
      _duration = '1 Hour';
      _reason   = 'Doctor / Medical';
    });
    _otherController.clear();
    _descController.clear();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ────────────────────────────────────────────────────
          Row(children: [
            const NavBackButton(),
            const SizedBox(width: 8),
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.access_time_rounded, color: _color, size: 26),
            ),
            const SizedBox(width: 16),
            Text('Apply Permission',
                style: Theme.of(context).textTheme.headlineMedium),
          ]),
          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Date ──────────────────────────────────────────────
                  _DateTile(
                    date: _date,
                    color: _color,
                    onTap: _pickDate,
                    fmt: _fmtDate,
                  ),
                  const SizedBox(height: 16),

                  // ── Off for (duration) ────────────────────────────────
                  DropdownButtonFormField<String>(
                    value: _duration,
                    isExpanded: true,
                    decoration: _deco('Off For', Icons.hourglass_bottom_rounded),
                    items: _durations
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d, style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) { if (v != null) setState(() => _duration = v); },
                  ),
                  const SizedBox(height: 16),

                  // ── Reason dropdown ───────────────────────────────────
                  DropdownButtonFormField<String>(
                    value: _reason,
                    isExpanded: true,
                    decoration: _deco('Reason', Icons.label_rounded),
                    items: _reasons
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r, style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _reason = v);
                    },
                  ),

                  // ── Other reason text field ───────────────────────────
                  if (_isOther) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _otherController,
                      decoration: _deco('Specify reason', Icons.edit_rounded),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // ── Description ───────────────────────────────────────
                  TextField(
                    controller: _descController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      alignLabelWithHint: true,
                      prefixIcon: Padding(
                        padding: EdgeInsets.only(bottom: 72),
                        child: Icon(Icons.notes_rounded, color: _color, size: 20),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: _color, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Buttons ───────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.clear_rounded),
                label: const Text('Clear'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _color,
                  side: BorderSide(color: _color),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Apply Permission'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: _color, size: 20),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _color, width: 2),
    ),
    filled: true,
    fillColor: Colors.white,
    labelStyle: const TextStyle(color: Color(0xFF6B7280)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

// ── Date tile ──────────────────────────────────────────────────────────────────
class _DateTile extends StatelessWidget {
  final DateTime? date;
  final Color color;
  final VoidCallback onTap;
  final String Function(DateTime) fmt;
  const _DateTile(
      {required this.date, required this.color,
       required this.onTap, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: date != null ? color.withValues(alpha: 0.05) : Colors.white,
          border: Border.all(
            color: date != null
                ? color.withValues(alpha: 0.4)
                : const Color(0xFFE5E7EB),
            width: date != null ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_rounded,
              size: 18, color: date != null ? color : const Color(0xFF6B7280)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Date',
                style: TextStyle(
                    fontSize: 11,
                    color: date != null ? color : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              date != null ? fmt(date!) : 'Select date',
              style: TextStyle(
                fontSize: 13,
                fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                color: date != null
                    ? const Color(0xFF111827)
                    : const Color(0xFF6B7280),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
