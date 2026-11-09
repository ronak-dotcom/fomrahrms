-- Two employees ended up sharing FHIPL-08 (Nirmal Kumar and Surya).
--
-- How: the HR create form exposes Employee ID as a plain free-text box with no
-- uniqueness check, and there was no unique constraint on the column either —
-- app_users' only key is (email). Nothing anywhere stopped the same ID being
-- typed twice. Nirmal had also been recreated three times (FHIPL-06 -> 07 ->
-- 08) while the activation bug was unresolved, so FHIPL-08 looked like the
-- next free number.
--
-- Why it matters: employee_id is the join key for employee_locations,
-- attendance_policy_employee_overrides, attendance_records and payslips. Two
-- people sharing one ID means shared geofence assignment, shared policy, and
-- attendance rows that cannot be told apart.

alter table app_users disable trigger trg_protect_app_users;

-- 1. Give Surya a distinct ID and carry the dependent rows across in step.
--    Surya's rows are identifiable by employee_name, so nothing is guessed.
update attendance_records
   set employee_id = 'FHIPL-09'
 where employee_id = 'FHIPL-08' and employee_name = 'Surya';

update app_users
   set employee_id = 'FHIPL-09'
 where employee_id = 'FHIPL-08' and name = 'Surya';

alter table app_users enable trigger trg_protect_app_users;

-- 2. The constraint that should always have existed.
create unique index if not exists app_users_employee_id_uidx
  on app_users (upper(btrim(employee_id)))
  where coalesce(btrim(employee_id),'') <> '';

-- 3. Automatic generation: next free number for a given prefix.
--    Zero-padded to two digits to match the existing FHIPL-01 / FD-01 style,
--    widening naturally past 99.
create or replace function public.next_employee_id(p_prefix text default 'FHIPL')
returns text
language sql
stable
as $function$
  select upper(btrim(p_prefix)) || '-' ||
         lpad((coalesce(max(
           nullif(regexp_replace(split_part(employee_id, '-', 2), '\D', '', 'g'), '')::int
         ), 0) + 1)::text, 2, '0')
    from app_users
   where upper(split_part(employee_id, '-', 1)) = upper(btrim(p_prefix));
$function$;

-- 4. Fill it in automatically when HR leaves the field blank, and normalise
--    whatever is typed (uppercase, spaces stripped) so 'fhipl- 10' and
--    'FHIPL-10' can never coexist as separate rows.
create or replace function public.assign_employee_id()
returns trigger
language plpgsql
as $function$
declare
  v_prefix text;
begin
  new.employee_id := upper(replace(coalesce(new.employee_id, ''), ' ', ''));

  if new.employee_id = '' then
    v_prefix := case
      when coalesce(new.business_unit, '') = 'FOMRA Developers' then 'FD'
      else 'FHIPL'
    end;
    new.employee_id := public.next_employee_id(v_prefix);
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_assign_employee_id on app_users;
create trigger trg_assign_employee_id
  before insert or update of employee_id on app_users
  for each row execute function public.assign_employee_id();

grant execute on function public.next_employee_id(text) to authenticated, service_role;
