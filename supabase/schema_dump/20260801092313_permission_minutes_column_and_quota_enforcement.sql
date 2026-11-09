-- Two related problems.
--
-- 1. Permission duration is not stored. LeaveStore.permMinutesFromReason()
--    parses it back out of a free-text string that also contains the
--    employee's own description, so a 2-hour permission described as "back in
--    30 Minutes" is charged 30. It also breaks silently if HR renames a
--    duration in the form editor, and defaults unrecognised labels to 60.
--
-- 2. The monthly quota is enforced only in Dart. RLS governs WHO may insert a
--    row, not whether the cap is already spent, so anything talking to
--    PostgREST directly skips the limit entirely.
--
-- Adding a real integer column fixes the first and makes the second
-- enforceable. leave_applications is currently empty, so there is nothing to
-- backfill.

alter table leave_applications
  add column if not exists permission_minutes integer;

-- Parser kept ONLY as a fallback for rows written by an app build that does
-- not yet populate the column. Ordered longest-match-first so that
-- '1 Hour 30 Minutes' is not read as '1 Hour', which the Dart version gets
-- wrong.
create or replace function public.permission_minutes_from_text(p text)
returns integer
language sql
immutable
as $function$
  select case
    when p is null                      then 60
    when p ilike '%1½ Hours%'           then 90
    when p ilike '%1 Hour 30 Minutes%'  then 90
    when p ilike '%2 Hours%'            then 120
    when p ilike '%1 Hour%'             then 60
    when p ilike '%30 Minutes%'         then 30
    else 60
  end;
$function$;

-- Fill the column from the duration segment only — the text before the first
-- '|' — so the employee's description can never influence the charge.
create or replace function public.set_permission_minutes()
returns trigger
language plpgsql
as $function$
begin
  if new.leave_type is distinct from 'Permission' then
    new.permission_minutes := null;
    return new;
  end if;
  if new.permission_minutes is null then
    new.permission_minutes :=
      public.permission_minutes_from_text(split_part(coalesce(new.reason,''), '|', 1));
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_set_permission_minutes on leave_applications;
create trigger trg_set_permission_minutes
  before insert or update on leave_applications
  for each row execute function public.set_permission_minutes();

-- Enforce the monthly cap server-side. Denied requests do not count.
create or replace function public.enforce_permission_quota()
returns trigger
language plpgsql
as $function$
declare
  v_quota integer;
  v_used  integer;
begin
  if new.leave_type is distinct from 'Permission' then
    return new;
  end if;

  select coalesce(permission_minutes_quota, 120) into v_quota
    from app_users
   where employee_id = new.employee_id
      or lower(btrim(name)) = lower(btrim(new.employee_name))
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
       or (coalesce(new.employee_id,'') = ''
           and lower(btrim(employee_name)) = lower(btrim(new.employee_name)))
     );

  if v_used + coalesce(new.permission_minutes, 0) > v_quota then
    raise exception
      'Monthly permission quota exhausted: % of % minutes already used this month, and this request is a further %.',
      v_used, v_quota, coalesce(new.permission_minutes, 0)
      using errcode = 'check_violation';
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_enforce_permission_quota on leave_applications;
create trigger trg_enforce_permission_quota
  before insert or update on leave_applications
  for each row execute function public.enforce_permission_quota();
