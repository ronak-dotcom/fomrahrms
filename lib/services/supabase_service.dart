// ignore_for_file: avoid_catches_without_on_clauses
import 'dart:async';
import 'gps_tracking_service.dart';
import 'user_store.dart';
import 'session_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/appraisal_store.dart';
import '../models/attendance_location.dart';
import '../models/attendance_store.dart';
import '../models/leave_store.dart';
import '../models/maintenance_store.dart';
import '../models/notification_store.dart';
import '../models/office_timing.dart';
import '../models/payslip_store.dart';
import '../models/profile_store.dart';
import '../models/employee_store.dart';
import '../models/kra_store.dart';
import '../models/task_store.dart';
import '../models/user_session.dart';

/*
  Run the following SQL in your Supabase SQL Editor to create the tables:

  create table if not exists leave_applications (
    id text primary key,
    employee_name text not null,
    employee_id text default '',
    department text default '',
    leave_type text default '',
    from_date date not null,
    to_date date not null,
    days integer not null,
    reason text default '',
    applied_on timestamptz default now(),
    manager_status text default 'pending',
    decided_by text default '',
    rejection_comment text default '',
    is_half_day boolean default false
  );

  -- If the table already exists:
  alter table leave_applications add column if not exists decided_by text default '';
  alter table leave_applications add column if not exists rejection_comment text default '';
  alter table leave_applications add column if not exists is_half_day boolean default false;
  alter table leave_applications add column if not exists management_status text default 'pending';
  alter table leave_applications add column if not exists management_decided_by text default '';
  alter table leave_applications add column if not exists management_rejection_comment text default '';
  alter table leave_applications add column if not exists proof_url text default '';
  alter table leave_applications add column if not exists leave_bucket text default '';

  alter table onboarding_forms disable row level security;

  create table if not exists onboarding_forms (
    id uuid primary key default gen_random_uuid(),
    submitted_at timestamptz default now(),
    name text, phone_number text, father_name text, designation text,
    date_of_joining text, full_name text, date_of_birth text,
    postal_address text, permanent_address text,
    family_details jsonb default '[]',
    education jsonb default '[]',
    experience jsonb default '[]',
    last_reporting_name text, last_reporting_designation text,
    last_company text, reference1 text, reference2 text,
    esi_number text, pf_number text, languages_known text,
    hobbies text, interests text, related_to_employee text,
    professional_membership text, specialized_training text,
    other_information text, blood_group text, allergic_to text,
    major_illness text, emergency_contact_name text,
    emergency_contact_number text, emergency_contact_address text,
    aadhar_number text, declaration_date text, declaration_place text
  );

  create table if not exists lead_sources (
    id text primary key,
    name text not null,
    url text not null,
    created_at timestamptz default now()
  );

  create table if not exists maintenance_tickets (
    id text primary key,
    reported_by_role text not null,
    reported_by text not null,
    issue_for text not null default 'IT',
    issue_type text not null,
    description text not null,
    status text default 'open',
    sent_to_management boolean default false,
    management_reviewed boolean default false,
    resolution_note text,
    resolved_at timestamptz,
    created_at timestamptz default now()
  );
  -- If table already exists, add the newer columns:
  alter table maintenance_tickets add column if not exists sent_to_management boolean default false;
  alter table maintenance_tickets add column if not exists issue_for text not null default 'IT';
  alter table maintenance_tickets add column if not exists management_reviewed boolean default false;
  alter table maintenance_tickets add column if not exists resolution_note text;
  alter table maintenance_tickets add column if not exists resolved_at timestamptz;
  alter table maintenance_tickets add column if not exists priority text not null default 'Medium';

  create table if not exists app_settings (
    id text primary key default 'global',
    color_theme text default 'midnightBlue'
  );
  -- Empty banner_quote means "no Management override" — the app rotates
  -- through a built-in daily Mahatria Ra quote instead.
  alter table app_settings add column if not exists banner_quote text default '';
  alter table app_settings add column if not exists banner_quote_author text default '';

  create table if not exists payslip_requests (
    id text primary key,
    employee_id text default '',
    employee_name text default '',
    month_year text not null,
    status text default 'pending',
    requested_at timestamptz default now(),
    decided_at timestamptz,
    decided_by text default '',
    rejection_comment text default ''
  );
  alter table payslip_requests add column if not exists rejection_comment text default '';

  create table if not exists payslips (
    id text primary key,
    employee_id text default '',
    month_year text not null,
    emp_name text default '',
    department text default '',
    designation text default '',
    band text default '',
    date_of_joining text default '',
    working_days integer default 0,
    days_worked integer default 0,
    lop_days integer default 0,
    gross_pay numeric default 0,
    basic numeric default 0,
    hra numeric default 0,
    educational_allowance numeric default 0,
    lta numeric default 0,
    other_allowance numeric default 0,
    conveyance_allowance numeric default 0,
    special_allowance numeric default 0,
    epf numeric default 0,
    professional_tax numeric default 0,
    tds numeric default 0,
    late_deductions numeric default 0,
    excess_leave_deduction numeric default 0,
    cug numeric default 0,
    leave_details text default '[]',
    generated_at timestamptz default now(),
    generated_by text default ''
  );

  -- If the table already exists:
  alter table payslips add column if not exists excess_leave_deduction numeric default 0;

  create table if not exists employee_profiles (
    employee_id text primary key,
    full_name text default '',
    mobile text default '',
    email text default '',
    address text default '',
    department text default '',
    designation text default '',
    reporting_manager text default '',
    date_of_joining text default ''
  );

  create table if not exists employees (
    id text primary key,
    name text not null,
    department text default '',
    designation text default '',
    mobile text default '',
    email text default '',
    address text default '',
    blood_group text default '',
    manager text default '',
    joining_date text default '',
    salary text default '',
    emergency_name text default '',
    emergency_phone text default '',
    bank_account text default '',
    ifsc text default ''
  );

  create table if not exists candidate_applications (
    id uuid default gen_random_uuid() primary key,
    submitted_at timestamptz default now(),
    name text default '',
    mobile text default '',
    place text default '',
    dob text default '',
    nationality text default '',
    email text default '',
    gender text default '',
    marital_status text default '',
    age text default '',
    interview_date text default '',
    post_applied text default '',
    total_experience text default '',
    relevant_experience text default '',
    reason_for_change text default '',
    current_ctc text default '',
    expected_ctc text default '',
    notice_period text default '',
    source text default '',
    job_portal text default '',
    referred_by text default '',
    related_employee text default '',
    applied_before text default '',
    hr_status text default 'pending',
    hr_comment text default '',
    assigned_manager text default '',
    manager_status text default 'pending',
    manager_comment text default '',
    management_status text default 'pending',
    management_comment text default ''
  );

  -- If the table already exists, add the review columns:
  alter table candidate_applications add column if not exists hr_status text default 'pending';
  alter table candidate_applications add column if not exists hr_comment text default '';
  alter table candidate_applications add column if not exists assigned_manager text default '';
  alter table candidate_applications add column if not exists manager_status text default 'pending';
  alter table candidate_applications add column if not exists manager_comment text default '';
  alter table candidate_applications add column if not exists management_status text default 'pending';
  alter table candidate_applications add column if not exists management_comment text default '';
  alter table candidate_applications add column if not exists standing_arrears text default '';
  alter table candidate_applications add column if not exists education_history jsonb default '[]';
  alter table candidate_applications add column if not exists employment_history jsonb default '[]';
  alter table candidate_applications add column if not exists referrals jsonb default '[]';
  alter table candidate_applications add column if not exists address text default '';
  alter table candidate_applications add column if not exists declaration_name text default '';
  alter table candidate_applications add column if not exists signature_date text default '';
  alter table candidate_applications add column if not exists declaration_agreed boolean default false;
  alter table candidate_applications add column if not exists resume_url text default '';
  alter table candidate_applications add column if not exists custom_field_values jsonb default '{}';
  alter table candidate_applications add column if not exists pre_offer_sent boolean default false;
  alter table candidate_applications add column if not exists pre_offer_sent_at text default '';
  alter table candidate_applications add column if not exists department text default '';
  alter table candidate_applications add column if not exists designation text default '';

  create table if not exists app_users (
    email text primary key,
    name text default '',
    employee_id text default '',
    designation text default '',
    role text default 'Employee',
    active boolean default true,
    password text default '',
    leave_allocation integer default 21,
    reporting_manager text default '',
    mobile text default '',
    address text default '',
    date_of_joining text default ''
  );

  -- If the table already exists, add missing columns:
  alter table app_users add column if not exists password text default '';
  alter table app_users add column if not exists leave_allocation integer default 21;
  alter table app_users add column if not exists reporting_manager text default '';
  alter table app_users add column if not exists mobile text default '';
  alter table app_users add column if not exists address text default '';
  alter table app_users add column if not exists date_of_joining text default '';
  alter table app_users add column if not exists el_avail_requested_at text default '';
  alter table app_users add column if not exists el_last_availed_at text default '';
  alter table app_users add column if not exists gross_pay numeric default 0;
  alter table app_users add column if not exists onroll_requested_at text default '';
  alter table app_users add column if not exists onroll_hr_status text default 'pending';
  alter table app_users add column if not exists onroll_hr_comment text default '';
  alter table app_users add column if not exists onroll_hr_decided_at text default '';
  alter table app_users add column if not exists onroll_manager_status text default 'pending';
  alter table app_users add column if not exists onroll_manager_comment text default '';
  alter table app_users add column if not exists onroll_manager_decided_at text default '';
  alter table app_users add column if not exists onroll_management_status text default 'pending';
  alter table app_users add column if not exists onroll_management_comment text default '';
  alter table app_users add column if not exists onroll_management_decided_at text default '';
  alter table app_users add column if not exists work_location text default '';
  alter table app_users add column if not exists work_location_pending text default '';
  alter table app_users add column if not exists work_location_requested_at text default '';
  alter table app_users add column if not exists department text default '';
  alter table app_users add column if not exists reporting_manager_pending text default '';
  alter table app_users add column if not exists reporting_manager_requested_at text default '';
  alter table app_users add column if not exists is_reporting_manager boolean default false;
  alter table app_users add column if not exists is_reporting_manager_pending boolean default false;
  alter table app_users add column if not exists date_of_birth text default '';
  -- 'FOMRA Developers' | 'FOMRA Housing' — which company this employee
  -- belongs to; '' = not yet classified by HR. HR sets it once directly;
  -- changing an already-set value requires Management approval, same
  -- pattern as work_location.
  alter table app_users add column if not exists business_unit text default '';
  alter table app_users add column if not exists business_unit_pending text default '';
  alter table app_users add column if not exists business_unit_requested_at text default '';
  alter table app_users add column if not exists is_reporting_manager_requested_at text default '';

  -- One-time backfill: existing Manager-role users must keep RM-dropdown
  -- eligibility now that eligibility is flag-based, not role-based.
  update app_users set is_reporting_manager = true where role = 'Manager' and is_reporting_manager = false;

  create table if not exists tasks (
    id text primary key,
    name text default '',
    description text default '',
    priority text default 'medium',
    start_date date not null,
    due_date date not null,
    weightage integer default 0,
    status text default 'assigned',
    assigned_employee text default '',
    team_members text default '',
    team_member_statuses text default '{}',
    department text default '',
    attachment text default ''
  );

  -- If the table already exists, add the new column:
  alter table tasks add column if not exists team_member_statuses text default '{}';

  create table if not exists onboarding_form_versions (
    id uuid default gen_random_uuid() primary key,
    created_at timestamptz default now(),
    created_by text default '',
    status text default 'pending',
    form_config jsonb not null default '{}',
    version_number integer default 1,
    approved_at timestamptz,
    approved_by text default '',
    rejection_note text default ''
  );
  alter table onboarding_form_versions disable row level security;
  alter table onboarding_forms add column if not exists mother_name text default '';
  alter table onboarding_forms add column if not exists aadhar_url text default '';
  alter table onboarding_forms add column if not exists attachments jsonb default '[]';
  alter table onboarding_forms add column if not exists mother_name text default '';

  -- Disable Row Level Security for development (enable and add policies for production)
  alter table leave_applications disable row level security;
  alter table maintenance_tickets disable row level security;
  alter table employee_profiles   disable row level security;
  alter table employees           disable row level security;
  alter table candidate_applications disable row level security;
  alter table app_users           disable row level security;
  alter table tasks               disable row level security;
  alter table app_settings        disable row level security;
  alter table payslip_requests    disable row level security;
  alter table payslips            disable row level security;

  -- Onboarding workflow columns (run if table already exists):
  alter table onboarding_forms add column if not exists status text default 'pending';
  alter table onboarding_forms add column if not exists hr_comment text default '';
  alter table onboarding_forms add column if not exists assigned_email text default '';
  alter table onboarding_forms add column if not exists assigned_emp_id text default '';
  alter table onboarding_forms add column if not exists assigned_manager text default '';
  alter table onboarding_forms add column if not exists assigned_department text default '';
  alter table onboarding_forms add column if not exists assigned_designation text default '';
  -- 'Employee' | 'Manager' | 'HR' — the account role HR/Management picks
  -- when assigning fields; Management is excluded since it's not created
  -- through recruitment (see role_hierarchy notes elsewhere).
  alter table onboarding_forms add column if not exists assigned_role text default 'Employee';

  -- Per-stage timestamps for the onboarding pipeline shown on the Employee
  -- Onboarding dashboard. `status` now also takes: sent_back, hr_denied,
  -- mgmt_denied, hr_approved, mgmt_approved, activation_sent,
  -- password_created, access_granted — each stage below is only stamped
  -- once, the first time the row reaches it.
  alter table onboarding_forms add column if not exists forwarded_at timestamptz;
  alter table onboarding_forms add column if not exists mgmt_approved_at timestamptz;
  alter table onboarding_forms add column if not exists activation_sent_at timestamptz;
  alter table onboarding_forms add column if not exists password_created_at timestamptz;
  alter table onboarding_forms add column if not exists account_active_at timestamptz;

  create table if not exists attendance_records (
    id text primary key,
    employee_name text not null,
    employee_id text default '',
    date text not null,
    check_in_time text default '',
    check_out_time text default '',
    created_at timestamptz default now()
  );
  alter table attendance_records disable row level security;
  alter table attendance_records add column if not exists check_in_note text default '';
  alter table attendance_records add column if not exists check_out_note text default '';
  alter table attendance_records add column if not exists location text default '';
  alter table attendance_records add column if not exists gps_points jsonb;
  -- Selfie columns + the private storage bucket + its RLS policies + the
  -- retention cron are defined in
  -- supabase/migrations/20260716020000_attendance_selfies.sql — run that
  -- migration rather than adding these columns by hand.
  alter table attendance_records add column if not exists check_in_selfie_path text default '';
  alter table attendance_records add column if not exists check_out_selfie_path text default '';

  create table if not exists form_versions (
    id uuid default gen_random_uuid() primary key,
    created_at timestamptz default now(),
    created_by text default '',
    status text default 'pending',
    form_config jsonb not null default '{}',
    version_number integer default 1,
    approved_at timestamptz,
    approved_by text default '',
    rejection_note text default ''
  );
  alter table form_versions disable row level security;

  create table if not exists notifications (
    id uuid default gen_random_uuid() primary key,
    created_at timestamptz default now(),
    type text not null,
    title text not null,
    body text default '',
    route text default '',
    target_email text default '',
    target_role text default '',
    target_reporting_manager text default '',
    source_id text default '',
    read_by jsonb default '[]'
  );
  alter table notifications disable row level security;
  create index if not exists idx_notifications_email on notifications(target_email);
  create index if not exists idx_notifications_role  on notifications(target_role);
  create index if not exists idx_notifications_rm    on notifications(target_reporting_manager);

  -- Retention: rows older than 20 days are pruned daily via pg_cron — the
  -- app's "All time" filter only ever shows what's still in the table, it
  -- doesn't assume full history is retained.
  create extension if not exists pg_cron with schema extensions;
  select cron.schedule(
    'delete-old-notifications',
    '0 3 * * *',
    $$ delete from notifications where created_at < now() - interval '20 days' $$
  );

  create table if not exists notification_preferences (
    email text primary key,
    muted_categories jsonb default '[]'
  );
  alter table notification_preferences disable row level security;

  -- Push notifications (FCM) — one row per signed-in device. Keyed by the
  -- token itself (not email+platform) so re-registering the same device
  -- after a login on a different account cleanly replaces the old owner.
  create table if not exists device_tokens (
    token text primary key,
    email text not null,
    platform text not null, -- 'android' | 'web'
    updated_at timestamptz default now()
  );
  alter table device_tokens disable row level security;

  -- Fires the send-push Edge Function on every new notification row, so
  -- every existing NotificationService._create() call site gets push for
  -- free without any code changes on the Flutter side.
  create extension if not exists pg_net with schema extensions;
  create or replace function notify_push() returns trigger as $$
  begin
    perform net.http_post(
      url := 'https://jjkijnmrtkkukdboajxu.functions.supabase.co/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impqa2lqbm1ydGtrdWtkYm9hanh1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIxMTE0NDMsImV4cCI6MjA5NzY4NzQ0M30.6I2swrTQDDT0phQvRqDkLFFo_BxtmxD3NE9R8lDbDeI'
      ),
      body := jsonb_build_object('record', row_to_json(new))
    );
    return new;
  end;
  $$ language plpgsql;

  drop trigger if exists notifications_push_trigger on notifications;
  create trigger notifications_push_trigger
    after insert on notifications
    for each row execute function notify_push();

  -- Employee performance appraisal forms (Task Management → Performance
  -- Management). One row per filled form per employee; history = every row
  -- for that employee_email, newest first.
  create table if not exists appraisal_forms (
    id text primary key,
    employee_email text not null,
    employee_id text default '',
    employee_name text default '',
    status text not null default 'draft', -- 'draft' | 'completed'
    moved_to_salary_hike boolean not null default false,
    data jsonb not null default '{}',
    created_by text default '',
    last_edited_by text default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );
  create index if not exists appraisal_forms_employee_idx on appraisal_forms (employee_email);
  alter table appraisal_forms disable row level security;

  -- KRA (Key Result Areas) documents HR or Management upload per employee.
  -- One row per uploaded file; history = every row for that employee_email,
  -- newest first. Files themselves live in the existing RESUME storage
  -- bucket under kra_uploads/.
  --
  -- HR uploads start 'pending' and only reach the employee once Management
  -- approves (see kra_approvals_page.dart); Management's own uploads are
  -- saved as 'approved' directly (no self-review needed).
  create table if not exists kra_documents (
    id text primary key,
    employee_email text not null,
    employee_name text default '',
    file_name text default '',
    file_url text default '',
    uploaded_by text default '',
    uploaded_at timestamptz not null default now(),
    status text not null default 'pending', -- 'pending' | 'approved' | 'rejected'
    decided_by text default '',
    decided_at timestamptz,
    review_note text default ''
  );
  create index if not exists kra_documents_employee_idx on kra_documents (employee_email);
  alter table kra_documents disable row level security;

  -- Run this instead if kra_documents already exists from before the approval workflow:
  -- alter table kra_documents add column if not exists status text not null default 'pending';
  -- alter table kra_documents add column if not exists decided_by text default '';
  -- alter table kra_documents add column if not exists decided_at timestamptz;
  -- alter table kra_documents add column if not exists review_note text default '';

  -- ── Post-approval recruitment email workflow ──────────────────────────
  -- Pre-Offer Letter (PDF + secure accept token) → Onboarding Form (secure
  -- token link) → HR field assignment (already existed) → Management
  -- approval → token-based account activation (no password emailed).

  alter table candidate_applications add column if not exists pre_offer_token text default '';
  alter table candidate_applications add column if not exists pre_offer_token_created_at text default '';
  alter table candidate_applications add column if not exists pre_offer_accepted boolean default false;
  alter table candidate_applications add column if not exists pre_offer_accepted_at text default '';
  alter table candidate_applications add column if not exists onboarding_token text default '';
  alter table candidate_applications add column if not exists onboarding_link_sent boolean default false;
  alter table candidate_applications add column if not exists onboarding_link_sent_at text default '';
  alter table candidate_applications add column if not exists onboarding_completed boolean default false;
  alter table candidate_applications add column if not exists onboarding_completed_at text default '';

  -- Nullable FK: token-based onboarding submissions set this; older
  -- anonymous submissions stay null and keep resolving via the existing
  -- fuzzy name/mobile match in employee_onboarding_page.dart.
  alter table onboarding_forms add column if not exists candidate_application_id uuid references candidate_applications(id);

  -- 24h expiring token for the "Set Your Password" activation link.
  alter table app_users add column if not exists activation_token text default '';
  alter table app_users add column if not exists activation_token_expires_at text default '';

  -- Company-issued Microsoft/Office 365 mailbox, set by HR — "Forgot
  -- Password" reset links go here, never the personal or login email.
  alter table app_users add column if not exists company_email text default '';
  alter table app_users add column if not exists reset_password_token text default '';
  alter table app_users add column if not exists reset_password_token_expires_at text default '';

  create table if not exists email_logs (
    id uuid default gen_random_uuid() primary key,
    template_name text not null,
    recipient text not null,
    subject text default '',
    html_body text default '',
    variables jsonb default '{}',
    attachments jsonb default '[]',
    status text default 'pending', -- 'pending' | 'sent' | 'failed'
    created_at timestamptz default now(),
    sent_at timestamptz,
    error_message text default '',
    retry_count integer default 0,
    related_candidate_id uuid,
    related_onboarding_id uuid
  );
  alter table email_logs disable row level security;
  create index if not exists idx_email_logs_recipient on email_logs(recipient);
  create index if not exists idx_email_logs_status on email_logs(status);

  -- Lets the HR portal reflect offer acceptance live without a manual refresh.
  alter publication supabase_realtime add table candidate_applications;
*/

