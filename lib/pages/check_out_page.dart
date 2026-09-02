import 'package:flutter/material.dart';
import '../models/attendance_policy_store.dart';
import '../models/attendance_store.dart';
import '../models/leave_store.dart';
import '../models/office_timing.dart';
import '../models/user_session.dart';
import '../services/gps_tracking_service.dart';
import '../services/notification_service.dart';
import '../services/selfie_capture_service.dart';
import '../services/supabase_service.dart';
import '../utils/checkin_status.dart';
import '../utils/geofence.dart';
import '../widgets/back_button.dart';
import '../theme/app_theme.dart';

// Minutes granted by an approved 'Permission' leave application covering
// today; 0 if none. Same pool of minutes checkInStatusFor uses for a late
// check-in — here it's spent on an early check-out instead.
int _approvedPermissionMinutesToday(List<LeaveApplication> apps) {
  final today = DateTime.now();
  final me = UserSession.name.trim().toLowerCase();
  bool coversToday(LeaveApplication a) {
    final d = DateTime(today.year, today.month, today.day);
    final f = DateTime(a.from.year, a.from.month, a.from.day);
    final t = DateTime(a.to.year, a.to.month, a.to.day);
    return !d.isBefore(f) && !d.isAfter(t);
  }

  for (final a in apps) {
    if (a.employeeName.trim().toLowerCase() != me) continue;
    if (a.leaveType != 'Permission') continue;
    if (a.managerStatus != LeaveApprovalStatus.approved) continue;
    if (coversToday(a)) return LeaveStore.permMinutesFromReason(a.reason);
  }
  return 0;
}

class CheckOutPage extends StatefulWidget {
  const CheckOutPage({super.key});

  @override
  State<CheckOutPage> createState() => _CheckOutPageState();
}

class _CheckOutPageState extends State<CheckOutPage> {
  static Color get _color => AppTheme.accentBlue;

  bool _loading = true;
  AttendanceRecord? _record;
  int _permissionMinutes = 0;
  bool _outsideOffice = false;
  String _nearestLocationName = '';
  bool _locatingForCheckOut = false;

