-- These 5 tables were reachable by anyone holding the public anon key, with
-- no login required at all — a plain HTTP request to the Supabase REST
-- endpoint could read/write them. None of them are touched by the
-- unauthenticated candidate-facing onboarding pages (checked against the
-- app source), so requiring a logged-in session closes that gap without
-- changing behaviour for the app itself, where every screen that reads
-- these already runs after login.
--
-- This is a first pass: "must be logged in" rather than fully row-scoped
-- per user, because notifications/notification_preferences in particular
-- have complex targeting (by role, by reporting manager, or by specific
-- email) that the client filters after fetching — replicating that exactly
-- in a row policy risks silently hiding notifications for some role. That
-- narrower scoping can be a follow-up once the targeting logic is mapped
-- out fully; this pass removes the "no login needed at all" exposure now.

alter table app_settings enable row level security;
alter table email_logs enable row level security;
alter table lead_sources enable row level security;
alter table notification_preferences enable row level security;
alter table notifications enable row level security;

create policy "authenticated_full_access" on app_settings
  for all to authenticated using (true) with check (true);
create policy "authenticated_full_access" on email_logs
  for all to authenticated using (true) with check (true);
create policy "authenticated_full_access" on lead_sources
  for all to authenticated using (true) with check (true);
create policy "authenticated_full_access" on notification_preferences
  for all to authenticated using (true) with check (true);
create policy "authenticated_full_access" on notifications
  for all to authenticated using (true) with check (true);
