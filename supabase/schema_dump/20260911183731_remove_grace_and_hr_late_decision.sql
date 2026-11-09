-- No grace for anyone. A minute past start time is late, so the separate
-- grace_late_count and the 3-occasions cap that governed it no longer apply.
update office_timings set grace_minutes = 0 where grace_minutes <> 0;

-- HR decides what an unabsorbed late actually costs.
--
-- Losing half a day's pay is a blunt outcome for someone who was late once
-- after their permission ran out, and HR often has context the system does
-- not — a hospital visit, a transport strike. Rather than forcing LOP, HR can
-- take the time from a leave balance instead, or waive it. Recorded per
-- employee per cycle with a reason, so a concession is visible and
-- attributable rather than an unexplained gap in the pay run.
create table if not exists late_lop_decisions (
  employee_id  text not null,
  cycle_label  text not null,           -- e.g. '2026-09'
  action       text not null default 'lop',  -- lop | CL | ML | EL | waive
  note         text default '',
  decided_by   text default '',
  decided_at   timestamptz not null default now(),
  primary key (employee_id, cycle_label)
);

comment on table late_lop_decisions is
  'HR''s decision on what a cycle''s unabsorbed lates cost: unpaid days, a deduction from a leave balance, or waived. Default is lop when no decision is recorded.';

alter table late_lop_decisions enable row level security;
create policy "late_lop_read"  on late_lop_decisions for select to authenticated
  using (employee_id = current_app_employee_id() or current_app_is_hr_or_mgmt());
create policy "late_lop_write" on late_lop_decisions for all to authenticated
  using (current_app_is_hr_or_mgmt()) with check (current_app_is_hr_or_mgmt());

-- Applies the decision, and reports what could not be honoured.
--
-- Returns lop_days (what still costs pay), leave_days (taken from a balance)
-- and shortfall_days — a bucket with too little left cannot absorb the whole
-- amount, and silently falling back to LOP would make HR's decision look like
-- it had been ignored.
create or replace function public.late_cost_for_cycle(
  p_employee_id text, p_date date default current_date
)
returns table(raw_days numeric, action text, lop_days numeric,
              leave_days numeric, leave_bucket text, shortfall_days numeric)
language plpgsql stable as $fn$
declare
  v_raw numeric;
  v_action text;
  v_avail numeric := 0;
  v_take numeric := 0;
begin
  v_raw := public.late_lop_days(p_employee_id, p_date);

  select d.action into v_action
    from late_lop_decisions d
   where d.employee_id = p_employee_id
     and d.cycle_label = public.attendance_cycle_label(p_date);
  v_action := coalesce(v_action, 'lop');

  if v_raw = 0 then
    return query select 0::numeric, v_action, 0::numeric, 0::numeric, ''::text, 0::numeric;
    return;
  end if;

  if v_action = 'waive' then
    return query select v_raw, v_action, 0::numeric, 0::numeric, ''::text, 0::numeric;
  elsif v_action in ('CL','ML','EL') then
    select b.usable into v_avail
      from public.leave_balance(p_employee_id, p_date) b
     where b.bucket = v_action;
    v_avail := coalesce(v_avail, 0);
    v_take := least(v_raw, v_avail);
    return query select v_raw, v_action, (v_raw - v_take), v_take, v_action,
                        greatest(0, v_raw - v_take);
  else
    return query select v_raw, 'lop'::text, v_raw, 0::numeric, ''::text, 0::numeric;
  end if;
end;
$fn$;
