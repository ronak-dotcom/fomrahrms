import 'dart:async';

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
import '../utils/location_consent.dart';
import '../widgets/back_button.dart';
import '../widgets/route_map_view.dart';
import '../theme/app_theme.dart';

// An approved Permission application already covering today explains the
// late arrival, so the note box shouldn't nag for one on top of it.
bool _onApprovedPermissionToday(List<LeaveApplication> apps) {
  final today = DateTime.now();
  final me = UserSession.name.trim().toLowerCase();
  bool coversToday(LeaveApplication a) {
    final d = DateTime(today.year, today.month, today.day);
    final f = DateTime(a.from.year, a.from.month, a.from.day);
    final t = DateTime(a.to.year, a.to.month, a.to.day);
    return !d.isBefore(f) && !d.isAfter(t);
  }

  return apps.any((a) =>
      a.employeeName.trim().toLowerCase() == me &&
      a.leaveType == 'Permission' &&
      a.managerStatus == LeaveApprovalStatus.approved &&
      coversToday(a));
}

class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  static Color get _color => AppTheme.primaryBlue;

  bool _loading = true;
  AttendanceRecord? _record; // today's record from Supabase
  bool _onPermission = false;
  bool _outsideOffice = false;
  String _nearestLocationName = '';
  bool _locatingForCheckIn = false;

  final _timeController = TextEditingController();
  final _noteController = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _autoFillTime();
    _loadTodayRecord();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
      _onPermission = _onApprovedPermissionToday(apps);
      _loading = false;
    });
    if (rec != null && rec.checkInTime.isNotEmpty) {
      AttendanceStore.isCheckedIn = rec.checkOutTime.isEmpty;
      if (AttendanceStore.isCheckedIn) {
        GpsTrackingService.start();
        _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (mounted) setState(() {});
        });
      }
    }
  }

  Future<void> _onCheckIn() async {
    await ensureLocationConsent(context);
    if (!mounted) return;

    setState(() => _locatingForCheckIn = true);

    // Ask for the position FIRST, before anything that awaits the network.
    //
    // Safari ties the geolocation permission prompt to a user gesture and will
    // refuse the request if too much has happened since the tap. Loading the
    // two stores first — two round-trips to Supabase — is long enough for
    // Safari to treat the gesture as spent and deny silently, which
    // getCurrentLocation() then reports as "permission not granted".
    //
    // Everyone here uses Safari, and GPS has been null on 100% of attendance
    // records. Ordering the store loads ahead of this call was my change, and
    // it can only have made that worse. The stores are not needed until the
    // geofence is evaluated below, so this costs nothing.
    final pos = await GpsTrackingService.getCurrentLocation();

    // Now load the stores. Both are kicked off fire-and-forget in main(), so
    // on a cold start they can still be EMPTY. An empty AttendancePolicyStore
    // makes policyForEmployee() return the built-in fallback (Office,
    // single_location), geofencing a user whose real policy is Unrestricted;
    // an empty OfficeTimingStore loses the no-fixed-timing row, so Management
    // falls through to the 09:30 default and is asked for a late reason.
    await Future.wait([
      AttendancePolicyStore.ensureLoaded(),
      OfficeTimingStore.ensureLoaded(),
    ]);
    if (!mounted) return;
    final policy = AttendancePolicyStore.policyForEmployee(
      employeeId: UserSession.employeeId,
      department: UserSession.department,
      workLocation: UserSession.workLocation,
    );
    final locations = AttendancePolicyStore.locationsForEmployee(UserSession.employeeId);
    // A failed location lookup (denied permission, GPS off, etc.) is treated
    // the same as being outside every assigned location — employees whose
    // policy requires one still get a check-in, just with a required
    // reason, rather than silently skipping the geofence check.
    final geofence = evaluateGeofence(
      policy: policy, locations: locations, lat: pos?.latitude, lng: pos?.longitude,
    );
    final outsideOffice = geofence.outsideAllowedLocation;
    if (!mounted) return;
    setState(() {
      _locatingForCheckIn = false;
      _outsideOffice = outsideOffice;
      _nearestLocationName = geofence.nearestLocation?.name ?? '';
    });

    if (outsideOffice && _noteController.text.trim().isEmpty) {
      // Distinguish "we couldn't read your location at all" from "we read it
      // and you're genuinely elsewhere". Both used to show the same message,
      // which made a GPS failure look like the employee was in the wrong place.
      final gpsError = pos == null ? GpsTrackingService.lastLocationError : null;
      final locationPhrase = _nearestLocationName.isNotEmpty
          ? "outside $_nearestLocationName"
          : 'outside your assigned location';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(gpsError != null
              ? 'Could Not Check Your Location'
              : 'You Are Not At Your Assigned Location'),
          content: Text(
            gpsError != null
                ? '$gpsError\n\nYou can still check in — please enter a reason below.'
                : "You're $locationPhrase. Please enter a reason "
                    'below to check in from this location.',
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
    if (!_onPermission && !outsideOffice && isLateCheckIn(_timeController.text, schedule) &&
        _noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please add a reason for checking in late.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final empName = UserSession.name.isNotEmpty ? UserSession.name : 'Employee';

    setState(() => _locatingForCheckIn = true);
    final selfiePath = !selfieRequiredForCurrentUser
        ? ''   // Management: no selfie required
        : await SelfieCaptureService.captureAndUpload(
      employeeId: UserSession.employeeId,
      date: date,
      kind: 'checkin',
      label: 'Check-In',
    );
    if (!mounted) return;
    if (selfiePath == null && selfieRequiredForCurrentUser) {
      setState(() => _locatingForCheckIn = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('A selfie is required to check in. Please try again.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }
    setState(() => _locatingForCheckIn = false);

    AttendanceStore.isCheckedIn = true;
    GpsTrackingService.start();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    final loc = pos != null ? '${pos.latitude},${pos.longitude}' : '';

    final err = await SupabaseService.saveCheckIn(
      employeeName: empName,
      employeeId: UserSession.employeeId,
      date: date,
      time: _timeController.text,
      location: loc,
      note: _noteController.text.trim(),
      selfiePath: selfiePath ?? '',
      lat: pos?.latitude,
      lng: pos?.longitude,
      accuracy: pos?.accuracy,
      withinRadius: geofence.requiresLocation ? geofence.isWithinAnyLocation : null,
      policyName: policy.name,
    );

    if (!mounted) return;

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sync error: $err'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    } else {
      if (UserSession.email.isNotEmpty) {
        NotificationService.checkInRecorded(
          employeeEmail: UserSession.email,
          time: _timeController.text,
          employeeRoutePrefix: NotificationService.routePrefixForRole(UserSession.role),
        );
      }
      NotificationService.notifyIfLateCheckIn(
        employeeName: empName,
        checkInTime: _timeController.text,
        date: now,
        schedule: schedule,
      );
      // Re-fetch to get the saved record
      final rec = await SupabaseService.fetchTodayAttendance(UserSession.employeeId);
      if (mounted) setState(() => _record = rec);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
              child: Icon(Icons.login_rounded, color: _color, size: 26),
            ),
            const SizedBox(width: 16),
            Text('Check In',
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
          else if (_record != null && _record!.checkInTime.isNotEmpty)
            _CheckedInView(record: _record!, refreshTimer: _refreshTimer)
          else
            _CheckInForm(
              timeController: _timeController,
              noteController: _noteController,
              onPermission: _onPermission,
              outsideOffice: _outsideOffice,
              nearestLocationName: _nearestLocationName,
              locating: _locatingForCheckIn,
              color: _color,
              cs: cs,
              onRefreshTime: _autoFillTime,
              onCheckIn: _onCheckIn,
            ),
        ]),
      ),
    );
  }
}

// ── Already checked in view ───────────────────────────────────────────────────
class _CheckedInView extends StatelessWidget {
  final AttendanceRecord record;
  final Timer? refreshTimer;
  const _CheckedInView({required this.record, this.refreshTimer});

  static Color get _color => AppTheme.primaryBlue;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pts = record.gpsPoints.isNotEmpty
        ? record.gpsPoints
        : _parseSingleLocation(record.location);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Status banner
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.green.withValues(alpha: 0.12) : Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? Colors.green.shade700 : Colors.green.shade300),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_rounded,
              color: isDark ? Colors.green.shade400 : Colors.green.shade600, size: 28),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Checked In',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.green.shade300 : Colors.green.shade800)),
            const SizedBox(height: 2),
            Text(record.date,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.green.shade400 : Colors.green.shade600)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.green.withValues(alpha: 0.2) : Colors.green.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(record.checkInTime,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800,
                    color: isDark ? Colors.green.shade300 : Colors.green.shade800,
                    fontFamily: 'monospace')),
          ),
        ]),
      ),
      const SizedBox(height: 16),

      // Note
      if (record.checkInNote.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE5E7EB)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.edit_note_rounded, size: 16,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(record.checkInNote,
                  style: TextStyle(fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8))),
            ),
          ]),
        ),
        const SizedBox(height: 12),
      ],

      // Location & route
      if (pts.isNotEmpty) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.route_rounded, color: _color, size: 18),
                const SizedBox(width: 8),
                Text(
                  pts.length > 1 ? 'Route (${pts.length} points)' : 'Check-In Location',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ]),
              const SizedBox(height: 12),
              RouteMapView(points: pts, recordId: record.id, height: 220),
              const SizedBox(height: 8),
              Text(
                'Last: ${pts.last[0].toStringAsFixed(6)}, ${pts.last[1].toStringAsFixed(6)}',
                style: TextStyle(fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
      ],

      // GPS status
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? Colors.blue.withValues(alpha: 0.1) : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isDark ? Colors.blue.shade700 : Colors.blue.shade200),
        ),
        child: Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: Colors.blue.shade400, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            record.checkOutTime.isEmpty
                ? 'GPS tracking active until check-out'
                : 'Checked out at ${record.checkOutTime}',
            style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                fontWeight: FontWeight.w500),
          ),
        ]),
      ),
    ]);
  }

  List<List<double>> _parseSingleLocation(String loc) {
    final parts = loc.split(',');
    if (parts.length != 2) return [];
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return [];
    return [[lat, lng]];
  }
}


