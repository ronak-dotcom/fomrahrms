alter table onboarding_forms
  add column if not exists needs_correction boolean not null default false;
alter table onboarding_forms
  add column if not exists fields_to_correct jsonb not null default '[]'::jsonb;
alter table onboarding_forms
  add column if not exists correction_requested_at timestamptz;
alter table onboarding_forms
  add column if not exists correction_requested_by text default '';
