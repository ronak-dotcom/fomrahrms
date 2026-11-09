-- v1 split this across two BEFORE triggers. Postgres fires same-timing
-- triggers in NAME order, so trg_enforce_permission_quota ran before
-- trg_set_permission_minutes and read a NULL permission_minutes — adding 0 to
-- the running total and letting every request through. Combining them into one
-- function removes the ordering dependency entirely.

drop trigger if exists trg_set_permission_minutes   on leave_applications;
drop trigger if exists trg_enforce_permission_quota on leave_applications;

create or replace function public.set_and_check_permission_minutes()
returns trigger
language plpgsql
as $function$
declare
  v_quota integer;
  v_used  integer;
begin
  if new.leave_type is distinct from 'Permission' then
    new.permission_minutes := null;
    return new;
  end if;

  -- 1. Derive the charge from the DURATION SEGMENT ONLY — the text before the
  --    first '|' — so the employee's own description cannot steer it.
  if new.permission_minutes is null then
    new.permission_minutes :=
      public.permission_minutes_from_text(split_part(coalesce(new.reason,''), '|', 1));
  end if;

  -- 2. Then enforce the monthly cap, now that the value exists.
  select coalesce(permission_minutes_quota, 120) into v_quota
    from app_users
   where (coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
      or (coalesce(new.employee_id,'') =  '' and lower(btrim(name)) = lower(btrim(new.employee_name)))
   limit 1;
  v_quota := coalesce(v_quota, 120);

  select coalesce(sum(permission_minutes), 0) into v_used
    from leave_applications
   where leave_type = 'Permission'
     and id is distinct from new.id
     and coalesce(manager_status,'') <> 'denied'
     and date_trunc('month', from_date) = date_trunc('month', new.from_date)
     and (
       (coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
       or (coalesce(new.employee_id,'') =  '' and lower(btrim(employee_name)) = lower(btrim(new.employee_name)))
     );

  if v_used + new.permission_minutes > v_quota then
    raise exception
      'Monthly permission quota exhausted: % of % minutes already used this month, and this request is a further %.',
      v_used, v_quota, new.permission_minutes
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

create trigger trg_permission_minutes
  before insert or update on leave_applications
  for each row execute function public.set_and_check_permission_minutes();
