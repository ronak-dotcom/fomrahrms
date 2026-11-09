-- Every check-in complaint so far has been diagnosed after the fact, by
-- inferring from what is MISSING in attendance_records. A failed attempt
-- leaves no trace at all: if someone taps check-in and it does not work,
-- nothing anywhere records that they tried, what their GPS said, or why it
-- was refused. That is why "Akila cannot check in" took a week and a
-- database archaeology session to explain.
--
-- This logs the attempt itself, successful or not, so a failure is visible
-- the same day rather than reconstructed later.
create table if not exists checkin_attempts (
  id            uuid primary key default gen_random_uuid(),
  employee_id   text not null,
  employee_name text not null default '',
  kind          text not null,              -- 'check_in' | 'check_out'
  outcome       text not null,              -- 'success' | 'blocked' | 'gps_failed' | 'error'
  reason        text default '',            -- why it was blocked, or the error
  lat           double precision,
  lng           double precision,
  accuracy      double precision,
  within_radius boolean,
  nearest_m     double precision,
  platform      text default '',            -- browser / OS, for Safari-style issues
  attempted_at  timestamptz not null default now()
);

create index if not exists checkin_attempts_recent_idx
  on checkin_attempts (attempted_at desc);
create index if not exists checkin_attempts_outcome_idx
  on checkin_attempts (outcome, attempted_at desc) where outcome <> 'success';

alter table checkin_attempts enable row level security;

-- Anyone signed in may log their own attempt; only HR and Management read
-- the diagnostics. Insert is deliberately permissive: a failure to log must
-- never itself block a check-in.
create policy "checkin_attempts_insert" on checkin_attempts
  for insert to authenticated with check (true);
create policy "checkin_attempts_read" on checkin_attempts
  for select to authenticated using (current_app_is_hr_or_mgmt());

comment on table checkin_attempts is
  'Diagnostic log of check-in/out attempts including failures. attendance_records only records successes, so this is the only place a blocked or failed attempt is visible.';
