-- The founder is not an employee. No joining date, no attendance, no payroll,
-- no leave entitlement — and counting him makes every percentage wrong: "5 of
-- 6 present" against a denominator containing someone who can never check in.
--
-- oversight_only already marks him. This makes every reporting view agree with
-- the app, so a query run directly against the database gives the same answer
-- as the screen.
--
-- Deliberately NOT hidden from approver lookups: he approves the Head of
-- Operations' leave, and app_manages()/the manager picker must still find him.
-- This governs counting and reporting only.

create or replace view public.v_employees as
  select * from app_users
   where active and not coalesce(oversight_only, false);

comment on view public.v_employees is
  'Employees for counting and reporting. Excludes the founder (oversight_only), who is not an employee. Approver lookups must use app_users directly — he still approves leave.';

create or replace view public.v_attendance_tracked_employees as
  select employee_id, name, email, department, designation, role
    from app_users
   where active
     and not coalesce(exempt_from_attendance, false)
     and not coalesce(oversight_only, false);

create or replace view public.v_payroll_eligible_employees as
  select employee_id, name, email, department, designation, gross_pay,
         date_of_joining, onroll_confirmed_at
    from app_users
   where active
     and coalesce(payroll_eligible, true)
     and not coalesce(oversight_only, false);

-- His joining date being blank is correct, not missing data. Record that so it
-- stops being reported as a gap.
comment on column app_users.oversight_only is
  'Founder / oversight role. Full administrative rights, but NOT an employee: no joining date, attendance, payroll or leave entitlement, and excluded from every headcount and report. Still selectable as an approver.';
