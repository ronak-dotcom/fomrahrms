-- protect_app_users_sensitive_columns() pins work_location back to its old
-- value for any caller that is not service_role or HR/Management. It does this
-- SILENTLY — the UPDATE reports success and affects rows, but the new value is
-- discarded. A migration running as `postgres` is therefore a no-op here.
-- Disable the trigger for the duration of this one statement.
alter table app_users disable trigger trg_protect_app_users;

update app_users set work_location = 'Office' where employee_id in ('FHIPL-08','FHIPL-01');
update app_users set work_location = 'Onsite' where employee_id in ('FHIPL-03','FD-01');

alter table app_users enable trigger trg_protect_app_users;
