import 'dart:convert';

enum PayslipRequestStatus { pending, approved, rejected }

class PayslipRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String monthYear; // 'YYYY-MM'
  PayslipRequestStatus status;
  final DateTime requestedAt;
  DateTime? decidedAt;
  String decidedBy;
  String rejectionComment;

  PayslipRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.monthYear,
    this.status = PayslipRequestStatus.pending,
    required this.requestedAt,
    this.decidedAt,
    this.decidedBy = '',
    this.rejectionComment = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'month_year': monthYear,
        'status': status.name,
        'requested_at': requestedAt.toIso8601String(),
        'decided_at': decidedAt?.toIso8601String(),
        'decided_by': decidedBy,
        'rejection_comment': rejectionComment,
      };

  factory PayslipRequest.fromJson(Map<String, dynamic> j) => PayslipRequest(
        id: (j['id'] as String?) ?? '',
        employeeId: (j['employee_id'] as String?) ?? '',
        employeeName: (j['employee_name'] as String?) ?? '',
        monthYear: (j['month_year'] as String?) ?? '',
        status: PayslipRequestStatus.values.firstWhere(
          (s) => s.name == (j['status'] as String?),
          orElse: () => PayslipRequestStatus.pending,
        ),
        requestedAt: DateTime.tryParse((j['requested_at'] as String?) ?? '') ??
            DateTime.now(),
        decidedAt: j['decided_at'] != null
            ? DateTime.tryParse(j['decided_at'] as String)
            : null,
        decidedBy: (j['decided_by'] as String?) ?? '',
        rejectionComment: (j['rejection_comment'] as String?) ?? '',
      );
}

class LeaveDetailRow {
  final String type;
  final double opening;
  final double taken;
  const LeaveDetailRow({required this.type, required this.opening, required this.taken});

  double get closing => (opening - taken).clamp(0, double.infinity);

  Map<String, dynamic> toJson() =>
      {'type': type, 'opening': opening, 'taken': taken};

  factory LeaveDetailRow.fromJson(Map<String, dynamic> j) => LeaveDetailRow(
        type: (j['type'] as String?) ?? '',
        opening: (j['opening'] as num?)?.toDouble() ?? 0,
        taken: (j['taken'] as num?)?.toDouble() ?? 0,
      );
}

class Payslip {
  final String id;
  final String employeeId;
  final String monthYear; // 'YYYY-MM'
  final String empName;
  final String department;
  final String designation;
  final String band;
  final String dateOfJoining;
  final int workingDays;
  /// Fractional: 2.5 days of LOP is a real outcome and has to be storable.
  final double daysWorked;
  final double lopDays;
  final double grossPay;

  final double basic;
  /// Dearness allowance. Absent from the payslip until November 2026, which
  /// left every stored payslip short of the salary on the employee record.
  final double da;
  final double hra;
  final double educationalAllowance;
  final double lta;
  final double otherAllowance;
  final double conveyanceAllowance;
  final double specialAllowance;

  final double epf;
  final double esi;
  final double professionalTax;
  final double tds;
  final double lateDeductions;
  final double excessLeaveDeduction;
  final double cug;

  final List<LeaveDetailRow> leaveDetails;
  final DateTime generatedAt;
  final String generatedBy;

  // ── Issued by the database (issue_payslips, from Nov 2026) ──────────────
  // A payslip issued from the payroll engine carries the engine's own
  // totals. Shown as issued rather than re-added from the lines: each line
  // is rounded to the paisa, so the lines can differ from the total by a few
  // paise, and net pay is rounded to the rupee.
  /// 'draft' (HR has not published it; the employee cannot see it) or
  /// 'published'.
  final String status;
  /// 'engine' when issued by the database; 'app' for the older payslips the
  /// app calculated itself.
  final String source;
  final int version;
  final double? grossEarned;
  final double? totalDeductionsIssued;
  final double? netPayIssued;
  final double roundedOff;
  final DateTime? cycleStart;
  final DateTime? cycleEnd;
  final int? attendanceWorkingDays;
  final int? daysPresent;
  final double? clUsed;
  final double? mlUsed;
  final double? elUsed;
  final double? compOffUsed;
  final double? lopLeave;
  /// The unpaid part of approved leave.
  final double? leaveLop;
  final int? permissionCount;
  final int? permissionMinutes;
  final int? lateCount;
  final double? lateLop;
  final double? permissionLop;

