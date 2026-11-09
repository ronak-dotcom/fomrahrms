-- Sandwich Leave Policy (Help Center 4.4). Written down since the system was
-- built, never implemented — leave days were counted exactly as submitted.
--
--   Leave on BOTH sides of a weekly off or holiday -> that day counts as leave.
--   Leave on only one side -> it does not.
--   Type depends on balance: CL where available, at most 2 CL adjusted
--   (matching 4.3, "CL can be availed up to 2 days at a time"), remainder LOP.
--   A Sat/Sun/Mon sandwich is allowed once per cycle; a second one in the same
--   cycle makes BOTH days LOP.
--
-- "Once a month" is read as once per ATTENDANCE CYCLE (26th-25th), consistent
-- with the permission quota and everything else that resets periodically.

alter table leave_applications
  add column if not exists sandwich_days int not null default 0,
  add column if not exists lop_days      int not null default 0;

comment on column leave_applications.sandwich_days is
  'Weekly-off or holiday days pulled in because leave falls on both sides of them.';
comment on column leave_applications.lop_days is
  'Days of this request treated as loss of pay: beyond the 2-day CL adjustment, or a repeat sandwich in the same cycle.';

-- Is this date a non-working day for this employee?
create or replace function public.is_non_working_day(p_employee_name text, p_date date)
returns boolean
language plpgsql
stable
as $function$
declare v_off text; v_weekday int;
begin
  if exists (select 1 from holidays where holiday_date = p_date) then
    return true;
  end if;
  select coalesce(nullif(btrim(weekly_off_day),''), 'Sunday') into v_off
    from app_users where lower(btrim(name)) = lower(btrim(p_employee_name)) limit 1;
  v_weekday := case lower(coalesce(v_off,'Sunday'))
    when 'monday' then 1 when 'tuesday' then 2 when 'wednesday' then 3
    when 'thursday' then 4 when 'friday' then 5 when 'saturday' then 6
    else 7 end;
  return extract(isodow from p_date)::int = v_weekday;
end;
$function$;

-- Does this employee have non-denied leave covering p_date?
create or replace function public.has_leave_on(p_employee_name text, p_date date, p_exclude_id text)
returns boolean
language sql
stable
as $function$
  select exists (
    select 1 from leave_applications
     where lower(btrim(employee_name)) = lower(btrim(p_employee_name))
       and leave_type <> 'Permission'
       and coalesce(manager_status,'') <> 'denied'
       and id is distinct from coalesce(p_exclude_id,'')
       and p_date between from_date and to_date
  );
$function$;

create or replace function public.apply_sandwich_policy()
returns trigger
language plpgsql
as $function$
declare
  d            date;
  v_sandwich   int := 0;
  v_span       int;
  v_prior      int;
  v_total      int;
begin
  if new.leave_type = 'Permission' then
    return new;
  end if;

  -- Only recompute for a new or rescheduled request, so an approval decision
  -- does not re-derive the figures on an existing row.
  if tg_op = 'UPDATE' and new.from_date = old.from_date and new.to_date = old.to_date then
    return new;
  end if;

  -- A non-working day immediately BEFORE the request, with leave on its far
  -- side, is sandwiched. Same for the day immediately after.
  d := new.from_date - 1;
  if public.is_non_working_day(new.employee_name, d)
     and public.has_leave_on(new.employee_name, d - 1, new.id) then
    v_sandwich := v_sandwich + 1;
  end if;

  d := new.to_date + 1;
  if public.is_non_working_day(new.employee_name, d)
     and public.has_leave_on(new.employee_name, d + 1, new.id) then
    v_sandwich := v_sandwich + 1;
  end if;

  -- Non-working days INSIDE the requested span always count: the employee is
  -- on leave either side of them by definition.
  d := new.from_date;
  while d <= new.to_date loop
    if public.is_non_working_day(new.employee_name, d) then
      v_sandwich := v_sandwich + 1;
    end if;
    d := d + 1;
  end loop;

  new.sandwich_days := v_sandwich;
  v_span := (new.to_date - new.from_date) + 1 + greatest(v_sandwich - 0, 0);

  -- How many sandwiches has this employee already had this cycle?
  select coalesce(sum(sandwich_days), 0) into v_prior
    from leave_applications
   where lower(btrim(employee_name)) = lower(btrim(new.employee_name))
     and leave_type <> 'Permission'
     and coalesce(manager_status,'') <> 'denied'
     and id is distinct from new.id
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date);

  v_total := (new.to_date - new.from_date) + 1 + v_sandwich;

  if v_sandwich > 0 and v_prior > 0 then
    -- Second sandwich in the same cycle: the whole thing is loss of pay.
    new.lop_days := v_total;
  else
    -- CL adjusts at most 2 days; anything beyond that is LOP.
    new.lop_days := greatest(v_total - 2, 0);
  end if;

  new.days := v_total;
  return new;
end;
$function$;

drop trigger if exists trg_apply_sandwich_policy on leave_applications;
create trigger trg_apply_sandwich_policy
  before insert or update on leave_applications
  for each row execute function public.apply_sandwich_policy();
