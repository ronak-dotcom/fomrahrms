-- Employee ids have been reassigned between people: FD-05 was Devaraj's, then
-- became Princy's while his records stayed behind, so for a while FD-05 held
-- both. Her cycle report counted his days and his showed zero — and neither
-- number looked obviously wrong on its own, which is why it went unnoticed.
--
-- The cascade trigger prevents the orphaning that caused it. This catches the
-- result directly: any attendance row whose employee_id disagrees with the id
-- that name currently holds. Should always be empty.
create or replace view v_attendance_identity_mismatch as
  select a.employee_id as row_employee_id,
         a.employee_name,
         u.employee_id as expected_employee_id,
         count(*) as rows,
         min(a.date_iso) as first_day,
         max(a.date_iso) as last_day
    from attendance_records a
    join app_users u on lower(trim(u.name)) = lower(trim(a.employee_name))
   where a.employee_id <> u.employee_id
   group by 1,2,3;

comment on view v_attendance_identity_mismatch is
  'Attendance rows filed under an employee id that no longer belongs to that person. Non-empty means someone is being credited with another person''s days.';
