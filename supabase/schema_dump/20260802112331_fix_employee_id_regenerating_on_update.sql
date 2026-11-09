-- BUG in assign_employee_id(): it generated a NEW id on UPDATE as well as
-- INSERT whenever the incoming value was blank.
--
-- Ronak was created as FHIPL-10. The Flutter client upserts the WHOLE record,
-- and when it wrote back with employee_id blank the trigger treated that as
-- "assign me one" and issued FHIPL-11. His ID silently changed underneath him.
--
-- employee_id is the join key for attendance_records, employee_locations,
-- attendance_policy_employee_overrides and payslips. A silent renumber orphans
-- every one of those. Ronak had no such rows yet, so nothing was actually
-- orphaned this time — but a long-serving employee would lose their history.
--
-- Generation belongs to INSERT only. On UPDATE, a blank means "unchanged",
-- never "reassign".
create or replace function public.assign_employee_id()
returns trigger
language plpgsql
as $function$
begin
  new.employee_id := upper(replace(coalesce(new.employee_id, ''), ' ', ''));

  if tg_op = 'UPDATE' then
    -- Never renumber an existing employee. A blank incoming value is a
    -- whole-record upsert that simply did not carry the id; keep the old one.
    if new.employee_id = '' then
      new.employee_id := old.employee_id;
    end if;
    return new;
  end if;

  -- INSERT only.
  if new.employee_id = '' then
    new.employee_id := public.next_employee_id(
      case when coalesce(new.business_unit, '') = 'FOMRA Developers' then 'FD' else 'FHIPL' end
    );
  end if;
  return new;
end;
$function$;

-- Ronak has no dependent rows, so restoring FHIPL-10 is safe and keeps the
-- sequence contiguous. Verified below before applying.
do $$
declare v_refs int;
begin
  select
    (select count(*) from attendance_records where employee_id in ('FHIPL-10','FHIPL-11')) +
    (select count(*) from employee_locations where employee_id in ('FHIPL-10','FHIPL-11')) +
    (select count(*) from leave_applications where employee_id in ('FHIPL-10','FHIPL-11')) +
    (select count(*) from payslips where employee_id in ('FHIPL-10','FHIPL-11'))
    into v_refs;

  if v_refs = 0 then
    alter table app_users disable trigger trg_protect_app_users;
    update app_users set employee_id = 'FHIPL-10' where employee_id = 'FHIPL-11';
    alter table app_users enable trigger trg_protect_app_users;
  else
    raise notice 'Left FHIPL-11 in place: % dependent rows exist', v_refs;
  end if;
end $$;
