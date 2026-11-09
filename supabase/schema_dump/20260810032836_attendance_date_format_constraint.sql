-- attendance_records.date is text in dd/MM/yyyy. A full conversion to a date
-- column is NOT needed and would be the riskier change:
--
--   * date_iso is a STORED GENERATED column derived from it, so the two cannot
--     drift apart — the sorting bug that motivated it is already solved.
--   * All three queries against `date` are exact matches
--     (fetchAttendanceForDate, fetchAttendanceForDates, fetchCheckedInAttendance).
--     Nothing sorts or ranges on the text column, so there is no lexical-order
--     bug left to fix.
--   * Converting the column would break every one of those exact matches and
--     the id format (_attendanceId uses the slash date), for no gain.
--
-- What IS still missing is a guarantee that only a valid dd/MM/yyyy string can
-- be written. Without it a malformed value would silently produce a NULL
-- date_iso and vanish from every date-based view.
alter table attendance_records drop constraint if exists attendance_date_format;
alter table attendance_records add constraint attendance_date_format
  check (date ~ '^\d{2}/\d{2}/\d{4}$');

-- And that the generated column actually resolved. slash_date_to_date()
-- returns NULL for an unparseable value; a row whose date_iso is NULL is
-- invisible to every range query and every report.
alter table attendance_records drop constraint if exists attendance_date_iso_resolves;
alter table attendance_records add constraint attendance_date_iso_resolves
  check (date_iso is not null);

comment on column attendance_records.date is
  'Working date as dd/MM/yyyy. Kept as text because the app matches on it exactly and the record id is derived from it. Sorting and ranges must use date_iso, which is generated from this and cannot drift.';
