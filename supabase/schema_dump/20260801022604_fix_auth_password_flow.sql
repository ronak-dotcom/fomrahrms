select set_config('app.bypass_sensitive_column_protection', 'on', true);

update app_users
   set password_hash = crypt(password, gen_salt('bf')), password = ''
 where coalesce(password,'') <> '' and coalesce(password_hash,'') = '';

update app_users set password_hash = null where password_hash = '';
update app_users set activation_token = null where activation_token = '';
update app_users set reset_password_token = null where reset_password_token = '';

create or replace function public.verify_app_user_password(p_email text, p_password text)
returns boolean language sql security definer set search_path to 'public','extensions'
as $function$
  select exists (
    select 1 from app_users
     where lower(email) = lower(p_email)
       and password_hash is not null
       and password_hash <> ''
       and password_hash = crypt(p_password, password_hash)
  );
$function$;
revoke all on function public.verify_app_user_password(text,text) from public, anon, authenticated;
grant execute on function public.verify_app_user_password(text,text) to service_role;

create or replace function public.try_timestamptz(p_value text)
returns timestamptz language plpgsql immutable as $function$
begin
  if p_value is null or btrim(p_value)='' then return null; end if;
  return p_value::timestamptz;
exception when others then return null;
end; $function$;

create or replace function public.app_user_by_activation_token(p_token text)
returns table(email text, name text, activation_token_expires_at text)
language sql stable security definer set search_path to 'public' as $function$
  select email, name, activation_token_expires_at from app_users
   where activation_token is not null and activation_token <> ''
     and lower(activation_token) = lower(coalesce(p_token,''))
     and coalesce(p_token,'') <> '';
$function$;

create or replace function public.app_user_by_reset_token(p_token text)
returns table(email text, name text, reset_password_token_expires_at text)
language sql stable security definer set search_path to 'public' as $function$
  select email, name, reset_password_token_expires_at from app_users
   where reset_password_token is not null and reset_password_token <> ''
     and lower(reset_password_token) = lower(coalesce(p_token,''))
     and coalesce(p_token,'') <> '';
$function$;

create or replace function public.complete_account_activation(p_token text, p_password text)
returns text language plpgsql security definer set search_path to 'public','extensions'
as $function$
declare v_email text; v_exp timestamptz;
begin
  if coalesce(p_token,'')='' or coalesce(p_password,'')='' then return null; end if;
  select email, try_timestamptz(activation_token_expires_at) into v_email, v_exp
    from app_users where activation_token is not null and lower(activation_token)=lower(p_token);
  if v_email is null then return null; end if;
  if v_exp is not null and v_exp <= now() then return null; end if;
  perform set_config('app.bypass_sensitive_column_protection','on',true);
  update app_users
     set password_hash = crypt(p_password, gen_salt('bf')), password='', active=true,
         activation_token=null, activation_token_expires_at=null,
         date_of_joining = case when date_of_joining is null or date_of_joining=''
           then to_char(now(),'YYYY-MM-DD') else date_of_joining end
   where email = v_email;
  return v_email;
end; $function$;

create or replace function public.complete_password_reset(p_token text, p_password text)
returns text language plpgsql security definer set search_path to 'public','extensions'
as $function$
declare v_email text; v_exp timestamptz;
begin
  if coalesce(p_token,'')='' or coalesce(p_password,'')='' then return null; end if;
  select email, try_timestamptz(reset_password_token_expires_at) into v_email, v_exp
    from app_users where reset_password_token is not null and lower(reset_password_token)=lower(p_token);
  if v_email is null then return null; end if;
  if v_exp is not null and v_exp <= now() then return null; end if;
  perform set_config('app.bypass_sensitive_column_protection','on',true);
  update app_users
     set password_hash = crypt(p_password, gen_salt('bf')), password='',
         reset_password_token=null, reset_password_token_expires_at=null
   where email = v_email;
  return v_email;
end; $function$;

alter table app_users drop constraint if exists app_users_password_hash_sane;
alter table app_users add constraint app_users_password_hash_sane
  check (password_hash is null or length(password_hash) >= 20) not valid;

update app_users set email = lower(btrim(email)) where email is distinct from lower(btrim(email));
update app_users set company_email = lower(btrim(company_email))
 where coalesce(company_email,'') <> '' and company_email is distinct from lower(btrim(company_email));

update app_users set company_email = lower(btrim(email))
 where coalesce(company_email,'') = '' and coalesce(email,'') <> '';

create unique index if not exists app_users_email_lower_idx on app_users (lower(email));

create or replace function public.normalise_app_user_email()
returns trigger language plpgsql as $function$
begin
  new.email := lower(btrim(coalesce(new.email,'')));
  if coalesce(new.company_email,'') <> '' then
    new.company_email := lower(btrim(new.company_email));
  end if;
  return new;
end; $function$;

drop trigger if exists trg_normalise_app_user_email on app_users;
create trigger trg_normalise_app_user_email
  before insert or update of email, company_email on app_users
  for each row execute function public.normalise_app_user_email();
