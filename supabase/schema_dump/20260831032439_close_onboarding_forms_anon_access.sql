-- Candidate access now runs entirely through onboarding_form_for_token()
-- and submit_onboarding_form(), which are SECURITY DEFINER and check the
-- onboarding token. Nothing the candidate does needs direct table access
-- any more, so the blanket anon policy that let any holder of the public
-- anon key read every submission can go.
--
-- candidate_applications keeps its anon policy for now: the pre-offer and
-- application-form pages still read and write it directly, so closing it
-- needs the same RPC treatment first. Left as a follow-up rather than
-- broken here.

drop policy if exists "app_access" on onboarding_forms;

create policy "authenticated_full_access" on onboarding_forms
  for all to authenticated using (true) with check (true);
