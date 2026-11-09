-- Mark all employees eligible for earned leave. Only Jose was previously.
--
-- Eligibility date = date of joining, so accrual runs from when they actually
-- started rather than from today — otherwise everyone's clock would restart
-- now and existing service would be lost. Sharad has no date_of_joining on
-- record, so he is given today's date rather than being silently skipped;
-- correct it if his real joining date is known.
--
-- elAccruedFor() counts WHOLE months from this date, so nobody accrues
-- anything until their first monthly anniversary passes.
alter table app_users disable trigger trg_protect_app_users;

update app_users
   set el_eligible_at = case
         when coalesce(date_of_joining,'') <> '' then date_of_joining
         else to_char(now(), 'YYYY-MM-DD')
       end
 where coalesce(el_eligible_at,'') = '';

alter table app_users enable trigger trg_protect_app_users;
