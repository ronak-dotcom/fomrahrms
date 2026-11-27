-- Late Review: HR's decisions take effect only after Management approves
-- (Ronak, 27 Nov 2026).
--
-- Excusing a single late arrival (waive_late) was already Management-only.
-- Late Review, where a cycle's late LOP is waived, charged to CL / ML / EL
-- or set to a figure, was not: HR's choice applied to pay at once. Now:
--   * HR's decision is saved as a request (status 'pending'); payroll keeps
--     using the rule (or the last approved decision) until Management acts.
--   * Management approves (status 'approved') or rejects it.
--   * A decision Management makes itself is approved at once.
--   * Management is notified of each request.

alter table public.late_lop_decisions
  add column if not exists status text not null default 'approved',
  add column if not exists approved_by text not null default '',
  add column if not exists approved_at timestamptz,
  add column if not exists requested_action text,
  add column if not exists requested_override numeric;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'late_lop_decisions_status_check') then
    alter table public.late_lop_decisions
      add constraint late_lop_decisions_status_check check (status in ('pending', 'approved', 'rejected'));
  end if;
end $$;

-- Who wrote it decides what it means. Rows written outside the app (tests,
-- maintenance) keep whatever status they were given.
create or replace function public.late_decision_approval()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_mgmt boolean := public.is_management_authority(coalesce(public.current_app_role(), ''));
begin
  if public.current_app_email() is null then
    return new;
  end if;
  if v_mgmt then
    if new.status is distinct from 'rejected' then
      new.status := 'approved';
      new.approved_by := coalesce(public.current_app_name(), '');
      new.approved_at := now();
    end if;
    return new;
  end if;
  -- HR: a request. The decision in force stays as it was until approved.
  new.requested_action := new.action;
  new.requested_override := new.lop_days_override;
  if tg_op = 'UPDATE' then
    new.action := old.action;
    new.lop_days_override := old.lop_days_override;
  else
    new.action := 'lop';
    new.lop_days_override := null;
  end if;
  new.status := 'pending';
  new.approved_by := '';
  new.approved_at := null;
  insert into public.notifications(type, title, body, route, target_role, source_id)
  values ('late_decision_request', 'Late review needs approval',
          coalesce(public.current_app_name(), 'HR') || ' asks to treat '
            || coalesce((select u.name from public.app_users u where u.employee_id = new.employee_id limit 1), new.employee_id)
            || '''s late arrivals in ' || new.cycle_label || ' as: '
            || case new.requested_action when 'waive' then 'waived'
                                         when 'lop' then 'unpaid'
                                         else 'deducted from ' || new.requested_action end
            || coalesce(' (' || nullif(btrim(new.note), '') || ')', '') || '.',
          '/management/late-review', 'Management', new.employee_id || '/' || new.cycle_label);
  return new;
end;
$$;

drop trigger if exists trg_late_decision_approval on public.late_lop_decisions;
create trigger trg_late_decision_approval
  before insert or update on public.late_lop_decisions
  for each row execute function public.late_decision_approval();

-- Management's answer to a request.
create or replace function public.decide_late_request(
  p_employee_id text, p_cycle_label text, p_approve boolean)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_management_authority(coalesce(public.current_app_role(), '')) then
    raise exception 'Only Management can approve a late review decision.' using errcode = '42501';
  end if;
  if p_approve then
    update public.late_lop_decisions d
       set action = coalesce(d.requested_action, d.action),
           lop_days_override = d.requested_override,
           status = 'approved'
     where d.employee_id = p_employee_id and d.cycle_label = p_cycle_label and d.status = 'pending';
  else
    update public.late_lop_decisions d
       set status = 'rejected'
     where d.employee_id = p_employee_id and d.cycle_label = p_cycle_label and d.status = 'pending';
  end if;
  -- (The approval trigger stamps who approved and when.)
  return found;
end;
$$;

revoke all on function public.decide_late_request(text, text, boolean) from public, anon;
grant execute on function public.decide_late_request(text, text, boolean) to authenticated;

-- Payroll (late_lop_days, late_cost_for_cycle) reads action and
-- lop_days_override, which always hold the decision in force: HR's request
-- waits in requested_action / requested_override until Management approves,
-- and a rejected request leaves the earlier decision (or the rule) in place.

do $zzcheck$
declare v_fail text;
begin
  select string_agg(test_name, '; ') into v_fail from public.run_money_rule_tests() where not passed;
  if v_fail is not null then raise exception 'Money-rule tests failed: %', v_fail; end if;
end $zzcheck$;
