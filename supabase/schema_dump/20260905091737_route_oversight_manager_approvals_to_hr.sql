-- Seven people report to an oversight-only account. Their approvals sat with
-- someone who does not operate the system day to day: one casual leave had
-- been pending since 08/08, nearly a month.
--
-- Those requests now surface to HR, who actions them after asking the manager
-- directly. The reporting line itself is unchanged — the employee still
-- reports to them, and the record still says so — only who sees the approval
-- queue changes.
create or replace function public.app_manages(p_name text)
returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (
    -- Normal case: the caller is the named reporting manager.
    select 1 from app_users me
      join app_users teammate on teammate.reporting_manager = me.name
     where lower(me.email) = current_app_email()
       and me.is_reporting_manager
       and teammate.name = p_name
  )
  or exists (
    -- HR acting for an oversight-only manager. Restricted to HR rather than
    -- anyone senior, so it is a defined stand-in and not a general bypass of
    -- the reporting line.
    select 1
      from app_users me
      join app_users teammate on teammate.name = p_name
      join app_users mgr on lower(trim(mgr.name)) = lower(trim(teammate.reporting_manager))
     where lower(me.email) = current_app_email()
       and me.role = 'HR'
       and coalesce(mgr.oversight_only, false)
  );
$fn$;

-- Names HR should see approvals for on the manager's behalf. Used by the
-- client so its team list matches what RLS already permits.
create or replace function public.oversight_managed_employees()
returns table(name text)
language sql stable as $fn$
  select e.name
    from app_users e
    join app_users m on lower(trim(m.name)) = lower(trim(e.reporting_manager))
   where e.active and coalesce(m.oversight_only, false);
$fn$;
