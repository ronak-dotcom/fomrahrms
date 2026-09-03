import 'dart:async';
import '../utils/checkin_location.dart';
import '../models/attendance_policy_store.dart';

import 'package:flutter/material.dart';
import '../models/attendance_store.dart';
import '../models/leave_store.dart';
import '../models/office_timing.dart';
import '../models/user_session.dart';
import '../services/gps_tracking_service.dart';
import '../services/notification_service.dart';
import '../services/selfie_capture_service.dart';
import '../services/supabase_service.dart';
import '../utils/checkin_status.dart';
import '../utils/location_consent.dart';
import '../widgets/back_button.dart';
import '../widgets/route_map_view.dart';
import '../theme/app_theme.dart';

class EmployeeAttendancePage extends StatefulWidget {
  // prefix kept for router compatibility; not used internally
  final String prefix;
  const EmployeeAttendancePage({super.key, this.prefix = '/employee'});

  @override
  State<EmployeeAttendancePage> createState() => _EmployeeAttendancePageState();
}

class _EmployeeAttendancePageState extends State<EmployeeAttendancePage> {
  static Color get _blue => AppTheme.primaryBlue;
  static const _teal  = Color(0xFF15803D);

  bool _loading = true;
  bool _submitting = false;
  AttendanceRecord? _record;
  // Minutes granted by a same-day approved Permission — extends the late
  // check-in cutoff and pulls the early check-out cutoff earlier by the
  // same amount; 0 if none. See checkin_status.dart's approvedPermissionMinutesFor.
  int _permissionMinutes = 0;
  Timer? _refreshTimer;

