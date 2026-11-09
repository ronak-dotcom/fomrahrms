-- Permission LOP lands on the day it happened, but payroll reads the cycle
-- sheet — so without a column here a half-day deduction would be invisible at
-- the moment it matters. Added as its own figure rather than folded into
-- lop_days, which counts full days of leave: merging them would make a
-- half-day permission overrun indistinguishable from an unpaid absence.
create or replace function public.permission_lop_days(
  p_employee_id text, p_date date default current_date
) returns numeric language sql stable as $fn$
  select coalesce(count(*) * 0.5, 0)::numeric
    from leave_applications l
   where l.employee_id = p_employee_id
     and l.leave_type = 'Permission'
     and coalesce(l.permission_lop_half_day, false)
     and case when l.management_status <> 'pending'
              then l.management_status else l.manager_status end = 'approved'
     and l.from_date >= public.attendance_cycle_start(p_date)
     and l.from_date <= public.attendance_cycle_end(p_date);
$fn$;

-- Total minutes taken this cycle, so HR can see who is close to the limit
-- rather than only who has passed it.
create or replace function public.permission_minutes_report(
  p_cycle_end date default current_date
)
returns table(employee_name text, employee_code text,
              minutes_used integer, quota integer, lop_half_days numeric)
language sql stable as $fn$
  select u.name, u.employee_id,
         public.permission_minutes_used(u.employee_id, p_cycle_end),
         coalesce(u.permission_minutes_quota, 120),
         public.permission_lop_days(u.employee_id, p_cycle_end)
    from app_users u
   where u.active and not coalesce(u.oversight_only, false)
     and not coalesce(u.exempt_from_attendance, false)
   order by 3 desc, 1;
$fn$;
