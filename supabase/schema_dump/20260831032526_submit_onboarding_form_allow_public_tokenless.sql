-- There are two ways into the joining form and the first version of this
-- function only handled one of them:
--   /onboarding-form/{token} - sent to a specific candidate, links the
--     submission back to their candidate_applications row, and is the only
--     path that may resubmit over an HR-requested correction.
--   /onboarding-form - a public, token-less form. Every one of the 19
--     submissions on this database arrived this way, so rejecting an empty
--     token (as the first version did) would have broken the live intake
--     entirely.
--
-- A token-less submission is always an insert: with no token there is
-- nothing establishing which existing row belongs to the person, so
-- allowing an update would let anyone overwrite an arbitrary submission.

create or replace function public.submit_onboarding_form(
  p_token text,
  p_name text,
  p_phone text,
  p_designation text,
  p_form_data jsonb
) returns uuid
language plpgsql security definer set search_path = public as $fn$
declare
  v_candidate uuid;
  v_existing  uuid;
  v_new       uuid;
begin
  -- Public, token-less form: insert only, no candidate link.
  if coalesce(p_token, '') = '' then
    insert into onboarding_forms (name, phone_number, designation, form_data)
    values (p_name, p_phone, p_designation, p_form_data)
    returning id into v_new;
    return v_new;
  end if;

  select c.id into v_candidate
    from candidate_applications c
   where c.onboarding_token = p_token;

  if v_candidate is null then
    raise exception 'This onboarding link is not valid.';
  end if;

  select f.id into v_existing
    from onboarding_forms f
   where f.candidate_application_id = v_candidate;

  if v_existing is null then
    insert into onboarding_forms (name, phone_number, designation, form_data,
                                  candidate_application_id)
    values (p_name, p_phone, p_designation, p_form_data, v_candidate)
    returning id into v_new;
    return v_new;
  end if;

  -- Only a submission HR has sent back may be rewritten, so an approved
  -- form cannot be quietly edited after the fact.
  update onboarding_forms
     set name = p_name, phone_number = p_phone, designation = p_designation,
         form_data = p_form_data,
         needs_correction = false, fields_to_correct = '[]'::jsonb
   where id = v_existing and needs_correction = true;

  if not found then
    raise exception 'This form has already been submitted.';
  end if;
  return v_existing;
end;
$fn$;
