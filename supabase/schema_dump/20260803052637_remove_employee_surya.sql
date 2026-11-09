-- Remove Surya (FHIPL-09, accounts@fomrahousing.in) and her operational data.
--
-- Archived before deletion rather than dropped outright: this is irreversible
-- otherwise, and an employee record removed by mistake cannot be reconstructed
-- from anywhere else. The archive is service_role-only.

create table if not exists deleted_employee_archive (
  id            bigserial primary key,
  deleted_at    timestamptz not null default now(),
  employee_id   text,
  employee_name text,
  email         text,
  source_table  text not null,
  row_data      jsonb not null
);

alter table deleted_employee_archive enable row level security;
-- No policies: service_role bypasses RLS, everyone else sees nothing.

comment on table deleted_employee_archive is
  'Rows removed when an employee is deleted. Kept so an accidental deletion is recoverable. service_role access only.';

-- 1. Archive everything first, including the selfie PATH so the orphaned file
--    can still be found and removed via the Storage API afterwards.
insert into deleted_employee_archive (employee_id, employee_name, email, source_table, row_data)
select 'FHIPL-09','Surya','accounts@fomrahousing.in','app_users', to_jsonb(t)
  from app_users t where employee_id='FHIPL-09';

insert into deleted_employee_archive (employee_id, employee_name, email, source_table, row_data)
select 'FHIPL-09','Surya','accounts@fomrahousing.in','attendance_records', to_jsonb(t)
  from attendance_records t where employee_id='FHIPL-09' or employee_name='Surya';

insert into deleted_employee_archive (employee_id, employee_name, email, source_table, row_data)
select 'FHIPL-09','Surya','accounts@fomrahousing.in','employee_locations', to_jsonb(t)
  from employee_locations t where employee_id='FHIPL-09';

insert into deleted_employee_archive (employee_id, employee_name, email, source_table, row_data)
select 'FHIPL-09','Surya','accounts@fomrahousing.in','notifications', to_jsonb(t)
  from notifications t where target_email='accounts@fomrahousing.in';

insert into deleted_employee_archive (employee_id, employee_name, email, source_table, row_data)
select 'FHIPL-09','Surya','accounts@fomrahousing.in','email_logs', to_jsonb(t)
  from email_logs t where recipient='accounts@fomrahousing.in';

-- 2. Delete operational data.
--
--    The attendance selfie in the 'attendance-selfies' bucket CANNOT be removed
--    from here: Supabase blocks direct deletes on storage tables
--    ("Direct deletion from storage tables is not allowed. Use the Storage API
--    instead."). The file is
--      attendance-selfies/FHIPL-08/01-08-2026_checkin_1785573642217.jpg
--    filed under her ORIGINAL employee id, before the renumbering. It must be
--    deleted through the Storage API or the dashboard. It is a facial
--    photograph, so leaving it orphaned is not acceptable — the path is
--    preserved in the archive above so it can still be located.
delete from employee_locations                   where employee_id='FHIPL-09';
delete from attendance_policy_employee_overrides where employee_id='FHIPL-09';
delete from attendance_records                   where employee_id='FHIPL-09' or employee_name='Surya';
delete from leave_applications                   where employee_id='FHIPL-09' or employee_name='Surya';
delete from payslips                             where employee_id='FHIPL-09';
delete from payslip_requests                     where employee_id='FHIPL-09';
delete from kra_documents                        where employee_email='accounts@fomrahousing.in';
delete from appraisal_forms                      where employee_email='accounts@fomrahousing.in';
delete from notifications                        where target_email='accounts@fomrahousing.in';
delete from email_logs                           where recipient='accounts@fomrahousing.in';

-- 3. The employee record itself.
alter table app_users disable trigger trg_protect_app_users;
delete from app_users where employee_id='FHIPL-09';
alter table app_users enable trigger trg_protect_app_users;

-- audit_log is deliberately NOT deleted. It is the record of what was done and
-- by whom — including this account's creation, activation and removal — so
-- deleting it would erase the evidence that any of it happened, which is the
-- opposite of what an audit log is for. A formal erasure request would require
-- clearing it too; say so if that is what this is.
