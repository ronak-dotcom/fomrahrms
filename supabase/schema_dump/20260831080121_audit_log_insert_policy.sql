-- audit_log had a SELECT policy (HR/Management only) but no INSERT policy
-- at all, so every audit write was denied with 403 — including the
-- write-failure audits that exist specifically to make silent failures
-- visible. The audit trail has been recording nothing.
--
-- Insert stays open to any authenticated user because entries record that
-- user's own actions; reading remains restricted to HR/Management via the
-- existing audit_log_select_staff policy.
create policy "audit_log_insert_authenticated" on audit_log
  for insert to authenticated with check (true);
