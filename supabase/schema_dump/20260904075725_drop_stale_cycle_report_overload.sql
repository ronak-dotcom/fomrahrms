-- An older single-argument attendance_cycle_report(date) survived when the
-- two-argument version was recreated to add vouched_days. Postgres treats
-- them as overloads, so a call with one argument silently reached the stale
-- one - no vouched_days column, and none of the later fixes. Worse, any
-- ambiguous call now errors outright. The two-argument form defaults
-- p_employee_ids to null, so it already covers the one-argument case.
drop function if exists public.attendance_cycle_report(date);
