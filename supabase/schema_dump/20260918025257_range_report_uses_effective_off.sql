-- The report now asks which day was actually taken off, not which day the
-- record says. A swap produced two wrong rows: the assigned day read
-- "Week Off" though the person worked, and the day they really took read
-- "Absent". The swap is labelled rather than hidden, so HR can see it
-- happened and challenge it if it looks wrong.
create or replace function public.attendance_range_report(
  p_from date, p_to date, p_employee_ids text[] default null
)
returns table(
  employee_id text, employee_name text, department text,
  date_iso date, day_name text, check_in_time text, check_out_time text,
  hours_worked numeric, status text, verification text, note text
)
language sql stable as $fn$
  with emp as (
    select u.employee_id, u.name, coalesce(u.department,'') as department,
           coalesce(o.check_in_time,'09:30') as start_time,
           coalesce(u.weekly_off_day,'') as assigned_off
      from app_users u
      left join department_office_timings dt on dt.department = u.department
      left join office_timings o on o.id = dt.office_timing_id
     where u.active and not coalesce(u.oversight_only,false)
       and not coalesce(u.exempt_from_attendance,false)
       and (p_employee_ids is null or array_length(p_employee_ids,1) is null
            or u.employee_id = any(p_employee_ids))
  ),
  days as (
    select e.*, d::date as day,
           public.effective_weekly_off(e.employee_id, d::date) as off_taken
      from emp e, generate_series(p_from, p_to, interval '1 day') d
  )
  select d.employee_id, d.name, d.department, d.day, to_char(d.day, 'Dy'),
         coalesce(a.check_in_time, ''), coalesce(a.check_out_time, ''),
         case when coalesce(a.check_in_time,'') <> ''
               and coalesce(a.check_out_time,'') <> ''
              then round((
                (substring(a.check_out_time from 1 for 2)::int * 60
                 + substring(a.check_out_time from 4 for 2)::int)
              - (substring(a.check_in_time from 1 for 2)::int * 60
                 + substring(a.check_in_time from 4 for 2)::int)
              )::numeric / 60, 2) end,
         case
           when coalesce(a.check_in_time,'') <> '' then
             case when coalesce(a.on_duty,false) then 'On Duty'
                  when (substring(a.check_in_time from 1 for 2)::int * 60
                        + substring(a.check_in_time from 4 for 2)::int)
                     > (substring(d.start_time from 1 for 2)::int * 60
                        + substring(d.start_time from 4 for 2)::int)
                  then 'Late' else 'Present' end
           when l.id is not null then coalesce(l.leave_type, 'Leave')
           -- The day actually taken off this week.
           when d.off_taken = d.day then
             case when lower(to_char(d.day,'Day')) like lower(d.assigned_off)||'%'
                  then 'Week Off'
                  else 'Week Off (swapped from ' || trim(d.assigned_off) || ')'
             end
           when exists (select 1 from holidays h where h.holiday_date = d.day)
             then 'Holiday'
           else 'Absent'
         end,
         coalesce(a.verification, ''), coalesce(a.check_in_note, '')
    from days d
    left join attendance_records a
           on a.employee_id = d.employee_id and a.date_iso = d.day
    left join leave_applications l
           on l.employee_id = d.employee_id
          and d.day between l.from_date and l.to_date
          and l.leave_type <> 'Permission'
          and case when l.management_status <> 'pending'
                   then l.management_status else l.manager_status end = 'approved'
   order by d.name, d.day;
$fn$;

select date_iso::text, day_name, check_in_time, status
  from attendance_range_report(date '2026-09-14', date '2026-09-17', ARRAY['FHIPL-03'])
 order by date_iso;
