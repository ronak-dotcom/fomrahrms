import 'dart:async';
import '../utils/checkin_location.dart';
import '../models/attendance_policy_store.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/attendance_store.dart';
import '../models/office_timing.dart';
import '../models/user_session.dart';
import '../services/gps_tracking_service.dart';
import '../services/notification_service.dart';
import '../services/selfie_capture_service.dart';
import '../services/supabase_service.dart';
import '../utils/checkin_status.dart';
import '../utils/location_consent.dart';
import '../theme/app_theme.dart';
import 'dashboard_info_blocks.dart' show InfoCard;
import 'hover_lift.dart';

/// One extra static tile shown in the unified Quick Access grid, alongside
/// the built-in Check In/Out and HR Policy tiles.
class QuickTile {
  final String label;
  final IconData icon;
  final Color color;
  final String? route;
  final VoidCallback? onTap;
  const QuickTile({
    required this.label,
    required this.icon,
    required this.color,
    this.route,
    this.onTap,
  }) : assert(route != null || onTap != null, 'QuickTile needs a route or onTap');
}

// ── Unified "Quick Access" grid: Check In/Out + HR Policy + extra tiles ──────
class AttendanceShortcutCard extends StatefulWidget {
  final String attendanceRoute;
  final Color accentColor;
  final String title;
  final List<QuickTile> extraTiles;
  // Fixed tile-grid column count. When set, skips the width-driven
  // LayoutBuilder below — every My Space row call site passes this
  // explicitly, since the row itself already decides wide-vs-narrow
  // layout and each card doesn't need to re-derive its own column count
  // from the (possibly still-settling) width it's been given.
  final int? columns;

  const AttendanceShortcutCard({
    super.key,
    required this.attendanceRoute,
    required this.accentColor,
    this.title = 'Quick Access',
    this.extraTiles = const [],
    this.columns,
  });

  @override
  State<AttendanceShortcutCard> createState() => _AttendanceShortcutCardState();
}

