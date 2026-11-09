-- Two bugs in my first version of attendance_cycle_report:
--
--  1. The late count ignored exempt_from_timing, so Ronak — who has no fixed
--     hours at all — was counted late 3 times. It also ignored grace_minutes,
--     so an arrival inside the grace window counted as late.
--
--  2. pay_days returned the full cycle length (31) for everyone, including
--     someone who joined mid-cycle. Prarthana joined 09/08 and would have been
--     paid for 31 days.

create or replace function public.attendance_cycle_report(p_cycle_end date)
returns table (
  employee_name      text,
  employee_code      text,
  department         text,
  designation        text,
  date_of_joining    text,
  total_working_days int,
  days_worked        int,
  leave_taken        numeric,
  lop_days           int,
  late_count         int,
  permission_count   int,
  pay_days           numeric,
  remarks            text
)
language sql
stable
as $function$
  with bounds as (
    select public.attendance_cycle_start(p_cycle_end) as s,
           public.attendance_cycle_end(p_cycle_end)   as e,
           public.attendance_cycle_label(p_cycle_end) as lbl
  ),
  emp as (
    select u.*,
           -- The employee's start time and grace, or the 09:30 default when
           -- their department has no timing configured.
           coalesce(o.check_in_time, '09:30')  as start_time,
           coalesce(o.grace_minutes, 10)       as grace,
           -- Someone who joined mid-cycle is only payable from their joining
           -- date, not the whole period.
           greatest(b.s, coalesce(nullif(u.date_of_joining,'')::date, b.s)) as pay_from
      from app_users u
      cross join bounds b
      left join department_office_timings dt on dt.department = u.department
      left join office_timings o on o.id = dt.office_timing_id
     where u.active
       and not coalesce(u.oversight_only, false)
       and not coalesce(u.exempt_from_attendance, false)
  ),
  days as (
    select e.employee_id, e.name, d::date as day
      from emp e, bounds b,
           generate_series(b.s, b.e, interval '1 day') d
  ),
  working as (
    select d.employee_id,
           count(*) filter (where not public.is_non_working_day(d.name, d.day))::int
             as total_working_days
      from days d group by d.employee_id
  ),
  worked as (
    select a.employee_id, count(*)::int as days_worked
      from attendance_records a, bounds b
     where a.date_iso between b.s and b.e
       and coalesce(a.check_in_time,'') <> ''
     group by a.employee_id
  ),
  lates as (
    select a.employee_id, count(*)::int as late_count
      from attendance_records a
      join emp e on e.employee_id = a.employee_id
      cross join bounds b
     where a.date_iso between b.s and b.e
       and coalesce(a.check_in_time,'') <> ''
       and not coalesce(a.late_waived, false)
       -- No fixed hours means never late. This was missing, so an exempt
       -- employee was measured against the 09:30 default.
       and not coalesce(e.exempt_from_timing, false)
       -- Grace window honoured, as it is everywhere else in the app.
       and (substring(a.check_in_time from 1 for 2)::int * 60
            + substring(a.check_in_time from 4 for 2)::int)
           > (substring(e.start_time from 1 for 2)::int * 60
              + substring(e.start_time from 4 for 2)::int + e.grace)
     group by a.employee_id
  ),
  lv as (
    select l.employee_id,
           sum(l.days) filter (where l.leave_type <> 'Permission')::numeric as leave_taken,
           sum(l.lop_days) filter (where l.leave_type <> 'Permission')::int as lop_days,
           count(*) filter (where l.leave_type = 'Permission')::int         as permission_count
      from leave_applications l, bounds b
     where l.manager_status = 'approved'
       and l.from_date <= b.e and l.to_date >= b.s
     group by l.employee_id
  )
  select e.name,
         e.employee_id,
         coalesce(e.department,''),
         coalesce(e.designation,''),
         coalesce(e.date_of_joining,''),
         coalesce(w.total_working_days, 0),
         coalesce(wk.days_worked, 0),
         coalesce(lv.leave_taken, 0),
         coalesce(lv.lop_days, 0),
         coalesce(lt.late_count, 0),
         coalesce(lv.permission_count, 0),
         -- Payable days from the joining date to the cycle end, less LOP.
         -- Weekly offs and holidays are paid, so they are not deducted.
         (((select e2.e from bounds e2) - e.pay_from) + 1 - coalesce(lv.lop_days,0))::numeric,
         coalesce(r.remarks, '')
    from emp e
    left join working w  on w.employee_id  = e.employee_id
    left join worked wk  on wk.employee_id = e.employee_id
    left join lates lt   on lt.employee_id = e.employee_id
    left join lv         on lv.employee_id = e.employee_id
    left join attendance_cycle_remarks r
           on r.employee_id = e.employee_id
          and r.cycle_label = (select lbl from bounds)
   order by e.name;
$function$;

grant execute on function public.attendance_cycle_report(date) to authenticated, service_role;
