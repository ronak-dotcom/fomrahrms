-- An executive marking a task done set it straight to 'completed'. The
-- reporting manager was notified, but only after the fact — they were told,
-- not asked, and had no way to say "that is not finished".
--
-- Completion now needs confirming: the employee marks it done, the manager
-- confirms or sends it back.
alter table tasks
  add column if not exists completion_claimed_at   timestamptz,
  add column if not exists completion_confirmed_by text default '',
  add column if not exists completion_confirmed_at timestamptz,
  add column if not exists reopen_reason           text default '';

comment on column tasks.completion_claimed_at is
  'When the assignee said it was done. Confirmation by the reporting manager is what actually completes it.';

-- Only the reporting manager, HR or Management may confirm — not the person
-- who did the work.
create or replace function public.confirm_task_completion(p_task_id text, p_confirm boolean, p_reason text default '')
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_assignee text; v_manager text;
begin
  select assigned_employee into v_assignee from tasks where id = p_task_id;
  if v_assignee is null then return false; end if;

  select reporting_manager into v_manager from app_users
   where lower(btrim(name)) = lower(btrim(v_assignee)) limit 1;

  -- The assignee confirming their own work would make the step meaningless.
  if lower(btrim(coalesce(current_app_name(),''))) = lower(btrim(v_assignee)) then
    raise exception 'You cannot confirm your own task. Your reporting manager confirms it.'
      using errcode = 'insufficient_privilege';
  end if;

  if not (
      lower(btrim(coalesce(current_app_name(),''))) = lower(btrim(coalesce(v_manager,'')))
      or public.is_management_authority(coalesce(current_app_role(),''))
      or coalesce(current_app_role(),'') = 'HR'
  ) then
    raise exception 'Only the reporting manager, HR or Management can confirm a task.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_confirm then
    update tasks
       set status = 'completed',
           completion_confirmed_by = coalesce(current_app_name(),''),
           completion_confirmed_at = now(),
           reopen_reason = ''
     where id = p_task_id;
  else
    -- Sent back: the work continues, with the reason recorded.
    update tasks
       set status = 'in_progress',
           completion_claimed_at = null,
           reopen_reason = coalesce(btrim(p_reason),'')
     where id = p_task_id;
  end if;
  return found;
end;
$function$;

revoke all on function public.confirm_task_completion(text, boolean, text) from public, anon;
grant execute on function public.confirm_task_completion(text, boolean, text) to authenticated, service_role;
