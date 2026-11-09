-- Three accounts are deactivated exits (FD-03, FHIPL-04, FHIPL-26). Someone
-- signing in to a deactivated account saw "No account found with that email",
-- which sends them hunting for a typo instead of to HR. Report the two cases
-- apart: `status` is 'ok', 'inactive' or 'not_found'.
drop function if exists public.request_password_reset(text, text, text);

create or replace function public.request_password_reset(
  p_identifier text,
  p_token      text,
  p_expires_at text
)
returns table (status text, name text, recipient text)
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
    return query select 'not_found'::text, null::text, null::text;
    return;
  end if;

  -- Matched without the active filter so a deactivated account can be told
  -- apart from one that was never there.
  select * into v
    from app_users u
   where lower(trim(u.email)) = v_q
      or (coalesce(u.company_email, '') <> '' and lower(trim(u.company_email)) = v_q)
      or lower(trim(u.employee_id)) = v_q
      or (length(v_digits) >= 6
          and regexp_replace(coalesce(u.mobile, ''), '\D', '', 'g') = v_digits)
   order by coalesce(u.active, true) desc   -- a live account wins a reused address
   limit 1;

  if not found then
    return query select 'not_found'::text, null::text, null::text;
    return;
  end if;

  if not coalesce(v.active, true) then
    -- No token is issued for a deactivated account.
    return query select 'inactive'::text, v.name, null::text;
    return;
  end if;

  update app_users
     set reset_password_token            = p_token,
         reset_password_token_expires_at = p_expires_at
   where email = v.email;

  return query
    select 'ok'::text,
           v.name,
           case when coalesce(v.company_email, '') <> ''
                then v.company_email
                else v.email
           end;
end;
$$;

revoke all on function public.request_password_reset(text, text, text) from public;
grant execute on function public.request_password_reset(text, text, text) to anon, authenticated;
