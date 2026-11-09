-- There are no foreign keys on employee_id anywhere, so changing someone's id
-- silently orphans everything keyed to it. It has already happened twice:
-- Princy FD-06 -> FD-05 and SOWNDARYA FD-10 -> FD-03 left 21 days of
-- attendance pointing at ids that no longer exist. Payroll reads by
-- employee_id, so those days were invisible — Princy would have been paid 18
-- days short — and SOWNDARYA's office assignment vanished, which is what put
-- her back on the missing-location list.
--
-- Adding real foreign keys would be the textbook fix, but several of these
-- tables legitimately hold rows for people not in app_users (staff-portal
-- entries, historical records), so a hard constraint would reject writes that
-- are currently valid. A cascade trigger keeps the ids consistent without
-- changing what may be inserted.
create or replace function public.cascade_employee_id_change()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.employee_id is not distinct from old.employee_id then
    return new;
  end if;

  update attendance_records                   set employee_id = new.employee_id where employee_id = old.employee_id;
  update leave_applications                   set employee_id = new.employee_id where employee_id = old.employee_id;
  update payslips                             set employee_id = new.employee_id where employee_id = old.employee_id;
  update payslip_requests                     set employee_id = new.employee_id where employee_id = old.employee_id;
  update appraisal_forms                      set employee_id = new.employee_id where employee_id = old.employee_id;
  update attendance_cycle_remarks             set employee_id = new.employee_id where employee_id = old.employee_id;
  update attendance_policy_employee_overrides set employee_id = new.employee_id where employee_id = old.employee_id;
  update employee_locations                   set employee_id = new.employee_id where employee_id = old.employee_id;
  update on_duty_requests                     set employee_id = new.employee_id where employee_id = old.employee_id;
  update attendance_confirmations             set employee_id = new.employee_id where employee_id = old.employee_id;
  update checkin_attempts                     set employee_id = new.employee_id where employee_id = old.employee_id;

  return new;
end;
$fn$;

drop trigger if exists trg_cascade_employee_id on app_users;
create trigger trg_cascade_employee_id
  after update of employee_id on app_users
  for each row execute function cascade_employee_id_change();

-- Surfaces the problem if it ever recurs by another route.
create or replace view v_orphaned_attendance as
  select a.employee_id, a.employee_name, count(*) as rows,
         min(a.date_iso) as first_day, max(a.date_iso) as last_day
    from attendance_records a
   where not exists (select 1 from app_users u where u.employee_id = a.employee_id)
   group by a.employee_id, a.employee_name;
