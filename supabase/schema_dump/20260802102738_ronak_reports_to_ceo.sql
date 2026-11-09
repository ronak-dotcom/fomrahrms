-- Ronak (Head of Operations) had no reporting manager, so his own leave
-- requests would have had no approver — app_manages() joins on
-- reporting_manager, and an empty value matches nobody. The CEO approves them.
--
-- Approving someone else's leave is oversight, so this does not conflict with
-- the CEO being oversight_only: that only blocks his OWN self-service pages,
-- not the approval queues.
alter table app_users disable trigger trg_protect_app_users;

update app_users
   set reporting_manager = 'Sharad Fomra'
 where employee_id = 'FHIPL-10';

alter table app_users enable trigger trg_protect_app_users;
