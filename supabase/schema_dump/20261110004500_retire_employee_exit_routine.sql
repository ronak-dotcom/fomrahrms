-- Exiting someone was a single flag: app_users.active = false. That stops
-- them signing in and drops them out of attendance and payroll, and nothing
-- else — so three people who had left still had 12 live push tokens between
-- them, Prasanth S alone holding 10 as recently as 27 October. Company
-- notifications were still being delivered to their personal devices.
--
-- One routine so an exit does the whole job, and the same job every time.
-- Nothing historical is deleted: attendance, leave, payroll, appraisals and
-- the audit trail all stay attached to the person who did them.
create or replace function public.retire_employee(
  p_email  text,
  p_reason text default null
)
returns table (
  employee_id     text,
  name            text,
  tokens_revoked  integer,
  id_retired      boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v        app_users%rowtype;
  v_tokens integer := 0;
  v_retire boolean := false;
begin
  if not current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can retire an employee';
  end if;

  select * into v from app_users where lower(email) = lower(trim(p_email));
  if not found then
    raise exception 'No account found for %', p_email;
  end if;

  -- 1. No further sign-in, and no route back in through a stale token.
  perform set_config('app.bypass_sensitive_column_protection', 'on', true);
  update app_users
     set active                          = false,
         activation_token                = null,
         activation_token_expires_at     = null,
         reset_password_token            = null,
         reset_password_token_expires_at = null
   where email = v.email;

  -- 2. Revoke push. This is the part that was missing: a device token
  --    outlives the session, so it keeps delivering until it is deleted.
  delete from device_tokens where lower(email) = lower(v.email);
  get diagnostics v_tokens = row_count;

  -- 3. Never reissue the employee ID. Attendance and payroll rows are keyed
  --    to it, so a reissued ID silently inherits the leaver's history.
  if coalesce(v.employee_id, '') <> '' then
    insert into retired_employee_ids (employee_id, previous_name, retired_at, note)
    values (v.employee_id, v.name, now(),
            coalesce(p_reason, 'Employee exit'))
    on conflict (employee_id) do nothing;
    v_retire := true;
  end if;

  perform log_audit_event(
    'employee_retired', 'app_users', v.employee_id,
    jsonb_build_object('reason', p_reason, 'tokens_revoked', v_tokens));

  return query select v.employee_id, v.name, v_tokens, v_retire;
end;
$$;

revoke all on function public.retire_employee(text, text) from public;
grant execute on function public.retire_employee(text, text) to authenticated;

comment on function public.retire_employee(text, text) is
  'The full exit routine: deactivate, clear sign-in tokens, revoke push '
  'devices, and retire the employee ID so it is never reissued. History is '
  'left intact. Use this rather than setting active = false by hand.';
