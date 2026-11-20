import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads and acts on the App Health data: consistency-check findings, the
/// app error log and problem reports. Reads are limited to HR and
/// Management by RLS; every change goes through a database function that
/// checks the caller again.
class AppHealthService {
  AppHealthService._();

  static SupabaseClient get _db => Supabase.instance.client;

  static List<Map<String, dynamic>> _rows(dynamic data) => [
        for (final r in (data as List)) Map<String, dynamic>.from(r as Map),
      ];

  /// The most recent consistency-check run, or null if none has run.
  static Future<Map<String, dynamic>?> latestRun() async {
    final data = await _db
        .from('integrity_check_runs')
        .select()
        .order('started_at', ascending: false)
        .limit(1);
    final rows = _rows(data);
    return rows.isEmpty ? null : rows.first;
  }

  /// [state] is 'open', 'acknowledged' or 'resolved'.
  static Future<List<Map<String, dynamic>>> findings(String state) async {
    var q = _db.from('integrity_findings').select();
    switch (state) {
      case 'open':
        q = q.isFilter('resolved_at', null).isFilter('acknowledged_at', null);
      case 'acknowledged':
        q = q.isFilter('resolved_at', null).not('acknowledged_at', 'is', null);
      case 'resolved':
        q = q.not('resolved_at', 'is', null);
    }
    final data = await q.order('last_seen_at', ascending: false).limit(500);
    final rows = _rows(data);
    const rank = {'high': 0, 'medium': 1, 'low': 2};
    rows.sort((a, b) =>
        (rank[a['severity']] ?? 3).compareTo(rank[b['severity']] ?? 3));
    return rows;
  }

  /// Runs the checks now. Returns the run summary.
  static Future<Map<String, dynamic>> runChecksNow() async {
    final data = await _db.rpc('run_integrity_checks', params: {'p_trigger': 'manual'});
    final rows = _rows(data);
    return rows.isEmpty ? <String, dynamic>{} : rows.first;
  }

  static Future<void> acknowledgeFinding(int id, {required bool acknowledge, String? note}) =>
      _db.rpc('acknowledge_integrity_finding', params: {
        'p_id': id,
        'p_acknowledge': acknowledge,
        'p_note': note,
      });

  /// [reports] picks problem reports; otherwise crashes, errors and failed
  /// writes. [status] is 'open', 'resolved' or 'all'.
  static Future<List<Map<String, dynamic>>> issues({
    required bool reports,
    required String status,
  }) async {
    var q = _db.from('app_error_logs').select();
    q = reports ? q.eq('kind', 'report') : q.neq('kind', 'report');
    if (status != 'all') q = q.eq('status', status);
    final data = await q.order('occurred_at', ascending: false).limit(300);
    return _rows(data);
  }

  static Future<void> resolveIssue(int id, {required bool resolved, String? note}) =>
      _db.rpc('resolve_app_issue', params: {
        'p_id': id,
        'p_resolved': resolved,
        'p_note': note,
      });

  static Future<String?> screenshotUrl(String path) async {
    try {
      return await _db.storage.from('problem-reports').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }
}
