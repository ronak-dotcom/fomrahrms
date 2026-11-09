-- Management is an oversight / super-admin role, not an employee subject to HR
-- rules. They are not on the leave cycle, not on payroll, have no fixed hours
-- and no fixed base, and are never "on probation" — Sharad Fomra had a blank
-- onroll_confirmed_at simply because the confirmation workflow was never run
-- for him, which under the probation rules would have limited the MD to one
-- leave per cycle and no permission.
--
-- Exempting by ROLE rather than by confirming him keeps the distinction
-- honest: he is not a confirmed employee, he is not an employee for these
-- purposes at all.

create or replace function public.is_management(p_employee_id text, p_employee_name text)
returns boolean
language sql
stable
as $function$
  select coalesce(lower(btrim(role)), '') = 'management'
    from app_users
   where (coalesce(p_employee_id,'') <> '' and employee_id = p_employee_id)
      or (coalesce(p_employee_id,'') =  '' and lower(btrim(name)) = lower(btrim(p_employee_name)))
   limit 1;
$function$;

-- Probation rules: Management is exempt entirely.
create or replace function public.enforce_probation_leave_rules()
returns trigger
language plpgsql
as $function$
declare
  v_confirmed boolean;
  v_used      integer;
begin
  if coalesce(public.is_management(new.employee_id, new.employee_name), false) then
    return new;                      -- not subject to leave rules at all
  end if;

  v_confirmed := coalesce(
    public.is_employee_confirmed(new.employee_id, new.employee_name), false);
  if v_confirmed then
    return new;
  end if;

  if new.leave_type = 'Permission' then
    raise exception
      'Permission is not available during probation. It becomes available once employment is confirmed.'
      using errcode = 'check_violation';
  end if;

  select count(*) into v_used
    from leave_applications
   where leave_type <> 'Permission'
     and id is distinct from new.id
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
end;
$function$;

-- Permission quota: Management is exempt too.
create or replace function public.set_and_check_permission_minutes()
returns trigger
language plpgsql
as $function$
declare
  v_quota integer;
  v_used  integer;
begin
  if new.leave_type is distinct from 'Permission' then
    new.permission_minutes := null;
    return new;
  end if;

  if new.permission_minutes is null then
    new.permission_minutes :=
      public.permission_minutes_from_text(split_part(coalesce(new.reason,''), '|', 1));
  end if;

  if coalesce(public.is_management(new.employee_id, new.employee_name), false) then
    return new;                      -- no quota, no duration restriction
  end if;

  if new.permission_minutes is null or new.permission_minutes not in (30, 60, 120) then
    raise exception
      'Permission must be 30, 60 or 120 minutes. The allowance of 120 minutes per attendance cycle can be taken as 4x30, 2x60 or 1x120.'
      using errcode = 'check_violation';
  end if;

  select coalesce(permission_minutes_quota, 120) into v_quota
    from app_users
   where (coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
      or (coalesce(new.employee_id,'') =  '' and lower(btrim(name)) = lower(btrim(new.employee_name)))
   limit 1;
  v_quota := coalesce(v_quota, 120);

  select coalesce(sum(permission_minutes), 0) into v_used
    from leave_applications
   where leave_type = 'Permission'
     and id is distinct from new.id
     and coalesce(manager_status,'') <> 'denied'
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date)
     and ((coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
       or (coalesce(new.employee_id,'') =  '' and lower(btrim(employee_name)) = lower(btrim(new.employee_name))));

  if v_used + new.permission_minutes > v_quota then
    raise exception
      'Permission allowance exhausted for this cycle (% to %): % of % minutes already used, and this request is a further %.',
      to_char(public.attendance_cycle_start(new.from_date),'DD Mon'),
      to_char(public.attendance_cycle_end(new.from_date),'DD Mon'),
      v_used, v_quota, new.permission_minutes
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

-- Management is not on payroll. Flag it in the data rather than relying on
-- everyone remembering, so the phase-2 payroll run can exclude them by query
-- instead of by convention.
create or replace view public.v_payroll_eligible_employees as
  select employee_id, name, email, department, designation, gross_pay,
         date_of_joining, onroll_confirmed_at
    from app_users
   where active
     and lower(btrim(coalesce(role,''))) <> 'management';

comment on view public.v_payroll_eligible_employees is
  'Employees who should appear in a payroll run. Management is an oversight role and is excluded — they are not on payroll, not on the leave cycle, and have no fixed hours.';
