-- Employees request On Duty in advance; the reporting manager or HR
-- approves. Deliberately NOT routed through leave_applications: an unknown
-- leave type falls through effectiveBucket() to 'CL', so an On Duty day
-- would have silently deducted a casual leave — the opposite of the intent,
-- since the person was working.
create table if not exists on_duty_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id   text not null,
  employee_name text not null default '',
  date_iso      date not null,
  reason        text not null default '',
  status        text not null default 'pending',   -- pending | approved | denied
  requested_at  timestamptz not null default now(),
  decided_by    text default '',
  decided_at    timestamptz,
  unique (employee_id, date_iso)
);

alter table on_duty_requests enable row level security;

-- Employees see and raise their own; managers see their reports; HR and
-- Management see everything. Mirrors the attendance_records policy so the
-- two cannot disagree about who may look at whom.
create policy "on_duty_requests_access" on on_duty_requests
  for all to authenticated
  using (employee_id = current_app_employee_id()
         or app_manages(employee_name)
         or current_app_is_hr_or_mgmt())
  with check (employee_id = current_app_employee_id()
         or app_manages(employee_name)
         or current_app_is_hr_or_mgmt());

-- Applies an approved request to the attendance record whichever way round
-- the two arrive: the employee may request days ahead of checking in, or
-- retrospectively after the record already exists.
create or replace function public.apply_on_duty_request()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.status = 'approved' then
    update attendance_records
       set on_duty = true,
           on_duty_reason = new.reason,
           on_duty_set_by = coalesce(new.decided_by, '')
     where employee_id = new.employee_id and date_iso = new.date_iso;
  elsif new.status = 'denied' and coalesce(old.status,'') = 'approved' then
    update attendance_records
       set on_duty = false, on_duty_reason = '', on_duty_set_by = ''
     where employee_id = new.employee_id and date_iso = new.date_iso;
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_apply_on_duty_request on on_duty_requests;
create trigger trg_apply_on_duty_request
  after insert or update of status on on_duty_requests
  for each row execute function apply_on_duty_request();

-- The other order: the request was approved before the employee checked in,
-- so the record does not exist yet. Stamps the flag as the record is created.
create or replace function public.set_on_duty_from_request()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare r record;
begin
  if new.on_duty then return new; end if;
  select reason, decided_by into r from on_duty_requests
   where employee_id = new.employee_id and date_iso = new.date_iso
     and status = 'approved' limit 1;
  if found then
    new.on_duty := true;
    new.on_duty_reason := r.reason;
    new.on_duty_set_by := coalesce(r.decided_by,'');
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_set_on_duty_from_request on attendance_records;
create trigger trg_set_on_duty_from_request
  before insert on attendance_records
  for each row execute function set_on_duty_from_request();
