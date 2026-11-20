class LeaveFormConfig {
  // In-memory cache so all three apply pages share one fetch per session.
  static Map<String, dynamic>? _cache;
  static Map<String, dynamic>? get cached => _cache;
  static void setCache(Map<String, dynamic> cfg) => _cache = cfg;
  static void invalidate() => _cache = null;

  // ── Defaults ────────────────────────────────────────────────────────────────

  static const defaultLeaveTypes = [
    'Casual Leave',
    'Medical / Sick Leave',
    'Earned Leave',
    'Maternity Leave',
    'Paternity Leave',
    'To Vote',
    'Personal Leave',
    'Funeral / Bereavement',
    'LOP or Others',
  ];

  // The allowance is 2 hours per attendance cycle, in 30-minute steps:
  // 30, 60, 90 or 120 minutes a time (90 allowed again, 20 Nov 2026).
  // Enforced in the database by set_and_check_permission_minutes(); beyond
  // the allowance each permission is half a day's LOP.
  static const defaultPermissionDurations = [
    '30 Minutes',
    '1 Hour',
    '1 Hour 30 Minutes',
    '2 Hours',
  ];

  static const defaultPermissionReasons = [
    'Doctor / Medical',
    'Bank Work',
    'Government / Official Work',
    'Personal Work',
    'Family Emergency',
    'School / College',
    'Other',
  ];

  static const defaultCompOffReasons = [
    'Public Holiday Comp Off',
    'Week Off Comp Off',
    'Site Visit',
    'Leave Comp Off',
    'On Duty',
    'Others',
  ];

  static Map<String, dynamic> defaults() => {
        'leave_types': List<String>.from(defaultLeaveTypes),
        'permission_durations': List<String>.from(defaultPermissionDurations),
        'permission_reasons': List<String>.from(defaultPermissionReasons),
        'compoff_reasons': List<String>.from(defaultCompOffReasons),
      };

  // ── Getters from a config map ─────────────────────────────────────────────

  static List<String> getLeaveTypes(Map<String, dynamic> cfg) {
    final raw = cfg['leave_types'];
    if (raw is List && raw.isNotEmpty) return List<String>.from(raw.cast<String>());
    return List<String>.from(defaultLeaveTypes);
  }

  static List<String> getPermissionDurations(Map<String, dynamic> cfg) {
    final raw = cfg['permission_durations'];
    if (raw is List && raw.isNotEmpty) return List<String>.from(raw.cast<String>());
    return List<String>.from(defaultPermissionDurations);
  }

  static List<String> getPermissionReasons(Map<String, dynamic> cfg) {
    final raw = cfg['permission_reasons'];
    if (raw is List && raw.isNotEmpty) return List<String>.from(raw.cast<String>());
    return List<String>.from(defaultPermissionReasons);
  }

  static List<String> getCompOffReasons(Map<String, dynamic> cfg) {
    final raw = cfg['compoff_reasons'];
    if (raw is List && raw.isNotEmpty) return List<String>.from(raw.cast<String>());
    return List<String>.from(defaultCompOffReasons);
  }
}