  final _checkInCtrl  = TextEditingController();
  final _checkOutCtrl = TextEditingController();
  final _checkInNoteCtrl  = TextEditingController();
  final _checkOutNoteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fillTime(_checkInCtrl);
    _fillTime(_checkOutCtrl);
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    _checkInNoteCtrl.dispose();
    _checkOutNoteCtrl.dispose();
    super.dispose();
  }

  void _fillTime(TextEditingController ctrl) {
    final now = DateTime.now();
    ctrl.text =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SupabaseService.fetchTodayAttendance(UserSession.employeeId),
      SupabaseService.fetchLeaveApplications(),
    ]);
    if (!mounted) return;
    final rec = results[0] as AttendanceRecord?;
    final leaves = results[1] as List<LeaveApplication>;
    setState(() {
      _record  = rec;
      _permissionMinutes =
          approvedPermissionMinutesFor(leaves, UserSession.name, DateTime.now());
      _loading = false;
    });
    if (rec != null && rec.checkInTime.isNotEmpty && rec.checkOutTime.isEmpty) {
      AttendanceStore.isCheckedIn = true;
      GpsTrackingService.start();
      _refreshTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _checkIn() async {
    await ensureLocationConsent(context);
    if (!mounted) return;

    // This path did no geofence evaluation and never passed lat/lng to
    // saveCheckIn — same gap as the dashboard card. resolveCheckInLocation()
    // also loads both stores, so the explicit ensureLoaded() calls that were
    // here are now redundant.
    final loc = await resolveCheckInLocation();
    if (!mounted) return;
    if (await promptForLocationReason(context, loc,
        noteIsEmpty: _checkInNoteCtrl.text.trim().isEmpty)) {
      return;
    }
    if (!mounted) return;

    final schedule = OfficeTimingStore.scheduleForCurrentUser();
    final needsNote = isLateCheckIn(_checkInCtrl.text, schedule) && _permissionMinutes == 0;
    if (needsNote && _checkInNoteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please add a reason for checking in late.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    setState(() => _submitting = true);
    final now  = DateTime.now();
    final date = _fmtDate(now);
    final empName = UserSession.name.isNotEmpty ? UserSession.name : 'Employee';

    final selfiePath = !selfieRequiredForCurrentUser
        ? ''   // Management: no selfie required
        : await SelfieCaptureService.captureAndUpload(
      employeeId: UserSession.employeeId,
      date: date,
      kind: 'checkin',
      label: 'Check-In',
    );
    if (selfiePath == null && selfieRequiredForCurrentUser) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Selfie required to check in. ${SelfieCaptureService.lastFailure ?? "Please try again."}'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    AttendanceStore.isCheckedIn = true;
    GpsTrackingService.start();
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    // Position already resolved above by resolveCheckInLocation(); asking
    // again would prompt twice and could return a different fix.
    final err = await SupabaseService.saveCheckIn(
      employeeName: empName,
      employeeId:   UserSession.employeeId,
      date:     date,
      time:     _checkInCtrl.text,
      location: loc.position != null
          ? '${loc.position!.latitude},${loc.position!.longitude}'
          : '',
      note:     _checkInNoteCtrl.text.trim(),
      selfiePath: selfiePath ?? '',
      selfieFromPicker: SelfieCaptureService.lastUsedFallback,
      lat:          loc.lat,
      lng:          loc.lng,
      withinRadius: loc.withinRadius,
      accuracy:     loc.accuracy,
      policyName:   loc.policyName,
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
          time: _checkInCtrl.text,
          employeeRoutePrefix: NotificationService.routePrefixForRole(UserSession.role),
        );
      }
      NotificationService.notifyIfLateCheckIn(
        employeeName: empName,
        checkInTime: _checkInCtrl.text,
        date: now,
        schedule: schedule,
      );
    }

    final rec = await SupabaseService.fetchTodayAttendance(UserSession.employeeId);
    if (mounted) setState(() { _record = rec; _submitting = false; });
  }

  Future<void> _checkOut() async {
    final needsNote = isEarlyCheckOut(_checkOutCtrl.text,
        OfficeTimingStore.scheduleForCurrentUser(), _permissionMinutes);
    if (needsNote && _checkOutNoteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please add a reason for checking out early.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    setState(() => _submitting = true);
    final now  = DateTime.now();
    final date = _fmtDate(now);

    final selfiePath = !selfieRequiredForCurrentUser
        ? ''   // Management: no selfie required
        : await SelfieCaptureService.captureAndUpload(
      employeeId: UserSession.employeeId,
      date: date,
      kind: 'checkout',
      label: 'Check-Out',
    );
    if (selfiePath == null && selfieRequiredForCurrentUser) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Selfie required to check out. ${SelfieCaptureService.lastFailure ?? "Please try again."}'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    GpsTrackingService.stop();
    AttendanceStore.isCheckedIn = false;
    _refreshTimer?.cancel();
    _refreshTimer = null;

    await SupabaseService.saveCheckOut(
      employeeId: UserSession.employeeId,
      date: date,
      time: _checkOutCtrl.text,
      note: _checkOutNoteCtrl.text.trim(),
      selfiePath: selfiePath ?? '',
      selfieFromPicker: SelfieCaptureService.lastUsedFallback,
    );
    if (UserSession.email.isNotEmpty) {
      NotificationService.checkOutRecorded(
        employeeEmail: UserSession.email,
        time: _checkOutCtrl.text,
        employeeRoutePrefix: NotificationService.routePrefixForRole(UserSession.role),
      );
    }

    if (!mounted) return;
    _fillTime(_checkOutCtrl);
    final rec = await SupabaseService.fetchTodayAttendance(UserSession.employeeId);
    if (mounted) {
      setState(() { _record = rec; _submitting = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Checked out successfully'),
        backgroundColor: _teal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _dayLabel() {
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return days[DateTime.now().weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rec    = _record;

    final narrow = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: null,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(narrow ? 12 : 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            const NavBackButton(),
            SizedBox(width: narrow ? 4 : 8),
            if (!narrow) ...[
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.access_time_rounded, color: _blue, size: 22),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Attendance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium),
                Text(_dayLabel(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              ]),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: Icon(Icons.refresh_rounded, color: _blue),
              onPressed: _load,
            ),
          ]),
          const SizedBox(height: 24),

          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: CircularProgressIndicator(),
            ))

          // ── Fully checked out ──
          else if (rec != null && rec.checkOutTime.isNotEmpty)
            _DaySummary(record: rec, isDark: isDark)

          // ── Checked in, awaiting check-out ──
          else if (rec != null && rec.checkInTime.isNotEmpty) ...[
            _StatusBanner(
              icon: Icons.check_circle_rounded,
              color: Colors.green,
              isDark: isDark,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.login_rounded,
                      color: isDark ? Colors.green.shade300 : Colors.green.shade700,
                      size: 16),
                  const SizedBox(width: 6),
                  Text('Checked in at ',
                      style: TextStyle(fontSize: 13,
                          color: isDark ? Colors.green.shade300 : Colors.green.shade700)),
                  Text(rec.checkInTime,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'monospace',
                          color: isDark ? Colors.green.shade200 : Colors.green.shade800)),
                  const Spacer(),
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green.shade400, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('GPS active',
                      style: TextStyle(fontSize: 11,
                          color: isDark ? Colors.green.shade400 : Colors.green.shade600)),
                ]),
                if (rec.checkInNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(rec.checkInNote,
                      style: TextStyle(fontSize: 12,
                          color: isDark ? Colors.green.shade400 : Colors.green.shade700)),
                ],
              ]),
            ),

            // GPS route map (if location available)
            if (_routePoints(rec).isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.route_rounded, color: _blue, size: 16),
                      SizedBox(width: 8),
                      Text('Route', style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 10),
                    RouteMapView(points: _routePoints(rec), recordId: rec.id, keyPrefix: 'rt'),
                  ]),
                ),
              ),
            ],

            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _checkOutCtrl,
              builder: (context, _) {
                final showNote = isEarlyCheckOut(_checkOutCtrl.text,
                    OfficeTimingStore.scheduleForCurrentUser(), _permissionMinutes);
                return Column(children: [
                  _TimeField(
                    controller: _checkOutCtrl,
                    label:   'Check-Out Time',
                    icon:    Icons.logout_rounded,
                    color:   _teal,
                    cs:      cs,
                    onRefresh: () => _fillTime(_checkOutCtrl),
                  ),
                  if (showNote) ...[
                    const SizedBox(height: 12),
                    _NoteField(
                      controller: _checkOutNoteCtrl,
                      color: _teal,
                      cs: cs,
                      label: 'Reason for early check-out (required)',
                      hint: 'e.g. left early for client meeting',
                    ),
                  ],
                ]);
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _checkOut,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.logout_rounded),
                label: const Text('Check Out'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]

          // ── Not yet checked in ──
          else ...[
            _StatusBanner(
              icon: Icons.schedule_rounded,
              color: Colors.orange,
              isDark: isDark,
              child: Text("You haven't checked in yet today.",
                  style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.orange.shade300 : Colors.orange.shade800)),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: _checkInCtrl,
              builder: (context, _) {
                final showNote =
                    isLateCheckIn(_checkInCtrl.text,
                        OfficeTimingStore.scheduleForCurrentUser()) &&
                    _permissionMinutes == 0;
                return Column(children: [
                  _TimeField(
                    controller: _checkInCtrl,
                    label:    'Check-In Time',
                    icon:     Icons.login_rounded,
                    color:    _blue,
                    cs:       cs,
                    onRefresh: () => _fillTime(_checkInCtrl),
                  ),
                  if (showNote) ...[
                    const SizedBox(height: 12),
                    _NoteField(
                      controller: _checkInNoteCtrl,
                      color: _blue,
                      cs: cs,
                      label: 'Reason for late check-in (required)',
                      hint: 'e.g. traffic delay, doctor appointment',
                    ),
                  ],
                ]);
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _checkIn,
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.login_rounded),
                label: const Text('Check In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
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

  List<List<double>> _routePoints(AttendanceRecord rec) {
    if (rec.gpsPoints.isNotEmpty) return rec.gpsPoints;
    final parts = rec.location.split(',');
    if (parts.length != 2) return [];
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return [];
    return [[lat, lng]];
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final MaterialColor color;
  final bool isDark;
  final Widget child;
  const _StatusBanner(
      {required this.icon, required this.color, required this.isDark, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.12) : color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? color.shade700 : color.shade300),
      ),
      child: child,
    );
  }
}