  final _timeController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _autoFillTime();
    _loadTodayRecord();
  }

  @override
  void dispose() {
    _timeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _autoFillTime() {
    final now = DateTime.now();
    _timeController.text =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadTodayRecord() async {
    final results = await Future.wait([
      SupabaseService.fetchTodayAttendance(UserSession.employeeId),
      SupabaseService.fetchLeaveApplications(),
    ]);
    if (!mounted) return;
    final rec = results[0] as AttendanceRecord?;
    final apps = results[1] as List<LeaveApplication>;
    setState(() {
      _record = rec;
      _permissionMinutes = _approvedPermissionMinutesToday(apps);
      _loading = false;
    });
  }

  Future<void> _onCheckOut() async {
    // Same race as check-in: an unloaded policy store geofences a user whose
    // real policy is Unrestricted, and an unloaded timing store loses the
    // no-fixed-timing row.
    // Same Safari gesture constraint as check-in: request the position before
    // anything that awaits the network. See check_in_page for the reasoning.
    await Future.wait([
      AttendancePolicyStore.ensureLoaded(),
      OfficeTimingStore.ensureLoaded(),
      // Timed out rather than awaited indefinitely: on a stalled connection
      // these two network calls would otherwise leave the employee on the
      // spinner with nothing on screen. Both stores fall back to sensible
      // built-in defaults when empty, so proceeding is better than hanging.
    ].map((f) => f.timeout(const Duration(seconds: 10), onTimeout: () {})));
    if (!mounted) return;
    setState(() => _locatingForCheckOut = true);
    final pos = await GpsTrackingService.getCurrentLocation();
    final policy = AttendancePolicyStore.policyForEmployee(
      employeeId: UserSession.employeeId,
      department: UserSession.department,
      workLocation: UserSession.workLocation,
    );
    final locations = AttendancePolicyStore.locationsForEmployee(UserSession.employeeId);
    // A failed location lookup (denied permission, GPS off, etc.) is treated
    // the same as being outside every assigned location — employees whose
    // policy requires one still get a check-out, just with a required
    // reason, rather than silently skipping the geofence check.
    final geofence = evaluateGeofence(
      policy: policy, locations: locations, lat: pos?.latitude, lng: pos?.longitude,
    );
    final outsideOffice = geofence.outsideAllowedLocation;
    if (!mounted) return;
    setState(() {
      _locatingForCheckOut = false;
      _outsideOffice = outsideOffice;
      _nearestLocationName = geofence.nearestLocation?.name ?? '';
    });

    if (outsideOffice && _noteController.text.trim().isEmpty) {
      final locationPhrase = _nearestLocationName.isNotEmpty
          ? "outside $_nearestLocationName"
          : 'outside your assigned location';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('You Are Not At Your Assigned Location'),
          content: Text(
            "You're $locationPhrase. Please enter a reason "
            'below to check out from this location.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final schedule = OfficeTimingStore.scheduleForCurrentUser();
    if (!outsideOffice &&
        isEarlyCheckOut(_timeController.text, schedule, _permissionMinutes) &&
        _noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please add a reason for checking out early.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    setState(() => _locatingForCheckOut = true);
    final selfiePath = !selfieRequiredForCurrentUser
        ? ''   // Management: no selfie required
        : await SelfieCaptureService.captureAndUpload(
      employeeId: UserSession.employeeId,
      date: date,
      kind: 'checkout',
      label: 'Check-Out',
    );
    if (!mounted) return;
    if (selfiePath == null && selfieRequiredForCurrentUser) {
      setState(() => _locatingForCheckOut = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('A selfie is required to check out. Please try again.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }
    setState(() => _locatingForCheckOut = false);

    GpsTrackingService.stop();
    AttendanceStore.isCheckedIn = false;

    await SupabaseService.saveCheckOut(
      employeeId: UserSession.employeeId,
      date: date,
      time: _timeController.text,
      note: _noteController.text.trim(),
      selfiePath: selfiePath ?? '',
      lat: pos?.latitude,
      lng: pos?.longitude,
      withinRadius: geofence.requiresLocation ? geofence.isWithinAnyLocation : null,
    );

    if (!mounted) return;
    if (UserSession.email.isNotEmpty) {
      NotificationService.checkOutRecorded(
        employeeEmail: UserSession.email,
        time: _timeController.text,
        employeeRoutePrefix: NotificationService.routePrefixForRole(UserSession.role),
      );
    }
    // Re-fetch to show updated record
    final rec = await SupabaseService.fetchTodayAttendance(UserSession.employeeId);
    if (mounted) {
      setState(() => _record = rec);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Checked out successfully'),
        backgroundColor: _color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const NavBackButton(),
            const SizedBox(width: 8),
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.logout_rounded, color: _color, size: 26),
            ),
            const SizedBox(width: 16),
            Text('Check Out',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium),
          ]),
          const SizedBox(height: 24),

          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: CircularProgressIndicator(),
            ))

          // Not checked in at all
          else if (_record == null || _record!.checkInTime.isEmpty)
            _InfoBanner(
              icon: Icons.info_rounded,
              message: "You haven't checked in today. Please check in first.",
              color: Colors.orange,
              isDark: isDark,
            )

          // Already checked out
          else if (_record!.checkOutTime.isNotEmpty)
            _AlreadyCheckedOut(record: _record!, isDark: isDark)

          // Checked in, not yet checked out
          else ...[
            _CheckInSummaryBanner(record: _record!, isDark: isDark),
            const SizedBox(height: 16),
            if (_outsideOffice) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.red.withValues(alpha: 0.12) : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? Colors.red.shade700 : Colors.red.shade300),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.location_off_rounded,
                      color: isDark ? Colors.red.shade300 : Colors.red.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "You're not at ${_nearestLocationName.isNotEmpty ? _nearestLocationName : 'your assigned location'}. "
                      'Please give a reason to check out from here.',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: isDark ? Colors.red.shade300 : Colors.red.shade800),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ListenableBuilder(
                  listenable: _timeController,
                  builder: (context, _) {
                    final isEarly = isEarlyCheckOut(_timeController.text,
                        OfficeTimingStore.scheduleForCurrentUser(),
                        _permissionMinutes);
                    final showNote = isEarly || _outsideOffice;
                    final outLocationLabel =
                        _nearestLocationName.isNotEmpty ? _nearestLocationName : 'your assigned location';
                    final noteLabel = _outsideOffice && isEarly
                        ? 'Reason for early & outside-location check-out (required)'
                        : _outsideOffice
                            ? 'Reason for checking out outside $outLocationLabel (required)'
                            : 'Reason for early check-out (required)';
                    return Column(children: [
                      TextField(
                        controller: _timeController,
                        // System clock only — see the same note on
                        // check_in_page.dart. An editable check-out time
                        // lets someone record leaving later than they did,
                        // and free text breaks the HH:MM parsing the
                        // payroll and punctuality reports rely on.
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Check-Out Time',
                          prefixIcon: Icon(Icons.access_time_rounded, color: _color, size: 20),
                          suffixIcon: IconButton(
                            tooltip: 'Refresh time',
                            icon: Icon(Icons.schedule_rounded, color: _color),
                            onPressed: _autoFillTime,
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: cs.outlineVariant),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: _color, width: 2),
                          ),
                          filled: true,
                          fillColor: cs.surface,
                          labelStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                        ),
                      ),
                      if (showNote) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _noteController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: noteLabel,
                            hintText: 'e.g. left early for client meeting',
                            prefixIcon: Icon(Icons.edit_note_rounded, color: _color, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: cs.outlineVariant),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: _color, width: 2),
                            ),
                            filled: true,
                            fillColor: cs.surface,
                            labelStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                          ),
                        ),
                      ],
                    ]);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _locatingForCheckOut ? null : _onCheckOut,
                icon: _locatingForCheckOut
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.logout_rounded),
                label: Text(_locatingForCheckOut ? 'Checking location…' : 'Check Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final MaterialColor color;
  final bool isDark;
  const _InfoBanner({required this.icon, required this.message, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.12) : color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? color.shade700 : color.shade300),
      ),
      child: Row(children: [
        Icon(icon, color: isDark ? color.shade300 : color.shade700, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? color.shade300 : color.shade800,
                  fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _CheckInSummaryBanner extends StatelessWidget {
  final AttendanceRecord record;
  final bool isDark;
  const _CheckInSummaryBanner({required this.record, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.green.withValues(alpha: 0.1) : Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.green.shade700 : Colors.green.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.login_rounded,
              color: isDark ? Colors.green.shade400 : Colors.green.shade600, size: 18),
          const SizedBox(width: 10),
          Text('Checked in at ',
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.green.shade400 : Colors.green.shade700)),
          Text(record.checkInTime,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace',
                  color: isDark ? Colors.green.shade300 : Colors.green.shade800)),
          const SizedBox(width: 6),
          Text('· GPS tracking active',
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.green.shade500 : Colors.green.shade600)),
        ]),
        if (record.checkInNote.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(record.checkInNote,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.green.shade400 : Colors.green.shade700)),
        ],
      ]),
    );
  }
}

