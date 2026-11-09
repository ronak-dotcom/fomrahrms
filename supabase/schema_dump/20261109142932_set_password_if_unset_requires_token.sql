-- set_password_if_unset(email, password) was executable by `anon` and asked
-- for no proof of identity beyond the email address. Anyone logged out could
-- type a new joiner's address at the sign-in screen, be offered the
-- "create your password" panel, and claim the account before its owner ever
-- saw the activation mail. Company addresses follow firstname.lastname@, so
-- guessing one takes no effort.
--
-- The secure path already exists — complete_account_activation() checks the
-- token from the activation email. This brings the same proof to this
-- function rather than removing it, so the login-screen flow still works for
-- someone who arrives with their activation link.
--
-- Safe to tighten now: no account is currently sitting without a password,
-- so nobody is mid-activation and nobody is locked out by this.
create or replace function public.set_password_if_unset(
  p_email    text,
  p_password text,
  p_token    text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exp timestamptz;
begin
  if coalesce(p_email,'') = '' or coalesce(p_password,'') = '' then
    return false;
  end if;

  -- The token must belong to this very account, be unused and unexpired.
  select public.try_timestamptz(activation_token_expires_at) into v_exp
    from app_users
   where lower(email) = lower(p_email)
     and coalesce(password_hash,'') = ''
     and coalesce(activation_token,'') <> ''
     and lower(activation_token) = lower(coalesce(p_token,''));

  if not found then
    return false;
  end if;
  if v_exp is not null and v_exp <= now() then
    return false;
  end if;

  perform set_config('app.bypass_sensitive_column_protection', 'on', true);
  update app_users
     set password_hash              = crypt(p_password, gen_salt('bf')),
         password                   = '',
         active                     = true,
         activation_token           = null,
         activation_token_expires_at = null
   where lower(email) = lower(p_email);
  return found;
end;
$$;

-- The old two-argument form is what the unauthenticated path could reach.
drop function if exists public.set_password_if_unset(text, text);

revoke all on function public.set_password_if_unset(text, text, text) from public;
grant execute on function public.set_password_if_unset(text, text, text) to anon, authenticated;