/// Result of [SupabaseService.login] — see supabase/functions/login/index.ts.
class LoginResult {
  final bool ok;
  final bool needsPasswordSetup;
  final bool notActivated;
  final String? error;
  final Map<String, dynamic>? profile;

  const LoginResult({
    this.ok = false,
    this.needsPasswordSetup = false,
    this.notActivated = false,
    this.error,
    this.profile,
  });
}

class SupabaseService {

  /// Reports a write that failed instead of discarding it.
  ///
  /// Every write in this file used to end in `catch (_) {}`. That is how leave
  /// requests disappeared: RLS rejected the insert, the exception was thrown
  /// away, and the UI went on to show a success message and raise a
  /// notification for a row that did not exist. The screen and the database
  /// disagreed and nothing anywhere said so.
  ///
  /// Swallowing is still the behaviour — these calls are mostly fire-and-forget
  /// and throwing would surface as an unhandled async error rather than
  /// anything a user sees — but the failure is now visible in the browser
  /// console and recorded, so the next one is diagnosable in minutes rather
  /// than by tracing a user complaint back through the code.
  static void _writeFailed(String operation, Object error) {
    // ignore: avoid_print
    print('[write-failed] $operation: $error');
    lastWriteFailure = '$operation: $error';
    // Fire-and-forget, with the error explicitly absorbed. Without the
    // .catchError this would be an unawaited Future whose rejection becomes an
    // unhandled async error — replacing one silent failure with a noisier one.
    try {
      _db
          ?.from('audit_log')
          .insert({
            'action': 'write_failed',
            'actor_email': UserSession.email,
            'actor_role': UserSession.role.name,
            'target_type': 'supabase_service',
            'target_id': operation,
            'details': {'error': error.toString()},
          })
          .catchError((_) {});
    } catch (_) {
      // Auditing must never itself block or recurse.
    }
  }

