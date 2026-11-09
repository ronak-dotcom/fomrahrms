-- The selfie is mandatory and blocks check-in outright, with no fallback if
-- the device cannot produce one. An employee whose browser refuses to open
-- the camera has therefore been unable to record attendance at all since
-- 27/08: her attempt log shows "The camera did not open" repeatedly, and
-- before the recent timeout fix it simply froze the button with no error.
--
-- A hard requirement with no alternative path is a single point of failure
-- for someone's pay. This lets HR or Management lift it per employee when a
-- device genuinely cannot comply, so the person can work while the device
-- problem is sorted out separately. It is recorded on the attendance row
-- (selfie_exempt) so a missing photo is explained rather than suspicious.
alter table app_users
  add column if not exists exempt_from_selfie boolean not null default false;
alter table app_users
  add column if not exists selfie_exempt_reason text default '';

comment on column app_users.exempt_from_selfie is
  'Set by HR/Management when a device cannot capture a selfie (camera blocked or unsupported). Check-in proceeds without one; GPS and timing rules still apply.';
