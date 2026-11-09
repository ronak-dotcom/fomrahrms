-- URGENT REVERT.
--
-- Setting role = 'CEO' in the database broke Sharad's access in the LIVE app.
-- The deployed build's userRoleFor() has no 'ceo' case and falls through to
--   default: return UserRole.employee;
-- so the CEO has been logged in as an ordinary EMPLOYEE — no Administration,
-- no Employee Management, no Add Employee, and the employee shell's own
-- My Attendance / My Leave pages instead.
--
-- My error: I changed the database ahead of the code that understands it,
-- which is exactly the ordering mistake I had flagged as dangerous earlier.
--
-- The 'CEO' role string is not needed for behaviour anyway. Every CEO-specific
-- rule now hangs off explicit columns — oversight_only, exempt_from_attendance,
-- exempt_from_timing, exempt_from_geofence, exempt_from_leave_rules,
-- payroll_eligible — and those work regardless of the role string. Role carries
-- AUTHORITY; the flags carry APPLICABILITY. So restore the authority string the
-- deployed app understands and let the designation say "CEO".
--
-- 'CEO' can be reinstated as a role string once the build containing the
-- userRoleFor 'ceo' case is deployed, but there is no functional need.
alter table app_users disable trigger trg_protect_app_users;

update app_users
   set role        = 'Management',
       designation = 'Chief Executive Officer'
 where oversight_only
   and role = 'CEO';

alter table app_users enable trigger trg_protect_app_users;
