-- reporting_manager is matched by NAME, not employee_id — app_manages() joins
-- teammate.reporting_manager = me.name — so a typo produces an approval chain
-- that silently points at nobody. Jose Jenin Jeevi J currently reports to
-- "ronak", who does not exist in app_users, so anything he submits lands in a
-- queue with no owner.
--
-- This validates FUTURE writes only. The existing "ronak" row is deliberately
-- left alone: who Jose actually reports to is an organisational decision, not
-- something to guess in a migration. It is reported separately.
--
-- The proper fix is to key the relationship on employee_id rather than name;
-- that is a larger change requiring the app to be updated in step. This closes
-- the immediate hole without pretending to be that fix.

create or replace function public.validate_reporting_manager()
returns trigger
language plpgsql
as $function$
begin
  if coalesce(btrim(new.reporting_manager), '') = '' then
    return new;                                  -- no manager is legitimate
  end if;

  if new.reporting_manager = new.name then
    raise exception 'An employee cannot report to themselves.'
      using errcode = 'check_violation';
  end if;

  if not exists (
    select 1 from app_users m
     where lower(btrim(m.name)) = lower(btrim(new.reporting_manager))
  ) then
    raise exception
      'No employee named "%" exists, so approvals would have no owner. Pick an existing employee as the reporting manager.',
      new.reporting_manager
      using errcode = 'foreign_key_violation';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_validate_reporting_manager on app_users;
create trigger trg_validate_reporting_manager
  before insert or update of reporting_manager, name on app_users
  for each row execute function public.validate_reporting_manager();

-- Surface any existing dangling references for HR to correct.
create or replace view public.v_dangling_reporting_managers as
  select u.name, u.employee_id, u.role, u.reporting_manager
    from app_users u
   where coalesce(btrim(u.reporting_manager), '') <> ''
     and not exists (
       select 1 from app_users m
        where lower(btrim(m.name)) = lower(btrim(u.reporting_manager))
     );
