-- G2: store the accuracy radius that comes with every fix.
--
-- The device reports "this point, give or take X metres". X was discarded, so
-- a +/-2000 m cell-tower estimate was stored identically to a +/-5 m satellite
-- fix, and both were measured against a 150 m geofence. A "within radius"
-- verdict from a 2 km estimate is meaningless, and a poor fix can equally
-- place someone OUTSIDE a site they are standing in.
alter table attendance_records
  add column if not exists check_in_accuracy  numeric(8,1),
  add column if not exists check_out_accuracy numeric(8,1);

comment on column attendance_records.check_in_accuracy is
  'Radius in metres the device reported for this fix. Larger means less certain. Null on records taken before this was captured.';

-- A verdict is only as good as the fix behind it.
create or replace function public.gps_confidence(p_accuracy numeric, p_radius numeric default 150)
returns text
language sql
immutable
as $function$
  select case
    when p_accuracy is null then 'unknown'
    when p_accuracy <= 30 then 'high'
    when p_accuracy <= p_radius / 2 then 'usable'
    when p_accuracy <= p_radius then 'weak'
    else 'unreliable'
  end;
$function$;

comment on function public.gps_confidence is
  'How much weight the within-radius verdict deserves. "unreliable" means the accuracy radius exceeds the geofence itself, so the verdict is a coin flip.';

-- G4: location history, for Management.
--
-- Route points were captured in gps_points and never shown anywhere. This
-- exposes check-in/out positions with their confidence, so Management can see
-- where people were AND how much to trust it.
create or replace view public.v_location_history as
  select a.employee_id,
         a.employee_name,
         a.date,
         a.date_iso,
         a.check_in_time,
         a.check_out_time,
         a.check_in_lat,
         a.check_in_lng,
         a.check_in_within_radius,
         a.check_in_accuracy,
         public.gps_confidence(a.check_in_accuracy) as check_in_confidence,
         a.check_out_lat,
         a.check_out_lng,
         a.check_out_within_radius,
         a.check_out_accuracy,
         a.location_policy_name,
         nullif(a.check_in_note,'')      as check_in_note,
         nullif(a.check_in_gps_error,'') as check_in_gps_error,
         -- Distance to the nearest site this employee is assigned to, so a
         -- verdict can be sanity-checked rather than taken on trust.
         (select round(min(6371000*2*asin(sqrt(
             power(sin(radians(l.latitude - a.check_in_lat)/2),2) +
             cos(radians(a.check_in_lat))*cos(radians(l.latitude))*
             power(sin(radians(l.longitude - a.check_in_lng)/2),2))))::numeric, 0)
            from employee_locations el join locations l on l.id = el.location_id
           where el.employee_id = a.employee_id) as metres_to_nearest_site
    from attendance_records a
   where a.check_in_lat is not null or a.check_in_gps_error <> '';

comment on view public.v_location_history is
  'Location history for Management: where each check-in happened, how accurate the fix was, and how far from the nearest assigned site.';

-- Management and HR only. Location data is personal data; an employee has no
-- reason to browse anyone else's movements.
alter view public.v_location_history set (security_invoker = on);
