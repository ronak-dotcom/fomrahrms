-- Balances were never stored — they were entitlement-for-this-cycle minus
-- leave-taken-this-cycle, so anything unused simply vanished at the cycle
-- boundary and there was no number for HR to correct.
--
-- Rules being implemented:
--   * 1 CL + 1 ML + 1 EL accrued per cycle once confirmed; 1 CL only while
--     on probation.
--   * Unused leave carries forward within the leave year.
--   * The leave year runs 26 Dec -> 25 Dec, matching the attendance cycle
--     boundary rather than the calendar, so a reset never lands mid-cycle.
--   * On 26 Dec, CL and ML start fresh; EL continues, capped at 25.

create table if not exists leave_adjustments (
  id            uuid primary key default gen_random_uuid(),
  employee_id   text not null,
  bucket        text not null,          -- CL | ML | EL
  days          numeric not null,       -- may be negative
  reason        text not null default '',
  effective_on  date not null default current_date,
  created_by    text default '',
  created_at    timestamptz not null default now()
);

comment on table leave_adjustments is
  'HR/Management corrections to an individual balance — opening balances, carry-forward from before the system, encashment, or fixing a mistake. Kept as a ledger rather than an editable total so every change has a reason and an author.';

create index if not exists leave_adjustments_emp_idx on leave_adjustments (employee_id);

alter table leave_adjustments enable row level security;
create policy "leave_adjustments_read" on leave_adjustments
  for select to authenticated
  using (employee_id = current_app_employee_id() or current_app_is_hr_or_mgmt());
create policy "leave_adjustments_write" on leave_adjustments
  for all to authenticated
  using (current_app_is_hr_or_mgmt()) with check (current_app_is_hr_or_mgmt());

-- Start of the leave year containing p_date: the 26 Dec on or before it.
create or replace function public.leave_year_start(p_date date default current_date)
returns date language sql immutable as $fn$
  select case
    when p_date >= make_date(extract(year from p_date)::int, 12, 26)
      then make_date(extract(year from p_date)::int, 12, 26)
    else make_date(extract(year from p_date)::int - 1, 12, 26)
  end;
$fn$;

-- Whole cycles from the later of (leave-year start, joining date) up to and
-- including the cycle p_date falls in. Cycles turn on the 26th, so this is a
-- month count between the two 26ths.
create or replace function public.cycles_accrued(
  p_joining date, p_date date default current_date
) returns integer language sql stable as $fn$
  with bounds as (
    select greatest(public.leave_year_start(p_date),
                    coalesce(p_joining, public.leave_year_start(p_date))) as from_d,
           public.attendance_cycle_start(p_date) as current_cycle_start
  )
  select greatest(0,
    (extract(year  from current_cycle_start) - extract(year  from from_d))::int * 12
  + (extract(month from current_cycle_start) - extract(month from from_d))::int
  -- Joining mid-cycle still earns that cycle, so the part-month counts.
  + case when extract(day from from_d) > 25 then 0 else 1 end
  )::int
  from bounds;
$fn$;