class _AttendanceShortcutCardState extends State<AttendanceShortcutCard> {
  bool _loading = true;
  AttendanceRecord? _record;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rec = await SupabaseService.fetchTodayAttendance(UserSession.employeeId);
    if (!mounted) return;
    setState(() {
      _record = rec;
      _loading = false;
    });
    if (rec != null && rec.checkInTime.isNotEmpty && rec.checkOutTime.isEmpty) {
      AttendanceStore.isCheckedIn = true;
      GpsTrackingService.start();
      _ticker ??= Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _showHRPolicy() async {
    if (!mounted) return;

    String policyText = _kHRPolicyText;
    Map<String, dynamic>? pending;
    try {
      final results = await Future.wait([
        SupabaseService.fetchHRPolicy(),
        SupabaseService.fetchPendingHRPolicyVersion(),
      ]).timeout(const Duration(seconds: 6), onTimeout: () => [null, null]);
      policyText = (results[0] as String?) ?? _kHRPolicyText;
      pending    = results[1] as Map<String, dynamic>?;
    } catch (_) {}

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dlgCtx) => _HRPolicyDialog(
        approvedText: policyText,
        pendingVersion: pending,
        canEdit: UserSession.role == UserRole.hr,
        isManagement: UserSession.role == UserRole.management,
      ),
    );
  }

  static const String _kHRPolicyText = '''
FOMRA HOUSING & INFRASTRUCTURE PVT LTD
Human Resource Policy – 2026 (Version 1.0)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. WORKING HOURS & ATTENDANCE

1.1 Work Days & Timings
• The company follows a 6-day work week (Monday to Saturday).
• Employee working hours: 9:30 AM to 6:30 PM.
• Property Sourcing employees: 9:00 AM to 6:30 PM.
• Sales employees work Monday to Sunday depending on project requirements. They receive a weekly off on either Tuesday or Thursday, predefined by the Reporting Manager / Head of Operations / MD — this cannot be changed on a need basis.

Example:
  Sales Employees: If a client or office meeting falls on their weekly off (Tue/Thu), they cannot avail an alternative off — the weekly off lapses.
  Other Employees: If a client or office meeting falls on their weekly off (Sunday), they can avail comp off for an alternative day with prior approval from their Reporting Manager / Head of Operations / MD.

1.2 Attendance Requirements
• All employees must record attendance using the FOMRA HRMS app from their date of joining.
• Field employees must mark attendance by sharing their current location in the designated WhatsApp group daily. Land Acquisition employees must keep their live location active at all times during working hours.
• Failure to record or mark attendance will be treated as Absent, resulting in Loss of Pay (LOP).
• Any employee leaving work premises during working hours must obtain prior approval from the Reporting Manager. Failure to do so will result in LOP. Repeated violations lead to formal warnings or termination.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2. LATE ARRIVAL & PERMISSIONS POLICY

2.1 Late Arrival Policy
• Employees are permitted a maximum of 3 late arrivals per month.
• A grace period of up to 10 minutes is allowed per late arrival.
• Beyond 3 late arrivals in a month, each subsequent instance is treated as Half-Day LOP or adjusted against available leave balance.

2.2 Permission Policy
• Maximum of 2 hours of permission per month (applicable for Confirmed employees and Probationers).
• Permission can be availed in a single instance or split (minimum 30 minutes per instance, up to 4 occasions).
  - 30+ minutes = counted as 1 hour
  - 1+ hours = counted as 1.5 hours
  - 1.5+ hours = counted as 2 hours
• Beyond monthly limit, further permissions are adjusted against Casual Leave balance.
• Permissions cannot be clubbed with late arrival / early departure.
• Permission requests must be submitted in the pre-determined format provided by HR, or via WhatsApp approval from the Reporting Manager — one day prior, or immediately after the permission day in case of urgency.

2.3 Lunch Hours
• 30-minute lunch break between 1:00 PM and 2:00 PM.
• 15-minute bio break, once in the morning and once in the evening.
• Exceeding the lunch or bio break limit repeatedly will lead to 4 formal warnings per month; if it exceeds Half-Day, it results in LOP or termination.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

3. HOLIDAYS

• Maximum of 9 paid holidays annually, covering national holidays and major festivals.
• The holiday list is published by the HR Department before the start of each year.
• Employees required to work on public holidays are eligible for compensatory off with prior written / WhatsApp approval from their Reporting Manager / Head of Operations / MD.

Sales Employees (weekly off on Tue/Thu):
  If a public holiday falls on the same day as their weekly off, no additional comp off is provided.

Other Employees (excluding Sales):
  If a public holiday falls on a weekday, employees who work on that day are eligible for compensatory off with Reporting Manager approval.

Holidays – 2026:
  1 Jan   – New Year's Day
  14 Jan  – Pongal
  15 Jan  – Thiruvalluvar Day
  26 Jan  – Republic Day
  14 Apr  – Tamil New Year's Day
  15 Aug  – Independence Day
  2 Oct   – Gandhi Jayanthi
  20 Oct  – Ayutha Pooja
  8 Nov   – Diwali
  25 Dec  – Christmas

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

4. LEAVE POLICY

4.1 General Leave Rules
• Leave can be availed in half-day units.
• Leave cannot be adjusted against future leave credits (CL, ML, EL).
• CL, ML, and EL cannot be combined / clubbed together.
• All leave requests must be approved by the Reporting Manager and forwarded to HR at least one day in advance.
• Reporting Managers can approve up to 2 days. Beyond 2 days requires MD & Head of Operations approval.
• Sales Team: Reporting Manager approves up to 1 day; beyond 1 day requires MD approval.

4.2 Form Submission
• All Permission, Leave, Comp Off, and On-Duty (OD) forms must be approved by the Reporting Manager and submitted to HR — one day before leave, or on the day of return.
• Failure to submit approved forms results in LOP.

4.3 Leave Types (On-Role Employees)

Casual Leave (CL):
• 12 days per year (1 per month).
• Can be availed up to 2 days at a time.
• Cannot be carried forward; unused CL lapses at year-end and upon resignation.
• Cannot be clubbed with any other leave type.

Medical Leave (ML):
• 12 days per year.
• Beyond 3 consecutive days requires a medical certificate, else treated as LOP.
• Cannot be carried forward; lapses upon resignation.

Employees on Probation:
• Eligible for 1 day of leave per month (emergencies only).
• No CL, ML, or EL until probation is completed.
• Leave cannot be accumulated or carried forward.
• Eligible for permissions as per the Permission Policy.

Earned Leave (EL):
• For employees who have completed probation and 1 year of continuous service from the date of confirmation.
• 12 days EL per year (accrued at 1 day per completed month).
• Maximum accumulation: 20 days.
• EL balance exceeding 20 days can be encashed by employees with 2+ years of continuous service. Minimum 10 EL days must remain after encashment. Unavailed and unencashed EL lapses.
• Encashment formula: (Last Drawn Basic Salary ÷ Total days of month) × No. of days.

4.4 Sandwich Leave Policy
If leave is taken immediately before AND after a weekly off (Sunday) or declared holiday, the weekly off / holiday is also counted as leave.

Rules:
1. Leave on both sides of Sunday/holiday → Sunday/holiday counted as leave.
2. Leave only before OR after Sunday/holiday → Sunday/holiday not counted.
3. Leave type (CL/ML/EL/LOP) depends on available balance.
4. Leave on Sat+Sun or Sun+Mon is allowed once a month; twice or more = both days LOP.

Examples:
  Sat leave + Mon leave → Sun also becomes leave = 3 days total (sandwich).
  Fri leave + Sat leave, resumed Mon → only 2 days counted (Sun not counted).
  Mon leave only → 1 day (Sun not counted).
  Sat leave only → 1 day (Sun not counted).
  Fri leave + Mon leave, with Sat holiday → 4 days total (Fri + Sat + Sun + Mon).

4.5 Compensatory Off (Comp Off)
• Must be availed within the subsequent month of working on an approved holiday; else it lapses.
• Prior approval from Reporting Manager is mandatory.
• Sales team (rotational weekly offs) are not eligible for comp off on Saturdays & Sundays.
• Cannot be clubbed with weekly off or other leave types.
• Worked < 6 hours → Not eligible for comp off.
• Worked > 6 hours → Eligible for comp off.
• No prior approval → Comp off request rejected.

4.6 Wedding Leave
• Confirmed employees with minimum 2 years of continuous service are entitled to 7 days paid leave for their first legal marriage.
• Employees with more than 2 years of continuous service also receive a wedding gift of ₹25,000 from the company.

4.7 Maternity Leave
• Female employees with 3+ years of continuous service: 60 days (2 months) paid Maternity Leave.
• Miscarriage / medical termination of pregnancy (3+ years service): 42 days (6 weeks) with valid medical documents.
• May be availed up to 2 months before or after delivery, as per medical advice.
• Written notification and medical certificate are mandatory.
• Cannot be clubbed with CL / ML / EL.

4.8 Paternity Leave
• Male employees with 3+ years of continuous service: up to 3 days paid Paternity Leave, to be availed within one month of childbirth.
• Cannot be accumulated, carried forward, or encashed.
• Cannot be clubbed with CL / ML / EL.

4.9 Leave During Notice Period
• Permitted: 1 day of leave during notice period (with prior Reporting Manager approval).
• CL / ML balance lapses upon resignation.
• Available EL can be encashed with Full & Final Settlement as per policy.
• Unapproved leave during notice period is treated as LOP.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

5. GRATUITY POLICY

• Minimum 5 years of continuous service required to qualify.
• Formula: (Basic Salary × 15 × Completed Years of Service) ÷ 30
• Payment processed within 30 days from the official relieving date.
• May be partially or fully forfeited in cases of termination due to disciplinary action, misconduct, or unauthorized exit.
• Five-year requirement waived in cases of death or permanent disability; amount paid to legal nominee or beneficiary.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

6. OPERATIONAL POLICY

6.1 Dress Code
General:
• Employees must be clean, neat, and well-groomed at all times.
• Clothing must be professional, modest, and appropriate.
• Casual, workout, or outdoor attire is not permitted.
• Revealing, tight, or inappropriate clothing is strictly prohibited.
• Clothing must be clean, pressed, and free from visible damage.
• Clothing with offensive, political, or inappropriate messages is not allowed.

Male Employees: Formal attire with formal shoes; neat and well-groomed appearance.
Female Employees: Formal Indian or Western wear; sarees / traditional attire must be formal, sober, and professional.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

7. SEPARATION POLICY

7.1 Resignation
• Voluntary separation; Reporting Manager must discuss reasons and explore retention.
• Resignation must be submitted in writing or email and forwarded to HR.
• CL / ML balance lapses upon resignation.

7.2 Notice Period
• Employees must serve the applicable notice period or pay salary in lieu of shortfall.
• The company may relieve an employee earlier based on business needs.

Notice Period Structure:
  Deputy General Manager & Above : 60 Days
  Jr. Executive to Senior Manager : 30 Days
  Probationers                    : 15 Days

7.3 Full & Final Settlement (F&F)
• Salary not released during notice period on the regular salary date.
• F&F processed within 3 days after exit.
• All company property must be returned and clearances completed.
• Deductions apply for loss or damage beyond normal wear and tear.
• Final settlement held until all dues are cleared.

7.4 Termination
• May occur due to non-performance, misconduct, unethical behaviour, or falsification of information.
• Termination authority rests with the Reporting Manager.
• Salary paid only for actual days worked up to the date of termination.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

8. WORKPLACE CONDUCT & SAFETY

8.1 Visitors on Office Premises
• All visitors must sign in and provide identification at reception.
• Visitors must be escorted at all times by an authorized employee.
• Visitors are not permitted in restricted zones without authorization.
• Employees allowing unauthorized entry face disciplinary action.
• Dangerous items (weapons, explosives, hazardous materials) are strictly prohibited.

8.2 Drug, Alcohol & Smoke-Free Workplace
• Possession or consumption of alcohol, tobacco, or illegal substances on company premises or during work hours is strictly prohibited.
• Violation will lead to disciplinary action, including possible termination.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

9. HARASSMENT & DISCRIMINATION POLICY

9.1 Harassment Policy
Prohibited behaviour includes: demeaning remarks, unwelcome sexual advances, sexist / racist / religious slurs, offensive jokes or gestures, actions that create a hostile work environment, verbal or physical innuendoes, comments about appearance or attire, circulating offensive content, unwanted physical proximity, and spreading malicious rumours.

9.2 Discrimination Policy
The company strictly prohibits discrimination based on: gender or sexual orientation, race, caste or community, religion or nationality, age or disability, or marital / family status.

Retaliation against any employee who files a complaint or participates in an investigation is strictly forbidden.

9.3 Reporting & Redressal
If you experience harassment:
1. Clearly communicate that the behaviour is unwelcome.
2. If it continues, report to the ICC or HR.
3. Maintain records of incidents where possible.
4. Submit a written complaint within 15 days.

HR will maintain a confidential register, meet the complainant within 5 working days, record allegations, collect evidence, and provide the accused an opportunity to respond. Enquiry follows standard disciplinary procedures. Findings are reviewed by HOD & HR.

9.4 Confidentiality
Confidential information (personnel data, financial reports, client information) must be handled securely and shared only with authorized personnel. Breach of confidentiality may result in disciplinary or legal action.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

10. VIOLATION POLICY

The following (not exhaustive) may lead to disciplinary action, including termination:
• Falsifying documents, records, or timesheets
• Using threatening, abusive, or coercive language
• Violating safety protocols
• Mistreating colleagues, clients, or vendors
• Unauthorized overtime or off-duty work
• Consumption of alcohol, drugs, or tobacco during work hours
• Insubordination or refusal to follow instructions
• Theft, fraud, or misuse of company property
• Repeated absenteeism, tardiness, or negligence

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This policy is subject to revision at the sole discretion of the management of Fomra Housing & Infrastructure Pvt Ltd. From the date of revision, the new policy becomes applicable.

For any queries, please reach out to the HR Department.

Prepared by: Jose Jenin Jeevi J, HR Manager
Verified by:  Ronak Surana, Head of Operations
Approved by: Sharad Fomra, CEO & MD
''';

  void _openSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttendanceSheet(
        record: _record,
        accentColor: widget.accentColor,
        attendanceRoute: widget.attendanceRoute,
        onDone: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final rec     = _record;
    final accent  = widget.accentColor;
    final hrBlue  = isDark ? Colors.blue.shade300 : AppTheme.primaryBlue;

    // Determine status visuals for the Check In/Out tile
    final IconData statusIcon;
    final Color    statusColor;
    final String   statusText; // full detail, shown as a tooltip
    final String   tileLabel;  // short, actionable label for the tile itself

    if (_loading) {
      statusIcon  = Icons.access_time_rounded;
      statusColor = accent;
      statusText  = 'Attendance';
      tileLabel   = 'Check In/Out';
    } else if (rec != null && rec.checkOutTime.isNotEmpty) {
      statusIcon  = Icons.check_circle_rounded;
      statusColor = isDark ? Colors.blue.shade300 : const Color(0xFF3B82F6);
      final dur   = _durationStr(rec);
      statusText  = 'Done · ${rec.checkInTime} – ${rec.checkOutTime}${dur != null ? ' ($dur)' : ''}';
      tileLabel   = 'Checked Out';
    } else if (rec != null && rec.checkInTime.isNotEmpty) {
      statusIcon  = Icons.check_circle_rounded;
      statusColor = isDark ? Colors.green.shade300 : const Color(0xFF22C55E);
      statusText  = 'Checked in at ${rec.checkInTime}';
      tileLabel   = 'Check Out';
    } else {
      statusIcon  = Icons.fingerprint_rounded;
      statusColor = accent;
      statusText  = 'Check In / Out';
      tileLabel   = 'Check In';
    }

    final tiles = <Widget>[
      // The CEO is outside attendance entirely — excluded from dashboards and
      // reports (v_attendance_tracked_employees) — so offering Check In/Out
      // would invite records that the rest of the system deliberately ignores.
      // Driven by the per-employee exemption rather than the role, so a future
      // exempt user is covered without another code change.
      if (!UserSession.exemptFromAttendance)
        Tooltip(
          message: statusText,
          child: _QuickTileView(
            icon: statusIcon,
            color: statusColor,
            label: tileLabel,
            loading: _loading,
            showLiveDot: !_loading && rec != null && rec.checkInTime.isNotEmpty && rec.checkOutTime.isEmpty,
            onTap: _loading ? null : _openSheet,
          ),
        ),
      _QuickTileView(
        icon: Icons.policy_rounded,
        color: hrBlue,
        label: 'HR Policy',
        onTap: _showHRPolicy,
      ),
      for (final t in widget.extraTiles)
        _QuickTileView(
          icon: t.icon,
          color: t.color,
          label: t.label,
          onTap: t.onTap ?? () => context.push(t.route!),
        ),
    ];

    Widget buildGrid(int cols) {
      final rows = <Widget>[];
      for (int i = 0; i < tiles.length; i += cols) {
        final end = (i + cols).clamp(0, tiles.length);
        final rowItems = tiles.sublist(i, end);
        rows.add(Row(children: [
          for (final w in rowItems) Expanded(child: w),
          for (int j = rowItems.length; j < cols; j++) const Expanded(child: SizedBox()),
        ]));
      }
      return Column(children: rows);
    }

    return InfoCard(
      icon: Icons.apps_rounded,
      title: widget.title,
      accentColor: AppTheme.primaryBlue,
      // Sizes to its own content — the enclosing MySpaceRow no longer
      // clamps every card to a fixed height, so nothing here needs to
      // scroll internally; the dashboard's outer scroll view handles it.
      child: widget.columns != null
          ? buildGrid(widget.columns!)
          : LayoutBuilder(builder: (context, constraints) {
              final cols = constraints.maxWidth > 420 ? 4 : 2;
              return buildGrid(cols);
            }),
    );
  }

  static String? _durationStr(AttendanceRecord rec) {
    try {
      final inP  = rec.checkInTime.split(':');
      final outP = rec.checkOutTime.split(':');
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
}

// ── A single Quick Access grid tile: icon-over-label with hover polish ───────
class _QuickTileView extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool showLiveDot;
  const _QuickTileView({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.showLiveDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(builder: (context, hovering) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: AppTheme.fastAnim,
            decoration: BoxDecoration(
              color: hovering ? color.withValues(alpha: 0.06) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedRotation(
                turns: hovering ? 0.04 : 0,
                duration: AppTheme.fastAnim,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: loading
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2, color: color),
                          )
                        : Icon(icon, color: color, size: 24),
                  ),
                  if (showLiveDot)
                    Positioned(
                      right: -2, top: -2,
                      child: Container(
                        width: 9, height: 9,
                        decoration: BoxDecoration(
                          color: Colors.green.shade400,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.white, width: 1.5),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 9.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            ]),
          ),
        ),
      );
    });
  }
}

