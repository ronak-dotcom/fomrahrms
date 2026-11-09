-- SIJO C JOSEPH (Sales) — weekly off is Tuesday, set by the reporting manager
-- and HR. This is the initial set, which HR makes directly; any later change
-- goes through the pending/approval path and needs Management sign-off.
--
-- Storing 'Tuesday' explicitly rather than leaving '' matters: '' is the
-- sentinel for Sunday, and Sales works Sundays, so an empty value would mark
-- his working day as an off day and Tuesday as a working day — the exact
-- inverse of reality.
alter table app_users disable trigger trg_protect_app_users;

update app_users
   set weekly_off_day = 'Tuesday'
 where employee_id = 'FHIPL-03' and department = 'Sales';

alter table app_users enable trigger trg_protect_app_users;
