-- attendance_cycle_report feeds generate_payroll, and it was the one place
-- still counting leave by `manager_status = 'approved'` alone. leave_balance
-- and attendance_range_report already resolved Management's decision
-- properly; this one did not, so a leave Management approved but the
-- reporting manager never touched came through as unworked days and was
-- docked from pay.
--
-- Body is unchanged apart from the leave join, which now uses the `granted`
-- column.
CREATE OR REPLACE FUNCTION public.attendance_cycle_report(p_cycle_end date, p_employee_ids text[] DEFAULT NULL::text[])
 RETURNS TABLE(employee_name text, employee_code text, department text, designation text, date_of_joining text, total_working_days integer, days_worked integer, leave_taken numeric, lop_days integer, late_count integer, grace_late_count integer, permission_count integer, vouched_days integer, pay_days numeric, remarks text)
 LANGUAGE sql
 STABLE
AS $function$
  with bounds as (
    select public.attendance_cycle_start(p_cycle_end) as s,
           public.attendance_cycle_end(p_cycle_end)   as e,
           public.attendance_cycle_label(p_cycle_end) as lbl
  ),
  emp as (
    select u.*, coalesce(o.check_in_time,'09:30') as start_time,
           coalesce(o.grace_minutes,10) as grace,
           greatest(b.s, coalesce(nullif(u.date_of_joining,'')::date, b.s)) as pay_from
      from app_users u cross join bounds b
      left join department_office_timings dt on dt.department = u.department
      left join office_timings o on o.id = dt.office_timing_id
     where u.active and not coalesce(u.oversight_only,false)
       and not coalesce(u.exempt_from_attendance,false)
       and (p_employee_ids is null or array_length(p_employee_ids,1) is null
            or u.employee_id = any(p_employee_ids))
  ),
  days as (
    select e.employee_id, e.name, d::date as day
      from emp e, bounds b, generate_series(b.s, b.e, interval '1 day') d
  ),
  working as (
    select d.employee_id,
           count(*) filter (where not public.is_non_working_day(d.name, d.day))::int as total_working_days
      from days d group by d.employee_id
  ),
  worked as (
    select a.employee_id, count(*)::int as days_worked,
           count(*) filter (where a.verification = 'vouched')::int as vouched_days
      from attendance_records a, bounds b
     where a.date_iso between b.s and b.e and coalesce(a.check_in_time,'') <> ''
     group by a.employee_id
  ),
  -- Each late day classified, then grace days numbered in date order so only
  -- the first three keep the concession.
  marked as (
    select a.employee_id, a.date_iso,
           (substring(a.check_in_time from 1 for 2)::int*60
            + substring(a.check_in_time from 4 for 2)::int) as in_min,
           (substring(e.start_time from 1 for 2)::int*60
            + substring(e.start_time from 4 for 2)::int) as start_min,
           e.grace
      from attendance_records a
      join emp e on e.employee_id = a.employee_id
      cross join bounds b
     where a.date_iso between b.s and b.e and coalesce(a.check_in_time,'') <> ''
       and not coalesce(a.late_waived,false) and not coalesce(e.exempt_from_timing,false)
       and coalesce(a.on_duty,false) = false
  ),
  classified as (
    select employee_id, date_iso,
           in_min > start_min + grace as hard_late,
           in_min > start_min and in_min <= start_min + grace as in_grace
      from marked
  ),
  numbered as (
    select employee_id, hard_late, in_grace,
           case when in_grace
                then row_number() over (partition by employee_id, in_grace order by date_iso)
                else null end as grace_seq
      from classified
  )
  select e.name, e.employee_id, coalesce(e.department,''), coalesce(e.designation,''),
         coalesce(e.date_of_joining,''),
         coalesce(w.total_working_days,0), coalesce(wk.days_worked,0),
         coalesce(lv.leave_taken,0), coalesce(lv.lop_days,0),
         -- Hard lates, plus any grace day beyond the third.
         coalesce((select count(*) from numbered n
                    where n.employee_id = e.employee_id
                      and (n.hard_late or (n.in_grace and n.grace_seq > 3)))::int, 0),
         -- Only the grace days still covered by the concession.
         coalesce((select count(*) from numbered n
                    where n.employee_id = e.employee_id
                      and n.in_grace and n.grace_seq <= 3)::int, 0),
         coalesce(lv.permission_count,0), coalesce(wk.vouched_days,0),
         (((select e2.e from bounds e2) - e.pay_from) + 1 - coalesce(lv.lop_days,0))::numeric,
         coalesce(r.remarks,'')
    from emp e
    left join working w on w.employee_id = e.employee_id
    left join worked wk on wk.employee_id = e.employee_id
    left join (
      select l.employee_id,
             sum(l.days) filter (where l.leave_type <> 'Permission')::numeric as leave_taken,
             sum(l.lop_days) filter (where l.leave_type <> 'Permission')::int as lop_days,
             count(*) filter (where l.leave_type = 'Permission')::int as permission_count
        from leave_applications l, bounds b
       where l.granted and l.from_date <= b.e and l.to_date >= b.s
       group by l.employee_id
    ) lv on lv.employee_id = e.employee_id
    left join attendance_cycle_remarks r
           on r.employee_id = e.employee_id and r.cycle_label = (select lbl from bounds)
   order by e.name;
$function$;
