-- Sales and Projects sometimes work outside normal hours for business
-- reasons (BTL activity, site/project work). Those days are PRESENCE, not
-- absence, so this is a flag on the attendance record rather than a leave
-- type — booking it as leave would deduct balance and mark them absent,
-- which is the opposite of what happened.
--
-- Deliberately no hours/overtime accounting: the day is simply marked as
-- on duty, and late-arrival and early-checkout rules do not apply to it.
alter table attendance_records
  add column if not exists on_duty boolean not null default false;
alter table attendance_records
  add column if not exists on_duty_reason text default '';
alter table attendance_records
  add column if not exists on_duty_set_by text default '';

comment on column attendance_records.on_duty is
  'Day worked outside normal hours for business purposes. Exempt from late/early timing rules; shown in its own colour on attendance views. Does not accrue overtime or comp off.';

create index if not exists attendance_records_on_duty_idx
  on attendance_records (on_duty) where on_duty;