class _AlreadyCheckedOut extends StatelessWidget {
  final AttendanceRecord record;
  final bool isDark;
  const _AlreadyCheckedOut({required this.record, required this.isDark});

  @override
  Widget build(BuildContext context) {
    String? duration;
    try {
      final inParts = record.checkInTime.split(':');
      final outParts = record.checkOutTime.split(':');
      if (inParts.length == 2 && outParts.length == 2) {
        final inMin = int.parse(inParts[0]) * 60 + int.parse(inParts[1]);
        final outMin = int.parse(outParts[0]) * 60 + int.parse(outParts[1]);
        final diff = outMin - inMin;
        if (diff > 0) {
          final h = diff ~/ 60;
          final m = diff % 60;
          duration = h > 0 ? '${h}h ${m}m' : '${m}m';
        }
      }
    } catch (_) {}

    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.primaryBlue.withValues(alpha: 0.12) : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? Colors.blue.shade700 : Colors.blue.shade300),
        ),
        child: Column(children: [
          Icon(Icons.check_circle_rounded,
              color: isDark ? Colors.blue.shade300 : Colors.blue.shade600, size: 36),
          const SizedBox(height: 10),
          Text('Already Checked Out',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: isDark ? Colors.blue.shade200 : Colors.blue.shade800)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _TimeBlock(label: 'Check-In', time: record.checkInTime, isDark: isDark),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.arrow_forward_rounded,
                  color: isDark ? Colors.blue.shade400 : Colors.blue.shade400, size: 20),
            ),
            _TimeBlock(label: 'Check-Out', time: record.checkOutTime, isDark: isDark),
          ]),
          if (duration != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Duration: $duration',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.blue.shade200 : Colors.blue.shade800)),
            ),
          ],
          if (record.checkInNote.isNotEmpty || record.checkOutNote.isNotEmpty) ...[
            const SizedBox(height: 14),
            if (record.checkInNote.isNotEmpty)
              _NoteLine(label: 'Check-in note', text: record.checkInNote, isDark: isDark),
            if (record.checkOutNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              _NoteLine(label: 'Check-out note', text: record.checkOutNote, isDark: isDark),
            ],
          ],
        ]),
      ),
    ]);
  }
}

class _NoteLine extends StatelessWidget {
  final String label;
  final String text;
  final bool isDark;
  const _NoteLine({required this.label, required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12,
              color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final String label;
  final String time;
  final bool isDark;
  const _TimeBlock({required this.label, required this.time, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(label,
          style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.blue.shade400 : Colors.blue.shade600)),
      const SizedBox(height: 4),
      Text(time,
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'monospace',
              color: isDark ? Colors.blue.shade200 : Colors.blue.shade900)),
    ]);
  }
}