class _TimeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color color;
  final ColorScheme cs;
  final VoidCallback onRefresh;
  const _TimeField({
    required this.controller, required this.label, required this.icon,
    required this.color, required this.cs, required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: controller,
          // System clock only — this widget renders both the check-in and
          // check-out time on the attendance page. See check_in_page.dart
          // for why these must not be typeable.
          readOnly: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: color, size: 20),
            suffixIcon: IconButton(
              tooltip: 'Refresh time',
              icon: Icon(Icons.schedule_rounded, color: color),
              onPressed: onRefresh,
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
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  final TextEditingController controller;
  final Color color;
  final ColorScheme cs;
  final String label;
  final String hint;
  const _NoteField({
    required this.controller,
    required this.color,
    required this.cs,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: controller,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
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
      ),
    );
  }
}

// ── Day summary (both checked in + out) ───────────────────────────────────────
class _DaySummary extends StatelessWidget {
  final AttendanceRecord record;
  final bool isDark;
  const _DaySummary({required this.record, required this.isDark});

  String? get _duration {
    try {
      final inP  = record.checkInTime.split(':');
      final outP = record.checkOutTime.split(':');
      if (inP.length == 2 && outP.length == 2) {
        final diff = (int.parse(outP[0]) * 60 + int.parse(outP[1])) -
                     (int.parse(inP[0])  * 60 + int.parse(inP[1]));
        if (diff > 0) {
          final h = diff ~/ 60, m = diff % 60;
          return h > 0 ? '${h}h ${m}m' : '${m}m';
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dur = _duration;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.primaryBlue.withValues(alpha: 0.12)
            : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? Colors.blue.shade700 : Colors.blue.shade200),
      ),
      child: Column(children: [
        Icon(Icons.check_circle_rounded,
            color: isDark ? Colors.blue.shade300 : Colors.blue.shade600,
            size: 36),
        const SizedBox(height: 8),
        Text('Attendance Complete',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700,
                color: isDark ? Colors.blue.shade200 : Colors.blue.shade800)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _TimeBlock(label: 'Check In',  time: record.checkInTime,  isDark: isDark),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Icon(Icons.arrow_forward_rounded,
                color: isDark ? Colors.blue.shade400 : Colors.blue.shade400,
                size: 20),
          ),
          _TimeBlock(label: 'Check Out', time: record.checkOutTime, isDark: isDark),
        ]),
        if (dur != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Duration: $dur',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: isDark ? Colors.blue.shade200 : Colors.blue.shade800)),
          ),
        ],
        if (record.checkInNote.isNotEmpty || record.checkOutNote.isNotEmpty) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (record.checkInNote.isNotEmpty)
                _NoteLine(label: 'Check-in note', text: record.checkInNote, isDark: isDark),
              if (record.checkOutNote.isNotEmpty) ...[
                const SizedBox(height: 6),
                _NoteLine(label: 'Check-out note', text: record.checkOutNote, isDark: isDark),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

class _NoteLine extends StatelessWidget {
  final String label;
  final String text;
  final bool isDark;
  const _NoteLine({required this.label, required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 12,
            color: isDark ? Colors.blue.shade300 : Colors.blue.shade700),
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: text),
        ],
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

