-- GPS is null on 100% of attendance records, still, after three attempts to
-- fix it: skipping the unreliable web service-check, adding diagnostics, and
-- reordering the request ahead of the store loads. Each was a plausible
-- hypothesis and none was verifiable, because the failure reason lives in
-- GpsTrackingService.lastLocationError and is never persisted — it exists
-- only in the browser of whoever checked in.
--
-- Rather than guess a fourth time, record the reason. One check-in then says
-- exactly which of these it is:
--   services disabled / permission denied / permission blocked / timeout /
--   an exception, with its message
alter table attendance_records
  add column if not exists check_in_gps_error  text default '',
  add column if not exists check_out_gps_error text default '';

comment on column attendance_records.check_in_gps_error is
  'Why the location fix failed at check-in, empty when it succeeded. Diagnostic only — never shown to the employee.';
