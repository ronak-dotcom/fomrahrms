-- device_tokens had RLS enabled but not a single policy, which denies
-- everything: every push-token registration has been failing with 403
-- since RLS was turned on, so push notifications were silently dead.
--
-- The app's own bootstrap SQL still says "disable row level security" for
-- this table, but re-disabling would leave the whole table readable by
-- anyone with the anon key — and it maps device tokens to staff email
-- addresses. Adding the missing policy instead keeps RLS on and fixes
-- registration.
create policy "authenticated_full_access" on device_tokens
  for all to authenticated using (true) with check (true);
