-- The July attendance sheet has a REMARKS column per employee per cycle —
-- entries like "CL-1 Leave Balance Adjusted" or "Leave without information".
-- Nothing in the system held that: it is a manual note about how a particular
-- cycle was settled, not derivable from attendance or leave rows.
--
-- Keyed on the CYCLE rather than the calendar month, since that is the period
-- the sheet covers.
create table if not exists attendance_cycle_remarks (
  id            uuid primary key default gen_random_uuid(),
  employee_id   text not null,
  cycle_label   text not null,          -- 'YYYY-MM' of the month the cycle ENDS in
  remarks       text not null default '',
  updated_by    text default '',
  updated_at    timestamptz not null default now(),
  unique (employee_id, cycle_label)
);

comment on table attendance_cycle_remarks is
  'Free-text note per employee per attendance cycle, matching the REMARKS column of the manual attendance sheet. Not derivable from attendance or leave data — someone types it.';

alter table attendance_cycle_remarks enable row level security;

-- HR and Management write these; everyone can see their own.
drop policy if exists attendance_cycle_remarks_all on attendance_cycle_remarks;
create policy attendance_cycle_remarks_all on attendance_cycle_remarks for all to authenticated
  using (employee_id = current_app_employee_id() or current_app_is_hr_or_mgmt())
  with check (current_app_is_hr_or_mgmt());

-- ── The report itself ───────────────────────────────────────────────────────
-- Every column of the manual sheet, computed for one attendance cycle.
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
    select u.* from app_users u, bounds b
     where u.active
       and not coalesce(u.oversight_only, false)
       and not coalesce(u.exempt_from_attendance, false)
  ),
  -- Every date in the cycle, per employee, so weekly offs and holidays can be
  -- excluded from the working-day count rather than assumed.
  days as (
    select e.employee_id, d::date as day
      from emp e, bounds b,
           generate_series(b.s, b.e, interval '1 day') d
  ),
  working as (
    select d.employee_id,
           count(*) filter (
             where not public.is_non_working_day(
               (select name from app_users a where a.employee_id = d.employee_id), d.day)
           )::int as total_working_days
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
    -- Excused lateness is excluded: it was written off deliberately.
    select a.employee_id, count(*)::int as late_count
      from attendance_records a, bounds b
     where a.date_iso between b.s and b.e
       and coalesce(a.check_in_time,'') <> ''
       and not coalesce(a.late_waived, false)
       and a.check_in_time > coalesce((
             select o.check_in_time from app_users u
               left join department_office_timings dt on dt.department = u.department
               left join office_timings o on o.id = dt.office_timing_id
              where u.employee_id = a.employee_id), '09:30')
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
         -- Pay days: the cycle length minus loss of pay. Weekly offs and
         -- holidays are PAID, so they are not deducted.
         ((select (e2.e - e2.s) + 1 from bounds e2) - coalesce(lv.lop_days,0))::numeric,
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
