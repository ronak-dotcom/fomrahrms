-- Employee of the Month had NO approval step and raised NO notification.
-- HR wrote the row and it was live immediately — nothing reached Management,
-- which is why no approval notification ever arrived: there was no flow to
-- send one.
--
-- Brought into line with the other Management-approved decisions: HR proposes,
-- Management approves, and nothing is published until they do.
alter table employee_of_month
  add column if not exists status        text not null default 'approved',
  add column if not exists proposed_by   text default '',
  add column if not exists decided_by    text default '',
  add column if not exists decided_at    timestamptz,
  add column if not exists decline_reason text default '';

comment on column employee_of_month.status is
  'pending | approved | declined. Existing rows default to approved so the current winner is not retroactively unpublished.';

-- Only approved winners are shown on dashboards.
create or replace view public.v_published_employee_of_month as
  select * from employee_of_month where coalesce(status,'approved') = 'approved';

create or replace function public.decide_employee_of_month(
  p_id text,
  p_approve boolean,
  p_reason text default ''
) returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_management_authority(coalesce(current_app_role(),'')) then
    raise exception 'Only Management can approve Employee of the Month.'
      using errcode = 'insufficient_privilege';
  end if;

  update employee_of_month
     set status         = case when p_approve then 'approved' else 'declined' end,
         decided_by     = coalesce(current_app_name(), ''),
         decided_at     = now(),
         decline_reason = case when p_approve then '' else coalesce(p_reason,'') end
   where id::text = p_id;

  return found;
end;
$function$;

revoke all on function public.decide_employee_of_month(text, boolean, text) from public, anon;
grant execute on function public.decide_employee_of_month(text, boolean, text) to authenticated, service_role;
