import 'app_user.dart';
import 'attendance_location.dart';
import '../services/supabase_service.dart';

/// In-memory cache of Locations, Attendance Policies, and every assignment
/// (per-department, per-employee override, per-workLocation fallback) that
/// resolves which policy and which Locations apply to a given employee.
/// Mirrors OfficeTimingStore's ensureLoaded/refresh/invalidate + synchronous
/// resolver pattern — nothing is ever cached on the employee or attendance
/// record itself, so an HR change here takes effect on the very next
/// check-in/out.
class AttendancePolicyStore {
  /// Safety net so a geofence check never misbehaves before the first fetch
  /// completes (or if Supabase is unreachable) — matches today's real
  /// hardcoded office point, so behavior is unchanged until HR customizes it.
  static const fallbackLocation = OfficeLocation(
    id: '',
    name: 'Head Office',
    latitude: 13.085027778,
    longitude: 80.222750000,
    radiusMeters: 30,
  );
  static const fallbackPolicy = AttendancePolicy(
    id: '',
    name: 'Office',
    policyType: AttendancePolicyType.singleLocation,
    noteRequiredOutsideRadius: true,
  );

  static List<OfficeLocation> _locations = [];
  static List<AttendancePolicy> _policies = [];
  static Map<String, String> _departmentPolicyId = {};
  static Map<String, String> _employeeOverridePolicyId = {};
  static Map<String, String> _fallbackPolicyIdByWorkLocation = {};
  static Map<String, List<String>> _employeeLocationIds = {};
  static bool _loaded = false;

  static List<OfficeLocation> get allLocations => List.unmodifiable(_locations);
  static List<OfficeLocation> get activeLocations =>
      List.unmodifiable(_locations.where((l) => l.active));
  static List<AttendancePolicy> get allPolicies => List.unmodifiable(_policies);

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    await refresh();
  }

  static Future<void> refresh() async {
    final results = await Future.wait([
      SupabaseService.fetchLocations(),
      SupabaseService.fetchAttendancePolicies(),
      SupabaseService.fetchDepartmentPolicyAssignments(),
      SupabaseService.fetchEmployeePolicyOverrides(),
      SupabaseService.fetchFallbackPolicies(),
      SupabaseService.fetchEmployeeLocations(),
    ]);
    _locations = results[0] as List<OfficeLocation>;
    _policies = results[1] as List<AttendancePolicy>;
    _departmentPolicyId = results[2] as Map<String, String>;
    _employeeOverridePolicyId = results[3] as Map<String, String>;
    _fallbackPolicyIdByWorkLocation = results[4] as Map<String, String>;
    _employeeLocationIds = results[5] as Map<String, List<String>>;
    _loaded = true;
  }

  static void invalidate() => _loaded = false;

  /// Whether [employeeId] has an explicit override (for the admin UI's
  /// "why does this employee have this policy" provenance display).
  static bool hasEmployeeOverride(String employeeId) =>
      _employeeOverridePolicyId.containsKey(employeeId);

  /// Whether [department] has an explicit policy assignment.
  static bool hasDepartmentAssignment(String department) =>
      _departmentPolicyId.containsKey(department);

  static AttendancePolicy? _byId(String? id) {
    if (id == null) return null;
    final match = _policies.where((p) => p.id == id);
    return match.isEmpty ? null : match.first;
  }

  /// Resolution order: employee override → department assignment →
  /// work-location fallback → hardcoded safety net.
  static AttendancePolicy policyForEmployee({
    required String employeeId,
    required String department,
    required String workLocation,
  }) {
    final override = _byId(_employeeOverridePolicyId[employeeId]);
    if (override != null) return override;

    final departmentPolicy = _byId(_departmentPolicyId[department]);
    if (departmentPolicy != null) return departmentPolicy;

    final fallback = _byId(_fallbackPolicyIdByWorkLocation[workLocation]) ??
        _byId(_fallbackPolicyIdByWorkLocation['Office']);
    if (fallback != null) return fallback;

    return fallbackPolicy;
  }

  static AttendancePolicy policyForUser(AppUser u) => policyForEmployee(
        employeeId: u.employeeId,
        department: u.department,
        workLocation: u.workLocation,
      );

  /// What [policyForEmployee] would resolve to if this employee had no
  /// individual override — i.e. department assignment → work-location
  /// fallback → safety net. Used by the admin UI to show "Inherit (X)"
  /// next to the override picker.
  static AttendancePolicy inheritedPolicy({required String department, required String workLocation}) {
    final departmentPolicy = _byId(_departmentPolicyId[department]);
    if (departmentPolicy != null) return departmentPolicy;
    final fallback = _byId(_fallbackPolicyIdByWorkLocation[workLocation]) ??
        _byId(_fallbackPolicyIdByWorkLocation['Office']);
    return fallback ?? fallbackPolicy;
  }

  /// Active Locations assigned to [employeeId]. Falls back to the hardcoded
  /// Head Office point if nothing is configured yet (e.g. before the first
  /// sync completes), so a Single-Location employee is never silently left
  /// with zero locations.
  /// Locations an employee may check in from.
  ///
  /// Every ACTIVE company site counts, not only the ones assigned to them.
  /// Staff move between the office and sites for meetings, handovers and
  /// site visits, and being at another Fomra location is plainly not an
  /// absence — it was previously treated as off-site and demanded a written
  /// excuse. The assignment still matters: it is what
  /// [primaryLocationsFor] reports as the person's normal base, and the
  /// recorded coordinates show which site they were actually at.
  static List<OfficeLocation> locationsForEmployee(String employeeId) {
    final active = _locations.where((l) => l.active).toList();
    if (active.isEmpty) {
      // No locations configured at all — fall back rather than treat every
      // employee as permanently off-site.
      return const [fallbackLocation];
    }
    return active;
  }

  /// The sites actually assigned to [employeeId] — their normal base, as
  /// distinct from everywhere they are permitted to check in from.
  static List<OfficeLocation> primaryLocationsFor(String employeeId) {
    final ids = _employeeLocationIds[employeeId];
    if (ids == null || ids.isEmpty) return const [];
    return _locations.where((l) => l.active && ids.contains(l.id)).toList();
  }

  /// Location ids currently assigned to [employeeId] (for the admin UI).
  static List<String> locationIdsFor(String employeeId) =>
      List.unmodifiable(_employeeLocationIds[employeeId] ?? const []);

  /// Employees currently assigned to [locationId] (for the admin UI).
  static List<String> employeesFor(String locationId) => _employeeLocationIds.entries
      .where((e) => e.value.contains(locationId))
      .map((e) => e.key)
      .toList();

  /// Departments currently assigned to [policyId] (for the admin UI).
  static List<String> departmentsFor(String policyId) => _departmentPolicyId.entries
      .where((e) => e.value == policyId)
      .map((e) => e.key)
      .toList();

  /// work_location values ('Office'/'Onsite') currently falling back to
  /// [policyId] (for the admin UI).
  static List<String> fallbackWorkLocationsFor(String policyId) =>
      _fallbackPolicyIdByWorkLocation.entries
          .where((e) => e.value == policyId)
          .map((e) => e.key)
          .toList();
}
