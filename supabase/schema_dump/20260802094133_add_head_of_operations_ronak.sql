-- Ronak — Head of Operations. Management authority, so he approves at the
-- final stage alongside the CEO. Unlike the CEO, leave and salary DO apply to
-- him; only fixed timing and geofencing do not.
--
-- Management has no department, so department is left blank deliberately —
-- the timing exemption means it is never used to resolve office hours.
--
-- Joined 07/04/2007, so long past probation: onroll_confirmed_at is set to the
-- joining date and EL accrues from then (start_el_on_confirmation only fires
-- on UPDATE, so it is set explicitly here).
--
-- employee_id is left blank so assign_employee_id() generates the next one.
-- active is false: he sets his own password through the activation email,
-- which HR sends from Administration -> Resend Activation Email.

insert into app_users (
  name, email, company_email, role, designation, department,
  date_of_joining, onroll_confirmed_at, el_eligible_at,
  employee_id, active, password_hash,
  exempt_from_timing, exempt_from_geofence,
  exempt_from_leave_rules, exempt_from_attendance, payroll_eligible,
  leave_allocation, permission_minutes_quota, weekly_off_day,
  business_unit, reporting_manager, is_reporting_manager
)
values (
  'Ronak', 'ronak@fomrahousing.in', 'ronak@fomrahousing.in',
  'Management', 'Head of Operations', '',
  '2007-04-07', '2007-04-07', '2007-04-07',
  '', false, null,
  true,  true,     -- exempt: fixed timing, geofence
  false, false, true,  -- leave rules, attendance and payroll all APPLY
  21, 120, '',
  'FOMRA Housing', '', true
);

-- Jose reported to "ronak", who did not exist, so his approvals had no owner.
-- Now that the record exists the reference resolves; align the spelling so
-- app_manages() matches (it joins on name).
alter table app_users disable trigger trg_protect_app_users;
update app_users set reporting_manager = 'Ronak'
 where lower(btrim(reporting_manager)) = 'ronak';
alter table app_users enable trigger trg_protect_app_users;
