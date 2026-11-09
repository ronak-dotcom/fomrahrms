-- The candidate-facing onboarding form talked to onboarding_forms directly
-- as the anon role, which meant the permissive anon policy had to allow
-- SELECT on the whole table — so anyone holding the public anon key could
-- read every candidate's submission: home address, family details,
-- identity numbers, the lot.
--
-- These two functions move that access behind the onboarding token, which
-- is the actual capability the candidate holds. Being SECURITY DEFINER they
-- bypass RLS themselves, so the anon policy can then be closed entirely
-- (see the following migration) without breaking the candidate flow.

create or replace function public.onboarding_form_for_token(p_token text)
returns table(id uuid, form_data jsonb, needs_correction boolean, fields_to_correct jsonb)
language sql stable security definer set search_path = public as $fn$
  select f.id, f.form_data, f.needs_correction, f.fields_to_correct
    from onboarding_forms f
    join candidate_applications c on c.id = f.candidate_application_id
   where p_token <> '' and c.onboarding_token = p_token;
$fn$;

-- Insert on first submission, update in place on a correction resubmit.
-- Keyed on the token rather than a caller-supplied row id so a candidate
-- cannot write to someone else's submission by guessing an id.
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
begin
  if coalesce(p_token, '') = '' then
    raise exception 'A valid onboarding link is required.';
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
    returning id into v_existing;
    return v_existing;
  end if;

  -- Only a submission HR has sent back may be rewritten. Without this a
  -- candidate could keep editing an already-approved form after the fact.
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

revoke all on function public.onboarding_form_for_token(text) from public;
revoke all on function public.submit_onboarding_form(text, text, text, text, jsonb) from public;
grant execute on function public.onboarding_form_for_token(text) to anon, authenticated;
grant execute on function public.submit_onboarding_form(text, text, text, text, jsonb) to anon, authenticated;
