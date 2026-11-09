-- New Employee of the Month entries must await Management approval.
--
-- The column default was 'approved' so that EXISTING rows were not
-- retroactively unpublished when the column was added. But that default also
-- applied to new inserts, so HR's entry still went live immediately — the
-- approval gate existed but nothing had to pass through it.
--
-- Flip the default to 'pending'. Existing rows keep the 'approved' value they
-- were backfilled with; only new entries are gated.
alter table employee_of_month
  alter column status set default 'pending';

-- Belt and braces: HR must not be able to write 'approved' directly, or the
-- gate is bypassable by a client that sets the column itself. Only
-- decide_employee_of_month() (SECURITY DEFINER, Management-only) may do that.
create or replace function public.protect_eom_status()
returns trigger
language plpgsql
as $function$
begin
  if coalesce(current_setting('app.allow_eom_decision', true), 'off') = 'on' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Whatever the client sends, a new entry starts pending.
    new.status := 'pending';
    new.decided_by := '';
    new.decided_at := null;
    return new;
  end if;

  -- On UPDATE, the decision fields are owned by the RPC.
  new.status     := old.status;
  new.decided_by := old.decided_by;
  new.decided_at := old.decided_at;
  return new;
end;
$function$;

drop trigger if exists trg_protect_eom_status on employee_of_month;
create trigger trg_protect_eom_status
  before insert or update on employee_of_month
  for each row execute function public.protect_eom_status();

-- The RPC sets the flag so its own update is allowed through.
create or replace function public.decide_employee_of_month(
  p_id text, p_approve boolean, p_reason text default ''
) returns boolean language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_management_authority(coalesce(current_app_role(),'')) then
    raise exception 'Only Management can approve Employee of the Month.'
      using errcode = 'insufficient_privilege';
  end if;

  perform set_config('app.allow_eom_decision', 'on', true);

  update employee_of_month
     set status         = case when p_approve then 'approved' else 'declined' end,
         decided_by     = coalesce(current_app_name(), ''),
         decided_at     = now(),
         decline_reason = case when p_approve then '' else coalesce(p_reason,'') end
   where id::text = p_id;

  return found;
end; $function$;
