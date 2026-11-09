-- next_employee_id() only looked at app_users, so an id already reserved on
-- a forwarded-but-not-yet-approved onboarding could be suggested again to
-- the next hire — two pending onboardings would be handed the same number,
-- and the second would fail on the unique constraint at approval time.
-- Considering assigned_emp_id on in-flight submissions closes that window.
create or replace function public.next_employee_id(p_prefix text default 'FHIPL')
returns text language sql stable as $fn$
  with taken as (
    select employee_id AS id from app_users
    union all
    select assigned_emp_id from onboarding_forms
     where coalesce(assigned_emp_id,'') <> ''
       and status not in ('mgmt_denied','hr_denied')
  )
  select upper(btrim(p_prefix)) || '-' ||
         lpad((coalesce(max(
           nullif(regexp_replace(split_part(id, '-', 2), '\D', '', 'g'), '')::int
         ), 0) + 1)::text, 2, '0')
    from taken
   where upper(split_part(id, '-', 1)) = upper(btrim(p_prefix));
$fn$;
