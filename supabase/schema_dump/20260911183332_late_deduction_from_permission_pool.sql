-- Late handling, consuming the same 120-minute pool as permission requests.
--
-- Rule: the first 3 lates in a cycle cost nothing. From the 4th, the lateness
-- is charged to the permission pool rounded UP to a 30-minute block — up to
-- 30 min costs 30, 30-60 costs 60, 60-90 costs 90, 90-120 costs 120. Beyond
-- 120 minutes late is half a day regardless. Once the pool is empty every
-- further late is half a day.
--
-- Processed in DATE ORDER with permission requests, because the two draw on
-- one pool: whichever came first should get it. Charging all permissions
-- first would make a late on the 2nd cost half a day because of a permission
-- taken on the 20th.
--
-- Lateness is measured from scheduled start, not from the end of the grace
-- window — grace already forgives the first three occasions separately.
create or replace function public.late_deduction_detail(
  p_employee_id text, p_date date default current_date
)
returns table(
  event_date date, kind text, minutes_late integer, charged_minutes integer,
  pool_left integer, half_day_lop boolean
)
language plpgsql stable as $fn$
declare
  v_quota int;
  v_pool  int;
  v_late_seq int := 0;
  r record;
  v_block int;
  v_half boolean;
begin
  select coalesce(permission_minutes_quota, 120) into v_quota
    from app_users where employee_id = p_employee_id;
  v_pool := coalesce(v_quota, 120);

  for r in
    -- Permissions and lates on one timeline.
    select d, 'permission'::text as kind, mins, 0 as late_mins from (
      select l.from_date as d,
             case when coalesce(l.permission_minutes,0) > 0 then l.permission_minutes
                  when l.reason ilike '%2 hour%' then 120
                  when l.reason ilike '%1 hour%' then 60
                  when l.reason ilike '%30 min%' then 30
                  else 0 end as mins
        from leave_applications l
       where l.employee_id = p_employee_id and l.leave_type = 'Permission'
         and case when l.management_status <> 'pending'
                  then l.management_status else l.manager_status end = 'approved'
         and l.from_date between public.attendance_cycle_start(p_date)
                             and public.attendance_cycle_end(p_date)
    ) p
    union all
    select a.date_iso, 'late', 0,
           ((substring(a.check_in_time from 1 for 2)::int * 60
             + substring(a.check_in_time from 4 for 2)::int)
          - (substring(coalesce(o.check_in_time,'09:30') from 1 for 2)::int * 60
             + substring(coalesce(o.check_in_time,'09:30') from 4 for 2)::int))
      from attendance_records a
      join app_users u on u.employee_id = a.employee_id
      left join department_office_timings dt on dt.department = u.department
      left join office_timings o on o.id = dt.office_timing_id
     where a.employee_id = p_employee_id
       and a.date_iso between public.attendance_cycle_start(p_date)
                          and public.attendance_cycle_end(p_date)
       and coalesce(a.check_in_time,'') <> ''
       and not coalesce(a.late_waived, false)
       and coalesce(a.on_duty, false) = false
       and ((substring(a.check_in_time from 1 for 2)::int * 60
             + substring(a.check_in_time from 4 for 2)::int)
          - (substring(coalesce(o.check_in_time,'09:30') from 1 for 2)::int * 60
             + substring(coalesce(o.check_in_time,'09:30') from 4 for 2)::int))
           > coalesce(o.grace_minutes, 10)
    order by 1, 2
  loop
    v_half := false;
    v_block := 0;

    if r.kind = 'permission' then
      v_block := least(r.mins, greatest(v_pool, 0));
      -- A permission beyond the pool is handled by permission_lop_days, so it
      -- is not charged a second time here.
      v_pool := v_pool - r.mins;
    else
      v_late_seq := v_late_seq + 1;
      if v_late_seq > 3 then
        if r.late_mins > 120 then
          v_half := true;                       -- too late to buy back
        else
          v_block := ceil(r.late_mins / 30.0)::int * 30;
          if v_block <= greatest(v_pool, 0) then
            v_pool := v_pool - v_block;         -- paid for from the pool
          else
            v_half := true;                     -- pool exhausted
            v_block := 0;
          end if;
        end if;
      end if;
    end if;

    event_date := r.d;
    kind := r.kind;
    minutes_late := r.late_mins;
    charged_minutes := v_block;
    pool_left := greatest(v_pool, 0);
    half_day_lop := v_half;
    return next;
  end loop;
end;
$fn$;

-- Half-days a cycle's lates cost, for payroll.
create or replace function public.late_lop_days(
  p_employee_id text, p_date date default current_date
) returns numeric language sql stable as $fn$
  select coalesce(count(*) * 0.5, 0)::numeric
    from public.late_deduction_detail(p_employee_id, p_date)
   where half_day_lop;
$fn$;