// ── Help Center dialog (static reference info, no data fetching) ─────────────
void showHelpCenterDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (dlgCtx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.pink.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.support_agent_rounded, color: AppTheme.pink, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Help Center', style: AppTheme.cardHeading)),
            ]),
            const SizedBox(height: 16),
            const Text(
              "Need help with attendance, leave, payroll, or anything else on FOMRA HRMS? "
              "Reach out to the HR Department and we'll get back to you as soon as possible.",
              style: TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: const Text('Got it'),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ── HR Policy dialog ─────────────────────────────────────────────────────────
class _HRPolicyDialog extends StatefulWidget {
  final String approvedText;
  final Map<String, dynamic>? pendingVersion;
  final bool canEdit;        // true for HR
  final bool isManagement;   // true for Management
  const _HRPolicyDialog({
    required this.approvedText,
    required this.pendingVersion,
    required this.canEdit,
    required this.isManagement,
  });

  @override
  State<_HRPolicyDialog> createState() => _HRPolicyDialogState();
}

class _HRPolicyDialogState extends State<_HRPolicyDialog> {
  bool _editing   = false;
  bool _saving    = false;
  // When Management is previewing the pending version
  bool _previewPending = false;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.approvedText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submitForApproval() async {
    setState(() => _saving = true);
    try {
      await SupabaseService.submitHRPolicyForApproval(
          _ctrl.text, UserSession.name);
      if (!mounted) return;
      setState(() { _editing = false; _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Policy submitted to Management for approval.'),
          backgroundColor: AppTheme.accentBlue,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit: $e')),
      );
    }
  }

  String get _displayText =>
      _previewPending && widget.pendingVersion != null
          ? (widget.pendingVersion!['content'] as String? ?? '')
          : (_editing ? _ctrl.text : widget.approvedText);

  @override
  Widget build(BuildContext context) {
    final hasPending    = widget.pendingVersion != null;
    final pendingBy     = hasPending
        ? (widget.pendingVersion!['created_by'] as String? ?? 'HR')
        : '';
    final pendingVer    = hasPending
        ? 'v${widget.pendingVersion!['version_number'] ?? ''}'
        : '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Column(children: [
          // ── Header ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              const Icon(Icons.policy_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _previewPending
                      ? 'HR Policy – Pending ($pendingVer)'
                      : 'HR Policy',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
              if (widget.canEdit && !_editing && !hasPending)
                IconButton(
                  tooltip: 'Edit & submit for approval',
                  icon: const Icon(Icons.edit_rounded, color: Colors.white70, size: 20),
                  onPressed: () => setState(() => _editing = true),
                ),
              if (_editing)
                IconButton(
                  tooltip: 'Cancel edit',
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: () {
                    _ctrl.text = widget.approvedText;
                    setState(() => _editing = false);
                  },
                )
              else
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
            ]),
          ),

          // ── Pending approval banner ─────────────────────────────────────
          if (hasPending && !_editing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFFEF3C7),
              child: Row(children: [
                const Icon(Icons.pending_actions_rounded,
                    size: 16, color: Color(0xFFF57F17)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isManagement
                        ? '$pendingVer submitted by $pendingBy — awaiting your approval'
                        : '$pendingVer submitted by you — awaiting Management approval',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF7B4F00)),
                  ),
                ),
                if (widget.isManagement)
                  TextButton(
                    onPressed: () =>
                        setState(() => _previewPending = !_previewPending),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0)),
                    child: Text(
                      _previewPending ? 'View current' : 'Preview changes',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.accentBlue),
                    ),
                  ),
              ]),
            ),

          // ── Body ───────────────────────────────────────────────────────
          Expanded(
            child: _editing
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: _ctrl,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: 13, height: 1.6,
                          color: Color(0xFF6B7280)),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(
                      _displayText,
                      style: const TextStyle(fontSize: 13, height: 1.6,
                          color: Color(0xFF6B7280)),
                    ),
                  ),
          ),

          // ── Footer ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _editing
                ? Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () {
                          _ctrl.text = widget.approvedText;
                          setState(() => _editing = false);
                        },
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _submitForApproval,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Submit for Approval'),
                      ),
                    ),
                  ])
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ── Bottom-sheet popup ────────────────────────────────────────────────────────
class _AttendanceSheet extends StatefulWidget {
  final AttendanceRecord? record;
  final Color accentColor;
  final String attendanceRoute;
  final VoidCallback onDone;

