// Server-side login. Replaces the old client-side flow where the Flutter
// app downloaded the entire app_users table (every employee, including
// plaintext passwords) and compared passwords locally in Dart.
//
// The client now sends { email, password } here. This function checks the
// password against the bcrypt hash in app_users.password_hash via the
// verify_app_user_password RPC (see
// supabase/migrations/20260716000000_auth_foundation.sql — that RPC is
// service_role-only, so it can't be called directly by anon/authenticated
// clients). On success it mints a real Supabase Auth session for a shadow
// auth.users row linked to that employee (created lazily on first login
// after this migration ships) and returns the access/refresh tokens plus
// the caller's own profile fields — never another user's data, never any
// password material. The client calls supabase.auth.setSession(...) with
// the returned refresh token, so every later Postgres request carries a
// real JWT (auth.uid()/email) that RLS policies can key off.
//
// This deliberately does not touch the existing account-activation /
// password-reset token flow (still emailed via EmailService + the
// send-email function) — this function only replaces the final
// "check the password" step.
//
// Required secrets (set with `supabase secrets set`):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";

type SupabaseLike = {
  from: (table: string) => {
    select: (columns: string) => {
      ilike: (column: string, value: string) => {
        maybeSingle: () => Promise<{ data: Record<string, unknown> | null; error: unknown }>;
      };
    };
  };
};

// A NEW client for every request, never a shared one.
//
// This used to be a single client kept for the life of the function
// instance. verifyOtp() below signs the client it is called on in as the
// employee who just logged in, and from then on supabase-js sends that
// employee's token instead of the service-role key. So the next person to log
// in on the same warm instance was looked up AS THE PREVIOUS USER, under RLS,
// which lets an employee see only their own app_users row: their account
// "did not exist" and they were told "Invalid email or password" however
// correct the password was. A password reset could not help, because the
// password was never reached. Between 5 and 19 Nov 2026 this caused all 94
// not-found failures for real accounts, each within 3 minutes of someone
// else's successful login.
//
// Now: one service-role client per request for lookups and admin calls, and a
// separate throwaway client for verifyOtp, so no session is ever carried over.
function newClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be configured");
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

// CORS is a browser-side check only, so this is defence-in-depth rather than
// the security boundary. But getting it wrong LOCKS USERS OUT: the browser
// sends the preflight, sees an Access-Control-Allow-Origin that doesn't match,
// and never sends the POST. In the logs that is OPTIONS 200 with no POST.
//
// A single hardcoded origin broke exactly that way, because every Vercel
// deployment gets its own hostname. The live app is hrms.fomrahousing.in,
// covered by the second pattern. (This block was copied back from the
// deployed version on 19 Nov 2026; the repo copy had fallen behind it.)
const ALLOWED_ORIGIN_EXACT = [
  "https://fomrahrms-zeta.vercel.app",
  "https://internfomrahousing-oss.github.io",
];

const ALLOWED_ORIGIN_PATTERNS = [
  /^https:\/\/fomrahrms(-[a-z0-9-]+)?\.vercel\.app$/,
  /^https:\/\/([a-z0-9-]+\.)?fomrahousing\.in$/,
];

function isAllowedOrigin(origin: string): boolean {
  if (!origin) return false;
  if (ALLOWED_ORIGIN_EXACT.includes(origin)) return true;
  if (origin.startsWith("http://localhost")) return true;
  return ALLOWED_ORIGIN_PATTERNS.some((re) => re.test(origin));
}

