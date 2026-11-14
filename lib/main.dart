import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'models/color_theme_notifier.dart';
import 'models/language_notifier.dart';
import 'models/notification_store.dart';
import 'models/attendance_policy_store.dart';
import 'models/office_timing.dart';
import 'models/user_session.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'services/error_reporter.dart';
import 'services/supabase_service.dart';
import 'services/session_storage.dart';
import 'utils/secure_local_storage.dart';
import 'utils/url_strategy.dart';
import 'widgets/notification_popup_overlay.dart';

void main() async {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  // Record crashes and uncaught errors for Management's App Health page.
  ErrorReporter.install();

  // Restore persisted login before the router guard runs — must be awaited
  // since the router reads UserSession synchronously at first build.
  final restored = await SessionStorage.restore();
  if (restored) {
    staffLanguageNotifier.loadForUser(UserSession.employeeId);
  }

  // Start the app immediately so the splash screen clears.
  runApp(const FomraHrmsApp());

  // Initialize Supabase in the background after the first frame.
  try {
    await Supabase.initialize(
      url: 'https://jjkijnmrtkkukdboajxu.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impqa2lqbm1ydGtrdWtkYm9hanh1'
          'Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxMTE0NDMsImV4cCI6MjA5NzY4'
          'NzQ0M30.6I2swrTQDDT0phQvRqDkLFFo_BxtmxD3NE9R8lDbDeI',
      // Keystore/keychain-backed on native instead of plain SharedPreferences
      // — the session holds a real refresh token now that login mints a
      // genuine Supabase Auth session (see lib/utils/secure_local_storage.dart).
      authOptions: FlutterAuthClientOptions(localStorage: platformLocalStorage()),
    );
    // SessionStorage.restore() (above) trusts a locally-cached "logged in"
    // flag with its own 10h/180d expiry, entirely separate from Supabase's
    // real Auth session (the JWT every RLS policy actually keys off). If
    // that real session failed to restore/refresh here — expired refresh
    // token, cleared storage, etc. — every authenticated request from this
    // point on runs as anon and gets silently empty-filtered by RLS instead
    // of erroring, which used to look like "no data" bugs rather than what
    // it is: not actually logged in. Catch that mismatch once at startup
    // and force a real logout instead of leaving the app in a half-signed-in
    // state.
    if (restored && Supabase.instance.client.auth.currentSession == null) {
      await SessionStorage.clear();
      UserSession.clear();
      final context = rootNavigatorKey.currentContext;
      if (context != null) GoRouter.of(context).go('/login');
    }
    // supabase_flutter persists the Auth session in localStorage on web,
    // which every tab on this origin shares. Logging into a *different*
    // account in one tab silently rewrites that shared session — every
    // other already-open tab then starts running its queries as the new
    // account, RLS quietly narrows what comes back (e.g. an HR dashboard
    // dropping to "1 employee"), and nothing in the UI ever explains why.
    // onAuthStateChange fires in every tab when that swap happens, so catch
    // it here: if the session that just landed belongs to someone other
    // than who this tab thinks is logged in, this tab's identity is stale —
    // force it back to login with an explanation instead of silently
    // continuing to render as the wrong (or now-ambiguous) user.
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final incomingEmail = data.session?.user.email?.toLowerCase();
      if (!UserSession.loggedIn ||
          incomingEmail == null ||
          UserSession.email.isEmpty ||
          incomingEmail == UserSession.email.toLowerCase()) {
        return;
      }
      SessionStorage.clear();
      UserSession.clear();
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        GoRouter.of(context).go('/login',
            extra: 'You were signed out because a different account '
                'logged in on this browser.');
      }
    });
    // Chained via .then() rather than awaited outright — daily-reminder
    // checks below read the global TaskStore/UserStore that loadAll()
    // populates, so they must run after it, but the app itself shouldn't
    // block its splash screen on this.
    SupabaseService.loadAll().then((_) {
      if (restored && UserSession.loggedIn) {
        NotificationService.checkDailyTaskReminders();
        if (UserSession.role == UserRole.hr || UserSession.role == UserRole.management) {
          NotificationService.checkDailyReminders();
        }
        PushNotificationService.init();
      }
    });
    SupabaseService.restoreCheckInState();
    OfficeTimingStore.ensureLoaded();
    AttendancePolicyStore.ensureLoaded();
    colorThemeNotifier.loadInitial();
    if (restored && UserSession.employeeId.isNotEmpty) {
      SupabaseService.fetchCurrentUserPhotoUrl(UserSession.employeeId).then((url) {
        if (url != null) UserSession.photoUrl = url;
      });
    }
  } catch (_) {
  } finally {
    // Settled one way or another — safe for early queries to stop waiting.
    SupabaseService.markReady();
  }

  // Keep the notification bell fresh without a full realtime subscription —
  // re-poll periodically for as long as the app is open. Also doubles as
  // the retry path for the once-a-day reminder checks (cheap to call
  // repeatedly — each no-ops after its first run each calendar day).
  // On the FIRST poll after opening the app, every stored notification counts
  // as a "new arrival" — the store starts empty — so a popup was shown for
  // each one and they stacked across the screen at login. Nothing is lost by
  // suppressing them: they are all in the bell, and the badge shows the unread
  // count. Popups are for things that arrive WHILE you are working.
  var isFirstNotificationPoll = true;

  // A burst can still occur later (the daily reminder sweep raises several at
  // once). Cap what is shown on screen so a batch cannot cover the UI; the
  // rest remain in the bell.
  const maxPopupsPerPoll = 3;

  Timer.periodic(const Duration(seconds: 20), (_) async {
    if (!UserSession.loggedIn) return;
    final list = await SupabaseService.fetchNotifications();
    final newArrivals = NotificationStore.diffNewArrivals(list);
    NotificationStore.all
      ..clear()
      ..addAll(list);
    NotificationStore.recomputeUnread();
    NotificationService.checkDailyReminders();
    NotificationService.checkDailyTaskReminders();

    if (isFirstNotificationPoll) {
      isFirstNotificationPoll = false;
    } else {
      for (final arrival in newArrivals.take(maxPopupsPerPoll)) {
        showNotificationPopup(arrival);
      }
    }
  });
}
