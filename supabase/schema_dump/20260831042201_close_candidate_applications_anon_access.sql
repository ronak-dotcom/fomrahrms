-- Every unauthenticated path into this table now runs through a
-- SECURITY DEFINER function:
--   submit_candidate_application()          - public job application form
--   accept_pre_offer()                      - public offer acceptance
--   candidate_application_by_pre_offer_token()  - offer page read
--   candidate_application_by_onboarding_token() - joining form read
-- None of them need the anon role to touch the table directly, so the
-- blanket policy that let any holder of the public anon key read every
-- applicant's name, email, phone, CTC and resume link can be dropped.

drop policy if exists "app_access" on candidate_applications;

create policy "authenticated_full_access" on candidate_applications
  for all to authenticated using (true) with check (true);