function corsHeadersFor(req: Request) {
  const origin = req.headers.get("Origin") ?? "";
  if (!isAllowedOrigin(origin) && origin) {
    console.warn("login: request from unrecognised origin", origin);
  }
  const allowOrigin = isAllowedOrigin(origin) ? origin : ALLOWED_ORIGIN_EXACT[0];
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

// Escape PostgREST/ilike wildcards so an email containing `%` or `_`
// can't be used to match more than one row.
function escapeIlike(value: string) {
  return value.replace(/[%_]/g, "\\$&");
}

// Direct insert (service_role bypasses RLS) rather than the
// log_audit_event() RPC, since that RPC stamps the actor from the caller's
// own JWT — there isn't one yet on a failed login, and this function's
// session is the service role's, not the employee's.
async function logAudit(
  db: ReturnType<typeof newClient>,
  action: string,
  actorEmail: string,
  actorRole = "",
) {
  try {
    await db.from("audit_log").insert({
      action,
      actor_email: actorEmail,
      actor_role: actorRole,
      target_type: "app_users",
      target_id: actorEmail,
    });
  } catch (err) {
    console.error("audit log insert failed", err);
  }
}

function buildProfile(row: Record<string, unknown>) {
  return {
    email: row.email,
    name: row.name,
    employee_id: row.employee_id,
    role: row.role,
    active: row.active,
    designation: row.designation,
    department: row.department,
    reporting_manager: row.reporting_manager,
    is_reporting_manager: row.is_reporting_manager,
    work_location: row.work_location,
    permission_minutes_quota: row.permission_minutes_quota,
    // Drives probation rules in the client: while empty the employee gets one
    // leave per attendance cycle and no permission at all.
    onroll_confirmed_at: row.onroll_confirmed_at,
    // Hides Check In/Out and excludes the user from attendance reporting.
    exempt_from_attendance: row.exempt_from_attendance,
    // Full admin rights, no personal HR record — hides self-service entirely.
    oversight_only: row.oversight_only,
    // No fixed hours — suppresses the late-reason prompt and the early
    // check-out prompt for the CEO and the Head of Operations.
    exempt_from_timing: row.exempt_from_timing,
  };
}

export async function findAppUserByLoginIdentifier(
  supabaseClient: SupabaseLike,
  identifier: string,
) {
  const normalized = identifier.trim();
  if (!normalized) {
    return { row: null as Record<string, unknown> | null, matchedField: null as string | null };
  }

  const selectColumns = [
    "email",
    "name",
    "employee_id",
    "role",
    "active",
    "designation",
    "department",
    "reporting_manager",
    "is_reporting_manager",
    "work_location",
    "permission_minutes_quota",
    "password",
    "password_hash",
    "auth_user_id",
    "company_email",
    "onroll_confirmed_at",
    "exempt_from_attendance",
    "oversight_only",
    "exempt_from_timing",
  ].join(", ");

  // Signing in by mobile number was added here in September 2026 but never
  // deployed. Left out of the 19 Nov 2026 deploy so that fixing the shared
  // client changed nothing else; add "mobile" back as a separate change.
  const columns = ["email", "company_email", "employee_id"] as const;
  for (const column of columns) {
    const { data, error } = await supabaseClient
      .from("app_users")
      .select(selectColumns)
      .ilike(column, escapeIlike(normalized))
      .maybeSingle();

    if (!error && data) {
      return { row: data as Record<string, unknown>, matchedField: column };
    }
  }

  return { row: null, matchedField: null };
}

Deno.serve(async (req) => {
  const corsHeaders = corsHeadersFor(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  function json(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const { email, password } = await req.json();
    if (!email || !password) {
      return json({ error: "email and password are required" }, 400);
    }

    // Fresh per request; see newClient().
    const admin = newClient();
    const { row, matchedField } = await findAppUserByLoginIdentifier(admin as never, email);
    const entry = row as Record<string, unknown> | null;

    // Same generic error whether the email doesn't exist or the password is
    // wrong — no user-enumeration hints, matching the old client-side
    // behavior (login_page.dart always showed "Invalid email or password.").
    if (!entry || matchedField == null) {
      await logAudit(admin, "login_failed", email);
      return json({ error: "Invalid email or password" }, 401);
    }
    if (!entry.active) {
      return json({ error: "not_activated" }, 403);
    }

    // password_hash was stored as '' (empty string, NOT null) for every user
    // in production. '' is falsy in JS, so the old `if (passwordHash)` test
    // was false and control fell through to the plaintext `legacyPassword`
    // comparison below — which became the ONLY working login path, and is why
    // a password had to be typed into Supabase by hand for each employee.
    //
    // Guard on hash *shape* instead of truthiness. A bcrypt hash is 60 chars;
    // anything under 20 is empty, truncated or otherwise unusable, and would
    // make crypt(p_password, '') raise `ERROR: 22023: invalid salt` inside
    // verify_app_user_password().
    const passwordHash = typeof entry.password_hash === "string" ? entry.password_hash : "";
    const hasUsableHash = passwordHash.trim().length >= 20;

    if (!hasUsableHash) {
      // No password set yet -> the client shows the Set Password card.
      //
      // The plaintext `entry.password` fallback that used to live here has
      // been REMOVED. Existing plaintext passwords are migrated to bcrypt by
      // supabase/migrations/20260731000100_fix_auth_password_flow.sql, so no
      // account should reach this point still holding one. Deploy this
      // function only AFTER that migration has been applied.
      return json({ needsPasswordSetup: true, profile: buildProfile(entry) });
    }

    const loginEmail = String(entry.email ?? "").trim();
    let verified = false;

    try {
      const { data, error } = await admin.rpc(
        "verify_app_user_password",
        { p_email: loginEmail, p_password: password },
      );
      if (error) {
        // Previously swallowed silently, indistinguishable from a genuine
        // wrong-password result — every failed login looked identical
        // whether the RPC itself errored (missing function, permissions,
        // schema issue) or the password was actually just wrong.
        console.error("verify_app_user_password RPC failed", error);
      }
      verified = !error && Boolean(data);
    } catch (err) {
      console.error("verify_app_user_password threw", err);
      verified = false;
    }

    if (!verified) {
      await logAudit(admin, "login_failed", loginEmail, String(entry.role ?? ""));
      return json({ error: "Invalid email or password" }, 401);
    }

    // Lazily provision a shadow auth.users row the first time this employee
    // logs in after the migration — its password is random/unusable, since
    // verify_app_user_password above is the real credential check. Reuse an
    // existing auth user if one already exists for that email — looked up
    // via the auth_user_id_by_email() RPC (see
    // supabase/migrations/20260716000700_auth_user_lookup_rpc.sql) rather
    // than auth.admin.getUserByEmail(), which doesn't exist on the
    // supabase-js v2 Admin API.
    let authUserId = entry.auth_user_id as string | null;
    if (!authUserId) {
      try {
        const { data: existingId } = await admin.rpc("auth_user_id_by_email", {
          p_email: loginEmail,
        });
        if (existingId) {
          authUserId = existingId as string;
        } else {
          const { data: created, error: createError } = await admin.auth.admin.createUser({
            email: loginEmail,
            email_confirm: true,
            password: crypto.randomUUID() + crypto.randomUUID(),
          });
          if (createError || !created?.user) {
            console.error("createUser failed", createError);
            return json({ error: "Could not start session" }, 500);
          }
          authUserId = created.user.id;
        }
        await admin.from("app_users").update({ auth_user_id: authUserId }).eq("email", loginEmail);
      } catch (createErr) {
        console.error("createUser failed", createErr);
        return json({ error: "Could not start session" }, 500);
      }
    }

    // Mint a session for that auth user without ever needing its real
    // password: generate a magic-link token server-side, then immediately
    // redeem it ourselves via verifyOtp to get back a session.
    const { data: link, error: linkError } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email: loginEmail,
    });
    const hashedToken = link?.properties?.hashed_token;
    if (linkError || !hashedToken) {
      console.error("generateLink failed", linkError);
      return json({ error: "Could not start session" }, 500);
    }

    const { data: session, error: sessionError } = await newClient().auth.verifyOtp({
      type: "magiclink",
      token_hash: hashedToken,
    });
    if (sessionError || !session?.session) {
      console.error("verifyOtp failed", sessionError);
      return json({ error: "Could not start session" }, 500);
    }

    await logAudit(admin, "login_success", loginEmail, String(entry.role ?? ""));

    return json({
      access_token: session.session.access_token,
      refresh_token: session.session.refresh_token,
      profile: buildProfile(entry),
    });
  } catch (err) {
    console.error(err);
    return json({ error: String(err) }, 500);
  }
});