  const Payslip({
    required this.id,
    required this.employeeId,
    required this.monthYear,
    required this.empName,
    required this.department,
    required this.designation,
    this.band = '',
    required this.dateOfJoining,
    required this.workingDays,
    required this.daysWorked,
    required this.lopDays,
    required this.grossPay,
    required this.basic,
    this.da = 0,
    required this.hra,
    required this.educationalAllowance,
    required this.lta,
    required this.otherAllowance,
    required this.conveyanceAllowance,
    this.specialAllowance = 0,
    required this.epf,
    this.esi = 0,
    required this.professionalTax,
    required this.tds,
    required this.lateDeductions,
    this.excessLeaveDeduction = 0,
    this.cug = 0,
    this.leaveDetails = const [],
    required this.generatedAt,
    this.generatedBy = '',
    this.status = 'published',
    this.source = 'app',
    this.version = 1,
    this.grossEarned,
    this.totalDeductionsIssued,
    this.netPayIssued,
    this.roundedOff = 0,
    this.cycleStart,
    this.cycleEnd,
    this.attendanceWorkingDays,
    this.daysPresent,
    this.clUsed,
    this.mlUsed,
    this.elUsed,
    this.compOffUsed,
    this.lopLeave,
    this.leaveLop,
    this.permissionCount,
    this.permissionMinutes,
    this.lateCount,
    this.lateLop,
    this.permissionLop,
  });

  bool get isFromEngine => source == 'engine';
  bool get isDraft => status == 'draft';

