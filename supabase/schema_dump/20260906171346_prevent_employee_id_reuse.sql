-- FD-05 was Devaraj's, then Princy's. FD-06 was Princy's, then offered to
-- SOWNDARYA. FD-10 was SOWNDARYA's, now FD-03. Each reassignment left records
-- behind for the next holder to inherit, and the cycle report silently
-- credited one person with another's days.
--
-- The cascade trigger stops records being orphaned. This stops the id being
-- handed to someone else in the first place, which is the actual source.
create table if not exists retired_employee_ids (
  employee_id  text primary key,
  previous_name text not null default '',
  retired_at   timestamptz not null default now(),
  note         text default ''
);

comment on table retired_employee_ids is
  'Employee ids that have belonged to someone. Never reissued: historical records key on employee_id, so reuse makes one person inherit another''s attendance and pay.';

-- Seeds from ids already known to have changed hands.
insert into retired_employee_ids (employee_id, previous_name, note)
values
  ('FD-05','Devaraj','Reassigned to P. Prarthana Princy; his records were left behind'),
  ('FD-06','P. Prarthana Princy','Was offered to SOWNDARYA during onboarding'),
  ('FD-10','SOWNDARYA','Changed to FD-03; attendance and location were orphaned')
on conflict (employee_id) do nothing;

-- Records the outgoing id whenever someone's changes, so the history builds
-- itself rather than depending on anyone remembering.
create or replace function public.retire_previous_employee_id()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.employee_id is distinct from old.employee_id
     and coalesce(old.employee_id,'') <> '' then
    insert into retired_employee_ids (employee_id, previous_name, note)
    values (old.employee_id, old.name,
            'Changed to ' || new.employee_id)
    on conflict (employee_id) do nothing;
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_retire_previous_employee_id on app_users;
create trigger trg_retire_previous_employee_id
  after update of employee_id on app_users
  for each row execute function retire_previous_employee_id();

-- next_employee_id() must skip retired ids as well as live and reserved ones,
-- or it would suggest exactly the numbers that caused this.
create or replace function public.next_employee_id(p_prefix text default 'FHIPL')
returns text language sql stable as $fn$
  with taken as (
    select employee_id as id from app_users
    union all
    select assigned_emp_id from onboarding_forms
     where coalesce(assigned_emp_id,'') <> ''
       and status not in ('mgmt_denied','hr_denied')
    union all
    select employee_id from retired_employee_ids
  )
  select upper(btrim(p_prefix)) || '-' ||
         lpad((coalesce(max(
           nullif(regexp_replace(split_part(id, '-', 2), '\D', '', 'g'), '')::int
         ), 0) + 1)::text, 2, '0')
    from taken
   where upper(split_part(id, '-', 1)) = upper(btrim(p_prefix));
$fn$;
