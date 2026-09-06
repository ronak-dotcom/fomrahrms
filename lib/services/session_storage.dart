import '../models/user_session.dart';
import '../utils/kv_store.dart';

class SessionStorage {
  static const _kRole             = 'fomra_role';
  static const _kName             = 'fomra_name';
  static const _kEmployeeId       = 'fomra_employee_id';
  static const _kEmail            = 'fomra_email';
  static const _kExpiry           = 'fomra_expiry';
  static const _kDesignation      = 'fomra_designation';
  static const _kDepartment       = 'fomra_department';
  static const _kReportingManager = 'fomra_reporting_manager';
  static const _kIsReportingManager = 'fomra_is_reporting_manager';
  static const _kWorkLocation     = 'fomra_work_location';
  static const _kPermissionQuota  = 'fomra_permission_minutes_quota';
  static const _kIsOnroll         = 'fomra_is_onroll';
  static const _kExemptAttendance = 'fomra_exempt_attendance';
  static const _kOversightOnly    = 'fomra_oversight_only';
  static const _kExemptTiming     = 'fomra_exempt_timing';

  /// 10 hours meant a login at 09:00 expired by 19:00, so staff re-entered
  /// their credentials EVERY morning — at exactly the moment they were trying
  /// to check in, which is what made people late. The session holds a real
  /// Supabase refresh token in keystore/keychain, so a longer window is not
  /// a weaker credential; it just stops asking a question already answered.
  ///
  /// 30 days, and renewed on every app open (see restore), so anyone using
  /// the app regularly never sees the login screen again. Signing out still
  /// clears it immediately.
  static const _duration = Duration(days: 30);

  /// Daily re-authentication point, chosen deliberately at 15:00.
  ///
  /// A session that simply never expires would let anyone holding the phone
  /// check in or out as that person indefinitely. But putting the login at a
  /// fixed clock time beats an elapsed-time expiry, which lands wherever the
  /// previous login happened to fall — often 09:00, exactly when people are
  /// rushing to check in, which is what was making them late.
  ///
  /// 15:00 sits between the two moments that matter: after everyone has
  /// checked in, and well before check-out at 18:30. The one login of the day
  /// therefore happens when nobody is against the clock.
  static const _dailyResetHour = 15;

  /// The next 15:00 after [from]. Sessions never outlive this.
  static DateTime _nextDailyReset(DateTime from) {
    final todayReset =
        DateTime(from.year, from.month, from.day, _dailyResetHour);
    return from.isBefore(todayReset)
        ? todayReset
        : todayReset.add(const Duration(days: 1));
  }

  /// Whichever comes first: the rolling window, or the next 15:00.
  static DateTime _expiryFrom(DateTime now, Duration window) {
    final rolling = now.add(window);
    final reset = _nextDailyReset(now);
    return rolling.isBefore(reset) ? rolling : reset;
  }
  // Housekeeping/Support Staff stay logged in far longer — they share
  // devices and re-entering credentials each shift is impractical.
  static const _staffPortalDuration = Duration(days: 180);

  static Future<void> save() async {
    await kvSetString(_kRole, UserSession.role.name);
    await kvSetString(_kName, UserSession.name);
    await kvSetString(_kEmployeeId, UserSession.employeeId);
    await kvSetString(_kEmail, UserSession.email);
    await kvSetString(_kDesignation, UserSession.designation);
    await kvSetString(_kDepartment, UserSession.department);
    await kvSetString(_kReportingManager, UserSession.reportingManager);
    await kvSetString(_kIsReportingManager, UserSession.isReportingManager ? '1' : '0');
    await kvSetString(_kWorkLocation, UserSession.workLocation);
    await kvSetString(_kPermissionQuota, UserSession.permissionMinutesQuota.toString());
    await kvSetString(_kIsOnroll, UserSession.isOnroll ? '1' : '0');
    await kvSetString(_kExemptAttendance, UserSession.exemptFromAttendance ? '1' : '0');
    await kvSetString(_kOversightOnly, UserSession.oversightOnly ? '1' : '0');
    await kvSetString(_kExemptTiming, UserSession.exemptFromTiming ? '1' : '0');
    final duration =
        UserSession.isStaffPortal ? _staffPortalDuration : _duration;
    // Staff portal keeps its long window untouched: it is a shared device
    // that nobody would be present to sign back in at 15:00.
    final expiry = UserSession.isStaffPortal
        ? DateTime.now().add(duration)
        : _expiryFrom(DateTime.now(), duration);
    await kvSetString(_kExpiry, expiry.millisecondsSinceEpoch.toString());
  }

  static Future<bool> restore() async {
    try {
      final expiryStr = await kvGetString(_kExpiry);
      if (expiryStr == null) return false;
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(int.parse(expiryStr));
      if (DateTime.now().isAfter(expiry)) {
        await clear();
        return false;
      }
      final roleName = await kvGetString(_kRole);
      if (roleName == null) return false;
      final role = UserRole.values.firstWhere(
        (r) => r.name == roleName,
        orElse: () => UserRole.employee,
      );
      UserSession.loggedIn         = true;
      UserSession.role             = role;
      UserSession.name             = await kvGetString(_kName) ?? '';
      UserSession.employeeId       = await kvGetString(_kEmployeeId) ?? '';
      UserSession.email            = await kvGetString(_kEmail) ?? '';
      UserSession.designation      = await kvGetString(_kDesignation) ?? '';
      UserSession.department       = await kvGetString(_kDepartment) ?? '';
      UserSession.reportingManager = await kvGetString(_kReportingManager) ?? '';
      UserSession.isReportingManager = (await kvGetString(_kIsReportingManager)) == '1';
      UserSession.workLocation     = await kvGetString(_kWorkLocation) ?? '';
      UserSession.permissionMinutesQuota =
          int.tryParse(await kvGetString(_kPermissionQuota) ?? '') ?? 120;
      UserSession.isOnroll = (await kvGetString(_kIsOnroll)) == '1';
      UserSession.exemptFromAttendance = (await kvGetString(_kExemptAttendance)) == '1';
      UserSession.oversightOnly = (await kvGetString(_kOversightOnly)) == '1';
      UserSession.exemptFromTiming = (await kvGetString(_kExemptTiming)) == '1';
      // Sliding expiry, renewed here rather than at the top because
      // isStaffPortal is derived from the fields just restored above and
      // would otherwise read stale. Without renewal a 30-day window still
      // evicts a daily user, just less often — the same interruption, harder
      // to predict.
      final renewal =
          UserSession.isStaffPortal ? _staffPortalDuration : _duration;
      final renewed = UserSession.isStaffPortal
          ? DateTime.now().add(renewal)
          : _expiryFrom(DateTime.now(), renewal);
      await kvSetString(_kExpiry, renewed.millisecondsSinceEpoch.toString());

      // Photo URL is fetched from main() once Supabase has finished
      // initializing (fetching it here would race Supabase.initialize()
      // and silently fail every time).
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear() async {
    await kvRemove(_kRole);
    await kvRemove(_kName);
    await kvRemove(_kEmployeeId);
    await kvRemove(_kEmail);
    await kvRemove(_kExpiry);
    await kvRemove(_kDesignation);
    await kvRemove(_kDepartment);
    await kvRemove(_kReportingManager);
    await kvRemove(_kIsReportingManager);
    await kvRemove(_kWorkLocation);
    await kvRemove(_kPermissionQuota);
    await kvRemove(_kIsOnroll);
    await kvRemove(_kExemptAttendance);
    await kvRemove(_kOversightOnly);
    await kvRemove(_kExemptTiming);
  }
}
