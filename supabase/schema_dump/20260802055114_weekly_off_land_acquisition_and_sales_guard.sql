-- Sales works every Sunday; Land Acquisition does not.
--
-- weekly_off_day uses '' as a sentinel meaning Sunday (see
-- hr_employee_records_page: `weeklyOffDay = day == 'Sunday' ? '' : day`), and
-- every employee currently has ''. For Sales that is exactly wrong: Sunday is
-- a working day for them, so a Sales employee with '' has their working day
-- marked as an off day and their real off day marked as working.

alter table app_users disable trigger trg_protect_app_users;

-- Land Acquisition: Sunday off. '' already means Sunday, so this is a no-op
-- in value but makes the intent explicit rather than relying on the sentinel.
update app_users set weekly_off_day = ''
 where department = 'Land Acquisition';

alter table app_users enable trigger trg_protect_app_users;

-- Surface Sales staff who still have no explicit weekly off. They cannot be
-- left on the Sunday default, and the day is a per-person decision made by the
-- reporting manager and HR, so it is not guessed here.
create or replace view public.v_sales_missing_weekly_off as
  select name, employee_id, department, reporting_manager,
         'Sunday is a working day for Sales — an explicit weekly off day must be set by the reporting manager and HR'
           as action_required
    from app_users
   where department = 'Sales'
     and coalesce(btrim(weekly_off_day), '') = '';

-- Warn rather than block: an employee whose department works Sundays should
-- not silently end up with Sunday off. Blocking outright would prevent HR from
-- creating a Sales employee before deciding their off day, which is the normal
-- order of events.
create or replace function public.warn_sales_sunday_off()
returns trigger
language plpgsql
as $function$
begin
  if new.department = 'Sales' and coalesce(btrim(new.weekly_off_day),'') = '' then
    begin
      insert into audit_log (action, actor_email, actor_role, target_type, target_id, details)
      values ('sales_weekly_off_unset',
              coalesce(current_app_email(), current_user),
              coalesce(current_app_role(), ''),
              'app_users', new.email,
              jsonb_build_object('note','Sales works Sundays; weekly off day still unset'));
    exception when others then null;
    end;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_warn_sales_sunday_off on app_users;
create trigger trg_warn_sales_sunday_off
  after insert or update of department, weekly_off_day on app_users
  for each row execute function public.warn_sales_sunday_off();
