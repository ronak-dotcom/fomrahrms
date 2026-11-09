-- Management works to no fixed hours: check in and out at any time, with no
-- late-reason prompt.
--
-- The client now derives this from the ROLE as well as the flag, because the
-- flag travels login -> UserSession -> local storage and a session created
-- before the flag existed carries a stale false. Role has always been in the
-- session, so keying on it makes the exemption immediate.
--
-- Keeping the data in step anyway, so anything reading the column directly
-- (reports, exports, a future service) agrees with the app rather than
-- depending on the same derivation being repeated correctly elsewhere.
alter table app_users disable trigger trg_protect_app_users;

update app_users
   set exempt_from_timing   = true,
       exempt_from_geofence = true
 where public.is_management_authority(role)
   and not (exempt_from_timing and exempt_from_geofence);

alter table app_users enable trigger trg_protect_app_users;

-- Any new Management user gets it without someone remembering.
create or replace function public.default_management_exemptions()
returns trigger
language plpgsql
as $function$
begin
  if public.is_management_authority(new.role) then
    new.exempt_from_timing   := true;
    new.exempt_from_geofence := true;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_default_management_exemptions on app_users;
create trigger trg_default_management_exemptions
  before insert or update of role on app_users
  for each row execute function public.default_management_exemptions();

-- And keep the geofence policy override in step, since an exempt user with no
-- assigned location is otherwise read as "outside everywhere".
insert into attendance_policy_employee_overrides (employee_id, policy_id)
select u.employee_id, p.id from app_users u
  cross join attendance_policies p
 where p.name = 'Unrestricted Check-in' and u.exempt_from_geofence
on conflict (employee_id) do update set policy_id = excluded.policy_id;
