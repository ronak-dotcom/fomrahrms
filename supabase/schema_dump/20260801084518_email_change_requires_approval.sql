alter table app_users add column if not exists email_pending      text default '';
alter table app_users add column if not exists email_requested_at text default '';

create or replace function public.protect_login_email()
returns trigger language plpgsql as $function$
begin
  if new.email is distinct from old.email then
    if current_user = 'service_role'
       or coalesce(current_setting('app.allow_login_email_change', true), 'off') = 'on'
    then
      new.auth_user_id := null;
    else
      raise exception
        'Login email changes require Management approval — use request_login_email_change() and approve_login_email_change().'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_protect_login_email on app_users;
create trigger trg_protect_login_email
  before update of email on app_users
  for each row execute function public.protect_login_email();

create or replace function public.request_login_email_change(p_employee_email text, p_new_email text)
returns boolean language plpgsql security definer set search_path to 'public'
as $function$
declare v_new text := lower(btrim(coalesce(p_new_email,'')));
begin
  if not current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can request a login email change.' using errcode='insufficient_privilege';
  end if;
  if v_new = '' or v_new !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'That does not look like a valid email address.' using errcode='check_violation';
  end if;
  if exists (select 1 from app_users where lower(email)=v_new) then
    raise exception 'Another account already uses that email address.' using errcode='unique_violation';
  end if;
  update app_users
     set email_pending = v_new,
         email_requested_at = to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"')
   where lower(email) = lower(btrim(p_employee_email));
  return found;
end; $function$;

create or replace function public.approve_login_email_change(p_employee_email text)
returns text language plpgsql security definer set search_path to 'public'
as $function$
declare v_old text; v_new text;
begin
  if coalesce(current_app_role(),'') <> 'Management' then
    raise exception 'Only Management can approve a login email change.' using errcode='insufficient_privilege';
  end if;
  select email, nullif(btrim(email_pending),'') into v_old, v_new
    from app_users where lower(email)=lower(btrim(p_employee_email));
  if v_new is null then return null; end if;
  if exists (select 1 from app_users where lower(email)=v_new) then
    raise exception 'Another account already uses that email address.' using errcode='unique_violation';
  end if;
  perform set_config('app.allow_login_email_change','on',true);
  perform set_config('app.bypass_sensitive_column_protection','on',true);
  update app_users
     set email = v_new, company_email = v_new,
         email_pending = '', email_requested_at = '',
         activation_token = null, activation_token_expires_at = null,
         reset_password_token = null, reset_password_token_expires_at = null
   where lower(email) = lower(v_old);
  return v_new;
end; $function$;

create or replace function public.reject_login_email_change(p_employee_email text)
returns boolean language plpgsql security definer set search_path to 'public'
as $function$
begin
  if coalesce(current_app_role(),'') <> 'Management' then
    raise exception 'Only Management can reject a login email change.' using errcode='insufficient_privilege';
  end if;
  update app_users set email_pending='', email_requested_at=''
   where lower(email)=lower(btrim(p_employee_email));
  return found;
end; $function$;

revoke all on function public.request_login_email_change(text,text) from public, anon;
revoke all on function public.approve_login_email_change(text) from public, anon;
revoke all on function public.reject_login_email_change(text) from public, anon;
grant execute on function public.request_login_email_change(text,text) to authenticated, service_role;
grant execute on function public.approve_login_email_change(text) to authenticated, service_role;
grant execute on function public.reject_login_email_change(text) to authenticated, service_role;

create or replace function public.protect_app_users_sensitive_columns()
returns trigger language plpgsql as $function$
begin
  if current_user = 'service_role' or current_app_is_hr_or_mgmt() then
    return new;
  end if;
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
  return new;
end; $function$;
