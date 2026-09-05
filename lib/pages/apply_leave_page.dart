import 'package:file_picker/file_picker.dart';
import '../utils/leave_deduction.dart';
import '../utils/attendance_cycle.dart';
import 'package:flutter/material.dart';
import '../widgets/leave_month_calendar.dart';
import '../models/app_user.dart';
import '../models/leave_form_config.dart';
import '../models/leave_store.dart';
import '../models/user_session.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/user_store.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

class ApplyLeavePage extends StatefulWidget {
  const ApplyLeavePage({super.key});

  @override
  State<ApplyLeavePage> createState() => _ApplyLeavePageState();
}

class _ApplyLeavePageState extends State<ApplyLeavePage> {
  static Color get _color => AppTheme.primaryBlue;

  // Populated from Supabase config; falls back to LeaveFormConfig defaults.
  List<String> _allLeaveTypes = List<String>.from(LeaveFormConfig.defaultLeaveTypes);

  /// Public holidays for the year, and the signed-in user's record — both
  /// needed to preview what a request will actually cost.
  Set<String> _holidayDates = {};
  AppUser? _me;
  List<LeaveApplication> _myLeaves = [];

  DateTime? _fromDate;
  DateTime? _toDate;
  String _leaveType  = 'Casual Leave';
  String _bucket     = 'CL'; // CL / ML / EL / LOP — balance this leave draws from
  bool   _isHalfDay  = false;
  final _reasonController = TextEditingController();

  double _usedCl       = 0.0;
  double _usedMl       = 0.0;
  double _usedEl       = 0.0;
  int    _accruedEl    = 0;
  bool   _isOnroll     = false;
  bool   _isElEligible = false;

  // Sickness proof (Medical / Sick Leave only) — uploaded immediately on
  // selection so submission just carries the resulting URL.
  String _proofUrl      = '';
  String _proofFileName = '';
  bool   _uploadingProof = false;

  List<String> get _leaveTypes {
    // EL is only offered as a reason once the employee is EL-eligible.
    // Medical/other reasons stay selectable regardless of ML eligibility —
    // if the employee has no ML balance, _syncBucket() falls it back to CL.
    if (_isElEligible) return _allLeaveTypes;
    return _allLeaveTypes.where((t) => LeaveStore.effectiveBucket(t) != 'EL').toList();
  }

  static const _bucketLabels = {'CL': 'Casual Leave', 'ML': 'Medical Leave', 'EL': 'Earned Leave'};

  /// Balance buckets actually available to this employee.
  List<String> get _applicableBuckets {
    final b = <String>['CL'];
    if (_isOnroll) b.add('ML');
    if (_isElEligible) b.add('EL');
    return b;
  }

  /// Whether the employee needs to pick which balance this leave draws
  /// from — only relevant when the reason doesn't already force a bucket
  /// (Earned Leave → EL, LOP or Others → LOP) and more than one applies.
  bool get _showBucketPicker {
    final reasonBucket = LeaveStore.effectiveBucket(_leaveType);
    if (reasonBucket == 'LOP' || reasonBucket == 'EL') return false;
    return _applicableBuckets.length > 1;
  }

  /// Resets [_bucket] to the sensible default for the current reason —
  /// its own bucket if applicable to this employee, else CL.
  void _syncBucket() {
    final reasonBucket = LeaveStore.effectiveBucket(_leaveType);
    if (reasonBucket == 'LOP') {
      _bucket = 'LOP';
    } else if (reasonBucket == 'EL') {
      _bucket = _isElEligible ? 'EL' : 'CL';
    } else {
      _bucket = _applicableBuckets.contains(reasonBucket) ? reasonBucket : 'CL';
    }
  }

  double get _remaining {
    switch (_bucket) {
      case 'ML':  return _isOnroll ? (1.0 - _usedMl).clamp(0.0, 1.0) : 0.0;
      case 'EL':  return (_accruedEl.toDouble() - _usedEl).clamp(0.0, _accruedEl.toDouble());
      case 'LOP': return double.infinity;
      default:    return (1.0 - _usedCl).clamp(0.0, 1.0);
    }
  }

