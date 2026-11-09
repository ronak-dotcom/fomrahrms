-- Mobile is now a valid login identifier for staff without email (see
-- login edge function). Two employees sharing a mobile number would make
-- login ambiguous, so enforce uniqueness among non-blank values.
create unique index if not exists app_users_mobile_login_uidx
  on app_users (mobile)
  where mobile <> '';
