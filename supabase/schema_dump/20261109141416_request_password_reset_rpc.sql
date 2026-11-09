-- Forgot Password was unusable for every employee.
--
-- The dialog runs before sign-in, so the caller is `anon`. Every SELECT and
-- UPDATE policy on app_users is granted to `authenticated` only, so the
-- lookup returned zero rows and the screen reported "No account found with
-- that email" for accounts that plainly exist — and the token write that
-- follows would have been blocked too.
--
-- The rest of the reset flow already runs through SECURITY DEFINER RPCs
-- (app_user_by_reset_token, complete_password_reset). This is the one step
-- that was left on direct table access.
--
-- Finds the account by login email, company email, employee ID or mobile,
-- stores the reset token, and returns only the display name and the address
-- the link should go to. Nothing else about the row is exposed.
create or replace function public.request_password_reset(
  p_identifier text,
  p_token      text,
  p_expires_at text
)
returns table (name text, recipient text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_q      text := lower(trim(coalesce(p_identifier, '')));
  v_digits text := regexp_replace(coalesce(p_identifier, ''), '\D', '', 'g');
  v        app_users%rowtype;
begin
  if v_q = '' or coalesce(p_token, '') = '' then
    return;
  end if;

  select * into v
    from app_users u
   where coalesce(u.active, true)
     and (
          lower(trim(u.email)) = v_q
       or (coalesce(u.company_email, '') <> '' and lower(trim(u.company_email)) = v_q)
       or lower(trim(u.employee_id)) = v_q
       -- Only match a mobile when the identifier really looks like one;
       -- otherwise an employee with no mobile on file would match "".
       or (length(v_digits) >= 6
           and regexp_replace(coalesce(u.mobile, ''), '\D', '', 'g') = v_digits)
     )
   limit 1;

  if not found then
    return;
  end if;

  update app_users
     set reset_password_token             = p_token,
         reset_password_token_expires_at  = p_expires_at
   where email = v.email;

  return query
    select v.name,
           case when coalesce(v.company_email, '') <> ''
                then v.company_email
                else v.email
           end;
end;
$$;

revoke all on function public.request_password_reset(text, text, text) from public;
grant execute on function public.request_password_reset(text, text, text) to anon, authenticated;
