-- Attendance for any date range, for one person or several.
--
-- The records screen shows a single day and the cycle report is locked to the
-- 26th-to-25th window, so a question like "Jose, Devaraj and Saurabh from
-- 01/05 to 07/07" could not be answered at all — it had to be assembled by
-- opening each person and each cycle separately.
--
-- p_employee_ids NULL means everyone, so the same function serves a
-- company-wide range report without a second one to keep in step.
create or replace function public.attendance_range_report(
  p_from date,
  p_to   date,
  p_employee_ids text[] default null
)
returns table(
  employee_id text, employee_name text, department text,
  date_iso date, day_name text,
  check_in_time text, check_out_time text,
  hours_worked numeric, status text, verification text, note text
)
language sql stable as $fn$
  with emp as (
    select u.employee_id, u.name, coalesce(u.department,'') as department,
           coalesce(o.check_in_time,'09:30') as start_time
      from app_users u
      left join department_office_timings dt on dt.department = u.department
      left join office_timings o on o.id = dt.office_timing_id
     where u.active
       and not coalesce(u.oversight_only,false)
       and not coalesce(u.exempt_from_attendance,false)
       and (p_employee_ids is null or array_length(p_employee_ids,1) is null
            or u.employee_id = any(p_employee_ids))
  ),
  days as (
    select e.employee_id, e.name, e.department, e.start_time, d::date as day
      from emp e, generate_series(p_from, p_to, interval '1 day') d
  )
  select d.employee_id, d.name, d.department, d.day,
         to_char(d.day, 'Dy'),
         coalesce(a.check_in_time, ''),
         coalesce(a.check_out_time, ''),
         -- Only where both ends exist; a missing check-out would otherwise
         -- read as a negative or absurd figure.
         case when coalesce(a.check_in_time,'') <> ''
               and coalesce(a.check_out_time,'') <> ''
              then round((
                (substring(a.check_out_time from 1 for 2)::int * 60
                 + substring(a.check_out_time from 4 for 2)::int)
              - (substring(a.check_in_time  from 1 for 2)::int * 60
                 + substring(a.check_in_time  from 4 for 2)::int)
              )::numeric / 60, 2)
         end,
         case
           when coalesce(a.check_in_time,'') <> '' then
             case when coalesce(a.on_duty,false) then 'On Duty'
                  when (substring(a.check_in_time from 1 for 2)::int * 60
                        + substring(a.check_in_time from 4 for 2)::int)
                     > (substring(d.start_time from 1 for 2)::int * 60
                        + substring(d.start_time from 4 for 2)::int)
                  then 'Late' else 'Present' end
           when l.id is not null then coalesce(l.leave_type, 'Leave')
           when public.is_non_working_day(d.name, d.day) then 'Week Off / Holiday'
           else 'Absent'
         end,
         coalesce(a.verification, ''),
         coalesce(a.check_in_note, '')
    from days d
    left join attendance_records a
           on a.employee_id = d.employee_id and a.date_iso = d.day
    -- Approved leave only: a pending request is not yet a reason to be away.
    left join leave_applications l
           on l.employee_id = d.employee_id
          and d.day between l.from_date and l.to_date
          and l.leave_type <> 'Permission'
          and case when l.management_status <> 'pending'
                   then l.management_status else l.manager_status end = 'approved'
   order by d.name, d.day;
$fn$;