  /// Most recent write failure, for surfacing in the UI where a user is
  /// waiting on the result.
  static String? lastWriteFailure;
  static SupabaseClient? get _db {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  // main.dart deliberately renders the app before Supabase.initialize()
  // finishes (so the splash screen clears instantly), which leaves a short
  // window where _db is null and any query silently comes back empty
  // instead of erroring — e.g. a fast click into "Forward to Management"
  // right after a page load could see an empty reporting-managers list for
  // no visible reason. main() completes this once initialize() settles
  // (success or failure); [awaitReady] lets a handful of early, easy-to-hit
  // queries wait that out instead of racing it.
  static final Completer<void> _readyCompleter = Completer<void>();
  static void markReady() {
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  static Future<void> awaitReady() =>
      _readyCompleter.future.timeout(const Duration(seconds: 8), onTimeout: () {});

  // ── Leave Applications ────────────────────────────────────────────────

  static Future<void> saveLeaveApplication(LeaveApplication app) async {
    // Core upsert — only columns that exist in the original schema
    try {
      await _db?.from('leave_applications').upsert({
        'id':             app.id,
        'employee_name':  app.employeeName,
        // Was omitted entirely. RLS on leave_applications gates writes on
        // employee_id (or the employee's own name), so with this blank an
        // ordinary employee's insert was REJECTED — and the catch below
        // swallowed it, so the UI reported success and raised a notification
        // while nothing was written. Leave requests silently vanished.
        'employee_id':    UserSession.employeeId,
        'department':     app.department,
        'leave_type':     app.leaveType,
        'from_date':      app.from.toIso8601String().substring(0, 10),
        'to_date':        app.to.toIso8601String().substring(0, 10),
        'days':           app.days,
        'reason':         app.reason,
        'applied_on':     app.appliedOn.toIso8601String(),
        'manager_status': app.managerStatus.name,
      });
    } catch (e) {
      // NEVER swallow this again. A rejected write here means the employee's
      // leave request does not exist, while every other signal — the snackbar,
      // the notification — says it does.
      // Deliberately not rethrown: three of the five call sites do not await
      // this, so a rethrow would become an unhandled async error rather than
      // anything the employee sees. Logged loudly instead — the silent
      // `catch (_) {}` here is what let leave requests vanish while the UI
      // reported success.
      // ignore: avoid_print
      print('saveLeaveApplication FAILED for ${app.employeeName}: $e');
    }
    // is_half_day / proof_url / leave_bucket — added later; skipped silently if columns not yet in DB
    try {
      await _db?.from('leave_applications')
          .update({'is_half_day': app.isHalfDay})
          .eq('id', app.id);
    } catch (e) { _writeFailed('saveLeaveApplication', e); }
    try {
      await _db?.from('leave_applications')
          .update({'proof_url': app.proofUrl})
          .eq('id', app.id);
    } catch (e) { _writeFailed('saveLeaveApplication', e); }
    try {
      await _db?.from('leave_applications')
          .update({'leave_bucket': app.leaveBucket})
          .eq('id', app.id);
    } catch (e) { _writeFailed('saveLeaveApplication', e); }
    logAuditEvent('leave_application_saved', targetType: 'leave_applications', targetId: app.id);
  }

  static Future<void> updateLeaveManagerStatus(
      String id, LeaveApprovalStatus status,
      {String decidedBy = '', String rejectionComment = ''}) async {
    try {
      await _db?.from('leave_applications').update({
        'manager_status':    status.name,
        'decided_by':        decidedBy,
        'rejection_comment': rejectionComment,
      }).eq('id', id);
      logAuditEvent('leave_manager_decision', targetType: 'leave_applications', targetId: id,
          details: {'status': status.name});
    } catch (e) { _writeFailed('updateLeaveManagerStatus', e); }
  }

  /// Called when management (HR/admin) approves or denies — writes to the
  /// separate management columns so the manager's decision is never overwritten.
  static Future<void> updateLeaveManagementStatus(
      String id, LeaveApprovalStatus status,
      {String decidedBy = '', String rejectionComment = ''}) async {
    try {
      await _db?.from('leave_applications').update({
        'management_status':            status.name,
        'management_decided_by':        decidedBy,
        'management_rejection_comment': rejectionComment,
      }).eq('id', id);
      logAuditEvent('leave_management_decision', targetType: 'leave_applications', targetId: id,
          details: {'status': status.name});
    } catch (e) { _writeFailed('updateLeaveManagementStatus', e); }
  }

  static Future<List<LeaveApplication>> fetchLeaveApplications() async {
    try {
      final data = await _db
          ?.from('leave_applications')
          .select()
          .order('applied_on', ascending: false);
      if (data == null) return [];
      final list = (data as List).map((row) {
        final app = LeaveApplication(
          id:           row['id'] as String,
          employeeName: row['employee_name'] as String,
          department:   (row['department'] as String?) ?? '',
          leaveType:    (row['leave_type'] as String?) ?? '',
          from:         DateTime.parse(row['from_date'] as String),
          to:           DateTime.parse(row['to_date'] as String),
          days:         row['days'] as int,
          reason:       (row['reason'] as String?) ?? '',
          appliedOn:    DateTime.parse(row['applied_on'] as String),
        );
        // Prefer management_status if set — it overrides manager decision and locks manager controls
        final mgmtStatus = _parseStatus(row['management_status']);
        if (mgmtStatus != LeaveApprovalStatus.pending) {
          app.managementDecided = true;
          app.managerStatus    = mgmtStatus;
          app.decidedBy        = (row['management_decided_by']        as String?) ?? '';
          app.rejectionComment = (row['management_rejection_comment'] as String?) ?? '';
        } else {
          app.managerStatus    = _parseStatus(row['manager_status']);
          app.decidedBy        = (row['decided_by']        as String?) ?? '';
          app.rejectionComment = (row['rejection_comment'] as String?) ?? '';
        }
        app.isHalfDay   = (row['is_half_day'] as bool?) ?? false;
        app.proofUrl    = (row['proof_url']  as String?) ?? '';
        app.leaveBucket = (row['leave_bucket'] as String?) ?? '';
        return app;
      }).toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  static LeaveApprovalStatus _parseStatus(dynamic val) =>
      LeaveApprovalStatus.values.firstWhere(
        (s) => s.name == ((val as String?) ?? 'pending'),
        orElse: () => LeaveApprovalStatus.pending,
      );

  // ── Maintenance Tickets ───────────────────────────────────────────────

  static Future<String?> saveMaintenanceTicket(MaintenanceTicket ticket) async {
    try {
      await _db?.from('maintenance_tickets').upsert({
        'id':                   ticket.id,
        'reported_by_role':     ticket.reportedByRole.name,
        'reported_by':          ticket.reportedBy,
        'issue_for':            ticket.issueFor,
        'issue_type':           ticket.issueType,
        'description':          ticket.description,
        'priority':             ticket.priority,
        'status':               ticket.status.name,
        'sent_to_management':   ticket.sentToManagement,
        'management_reviewed':  ticket.managementReviewed,
        'send_to_management_note': ticket.sendToManagementNote,
        'resolution_note':      ticket.resolutionNote,
        'resolved_at':          ticket.resolvedAt?.toIso8601String(),
        'created_at':           ticket.createdAt.toIso8601String(),
        'attachment_url':       ticket.attachmentUrl,
        'attachment_name':      ticket.attachmentName,
      });
      return null;
    } catch (_) {
      return 'Could not save the maintenance ticket. Please try again.';
    }
  }

  // Sending (or re-sending) to Management always resets management_reviewed
  // to false, so the ticket lands back in Management's "awaiting review"
  // queue rather than being mistaken for one they've already sent back.
  static Future<void> updateTicketSentToManagement(String id, bool sent, {String? note}) async {
    try {
      final payload = <String, dynamic>{'sent_to_management': sent};
      if (sent) {
        payload['management_reviewed'] = false;
        payload['send_to_management_note'] = note;
      }
      await _db?.from('maintenance_tickets')
          .update(payload)
          .eq('id', id);
    } catch (e) { _writeFailed('updateTicketSentToManagement', e); }
  }

  static Future<void> updateTicketStatus(
      String id, MaintenanceStatus status) async {
    try {
      await _db
          ?.from('maintenance_tickets')
          .update({'status': status.name})
          .eq('id', id);
    } catch (e) { _writeFailed('updateTicketStatus', e); }
  }

  static Future<void> updateTicketManagementReviewed(String id, bool reviewed) async {
    try {
      await _db?.from('maintenance_tickets')
          .update({'management_reviewed': reviewed})
          .eq('id', id);
    } catch (e) { _writeFailed('updateTicketManagementReviewed', e); }
  }

  static Future<void> updateTicketResolution(
      String id, String note, DateTime resolvedAt) async {
    try {
      await _db?.from('maintenance_tickets').update({
        'status':          MaintenanceStatus.resolved.name,
        'resolution_note': note,
        'resolved_at':     resolvedAt.toIso8601String(),
      }).eq('id', id);
    } catch (e) { _writeFailed('updateTicketResolution', e); }
  }

  static Future<List<MaintenanceTicket>> fetchMaintenanceTickets() async {
    try {
      final data = await _db
          ?.from('maintenance_tickets')
          .select()
          .order('created_at', ascending: false);
      if (data == null) return [];
      return (data as List).map((row) {
        final roleStr = (row['reported_by_role'] as String?) ?? 'employee';
        final role = UserRole.values.firstWhere(
          (r) => r.name == roleStr,
          orElse: () => UserRole.employee,
        );
        final statusStr = (row['status'] as String?) ?? 'open';
        final status = MaintenanceStatus.values.firstWhere(
          (s) => s.name == statusStr,
          orElse: () => MaintenanceStatus.open,
        );
        return MaintenanceTicket(
          id:                 row['id'] as String,
          reportedByRole:     role,
          reportedBy:         row['reported_by'] as String,
          issueFor:           (row['issue_for'] as String?) ?? 'IT',
          issueType:          row['issue_type'] as String,
          description:        row['description'] as String,
          priority:           (row['priority'] as String?) ?? 'Medium',
          status:             status,
          sentToManagement:   (row['sent_to_management'] as bool?) ?? false,
          managementReviewed: (row['management_reviewed'] as bool?) ?? false,
          sendToManagementNote: row['send_to_management_note'] as String?,
          resolutionNote:     row['resolution_note'] as String?,
          resolvedAt:         row['resolved_at'] != null
              ? DateTime.parse(row['resolved_at'] as String)
              : null,
          createdAt:          DateTime.parse(row['created_at'] as String),
          attachmentUrl:      row['attachment_url'] as String?,
          attachmentName:     row['attachment_name'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Employee Profiles ─────────────────────────────────────────────────

  static Future<void> saveProfile(ProfileData data) async {
    try {
      await _db?.from('employee_profiles').upsert({
        'employee_id':       data.employeeId,
        'full_name':         data.fullName,
        'mobile':            data.mobile,
        'email':             data.email,
        'address':           data.address,
        'department':        data.department,
        'designation':       data.designation,
        'reporting_manager': data.reportingManager,
        'date_of_joining':   data.dateOfJoining,
      });
    } catch (e) { _writeFailed('saveProfile', e); }
  }

  static Future<List<ProfileData>> fetchProfiles() async {
    try {
      final data = await _db?.from('employee_profiles').select();
      if (data == null) return [];
      return (data as List).map((row) => ProfileData(
        employeeId:       (row['employee_id'] as String?) ?? '',
        fullName:         (row['full_name'] as String?) ?? '',
        mobile:           (row['mobile'] as String?) ?? '',
        email:            (row['email'] as String?) ?? '',
        address:          (row['address'] as String?) ?? '',
        department:       (row['department'] as String?) ?? '',
        designation:      (row['designation'] as String?) ?? '',
        reportingManager: (row['reporting_manager'] as String?) ?? '',
        dateOfJoining:    (row['date_of_joining'] as String?) ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Employees ─────────────────────────────────────────────────────────

  static Future<void> saveEmployee(Employee emp) async {
    try {
      await _db?.from('employees').upsert({
        'id':              emp.id,
        'name':            emp.name,
        'department':      emp.department,
        'designation':     emp.designation,
        'mobile':          emp.mobile,
        'email':           emp.email,
        'address':         emp.address,
        'blood_group':     emp.bloodGroup,
        'manager':         emp.manager,
        'joining_date':    emp.joiningDate,
        'salary':          emp.salary,
        'emergency_name':  emp.emergencyName,
        'emergency_phone': emp.emergencyPhone,
        'bank_account':    emp.bankAccount,
        'ifsc':            emp.ifsc,
      });
    } catch (e) { _writeFailed('saveEmployee', e); }
  }

  static Future<List<Employee>> fetchEmployees() async {
    try {
      final data = await _db?.from('employees').select().order('name');
      if (data == null) return [];
      return (data as List).map((row) => Employee(
        id:            row['id'] as String,
        name:          row['name'] as String,
        department:    (row['department'] as String?) ?? '',
        designation:   (row['designation'] as String?) ?? '',
        mobile:        (row['mobile'] as String?) ?? '',
        email:         (row['email'] as String?) ?? '',
        address:       (row['address'] as String?) ?? '',
        bloodGroup:    (row['blood_group'] as String?) ?? '',
        manager:       (row['manager'] as String?) ?? '',
        joiningDate:   (row['joining_date'] as String?) ?? '',
        salary:        (row['salary'] as String?) ?? '',
        emergencyName: (row['emergency_name'] as String?) ?? '',
        emergencyPhone:(row['emergency_phone'] as String?) ?? '',
        bankAccount:   (row['bank_account'] as String?) ?? '',
        ifsc:          (row['ifsc'] as String?) ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Resume Upload ─────────────────────────────────────────────────────
  //
  // The RESUME and 'onboarding attachments' buckets went private in
  // supabase/migrations/20260716000200_document_buckets.sql — getPublicUrl
  // no longer works on them (the bucket rejects unsigned/anon reads).
  // Uploads now return the bare storage path instead of a URL; callers must
  // resolve it to a short-lived signed URL immediately before displaying or
  // opening it, via [resolveAttachmentUrl] — never store the signed URL
  // itself, since it expires.

  /// Resolves a stored attachment reference — either a bare storage path
  /// (new uploads) or a legacy public URL (rows written before the bucket
  /// went private, in which case the bucket/path are parsed back out of the
  /// URL itself, so no DB backfill is needed) — into a fresh signed URL.
  /// [bucket] is required for bare paths; ignored (and inferred instead)
  /// for legacy URLs.
  static Future<String?> resolveAttachmentUrl(
    String stored, {
    String? bucket,
    int expiresIn = 3600,
  }) async {
    final db = _db;
    if (db == null || stored.isEmpty) return null;
    var resolvedBucket = bucket ?? '';
    var path = stored;
    const marker = '/object/public/';
    final idx = stored.indexOf(marker);
    if (idx != -1) {
      final rest = stored.substring(idx + marker.length); // '<bucket>/<path...>'
      final slash = rest.indexOf('/');
      if (slash != -1) {
        resolvedBucket = Uri.decodeComponent(rest.substring(0, slash));
        path = Uri.decodeComponent(rest.substring(slash + 1));
      }
    } else if (stored.startsWith('http')) {
      // Not a recognized public-URL shape (e.g. already a signed URL) —
      // nothing left to do but hand it back as-is.
      return stored;
    }
    if (resolvedBucket.isEmpty) return null;
    try {
      return await db.storage.from(resolvedBucket).createSignedUrl(path, expiresIn);
    } catch (_) {
      return null;
    }
  }

  // Throws on failure so callers can surface the error to the user.
  static Future<String> uploadResume(
      Uint8List bytes, String fileName, String mimeType) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = '${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _db!.storage.from('RESUME').uploadBinary(
      path, bytes,
      fileOptions: FileOptions(
          contentType: mimeType.isNotEmpty ? mimeType : 'application/octet-stream'),
    );
    return path;
  }

  // Custom field file uploads (PDF / image) — stored in the RESUME bucket under custom_uploads/.
  // Throws on failure so callers can surface the error to the user.
  static Future<String> uploadFile(
      Uint8List bytes, String fileName, String mimeType) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'custom_uploads/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _db!.storage.from('RESUME').uploadBinary(
      path, bytes,
      fileOptions: FileOptions(
          contentType: mimeType.isNotEmpty ? mimeType : 'application/octet-stream'),
    );
    return path;
  }

  // ── Attendance Selfies ────────────────────────────────────────────────
  // Private bucket — see supabase/migrations/20260716020000_attendance_selfies.sql
  // for the bucket + RLS policies (upload = own employee_id folder only,
  // read = HR/Management only) and supabase/migrations/20260717000000_selfie_45day_retention.sql
  // for the 45-day retention window (both the purge cron and the RLS
  // policy itself refuse anything older). Never use getPublicUrl on this bucket.

  static const _selfieBucket = 'attendance-selfies';

  /// Uploads an already-watermarked, already-compressed selfie and returns
  /// its storage path (not a URL) for storing on the attendance row, or
  /// null on failure.
  static Future<String?> uploadAttendanceSelfie({
    required String employeeId,
    required String date, // 'dd/MM/yyyy'
    required String kind, // 'checkin' | 'checkout'
    required Uint8List bytes,
  }) async {
    final db = _db;
    if (db == null || employeeId.isEmpty) return null;
    final safeDate = date.replaceAll('/', '-');
    final path =
        '$employeeId/${safeDate}_${kind}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await db.storage.from(_selfieBucket).uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
      return path;
    } catch (_) {
      return null;
    }
  }

  /// Short-lived signed URL for an HR/Management viewer — storage RLS
  /// rejects this for any caller who isn't HR/Management, regardless of
  /// what the client claims, so this must only ever be called from those
  /// screens (never from the employee's own attendance view).
  static Future<String?> attendanceSelfieUrl(String path) async {
    final db = _db;
    if (db == null || path.isEmpty) return null;
    // Deliberately not caught here — the caller (HR attendance records page)
    // shows the real error message so a permission/RLS/network failure is
    // distinguishable from "no selfie was ever taken" instead of both
    // rendering as the same generic broken-camera icon.
    return await db.storage.from(_selfieBucket).createSignedUrl(path, 3600);
  }

  // ── Candidate Applications ────────────────────────────────────────────

  static Future<void> saveCandidateApplication(Map<String, dynamic> data) async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized. Please refresh and try again.');
    await db.from('candidate_applications').insert(data);
  }

  static Future<List<Map<String, dynamic>>> fetchCandidateApplications() async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized.');
    final data = await db
        .from('candidate_applications')
        .select()
        .order('submitted_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  // verify: when true, confirms the row was actually updated (RLS silently
  // no-ops a blocked update instead of throwing) and throws if not — used
  // before emailing a candidate a token, so a broken write can't produce a
  // link that was sent but never actually saved.
  static Future<void> updateCandidateStatus(
      String id, Map<String, dynamic> fields, {bool verify = false}) async {
    final db = _db;
    if (db == null) return;
    if (verify) {
      final rows = await db.from('candidate_applications').update(fields).eq('id', id).select();
      if (rows.isEmpty) {
        throw Exception('Update was not applied — you may not have permission, or the candidate record no longer exists.');
      }
      return;
    }
    await db.from('candidate_applications').update(fields).eq('id', id);
  }

  static Future<void> deleteCandidateApplication(String id) async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized.');
    await db.from('candidate_applications').delete().eq('id', id);
  }

  // ── App Users (Administration) ────────────────────────────────────────

  // Explicit column list — deliberately excludes password/password_hash and
  // the activation/reset token columns. This used to be a bare .select(),
  // which shipped every employee's plaintext password (and pending reset
  // tokens) to any logged-in client fetching the roster; has_password is a
  // generated boolean column, never the hash itself.
  static const _appUserColumns =
      'name, email, employee_id, designation, department, '
      'business_unit, business_unit_pending, business_unit_requested_at, '
      'weekly_off_day, weekly_off_day_pending, weekly_off_day_requested_at, '
      'role, active, has_password, leave_allocation, '
      'reporting_manager, reporting_manager_pending, reporting_manager_requested_at, '
      'is_reporting_manager, is_reporting_manager_pending, is_reporting_manager_requested_at, '
      'mobile, address, date_of_birth, date_of_joining, '
      'onroll_confirmed_at, onroll_requested_at, '
      'onroll_hr_status, onroll_hr_comment, onroll_hr_decided_at, '
      'onroll_manager_status, onroll_manager_comment, onroll_manager_decided_at, '
      'onroll_management_status, onroll_management_comment, onroll_management_decided_at, '
      'el_eligible_at, el_avail_requested_at, el_last_availed_at, '
      'gross_pay, gross_pay_pending, gross_pay_requested_at, '
      'work_location, work_location_pending, work_location_requested_at, '
      'permission_minutes_quota, permission_minutes_quota_pending, permission_minutes_quota_requested_at, '
      'company_email, email_pending, email_requested_at, '
      'exempt_from_timing, exempt_from_geofence, exempt_from_leave_rules, '
      'exempt_from_attendance, payroll_eligible, oversight_only';

  // Postgres `numeric` columns (gross_pay, gross_pay_pending, ...) come back
  // from PostgREST as JSON strings, not numbers — it does this to avoid
  // silently losing precision, since JSON numbers are doubles. `as num?`
  // throws on a String, which used to take down this entire row-mapping
  // pass (and, via the catch-all below, made the whole employee list
  // silently vanish) the moment any employee had a non-null gross pay.
  static double? _numFromJson(dynamic v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

  static Future<List<AppUser>> fetchAppUsers() async {
    try {
      await awaitReady();
      final data = await _db?.from('app_users').select(_appUserColumns).order('name');
      if (data == null) return [];
      return (data as List).map((row) => AppUser(
        name:                 (row['name']                    as String?) ?? '',
        email:                (row['email']                   as String?) ?? '',
        employeeId:           (row['employee_id']             as String?) ?? '',
        designation:          (row['designation']             as String?) ?? '',
        department:           (row['department']              as String?) ?? '',
        businessUnit:         (row['business_unit']           as String?) ?? '',
        businessUnitPending:      (row['business_unit_pending']      as String?) ?? '',
        businessUnitRequestedAt:  (row['business_unit_requested_at'] as String?) ?? '',
        weeklyOffDay:             (row['weekly_off_day']              as String?) ?? '',
        weeklyOffDayPending:      (row['weekly_off_day_pending']       as String?) ?? '',
        weeklyOffDayRequestedAt:  (row['weekly_off_day_requested_at']  as String?) ?? '',
        role:                 (row['role']                    as String?) ?? 'Employee',
        active:               (row['active']                  as bool?)   ?? true,
        hasPassword:          (row['has_password']            as bool?)   ?? false,
        leaveAllocation:      (row['leave_allocation']        as int?)    ?? 21,
        reportingManager:     (row['reporting_manager']       as String?) ?? '',
        reportingManagerPending:     (row['reporting_manager_pending']       as String?) ?? '',
        reportingManagerRequestedAt: (row['reporting_manager_requested_at']  as String?) ?? '',
        isReportingManager:            (row['is_reporting_manager']            as bool?)   ?? false,
        isReportingManagerPending:     (row['is_reporting_manager_pending']    as bool?)   ?? false,
        isReportingManagerRequestedAt: (row['is_reporting_manager_requested_at'] as String?) ?? '',
        mobile:               (row['mobile']                  as String?) ?? '',
        address:              (row['address']                 as String?) ?? '',
        dateOfBirth:          (row['date_of_birth']           as String?) ?? '',
        dateOfJoining:        (row['date_of_joining']         as String?) ?? '',
        onrollConfirmedAt:    (row['onroll_confirmed_at']     as String?) ?? '',
        onrollRequestedAt:    (row['onroll_requested_at']     as String?) ?? '',
        onrollHrStatus:            (row['onroll_hr_status']            as String?) ?? 'pending',
        onrollHrComment:           (row['onroll_hr_comment']           as String?) ?? '',
        onrollHrDecidedAt:         (row['onroll_hr_decided_at']         as String?) ?? '',
        onrollManagerStatus:       (row['onroll_manager_status']       as String?) ?? 'pending',
        onrollManagerComment:      (row['onroll_manager_comment']      as String?) ?? '',
        onrollManagerDecidedAt:    (row['onroll_manager_decided_at']    as String?) ?? '',
        onrollManagementStatus:    (row['onroll_management_status']    as String?) ?? 'pending',
        onrollManagementComment:   (row['onroll_management_comment']   as String?) ?? '',
        onrollManagementDecidedAt: (row['onroll_management_decided_at'] as String?) ?? '',
        elEligibleAt:         (row['el_eligible_at']          as String?) ?? '',
        elAvailRequestedAt:   (row['el_avail_requested_at']   as String?) ?? '',
        elLastAvailedAt:      (row['el_last_availed_at']      as String?) ?? '',
        grossPay:             _numFromJson(row['gross_pay']) ?? 0,
        grossPayPending:      _numFromJson(row['gross_pay_pending']) ?? 0,
        grossPayRequestedAt:  (row['gross_pay_requested_at'] as String?) ?? '',
        workLocation:            (row['work_location']             as String?) ?? '',
        workLocationPending:     (row['work_location_pending']     as String?) ?? '',
        workLocationRequestedAt: (row['work_location_requested_at'] as String?) ?? '',
        permissionMinutesQuota:          (row['permission_minutes_quota'] as num?)?.toInt() ?? 120,
        permissionMinutesQuotaPending:   (row['permission_minutes_quota_pending'] as num?)?.toInt() ?? 0,
        permissionMinutesQuotaRequestedAt: (row['permission_minutes_quota_requested_at'] as String?) ?? '',
        companyEmail:         (row['company_email']           as String?) ?? '',
        exemptFromTiming:     (row['exempt_from_timing']      as bool?) ?? false,
        exemptFromGeofence:   (row['exempt_from_geofence']    as bool?) ?? false,
        exemptFromLeaveRules: (row['exempt_from_leave_rules'] as bool?) ?? false,
        exemptFromAttendance: (row['exempt_from_attendance']  as bool?) ?? false,
        payrollEligible:      (row['payroll_eligible']        as bool?) ?? true,
        oversightOnly:        (row['oversight_only']          as bool?) ?? false,
        emailPending:         (row['email_pending']           as String?) ?? '',
        emailRequestedAt:     (row['email_requested_at']      as String?) ?? '',
      )).toList();
    } catch (e, st) {
      // This used to fail totally silently — any parse/network/RLS error
      // here looked identical to "the company genuinely has zero
      // employees" everywhere that reads UserStore.load(), which made a
      // real bug indistinguishable from an empty result. Logging it doesn't
      // fix the underlying cause, but it means the next occurrence shows up
      // in the browser console instead of just an empty employee list.
      // ignore: avoid_print
      print('fetchAppUsers failed: $e\n$st');
      return [];
    }
  }

  static Future<void> upsertAppUser(AppUser u) async {
    await _db?.from('app_users').upsert({
      'email':                    u.email,
      'name':                     u.name,
      'employee_id':              u.employeeId,
      'designation':              u.designation,
      'department':               u.department,
      'business_unit':            u.businessUnit,
      'business_unit_pending':    u.businessUnitPending,
      'business_unit_requested_at': u.businessUnitRequestedAt,
      'weekly_off_day':            u.weeklyOffDay,
      'weekly_off_day_pending':    u.weeklyOffDayPending,
      'weekly_off_day_requested_at': u.weeklyOffDayRequestedAt,
      'role':                     u.role,
      'active':                   u.active,
      'leave_allocation':         u.leaveAllocation,
      'reporting_manager':        u.reportingManager,
      'reporting_manager_pending':        u.reportingManagerPending,
      'reporting_manager_requested_at':   u.reportingManagerRequestedAt,
      'is_reporting_manager':             u.isReportingManager,
      'is_reporting_manager_pending':     u.isReportingManagerPending,
      'is_reporting_manager_requested_at': u.isReportingManagerRequestedAt,
      'mobile':                   u.mobile,
      'address':                  u.address,
      'date_of_birth':            u.dateOfBirth,
      'date_of_joining':          u.dateOfJoining,
      'onroll_confirmed_at':      u.onrollConfirmedAt,
      'onroll_requested_at':      u.onrollRequestedAt,
      'onroll_hr_status':             u.onrollHrStatus,
      'onroll_hr_comment':            u.onrollHrComment,
      'onroll_hr_decided_at':         u.onrollHrDecidedAt,
      'onroll_manager_status':        u.onrollManagerStatus,
      'onroll_manager_comment':       u.onrollManagerComment,
      'onroll_manager_decided_at':    u.onrollManagerDecidedAt,
      'onroll_management_status':    u.onrollManagementStatus,
      'onroll_management_comment':   u.onrollManagementComment,
      'onroll_management_decided_at': u.onrollManagementDecidedAt,
      'el_eligible_at':           u.elEligibleAt,
      'el_avail_requested_at':    u.elAvailRequestedAt,
      'el_last_availed_at':       u.elLastAvailedAt,
      'gross_pay':                u.grossPay,
      'gross_pay_pending':        u.grossPayPending,
      'gross_pay_requested_at':   u.grossPayRequestedAt,
      'work_location':            u.workLocation,
      'work_location_pending':    u.workLocationPending,
      'work_location_requested_at': u.workLocationRequestedAt,
      'permission_minutes_quota':            u.permissionMinutesQuota,
      'permission_minutes_quota_pending':    u.permissionMinutesQuotaPending,
      'permission_minutes_quota_requested_at': u.permissionMinutesQuotaRequestedAt,
      'company_email':            u.companyEmail,
      // email / email_pending / email_requested_at are deliberately NOT written
      // here. trg_protect_login_email raises on any direct change to `email`,
      // and the pending columns are owned by the request/approve RPCs below.
    });
  }

  static Future<void> requestElAvail(String email) async {
    try {
      await _db?.from('app_users').update({
        'el_avail_requested_at': DateTime.now().toIso8601String(),
      }).eq('email', email);
    } catch (e) { _writeFailed('requestElAvail', e); }
  }

  static Future<void> confirmElAvail(String email) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _db?.from('app_users').update({
        'el_last_availed_at':    now,
        'el_avail_requested_at': '',
      }).eq('email', email);
    } catch (e) { _writeFailed('confirmElAvail', e); }
  }

  static Future<void> deleteAppUser(String email) async {
    try {
      await _db?.from('app_users').delete().eq('email', email);
    } catch (e) { _writeFailed('deleteAppUser', e); }
  }

  // ── Tasks ─────────────────────────────────────────────────────────────

  static Future<void> saveTask(Task task) async {
    try {
      await _db?.from('tasks').upsert(task.toJson());
    } catch (e) { _writeFailed('saveTask', e); }
  }

  static Future<void> deleteTask(String id) async {
    try {
      await _db?.from('tasks').delete().eq('id', id);
    } catch (e) { _writeFailed('deleteTask', e); }
  }

  // [note] is the reason given for completing a task after it went Delayed
  // (see MyTasksPage._onDone) — written to the completion_note column.
  // Falls back to a plain status update if that column doesn't exist yet
  // on this database, so completing a task never silently fails outright.
  static Future<void> updateTaskStatus(String id, TaskStatus status, {String? note}) async {
    if (note != null && note.isNotEmpty) {
      try {
        await _db?.from('tasks').update({
          'status': status.name,
          'completion_note': note,
        }).eq('id', id);
        return;
      } catch (e) { _writeFailed('updateTaskStatus', e); }
    }
    try {
      await _db?.from('tasks').update({'status': status.name}).eq('id', id);
    } catch (e) { _writeFailed('updateTaskStatus', e); }
  }

  static Future<void> updateTaskReceived(String id, DateTime receivedAt) async {
    try {
      await _db?.from('tasks').update({
        'status': TaskStatus.inProgress.name,
        'received_at': receivedAt.toIso8601String(),
      }).eq('id', id);
    } catch (e) { _writeFailed('updateTaskReceived', e); }
  }

  // Updates one team member's status; if allCompleted, also flips overall
  // status. [note] is that member's reason for completing late (see
  // MyTasksPage._onGroupDone) — same completion_note column and fallback
  // as updateTaskStatus, since there's no per-member notes column.
  static Future<void> updateTeamMemberStatus(
      String taskId, Map<String, String> statuses, bool allCompleted, {String? note}) async {
    final update = <String, dynamic>{
      'team_member_statuses': jsonEncode(statuses),
    };
    if (allCompleted) update['status'] = TaskStatus.completed.name;
    if (note != null && note.isNotEmpty) {
      try {
        await _db?.from('tasks')
            .update({...update, 'completion_note': note}).eq('id', taskId);
        return;
      } catch (e) { _writeFailed('updateTeamMemberStatus', e); }
    }
    try {
      await _db?.from('tasks').update(update).eq('id', taskId);
    } catch (e) { _writeFailed('updateTeamMemberStatus', e); }
  }

  static Future<List<Task>> fetchTasks() async {
    try {
      final data = await _db?.from('tasks').select().order('id');
      if (data == null) return [];
      return (data as List)
          .map((row) => Task.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Task Updates (daily comment log — see task_updates migration) ──────

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<TaskUpdate>> fetchTaskUpdates(String taskId) async {
    try {
      final data = await _db?.from('task_updates').select()
          .eq('task_id', taskId).order('created_at');
      if (data == null) return [];
      return (data as List)
          .map((row) => TaskUpdate.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // IDs of [employeeName]'s tasks that already have a comment dated [day] —
  // used by the logout gate to find which active tasks still need one.
  static Future<Set<String>> fetchTaskUpdateTaskIdsFor(String employeeName, DateTime day) async {
    try {
      final data = await _db?.from('task_updates').select('task_id')
          .eq('employee_name', employeeName).eq('update_date', _isoDate(day));
      if (data == null) return {};
      return (data as List)
          .map((row) => (row as Map)['task_id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<bool> addTaskUpdate(String taskId, String employeeName, String comment) async {
    try {
      await _db?.from('task_updates').insert({
        'task_id':       taskId,
        'employee_name': employeeName,
        'update_date':   _isoDate(DateTime.now()),
        'comment':       comment,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Appraisal Forms ──────────────────────────────────────────────────

  // Unlike most save*() methods here, this one does NOT swallow errors —
  // the appraisal form editor needs to tell the user a save actually failed
  // (e.g. RLS misconfiguration) instead of showing a false "Draft saved".
  static Future<void> saveAppraisalForm(AppraisalForm form) async {
    await _db?.from('appraisal_forms').upsert(form.toRow());
  }

  static Future<List<AppraisalForm>> fetchAppraisalForms() async {
    try {
      final data = await _db?.from('appraisal_forms').select().order('created_at', ascending: false);
      if (data == null) return [];
      return (data as List)
          .map((row) => AppraisalForm.fromRow(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── KRA Documents ─────────────────────────────────────────────────────

  // Throws on failure so callers can surface the error to the user.
  static Future<String> uploadKraFile(
      Uint8List bytes, String fileName, String mimeType) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'kra_uploads/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _db!.storage.from('RESUME').uploadBinary(
      path, bytes,
      fileOptions: FileOptions(
          contentType: mimeType.isNotEmpty ? mimeType : 'application/octet-stream'),
    );
    return path;
  }

  static Future<void> saveKraDocument(KraDocument doc) async {
    await _db?.from('kra_documents').upsert(doc.toRow());
  }

  static Future<List<KraDocument>> fetchKraDocuments() async {
    try {
      final data = await _db?.from('kra_documents').select().order('uploaded_at', ascending: false);
      if (data == null) return [];
      return (data as List)
          .map((row) => KraDocument.fromRow(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> deleteKraDocument(String id) async {
    await _db?.from('kra_documents').delete().eq('id', id);
  }

  static Future<void> updateKraStatus(
    String id,
    String status, {
    String decidedBy = '',
    String reviewNote = '',
  }) async {
    await _db?.from('kra_documents').update({
      'status': status,
      'decided_by': decidedBy,
      'decided_at': DateTime.now().toIso8601String(),
      'review_note': reviewNote,
    }).eq('id', id);
  }

  // ── Form Versions ─────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchFormVersions() async {
    final db = _db;
    if (db == null) return [];
    try {
      final data = await db
          .from('form_versions')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> fetchActiveFormVersion() async {
    final db = _db;
    if (db == null) return null;
    try {
      final data = await db
          .from('form_versions')
          .select()
          .eq('status', 'approved')
          .order('approved_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchFormVersionById(
      String id) async {
    final db = _db;
    if (db == null) return null;
    try {
      final data = await db
          .from('form_versions')
          .select()
          .eq('id', id)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchFormVersionByNumber(
      int versionNumber) async {
    final db = _db;
    if (db == null) return null;
    try {
      final data = await db
          .from('form_versions')
          .select()
          .eq('version_number', versionNumber)
          .eq('status', 'approved')
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveFormVersion(Map<String, dynamic> data) async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized.');
    await db.from('form_versions').insert(data);
  }

  static Future<void> updateFormVersionStatus(
    String id,
    String status, {
    String decidedBy = '',
    String note = '',
  }) async {
    final db = _db;
    if (db == null) return;
    final update = <String, dynamic>{'status': status};
    if (status == 'approved') {
      update['approved_at'] =
          DateTime.now().toUtc().toIso8601String();
      update['approved_by'] = decidedBy;
    }
    if (note.isNotEmpty) update['rejection_note'] = note;
    await db.from('form_versions').update(update).eq('id', id);
  }

  static Future<int> getNextFormVersionNumber() async {
    final db = _db;
    if (db == null) return 1;
    try {
      final data = await db
          .from('form_versions')
          .select('version_number')
          .order('version_number', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isEmpty) return 1;
      return ((list.first['version_number'] as int?) ?? 0) + 1;
    } catch (_) {
      return 1;
    }
  }

  // ── Onboarding Form Versions ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchOnboardingFormVersions() async {
    final db = _db;
    if (db == null) return [];
    try {
      final data = await db
          .from('onboarding_form_versions')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> fetchActiveOnboardingFormVersion() async {
    final db = _db;
    if (db == null) return null;
    try {
      final data = await db
          .from('onboarding_form_versions')
          .select()
          .eq('status', 'approved')
          .order('approved_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveOnboardingFormVersion(
      Map<String, dynamic> data) async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized.');
    await db.from('onboarding_form_versions').insert(data);
  }

  static Future<void> updateOnboardingFormVersionStatus(
    String id,
    String status, {
    String decidedBy = '',
    String note = '',
  }) async {
    final db = _db;
    if (db == null) return;
    final update = <String, dynamic>{'status': status};
    if (status == 'approved') {
      update['approved_at'] = DateTime.now().toUtc().toIso8601String();
      update['approved_by'] = decidedBy;
    }
    if (note.isNotEmpty) update['rejection_note'] = note;
    await db.from('onboarding_form_versions').update(update).eq('id', id);
  }

  static Future<int> getNextOnboardingFormVersionNumber() async {
    final db = _db;
    if (db == null) return 1;
    try {
      final data = await db
          .from('onboarding_form_versions')
          .select('version_number')
          .order('version_number', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isEmpty) return 1;
      return ((list.first['version_number'] as int?) ?? 0) + 1;
    } catch (_) {
      return 1;
    }
  }

  // ── Leave Form Configs ────────────────────────────────────────────────
  /*
    create table if not exists leave_form_configs (
      id uuid default gen_random_uuid() primary key,
      created_at timestamptz default now(),
      created_by text default '',
      status text default 'pending',
      form_config jsonb not null default '{}',
      version_number integer default 1,
      approved_at timestamptz,
      approved_by text default '',
      rejection_note text default ''
    );
    alter table leave_form_configs disable row level security;
  */

  static Future<List<Map<String, dynamic>>> fetchLeaveFormVersions() async {
    final db = _db;
    if (db == null) return [];
    try {
      final data = await db
          .from('leave_form_configs')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> fetchActiveLeaveFormConfig() async {
    final db = _db;
    if (db == null) return null;
    try {
      final data = await db
          .from('leave_form_configs')
          .select()
          .eq('status', 'approved')
          .order('approved_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLeaveFormVersion(Map<String, dynamic> data) async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized.');
    await db.from('leave_form_configs').insert(data);
  }

  static Future<void> updateLeaveFormVersionStatus(
    String id,
    String status, {
    String decidedBy = '',
    String note = '',
  }) async {
    final db = _db;
    if (db == null) return;
    final update = <String, dynamic>{'status': status};
    if (status == 'approved') {
      update['approved_at'] = DateTime.now().toUtc().toIso8601String();
      update['approved_by'] = decidedBy;
    }
    if (note.isNotEmpty) update['rejection_note'] = note;
    await db.from('leave_form_configs').update(update).eq('id', id);
  }

  static Future<int> getNextLeaveFormVersionNumber() async {
    final db = _db;
    if (db == null) return 1;
    try {
      final data = await db
          .from('leave_form_configs')
          .select('version_number')
          .order('version_number', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isEmpty) return 1;
      return ((list.first['version_number'] as int?) ?? 0) + 1;
    } catch (_) {
      return 1;
    }
  }

  // ── Maintenance Form Configs ────────────────────────────────────────────
  /*
    create table if not exists maintenance_form_configs (
      id uuid default gen_random_uuid() primary key,
      created_at timestamptz default now(),
      created_by text default '',
      status text default 'pending',
      form_config jsonb not null default '{}',
      version_number integer default 1,
      approved_at timestamptz,
      approved_by text default '',
      rejection_note text default ''
    );
    alter table maintenance_form_configs disable row level security;
  */

  static Future<List<Map<String, dynamic>>> fetchMaintenanceFormVersions() async {
    final db = _db;
    if (db == null) return [];
    try {
      final data = await db
          .from('maintenance_form_configs')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> fetchActiveMaintenanceFormConfig() async {
    final db = _db;
    if (db == null) return null;
    try {
      final data = await db
          .from('maintenance_form_configs')
          .select()
          .eq('status', 'approved')
          .order('approved_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveMaintenanceFormVersion(Map<String, dynamic> data) async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized.');
    await db.from('maintenance_form_configs').insert(data);
  }

  static Future<void> updateMaintenanceFormVersionStatus(
    String id,
    String status, {
    String decidedBy = '',
    String note = '',
  }) async {
    final db = _db;
    if (db == null) return;
    final update = <String, dynamic>{'status': status};
    if (status == 'approved') {
      update['approved_at'] = DateTime.now().toUtc().toIso8601String();
      update['approved_by'] = decidedBy;
    }
    if (note.isNotEmpty) update['rejection_note'] = note;
    await db.from('maintenance_form_configs').update(update).eq('id', id);
  }

  static Future<int> getNextMaintenanceFormVersionNumber() async {
    final db = _db;
    if (db == null) return 1;
    try {
      final data = await db
          .from('maintenance_form_configs')
          .select('version_number')
          .order('version_number', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isEmpty) return 1;
      return ((list.first['version_number'] as int?) ?? 0) + 1;
    } catch (_) {
      return 1;
    }
  }

  // ── Office Timings (department-based working hours) ────────────────────
  /*
    create table if not exists office_timings (
      id uuid default gen_random_uuid() primary key,
      name text not null,
      check_in_time text not null,
      check_out_time text not null,
      grace_minutes integer not null default 10,
      working_hours numeric not null default 8,
      is_default boolean not null default false,
      created_at timestamptz default now()
    );
    create table if not exists department_office_timings (
      department text primary key,
      office_timing_id uuid not null references office_timings(id) on delete cascade
    );
  */

  static Future<List<OfficeTiming>> fetchOfficeTimings() async {
    final db = _db;
    if (db == null) return [];
    try {
      final data = await db.from('office_timings').select().order('created_at');
      return (data as List)
          .map((row) => OfficeTiming.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// department → office_timing_id, for every department HR has explicitly
  /// assigned (anything absent uses the default timing).
  static Future<Map<String, String>> fetchDepartmentOfficeTimingMap() async {
    final db = _db;
    if (db == null) return {};
    try {
      final data = await db.from('department_office_timings').select();
      return {
        for (final row in (data as List))
          (row as Map<String, dynamic>)['department'] as String:
              row['office_timing_id'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<String?> saveOfficeTiming(OfficeTiming timing) async {
    final db = _db;
    if (db == null) return 'Database not initialized.';
    try {
      await db.from('office_timings').upsert(timing.toJson());
      return null;
    } catch (_) {
      return 'Could not save office timings. Please try again.';
    }
  }

  static Future<void> deleteOfficeTiming(String id) async {
    final db = _db;
    if (db == null) return;
    await db.from('office_timings').delete().eq('id', id);
  }

  /// Assigns [department] to [timingId] — an upsert keyed on the
  /// department, so it automatically moves off whatever timing it was
  /// previously assigned to.
  static Future<void> assignDepartmentToTiming(String department, String timingId) async {
    final db = _db;
    if (db == null) return;
    await db.from('department_office_timings').upsert({
      'department': department,
      'office_timing_id': timingId,
    });
  }

  /// Removes any explicit assignment for [department], reverting it to the
  /// default timing.
  static Future<void> unassignDepartmentTiming(String department) async {
    final db = _db;
    if (db == null) return;
    await db.from('department_office_timings').delete().eq('department', department);
  }

  // ── Location Management (Locations + Attendance Policies) ───────────────
  /*
    See supabase/migrations/20260718030000_location_management.sql for the
    full schema: locations, attendance_policies, attendance_policy_fallbacks,
    attendance_policy_department_assignments,
    attendance_policy_employee_overrides, employee_locations, plus new
    check_in_lat/lng/within_radius, check_out_lat/lng/within_radius, and
    location_policy_name columns on attendance_records.
  */

  static Future<List<OfficeLocation>> fetchLocations() async {
    final db = _db;
    if (db == null) return [];
    try {
      final data = await db.from('locations').select().order('created_at');
      return (data as List)
          .map((row) => OfficeLocation.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String?> saveLocation(OfficeLocation location) async {
    final db = _db;
    if (db == null) return 'Database not initialized.';
    try {
      await db.from('locations').upsert(location.toJson());
      return null;
    } catch (_) {
      return 'Could not save location. Please try again.';
    }
  }

  static Future<String?> deleteLocation(String id) async {
    final db = _db;
    if (db == null) return 'Database not initialized.';
    try {
      await db.from('locations').delete().eq('id', id);
      return null;
    } catch (_) {
      return 'Could not delete location. Please try again.';
    }
  }

  static Future<List<AttendancePolicy>> fetchAttendancePolicies() async {
    final db = _db;
    if (db == null) return [];
    try {
      final data = await db.from('attendance_policies').select().order('created_at');
      return (data as List)
          .map((row) => AttendancePolicy.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<String?> saveAttendancePolicy(AttendancePolicy policy) async {
    final db = _db;
    if (db == null) return 'Database not initialized.';
    try {
      await db.from('attendance_policies').upsert(policy.toJson());
      return null;
    } catch (_) {
      return 'Could not save attendance policy. Please try again.';
    }
  }

  /// Fails (with a readable error) if this policy is still referenced by a
  /// fallback, department assignment, or employee override — `on delete
  /// restrict` in the schema surfaces as a Postgres foreign-key error here.
  static Future<String?> deleteAttendancePolicy(String id) async {
    final db = _db;
    if (db == null) return 'Database not initialized.';
    try {
      await db.from('attendance_policies').delete().eq('id', id);
      return null;
    } catch (_) {
      return 'Could not delete this policy — it may still be assigned to a location.';
    }
  }

  /// work_location ('Office'/'Onsite') → policy id, used when an employee
  /// has no department assignment or individual override.
  static Future<Map<String, String>> fetchFallbackPolicies() async {
    final db = _db;
    if (db == null) return {};
    try {
      final data = await db.from('attendance_policy_fallbacks').select();
      return {
        for (final row in (data as List))
          (row as Map<String, dynamic>)['work_location'] as String: row['policy_id'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> setFallbackPolicy(String workLocation, String policyId) async {
    final db = _db;
    if (db == null) return;
    await db.from('attendance_policy_fallbacks').upsert({
      'work_location': workLocation,
      'policy_id': policyId,
    });
  }

  static Future<Map<String, String>> fetchDepartmentPolicyAssignments() async {
    final db = _db;
    if (db == null) return {};
    try {
      final data = await db.from('attendance_policy_department_assignments').select();
      return {
        for (final row in (data as List))
          (row as Map<String, dynamic>)['department'] as String: row['policy_id'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> assignDepartmentPolicy(String department, String policyId) async {
    final db = _db;
    if (db == null) return;
    await db.from('attendance_policy_department_assignments').upsert({
      'department': department,
      'policy_id': policyId,
    });
  }

  static Future<void> unassignDepartmentPolicy(String department) async {
    final db = _db;
    if (db == null) return;
    await db.from('attendance_policy_department_assignments').delete().eq('department', department);
  }

  static Future<Map<String, String>> fetchEmployeePolicyOverrides() async {
    final db = _db;
    if (db == null) return {};
    try {
      final data = await db.from('attendance_policy_employee_overrides').select();
      return {
        for (final row in (data as List))
          (row as Map<String, dynamic>)['employee_id'] as String: row['policy_id'] as String,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> setEmployeePolicyOverride(String employeeId, String policyId) async {
    final db = _db;
    if (db == null) return;
    await db.from('attendance_policy_employee_overrides').upsert({
      'employee_id': employeeId,
      'policy_id': policyId,
    });
  }

  static Future<void> clearEmployeePolicyOverride(String employeeId) async {
    final db = _db;
    if (db == null) return;
    await db.from('attendance_policy_employee_overrides').delete().eq('employee_id', employeeId);
  }

  /// employee_id → list of assigned location ids.
  static Future<Map<String, List<String>>> fetchEmployeeLocations() async {
    final db = _db;
    if (db == null) return {};
    try {
      final data = await db.from('employee_locations').select();
      final map = <String, List<String>>{};
      for (final row in (data as List)) {
        final r = row as Map<String, dynamic>;
        final empId = r['employee_id'] as String;
        (map[empId] ??= []).add(r['location_id'] as String);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Replaces every Location assigned to [employeeId] with [locationIds] in
  /// one call — diffs against the current assignment so unrelated rows for
  /// other employees are untouched.
  static Future<String?> setEmployeeLocations(String employeeId, List<String> locationIds) async {
    final db = _db;
    if (db == null) return 'Database not initialized.';
    try {
      final current = await db
          .from('employee_locations')
          .select('location_id')
          .eq('employee_id', employeeId);
      final currentIds = (current as List)
          .map((r) => (r as Map<String, dynamic>)['location_id'] as String)
          .toSet();
      final newIds = locationIds.toSet();

      final toAdd = newIds.difference(currentIds);
      final toRemove = currentIds.difference(newIds);

      if (toAdd.isNotEmpty) {
        await db.from('employee_locations').insert([
          for (final locId in toAdd) {'employee_id': employeeId, 'location_id': locId},
        ]);
      }
      for (final locId in toRemove) {
        await db
            .from('employee_locations')
            .delete()
            .eq('employee_id', employeeId)
            .eq('location_id', locId);
      }
      return null;
    } catch (_) {
      return 'Could not update employee locations. Please try again.';
    }
  }

  // ── Attendance Records ────────────────────────────────────────────────

  static String _attendanceId(String employeeId, String date) =>
      '${employeeId.isNotEmpty ? employeeId : 'emp'}_${date.replaceAll('/', '-')}';

  static Future<String?> saveCheckIn({
    required String employeeName,
    required String employeeId,
    required String date,
    required String time,
    String location = '',
    String note = '',
    String selfiePath = '',
    double? lat,
    double? lng,
    bool? withinRadius,
    double? accuracy,
    String policyName = '',
  }) async {
    try {
      if (_db == null) return 'Database not connected';
      await _db!.from('attendance_records').upsert({
        'id':                      _attendanceId(employeeId, date),
        'employee_name':           employeeName,
        'employee_id':             employeeId,
        'date':                    date,
        'check_in_time':           time,
        'check_out_time':          '',
        'location':                location,
        'check_in_note':           note,
        'check_in_selfie_path':    selfiePath,
        'check_in_lat':            lat,
        'check_in_lng':            lng,
        'check_in_within_radius':  withinRadius,
        'check_in_accuracy':       accuracy,
        'location_policy_name':    policyName,
        // Why the fix failed, when it did. lastLocationError previously only
        // existed in the browser of whoever checked in, so three attempts at
        // the GPS problem were all unverifiable guesses. Recording it means
        // one check-in identifies the actual cause.
        'check_in_gps_error':      lat == null
            ? (GpsTrackingService.lastLocationError ?? 'no position and no error reported')
            : '',
      });
      logAuditEvent('attendance_check_in', targetType: 'attendance_records', targetId: employeeId);
      return null;
    } catch (_) {
      return 'Could not save check-in. Please try again.';
    }
  }

  static Future<void> updateLocation({
    required String employeeId,
    required String date,
    required String location,
  }) async {
    try {
      await _db
          ?.from('attendance_records')
          .update({'location': location})
          .eq('id', _attendanceId(employeeId, date));
    } catch (e) { _writeFailed('updateLocation', e); }
  }

  static Future<void> updateGpsPoints({
    required String employeeId,
    required String date,
    required List<List<double>> points,
  }) async {
    try {
      await _db
          ?.from('attendance_records')
          .update({'gps_points': points})
          .eq('id', _attendanceId(employeeId, date));
    } catch (e) { _writeFailed('updateGpsPoints', e); }
  }

  static Future<List<List<double>>> fetchGpsPoints({
    required String employeeId,
    required String date,
  }) async {
    try {
      final data = await _db
          ?.from('attendance_records')
          .select('gps_points')
          .eq('id', _attendanceId(employeeId, date))
          .limit(1);
      if (data == null || (data as List).isEmpty) return [];
      return _parseGpsPoints((data as List).first['gps_points']);
    } catch (_) {
      return [];
    }
  }

  static List<List<double>> _parseGpsPoints(dynamic raw) {
    if (raw == null) return [];
    try {
      return (raw as List).map<List<double>>((p) {
        if (p is List && p.length >= 2) {
          return [(p[0] as num).toDouble(), (p[1] as num).toDouble()];
        }
        return [];
      }).where((p) => p.length == 2).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCheckOut({
    required String employeeId,
    required String date,
    required String time,
    String note = '',
    String selfiePath = '',
    double? lat,
    double? lng,
    bool? withinRadius,
  }) async {
    try {
      await _db
          ?.from('attendance_records')
          .update({
            'check_out_time':          time,
            'check_out_note':          note,
            'check_out_selfie_path':   selfiePath,
            'check_out_lat':           lat,
            'check_out_lng':           lng,
            'check_out_within_radius': withinRadius,
          })
          .eq('id', _attendanceId(employeeId, date));
      logAuditEvent('attendance_check_out', targetType: 'attendance_records', targetId: employeeId);
    } catch (e) { _writeFailed('saveCheckOut', e); }
  }

  static Future<List<AttendanceRecord>> fetchAttendanceForDate(String date) async {
    try {
      final data = await _db
          ?.from('attendance_records')
          .select()
          .eq('date', date)
          .order('created_at', ascending: true);
      if (data == null) return [];
      return (data as List).map((row) => AttendanceRecord(
        id:           row['id'] as String,
        employeeName: row['employee_name'] as String,
        employeeId:   (row['employee_id']    as String?) ?? '',
        date:         row['date'] as String,
        checkInTime:  (row['check_in_time']  as String?) ?? '',
        checkOutTime: (row['check_out_time'] as String?) ?? '',
        location:     (row['location']        as String?) ?? '',
        gpsPoints:    _parseGpsPoints(row['gps_points']),
        checkInNote:  (row['check_in_note']  as String?) ?? '',
        checkOutNote: (row['check_out_note'] as String?) ?? '',
        checkInSelfiePath:  (row['check_in_selfie_path']  as String?) ?? '',
        checkOutSelfiePath: (row['check_out_selfie_path'] as String?) ?? '',
        checkInLat:          (row['check_in_lat']  as num?)?.toDouble(),
        checkInLng:          (row['check_in_lng']  as num?)?.toDouble(),
        checkInWithinRadius: row['check_in_within_radius']  as bool?,
        lateWaived:          (row['late_waived'] as bool?) ?? false,
        lateWaiverReason:    (row['late_waiver_reason'] as String?) ?? '',
        checkOutLat:          (row['check_out_lat'] as num?)?.toDouble(),
        checkOutLng:          (row['check_out_lng'] as num?)?.toDouble(),
        checkOutWithinRadius: row['check_out_within_radius'] as bool?,
        locationPolicyName:   (row['location_policy_name'] as String?) ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Attendance records for several dates ("dd/MM/yyyy" strings) in one
  /// query — used to build the attendance summary's day-over-day trend.
  static Future<List<AttendanceRecord>> fetchAttendanceForDates(List<String> dates) async {
    if (dates.isEmpty) return [];
    try {
      final data = await _db
          ?.from('attendance_records')
          .select()
          .inFilter('date', dates)
          .order('created_at', ascending: true);
      if (data == null) return [];
      return (data as List).map((row) => AttendanceRecord(
        id:           row['id'] as String,
        employeeName: row['employee_name'] as String,
        employeeId:   (row['employee_id']    as String?) ?? '',
        date:         row['date'] as String,
        checkInTime:  (row['check_in_time']  as String?) ?? '',
        checkOutTime: (row['check_out_time'] as String?) ?? '',
        location:     (row['location']        as String?) ?? '',
        gpsPoints:    _parseGpsPoints(row['gps_points']),
        checkInNote:  (row['check_in_note']  as String?) ?? '',
        checkOutNote: (row['check_out_note'] as String?) ?? '',
        checkInSelfiePath:  (row['check_in_selfie_path']  as String?) ?? '',
        checkOutSelfiePath: (row['check_out_selfie_path'] as String?) ?? '',
        checkInLat:          (row['check_in_lat']  as num?)?.toDouble(),
        checkInLng:          (row['check_in_lng']  as num?)?.toDouble(),
        checkInWithinRadius: row['check_in_within_radius']  as bool?,
        lateWaived:          (row['late_waived'] as bool?) ?? false,
        lateWaiverReason:    (row['late_waiver_reason'] as String?) ?? '',
        checkOutLat:          (row['check_out_lat'] as num?)?.toDouble(),
        checkOutLng:          (row['check_out_lng'] as num?)?.toDouble(),
        checkOutWithinRadius: row['check_out_within_radius'] as bool?,
        locationPolicyName:   (row['location_policy_name'] as String?) ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Employees currently checked in for [date] (checked in, not yet checked
  /// out) — used by the Reports & Analytics live tracking map, which only
  /// needs whoever's on the move right now rather than the full day's rows.
  static Future<List<AttendanceRecord>> fetchCheckedInAttendance(String date) async {
    try {
      final data = await _db
          ?.from('attendance_records')
          .select()
          .eq('date', date)
          .not('check_in_time', 'eq', '')
          .eq('check_out_time', '');
      if (data == null) return [];
      return (data as List).map((row) => AttendanceRecord(
        id:           row['id'] as String,
        employeeName: row['employee_name'] as String,
        employeeId:   (row['employee_id']    as String?) ?? '',
        date:         row['date'] as String,
        checkInTime:  (row['check_in_time']  as String?) ?? '',
        checkOutTime: (row['check_out_time'] as String?) ?? '',
        location:     (row['location']        as String?) ?? '',
        gpsPoints:    _parseGpsPoints(row['gps_points']),
        checkInNote:  (row['check_in_note']  as String?) ?? '',
        checkOutNote: (row['check_out_note'] as String?) ?? '',
        checkInSelfiePath:  (row['check_in_selfie_path']  as String?) ?? '',
        checkOutSelfiePath: (row['check_out_selfie_path'] as String?) ?? '',
        checkInLat:          (row['check_in_lat']  as num?)?.toDouble(),
        checkInLng:          (row['check_in_lng']  as num?)?.toDouble(),
        checkInWithinRadius: row['check_in_within_radius']  as bool?,
        lateWaived:          (row['late_waived'] as bool?) ?? false,
        lateWaiverReason:    (row['late_waiver_reason'] as String?) ?? '',
        checkOutLat:          (row['check_out_lat'] as num?)?.toDouble(),
        checkOutLng:          (row['check_out_lng'] as num?)?.toDouble(),
        checkOutWithinRadius: row['check_out_within_radius'] as bool?,
        locationPolicyName:   (row['location_policy_name'] as String?) ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<AttendanceRecord?> fetchTodayAttendance(String employeeId) async {
    if (employeeId.isEmpty) return null;
    final today = DateTime.now();
    final date =
        '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
    try {
      final data = await _db
          ?.from('attendance_records')
          .select()
          .eq('id', _attendanceId(employeeId, date))
          .limit(1);
      if (data == null || (data as List).isEmpty) return null;
      final row = (data as List).first as Map<String, dynamic>;
      return AttendanceRecord(
        id:           row['id'] as String,
        employeeName: row['employee_name'] as String,
        employeeId:   (row['employee_id']  as String?) ?? '',
        date:         row['date'] as String,
        checkInTime:  (row['check_in_time']  as String?) ?? '',
        checkOutTime: (row['check_out_time'] as String?) ?? '',
        location:     (row['location']        as String?) ?? '',
        gpsPoints:    _parseGpsPoints(row['gps_points']),
        checkInNote:  (row['check_in_note']  as String?) ?? '',
        checkOutNote: (row['check_out_note'] as String?) ?? '',
        checkInSelfiePath:  (row['check_in_selfie_path']  as String?) ?? '',
        checkOutSelfiePath: (row['check_out_selfie_path'] as String?) ?? '',
        checkInLat:          (row['check_in_lat']  as num?)?.toDouble(),
        checkInLng:          (row['check_in_lng']  as num?)?.toDouble(),
        checkInWithinRadius: row['check_in_within_radius']  as bool?,
        lateWaived:          (row['late_waived'] as bool?) ?? false,
        lateWaiverReason:    (row['late_waiver_reason'] as String?) ?? '',
        checkOutLat:          (row['check_out_lat'] as num?)?.toDouble(),
        checkOutLng:          (row['check_out_lng'] as num?)?.toDouble(),
        checkOutWithinRadius: row['check_out_within_radius'] as bool?,
        locationPolicyName:   (row['location_policy_name'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Attendance for a date RANGE, using date_iso rather than the text date.
  ///
  /// fetchAttendanceForMonth() matches on '%/MM/yyyy', which can only express
  /// a calendar month — it cannot span 26 Jul to 25 Aug. date_iso is the
  /// generated ISO column, so a range query on it is both correct and sortable.
  static Future<List<AttendanceRecord>> fetchAttendanceForRange(
      String employeeId, DateTime from, DateTime to) async {
    if (employeeId.isEmpty) return [];
    String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final data = await _db
          ?.from('attendance_records')
          .select()
          .eq('employee_id', employeeId)
          .gte('date_iso', iso(from))
          .lte('date_iso', iso(to))
          .order('date_iso');
      if (data == null) return [];
      // Reuse the month mapping rather than repeating twenty fields: this
      // mapping has already drifted between call sites once.
      return _mapAttendanceRows(data as List);
    } catch (e) {
      _writeFailed('fetchAttendanceForRange', e);
      return [];
    }
  }

  /// Shared row -> AttendanceRecord mapping.
  static List<AttendanceRecord> _mapAttendanceRows(List rows) =>
      rows.map((r) {
        final row = r as Map<String, dynamic>;
        return AttendanceRecord(
          id:           (row['id'] as String?) ?? '',
          employeeName: (row['employee_name'] as String?) ?? '',
          employeeId:   (row['employee_id'] as String?) ?? '',
          date:         (row['date'] as String?) ?? '',
          checkInTime:  (row['check_in_time']  as String?) ?? '',
          checkOutTime: (row['check_out_time'] as String?) ?? '',
          location:     (row['location'] as String?) ?? '',
          gpsPoints:    _parseGpsPoints(row['gps_points']),
          checkInNote:  (row['check_in_note']  as String?) ?? '',
          checkOutNote: (row['check_out_note'] as String?) ?? '',
          checkInSelfiePath:  (row['check_in_selfie_path']  as String?) ?? '',
          checkOutSelfiePath: (row['check_out_selfie_path'] as String?) ?? '',
          checkInLat:          (row['check_in_lat']  as num?)?.toDouble(),
          checkInLng:          (row['check_in_lng']  as num?)?.toDouble(),
          checkInWithinRadius: row['check_in_within_radius']  as bool?,
          lateWaived:          (row['late_waived'] as bool?) ?? false,
          lateWaiverReason:    (row['late_waiver_reason'] as String?) ?? '',
          checkOutLat:          (row['check_out_lat'] as num?)?.toDouble(),
          checkOutLng:          (row['check_out_lng'] as num?)?.toDouble(),
          checkOutWithinRadius: row['check_out_within_radius'] as bool?,
          locationPolicyName:   (row['location_policy_name'] as String?) ?? '',
        );
      }).toList();

  static Future<List<AttendanceRecord>> fetchAttendanceForMonth(
      String employeeId, int year, int month) async {
    if (employeeId.isEmpty) return [];
    final monthStr = '${month.toString().padLeft(2, '0')}/$year';
    try {
      final data = await _db
          ?.from('attendance_records')
          .select()
          .eq('employee_id', employeeId)
          .like('date', '%/$monthStr');
      if (data == null) return [];
      return (data as List).map((row) => AttendanceRecord(
        id:           row['id']           as String,
        employeeName: (row['employee_name'] as String?) ?? '',
        employeeId:   (row['employee_id']   as String?) ?? '',
        date:         (row['date']          as String?) ?? '',
        checkInTime:  (row['check_in_time'] as String?) ?? '',
        checkOutTime: (row['check_out_time'] as String?) ?? '',
        location:     (row['location']       as String?) ?? '',
        gpsPoints:    _parseGpsPoints(row['gps_points']),
        checkInNote:  (row['check_in_note']  as String?) ?? '',
        checkOutNote: (row['check_out_note'] as String?) ?? '',
        checkInSelfiePath:  (row['check_in_selfie_path']  as String?) ?? '',
        checkOutSelfiePath: (row['check_out_selfie_path'] as String?) ?? '',
        checkInLat:          (row['check_in_lat']  as num?)?.toDouble(),
        checkInLng:          (row['check_in_lng']  as num?)?.toDouble(),
        checkInWithinRadius: row['check_in_within_radius']  as bool?,
        lateWaived:          (row['late_waived'] as bool?) ?? false,
        lateWaiverReason:    (row['late_waiver_reason'] as String?) ?? '',
        checkOutLat:          (row['check_out_lat'] as num?)?.toDouble(),
        checkOutLng:          (row['check_out_lng'] as num?)?.toDouble(),
        checkOutWithinRadius: row['check_out_within_radius'] as bool?,
        locationPolicyName:   (row['location_policy_name'] as String?) ?? '',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<AttendanceRecord>> fetchEmployeeRecentAttendance(String employeeId, {int limit = 30}) async {
    if (employeeId.isEmpty) return [];
    try {
      final data = await _db
          ?.from('attendance_records')
          .select()
          .eq('employee_id', employeeId)
          .order('created_at', ascending: false)
          .limit(limit);
      if (data == null) return [];
      return (data as List).map((row) => AttendanceRecord(
        id:           row['id'] as String,
        employeeName: (row['employee_name'] as String?) ?? '',
        employeeId:   (row['employee_id']   as String?) ?? '',
        date:         (row['date']           as String?) ?? '',
        checkInTime:  (row['check_in_time']  as String?) ?? '',
        checkOutTime: (row['check_out_time'] as String?) ?? '',
        location:     (row['location']       as String?) ?? '',
        gpsPoints:    _parseGpsPoints(row['gps_points']),
      )).toList();
    } catch (_) {
      return [];
    }
  }

  // Sets AttendanceStore.isCheckedIn based on today's Supabase record.
  static Future<void> restoreCheckInState() async {
    if (!UserSession.loggedIn || UserSession.employeeId.isEmpty) return;
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    try {
      final data = await _db
          ?.from('attendance_records')
          .select()
          .eq('id', _attendanceId(UserSession.employeeId, date))
          .limit(1);
      if (data == null || (data as List).isEmpty) return;
      final row = (data as List).first as Map<String, dynamic>;
      final checkIn  = (row['check_in_time']  as String?) ?? '';
      final checkOut = (row['check_out_time'] as String?) ?? '';
      AttendanceStore.isCheckedIn = checkIn.isNotEmpty && checkOut.isEmpty;
    } catch (e) { _writeFailed('restoreCheckInState', e); }
  }

  // ── Announcements ─────────────────────────────────────────────────────────
  /*
    create table if not exists announcements (
      id uuid default gen_random_uuid() primary key,
      text text not null,
      announced_on date not null default current_date,
      created_at timestamptz default now()
    );
    alter table announcements disable row level security;

    create table if not exists holidays (
      id uuid default gen_random_uuid() primary key,
      name text not null,
      holiday_date date not null,
      created_at timestamptz default now()
    );
    alter table holidays disable row level security;

    create table if not exists birthdays (
      id uuid default gen_random_uuid() primary key,
      name text not null,
      birthday_date date not null,
      created_at timestamptz default now()
    );
    alter table birthdays disable row level security;
  */

  static Future<List<Map<String, dynamic>>> fetchAnnouncements() async {
    try {
      final data = await _db
          ?.from('announcements')
          .select()
          .order('announced_on', ascending: false)
          .limit(200);
      if (data == null) return [];
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<String?> addAnnouncement(
    String text,
    DateTime date, {
    String? targetEmployeeId,
    String? targetEmployeeName,
  }) async {
    try {
      await _db?.from('announcements').insert({
        'text': text,
        'announced_on': date.toIso8601String().substring(0, 10),
        'target_employee_id': targetEmployeeId,
        'target_employee_name': targetEmployeeName,
      });
      return null; // null = success
    } catch (_) {
      return 'Could not post announcement. Please try again.';
    }
  }

  static Future<void> deleteAnnouncement(String id) async {
    try {
      await _db?.from('announcements').delete().eq('id', id);
    } catch (e) { _writeFailed('deleteAnnouncement', e); }
  }

  // ── Holidays ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchHolidays(int year) async {
    try {
      final data = await _db
          ?.from('holidays')
          .select()
          .gte('holiday_date', '$year-01-01')
          .lte('holiday_date', '$year-12-31')
          .order('holiday_date', ascending: true);
      if (data == null) return [];
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> addHoliday(String name, DateTime date) async {
    try {
      await _db?.from('holidays').insert({
        'name': name,
        'holiday_date': date.toIso8601String().substring(0, 10),
      });
    } catch (e) { _writeFailed('addHoliday', e); }
  }

  static Future<void> deleteHoliday(String id) async {
    try {
      await _db?.from('holidays').delete().eq('id', id);
    } catch (e) { _writeFailed('deleteHoliday', e); }
  }

  // ── Birthdays ──────────────────────────────────────────────────────────────
  // Auto-derived from the Date of Birth candidates fill in on the onboarding
  // form (form_data->>'date_of_birth', format dd/MM/yyyy), for whichever
  // submission resulted in an actual employee account (status =
  // 'access_granted'). The manual 'birthdays' table remains as a fallback for
  // employees hired before onboarding captured DOB, or missed by name-matching.

  static DateTime? _parseOnboardingDob(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final parts = t.split('/');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        try {
          return DateTime(y, m, d);
        } catch (_) {
          return null;
        }
      }
    }
    return DateTime.tryParse(t);
  }

  static Future<List<Map<String, dynamic>>> fetchOnboardingBirthdaysForMonth(
      int month) async {
    try {
      final data = await _db
          ?.from('onboarding_forms')
          .select('name, form_data, assigned_emp_id, status, submitted_at')
          .eq('status', 'access_granted')
          .order('submitted_at', ascending: false);
      if (data == null) return [];
      final rows = List<Map<String, dynamic>>.from(data as List);
      final seenEmpIds = <String>{};
      final result = <Map<String, dynamic>>[];
      for (final row in rows) {
        final empId = (row['assigned_emp_id'] as String? ?? '').trim();
        // One entry per employee — keep only their most recent submission.
        if (empId.isEmpty || !seenEmpIds.add(empId)) continue;
        final name = (row['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        final fd = row['form_data'];
        final dobRaw = fd is Map ? (fd['date_of_birth'] as String? ?? '') : '';
        final dob = _parseOnboardingDob(dobRaw);
        if (dob == null || dob.month != month) continue;
        result.add({
          'name': name,
          'birthday_date': dob.toIso8601String().substring(0, 10),
        });
      }
      result.sort((a, b) =>
          (DateTime.tryParse(a['birthday_date'] as String) ?? DateTime.now())
              .day
              .compareTo((DateTime.tryParse(b['birthday_date'] as String) ??
                      DateTime.now())
                  .day));
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchBirthdaysForMonth(
      int month) async {
    final auto = await fetchOnboardingBirthdaysForMonth(month);
    try {
      final data = await _db
          ?.from('birthdays')
          .select()
          .order('birthday_date', ascending: true);
      if (data == null) return auto;
      final manual = List<Map<String, dynamic>>.from(data as List).where((row) {
        final d = DateTime.tryParse(row['birthday_date'] as String? ?? '');
        return d != null && d.month == month;
      });
      final autoNames =
          auto.map((r) => (r['name'] as String).trim().toLowerCase()).toSet();
      final merged = [
        ...auto,
        ...manual.where((r) =>
            !autoNames.contains((r['name'] as String? ?? '').trim().toLowerCase())),
      ];
      merged.sort((a, b) =>
          (DateTime.tryParse(a['birthday_date'] as String? ?? '') ?? DateTime.now())
              .day
              .compareTo((DateTime.tryParse(b['birthday_date'] as String? ?? '') ??
                      DateTime.now())
                  .day));
      return merged;
    } catch (_) {
      return auto;
    }
  }

  /// Every birthday across the year (auto-derived + manual), for the "view
  /// full list" dialog — unlike [fetchBirthdaysForMonth] this isn't
  /// filtered down to one month.
  static Future<List<Map<String, dynamic>>> fetchAllBirthdays() async {
    final auto = <Map<String, dynamic>>[];
    for (var month = 1; month <= 12; month++) {
      auto.addAll(await fetchOnboardingBirthdaysForMonth(month));
    }
    try {
      final data = await _db
          ?.from('birthdays')
          .select()
          .order('birthday_date', ascending: true);
      final manual = data == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(data as List);
      final autoNames =
          auto.map((r) => (r['name'] as String).trim().toLowerCase()).toSet();
      final merged = [
        ...auto,
        ...manual.where((r) =>
            !autoNames.contains((r['name'] as String? ?? '').trim().toLowerCase())),
      ];
      merged.sort((a, b) {
        final da = DateTime.tryParse(a['birthday_date'] as String? ?? '') ?? DateTime.now();
        final db = DateTime.tryParse(b['birthday_date'] as String? ?? '') ?? DateTime.now();
        if (da.month != db.month) return da.month.compareTo(db.month);
        return da.day.compareTo(db.day);
      });
      return merged;
    } catch (_) {
      auto.sort((a, b) {
        final da = DateTime.tryParse(a['birthday_date'] as String? ?? '') ?? DateTime.now();
        final db = DateTime.tryParse(b['birthday_date'] as String? ?? '') ?? DateTime.now();
        if (da.month != db.month) return da.month.compareTo(db.month);
        return da.day.compareTo(db.day);
      });
      return auto;
    }
  }

  static Future<void> addBirthday(String name, DateTime date) async {
    try {
      await _db?.from('birthdays').insert({
        'name': name,
        'birthday_date': date.toIso8601String().substring(0, 10),
      });
    } catch (e) { _writeFailed('addBirthday', e); }
  }

  static Future<void> deleteBirthday(String id) async {
    try {
      await _db?.from('birthdays').delete().eq('id', id);
    } catch (e) { _writeFailed('deleteBirthday', e); }
  }

  // ── Employee of the Month ──────────────────────────────────────────────────
  // Multiple employees can share a single month's announcement — every row
  // for the most recently announced month_year is a co-winner, not just one.

  /// Winners awaiting Management approval. Empty for everyone else — the RPC
  /// that decides them is Management-only, so there is nothing an ordinary
  /// user could do with the list.
  static Future<List<Map<String, dynamic>>> fetchPendingEmployeesOfMonth() async {
    try {
      final rows = await _db
          ?.from('employee_of_month')
          .select()
          .eq('status', 'pending')
          .order('month_year', ascending: false);
      return List<Map<String, dynamic>>.from(rows ?? []);
    } catch (_) {
      return [];
    }
  }

  /// Management approves or declines a proposed winner. Returns null on
  /// success, or a message to show.
  static Future<String?> decideEmployeeOfMonth(String id, bool approve,
      {String reason = ''}) async {
    try {
      await _db?.rpc('decide_employee_of_month', params: {
        'p_id': id,
        'p_approve': approve,
        'p_reason': reason,
      });
      return null;
    } catch (e) {
      if (e is PostgrestException && e.message.trim().isNotEmpty) return e.message;
      return 'Could not save the decision. Please try again.';
    }
  }

  static Future<List<Map<String, dynamic>>> fetchEmployeesOfMonth() async {
    try {
      // Approved only. A proposal awaiting Management sign-off must not
      // appear on dashboards or trigger the celebration animation.
      final all = await _db
          ?.from('employee_of_month')
          .select()
          .eq('status', 'approved')
          .order('month_year', ascending: false);
      if (all == null || all.isEmpty) return [];
      final latestMonth = all.first['month_year'] as String?;
      return List<Map<String, dynamic>>.from(
          all.where((r) => r['month_year'] == latestMonth));
    } catch (_) {
      return [];
    }
  }

  /// Reconciles [monthYear]'s winners to exactly [names]: adds any new
  /// names (or updates their reason if already present), and removes any
  /// existing winner for that month who isn't in [names] anymore — so the
  /// dialog's checkbox selection is the single source of truth per save.
  static Future<String?> saveEmployeesOfMonth(
      List<String> names, String reason, String monthYear) async {
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      final existing = await _db
              ?.from('employee_of_month')
              .select('id, employee_name')
              .eq('month_year', monthYear) ??
          [];

      final toRemove = existing.where((r) => !names.contains(r['employee_name']));
      for (final r in toRemove) {
        await _db?.from('employee_of_month').delete().eq('id', r['id']);
      }

      for (final name in names) {
        final match = existing.where((r) => r['employee_name'] == name);
        if (match.isNotEmpty) {
          await _db?.from('employee_of_month').update({
            'reason': reason,
            'announced_date': today,
          }).eq('id', match.first['id']);
        } else {
          await _db?.from('employee_of_month').insert({
            'employee_name': name,
            'reason': reason,
            'month_year': monthYear,
            'announced_date': today,
          });
        }
      }
      return null;
    } catch (_) {
      return 'Could not save Employee of the Month. Please try again.';
    }
  }

  // ── App settings (global color theme) ───────────────────────────────────────

  static Future<String?> fetchColorTheme() async {
    try {
      final data = await _db
          ?.from('app_settings')
          .select('color_theme')
          .eq('id', 'global')
          .maybeSingle();
      return data?['color_theme'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setColorTheme(String themeKey) async {
    try {
      await _db?.from('app_settings').upsert({
        'id': 'global',
        'color_theme': themeKey,
      });
    } catch (e) { _writeFailed('setColorTheme', e); }
  }

  // ── App settings (global welcome-banner quote) ───────────────────────────────

  static Future<Map<String, String>?> fetchBannerQuote() async {
    try {
      final data = await _db
          ?.from('app_settings')
          .select('banner_quote, banner_quote_author')
          .eq('id', 'global')
          .maybeSingle();
      if (data == null) return null;
      return {
        'quote': (data['banner_quote'] as String?) ?? '',
        'author': (data['banner_quote_author'] as String?) ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> setBannerQuote(String quote, String author) async {
    try {
      await _db?.from('app_settings').upsert({
        'id': 'global',
        'banner_quote': quote,
        'banner_quote_author': author,
      });
    } catch (e) { _writeFailed('setBannerQuote', e); }
  }

  // ── Payslip requests ─────────────────────────────────────────────────────

  static Future<List<PayslipRequest>> fetchPayslipRequests() async {
    try {
      final data = await _db
          ?.from('payslip_requests')
          .select()
          .order('requested_at', ascending: false);
      if (data == null) return [];
      return (data as List)
          .map((row) => PayslipRequest.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<PayslipRequest>> fetchPayslipRequestsFor(String employeeId) async {
    try {
      final data = await _db
          ?.from('payslip_requests')
          .select()
          .eq('employee_id', employeeId)
          .order('requested_at', ascending: false);
      if (data == null) return [];
      return (data as List)
          .map((row) => PayslipRequest.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> requestPayslip(PayslipRequest req) async {
    try {
      await _db?.from('payslip_requests').upsert(req.toJson());
    } catch (e) { _writeFailed('requestPayslip', e); }
  }

  static Future<void> decidePayslipRequest(
      String id, PayslipRequestStatus status, String decidedBy,
      {String rejectionComment = ''}) async {
    try {
      await _db?.from('payslip_requests').update({
        'status': status.name,
        'decided_at': DateTime.now().toIso8601String(),
        'decided_by': decidedBy,
        'rejection_comment': rejectionComment,
      }).eq('id', id);
    } catch (e) { _writeFailed('decidePayslipRequest', e); }
  }

  // ── Payslips ──────────────────────────────────────────────────────────────

  static Future<List<Payslip>> fetchPayslips(String employeeId) async {
    try {
      final data = await _db
          ?.from('payslips')
          .select()
          .eq('employee_id', employeeId)
          .order('month_year', ascending: false);
      if (data == null) return [];
      return (data as List)
          .map((row) => Payslip.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePayslip(Payslip p) async {
    try {
      await _db?.from('payslips').upsert(p.toJson());
    } catch (e) { _writeFailed('savePayslip', e); }
  }

  /// All employees' payslips for one month (`'YYYY-MM'`) — unlike
  /// [fetchPayslips], which is scoped to a single employee. Used by the
  /// Reports & Analytics Payroll Summary card.
  static Future<List<Payslip>> fetchPayslipsForMonth(String monthYear) async {
    try {
      final data = await _db
          ?.from('payslips')
          .select()
          .eq('month_year', monthYear);
      if (data == null) return [];
      return (data as List)
          .map((row) => Payslip.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────

  // PostgREST .or() syntax needs values quoted if they might contain a
  // comma/paren; cheap to always quote rather than sniff for it.
  static String _orQuoted(String value) => '"${value.replaceAll('"', '\\"')}"';

  static Future<List<AppNotification>> fetchNotifications() async {
    try {
      // Filtered server-side to just what's addressed to the signed-in user
      // (mirrors NotificationStore.isForCurrentUser) — the poll loop in
      // main.dart hits this every 45s, and an unfiltered fetch means every
      // client downloads the whole company's notification feed each cycle.
      final email = UserSession.email.trim();
      final role = currentRoleLabel();
      final name = UserSession.name.trim();
      final orFilter = [
        if (email.isNotEmpty) 'target_email.eq.${_orQuoted(email)}',
        'target_role.eq.${_orQuoted(role)}',
        'target_role.eq.ALL',
        if (name.isNotEmpty) 'target_reporting_manager.eq.${_orQuoted(name)}',
      ].join(',');
      final data = await _db
          ?.from('notifications')
          .select()
          .or(orFilter)
          .order('created_at', ascending: false)
          .limit(500);
      if (data == null) return [];
      return (data as List).map((row) => AppNotification(
        id:                     row['id'] as String,
        createdAt:              DateTime.parse(row['created_at'] as String),
        type:                   (row['type']  as String?) ?? '',
        title:                  (row['title'] as String?) ?? '',
        body:                   (row['body']  as String?) ?? '',
        route:                  (row['route'] as String?) ?? '',
        targetEmail:            (row['target_email']             as String?) ?? '',
        targetRole:             (row['target_role']               as String?) ?? '',
        targetReportingManager: (row['target_reporting_manager'] as String?) ?? '',
        sourceId:               (row['source_id']                as String?) ?? '',
        readBy: row['read_by'] is List
            ? List<String>.from(row['read_by'] as List)
            : [],
      )).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> insertNotification({
    required String type,
    required String title,
    String body = '',
    String route = '',
    String targetEmail = '',
    String targetRole = '',
    String targetReportingManager = '',
    String sourceId = '',
  }) async {
    try {
      await _db?.from('notifications').insert({
        'type':                     type,
        'title':                    title,
        'body':                     body,
        'route':                    route,
        'target_email':             targetEmail,
        'target_role':              targetRole,
        'target_reporting_manager': targetReportingManager,
        'source_id':                sourceId,
      });
    } catch (e) { _writeFailed('insertNotification', e); }
  }

  static Future<void> markNotificationRead(String id, List<String> readBy) async {
    try {
      await _db?.from('notifications').update({'read_by': readBy}).eq('id', id);
    } catch (e) { _writeFailed('markNotificationRead', e); }
  }

  // ── Push notification device tokens ─────────────────────────────────────

  static Future<void> upsertDeviceToken({
    required String token,
    required String email,
    required String platform,
  }) async {
    try {
      await _db?.from('device_tokens').upsert({
        'token':      token,
        'email':      email,
        'platform':   platform,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) { _writeFailed('upsertDeviceToken', e); }
  }

  static Future<void> deleteDeviceToken(String token) async {
    try {
      await _db?.from('device_tokens').delete().eq('token', token);
    } catch (e) { _writeFailed('deleteDeviceToken', e); }
  }

  // ── Transactional email (Zoho SMTP via the send-email Edge Function) ────

  /// Returns null on success, or an error message on failure — callers show
  /// the message directly (e.g. in a SnackBar) rather than throwing, since
  /// a failed send is an expected, user-facing outcome (bad address, SMTP
  /// hiccup), not a bug.
  ///
  /// [html] and [attachments] are optional additions used by EmailService —
  /// existing plain-text callers are unaffected.
  static Future<String?> sendEmail({
    required String to,
    required String subject,
    required String body,
    String? html,
    List<Map<String, dynamic>>? attachments,
  }) async {
    try {
      final res = await _db?.functions.invoke('send-email', body: {
        'to': to,
        'subject': subject,
        'body': body,
        if (html != null) 'html': html,
        if (attachments != null && attachments.isNotEmpty) 'attachments': attachments,
      });
      if (res == null) return 'Could not send email. Please try again.';
      if (res.status != 200) {
        final data = res.data;
        final err = data is Map && data['error'] is String ? data['error'] as String : null;
        return err ?? 'Could not send email. Please try again.';
      }
      return null;
    } catch (_) {
      return 'Could not send email. Please try again.';
    }
  }

  // ── Pre-Offer PDF upload (same RESUME bucket every other upload uses) ──

  // upsert:true was the actual cause of the 403 — Postgres RLS requires an
  // UPDATE policy for any ON CONFLICT DO UPDATE statement even when the row
  // doesn't exist yet, and the RESUME bucket only has INSERT/SELECT
  // policies for anon (no UPDATE), so upsert always failed regardless of
  // folder path. A plain insert satisfies the existing INSERT policy; a
  // resend for the same candidate hits "Duplicate" (409) instead, which we
  // treat as success since the object (and its PDF) is already there.
  static Future<String> uploadPreOfferPdf(String candidateId, Uint8List bytes) async {
    final path = 'custom_uploads/pre-offer-letter-$candidateId.pdf';
    try {
      await _db!.storage.from('RESUME').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf'),
      );
    } on StorageException catch (e) {
      final isDuplicate = e.statusCode == '409' ||
          e.error?.toLowerCase() == 'duplicate' ||
          e.message.toLowerCase().contains('already exists');
      if (!isDuplicate) rethrow;
    }
    return path;
  }

  /// Short-lived signed URL for a candidate's Pre-Offer Letter PDF — no
  /// extra DB column needed since the storage path is derived from the id.
  /// Was a synchronous getPublicUrl(); now async since it's signed on demand.
  static Future<String?> preOfferPdfUrl(String candidateId) => resolveAttachmentUrl(
        'custom_uploads/pre-offer-letter-$candidateId.pdf',
        bucket: 'RESUME',
      );

  // ── Candidate token lookups (public pre-offer / onboarding-form pages) ──

  // Routed through SECURITY DEFINER RPCs rather than a plain anon
  // .select().eq(token) — see the "Token-gated lookups" section of
  // supabase/migrations/20260716000100_rls_policies.sql for why a raw
  // anon select can't safely stay once RLS is enabled (it would let
  // anyone list every row with a token set, not just the one they know).

  static Future<Map<String, dynamic>?> fetchCandidateByPreOfferToken(String token) async {
    if (token.isEmpty) return null;
    final data = await _db?.rpc('candidate_application_by_pre_offer_token', params: {'p_token': token});
    if (data is List && data.isNotEmpty) return Map<String, dynamic>.from(data.first as Map);
    return null;
  }

  static Future<Map<String, dynamic>?> fetchCandidateByOnboardingToken(String token) async {
    if (token.isEmpty) return null;
    final data = await _db?.rpc('candidate_application_by_onboarding_token', params: {'p_token': token});
    if (data is List && data.isNotEmpty) return Map<String, dynamic>.from(data.first as Map);
    return null;
  }

  /// The personal email a new employee's activation link must go to — their
  /// freshly-assigned @fomrahousing.in address is just a login username at
  /// this point and almost certainly isn't a provisioned mailbox yet, so
  /// sending there looks successful (SMTP accepts it) but nothing arrives.
  /// Prefers the real FK; falls back to the same fuzzy name/mobile match
  /// used elsewhere for older, token-less onboarding submissions.
  static Future<String?> fetchCandidatePersonalEmail({
    String? candidateApplicationId,
    required String name,
    required String mobile,
  }) async {
    try {
      if (candidateApplicationId != null && candidateApplicationId.isNotEmpty) {
        final row = await _db
            ?.from('candidate_applications')
            .select('email')
            .eq('id', candidateApplicationId)
            .maybeSingle();
        final email = (row?['email'] as String?)?.trim();
        if (email != null && email.isNotEmpty) return email;
      }
      if (name.isEmpty) return null;
      final results = await _db
          ?.from('candidate_applications')
          .select('email')
          .or('name.ilike.%$name%${mobile.isNotEmpty ? ",mobile.eq.$mobile" : ""}')
          .limit(1);
      if (results != null && results.isNotEmpty) {
        final email = (results.first['email'] as String?)?.trim();
        if (email != null && email.isNotEmpty) return email;
      }
    } catch (e) { _writeFailed('fetchCandidatePersonalEmail', e); }
    return null;
  }

  /// Used to block duplicate onboarding submissions for the same candidate —
  /// a token-based link can otherwise be resubmitted any number of times.
  static Future<bool> hasOnboardingFormForCandidate(String candidateId) async {
    if (candidateId.isEmpty) return false;
    final data = await _db?.rpc('has_onboarding_form_for_candidate', params: {'p_candidate_id': candidateId});
    return data == true;
  }

  // Returns the existing submission (if any) for this candidate — used to
  // tell a fresh candidate ("nothing submitted yet") apart from one who is
  // revisiting the link after HR sent it back for a correction (data already
  // there, prefill instead of blanking).
  static Future<Map<String, dynamic>?> fetchOnboardingFormForCandidate(String candidateId) async {
    if (candidateId.isEmpty) return null;
    final data = await _db
        ?.from('onboarding_forms')
        .select('id, form_data, needs_correction, fields_to_correct')
        .eq('candidate_application_id', candidateId)
        .maybeSingle();
    return data == null ? null : Map<String, dynamic>.from(data as Map);
  }

  // HR flags specific fields as wrong and sends the submission back to the
  // candidate. The row (and every other field's data) is left untouched —
  // only these two flags change — so the candidate's next visit to the same
  // link can prefill everything and highlight just what needs fixing.
  static Future<void> requestOnboardingCorrection(
    String onboardingFormId,
    List<String> fieldKeys, {
    required String requestedBy,
  }) async {
    await _db?.from('onboarding_forms').update({
      'needs_correction': true,
      'fields_to_correct': fieldKeys,
      'correction_requested_at': DateTime.now().toUtc().toIso8601String(),
      'correction_requested_by': requestedBy,
      'status': 'pending',
    }).eq('id', onboardingFormId);
  }

  // ── Email Logs ───────────────────────────────────────────────────────

  static Future<String?> insertEmailLog(Map<String, dynamic> fields) async {
    final data = await _db
        ?.from('email_logs')
        .insert(fields)
        .select('id')
        .maybeSingle();
    return data?['id'] as String?;
  }

  static Future<void> updateEmailLog(String id, Map<String, dynamic> fields) async {
    await _db?.from('email_logs').update(fields).eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> fetchEmailLogs() async {
    final data = await _db
        ?.from('email_logs')
        .select()
        .order('created_at', ascending: false);
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<Map<String, dynamic>?> fetchEmailLog(String id) async {
    final data = await _db?.from('email_logs').select().eq('id', id).maybeSingle();
    return data;
  }

  /// Next unused employee ID for the business unit, e.g. FHIPL-10 / FD-02.
  /// Advisory only — the database assigns one anyway if the field is left
  /// blank, and rejects a duplicate outright via app_users_employee_id_uidx.
  static Future<String?> nextEmployeeId({String businessUnit = ''}) async {
    try {
      final v = await _db?.rpc('next_employee_id', params: {
        'p_prefix': businessUnit.trim() == 'FOMRA Developers' ? 'FD' : 'FHIPL',
      });
      return v is String && v.isNotEmpty ? v : null;
    } catch (e) {
      // Non-fatal: HR can still type one, and the DB fills a blank itself.
      return null;
    }
  }

  /// Management excuses a late arrival — normally a system fault, such as the
  /// browser refusing the location permission so the employee could not
  /// complete check-in before their start time.
  ///
  /// The recorded TIME is deliberately not altered: it is when the system
  /// accepted the check-in, and rewriting it would falsify the record. The
  /// waiver sits alongside it. Returns null on success, or a message to show.
  /// Location history for Management: where each check-in happened, how
  /// accurate the fix was, and how far from the nearest assigned site.
  ///
  /// Reads v_location_history, which has security_invoker on — so the RLS
  /// policy on attendance_records still applies and an employee querying this
  /// sees only their own movements. Location is personal data.
  /// The monthly attendance sheet, exactly as HR keeps it by hand: one row per
  /// employee for one 26th-to-25th cycle, with working days, days worked,
  /// leave, LOP, lates, permission, pay days and remarks.
  ///
  /// Computed in the database rather than the client so the export cannot
  /// disagree with what the screens show — the same rules for lateness,
  /// exemptions and non-working days apply in one place.
  static Future<List<Map<String, dynamic>>> fetchCycleReport(DateTime cycleEnd) async {
    try {
      final iso = '${cycleEnd.year.toString().padLeft(4, '0')}-'
          '${cycleEnd.month.toString().padLeft(2, '0')}-'
          '${cycleEnd.day.toString().padLeft(2, '0')}';
      final rows = await _db?.rpc('attendance_cycle_report', params: {'p_cycle_end': iso});
      return List<Map<String, dynamic>>.from(rows ?? []);
    } catch (e) {
      _writeFailed('fetchCycleReport', e);
      return [];
    }
  }

  /// Saves the manual REMARKS note for one employee and cycle.
  static Future<String?> saveCycleRemarks(
      String employeeId, String cycleLabel, String remarks) async {
    try {
      await _db?.from('attendance_cycle_remarks').upsert({
        'employee_id': employeeId,
        'cycle_label': cycleLabel,
        'remarks': remarks,
        'updated_by': UserSession.name,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'employee_id,cycle_label');
      return null;
    } catch (e) {
      _writeFailed('saveCycleRemarks', e);
      return 'Could not save the remark. Please try again.';
    }
  }

  static Future<List<Map<String, dynamic>>> fetchLocationHistory({
    String? employeeId,
    String? fromIso,
    String? toIso,
  }) async {
    try {
      var q = _db?.from('v_location_history').select();
      if (q == null) return [];
      if ((employeeId ?? '').isNotEmpty) q = q.eq('employee_id', employeeId!);
      if ((fromIso ?? '').isNotEmpty) q = q.gte('date_iso', fromIso!);
      if ((toIso ?? '').isNotEmpty) q = q.lte('date_iso', toIso!);
      final rows = await q.order('date_iso', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _writeFailed('fetchLocationHistory', e);
      return [];
    }
  }

  static Future<String?> waiveLate(String recordId, String reason) async {
    try {
      await _db?.rpc('waive_late', params: {
        'p_record_id': recordId,
        'p_reason': reason,
      });
      logAuditEvent('late_waived', targetType: 'attendance_records', targetId: recordId);
      return null;
    } catch (e) {
      return _rpcMessage(e);
    }
  }

  static Future<String?> unwaiveLate(String recordId) async {
    try {
      await _db?.rpc('unwaive_late', params: {'p_record_id': recordId});
      logAuditEvent('late_waiver_removed', targetType: 'attendance_records', targetId: recordId);
      return null;
    } catch (e) {
      return _rpcMessage(e);
    }
  }

  // ── Login email change (Management-approved) ───────────────────────────
  // `email` is the credential the login function verifies against, so unlike
  // the other Chain C fields it is enforced in the database — a direct write
  // raises rather than being silently pinned. See
  // supabase/migrations/20260731000200_email_change_requires_approval.sql.

  /// HR (or Management) proposes a new login address. Returns null on
  /// success, or a message to show the user.
  static Future<String?> requestLoginEmailChange(
    String employeeEmail, {
    required String newEmail,
  }) async {
    try {
      final ok = await _db?.rpc('request_login_email_change', params: {
        'p_employee_email': employeeEmail.trim().toLowerCase(),
        'p_new_email': newEmail.trim().toLowerCase(),
      });
      if (ok != true) return 'No account found with that email address.';
      logAuditEvent('login_email_change_requested',
          targetType: 'app_users', targetId: employeeEmail);
      return null;
    } catch (e) {
      return _rpcMessage(e);
    }
  }

  /// Management only. Returns the newly-active address, or an error message.
  static Future<({String? newEmail, String? error})> approveLoginEmailChange(
      String employeeEmail) async {
    try {
      final v = await _db?.rpc('approve_login_email_change',
          params: {'p_employee_email': employeeEmail.trim().toLowerCase()});
      if (v is! String || v.isEmpty) {
        return (newEmail: null, error: 'There is no pending email change for this employee.');
      }
      logAuditEvent('login_email_change_approved',
          targetType: 'app_users', targetId: v);
      return (newEmail: v, error: null);
    } catch (e) {
      return (newEmail: null, error: _rpcMessage(e));
    }
  }

  /// Management only. Returns null on success, or a message to show.
  static Future<String?> rejectLoginEmailChange(String employeeEmail) async {
    try {
      await _db?.rpc('reject_login_email_change',
          params: {'p_employee_email': employeeEmail.trim().toLowerCase()});
      logAuditEvent('login_email_change_rejected',
          targetType: 'app_users', targetId: employeeEmail);
      return null;
    } catch (e) {
      return _rpcMessage(e);
    }
  }

  /// The RPCs raise with human-readable messages ("Only Management can
  /// approve…", "Another account already uses that email address."), so
  /// surface those rather than a raw PostgrestException dump.
  static String _rpcMessage(Object e) {
    if (e is PostgrestException) {
      final m = e.message.trim();
      if (m.isNotEmpty) return m;
    }
    return 'Something went wrong. Please try again.';
  }

  // ── Account activation tokens (Set Your Password flow) ─────────────────

  // .select() + a rows-affected check so a blocked/no-op write throws
  // instead of silently succeeding — otherwise the activation email goes
  // out with a token that was never actually saved, leaving the employee
  // with a permanently "Invalid Activation Link".
  static Future<void> setAppUserActivationToken(
    String email, {
    required String token,
    required String expiresAt,
  }) async {
    final db = _db;
    if (db == null) return;
    // Emails are stored normalised (lowercased + trimmed) by
    // 20260731000100_fix_auth_password_flow.sql, and every server-side RPC
    // matches on lower(email). Normalise here too: a single capital letter
    // used to make this UPDATE match zero rows while the activation email
    // still went out, leaving a permanently dead "Set Your Password" link.
    final rows = await db.from('app_users').update({
      'activation_token': token,
      'activation_token_expires_at': expiresAt,
      'active': false,
    }).eq('email', email.trim().toLowerCase()).select();
    if (rows.isEmpty) {
      throw Exception('Could not save the activation token for $email — check permissions and that the account exists.');
    }
  }

  static Future<Map<String, dynamic>?> fetchAppUserByActivationToken(String token) async {
    if (token.isEmpty) return null;
    final data = await _db?.rpc('app_user_by_activation_token', params: {'p_token': token});
    if (data is List && data.isNotEmpty) return Map<String, dynamic>.from(data.first as Map);
    return null;
  }

  /// Verifies [token] and hashes+sets the password server-side via
  /// complete_account_activation() — see
  /// supabase/migrations/20260716000500_password_flow_rpcs.sql — since this
  /// is called from an anonymous public page (/set-password/{token}),
  /// unlike the service_role-only set_app_user_password RPC. Returns the
  /// activated email on success, or null if the token was invalid/expired.
  static Future<String?> completeAccountActivation(String token, {required String password}) async {
    final email = await _db?.rpc('complete_account_activation',
        params: {'p_token': token, 'p_password': password}) as String?;
    if (email == null) return null;
    // Advances the linked onboarding submission to "Password Created" — only
    // fires from activation_sent so it can't rewind a further-along row.
    try {
      await _db
          ?.from('onboarding_forms')
          .update({
            'status': 'password_created',
            'password_created_at': DateTime.now().toIso8601String(),
          })
          .eq('assigned_email', email)
          .eq('status', 'activation_sent');
    } catch (e) { _writeFailed('completeAccountActivation', e); }
    // "Date of joining" (if not already set) is stamped server-side inside
    // complete_account_activation() itself — see
    // supabase/migrations/20260725010000_stamp_date_of_joining_on_activation.sql.
    // A follow-up client call here would run as anon (no session exists yet
    // at this point in the flow) and get silently rejected by app_users'
    // "to authenticated" RLS policy, same bug class as the password_hash/
    // active-reverting issue fixed in the last few migrations.
    logAuditEvent('account_activated', targetType: 'app_users', targetId: email);
    return email;
  }

  // Advances the linked onboarding submission to "Account Active" the first
  // time the employee actually logs in — only fires from password_created,
  // so repeat logins are a no-op.
  static Future<void> markOnboardingAccountActive(String email) async {
    try {
      await _db
          ?.from('onboarding_forms')
          .update({
            'status': 'access_granted',
            'account_active_at': DateTime.now().toIso8601String(),
          })
          .eq('assigned_email', email)
          .eq('status', 'password_created');
    } catch (e) { _writeFailed('markOnboardingAccountActive', e); }
  }

  // ── Forgot Password tokens (already-active accounts) ───────────────────
  // Deliberately separate from the activation-token flow above: this must
  // never touch `active`, since the employee's existing password should
  // keep working until they actually finish the reset.

  static Future<void> setPasswordResetToken(
    String email, {
    required String token,
    required String expiresAt,
  }) async {
    final db = _db;
    if (db == null) return;
    // Same normalisation + rows-affected guard as the activation-token
    // writer above: a silently-zero-row UPDATE here sent a reset email whose
    // link could never work, which is why "forgot password" never helped.
    final rows = await db.from('app_users').update({
      'reset_password_token': token,
      'reset_password_token_expires_at': expiresAt,
    }).eq('email', email.trim().toLowerCase()).select();
    if (rows.isEmpty) {
      throw Exception('Could not save the password-reset token for $email — check permissions and that the account exists.');
    }
  }

  static Future<Map<String, dynamic>?> fetchAppUserByResetToken(String token) async {
    if (token.isEmpty) return null;
    final data = await _db?.rpc('app_user_by_reset_token', params: {'p_token': token});
    if (data is List && data.isNotEmpty) return Map<String, dynamic>.from(data.first as Map);
    return null;
  }

  /// Verifies [token] and hashes+sets the password server-side via
  /// complete_password_reset() — see
  /// supabase/migrations/20260716000500_password_flow_rpcs.sql. Returns the
  /// reset email on success, or null if the token was invalid/expired.
  static Future<String?> completePasswordReset(String token, {required String password}) async {
    final email = await _db?.rpc('complete_password_reset',
        params: {'p_token': token, 'p_password': password}) as String?;
    if (email != null) {
      logAuditEvent('password_reset', targetType: 'app_users', targetId: email);
    }
    return email;
  }

  /// Self-service password change for an already-logged-in user — via
  /// change_own_password(), which re-verifies [currentPassword] server-side
  /// before setting [newPassword]; see
  /// supabase/migrations/20260725070000_change_own_password_rpc.sql. Returns
  /// true on success, false if the current password didn't match, null if
  /// the call itself failed (network/RPC error).
  static Future<bool?> changeOwnPassword(String currentPassword, String newPassword) async {
    try {
      final ok = await _db?.rpc('change_own_password', params: {
        'p_current_password': currentPassword,
        'p_new_password': newPassword,
      }) as bool?;
      if (ok == true) {
        logAuditEvent('password_changed', targetType: 'app_users', targetId: UserSession.email);
      }
      return ok;
    } catch (_) {
      return null;
    }
  }

  // ── Server-side login (Edge Function) ───────────────────────────────────
  // See supabase/functions/login/index.ts. Replaces fetching the whole
  // app_users table and comparing passwords client-side.

  // ── Audit log ────────────────────────────────────────────────────────
  // See AuditLogService for the callable wrapper — this is the raw RPC call.
  //
  // Swallows its own errors — callers throughout this file call this
  // without awaiting it (fire-and-forget), so if it threw, that would
  // surface as an unhandled async exception with no relation to whatever
  // real operation the caller was actually reporting success/failure for
  // (e.g. a failed audit write must never make saveCheckIn() look like the
  // check-in itself failed). This also means a real check-in/leave-save/
  // activation/etc. still succeeds even before the audit_log migration
  // (20260716000400_audit_log.sql) has been applied.
  static Future<void> logAuditEvent(
    String action, {
    String targetType = '',
    String targetId = '',
    Map<String, dynamic>? details,
  }) async {
    try {
      await _db?.rpc('log_audit_event', params: {
        'p_action': action,
        'p_target_type': targetType,
        'p_target_id': targetId,
        'p_details': details ?? {},
      });
    } catch (e) { _writeFailed('logAuditEvent', e); }
  }

  /// Only succeeds if [email] genuinely has no password yet — via
  /// set_password_if_unset(), see
  /// supabase/migrations/20260716000500_password_flow_rpcs.sql. Called from
  /// an anonymous context (the user isn't signed in yet), so — unlike
  /// set_app_user_password — this can't be used to overwrite an existing
  /// password.
  static Future<bool> setInitialUserPassword(String email, String password) async {
    try {
      final ok = await _db?.rpc('set_password_if_unset', params: {'p_email': email, 'p_password': password});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<LoginResult> login(String email, String password) async {
    final db = _db;
    if (db == null) return const LoginResult(error: 'Not connected');
    try {
      final res = await db.functions.invoke('login', body: {'email': email, 'password': password});
      final data = res.data;
      if (res.status == 200 && data is Map) {
        if (data['needsPasswordSetup'] == true) {
          return LoginResult(
            needsPasswordSetup: true,
            profile: Map<String, dynamic>.from(data['profile'] as Map),
          );
        }
        final refreshToken = data['refresh_token'] as String?;
        if (refreshToken != null) {
          await db.auth.setSession(refreshToken);
        }
        return LoginResult(ok: true, profile: Map<String, dynamic>.from(data['profile'] as Map));
      }
      if (res.status == 403 && data is Map && data['error'] == 'not_activated') {
        return const LoginResult(notActivated: true);
      }
      if (data is Map && data['error'] is String) {
        return LoginResult(error: data['error'] as String);
      }
      return const LoginResult(error: 'Invalid email or password.');
    } on FunctionException catch (e) {
      // supabase_flutter throws instead of returning a handled `res.status`
      // for some non-2xx codes (e.g. 401) — surface the Edge Function's own
      // message when it sent one, never the raw "FunctionException(status:
      // ...)" wrapper, which reads as a crash to a non-technical user.
      final details = e.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : null;
      return LoginResult(error: message ?? 'Invalid email or password.');
    } catch (_) {
      return const LoginResult(error: 'Something went wrong. Please try again.');
    }
  }

  // Revokes the real Supabase Auth session (refresh token) and clears it
  // from local storage. Every "Sign Out" button only clears UserSession /
  // SessionStorage (the app's own logged-in flag) — without this, the
  // underlying auth session stays valid in secure storage, so it gets
  // silently restored by Supabase.initialize() the next time the app
  // launches on this device even though the user "signed out".
  static Future<void> signOut() async {
    try {
      await _db?.auth.signOut();
    } catch (_) {
      // Best-effort — local session/UI state is already being cleared by
      // the caller regardless of whether the network call succeeds.
    }
  }

  // ── Notification preferences (muted categories) ─────────────────────────

  static Future<List<String>> fetchMutedCategories(String email) async {
    if (email.isEmpty) return [];
    try {
      final data = await _db
          ?.from('notification_preferences')
          .select('muted_categories')
          .eq('email', email)
          .maybeSingle();
      final raw = data?['muted_categories'];
      return raw is List ? List<String>.from(raw) : [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> setMutedCategories(String email, List<String> categoryIds) async {
    if (email.isEmpty) return;
    try {
      await _db?.from('notification_preferences').upsert({
        'email': email,
        'muted_categories': categoryIds,
      });
    } catch (e) { _writeFailed('setMutedCategories', e); }
  }

  // ── Initial load on app start ─────────────────────────────────────────

  static Future<void> loadAll() async {
    await Future.wait([
      _loadLeave(),
      _loadMaintenance(),
      _loadProfiles(),
      _loadEmployees(),
      _loadTasks(),
      _loadNotifications(),
      _loadNotificationPreferences(),
    ]);
    await refreshSessionFlags();
  }

  /// Re-read the signed-in user's rule flags from their own record.
  ///
  /// These flags arrive in the login response and are then cached in local
  /// storage, so a session created BEFORE a flag existed keeps the stale
  /// default until the user happens to log out and back in. That is how the
  /// Head of Operations kept being asked for a late reason after the
  /// exemption was already set and deployed: correct data, correct code,
  /// stale session.
  ///
  /// Running on every cold start makes it self-healing, and means the next
  /// flag added does not need anyone to be told to sign out.
  static Future<void> refreshSessionFlags() async {
    if (!UserSession.loggedIn || UserSession.email.isEmpty) return;
    try {
      final me = await UserStore.findByEmail(UserSession.email);
      if (me == null) return;
      UserSession.isOnroll             = me.onrollConfirmedAt.trim().isNotEmpty;
      UserSession.exemptFromTiming     = me.exemptFromTiming;
      UserSession.exemptFromAttendance = me.exemptFromAttendance;
      UserSession.oversightOnly        = me.oversightOnly;
      UserSession.permissionMinutesQuota = me.permissionMinutesQuota;
      UserSession.department           = me.department;
      await SessionStorage.save();
    } catch (_) {
      // Never block startup on this — the cached values still work, they may
      // just be stale.
    }
  }

  static Future<void> _loadNotificationPreferences() async {
    if (UserSession.email.isEmpty) return;
    final muted = await fetchMutedCategories(UserSession.email);
    NotificationStore.mutedCategories = muted.toSet();
    NotificationStore.recomputeUnread();
  }

  static Future<void> _loadNotifications() async {
    final list = await fetchNotifications();
    // Seeds the new-arrival baseline before anything else touches it, so
    // existing history never pops up as if it just arrived.
    NotificationStore.diffNewArrivals(list);
    NotificationStore.all
      ..clear()
      ..addAll(list);
    NotificationStore.recomputeUnread();
  }

  static Future<void> _loadLeave() async {
    final list = await fetchLeaveApplications();
    LeaveStore.applications
      ..clear()
      ..addAll(list);
    LeaveStore.syncCounter();
  }

  static Future<void> _loadMaintenance() async {
    final list = await fetchMaintenanceTickets();
    MaintenanceStore.tickets
      ..clear()
      ..addAll(list);
    MaintenanceStore.syncCounter();
  }

  static Future<void> _loadProfiles() async {
    final list = await fetchProfiles();
    for (final p in list) {
      ProfileStore.saveByHr(p);
    }
  }

  static Future<void> _loadEmployees() async {
    final list = await fetchEmployees();
    EmployeeStore.employees
      ..clear()
      ..addAll(list);
  }

  static Future<void> _loadTasks() async {
    final list = await fetchTasks();
    TaskStore.tasks
      ..clear()
      ..addAll(list);
  }

  // ── Profile photo ─────────────────────────────────────────────────────────
  // Looks up the onboarding form for the given employee ID and returns the
  // URL of the first image attachment (Passport Photo / photo_upload type).
  static Future<String?> fetchCurrentUserPhotoUrl(String employeeId) async {
    final db = _db;
    if (db == null || employeeId.isEmpty) return null;
    try {
      final rows = await db
          .from('onboarding_forms')
          .select('attachments, form_data')
          .eq('assigned_emp_id', employeeId)
          .order('submitted_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) return null;
      final row = list.first;
      // Manually-uploaded photos (via updateCurrentUserPhoto) live in the
      // top-level 'attachments' column; the passport photo submitted with
      // the original onboarding form lives nested inside 'form_data'
      // (only name/phone/designation are ever written top-level on submit).
      // Check the manual upload first so it takes precedence if both exist.
      final formData = row['form_data'];
      final attachments = [
        ...(row['attachments'] is List ? row['attachments'] as List : const []),
        ...(formData is Map && formData['attachments'] is List
            ? formData['attachments'] as List
            : const []),
      ];
      for (final item in attachments) {
        final docType = (item['doc_type'] ?? '').toString().toLowerCase();
        final stored = (item['url'] ?? '').toString();
        if (stored.isNotEmpty &&
            (docType.contains('photo') || docType.contains('passport'))) {
          // Manual re-uploads (updateCurrentUserPhoto) live in the RESUME
          // bucket under profile_photos/; the original onboarding passport
          // photo lives in the 'onboarding attachments' bucket instead —
          // resolveAttachmentUrl auto-detects the bucket for legacy public
          // URLs, but a bare path needs it named explicitly.
          final bucket = stored.startsWith('profile_photos/') ? 'RESUME' : 'onboarding attachments';
          return await resolveAttachmentUrl(stored, bucket: bucket, expiresIn: 86400);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Uploads a new profile photo and stores it as the current user's attachment
  // on their latest onboarding form (the same place fetchCurrentUserPhotoUrl
  // reads from). Stores the bare storage path (not a URL, now that the
  // bucket is private) and returns a signed URL for immediate display.
  static Future<String?> updateCurrentUserPhoto(
      String employeeId, Uint8List bytes, String fileName, String mimeType) async {
    final db = _db;
    if (db == null || employeeId.isEmpty) return null;
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path =
        'profile_photos/${employeeId}_${DateTime.now().millisecondsSinceEpoch}_$safe';
    try {
      await db.storage.from('RESUME').uploadBinary(
        path, bytes,
        fileOptions: FileOptions(
            contentType: mimeType.isNotEmpty ? mimeType : 'image/jpeg'),
      );
    } catch (_) {
      return null;
    }

    try {
      final rows = await db
          .from('onboarding_forms')
          .select('id, attachments')
          .eq('assigned_emp_id', employeeId)
          .order('submitted_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isNotEmpty) {
        final row = list.first;
        final attachments = row['attachments'] is List
            ? List<Map<String, dynamic>>.from(row['attachments'])
            : <Map<String, dynamic>>[];
        attachments.removeWhere((a) {
          final docType = (a['doc_type'] ?? '').toString().toLowerCase();
          return docType.contains('photo') || docType.contains('passport');
        });
        attachments.insert(
            0, {'doc_type': 'photo_upload', 'url': path, 'file_name': fileName});
        await db
            .from('onboarding_forms')
            .update({'attachments': attachments}).eq('id', row['id']);
      }
    } catch (e) { _writeFailed('updateCurrentUserPhoto', e); }

    return resolveAttachmentUrl(path, bucket: 'RESUME', expiresIn: 86400);
  }

  // Removes the current user's manually-uploaded profile photo from their
  // latest onboarding form's 'attachments' column. Returns true on success.
  static Future<bool> deleteCurrentUserPhoto(String employeeId) async {
    final db = _db;
    if (db == null || employeeId.isEmpty) return false;
    try {
      final rows = await db
          .from('onboarding_forms')
          .select('id, attachments')
          .eq('assigned_emp_id', employeeId)
          .order('submitted_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) return false;
      final row = list.first;
      final attachments = row['attachments'] is List
          ? List<Map<String, dynamic>>.from(row['attachments'])
          : <Map<String, dynamic>>[];
      attachments.removeWhere((a) {
        final docType = (a['doc_type'] ?? '').toString().toLowerCase();
        return docType.contains('photo') || docType.contains('passport');
      });
      await db
          .from('onboarding_forms')
          .update({'attachments': attachments}).eq('id', row['id']);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── HR Policy (versioned, approval workflow) ──────────────────────────────
  // Returns the content of the latest approved version, or null if none.
  static Future<String?> fetchHRPolicy() async {
    final db = _db;
    if (db == null) return null;
    try {
      final data = await db
          .from('hr_policy_versions')
          .select('content')
          .eq('status', 'approved')
          .order('approved_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      return list.isEmpty ? null : list.first['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  // Returns all versions (pending / approved / rejected) for the approvals page.
  static Future<List<Map<String, dynamic>>> fetchHRPolicyVersions() async {
    final db = _db;
    if (db == null) return [];
    try {
      final data = await db
          .from('hr_policy_versions')
          .select()
          .order('version_number', ascending: false);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (_) {
      return [];
    }
  }

  // Returns the next version number.
  static Future<int> getNextHRPolicyVersionNumber() async {
    final db = _db;
    if (db == null) return 1;
    try {
      final data = await db
          .from('hr_policy_versions')
          .select('version_number')
          .order('version_number', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      if (list.isEmpty) return 1;
      return ((list.first['version_number'] as int?) ?? 0) + 1;
    } catch (_) {
      return 1;
    }
  }

  // HR submits a new pending policy version for Management approval.
  static Future<void> submitHRPolicyForApproval(
      String content, String createdBy) async {
    final db = _db;
    if (db == null) throw Exception('Database not initialized.');
    final version = await getNextHRPolicyVersionNumber();
    await db.from('hr_policy_versions').insert({
      'version_number': version,
      'content': content,
      'status': 'pending',
      'created_by': createdBy,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // Management approves or rejects a pending version.
  static Future<void> updateHRPolicyVersionStatus(
    String id,
    String status, {
    String decidedBy = '',
    String note = '',
  }) async {
    final db = _db;
    if (db == null) return;
    final update = <String, dynamic>{'status': status};
    if (status == 'approved') {
      update['approved_at'] = DateTime.now().toUtc().toIso8601String();
      update['approved_by'] = decidedBy;
    }
    if (note.isNotEmpty) update['rejection_note'] = note;
    await db.from('hr_policy_versions').update(update).eq('id', id);
  }

  // Returns any pending HR policy version (for showing HR a "pending" banner).
  static Future<Map<String, dynamic>?> fetchPendingHRPolicyVersion() async {
    final db = _db;
    if (db == null) return null;
    try {
      final data = await db
          .from('hr_policy_versions')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(data as List);
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
  }
}