  /// 30 -> "30", 27.5 -> "27.5".
  static String fmtDays(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  double get actualGrossPay =>
      grossEarned ??
      (basic + da + hra + educationalAllowance + lta + otherAllowance +
          conveyanceAllowance + specialAllowance);

  double get totalDeductions =>
      totalDeductionsIssued ??
      (epf + esi + professionalTax + tds + lateDeductions + excessLeaveDeduction + cug);

  /// As issued (rounded to the rupee) when the database issued it.
  double get netPay => netPayIssued ?? (actualGrossPay - totalDeductions);

  Map<String, dynamic> toJson() => {
        'id': id,
        'employee_id': employeeId,
        'month_year': monthYear,
        'emp_name': empName,
        'department': department,
        'designation': designation,
        'band': band,
        'date_of_joining': dateOfJoining,
        'working_days': workingDays,
        'days_worked': daysWorked,
        'lop_days': lopDays,
        'gross_pay': grossPay,
        'basic': basic,
        'da': da,
        'hra': hra,
        'educational_allowance': educationalAllowance,
        'lta': lta,
        'other_allowance': otherAllowance,
        'conveyance_allowance': conveyanceAllowance,
        'special_allowance': specialAllowance,
        'epf': epf,
        'esi': esi,
        'professional_tax': professionalTax,
        'tds': tds,
        'late_deductions': lateDeductions,
        'excess_leave_deduction': excessLeaveDeduction,
        'cug': cug,
        'leave_details': jsonEncode(leaveDetails.map((r) => r.toJson()).toList()),
        'generated_at': generatedAt.toIso8601String(),
        'generated_by': generatedBy,
      };

  factory Payslip.fromJson(Map<String, dynamic> j) {
    List<LeaveDetailRow> parseLeave(dynamic v) {
      if (v == null) return [];
      try {
        final decoded = v is String ? jsonDecode(v) : v;
        if (decoded is List) {
          return decoded
              .map((e) => LeaveDetailRow.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      } catch (_) {}
      return [];
    }

    // payslips' salary-component columns are Postgres `numeric`, which
    // PostgREST serializes as a JSON string rather than a number — `as
    // num?` throws on that (see SupabaseService._numFromJson for the same
    // fix applied to app_users.gross_pay).
    double numOf(String key) {
      final v = j[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0;
      return 0;
    }
    double? numOrNull(String key) {
      final v = j[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }
    int? intOrNull(String key) => numOrNull(key)?.round();
    DateTime? dateOrNull(String key) => DateTime.tryParse((j[key] as String?) ?? '');

    return Payslip(
      id: (j['id'] as String?) ?? '',
      employeeId: (j['employee_id'] as String?) ?? '',
      monthYear: (j['month_year'] as String?) ?? '',
      empName: (j['emp_name'] as String?) ?? '',
      department: (j['department'] as String?) ?? '',
      designation: (j['designation'] as String?) ?? '',
      band: (j['band'] as String?) ?? '',
      dateOfJoining: (j['date_of_joining'] as String?) ?? '',
      workingDays: (j['working_days'] as num?)?.toInt() ?? 0,
      daysWorked: numOf('days_worked'),
      lopDays: numOf('lop_days'),
      grossPay: numOf('gross_pay'),
      basic: numOf('basic'),
      da: numOf('da'),
      hra: numOf('hra'),
      educationalAllowance: numOf('educational_allowance'),
      lta: numOf('lta'),
      otherAllowance: numOf('other_allowance'),
      conveyanceAllowance: numOf('conveyance_allowance'),
      specialAllowance: numOf('special_allowance'),
      epf: numOf('epf'),
      esi: numOf('esi'),
      professionalTax: numOf('professional_tax'),
      tds: numOf('tds'),
      lateDeductions: numOf('late_deductions'),
      excessLeaveDeduction: numOf('excess_leave_deduction'),
      cug: numOf('cug'),
      leaveDetails: parseLeave(j['leave_details']),
      generatedAt: DateTime.tryParse((j['generated_at'] as String?) ?? '') ??
          DateTime.now(),
      generatedBy: (j['generated_by'] as String?) ?? '',
      status: (j['status'] as String?) ?? 'published',
      source: (j['source'] as String?) ?? 'app',
      version: intOrNull('version') ?? 1,
      grossEarned: numOrNull('gross_earned'),
      totalDeductionsIssued: numOrNull('total_deductions'),
      netPayIssued: numOrNull('net_pay'),
      roundedOff: numOrNull('rounded_off') ?? 0,
      cycleStart: dateOrNull('cycle_start'),
      cycleEnd: dateOrNull('cycle_end'),
      attendanceWorkingDays: intOrNull('attendance_working_days'),
      daysPresent: intOrNull('days_present'),
      clUsed: numOrNull('cl_used'),
      mlUsed: numOrNull('ml_used'),
      elUsed: numOrNull('el_used'),
      compOffUsed: numOrNull('comp_off_used'),
      lopLeave: numOrNull('lop_leave'),
      leaveLop: numOrNull('leave_lop'),
      permissionCount: intOrNull('permission_count'),
      permissionMinutes: intOrNull('permission_minutes'),
      lateCount: intOrNull('late_count'),
      lateLop: numOrNull('late_lop'),
      permissionLop: numOrNull('permission_lop'),
    );
  }
}

/// A selectable option for a dropdown-driven payslip line — either a
/// percentage of Gross Pay/Basic, or a flat amount.
class PayOption {
  final String label;
  final double? percentOfGross;
  final double? percentOfBasic;
  final double? fixedAmount;
  const PayOption({required this.label, this.percentOfGross, this.percentOfBasic, this.fixedAmount});

  double amount(double grossPay, double basic) {
    if (fixedAmount != null) return fixedAmount!;
    if (percentOfBasic != null) return basic * percentOfBasic! / 100;
    if (percentOfGross != null) return grossPay * percentOfGross! / 100;
    return 0;
  }
}

/// Preset dropdown options + calculation rules for each payslip line item.
class PayslipCalc {
  static const basicOptions = [
    PayOption(label: '40% of Gross', percentOfGross: 40),
    PayOption(label: '45% of Gross', percentOfGross: 45),
    PayOption(label: '50% of Gross', percentOfGross: 50),
  ];
  static const defaultBasicIndex = 2; // 50%

  static const educationalOptions = [
    PayOption(label: 'Fixed ₹200', fixedAmount: 200),
    PayOption(label: '1% of Gross', percentOfGross: 1),
    PayOption(label: '2% of Gross', percentOfGross: 2),
  ];
  static const defaultEducationalIndex = 0; // fixed 200

  static const ltaOptions = [
    PayOption(label: '5% of Gross', percentOfGross: 5),
    PayOption(label: '7% of Gross', percentOfGross: 7),
    PayOption(label: '10% of Gross', percentOfGross: 10),
  ];
  static const defaultLtaIndex = 0; // 5%

  static const conveyanceOptions = [
    PayOption(label: '3% of Gross', percentOfGross: 3),
    PayOption(label: '4% of Gross', percentOfGross: 4),
    PayOption(label: '5% of Gross', percentOfGross: 5),
  ];
  static const defaultConveyanceIndex = 0; // 3%

  // Fixed, non-editable rules
  static double hra(double basic) => basic * 0.5;
  static double otherAllowance(double grossPay) => grossPay * 0.02;
  static const double epf = 1800;
  static const double professionalTax = 208;

  static bool tdsApplicable(double monthlyGrossPay) => monthlyGrossPay * 12 >= 1200000;
  static double tds(double monthlyGrossPay) =>
      tdsApplicable(monthlyGrossPay) ? monthlyGrossPay * 0.10 : 0;

  /// One day's pay = Gross Pay ÷ calendar days in the month.
  static double oneDaySalary({required double grossPay, required int daysInMonth}) =>
      daysInMonth <= 0 ? 0 : grossPay / daysInMonth;

  /// Late arrivals within the grace window (09:31–09:41, see
  /// [isGraceLate] in checkin_status.dart) are excused this many times a
  /// month; beyond that, and every arrival after 09:41 ([isSevereLate])
  /// with no exceptions, costs half a day's pay each.
  static const int lateGraceExcuses = 3;

  static double lateDeduction({
    required double grossPay,
    required int daysInMonth,
    required int graceLateDays,
    required int severeLateDays,
  }) {
    final chargeableGrace = (graceLateDays - lateGraceExcuses).clamp(0, graceLateDays);
    final chargeable = chargeableGrace + severeLateDays;
    if (chargeable <= 0) return 0;
    return oneDaySalary(grossPay: grossPay, daysInMonth: daysInMonth) * 0.5 * chargeable;
  }

  /// Deduction for CL/ML/EL days taken beyond the employee's balance for the
  /// month, at a full day's pay each.
  static double excessLeaveDeduction({
    required double grossPay,
    required int daysInMonth,
    required double excessDays,
  }) {
    if (excessDays <= 0) return 0;
    return oneDaySalary(grossPay: grossPay, daysInMonth: daysInMonth) * excessDays;
  }
}
