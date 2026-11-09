-- Where the reporting manager IS the HR role holder there is no second
-- person to sign, and blocking the day would punish the employee for an org
-- chart they did not choose. So no action means approved: the confirmation
-- goes through on the manager's signature, and Management can reject it
-- beforehand or overturn it afterwards.
--
-- Deliberately marked as auto-approved rather than attributed to a person.
-- Recording a name nobody actually clicked would make the audit trail lie
-- about who took responsibility, and the whole point of the vouched flag is
-- that these days are visibly weaker evidence.
create or replace function public.auto_approve_when_no_second_approver()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare v_manager_is_hr boolean;
begin
  if new.status <> 'confirmed' or new.hr_status <> 'pending' then
    return new;
  end if;

  select exists (
    select 1 from app_users e
      join app_users m on lower(trim(m.name)) = lower(trim(e.reporting_manager))
     where e.employee_id = new.employee_id and m.role = 'HR'
  ) into v_manager_is_hr;

  if v_manager_is_hr then
    new.hr_status := 'approved';
    new.hr_decided_by := 'system';
    new.hr_decided_by_name := 'Auto-approved (manager is HR)';
    new.hr_decided_at := now();
    new.hr_note := 'No separate HR approver: the reporting manager holds the '
                || 'HR role. Approved automatically; Management may overturn.';
  end if;
  return new;
end;
$fn$;

-- BEFORE so the values are set on the same row version the existing
-- apply_attendance_confirmation() AFTER trigger then acts on — otherwise the
-- attendance record would not be created until something else touched the row.
drop trigger if exists trg_auto_approve_confirmation on attendance_confirmations;
create trigger trg_auto_approve_confirmation
  before update of status on attendance_confirmations
  for each row execute function auto_approve_when_no_second_approver();
