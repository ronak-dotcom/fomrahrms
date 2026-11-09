-- Some devices refuse a direct camera launch, so the app falls back to the
-- photo picker rather than waiving the selfie. That keeps the control, but
-- a picker selection could be an existing photo while the watermark looks
-- identical either way - so the source is recorded and shown to HR instead
-- of the difference being invisible.
alter table attendance_records
  add column if not exists check_in_selfie_from_picker boolean not null default false;
alter table attendance_records
  add column if not exists check_out_selfie_from_picker boolean not null default false;

comment on column attendance_records.check_in_selfie_from_picker is
  'True when the selfie came from the photo picker because the device would not open the camera directly. Watermarked identically, so this flag is the only way to tell.';
