-- ── 1. Sales and CRM may check in from ANY configured site ──────────────────
-- These roles sit at different sites through the week — unlike Land
-- Acquisition, who are in the field with no fixed site and are simply exempt
-- from the geofence. Sales and CRM should still be geofenced, but against
-- every site rather than one.
--
-- employee_locations is already many-to-many (unique on the PAIR), and
-- evaluateGeofence() already passes when the position is within ANY assigned
-- location, so nothing structural changes — only what gets assigned.
--
-- HR can still remove a site from a person afterwards; nothing re-adds it.

create or replace function public.site_roaming_departments()
returns text[] language sql immutable as $function$
  select array['Sales', 'CRM']::text[];
$function$;

-- Backfill: every existing Sales/CRM employee gets every existing site.
insert into employee_locations (employee_id, location_id)
select u.employee_id, l.id
  from app_users u cross join locations l
 where u.department = any(public.site_roaming_departments())
   and coalesce(u.employee_id,'') <> ''
   and l.active
on conflict (employee_id, location_id) do nothing;

-- A NEW site becomes available to Sales/CRM automatically.
create or replace function public.grant_new_location_to_roamers()
returns trigger language plpgsql as $function$
begin
  insert into employee_locations (employee_id, location_id)
  select u.employee_id, new.id
    from app_users u
   where u.department = any(public.site_roaming_departments())
     and coalesce(u.employee_id,'') <> ''
  on conflict (employee_id, location_id) do nothing;
  return new;
end; $function$;

drop trigger if exists trg_grant_new_location_to_roamers on locations;
create trigger trg_grant_new_location_to_roamers
  after insert on locations
  for each row execute function public.grant_new_location_to_roamers();

-- A NEW Sales/CRM employee, or someone moved into those departments, gets
-- every site.
create or replace function public.grant_all_locations_to_roamer()
returns trigger language plpgsql as $function$
begin
  if new.department = any(public.site_roaming_departments())
     and coalesce(new.employee_id,'') <> ''
     and (tg_op = 'INSERT' or new.department is distinct from old.department) then
    insert into employee_locations (employee_id, location_id)
    select new.employee_id, l.id from locations l where l.active
    on conflict (employee_id, location_id) do nothing;
  end if;
  return new;
end; $function$;

drop trigger if exists trg_grant_all_locations_to_roamer on app_users;
create trigger trg_grant_all_locations_to_roamer
  after insert or update of department, employee_id on app_users
  for each row execute function public.grant_all_locations_to_roamer();

-- ── 2. Late waiver — Management only ────────────────────────────────────────
-- An employee must not be marked late because the app failed. Sijo reached
-- site at 09:16 and the browser refused the location permission, so he could
-- not complete check-in until 09:32 — past the 09:30 Sales start.
--
-- The recorded TIME is deliberately not altered: 09:32 is when the system
-- accepted it, and overwriting that would falsify the record. The waiver sits
-- alongside it, with a reason and who granted it.
alter table attendance_records
  add column if not exists late_waived        boolean not null default false,
  add column if not exists late_waiver_reason text default '',
  add column if not exists late_waived_by     text default '',
  add column if not exists late_waived_at     timestamptz;

comment on column attendance_records.late_waived is
  'Lateness excused — typically a system fault. Excluded from late counts and any pay consequence. Management only.';

create or replace function public.waive_late(p_record_id text, p_reason text)
returns boolean language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_management_authority(coalesce(current_app_role(), '')) then
    raise exception 'Only Management can waive a late arrival.'
      using errcode = 'insufficient_privilege';
  end if;
  if coalesce(btrim(p_reason),'') = '' then
    raise exception 'A reason is required to waive a late arrival.'
      using errcode = 'check_violation';
  end if;

  update attendance_records
     set late_waived = true,
         late_waiver_reason = btrim(p_reason),
         late_waived_by = coalesce(current_app_name(), ''),
         late_waived_at = now()
   where id = p_record_id;
  return found;
end; $function$;

create or replace function public.unwaive_late(p_record_id text)
returns boolean language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_management_authority(coalesce(current_app_role(), '')) then
    raise exception 'Only Management can change a late waiver.'
      using errcode = 'insufficient_privilege';
  end if;
  update attendance_records
     set late_waived = false, late_waiver_reason = '',
         late_waived_by = '', late_waived_at = null
   where id = p_record_id;
  return found;
end; $function$;

revoke all on function public.waive_late(text, text)   from public, anon;
revoke all on function public.unwaive_late(text)       from public, anon;
grant execute on function public.waive_late(text, text) to authenticated, service_role;
grant execute on function public.unwaive_late(text)     to authenticated, service_role;
