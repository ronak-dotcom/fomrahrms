-- Permission was counted, not measured: the form offered "30 Minutes",
-- "1 Hour", "2 Hours" as a label and stored no times at all, so nobody could
-- say when someone was away, and the 120-minute monthly allowance was tracked
-- by counting requests rather than adding up minutes.
alter table leave_applications add column if not exists permission_start_time text default '';
alter table leave_applications add column if not exists permission_end_time   text default '';
alter table leave_applications add column if not exists permission_minutes    integer default 0;
-- Set when a request pushes the employee past the monthly allowance. Recorded
-- on the request rather than derived later so the reason for the deduction
-- stays attached to the thing that caused it.
alter table leave_applications add column if not exists permission_lop_half_day boolean not null default false;

comment on column leave_applications.permission_minutes is
  'Minutes between start and end. The monthly allowance is spent in minutes, not in number of requests.';

-- Minutes already approved this attendance cycle.
create or replace function public.permission_minutes_used(
  p_employee_id text, p_date date default current_date
) returns integer language sql stable as $fn$
  select coalesce(sum(
           case when coalesce(l.permission_minutes,0) > 0
                then l.permission_minutes
                -- Older rows carry only a label, so fall back to reading it.
                else case
                  when l.reason ilike '%2 hour%'  then 120
                  when l.reason ilike '%1 hour%'  then 60
                  when l.reason ilike '%30 min%'  then 30
                  else 0 end
           end), 0)::int
    from leave_applications l
   where l.employee_id = p_employee_id
     and l.leave_type = 'Permission'
     and case when l.management_status <> 'pending'
              then l.management_status else l.manager_status end = 'approved'
     and l.from_date >= public.attendance_cycle_start(p_date)
     and l.from_date <= public.attendance_cycle_end(p_date);
$fn$;

-- What the employee has left, and what a request of p_minutes would do.
create or replace function public.permission_balance(
  p_employee_id text, p_date date default current_date, p_minutes integer default 0
)
returns table(quota integer, used integer, remaining integer,
              would_exceed boolean, lop_half_day boolean)
language sql stable as $fn$
  with q as (
    select coalesce(u.permission_minutes_quota, 120) as quota,
           public.permission_minutes_used(p_employee_id, p_date) as used
      from app_users u where u.employee_id = p_employee_id
  )
  select q.quota, q.used, greatest(0, q.quota - q.used),
         (q.used + p_minutes) > q.quota,
         -- Exceeding costs half a day's pay. Applied to the day it happened;
         -- the cycle report also flags it so it is not a surprise at payroll.
         (q.used + p_minutes) > q.quota
    from q;
$fn$;
