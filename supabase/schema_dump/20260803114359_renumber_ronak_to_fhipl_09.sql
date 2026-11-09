-- Reuse FHIPL-09, freed when Surya was removed, for Ronak (was FHIPL-10) so
-- the sequence stays contiguous.
--
-- employee_id is the join key for attendance_records, employee_locations,
-- attendance_policy_employee_overrides, leave_applications, payslips and
-- payslip_requests. All are updated in the SAME transaction — a renumber that
-- misses one orphans that history silently, which is exactly what the
-- auto-assign bug did to this record earlier.
alter table app_users disable trigger trg_protect_app_users;

update attendance_records                   set employee_id='FHIPL-09' where employee_id='FHIPL-10';
update employee_locations                   set employee_id='FHIPL-09' where employee_id='FHIPL-10';
update attendance_policy_employee_overrides set employee_id='FHIPL-09' where employee_id='FHIPL-10';
update leave_applications                   set employee_id='FHIPL-09' where employee_id='FHIPL-10';
update payslips                             set employee_id='FHIPL-09' where employee_id='FHIPL-10';
update payslip_requests                     set employee_id='FHIPL-09' where employee_id='FHIPL-10';
update app_users                            set employee_id='FHIPL-09' where employee_id='FHIPL-10';

alter table app_users enable trigger trg_protect_app_users;

-- Note: his attendance selfies remain stored under 'FHIPL-10/...' paths in the
-- attendance-selfies bucket. attendance_records holds the full path, so they
-- still resolve correctly; renaming storage objects needs the Storage API and
-- is cosmetic only.
