-- Lets the cycle attendance report be scoped to a chosen set of employees
-- instead of always the whole company, and adds a grace-late count
-- alongside the existing (severe) late count so a punctuality picture
-- during payroll isn't just "how many days incurred a deduction" but also
-- "how many days were late at all".
create or replace function public.attendance_cycle_report(
  p_cycle_end date,
  p_employee_ids text[] default null
)
returns table(
  employee_name text, employee_code text, department text, designation text,
  date_of_joining text, total_working_days integer, days_worked integer,
  leave_taken numeric, lop_days integer, late_count integer,
  grace_late_count integer, permission_count integer, pay_days numeric,
  remarks text
)
language sql stable as $function$
  with bounds as (
    select public.attendance_cycle_start(p_cycle_end) as s,
           public.attendance_cycle_end(p_cycle_end)   as e,
           public.attendance_cycle_label(p_cycle_end) as lbl
  ),
  emp as (
    select u.*,
           coalesce(o.check_in_time, '09:30')  as start_time,
           coalesce(o.grace_minutes, 10)       as grace,
           greatest(b.s, coalesce(nullif(u.date_of_joining,'')::date, b.s)) as pay_from
      from app_users u
      cross join bounds b
      left join department_office_timings dt on dt.department = u.department
      left join office_timings o on o.id = dt.office_timing_id
     where u.active
       and not coalesce(u.oversight_only, false)
       and not coalesce(u.exempt_from_attendance, false)
       and (p_employee_ids is null or array_length(p_employee_ids, 1) is null
            or u.employee_id = any(p_employee_ids))
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
    select a.employee_id,
           count(*) filter (
             where (substring(a.check_in_time from 1 for 2)::int * 60
                    + substring(a.check_in_time from 4 for 2)::int)
                 > (substring(e.start_time from 1 for 2)::int * 60
                    + substring(e.start_time from 4 for 2)::int + e.grace)
           )::int as late_count,
           count(*) filter (
             where (substring(a.check_in_time from 1 for 2)::int * 60
                    + substring(a.check_in_time from 4 for 2)::int)
                 > (substring(e.start_time from 1 for 2)::int * 60
                    + substring(e.start_time from 4 for 2)::int)
               and (substring(a.check_in_time from 1 for 2)::int * 60
                    + substring(a.check_in_time from 4 for 2)::int)
                <= (substring(e.start_time from 1 for 2)::int * 60
                    + substring(e.start_time from 4 for 2)::int + e.grace)
           )::int as grace_late_count
      from attendance_records a
      join emp e on e.employee_id = a.employee_id
      cross join bounds b
     where a.date_iso between b.s and b.e
       and coalesce(a.check_in_time,'') <> ''
       and not coalesce(a.late_waived, false)
       and not coalesce(e.exempt_from_timing, false)
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
         coalesce(lt.grace_late_count, 0),
         coalesce(lv.permission_count, 0),
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

-- Day-level punctuality detail for a chosen set of employees over one pay
-- cycle — every late check-in with the date, time, how many minutes late,
-- and whether it fell inside the grace window or past it. This is the
-- actual "how was each employee" detail a punctuality review during payroll
-- needs; attendance_cycle_report() above only gives per-employee totals.
create or replace function public.attendance_punctuality_detail(
  p_cycle_end date,
  p_employee_ids text[]
)
returns table(
  employee_name text, employee_code text, date text, check_in_time text,
  scheduled_start text, minutes_late integer, severity text
)
language sql stable as $function$
  with bounds as (
    select public.attendance_cycle_start(p_cycle_end) as s,
           public.attendance_cycle_end(p_cycle_end)   as e
  ),
  emp as (
    select u.employee_id, u.name,
           coalesce(o.check_in_time, '09:30')  as start_time,
           coalesce(o.grace_minutes, 10)       as grace,
           coalesce(u.exempt_from_timing, false) as exempt_from_timing
      from app_users u
      left join department_office_timings dt on dt.department = u.department
      left join office_timings o on o.id = dt.office_timing_id
     where u.employee_id = any(p_employee_ids)
  )
  select e.name, e.employee_id, to_char(a.date_iso, 'DD/MM/YYYY'), a.check_in_time,
         e.start_time,
         ((substring(a.check_in_time from 1 for 2)::int * 60
           + substring(a.check_in_time from 4 for 2)::int)
          - (substring(e.start_time from 1 for 2)::int * 60
             + substring(e.start_time from 4 for 2)::int))::int as minutes_late,
         case when (substring(a.check_in_time from 1 for 2)::int * 60
                    + substring(a.check_in_time from 4 for 2)::int)
                 > (substring(e.start_time from 1 for 2)::int * 60
                    + substring(e.start_time from 4 for 2)::int + e.grace)
              then 'severe' else 'grace' end
    from attendance_records a
    join emp e on e.employee_id = a.employee_id
    cross join bounds b
   where a.date_iso between b.s and b.e
     and coalesce(a.check_in_time,'') <> ''
     and not coalesce(a.late_waived, false)
     and not e.exempt_from_timing
     and (substring(a.check_in_time from 1 for 2)::int * 60
          + substring(a.check_in_time from 4 for 2)::int)
       > (substring(e.start_time from 1 for 2)::int * 60
          + substring(e.start_time from 4 for 2)::int)
   order by e.name, a.date_iso;
$function$;
