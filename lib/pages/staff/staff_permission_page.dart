import 'package:flutter/material.dart';
import '../../l10n/staff_strings.dart';
import '../../models/language_notifier.dart';
import '../../models/leave_store.dart';
import '../../models/user_session.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'staff_history.dart';

// Canonical English values — stored as-is in LeaveApplication.reason so HR's
// (English-only) approval screens and LeaveStore.permMinutesFromReason keep
// working regardless of the Staff Portal's display language.
// The allowance is 2 hours per cycle in 30-minute steps: 30, 60, 90 or 120
// a time (90 allowed again, 20 Nov 2026). '1 Hour 30 Minutes' is read as 90
// by both the app and the database.
const _durations = ['30 Minutes', '1 Hour', '1 Hour 30 Minutes', '2 Hours'];
const _durationKeys = {
  '30 Minutes':         'duration_30m',
  '1 Hour':             'duration_1h',
  '1 Hour 30 Minutes':  'duration_1h30m',
  '2 Hours':            'duration_2h',
};

/// Staff Portal permission request: date + a radio-button duration picker,
/// capped at 2 requests per calendar month (count-based, not minutes-based —
/// see LeaveStore.permCountThisMonth). No reason/description field.
class StaffPermissionPage extends StatefulWidget {
  const StaffPermissionPage({super.key});

  @override
  State<StaffPermissionPage> createState() => _StaffPermissionPageState();
}

class _StaffPermissionPageState extends State<StaffPermissionPage> {
  static Color get _color => AppTheme.accentBlue;

  DateTime? _date;
  String _duration = _durations.first;
  bool _submitting = false;
  bool _loading = true;

  String get _employeeName => UserSession.name.isEmpty ? 'Employee' : UserSession.name;
  int get _usedThisMonth => LeaveStore.permCountThisMonth(_employeeName);
  bool get _limitReached => _usedThisMonth >= 2;

  List<LeaveApplication> get _history {
    final list = LeaveStore.applications
        .where((a) => a.employeeName == _employeeName && a.leaveType == 'Permission')
        .toList();
    list.sort((a, b) => b.appliedOn.compareTo(a.appliedOn));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    final apps = await SupabaseService.fetchLeaveApplications();
    if (!mounted) return;
    if (apps.isNotEmpty) {
      LeaveStore.applications..clear()..addAll(apps);
      LeaveStore.syncCounter();
    }
    setState(() => _loading = false);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: ColorScheme.light(primary: _color)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_limitReached) return;
    if (_date == null) {
      _snack(st('select_permission_date_err'));
      return;
    }
    setState(() => _submitting = true);

    final app = LeaveApplication(
      id:           LeaveStore.generateId(),
      employeeName: _employeeName,
      department:   UserSession.department,
      leaveType:    'Permission',
      from:         _date!,
      to:           _date!,
      days:         1,
      reason:       _duration,
      appliedOn:    DateTime.now(),
    )..isHalfDay = true;

    LeaveStore.applications.add(app);
    await SupabaseService.saveLeaveApplication(app);

    if (!mounted) return;
    setState(() { _submitting = false; _date = null; _duration = _durations.first; });
    _snack(st('permission_submitted'));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.center),
      backgroundColor: _color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: staffLanguageNotifier,
      builder: (context, _, __) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 760;
          final form = _ApplyPermissionForm(
            date: _date,
            duration: _duration,
            usedThisMonth: _usedThisMonth,
            limitReached: _limitReached,
            submitting: _submitting,
            onPickDate: _pickDate,
            onDurationChanged: (v) => setState(() => _duration = v),
            onSubmit: _submit,
            fmt: _fmt,
          );
          final history = Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: StaffHistorySection(
                title: st('permission_history'),
                items: _history,
                emptyKey: 'no_permission_history',
                subtitleOf: (a) => st(_durationKeys[a.reason] ?? a.reason),
              ),
            ),
          );

          if (!wide) {
            return Column(children: [form, const SizedBox(height: 20), history]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: form),
            const SizedBox(width: 20),
            Expanded(flex: 6, child: history),
          ]);
        }),
      ),
    );
  }
}

class _ApplyPermissionForm extends StatelessWidget {
  final DateTime? date;
  final String duration;
  final int usedThisMonth;
  final bool limitReached;
  final bool submitting;
  final VoidCallback onPickDate;
  final ValueChanged<String> onDurationChanged;
  final VoidCallback onSubmit;
  final String Function(DateTime) fmt;
  const _ApplyPermissionForm({
    required this.date, required this.duration, required this.usedThisMonth,
    required this.limitReached, required this.submitting,
    required this.onPickDate, required this.onDurationChanged, required this.onSubmit, required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.accentBlue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(st('apply_permission'), style: AppTheme.cardHeading),
          const SizedBox(height: 4),
          Text(st('fill_permission_details'), style: AppTheme.captionText),
          const SizedBox(height: 18),

          if (limitReached)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(AppTheme.controlRadius),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(st('permission_limit_reached'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF9A3412))),
                ),
              ]),
            ),

          Text(st('permission_date'), style: AppTheme.captionText.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          InkWell(
            onTap: limitReached ? null : onPickDate,
            borderRadius: BorderRadius.circular(AppTheme.controlRadius),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.pageBackground,
                border: Border.all(color: date != null ? color.withValues(alpha: 0.5) : AppTheme.borderSubtle,
                    width: date != null ? 1.5 : 1),
                borderRadius: BorderRadius.circular(AppTheme.controlRadius),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today_rounded, size: 18, color: color),
                const SizedBox(width: 12),
                Text(date != null ? fmt(date!) : st('select_date'),
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600,
                        color: date != null ? AppTheme.textPrimary : AppTheme.textSecondary)),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          Text(st('permission_duration'), style: AppTheme.captionText.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.borderSubtle),
              borderRadius: BorderRadius.circular(AppTheme.controlRadius),
            ),
            child: Column(children: [
              for (var i = 0; i < _durations.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                RadioListTile<String>(
                  value: _durations[i],
                  groupValue: duration,
                  onChanged: limitReached ? null : (v) { if (v != null) onDurationChanged(v); },
                  activeColor: color,
                  title: Text(st(_durationKeys[_durations[i]]!),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (submitting || limitReached) ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: submitting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(st('apply'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
