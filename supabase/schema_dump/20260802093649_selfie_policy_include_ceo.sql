-- The selfie-viewing policy enumerated role literally as ARRAY['HR','Management'],
-- so renaming the CEO's role silently removed his access to attendance selfies.
-- Route it through is_management_authority() as well, so it covers HR plus any
-- management-tier role and cannot drift again.
--
-- The 45-day retention window is preserved exactly as before.
drop policy if exists attendance_selfies_select_hr_management on storage.objects;

create policy attendance_selfies_select_hr_management on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attendance-selfies'
    and exists (
      select 1 from app_users
       where app_users.auth_user_id = auth.uid()
         and (app_users.role = 'HR' or public.is_management_authority(app_users.role))
    )
    and exists (
      select 1 from attendance_records ar
       where ar.created_at > (now() - interval '45 days')
         and (ar.check_in_selfie_path = objects.name
           or ar.check_out_selfie_path = objects.name)
    )
  );
