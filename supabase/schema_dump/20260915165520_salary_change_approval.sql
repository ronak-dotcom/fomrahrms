-- Salary changes now need Management approval, and nothing is constant:
-- components are whatever the employee's package actually contains.
--
-- Arbitrary components, as amounts. Positive is an earning, negative a
-- deduction, so one mechanism covers "add a site allowance" and "recover an
-- advance" without a second concept. Stored as jsonb because the set differs
-- per person and adding a column per allowance would mean a migration every
-- time someone negotiates a new one.
alter table salary_structures
  add column if not exists custom_components jsonb not null default '[]'::jsonb;

comment on column salary_structures.custom_components is
  'Extra components as [{"label":"Site Allowance","amount":2500}]. Negative amounts are deductions. Fixed columns cover the standard set; this covers everything else.';

-- HR proposes, Management decides. HR used to write straight to
-- salary_structures, so a salary could change with no second signature —
-- and payroll reads it directly, so the first anyone knew was the payslip.
create table if not exists salary_change_requests (
  id            uuid primary key default gen_random_uuid(),
  employee_id   text not null,
  proposed      jsonb not null,      -- the full structure being requested
  current_value jsonb,               -- what it is now, for the diff
  reason        text default '',
  requested_by  text not null default '',
  requested_at  timestamptz not null default now(),
  status        text not null default 'pending',   -- pending | approved | rejected
  decided_by    text default '',
  decided_at    timestamptz,
  decision_note text default ''
);

create index if not exists salary_change_pending_idx
  on salary_change_requests (status) where status = 'pending';

alter table salary_change_requests enable row level security;
create policy "salary_change_read" on salary_change_requests
  for select to authenticated
  using (employee_id = current_app_employee_id() or current_app_is_hr_or_mgmt());
-- HR may raise one; only Management may decide it. Enforced here so it does
-- not rely on a button being hidden.
create policy "salary_change_insert" on salary_change_requests
  for insert to authenticated with check (current_app_is_hr_or_mgmt());
create policy "salary_change_decide" on salary_change_requests
  for update to authenticated
  using (coalesce(current_app_role(),'') in ('Management','CEO'))
  with check (coalesce(current_app_role(),'') in ('Management','CEO'));

-- Applies an approved change to the live structure, so approval and effect
-- cannot drift apart.
create or replace function public.apply_salary_change()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.status <> 'approved' or coalesce(old.status,'') = 'approved' then
    return new;
  end if;

  insert into salary_structures (
    employee_id, actual_gross, basic, da, hra, conveyance, other_allowance,
    educational, lta, professional_tax, epf, esi, tds, custom_components,
    updated_by, updated_at
  )
  select new.employee_id,
         (new.proposed->>'actual_gross')::numeric,
         (new.proposed->>'basic')::numeric,
         (new.proposed->>'da')::numeric,
         (new.proposed->>'hra')::numeric,
         (new.proposed->>'conveyance')::numeric,
         (new.proposed->>'other_allowance')::numeric,
         (new.proposed->>'educational')::numeric,
         (new.proposed->>'lta')::numeric,
         (new.proposed->>'professional_tax')::numeric,
         nullif(new.proposed->>'epf','')::numeric,
         nullif(new.proposed->>'esi','')::numeric,
         nullif(new.proposed->>'tds','')::numeric,
         coalesce(new.proposed->'custom_components', '[]'::jsonb),
         -- Records who APPROVED it, not who typed it: that is the signature
         -- that carries authority.
         coalesce(nullif(new.decided_by,''), 'Management'),
         now()
  on conflict (employee_id) do update set
    actual_gross=excluded.actual_gross, basic=excluded.basic, da=excluded.da,
    hra=excluded.hra, conveyance=excluded.conveyance,
    other_allowance=excluded.other_allowance, educational=excluded.educational,
    lta=excluded.lta, professional_tax=excluded.professional_tax,
    epf=excluded.epf, esi=excluded.esi, tds=excluded.tds,
    custom_components=excluded.custom_components,
    updated_by=excluded.updated_by, updated_at=now();

  return new;
end;
$fn$;

drop trigger if exists trg_apply_salary_change on salary_change_requests;
create trigger trg_apply_salary_change
  after update of status on salary_change_requests
  for each row execute function apply_salary_change();
