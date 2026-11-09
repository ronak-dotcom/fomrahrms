-- The 26th is a cycle START, not the end of the previous one, so treating
-- day > 25 as "no cycle earned" gave an employee who joined on the 26th zero
-- accrual for a cycle they worked in full. Whichever day someone joins, they
-- are present for part of that cycle and earn it, so the count is simply the
-- number of cycle starts from their first cycle up to the current one,
-- inclusive.
create or replace function public.cycles_accrued(
  p_joining date, p_date date default current_date
) returns integer language sql stable as $fn$
  with bounds as (
    select public.attendance_cycle_start(
             greatest(public.leave_year_start(p_date),
                      coalesce(p_joining, public.leave_year_start(p_date)))
           ) as first_cycle_start,
           public.attendance_cycle_start(p_date) as current_cycle_start
  )
  select greatest(0,
    (extract(year  from current_cycle_start) - extract(year  from first_cycle_start))::int * 12
  + (extract(month from current_cycle_start) - extract(month from first_cycle_start))::int
  + 1
  )::int
  from bounds;
$fn$;
