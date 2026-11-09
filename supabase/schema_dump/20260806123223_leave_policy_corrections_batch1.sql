-- Three corrections against the written HR policy.

-- ── 1. Probation employees DO get permission ────────────────────────────────
-- I was told "no permissions" and implemented a hard block. The written policy
-- says the opposite: "Employees on Probation ... Eligible for permissions as
-- per the Permission Policy." So probation restricts LEAVE (one day per month,
-- emergencies only, no CL/ML/EL) but not permission.
create or replace function public.enforce_probation_leave_rules()
returns trigger language plpgsql as $function$
declare v_used integer;
begin
  if coalesce(public.is_exempt_from_leave_rules(new.employee_id, new.employee_name), false) then
    return new;
  end if;

  -- Permission is available on probation. Its own quota still applies via
  -- set_and_check_permission_minutes().
  if new.leave_type = 'Permission' then
    return new;
  end if;

  if coalesce(public.is_employee_confirmed(new.employee_id, new.employee_name), false) then
    return new;
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

-- ── 2. Earned leave accrues from CONFIRMATION, not from joining ─────────────
-- start_el_on_confirmation() seeded el_eligible_at from date_of_joining, so
-- probation service counted and people accrued roughly a year early.
create or replace function public.start_el_on_confirmation()
returns trigger language plpgsql as $function$
begin
  if coalesce(btrim(new.onroll_confirmed_at),'') <> ''
     and coalesce(btrim(old.onroll_confirmed_at),'') = ''
     and coalesce(btrim(new.el_eligible_at),'') = '' then
    -- The confirmation date itself. Probation service does not count towards
    -- earned leave.
    new.el_eligible_at := left(btrim(new.onroll_confirmed_at), 10);
  end if;
  return new;
end; $function$;

-- Correct the one employee already seeded from their joining date.
alter table app_users disable trigger trg_protect_app_users;
update app_users
   set el_eligible_at = left(btrim(onroll_confirmed_at), 10)
 where coalesce(btrim(onroll_confirmed_at),'') <> ''
   and coalesce(btrim(el_eligible_at),'') <> ''
   and left(btrim(el_eligible_at),10) <> left(btrim(onroll_confirmed_at),10);
alter table app_users enable trigger trg_protect_app_users;

-- ── 3. Management does not approve its own change ───────────────────────────
-- If Management sets someone as a Reporting Manager, requiring Management to
-- then approve it is asking the same person to approve themselves. Only a
-- change made by HR needs sign-off.
--
-- Applies to every approval-gated field, not just is_reporting_manager: the
-- reasoning is identical for pay, work location and the rest.
create or replace function public.auto_approve_management_changes()
returns trigger
language plpgsql
as $function$
begin
  if not public.is_management_authority(coalesce(current_app_role(), '')) then
    return new;
  end if;

  -- Management is the approving authority, so a pending value it just set is
  -- already approved. Commit it and clear the pending state.
  if coalesce(new.is_reporting_manager_pending::text,'') <> ''
     and new.is_reporting_manager_pending is distinct from old.is_reporting_manager_pending then
    new.is_reporting_manager := new.is_reporting_manager_pending;
    new.is_reporting_manager_pending := false;
    new.is_reporting_manager_requested_at := '';
  end if;

  if coalesce(new.work_location_pending,'') <> ''
     and new.work_location_pending is distinct from old.work_location_pending then
    new.work_location := new.work_location_pending;
    new.work_location_pending := '';
    new.work_location_requested_at := '';
  end if;

  if coalesce(new.weekly_off_day_pending,'') <> ''
     and new.weekly_off_day_pending is distinct from old.weekly_off_day_pending then
    new.weekly_off_day := new.weekly_off_day_pending;
    new.weekly_off_day_pending := '';
    new.weekly_off_day_requested_at := '';
  end if;

  if coalesce(new.reporting_manager_pending,'') <> ''
     and new.reporting_manager_pending is distinct from old.reporting_manager_pending then
    new.reporting_manager := new.reporting_manager_pending;
    new.reporting_manager_pending := '';
    new.reporting_manager_requested_at := '';
  end if;

  if coalesce(new.business_unit_pending,'') <> ''
     and new.business_unit_pending is distinct from old.business_unit_pending then
    new.business_unit := new.business_unit_pending;
    new.business_unit_pending := '';
    new.business_unit_requested_at := '';
  end if;

  if coalesce(new.gross_pay_pending,0) <> 0
     and new.gross_pay_pending is distinct from old.gross_pay_pending then
    new.gross_pay := new.gross_pay_pending;
    new.gross_pay_pending := 0;
    new.gross_pay_requested_at := '';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_auto_approve_management_changes on app_users;
create trigger trg_auto_approve_management_changes
  before update on app_users
  for each row execute function public.auto_approve_management_changes();
