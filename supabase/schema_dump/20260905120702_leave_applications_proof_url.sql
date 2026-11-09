-- The app writes proof_url (a medical certificate or similar attached to a
-- leave request) but the column was never created, so every submission
-- logged a PGRST204 schema-cache error. It was caught and only printed, so
-- nobody saw it — the error on Devaraj's lost request was exactly this.
--
-- Adding the column rather than removing the write: attaching proof to a
-- medical leave is a real requirement, and silently discarding an uploaded
-- certificate would be worse than the error.
alter table leave_applications add column if not exists proof_url text default '';

comment on column leave_applications.proof_url is
  'Supporting document for the request, e.g. a medical certificate.';
