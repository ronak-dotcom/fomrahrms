-- The cascade moved employee_id but left the attendance record's primary key,
-- which embeds the old employee id. Check-out computes that key from the
-- CURRENT employee id, so after any id change the update targeted a row that
-- did not exist and silently did nothing — the employee pressed Check Out and
-- nothing happened, with no error to explain it.
--
-- It also created split days: a check-in under the old key and a check-out
-- under the new one, which is how one employee ended up with two rows for the
-- same date.
create or replace function public.cascade_employee_id_change()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.employee_id is not distinct from old.employee_id then
    return new;
  end if;

  -- Key first, in two phases. A single pass can collide where ids have been
  -- passed between people: one person's new key may be another's current one.
  update attendance_records
     set id = 'TMP__' || id
   where employee_id = old.employee_id;

  update attendance_records
     set employee_id = new.employee_id,
         id = new.employee_id || '_' || to_char(date_iso, 'DD-MM-YYYY')
   where id like 'TMP__%' and employee_id = old.employee_id;

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
  update salary_structures                    set employee_id = new.employee_id where employee_id = old.employee_id;
  update leave_adjustments                    set employee_id = new.employee_id where employee_id = old.employee_id;
  update late_lop_decisions                   set employee_id = new.employee_id where employee_id = old.employee_id;

  return new;
end;
$fn$;

-- Surfaces the fault directly if it ever recurs by another route.
create or replace view v_attendance_id_mismatch as
  select id, employee_id, employee_name, date_iso,
         employee_id || '_' || to_char(date_iso,'DD-MM-YYYY') as expected_id
    from attendance_records
   where id <> employee_id || '_' || to_char(date_iso,'DD-MM-YYYY');

comment on view v_attendance_id_mismatch is
  'Attendance rows whose primary key names a different employee id than the row belongs to. Check-out silently fails for these. Should always be empty.';
