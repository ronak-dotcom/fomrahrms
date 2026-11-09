-- FD-05 is both retired (it was Devaraj's) and live (Princy holds it now).
-- That is a true record of a reuse that already happened, not something to
-- delete — but it must not stop the current holder being recognised, and it
-- should be visible as the anomaly it is.
--
-- Also removes an id from the retired list when someone is given it, so a
-- rename that returns to a previous id does not leave that id marked dead
-- while its owner is using it — which my own rename test produced.
create or replace function public.retire_previous_employee_id()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.employee_id is distinct from old.employee_id
     and coalesce(old.employee_id,'') <> '' then
    insert into retired_employee_ids (employee_id, previous_name, note)
    values (old.employee_id, old.name, 'Changed to ' || new.employee_id)
    on conflict (employee_id) do nothing;
  end if;

  -- The incoming id is in use again, so it is not retired.
  delete from retired_employee_ids where employee_id = new.employee_id;
  return new;
end;
$fn$;

-- Reuses that have already happened, for HR to see rather than discover
-- through a wrong pay figure.
create or replace view v_reused_employee_ids as
  select r.employee_id, r.previous_name as was, u.name as now_held_by,
         r.retired_at, r.note
    from retired_employee_ids r
    join app_users u on u.employee_id = r.employee_id;

comment on view v_reused_employee_ids is
  'Ids that belonged to one person and are now held by another. Their historical records key on employee_id, so check both people''s attendance and pay before trusting either.';
