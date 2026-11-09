-- Management is the final authority but not a required step: the day becomes
-- attendance once the manager confirms and HR approves. Management sees what
-- was decided and can overturn it if something breached policy — an override,
-- not another queue. Making them a mandatory third signature would stall
-- every routine case waiting on someone who usually has nothing to add.
alter table attendance_confirmations
  add column if not exists mgmt_status text not null default 'none';
  -- none | overturned
alter table attendance_confirmations
  add column if not exists mgmt_by text default '';
alter table attendance_confirmations
  add column if not exists mgmt_at timestamptz;
alter table attendance_confirmations
  add column if not exists mgmt_note text default '';

comment on column attendance_confirmations.mgmt_status is
  'none = Management has not intervened (the normal case). overturned = Management reversed an approved confirmation on policy grounds.';

-- Removes the attendance the two approvals created. Written as a trigger so
-- the record and the decision cannot drift apart if the client dies midway.
create or replace function public.apply_attendance_confirmation_override()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.mgmt_status <> 'overturned'
     or coalesce(old.mgmt_status,'none') = 'overturned' then
    return new;
  end if;

  -- Only removes rows this flow created. A day the employee later checked
  -- into normally is real attendance and must survive an override of the
  -- vouching that preceded it.
  delete from attendance_records
   where employee_id = new.employee_id
     and date_iso = new.date_iso
     and verification = 'vouched';

  return new;
end;
$fn$;

drop trigger if exists trg_attendance_confirmation_override on attendance_confirmations;
create trigger trg_attendance_confirmation_override
  after update of mgmt_status on attendance_confirmations
  for each row execute function apply_attendance_confirmation_override();