// ── Check-in form (not yet checked in) ───────────────────────────────────────
class _CheckInForm extends StatelessWidget {
  final TextEditingController timeController;
  final TextEditingController noteController;
  final bool onPermission;
  final bool outsideOffice;
  final String nearestLocationName;
  final bool locating;
  final Color color;
  final ColorScheme cs;
  final VoidCallback onRefreshTime;
  final VoidCallback onCheckIn;
  const _CheckInForm({
    required this.timeController, required this.noteController, required this.onPermission,
    required this.outsideOffice, required this.nearestLocationName, required this.locating,
    required this.color, required this.cs, required this.onRefreshTime, required this.onCheckIn,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locationLabel = nearestLocationName.isNotEmpty ? nearestLocationName : 'your assigned location';
    return Column(children: [
      if (outsideOffice) ...[
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
                "You're not at $locationLabel. Please give a reason to check in from here.",
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
            listenable: timeController,
            builder: (context, _) {
              final isLate = !onPermission &&
                  isLateCheckIn(timeController.text,
                      OfficeTimingStore.scheduleForCurrentUser());
              final showNote = isLate || outsideOffice;
              final noteLabel = outsideOffice && isLate
                  ? 'Reason for late & outside-location check-in (required)'
                  : outsideOffice
                      ? 'Reason for checking in outside $locationLabel (required)'
                      : 'Reason for late check-in (required)';
              return Column(children: [
                TextField(
                  controller: timeController,
                  // The recorded time must be the system clock, not
                  // whatever someone types. This was an editable field:
                  // an employee arriving at 10:30 could type 09:00 and the
                  // lateness calculation would believe it, and free text
                  // like "12 pm" reached production and cannot be parsed
                  // by the punctuality report, which reads HH:MM by
                  // character position.
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Check-In Time',
                    prefixIcon: Icon(Icons.access_time_rounded, color: color, size: 20),
                    suffixIcon: IconButton(
                      tooltip: 'Refresh time',
                      icon: Icon(Icons.schedule_rounded, color: color),
                      onPressed: onRefreshTime,
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: color, width: 2),
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    labelStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                if (showNote) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: noteLabel,
                      hintText: 'e.g. traffic delay, doctor appointment',
                      prefixIcon: Icon(Icons.edit_note_rounded, color: color, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: color, width: 2),
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
          onPressed: locating ? null : onCheckIn,
          icon: locating
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.login_rounded),
          label: Text(locating ? 'Checking location…' : 'Check In'),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    ]);
  }
}
