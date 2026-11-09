-- HR now picks the company on the forward dialog (it decides the FD- vs
-- FHIPL- id prefix), so that choice needs to survive to approval and land
-- on the created app_users row. Without it the new employee would default
-- to the wrong company despite HR having explicitly chosen one.
alter table onboarding_forms
  add column if not exists assigned_business_unit text default '';
