import 'package:supabase_flutter/supabase_flutter.dart';

/// An employee's exit: last working day, Management's decisions, and the
/// Full & Final settlement. Rules agreed 25 Nov 2026 (HRMS project doc
/// "Employee exit, last working day and Full & Final settlement"); the
/// database enforces them in record_exit / approve_exit / fnf_statement.
class EmployeeExit {
  final String id;
  final String employeeId;
  final String employeeName;
  final String exitType; // resigned / terminated / absconded / other
  final DateTime? resignationDate;
  final DateTime lastWorkingDay;
  final String reason;
  final int noticeDaysRequired;
  final bool noticeWaived;
  final String finalSalary; // pay / hold / withhold / settled
  final String fnf; // pay / hold / forfeit
  final String status; // pending / approved / rejected / cancelled
  final String requestedBy;
  final DateTime? requestedAt;
  final String decidedBy;
  final DateTime? decidedAt;
  final String decisionNote;
  final DateTime? accountClosedAt;
  final String fnfStatus; // draft / approved / paid
  final double? fnfTotal;
  final DateTime? fnfPaidAt;
  final String fnfPaymentNote;

  const EmployeeExit({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.exitType,
    required this.resignationDate,
    required this.lastWorkingDay,
    required this.reason,
    required this.noticeDaysRequired,
    required this.noticeWaived,
    required this.finalSalary,
    required this.fnf,
    required this.status,
    required this.requestedBy,
    required this.requestedAt,
    required this.decidedBy,
    required this.decidedAt,
    required this.decisionNote,
    required this.accountClosedAt,
    required this.fnfStatus,
    required this.fnfTotal,
    required this.fnfPaidAt,
    required this.fnfPaymentNote,
  });

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  factory EmployeeExit.fromMap(Map<String, dynamic> m) => EmployeeExit(
        id: m['id'].toString(),
        employeeId: (m['employee_id'] as String?) ?? '',
        employeeName: (m['employee_name'] as String?) ?? '',
        exitType: (m['exit_type'] as String?) ?? 'other',
        resignationDate: _date(m['resignation_date']),
        lastWorkingDay: _date(m['last_working_day']) ?? DateTime.now(),
        reason: (m['reason'] as String?) ?? '',
        noticeDaysRequired: (m['notice_days_required'] as num?)?.toInt() ?? 0,
        noticeWaived: (m['notice_waived'] as bool?) ?? false,
        finalSalary: (m['final_salary'] as String?) ?? 'pay',
        fnf: (m['fnf'] as String?) ?? 'pay',
        status: (m['status'] as String?) ?? 'pending',
        requestedBy: (m['requested_by'] as String?) ?? '',
        requestedAt: _date(m['requested_at']),
        decidedBy: (m['decided_by'] as String?) ?? '',
        decidedAt: _date(m['decided_at']),
        decisionNote: (m['decision_note'] as String?) ?? '',
        accountClosedAt: _date(m['account_closed_at']),
        fnfStatus: (m['fnf_status'] as String?) ?? 'draft',
        fnfTotal: (m['fnf_total'] as num?)?.toDouble(),
        fnfPaidAt: _date(m['fnf_paid_at']),
        fnfPaymentNote: (m['fnf_payment_note'] as String?) ?? '',
      );

  bool get isOpen => status == 'pending' || status == 'approved';

  /// Days of notice actually given (resignation date to last working day).
  int? get noticeServed => resignationDate == null
      ? null
      : DateTime(lastWorkingDay.year, lastWorkingDay.month, lastWorkingDay.day)
              .difference(DateTime(resignationDate!.year, resignationDate!.month,
                  resignationDate!.day))
              .inDays +
          1;

  /// Same rule as exit_notice_short() in the database.
  int noticeShortWith({required bool waived}) {
    if (exitType != 'resigned' || waived || noticeServed == null) return 0;
    final s = noticeDaysRequired - noticeServed!;
    return s > 0 ? s : 0;
  }

  int get noticeShort => noticeShortWith(waived: noticeWaived);

  String get typeLabel => exitTypeLabels[exitType] ?? exitType;

  static const exitTypeLabels = {
    'resigned': 'Resigned',
    'terminated': 'Terminated',
    'absconded': 'Absconded',
    'other': 'Other',
  };

  static const finalSalaryLabels = {
    'pay': 'Paid in payroll',
    'hold': 'On hold',
    'withhold': 'Withheld',
    'settled': 'Settled outside the app',
  };

  static const fnfLabels = {
    'pay': 'To be paid',
    'hold': 'On hold',
    'forfeit': 'Not eligible',
  };
}

/// One line of the F&F statement, as fnf_statement() returns it.
class FnfLine {
  final int sort;
  final String kind; // earning / deduction / info / total
  final String label;
  final double amount;
  final String note;
  const FnfLine(this.sort, this.kind, this.label, this.amount, this.note);

