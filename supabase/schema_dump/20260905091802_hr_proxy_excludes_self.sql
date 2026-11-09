-- HR standing in for an oversight-only manager must not extend to their own
-- requests. The HR role holder himself reports to that manager, so without
-- this exclusion he would approve his own leave — and a pending permission of
-- his is in the queue right now. Enforced here as well as in the client so
-- the rule does not depend on which screen the update comes from.
create or replace function public.app_manages(p_name text)
returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from app_users me
      join app_users teammate on teammate.reporting_manager = me.name
     where lower(me.email) = current_app_email()
       and me.is_reporting_manager
       and teammate.name = p_name
  )
  or exists (
    select 1
      from app_users me
      join app_users teammate on teammate.name = p_name
      join app_users mgr on lower(trim(mgr.name)) = lower(trim(teammate.reporting_manager))
     where lower(me.email) = current_app_email()
       and me.role = 'HR'
       and coalesce(mgr.oversight_only, false)
       -- Not their own.
       and lower(trim(teammate.name)) <> lower(trim(me.name))
  );
$fn$;
