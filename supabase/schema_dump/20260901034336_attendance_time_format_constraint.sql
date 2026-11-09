-- The punctuality and payroll reports parse these columns by character
-- position (substring(check_in_time from 1 for 2)::int) to compute minutes
-- late. A value like '12 pm' or '6.45' either throws or yields a nonsense
-- lateness figure that then feeds a pay decision — and two such rows had
-- already reached production via an editable time field on the check-in
-- screen.
--
-- Enforced in the database rather than only in the app so that no client,
-- current or future, can write a value the reports cannot parse. Empty
-- string stays valid: it is how "not checked out yet" is represented.
alter table attendance_records
  add constraint attendance_check_in_time_format
  check (check_in_time IS NULL OR check_in_time = ''
         OR check_in_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');

alter table attendance_records
  add constraint attendance_check_out_time_format
  check (check_out_time IS NULL OR check_out_time = ''
         OR check_out_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$');
