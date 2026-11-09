-- Fix: non-working days INSIDE the requested span were added to the total as
-- well as being counted in (to_date - from_date + 1), so Fri-Mon came to 5
-- days instead of 4. Only days pulled in from OUTSIDE the span extend it.
--
-- Both are still reported in sandwich_days, since HR wants to see that a
-- weekly off was consumed either way — but only the outside ones add length.
create or replace function public.apply_sandwich_policy()
returns trigger
language plpgsql
as $function$
declare
  d           date;
  v_outside   int := 0;   -- non-working days pulled in from outside the span
  v_inside    int := 0;   -- non-working days already within the span
  v_prior     int;
  v_total     int;
begin
  if new.leave_type = 'Permission' then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.from_date = old.from_date and new.to_date = old.to_date then
    return new;
  end if;

  -- Immediately before the span, with leave on its far side.
  d := new.from_date - 1;
  if public.is_non_working_day(new.employee_name, d)
     and public.has_leave_on(new.employee_name, d - 1, new.id) then
    v_outside := v_outside + 1;
  end if;

  -- Immediately after.
  d := new.to_date + 1;
  if public.is_non_working_day(new.employee_name, d)
     and public.has_leave_on(new.employee_name, d + 1, new.id) then
    v_outside := v_outside + 1;
  end if;

  -- Inside the span: bracketed by definition, but already counted in the span
  -- length, so they must NOT extend it.
  d := new.from_date;
  while d <= new.to_date loop
    if public.is_non_working_day(new.employee_name, d) then
      v_inside := v_inside + 1;
    end if;
    d := d + 1;
  end loop;

  new.sandwich_days := v_outside + v_inside;
  v_total := (new.to_date - new.from_date) + 1 + v_outside;

  select coalesce(sum(sandwich_days), 0) into v_prior
    from leave_applications
   where lower(btrim(employee_name)) = lower(btrim(new.employee_name))
     and leave_type <> 'Permission'
     and coalesce(manager_status,'') <> 'denied'
     and id is distinct from new.id
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date);

  if new.sandwich_days > 0 and v_prior > 0 then
    new.lop_days := v_total;          -- second sandwich this cycle: all LOP
  else
    new.lop_days := greatest(v_total - 2, 0);   -- CL adjusts at most 2 days
  end if;

  new.days := v_total;
  return new;
end;
$function$;
