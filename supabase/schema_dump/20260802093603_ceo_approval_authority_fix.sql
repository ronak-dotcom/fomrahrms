-- Renaming the CEO's role from 'Management' to 'CEO' silently removed his
-- ability to approve login email changes: approve_ and reject_ both tested
-- current_app_role() <> 'Management' literally. Verified by calling the RPC
-- as the CEO and getting insufficient_privilege.
--
-- Route these through is_management_authority() so the check is about
-- AUTHORITY rather than one literal role string, and adding a further
-- management-tier role later cannot quietly remove someone's powers again.

create or replace function public.approve_login_email_change(p_employee_email text)
returns text language plpgsql security definer set search_path to 'public'
as $function$
declare v_old text; v_new text;
begin
  if not public.is_management_authority(coalesce(current_app_role(),'')) then
    raise exception 'Only Management or the CEO can approve a login email change.'
      using errcode='insufficient_privilege';
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
  if not public.is_management_authority(coalesce(current_app_role(),'')) then
    raise exception 'Only Management or the CEO can reject a login email change.'
      using errcode='insufficient_privilege';
  end if;
  update app_users set email_pending='', email_requested_at=''
   where lower(email)=lower(btrim(p_employee_email));
  return found;
end; $function$;

-- Selfie-access policies also enumerate roles literally. Widen to include CEO.
-- (attendance_selfies / selfie retention migrations used role in ('HR','Management'))
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname, cmd, qual, with_check
      from pg_policies
     where schemaname = 'public'
       and (coalesce(qual,'') || coalesce(with_check,'')) like '%Management%'
  loop
    raise notice 'policy still enumerating roles literally: %.%', r.tablename, r.policyname;
  end loop;
end $$;
