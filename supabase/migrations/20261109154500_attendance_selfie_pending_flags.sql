-- A selfie whose photo was taken but whose upload died on the way out used
-- to fail the whole check-in. The employee was sent to the vouching flow,
-- which needs a manager and HR to approve — a heavy price for a few seconds
-- of bad wifi, and it is what the remaining "Failed to fetch" / "Load
-- failed" entries in checkin_attempts actually are. The three upload retries
-- already in place cover about seven seconds; these outages ran longer.
--
-- The check-in may now proceed with the selfie marked pending, so attendance
-- is recorded and the photo is still owed rather than silently waived. HR
-- can see which rows are missing one.
alter table public.attendance_records
  add column if not exists check_in_selfie_pending  boolean not null default false,
  add column if not exists check_out_selfie_pending boolean not null default false;

comment on column public.attendance_records.check_in_selfie_pending is
  'Photo was captured but could not be uploaded. The check-in stands; the '
  'selfie is still owed. Cleared when a later upload attempt succeeds.';
comment on column public.attendance_records.check_out_selfie_pending is
  'As check_in_selfie_pending, for the check-out photo.';

-- So HR can find them without scanning the table.
create or replace view public.v_attendance_selfie_pending as
  select a.employee_id,
         u.name as employee_name,
         a.date_iso,
         a.check_in_selfie_pending,
         a.check_out_selfie_pending
    from attendance_records a
    left join app_users u on u.employee_id = a.employee_id
   where a.check_in_selfie_pending or a.check_out_selfie_pending
   order by a.date_iso desc, u.name;
