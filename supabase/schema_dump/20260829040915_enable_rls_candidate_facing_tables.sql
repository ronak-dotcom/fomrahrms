-- candidate_applications and onboarding_forms are read/written by
-- candidates BEFORE they have any account or login — the onboarding link
-- (/onboarding-form/{token}) is a plain URL a candidate opens with no
-- Supabase Auth session at all, so requests hit these tables as the anon
-- role, not authenticated.
--
-- Security for that flow is a capability URL (the token itself, e.g.
-- candidate_applications.onboarding_token), not row-level identity — there
-- is no auth.uid() to check against for someone who has never logged in.
-- Enabling RLS here with an authenticated-only policy (like the 5 tables
-- above) would break candidate submissions outright.
--
-- This pass enables RLS on both (previously fully off) and makes the
-- existing open-to-anon behaviour an explicit, named policy instead of an
-- absence of one, so it shows up as a deliberate choice rather than a gap.
-- Properly restricting the anon surface (e.g. a SECURITY DEFINER RPC that
-- validates the token server-side instead of direct table access) would
-- close this further but changes how the candidate-facing form talks to
-- the database and needs its own careful pass — flagging as a follow-up
-- rather than attempting it as part of this migration.

alter table candidate_applications enable row level security;
alter table onboarding_forms enable row level security;

create policy "app_access" on candidate_applications
  for all to anon, authenticated using (true) with check (true);
create policy "app_access" on onboarding_forms
  for all to anon, authenticated using (true) with check (true);
