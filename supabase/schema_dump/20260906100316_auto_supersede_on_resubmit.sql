-- Marking the existing backlog fixes today; this keeps it fixed. Without it
-- the next resubmission — and 3 of 19 forms were sent back, so there will be
-- one — puts a second live row beside the first and the list drifts again.
create or replace function public.supersede_earlier_onboarding_forms()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  update onboarding_forms
     set superseded = true, superseded_by = new.id
   where id <> new.id
     and lower(trim(name)) = lower(trim(new.name))
     and not superseded
     -- Only earlier ones: a correction submitted out of order must not
     -- supersede the newer form it was correcting.
     and submitted_at < new.submitted_at;
  return new;
end;
$fn$;

drop trigger if exists trg_supersede_earlier_onboarding on onboarding_forms;
create trigger trg_supersede_earlier_onboarding
  after insert on onboarding_forms
  for each row execute function supersede_earlier_onboarding_forms();
