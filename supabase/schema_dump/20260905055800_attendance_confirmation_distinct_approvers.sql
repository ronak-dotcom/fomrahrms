-- The two signatures only mean something if two different people give them.
-- Akila's reporting manager IS the HR role holder (Jose is both), so he would
-- have seen both queues and could confirm and then approve his own
-- confirmation — turning an unverified day into paid attendance alone, which
-- is exactly what the second signature exists to prevent.
--
-- Enforced here rather than by hiding a button, so it holds no matter which
-- screen or client the update comes from.
create or replace function public.enforce_distinct_confirmation_approvers()
returns trigger language plpgsql as $fn$
begin
  if new.hr_status = 'approved'
     and coalesce(new.decided_by,'') <> ''
     and lower(trim(new.decided_by)) = lower(trim(coalesce(new.hr_decided_by,''))) then
    raise exception
      'The same person cannot both confirm and approve this attendance. %',
      'Ask Management to give the second approval.';
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_distinct_confirmation_approvers on attendance_confirmations;
create trigger trg_distinct_confirmation_approvers
  before update of hr_status on attendance_confirmations
  for each row execute function enforce_distinct_confirmation_approvers();

-- Where manager and HR are the same person there is no second HR to fall
-- back on, so Management provides the second signature instead. They are
-- already the final authority; this makes them the approver rather than an
-- observer for these cases only.
create or replace function public.confirmation_needs_management(p_id uuid)
returns boolean language sql stable as $fn$
  select exists (
    select 1
      from attendance_confirmations c
      join app_users e on e.employee_id = c.employee_id
      join app_users m on lower(trim(m.name)) = lower(trim(e.reporting_manager))
     where c.id = p_id
       and m.role = 'HR'
  );
$fn$;