  factory FnfLine.fromMap(Map<String, dynamic> m) => FnfLine(
        (m['sort'] as num?)?.toInt() ?? 0,
        (m['kind'] as String?) ?? '',
        (m['label'] as String?) ?? '',
        (m['amount'] as num?)?.toDouble() ?? 0,
        (m['note'] as String?) ?? '',
      );
}

/// An extra F&F line HR added (property recovery, advance, bonus, ...).
class FnfItem {
  final String id;
  final String label;
  final double amount;
  final String note;
  const FnfItem(this.id, this.label, this.amount, this.note);
}

class ExitService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// The database raises plain-language messages; show those.
  static String message(Object e) {
    if (e is PostgrestException) {
      final m = e.message.trim();
      if (m.isNotEmpty) return m;
    }
    return 'Something went wrong. Please try again.';
  }

  static Future<List<EmployeeExit>> fetchExits({String? employeeId}) async {
    var q = _db.from('employee_exits').select();
    if (employeeId != null) q = q.eq('employee_id', employeeId);
    final rows = await q.order('requested_at', ascending: false);
    return (rows as List)
        .map((r) => EmployeeExit.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The open exit for an employee (waiting for approval, or approved), or
  /// the most recent closed one if there is no open one.
  static Future<EmployeeExit?> fetchLatestFor(String employeeId) async {
    final all = await fetchExits(employeeId: employeeId);
    if (all.isEmpty) return null;
    final open = all.where((x) => x.isOpen).toList();
    return open.isNotEmpty ? open.first : all.first;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Future<String?> recordExit({
    required String employeeId,
    required String exitType,
    DateTime? resignationDate,
    required DateTime lastWorkingDay,
    required String reason,
    int? noticeDays,
  }) async {
    try {
      await _db.rpc('record_exit', params: {
        'p_employee_id': employeeId,
        'p_exit_type': exitType,
        'p_resignation_date': resignationDate == null ? null : _iso(resignationDate),
        'p_last_working_day': _iso(lastWorkingDay),
        'p_reason': reason,
        'p_notice_days': noticeDays,
      });
      return null;
    } catch (e) {
      return message(e);
    }
  }

  static Future<String?> approveExit(
    String exitId, {
    bool? noticeWaived,
    String? finalSalary,
    String? fnf,
    String? note,
  }) async {
    try {
      await _db.rpc('approve_exit', params: {
        'p_exit_id': exitId,
        'p_notice_waived': noticeWaived,
        'p_final_salary': finalSalary,
        'p_fnf': fnf,
        'p_note': note,
      });
      return null;
    } catch (e) {
      return message(e);
    }
  }

  static Future<String?> rejectExit(String exitId, String note) async {
    try {
      await _db.rpc('reject_exit', params: {'p_exit_id': exitId, 'p_note': note});
      return null;
    } catch (e) {
      return message(e);
    }
  }

  static Future<String?> cancelExit(String exitId, String note) async {
    try {
      await _db.rpc('cancel_exit', params: {'p_exit_id': exitId, 'p_note': note});
      return null;
    } catch (e) {
      return message(e);
    }
  }

  static Future<List<FnfLine>> fnfStatement(String exitId) async {
    final rows = await _db.rpc('fnf_statement', params: {'p_exit_id': exitId});
    final list = (rows as List)
        .map((r) => FnfLine.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
    list.sort((a, b) => a.sort.compareTo(b.sort));
    return list;
  }

  static Future<List<FnfItem>> fnfItems(String exitId) async {
    final rows = await _db
        .from('exit_fnf_items')
        .select('id, label, amount, note')
        .eq('exit_id', exitId)
        .eq('voided', false)
        .order('added_at');
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return FnfItem(m['id'].toString(), (m['label'] as String?) ?? '',
          (m['amount'] as num?)?.toDouble() ?? 0, (m['note'] as String?) ?? '');
    }).toList();
  }

  static Future<String?> addFnfItem(
      String exitId, String label, double amount, String note) async {
    try {
      await _db.rpc('add_fnf_item', params: {
        'p_exit_id': exitId,
        'p_label': label,
        'p_amount': amount,
        'p_note': note,
      });
      return null;
    } catch (e) {
      return message(e);
    }
  }

  static Future<String?> voidFnfItem(String itemId) async {
    try {
      await _db.rpc('void_fnf_item', params: {'p_item_id': itemId});
      return null;
    } catch (e) {
      return message(e);
    }
  }

  static Future<String?> approveFnf(String exitId) async {
    try {
      await _db.rpc('approve_fnf', params: {'p_exit_id': exitId});
      return null;
    } catch (e) {
      return message(e);
    }
  }

  static Future<String?> markFnfPaid(String exitId, String note) async {
    try {
      await _db.rpc('mark_fnf_paid', params: {'p_exit_id': exitId, 'p_note': note});
      return null;
    } catch (e) {
      return message(e);
    }
  }
}
