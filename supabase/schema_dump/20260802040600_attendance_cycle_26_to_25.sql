-- The attendance cycle runs 26th -> 25th, not 1st -> end of month.
--
-- Everything in this system assumed calendar months, including the permission
-- quota trigger added earlier this week: date_trunc('month', from_date) puts
-- 26 Jul and 3 Aug in DIFFERENT windows when they are in the SAME cycle. An
-- employee could spend their full 120 minutes on 24-25 July and another full
-- 120 on 26 July, because the calendar month rolled over mid-cycle.
--
-- Cycle naming: the cycle is labelled by the month it ENDS in, so
-- 26 Jul -> 25 Aug is the "August" cycle. That matches how the period is
-- normally referred to and how it will be paid.

create or replace function public.attendance_cycle_start(d date)
returns date
language sql
immutable
returns null on null input
as $function$
  select case
    when extract(day from d) >= 26
      then make_date(extract(year from d)::int, extract(month from d)::int, 26)
    else (make_date(extract(year from d)::int, extract(month from d)::int, 26)
            - interval '1 month')::date
  end;
$function$;

create or replace function public.attendance_cycle_end(d date)
returns date
language sql
immutable
returns null on null input
as $function$
  select (public.attendance_cycle_start(d) + interval '1 month' - interval '1 day')::date;
$function$;

-- 'YYYY-MM' of the month the cycle ends in — the cycle's label.
create or replace function public.attendance_cycle_label(d date)
returns text
language sql
immutable
returns null on null input
as $function$
  select to_char(public.attendance_cycle_end(d), 'YYYY-MM');
$function$;

grant execute on function public.attendance_cycle_start(date) to authenticated, service_role;
grant execute on function public.attendance_cycle_end(date)   to authenticated, service_role;
grant execute on function public.attendance_cycle_label(date) to authenticated, service_role;

-- Repoint the permission quota at the cycle instead of the calendar month.
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

  -- Same ATTENDANCE CYCLE (26th -> 25th), not the same calendar month.
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
