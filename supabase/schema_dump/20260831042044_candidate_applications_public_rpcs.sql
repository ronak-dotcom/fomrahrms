-- Two public, unauthenticated paths write to candidate_applications, and
-- both did it by talking to the table directly as the anon role:
--   /candidate-application - the public job application form, a plain
--     INSERT, so an applicant could set ANY column: their own
--     interview_status, pre_offer tokens, offered salary, hr notes.
--   /pre-offer/{token} - accept the offer, a plain UPDATE by row id, so
--     an anon caller could rewrite arbitrary fields on ANY candidate row
--     if they knew or guessed an id.
-- The permissive anon policy also allowed SELECT on the whole table:
-- every applicant's name, email, phone, CTC and resume link.
--
-- These functions replace both writes with a fixed column list (the
-- application) and a token-scoped, two-column update (the offer
-- response), so the anon policy can be dropped.

create or replace function public.submit_candidate_application(p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public as $fn$
declare v_id uuid;
begin
  if coalesce(p_data->>'name', '') = '' then
    raise exception 'Name is required.';
  end if;

  -- Deliberately an explicit column list rather than jsonb_populate_record:
  -- anything an applicant should not control (interview_status, tokens,
  -- offered CTC, HR notes, onboarding_token) is simply absent, so a
  -- crafted payload cannot reach those columns however it is shaped.
  insert into candidate_applications (
    name, mobile, place, dob, nationality, email, gender, marital_status, age,
    interview_date, post_applied, total_experience, relevant_experience,
    reason_for_change, current_ctc, expected_ctc, notice_period, source,
    job_portal, referred_by, related_employee, applied_before,
    standing_arrears, education_history, employment_history, referrals,
    address, declaration_name, signature_date, declaration_agreed,
    resume_url, custom_field_values
  ) values (
    p_data->>'name', p_data->>'mobile', p_data->>'place', p_data->>'dob',
    p_data->>'nationality', p_data->>'email', p_data->>'gender',
    p_data->>'marital_status', p_data->>'age', p_data->>'interview_date',
    p_data->>'post_applied', p_data->>'total_experience',
    p_data->>'relevant_experience', p_data->>'reason_for_change',
    p_data->>'current_ctc', p_data->>'expected_ctc', p_data->>'notice_period',
    p_data->>'source', p_data->>'job_portal', p_data->>'referred_by',
    p_data->>'related_employee', p_data->>'applied_before',
    p_data->>'standing_arrears',
    coalesce(p_data->'education_history', '[]'::jsonb),
    coalesce(p_data->'employment_history', '[]'::jsonb),
    coalesce(p_data->'referrals', '[]'::jsonb),
    p_data->>'address', p_data->>'declaration_name', p_data->>'signature_date',
    coalesce((p_data->>'declaration_agreed')::boolean, false),
    p_data->>'resume_url',
    coalesce(p_data->'custom_field_values', '{}'::jsonb)
  ) returning id into v_id;
  return v_id;
end;
$fn$;

-- Accepting an offer is keyed on the pre-offer token, not a row id, and
-- can only ever set these two columns.
create or replace function public.accept_pre_offer(p_token text)
returns boolean
language plpgsql security definer set search_path = public as $fn$
declare v_id uuid;
begin
  if coalesce(p_token, '') = '' then
    raise exception 'A valid offer link is required.';
  end if;

  select c.id into v_id
    from candidate_applications c
   where c.pre_offer_token = p_token;

  if v_id is null then
    raise exception 'This offer link is not valid.';
  end if;

  -- Not-already-accepted guard lives here rather than only in the UI, so a
  -- replayed request cannot overwrite the original acceptance timestamp.
  update candidate_applications
     set pre_offer_accepted = true,
         pre_offer_accepted_at = now()::text
   where id = v_id and coalesce(pre_offer_accepted, false) = false;

  return found;
end;
$fn$;

revoke all on function public.submit_candidate_application(jsonb) from public;
revoke all on function public.accept_pre_offer(text) from public;
grant execute on function public.submit_candidate_application(jsonb) to anon, authenticated;
grant execute on function public.accept_pre_offer(text) to anon, authenticated;
