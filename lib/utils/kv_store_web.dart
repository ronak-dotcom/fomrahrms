import 'dart:html' as html;

/// Web-side session storage for the app's own "logged in" record.
///
/// localStorage, NOT sessionStorage. sessionStorage is wiped the moment the
/// browser tab closes, so everyone was signed out every time they closed the
/// browser — and re-entered their credentials next morning at exactly the
/// point they were trying to check in, which is what was making people late.
/// The 10-hour expiry was blamed for this, but the tab closing beat it every
/// time.
///
/// The stored values are a role, a name, an employee id and an expiry — not
/// a password. The actual credential is Supabase's refresh token, which its
/// own client stores separately and already persists.
///
/// A shared device is the trade-off, and it is handled: Sign Out clears this
/// immediately, and the expiry still applies.
Future<String?> kvGetString(String key) async {
  // Falls back to sessionStorage so anyone mid-session when this shipped is
  // not signed out by the switch.
  return html.window.localStorage[key] ?? html.window.sessionStorage[key];
}

Future<void> kvSetString(String key, String value) async {
  html.window.localStorage[key] = value;
}

Future<void> kvRemove(String key) async {
  html.window.localStorage.remove(key);
  // Clears any value left over from before the switch, so signing out does
  // not leave a stale copy that the fallback above would then read back.
  html.window.sessionStorage.remove(key);
}
