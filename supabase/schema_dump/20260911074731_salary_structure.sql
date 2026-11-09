-- Per-employee salary structure, so payroll can be generated rather than
-- maintained in a spreadsheet. app_users held only gross_pay, and payslips
-- had 28 columns with nothing to populate them from — one July payslip
-- existed with gross 0 and real deductions.
--
-- Components are stored as amounts rather than derived from a formula. The
-- sheet's own arithmetic is not uniform: basic is 50% of gross and HRA 40% of
-- basic throughout, but DA follows a slab, conveyance and educational
-- allowance apply to some grades only, and whichever component is left over
-- absorbs the rounding. Re-deriving that would produce figures that differ
-- from what people have actually been paid.
create table if not exists salary_structures (
  employee_id      text primary key,
  actual_gross     numeric not null default 0,
  basic            numeric not null default 0,
  da               numeric not null default 0,
  hra              numeric not null default 0,
  conveyance       numeric not null default 0,
  other_allowance  numeric not null default 0,
  educational      numeric not null default 0,
  lta              numeric not null default 0,
  professional_tax numeric not null default 208,
  effective_from   date    not null default current_date,
  updated_by       text    default '',
  updated_at       timestamptz not null default now()
);

comment on table salary_structures is
  'Monthly salary components at FULL attendance. Payroll pro-rates these by days worked; it does not recompute them.';

alter table salary_structures enable row level security;
create policy "salary_read"  on salary_structures for select to authenticated
  using (employee_id = current_app_employee_id() or current_app_is_hr_or_mgmt());
create policy "salary_write" on salary_structures for all to authenticated
  using (current_app_is_hr_or_mgmt()) with check (current_app_is_hr_or_mgmt());

-- Every change kept, so a salary revision can be traced to who made it.
create table if not exists salary_structure_history (
  id           uuid primary key default gen_random_uuid(),
  employee_id  text not null,
  changed_at   timestamptz not null default now(),
  changed_by   text default '',
  old_values   jsonb,
  new_values   jsonb
);

alter table salary_structure_history enable row level security;
create policy "salary_hist_read" on salary_structure_history for select to authenticated
  using (current_app_is_hr_or_mgmt());

create or replace function public.log_salary_change()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  insert into salary_structure_history (employee_id, changed_by, old_values, new_values)
  values (coalesce(new.employee_id, old.employee_id),
          coalesce(new.updated_by, ''),
          case when tg_op = 'INSERT' then null else to_jsonb(old) end,
          to_jsonb(new));
  return new;
end;
$fn$;

drop trigger if exists trg_log_salary_change on salary_structures;
create trigger trg_log_salary_change
  after insert or update on salary_structures
  for each row execute function log_salary_change();
