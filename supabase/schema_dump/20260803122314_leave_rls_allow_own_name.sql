-- REGRESSION FIX: employees could not submit leave at all.
--
-- Enabling RLS on leave_applications gated writes on
--   employee_id = current_app_employee_id() or app_manages(employee_name) or hr/mgmt
-- but the client's insert (SupabaseService.upsertLeaveApplication) never
-- populates employee_id — LeaveApplication has no such field, only
-- employee_name. So for an ordinary employee every branch was false, the WITH
-- CHECK failed, and the insert was rejected.
--
-- Worse, the call site is wrapped in `catch (_) {}`, so the rejection was
-- swallowed: the UI reported success and raised a notification while nothing
-- was ever written. Sijo's leave request produced a notification and no row.
--
-- Matching on employee_name as well makes the policy agree with the data the
-- client actually sends. Ownership is still enforced — the name must be the
-- caller's own, taken from their JWT, not from anything they supply.
create or replace function public.owns_leave_row(p_employee_id text, p_employee_name text)
returns boolean
language sql
stable
as $function$
  select
    (coalesce(p_employee_id,'') <> '' and p_employee_id = current_app_employee_id())
    or (lower(btrim(coalesce(p_employee_name,''))) = lower(btrim(coalesce(current_app_name(),''))))
$function$;

drop policy if exists leave_applications_all on leave_applications;
create policy leave_applications_all on leave_applications for all to authenticated
  using (
    public.owns_leave_row(employee_id, employee_name)
    or app_manages(employee_name)
    or current_app_is_hr_or_mgmt()
  )
  with check (
    public.owns_leave_row(employee_id, employee_name)
    or app_manages(employee_name)
    or current_app_is_hr_or_mgmt()
  );

-- Same defect shape on attendance_records: the client writes employee_id
-- there, so it is currently fine, but a blank id would fail identically.
-- Left alone rather than changed speculatively.