  /// Calendar days selected (always >= 1).
  int get _calendarDays {
    if (_fromDate == null || _toDate == null) return 0;
    return _toDate!.difference(_fromDate!).inDays + 1;
  }

  /// What this request will actually cost, mirroring the database rule.
  ///
  /// The old version returned plain calendar days, so someone taking Saturday
  /// and Monday saw "2 days" while the database deducted 3 — having pulled in
  /// the Sunday between them. Correct, and completely unexplained.
  LeaveDeduction? get _deduction {
    if (_fromDate == null) return null;
    final to = _isHalfDay ? _fromDate! : (_toDate ?? _fromDate!);
    return previewLeaveDeduction(
      from: _fromDate!,
      to: to,
      isHalfDay: _isHalfDay,
      employee: _me,
      holidayIsoDates: _holidayDates,
      existingLeaves: _myLeaves,
    );
  }

  double get _effectiveDays => _deduction?.totalDays ?? 0.0;

  Widget _explain(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: Colors.amber.shade800),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900)),
          ),
        ]),
      );

  String _fmtEffective(double d) =>
      d == d.truncateToDouble() ? '${d.toInt()} day${d.toInt() == 1 ? '' : 's'}' : '½ day';

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    // Load form config first (uses in-memory cache after first fetch).
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
      final types = LeaveFormConfig.getLeaveTypes(cfg);
      if (mounted) setState(() => _allLeaveTypes = types);
    } catch (_) {}

    try {
      final results = await Future.wait([
        UserStore.load(),
        SupabaseService.fetchLeaveApplications(),
        // Needed to preview the real deduction: a public holiday inside the
        // range is not charged, and the weekly off decides what sandwiches.
        SupabaseService.fetchHolidays(DateTime.now().year),
      ]);
      final users  = (results[0] as List).cast<AppUser>();
      final leaves = results[1] as List<LeaveApplication>;
      final holidayRows = (results[2] as List).cast<Map<String, dynamic>>();

      final matches = users.where((u) => u.name == UserSession.name).toList();
      final me      = matches.isNotEmpty ? matches.first : null;

      _me = me;
      _myLeaves = leaves.where((a) => a.employeeName == UserSession.name).toList();
      _holidayDates = {
        for (final h in holidayRows)
          if ((h['holiday_date'] as String?)?.isNotEmpty ?? false)
            (h['holiday_date'] as String).substring(0, 10),
      };

      // EL cutoff for cumulative tracking
      DateTime? elCutoff;
      if (me != null && me.isElEligible) {
        final ref = me.elLastAvailedAt.isNotEmpty ? me.elLastAvailedAt : me.elEligibleAt;
        elCutoff = ref.isNotEmpty ? DateTime.tryParse(ref) : null;
      }

      // Per-bucket usage
      final now = DateTime.now();
      double usedCl = 0, usedMl = 0, usedEl = 0;
      for (final a in leaves) {
        if (a.employeeName != UserSession.name ||
            a.managerStatus != LeaveApprovalStatus.approved) continue;
        final bucket = a.bucket;
        // CL/ML accrue per attendance cycle (26th -> 25th), not calendar month.
        if (bucket == 'CL' && sameAttendanceCycle(a.from, now)) {
          usedCl += a.effectiveDays;
        } else if (bucket == 'ML' && sameAttendanceCycle(a.from, now)) {
          usedMl += a.effectiveDays;
        } else if (bucket == 'EL' && (elCutoff == null || a.from.isAfter(elCutoff))) {
          usedEl += a.effectiveDays;
        }
      }

      // EL accrual
      int accruedEl = 0;
      if (me != null && me.isElEligible) {
        final ref = me.elLastAvailedAt.isNotEmpty ? me.elLastAvailedAt : me.elEligibleAt;
        if (ref.isNotEmpty) {
          final cut = DateTime.tryParse(ref);
          if (cut != null) {
            final months = (now.year - cut.year) * 12 + (now.month - cut.month);
            accruedEl = (months * me.monthlyEl).clamp(0, 9999);
          }
        }
      }

      if (mounted) setState(() {
        _usedCl       = usedCl;
        _usedMl       = usedMl;
        _usedEl       = usedEl;
        _accruedEl    = accruedEl;
        _isOnroll     = me?.isOnroll     ?? false;
        _isElEligible = me?.isElEligible ?? false;
        if (!_leaveTypes.contains(_leaveType)) _leaveType = _leaveTypes.first;
        _syncBucket();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }


  /// Holiday or the employee's weekly off. Falls back to Sunday when no
  /// weekly off is recorded, which is the case for most staff.
  bool _isNonWorkingDay(DateTime d) {
    final iso = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    if (_holidayDates.contains(iso)) return true;
    const names = {
      'monday': DateTime.monday, 'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday, 'thursday': DateTime.thursday,
      'friday': DateTime.friday, 'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
    };
    final off = (_me?.weeklyOffDay ?? '').trim().toLowerCase();
    return d.weekday == (names[off] ?? DateTime.sunday);
  }

  Widget _pickerTheme(BuildContext ctx, Widget? child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: _color),
        ),
        child: child!,
      );

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: _pickerTheme,
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked;
        if (_isHalfDay) {
          _toDate = picked; // half day is always a single date
        } else if (_toDate != null && _toDate!.isBefore(picked)) {
          _toDate = null;
        }
      });
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? (_fromDate ?? DateTime.now()),
      firstDate: _fromDate ?? DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: _pickerTheme,
    );
    if (picked != null) setState(() => _toDate = picked);
  }

  Future<void> _pickProofFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      _showSnack('Could not read file.', Colors.red);
      return;
    }
    if (bytes.length > 5 * 1024 * 1024) {
      _showSnack('File too large — please keep it under 5 MB.', Colors.red);
      return;
    }

    setState(() => _uploadingProof = true);
    try {
      final url = await SupabaseService.uploadFile(bytes, file.name, 'application/pdf');
      if (!mounted) return;
      setState(() {
        _proofUrl = url;
        _proofFileName = file.name;
      });
    } catch (e) {
      if (mounted) _showSnack('Upload failed: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _uploadingProof = false);
    }
  }

  Future<void> _submit() async {
    if (_fromDate == null || (!_isHalfDay && _toDate == null)) {
      _showSnack('Please select from and to dates.', Colors.red);
      return;
    }

    // If bucket balance exceeded, show unpaid-leave T&C dialog before proceeding
    if (_remaining != double.infinity && _effectiveDays > _remaining) {
      final agreed = await _showUnpaidDialog();
      if (!agreed) return;
    }

    await _doSubmit();
  }

  Future<bool> _showUnpaidDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.warning_amber_rounded,
                    color: Colors.orange.shade700, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Unpaid Leave Notice',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Your monthly leave balance is exhausted.',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'By proceeding, you acknowledge that:',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                  const SizedBox(height: 6),
                  _TcPoint('This leave will be treated as Loss of Pay (LOP).'),
                  _TcPoint('Salary will be deducted for the days applied.'),
                  _TcPoint('This is subject to manager / management approval.'),
                  _TcPoint('LOP entries are recorded in your attendance.'),
                ]),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('I Agree — Apply as LOP'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _doSubmit() async {
    final toDate = _isHalfDay ? _fromDate! : _toDate!;
    final app = LeaveApplication(
      id:           LeaveStore.generateId(),
      employeeName: UserSession.name.isEmpty ? 'Employee' : UserSession.name,
      department:   '',
      leaveType:    _leaveType,
      from:         _fromDate!,
      to:           toDate,
      days:         _isHalfDay ? 1 : _calendarDays,
      reason:       _reasonController.text.trim(),
      appliedOn:    DateTime.now(),
    )
      ..isHalfDay   = _isHalfDay
      ..proofUrl    = _proofUrl
      ..leaveBucket = _bucket;
    // Awaited. Fire-and-forget is how a request vanished today while the
    // employee saw "submitted successfully" and the manager was notified
    // about something that does not exist.
    final err = await SupabaseService.saveLeaveApplication(app);
    if (!mounted) return;
    if (err != null) {
      _showSnack('Could not submit: $err', Colors.red.shade700);
      return;
    }

    LeaveStore.applications.add(app);
    if (UserSession.reportingManager.isNotEmpty) {
      // Only after the write succeeded — notifying about a request that was
      // not stored sends the manager to an empty queue.
      NotificationService.leaveSubmitted(
        employeeName: app.employeeName,
        leaveType: app.leaveType,
        reportingManagerName: UserSession.reportingManager,
      );
    }

    _showSnack('Leave application submitted successfully.', _color);
    _clear();
  }

  void _clear() {
    setState(() {
      _fromDate  = null;
      _toDate    = null;
      _leaveType = 'Casual Leave';
      _bucket    = 'CL';
      _isHalfDay = false;
      _proofUrl      = '';
      _proofFileName = '';
    });
    _reasonController.clear();
  }

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: bg,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              const NavBackButton(),
              const SizedBox(width: 8),
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.event_available_rounded, color: _color, size: 26),
              ),
              const SizedBox(width: 16),
              Text('Apply Leave', style: Theme.of(context).textTheme.headlineMedium),
            ]),
            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leave type dropdown
                    DropdownButtonFormField<String>(
                      value: _leaveType,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Leave Type',
                        prefixIcon: Icon(Icons.label_rounded, color: _color, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _color, width: 2),
                        ),
                        filled: true, fillColor: Colors.white,
                        labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      items: _leaveTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _leaveType = v;
                          _syncBucket();
                        });
                      },
                    ),
                    const SizedBox(height: 14),

                    if (_showBucketPicker) ...[
                      Text('Deduct From',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _applicableBuckets.map((b) {
                          final selected = _bucket == b;
                          return ChoiceChip(
                            label: Text('${_bucketLabels[b]} ($b)', style: const TextStyle(fontSize: 12)),
                            selected: selected,
                            onSelected: (_) => setState(() => _bucket = b),
                            selectedColor: _color.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              color: selected ? _color : Colors.black87,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                            side: BorderSide(color: selected ? _color : const Color(0xFFE5E7EB)),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Half day / Full day toggle
                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isHalfDay = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isHalfDay ? _color : Colors.white,
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                              border: Border.all(color: _color.withValues(alpha: 0.5)),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.wb_sunny_rounded, size: 15,
                                  color: !_isHalfDay ? Colors.white : _color),
                              const SizedBox(width: 6),
                              Text('Full Day', style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: !_isHalfDay ? Colors.white : _color)),
                            ]),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _isHalfDay = true;
                            if (_fromDate != null) _toDate = _fromDate;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _isHalfDay ? _color : Colors.white,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                              border: Border.all(color: _color.withValues(alpha: 0.5)),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.brightness_3_rounded, size: 15,
                                  color: _isHalfDay ? Colors.white : _color),
                              const SizedBox(width: 6),
                              Text('Half Day', style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: _isHalfDay ? Colors.white : _color)),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),

                    // Calendar rather than two date fields. Holidays and the
                    // employee's weekly off are shaded, so a request is not
                    // built across them unknowingly — previously the reduced
                    // day count only appeared after selecting, which read as
                    // the app miscounting.
                    Row(children: [
                      Expanded(child: _DateTile(
                        label: 'From Date',
                        date: _fromDate,
                        onTap: _pickFrom,
                        color: _color,
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _DateTile(
                        label: _isHalfDay ? 'Date' : 'To Date',
                        date: _isHalfDay ? _fromDate : _toDate,
                        onTap: _isHalfDay ? () {} : _pickTo,
                        color: _color,
                        disabled: _isHalfDay,
                      )),
                    ]),
                    const SizedBox(height: 12),
                    LeaveMonthCalendar(
                      from: _fromDate,
                      to: _isHalfDay ? _fromDate : _toDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      color: _color,
                      singleDate: _isHalfDay,
                      isNonWorking: _isNonWorkingDay,
                      onRangeChanged: (f, t) => setState(() {
                        _fromDate = f;
                        _toDate = _isHalfDay ? f : t;
                      }),
                    ),

                    // What this will actually cost, and why — shown before
                    // submitting rather than discovered afterwards.
                    if (_effectiveDays > 0) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: _color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_fmtEffective(_effectiveDays)} will be deducted',
                            style: TextStyle(
                                color: _color,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ),
                      ),
                      if (_deduction?.hasSurprise ?? false) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((_deduction?.sandwichDays ?? 0) > 0)
                                _explain(
                                  Icons.info_outline_rounded,
                                  'Your weekly off falls between leave days, so it is '
                                  'counted as leave too (sandwich policy).',
                                ),
                              if ((_deduction?.holidaysExcluded ?? 0) > 0)
                                _explain(
                                  Icons.celebration_rounded,
                                  '${_deduction!.holidaysExcluded} public holiday'
                                  '${_deduction!.holidaysExcluded == 1 ? '' : 's'} in this '
                                  'range — not charged to your balance.',
                                ),
                              if ((_deduction?.lopDays ?? 0) > 0)
                                _explain(
                                  Icons.money_off_rounded,
                                  '${_deduction!.lopDays} day'
                                  '${_deduction!.lopDays == 1 ? '' : 's'} beyond the 2-day '
                                  'casual leave adjustment will be loss of pay.',
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // Reason
                    TextField(
                      controller: _reasonController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        alignLabelWithHint: true,
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 60),
                          child: Icon(Icons.notes_rounded, color: _color, size: 20),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: _color, width: 2),
                        ),
                        filled: true, fillColor: Colors.white,
                        labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ),

                    // Supporting document upload — optional, any leave type
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.picture_as_pdf_rounded, color: _color, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Supporting Document (PDF, optional)',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                              const SizedBox(height: 2),
                              Text(
                                _uploadingProof
                                    ? 'Uploading…'
                                    : _proofFileName.isNotEmpty
                                        ? _proofFileName
                                        : 'No file selected',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    color: _proofFileName.isNotEmpty
                                        ? const Color(0xFF111827)
                                        : const Color(0xFF9CA3AF)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_proofFileName.isNotEmpty && !_uploadingProof)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            tooltip: 'Remove',
                            onPressed: () => setState(() {
                              _proofUrl = '';
                              _proofFileName = '';
                            }),
                          ),
                        OutlinedButton(
                          onPressed: _uploadingProof ? null : _pickProofFile,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: _uploadingProof
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_proofFileName.isNotEmpty ? 'Replace' : 'Upload'),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Submit Application'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _TcPoint extends StatelessWidget {
  final String text;
  const _TcPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.circle, size: 5, color: Colors.orange.shade700),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
        ),
      ]),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final Color color;
  final bool disabled;
  const _DateTile({
    required this.label,
    required this.date,
    required this.onTap,
    required this.color,
    this.disabled = false,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: disabled
              ? const Color(0xFFF8FAFC)
              : (date != null ? color.withValues(alpha: 0.05) : Colors.white),
          border: Border.all(
            color: disabled
                ? const Color(0xFFE5E7EB)
                : (date != null ? color.withValues(alpha: 0.4) : const Color(0xFFE5E7EB)),
            width: date != null && !disabled ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: date != null ? color : const Color(0xFF6B7280),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.calendar_today_rounded,
                size: 16, color: date != null ? color : const Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Text(
              date != null ? _fmt(date!) : 'Select date',
              style: TextStyle(
                fontSize: 13,
                fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
                color: date != null ? const Color(0xFF111827) : const Color(0xFF6B7280),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
