-- Two things were conflated in the single 'Management' role: AUTHORITY (who
-- can approve) and RULE APPLICABILITY (which HR rules bind you). They are
-- orthogonal, and two people now need different combinations:
--
--   CEO              — full authority. No attendance, no leave rules, no
--                      payroll, no timing, no geofence. Not in attendance
--                      reporting at all.
--   Head of Operations — full authority, and part of management, BUT leave
--                      and salary DO apply. Only timing and geofence do not.
--
-- So authority stays with the role, and applicability moves to explicit
-- per-employee flags. Deriving exemptions from the role string (as before)
-- cannot express the difference between these two.

-- 1. 'CEO' carries the same authority as 'Management' everywhere.
create or replace function public.current_app_is_hr_or_mgmt()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce(current_app_role(), '') in ('HR', 'Management', 'CEO');
$function$;

create or replace function public.is_management_authority(p_role text)
returns boolean
language sql
immutable
as $function$
  select coalesce(btrim(p_role), '') in ('Management', 'CEO');
$function$;

-- 2. Per-employee exemptions.
alter table app_users add column if not exists exempt_from_timing        boolean not null default false;
alter table app_users add column if not exists exempt_from_geofence      boolean not null default false;
alter table app_users add column if not exists exempt_from_leave_rules   boolean not null default false;
alter table app_users add column if not exists exempt_from_attendance    boolean not null default false;
alter table app_users add column if not exists payroll_eligible          boolean not null default true;

comment on column app_users.exempt_from_timing      is 'No fixed working hours — never assessed for lateness or early departure.';
comment on column app_users.exempt_from_geofence    is 'No fixed base — check-in is never assessed against an office radius.';
comment on column app_users.exempt_from_leave_rules is 'Not on the leave cycle: no probation cap, no permission quota or duration limits.';
comment on column app_users.exempt_from_attendance  is 'Excluded from attendance entirely, including dashboards and reports.';
comment on column app_users.payroll_eligible        is 'Appears in payroll runs. False for the CEO.';

-- 3. Apply to the CEO.
alter table app_users disable trigger trg_protect_app_users;

update app_users
   set role                    = 'CEO',
       designation             = case when coalesce(btrim(designation),'') = ''
                                      then 'Chief Executive Officer' else designation end,
       exempt_from_timing      = true,
       exempt_from_geofence    = true,
       exempt_from_leave_rules = true,
       exempt_from_attendance  = true,
       payroll_eligible        = false
 where employee_id = 'FHIPL-01';

alter table app_users enable trigger trg_protect_app_users;

-- 4. Rule checks now read the flags, not the role.
create or replace function public.is_exempt_from_leave_rules(p_employee_id text, p_employee_name text)
returns boolean
language sql
stable
as $function$
  select coalesce(exempt_from_leave_rules, false)
    from app_users
   where (coalesce(p_employee_id,'') <> '' and employee_id = p_employee_id)
      or (coalesce(p_employee_id,'') =  '' and lower(btrim(name)) = lower(btrim(p_employee_name)))
   limit 1;
$function$;

create or replace function public.enforce_probation_leave_rules()
returns trigger language plpgsql as $function$
declare v_used integer;
begin
  if coalesce(public.is_exempt_from_leave_rules(new.employee_id, new.employee_name), false) then
    return new;
  end if;
  if coalesce(public.is_employee_confirmed(new.employee_id, new.employee_name), false) then
    return new;
  end if;

  if new.leave_type = 'Permission' then
    raise exception
      'Permission is not available during probation. It becomes available once employment is confirmed.'
      using errcode = 'check_violation';
  end if;

  select count(*) into v_used from leave_applications
   where leave_type <> 'Permission' and id is distinct from new.id
     and coalesce(manager_status,'') <> 'denied'
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date)
     and ((coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
       or (coalesce(new.employee_id,'') =  '' and lower(btrim(employee_name)) = lower(btrim(new.employee_name))));

  if v_used >= 1 then
    raise exception
      'Probation allows one leave per cycle (% to %), and one has already been taken. Further leave becomes available once employment is confirmed.',
      to_char(public.attendance_cycle_start(new.from_date),'DD Mon'),
      to_char(public.attendance_cycle_end(new.from_date),'DD Mon')
      using errcode = 'check_violation';
  end if;
  return new;
end; $function$;

create or replace function public.set_and_check_permission_minutes()
returns trigger language plpgsql as $function$
declare v_quota integer; v_used integer;
begin
  if new.leave_type is distinct from 'Permission' then
    new.permission_minutes := null; return new;
  end if;
  if new.permission_minutes is null then
    new.permission_minutes :=
      public.permission_minutes_from_text(split_part(coalesce(new.reason,''), '|', 1));
  end if;
  if coalesce(public.is_exempt_from_leave_rules(new.employee_id, new.employee_name), false) then
    return new;
  end if;

  if new.permission_minutes is null or new.permission_minutes not in (30,60,120) then
    raise exception
      'Permission must be 30, 60 or 120 minutes. The allowance of 120 minutes per attendance cycle can be taken as 4x30, 2x60 or 1x120.'
      using errcode='check_violation';
  end if;

  select coalesce(permission_minutes_quota,120) into v_quota from app_users
   where (coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
      or (coalesce(new.employee_id,'') =  '' and lower(btrim(name)) = lower(btrim(new.employee_name)))
   limit 1;
  v_quota := coalesce(v_quota,120);

  select coalesce(sum(permission_minutes),0) into v_used from leave_applications
   where leave_type='Permission' and id is distinct from new.id
     and coalesce(manager_status,'') <> 'denied'
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date)
     and ((coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
       or (coalesce(new.employee_id,'') =  '' and lower(btrim(employee_name)) = lower(btrim(new.employee_name))));

  if v_used + new.permission_minutes > v_quota then
    raise exception
      'Permission allowance exhausted for this cycle (% to %): % of % minutes already used, and this request is a further %.',
      to_char(public.attendance_cycle_start(new.from_date),'DD Mon'),
      to_char(public.attendance_cycle_end(new.from_date),'DD Mon'),
      v_used, v_quota, new.permission_minutes using errcode='check_violation';
  end if;
  return new;
end; $function$;

-- 5. Views driven by flags.
create or replace view public.v_payroll_eligible_employees as
  select employee_id, name, email, department, designation, gross_pay,
         date_of_joining, onroll_confirmed_at
    from app_users
   where active and coalesce(payroll_eligible, true);

create or replace view public.v_attendance_tracked_employees as
  select employee_id, name, email, department, designation, role
    from app_users
   where active and not coalesce(exempt_from_attendance, false);

comment on view public.v_attendance_tracked_employees is
  'Employees who should appear in attendance dashboards and reports. The CEO is excluded.';