  const _AttendanceSheet({
    required this.record,
    required this.accentColor,
    required this.attendanceRoute,
    required this.onDone,
  });

  @override
  State<_AttendanceSheet> createState() => _AttendanceSheetState();
}

class _AttendanceSheetState extends State<_AttendanceSheet> {
  static const _green = Color(0xFF22C55E);
  static const _teal  = Color(0xFF15803D);

  late final TextEditingController _timeCtrl;
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  // Minutes granted by a same-day approved Permission; 0 if none. See
  // checkin_status.dart's approvedPermissionMinutesFor.
  int _permissionMinutes = 0;

  @override
  void initState() {
    super.initState();
    _timeCtrl = TextEditingController(text: _nowTime());
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    final leaves = await SupabaseService.fetchLeaveApplications();
    if (!mounted) return;
    setState(() {
      _permissionMinutes =
          approvedPermissionMinutesFor(leaves, UserSession.name, DateTime.now());
    });
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _nowTime() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _checkIn() async {
    await ensureLocationConsent(context);
    if (!mounted) return;

    // This path did NO geofence evaluation at all, and never passed lat/lng to
    // saveCheckIn — it fetched the position, turned it into a display string,
    // and discarded the coordinates. That is why every attendance record has
    // null GPS and a null within-radius verdict, and why an employee could
    // check in from anywhere through the dashboard without being asked for a
    // reason. The configured geofences were bypassed by the most convenient
    // button in the app.
    final loc = await resolveCheckInLocation();
    if (!mounted) return;
    if (await promptForLocationReason(context, loc,
        noteIsEmpty: _noteCtrl.text.trim().isEmpty)) {
      return;
    }
    if (!mounted) return;

    if (isLateCheckIn(_timeCtrl.text, OfficeTimingStore.scheduleForCurrentUser()) &&
        _permissionMinutes == 0 &&
        _noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please add a reason for checking in late.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    setState(() => _submitting = true);
    final now = DateTime.now();
    final empName = UserSession.name.isNotEmpty ? UserSession.name : 'Employee';

    final selfiePath = !selfieRequiredForCurrentUser
        ? ''   // Management: no selfie required
        : await SelfieCaptureService.captureAndUpload(
      employeeId: UserSession.employeeId,
      date: _fmtDate(now),
      kind: 'checkin',
      label: 'Check-In',
    );
    if (!mounted) return;
    if (selfiePath == null && selfieRequiredForCurrentUser) {
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

    final err = await SupabaseService.saveCheckIn(
      employeeName: empName,
      employeeId:   UserSession.employeeId,
      date:         _fmtDate(now),
      time:         _timeCtrl.text,
      location:     loc.position != null
          ? '${loc.position!.latitude},${loc.position!.longitude}'
          : '',
      note:         _noteCtrl.text.trim(),
      selfiePath:   selfiePath ?? '',
      // Previously omitted entirely, so the coordinates were fetched and
      // thrown away.
      lat:          loc.lat,
      lng:          loc.lng,
      withinRadius: loc.withinRadius,
      accuracy:     loc.accuracy,
      policyName:   loc.policyName,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sync error: $err'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    } else {
      widget.onDone();
      NotificationService.checkInRecorded(
        employeeEmail: UserSession.email,
        time: _timeCtrl.text,
        employeeRoutePrefix: NotificationService.routePrefixForRole(UserSession.role),
      );
      NotificationService.notifyIfLateCheckIn(
        employeeName: empName,
        checkInTime: _timeCtrl.text,
        date: now,
        schedule: OfficeTimingStore.scheduleForCurrentUser(),
      );
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Checked in at ${_timeCtrl.text}'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
    }
  }

  Future<void> _checkOut() async {
    if (isEarlyCheckOut(_timeCtrl.text,
            OfficeTimingStore.scheduleForCurrentUser(), _permissionMinutes) &&
        _noteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please add a reason for checking out early.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ));
      return;
    }

    setState(() => _submitting = true);
    final now = DateTime.now();

    final selfiePath = !selfieRequiredForCurrentUser
        ? ''   // Management: no selfie required
        : await SelfieCaptureService.captureAndUpload(
      employeeId: UserSession.employeeId,
      date: _fmtDate(now),
      kind: 'checkout',
      label: 'Check-Out',
    );
    if (!mounted) return;
    if (selfiePath == null && selfieRequiredForCurrentUser) {
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

    await SupabaseService.saveCheckOut(
      employeeId:  UserSession.employeeId,
      date:        _fmtDate(now),
      time:        _timeCtrl.text,
      note:        _noteCtrl.text.trim(),
      selfiePath:  selfiePath ?? '',
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    widget.onDone();
    NotificationService.checkOutRecorded(
      employeeEmail: UserSession.email,
      time: _timeCtrl.text,
      employeeRoutePrefix: NotificationService.routePrefixForRole(UserSession.role),
    );
    if (mounted) Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Checked out at ${_timeCtrl.text}'),
      backgroundColor: _teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final cs      = Theme.of(context).colorScheme;
    final rec     = widget.record;
    final accent  = widget.accentColor;

    final isCheckedIn = rec != null && rec.checkInTime.isNotEmpty && rec.checkOutTime.isEmpty;
    final isDone      = rec != null && rec.checkOutTime.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Drag handle
        const SizedBox(height: 12),
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),

        // Header
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.access_time_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Text('Attendance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const Spacer(),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go(widget.attendanceRoute);
            },
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('View Details', style: TextStyle(fontSize: 12, color: accent,
                  fontWeight: FontWeight.w600)),
              const SizedBox(width: 2),
              Icon(Icons.arrow_forward_ios_rounded, size: 10, color: accent),
            ]),
          ),
        ]),
        const SizedBox(height: 20),

        // Status banner
        if (isDone) ...[
          _doneBanner(rec, isDark),
          const SizedBox(height: 16),
        ] else if (isCheckedIn) ...[
          _statusBanner(
            icon: Icons.check_circle_rounded,
            text: 'Checked in at ${rec.checkInTime}',
            fg: isDark ? Colors.green.shade300 : _green,
            bg: isDark ? Colors.green.withValues(alpha: 0.12) : Colors.green.shade50,
            border: isDark ? Colors.green.shade700 : Colors.green.shade200,
          ),
          const SizedBox(height: 16),
        ] else ...[
          _statusBanner(
            icon: Icons.schedule_rounded,
            text: "Not checked in yet today",
            fg: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
            bg: isDark ? Colors.orange.withValues(alpha: 0.12) : Colors.orange.shade50,
            border: isDark ? Colors.orange.shade700 : Colors.orange.shade200,
          ),
          const SizedBox(height: 16),
        ],

        // Time field (hide when done)
        if (!isDone) ...[
          ListenableBuilder(
            listenable: _timeCtrl,
            builder: (context, _) {
              final schedule = OfficeTimingStore.scheduleForCurrentUser();
              final showNote = isCheckedIn
                  ? isEarlyCheckOut(_timeCtrl.text, schedule, _permissionMinutes)
                  : (isLateCheckIn(_timeCtrl.text, schedule) && _permissionMinutes == 0);
              return Column(children: [
                TextField(
                  controller: _timeCtrl,
                  // System clock only. This field previously opened a
                  // datetime keyboard, actively inviting the employee to
                  // type a time — which is how unparseable values like
                  // "12 pm" reached the attendance table and, from there,
                  // the lateness maths behind payroll.
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: isCheckedIn ? 'Check-Out Time' : 'Check-In Time',
                    prefixIcon: Icon(
                      isCheckedIn ? Icons.logout_rounded : Icons.login_rounded,
                      color: isCheckedIn ? _teal : accent,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Use current time',
                      icon: Icon(Icons.schedule_rounded,
                          color: isCheckedIn ? _teal : accent),
                      onPressed: () => setState(() => _timeCtrl.text = _nowTime()),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isCheckedIn ? _teal : accent, width: 2),
                    ),
                    filled: true,
                    fillColor: cs.surface,
                  ),
                ),
                if (showNote) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: isCheckedIn
                          ? 'Reason for early check-out (required)'
                          : 'Reason for late check-in (required)',
                      hintText: isCheckedIn
                          ? 'e.g. left early for client meeting'
                          : 'e.g. traffic delay, doctor appointment',
                      prefixIcon: Icon(Icons.edit_note_rounded,
                          color: isCheckedIn ? _teal : accent, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: isCheckedIn ? _teal : accent, width: 2),
                      ),
                      filled: true,
                      fillColor: cs.surface,
                    ),
                  ),
                ],
              ]);
            },
          ),
          const SizedBox(height: 16),

          // Action button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : (isCheckedIn ? _checkOut : _checkIn),
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(isCheckedIn ? Icons.logout_rounded : Icons.login_rounded, size: 18),
              label: Text(isCheckedIn ? 'Check Out' : 'Check In',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: isCheckedIn ? _teal : accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _statusBanner({
    required IconData icon,
    required String text,
    required Color fg,
    required Color bg,
    required Color border,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Icon(icon, size: 15, color: fg),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _doneBanner(AttendanceRecord rec, bool isDark) {
    final dur  = _AttendanceShortcutCardState._durationStr(rec);
    final blue = isDark ? Colors.blue.shade300 : const Color(0xFF3B82F6);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2563EB).withValues(alpha: 0.12) : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.blue.shade700 : Colors.blue.shade200),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_rounded, size: 14, color: blue),
          const SizedBox(width: 6),
          Text('Attendance Complete',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: blue)),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _timeBlock('Check In',  rec.checkInTime,  blue),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: blue),
          ),
          _timeBlock('Check Out', rec.checkOutTime, blue),
        ]),
        if (dur != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.blue.withValues(alpha: 0.2) : Colors.blue.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(dur,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: blue)),
          ),
        ],
        if (rec.checkInNote.isNotEmpty || rec.checkOutNote.isNotEmpty) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (rec.checkInNote.isNotEmpty)
                Text('Check-in note: ${rec.checkInNote}',
                    style: TextStyle(fontSize: 11, color: blue)),
              if (rec.checkOutNote.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Check-out note: ${rec.checkOutNote}',
                    style: TextStyle(fontSize: 11, color: blue)),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _timeBlock(String label, String time, Color color) {
    return Column(children: [
      Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
      const SizedBox(height: 2),
      Text(time, style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800,
          fontFamily: 'monospace', color: color)),
    ]);
  }
}
