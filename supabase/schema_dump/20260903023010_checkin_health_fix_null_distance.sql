-- The distance subquery ran even when there was no GPS fix, and acos() of a
-- null-driven expression collapsed to 20015087 m — half the Earth's
-- circumference — displayed next to every employee who simply had not
-- checked in yet. A number that looks like data but means "no data" is
-- worse than a blank, so it is now null.
create or replace function public.checkin_health(p_days integer default 3)
returns table(
  day date, employee_name text, employee_code text,
  checked_in text, checked_out text, within_radius text,
  nearest_m integer, accuracy_m integer,
  failed_attempts bigint, last_failure text, verdict text
)
language sql stable as $fn$
  with tracked as (
    select u.employee_id, u.name from app_users u
     where u.active and not coalesce(u.exempt_from_attendance,false)
       and not coalesce(u.oversight_only,false)
  ),
  days as (
    select generate_series(current_date - (p_days - 1), current_date, interval '1 day')::date as d
  ),
  grid as (select d.d, t.employee_id, t.name from days d cross join tracked t),
  fails as (
    select employee_id, attempted_at::date as d, count(*) n,
           max(outcome || case when reason <> '' then ': ' || reason else '' end) as last_reason
      from checkin_attempts
     where outcome <> 'success' and attempted_at >= current_date - p_days
     group by 1,2
  )
  select g.d, g.name, g.employee_id,
         coalesce(nullif(a.check_in_time,''),  '—'),
         coalesce(nullif(a.check_out_time,''), '—'),
         case when a.check_in_lat is null then '—'
              when a.check_in_within_radius then 'inside'
              else 'OUTSIDE' end,
         case when a.check_in_lat is null then null else round(
           (select min(6371000 * acos(least(1, greatest(-1,
              cos(radians(l.latitude))*cos(radians(a.check_in_lat))*
              cos(radians(a.check_in_lng)-radians(l.longitude)) +
              sin(radians(l.latitude))*sin(radians(a.check_in_lat))))))
              from locations l where l.active))::int end,
         round(a.check_in_accuracy)::int,
         coalesce(f.n, 0),
         coalesce(f.last_reason, ''),
         case
           when a.check_in_time is null and public.is_non_working_day(g.name, g.d) then 'non-working'
           when a.check_in_time is null and coalesce(f.n,0) > 0 then 'FAILED TO CHECK IN'
           when a.check_in_time is null then 'no check-in'
           when coalesce(a.check_out_time,'') = '' and g.d < current_date then 'missing check-out'
           when coalesce(f.n,0) > 0 then 'worked, but hit errors'
           else 'ok'
         end
    from grid g
    left join attendance_records a on a.employee_id = g.employee_id and a.date_iso = g.d
    left join fails f on f.employee_id = g.employee_id and f.d = g.d
   order by g.d desc, g.name;
$fn$;
