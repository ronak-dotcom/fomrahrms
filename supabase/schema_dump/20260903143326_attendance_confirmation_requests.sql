-- When a device cannot produce the evidence check-in normally requires -
-- camera blocked, location denied, no GPS fix - the employee currently has
-- no way to record attendance at all. One employee lost a week to exactly
-- this. The alternative is a person vouching for them instead of a device:
-- the reporting manager confirms presence, and HR can see who confirmed
-- what, so a waived requirement is visible rather than invisible.
--
-- Deliberately its own table rather than another set of *_pending columns on
-- app_users: this is per-day and per-request, not a standing property of the
-- employee, and folding it into the user row is what made the existing
-- approvals hard to find.
create table if not exists attendance_confirmations (
  id             uuid primary key default gen_random_uuid(),
  employee_id    text not null,
  employee_name  text not null default '',
  date_iso       date not null,
  kind           text not null default 'check_in',   -- check_in | check_out
  claimed_time   text not null default '',           -- HH:MM the employee states
  employee_note  text default '',
  -- Why the device could not verify: the raw failure, carried from
  -- checkin_attempts so the manager sees what actually went wrong rather
  -- than taking the employee's word for the reason.
  failure_reason text default '',
  lat            double precision,
  lng            double precision,
  accuracy       double precision,

  status         text not null default 'pending',    -- pending | confirmed | rejected
  -- Who decided. Kept separate from status so HR can see the reporting
  -- manager's name against the decision, which is the point of routing it
  -- to the manager rather than to HR.
  decided_by      text default '',
  decided_by_name text default '',
  decided_at      timestamptz,
  decision_note   text default '',

  requested_at   timestamptz not null default now(),
  unique (employee_id, date_iso, kind)
);

create index if not exists attendance_confirmations_pending_idx
  on attendance_confirmations (status, date_iso desc) where status = 'pending';

alter table attendance_confirmations enable row level security;

-- Employee raises and sees their own; the reporting manager sees and decides
-- for their reports; HR and Management see everything, including who
-- confirmed it. app_manages() is the same helper attendance_records uses, so
-- "my team" means the same thing in both places.
create policy "attendance_confirmations_access" on attendance_confirmations
  for all to authenticated
  using (employee_id = current_app_employee_id()
         or app_manages(employee_name)
         or current_app_is_hr_or_mgmt())
  with check (employee_id = current_app_employee_id()
         or app_manages(employee_name)
         or current_app_is_hr_or_mgmt());

comment on table attendance_confirmations is
  'Manager-vouched attendance for days a device could not verify. Confirmed rows write through to attendance_records; HR retains visibility of who confirmed.';
