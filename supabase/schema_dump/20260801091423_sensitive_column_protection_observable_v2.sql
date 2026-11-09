-- Fixes v1: `v_discarded || 'gross_pay'` made Postgres parse the literal as an
-- array ("malformed array literal"). array_append() is unambiguous.
create or replace function public.protect_app_users_sensitive_columns()
returns trigger
language plpgsql
as $function$
declare
  v_discarded text[] := array[]::text[];
begin
  if current_user = 'service_role'
     or current_app_is_hr_or_mgmt()
     or coalesce(current_setting('app.bypass_sensitive_column_protection', true), 'off') = 'on'
  then
    return new;
  end if;

  if new.role                     is distinct from old.role                     then v_discarded := array_append(v_discarded,'role'); end if;
  if new.active                   is distinct from old.active                   then v_discarded := array_append(v_discarded,'active'); end if;
  if new.employee_id              is distinct from old.employee_id              then v_discarded := array_append(v_discarded,'employee_id'); end if;
  if new.gross_pay                is distinct from old.gross_pay                then v_discarded := array_append(v_discarded,'gross_pay'); end if;
  if new.leave_allocation         is distinct from old.leave_allocation         then v_discarded := array_append(v_discarded,'leave_allocation'); end if;
  if new.work_location            is distinct from old.work_location            then v_discarded := array_append(v_discarded,'work_location'); end if;
  if new.reporting_manager        is distinct from old.reporting_manager        then v_discarded := array_append(v_discarded,'reporting_manager'); end if;
  if new.weekly_off_day           is distinct from old.weekly_off_day           then v_discarded := array_append(v_discarded,'weekly_off_day'); end if;
  if new.business_unit            is distinct from old.business_unit            then v_discarded := array_append(v_discarded,'business_unit'); end if;
  if new.is_reporting_manager     is distinct from old.is_reporting_manager     then v_discarded := array_append(v_discarded,'is_reporting_manager'); end if;
  if new.permission_minutes_quota is distinct from old.permission_minutes_quota then v_discarded := array_append(v_discarded,'permission_minutes_quota'); end if;
  if new.password_hash            is distinct from old.password_hash            then v_discarded := array_append(v_discarded,'password_hash'); end if;
  if new.email                    is distinct from old.email                    then v_discarded := array_append(v_discarded,'email'); end if;
  if new.company_email            is distinct from old.company_email            then v_discarded := array_append(v_discarded,'company_email'); end if;

  new.role := old.role;
  new.active := old.active;
  new.employee_id := old.employee_id;
  new.leave_allocation := old.leave_allocation;
  new.gross_pay := old.gross_pay;
  new.gross_pay_pending := old.gross_pay_pending;
  new.gross_pay_requested_at := old.gross_pay_requested_at;
  new.permission_minutes_quota := old.permission_minutes_quota;
  new.permission_minutes_quota_pending := old.permission_minutes_quota_pending;
  new.permission_minutes_quota_requested_at := old.permission_minutes_quota_requested_at;
  new.is_reporting_manager := old.is_reporting_manager;
  new.is_reporting_manager_pending := old.is_reporting_manager_pending;
  new.is_reporting_manager_requested_at := old.is_reporting_manager_requested_at;
  new.business_unit := old.business_unit;
  new.business_unit_pending := old.business_unit_pending;
  new.business_unit_requested_at := old.business_unit_requested_at;
  new.work_location := old.work_location;
  new.work_location_pending := old.work_location_pending;
  new.work_location_requested_at := old.work_location_requested_at;
  new.weekly_off_day := old.weekly_off_day;
  new.weekly_off_day_pending := old.weekly_off_day_pending;
  new.weekly_off_day_requested_at := old.weekly_off_day_requested_at;
  new.reporting_manager := old.reporting_manager;
  new.reporting_manager_pending := old.reporting_manager_pending;
  new.reporting_manager_requested_at := old.reporting_manager_requested_at;
  new.password_hash := old.password_hash;
  new.auth_user_id := old.auth_user_id;
  new.email := old.email;
  new.company_email := old.company_email;
  new.email_pending := old.email_pending;
  new.email_requested_at := old.email_requested_at;

  if array_length(v_discarded, 1) is not null then
    begin
      insert into audit_log (action, actor_email, actor_role, target_type, target_id, details)
      values ('protected_columns_discarded',
              coalesce(current_app_email(), current_user),
              coalesce(current_app_role(), ''),
              'app_users', old.email,
              jsonb_build_object('columns', to_jsonb(v_discarded)));
    exception when others then
      null;  -- auditing must never block the write itself
    end;
  end if;

  return new;
end;
$function$;
