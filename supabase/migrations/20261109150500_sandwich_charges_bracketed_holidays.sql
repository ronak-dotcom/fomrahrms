-- A sandwiched weekly off was charged; a sandwiched public holiday was not.
--
-- is_non_working_day() already returns true for a holiday, but the loop
-- tested the holidays table first and subtracted those days outright, so the
-- holiday branch always won. Akila Varshini.J (4-9 Nov) and Deepak S
-- (7-10 Nov) both took leave either side of Diwali and neither was charged
-- for it, while Saurabh Chandak was correctly charged for the Sunday inside
-- his 10-14 October leave. Bracketing a declared festival is precisely what
-- a sandwich rule exists to catch.
--
-- Charged only when genuinely bracketed — a working day of leave before it
-- AND after it, inside the same request. Counting every non-working day in
-- the span instead would charge R. Chandru a full day for 20 October, which
-- is Ayutha Pooja and the whole of his request: nothing sandwiches it, and
-- he was never due to work it.
--
-- Applied to existing records as well, by re-running the trigger with
-- app.recalc_sandwich set. Three rows moved: Yuvaraj S 2 -> 3 days,
-- Akila Varshini.J 5 -> 6, Deepak S 3 -> 4.
create or replace function public.apply_sandwich_policy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare d date; v_outside int := 0; v_inside int := 0;
        v_working int := 0; v_first_w date; v_last_w date;
        v_prior int; v_total numeric(5,1);
begin
  if new.leave_type = 'Permission' then return new; end if;
  -- The recalculation needs to re-run this on rows whose dates have not
  -- moved; everyday updates still skip it.
  if tg_op = 'UPDATE' and new.from_date = old.from_date and new.to_date = old.to_date
     and new.is_half_day is not distinct from old.is_half_day
     and coalesce(current_setting('app.recalc_sandwich', true), '') <> 'on' then
    return new;
  end if;

  -- Leave on the far side of an adjacent non-working day: the same sandwich,
  -- split across two requests.
  d := new.from_date - 1;
  if public.is_non_working_day(new.employee_name, d)
     and public.has_leave_on(new.employee_name, d - 1, new.id) then
    v_outside := v_outside + 1;
  end if;
  d := new.to_date + 1;
  if public.is_non_working_day(new.employee_name, d)
     and public.has_leave_on(new.employee_name, d + 1, new.id) then
    v_outside := v_outside + 1;
  end if;

  -- First and last day actually due to be worked, which is what a
  -- non-working day has to sit between to count as sandwiched.
  select min(dd), max(dd), count(*)
    into v_first_w, v_last_w, v_working
    from generate_series(new.from_date, new.to_date, interval '1 day') g(dd)
   where not public.is_non_working_day(new.employee_name, g.dd::date);

  d := new.from_date;
  while d <= new.to_date loop
    if public.is_non_working_day(new.employee_name, d)
       and v_first_w is not null and d > v_first_w and d < v_last_w then
      v_inside := v_inside + 1;
    end if;
    d := d + 1;
  end loop;

  new.sandwich_days := v_outside + v_inside;
  -- Working days plus the non-working days they bracket. A non-working day
  -- that is not bracketed costs nothing.
  v_total := v_working + v_inside + v_outside;

  -- A half day is 0.5, and only meaningful on a single-day request.
  if coalesce(new.is_half_day,false) and (new.to_date = new.from_date) then
    v_total := 0.5;
    new.sandwich_days := 0;
  end if;
  if v_total < 0 then v_total := 0; end if;

  select coalesce(sum(sandwich_days),0) into v_prior from leave_applications
   where lower(btrim(employee_name)) = lower(btrim(new.employee_name))
     and leave_type <> 'Permission'
     and coalesce(manager_status,'') not in ('denied','cancelled')
     and id is distinct from new.id
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date);

  if new.sandwich_days > 0 and v_prior > 0 then
    new.lop_days := ceil(v_total);
  else
    new.lop_days := greatest(ceil(v_total) - 2, 0);
  end if;

  new.days := v_total;
  return new;
end;
$$;

-- Recalculate existing rows under the corrected rule.
do $$
begin
  perform set_config('app.recalc_sandwich', 'on', true);
  update leave_applications set to_date = to_date where leave_type <> 'Permission';
end $$;
