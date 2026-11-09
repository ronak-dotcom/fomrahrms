-- Every joining form captures blood group, emergency contact, PF and ESI
-- numbers, date of birth and father's name. None of it reaches app_users:
-- all 19 forms have a blood group, and zero employees do. The candidate
-- fills it in, HR files the form, and the value is never seen again — PF and
-- ESI especially, which payroll needs and currently has nowhere to read from.
alter table app_users add column if not exists date_of_birth text default '';
alter table app_users add column if not exists father_name text default '';
alter table app_users add column if not exists pf_number text default '';
alter table app_users add column if not exists esi_number text default '';
alter table app_users add column if not exists emergency_contact_address text default '';

-- Backfills what has already been collected. Matched on name because no
-- form links to an app_users row — the two were never connected.
-- Only fills BLANKS: anything HR has since corrected in app_users is the
-- more recent truth and must not be overwritten by an older form.
do $$
begin
  perform set_config('app.bypass_sensitive_column_protection','on', true);

  update app_users u set
    blood_group   = coalesce(nullif(u.blood_group,''),   nullif(f.form_data->>'blood_group','')),
    date_of_birth = coalesce(nullif(u.date_of_birth,''), nullif(f.form_data->>'date_of_birth','')),
    father_name   = coalesce(nullif(u.father_name,''),   nullif(f.form_data->>'father_name','')),
    pf_number     = coalesce(nullif(u.pf_number,''),     nullif(f.form_data->>'pf_number','')),
    esi_number    = coalesce(nullif(u.esi_number,''),    nullif(f.form_data->>'esi_number','')),
    emergency_name  = coalesce(nullif(u.emergency_name,''),  nullif(f.form_data->>'emergency_contact_name','')),
    emergency_phone = coalesce(nullif(u.emergency_phone,''), nullif(f.form_data->>'emergency_contact_number','')),
    emergency_contact_address =
        coalesce(nullif(u.emergency_contact_address,''), nullif(f.form_data->>'emergency_contact_address',''))
  from (
    -- One row per person: the most recent APPROVED form. Rejected and
    -- sent-back submissions are superseded and must not win.
    select distinct on (lower(trim(name))) name, form_data
      from onboarding_forms
     where status = 'access_granted'
     order by lower(trim(name)), submitted_at desc
  ) f
  where lower(trim(u.name)) = lower(trim(f.name));
end $$;

select count(*) filter (where coalesce(blood_group,'')<>'')   as with_blood,
       count(*) filter (where coalesce(pf_number,'')<>'')      as with_pf,
       count(*) filter (where coalesce(emergency_phone,'')<>'') as with_emergency
  from app_users where active;
