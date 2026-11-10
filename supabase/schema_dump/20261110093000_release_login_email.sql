-- A login email is the primary key of app_users, so a departing employee's
-- address stayed locked forever and HR could not give a role mailbox to the
-- person taking over the job: "Already used by SOWNDARYA", Forward disabled.
--
-- Freeing it is not a rename of one field. Seven tables point at the address
-- loosely, with no foreign key to drag along: audit_log, notifications,
-- notification_preferences, appraisal_forms, kra_documents, onboarding_forms
-- and device_tokens. Leave them and the new holder inherits the leaver's
-- history -- SOWNDARYA's 79 audit rows would have read as the new person's
-- actions. So the address moves to an archive form and every reference moves
-- with it, keeping each person's history attached to them.
--
-- The archive address is built from the employee ID, which is never
-- reissued, so it cannot collide, and points at a subdomain with no mail
-- routing: nothing should ever be delivered there.
create table if not exists public.released_login_emails (
  released_email text primary key,
  archived_as    text        not null,
  employee_id    text,
  previous_name  text,
  released_at    timestamptz not null default now(),
  released_by    text,
  note           text
);

alter table public.released_login_emails enable row level security;

create policy released_login_emails_read on public.released_login_emails
  for select to authenticated using (true);

create policy released_login_emails_write on public.released_login_emails
  for all to authenticated using (current_app_is_hr_or_mgmt())
  with check (current_app_is_hr_or_mgmt());

create or replace function public.release_login_email(
  p_email  text,
  p_reason text default null
)
returns table (
  archived_as   text,
  employee_id   text,
  previous_name text,
  rows_moved    integer
)
language plpgsql
security definer
set search_path = public, auth
as $fn$
declare
  v         app_users%rowtype;
  v_archive text;
  v_auth    uuid;
  v_moved   integer := 0;
  n         integer;
begin
  if not current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can release a login email';
  end if;

  select * into v from app_users where lower(email) = lower(trim(p_email));
  if not found then
    raise exception 'No account found for %', p_email;
  end if;

  -- Never take an address off someone who still works here.
  if coalesce(v.active, true) then
    raise exception
      'Refusing to release % - % is still active. Retire the account first (retire_employee).',
      p_email, v.name;
  end if;

  v_auth := v.auth_user_id;

  v_archive := lower(coalesce(nullif(v.employee_id, ''),
                              replace(split_part(v.email, '@', 1), '.', '_')))
               || '@exited.fomrahousing.in';

  if exists (select 1 from app_users where lower(email) = v_archive) then
    raise exception 'Archive address % is already in use', v_archive;
  end if;

  perform set_config('app.bypass_sensitive_column_protection', 'on', true);
  -- protect_login_email() guards the primary key against casual edits and
  -- points at request/approve_login_email_change() for a live employee
  -- changing their own address. This is the other case: a departed account
  -- being archived so the address can be reissued. Same documented bypass.
  perform set_config('app.allow_login_email_change', 'on', true);

  update audit_log set actor_email = v_archive
    where lower(actor_email) = lower(v.email);
  get diagnostics n = row_count; v_moved := v_moved + n;

  update notifications set target_email = v_archive
    where lower(target_email) = lower(v.email);
  get diagnostics n = row_count; v_moved := v_moved + n;

  update notification_preferences set email = v_archive
    where lower(email) = lower(v.email);
  get diagnostics n = row_count; v_moved := v_moved + n;

  update appraisal_forms set employee_email = v_archive
    where lower(employee_email) = lower(v.email);
  get diagnostics n = row_count; v_moved := v_moved + n;

  update kra_documents set employee_email = v_archive
    where lower(employee_email) = lower(v.email);
  get diagnostics n = row_count; v_moved := v_moved + n;

  update onboarding_forms set assigned_email = v_archive
    where lower(assigned_email) = lower(v.email);
  get diagnostics n = row_count; v_moved := v_moved + n;

  update device_tokens set email = v_archive
    where lower(email) = lower(v.email);
  get diagnostics n = row_count; v_moved := v_moved + n;

  -- The row itself. company_email is cleared so it cannot shadow the new
  -- holder, who will carry that mailbox.
  update app_users
     set email = v_archive,
         company_email = ''
   where email = v.email;

  -- Free the address in Auth too, or the new account cannot be created
  -- there, and expire any session still alive on the old identity.
  if v_auth is not null then
    update auth.identities
       set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb),
                                     '{email}', to_jsonb(v_archive))
     where user_id = v_auth;

    update auth.users
       set email = v_archive,
           email_change = '',
           email_change_token_new = ''
     where id = v_auth;

    update auth.sessions set not_after = now()
     where user_id = v_auth and (not_after is null or not_after > now());
  end if;

  insert into released_login_emails
    (released_email, archived_as, employee_id, previous_name, released_by, note)
  values (lower(v.email), v_archive, v.employee_id, v.name,
          coalesce(current_app_email(), 'unknown'),
          coalesce(p_reason, 'Login email released for reuse'))
  on conflict (released_email) do nothing;

  perform log_audit_event('login_email_released', 'app_users', v.employee_id,
    jsonb_build_object('from', lower(v.email), 'to', v_archive,
                       'rows_moved', v_moved));

  return query select v_archive, v.employee_id, v.name, v_moved;
end;
$fn$;

revoke all on function public.release_login_email(text, text) from public;
grant execute on function public.release_login_email(text, text) to authenticated;

-- Run for SOWNDARYA (FD-03) on 10 Nov 2026: 86 references moved
-- (79 audit_log, 3 notifications, 4 onboarding_forms), 30 live auth sessions
-- expired, accounts@fomrahousing.in freed in both app_users and auth.users.
