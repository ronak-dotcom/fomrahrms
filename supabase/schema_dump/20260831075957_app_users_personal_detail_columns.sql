-- The Add Employee page collects blood group, bank and emergency-contact
-- details and wrote them to an `employees` table that does not exist, so
-- every submission 404'd, was swallowed by the error handler, and the page
-- still reported "Employee added successfully" — the record only ever
-- existed in memory and vanished on refresh.
--
-- Rather than create that table (which would leave employee identity split
-- across two tables that could disagree), these columns move onto
-- app_users, which is what the rest of the app already treats as the
-- single source of truth for people.
alter table app_users add column if not exists blood_group text default '';
alter table app_users add column if not exists bank_account text default '';
alter table app_users add column if not exists ifsc text default '';
alter table app_users add column if not exists emergency_name text default '';
alter table app_users add column if not exists emergency_phone text default '';
