-- Permission quota: only the permission that takes the cycle over the quota
-- costs half a day. 19 Nov 2026.
--
-- set_and_check_permission_minutes() runs on every insert AND update, and
-- counted every other live permission in the cycle, including ones filed
-- later. So approving an earlier permission after a later one had been filed
-- re-ran the check against both and charged both: a 2-hour permission and a
-- 30-minute one cost a full day of LOP instead of half. The money-rule tests
-- (ZZT-07) have pinned this since 13 Nov.
--
-- Now only permissions filed BEFORE this one count (applied_on, then id to
-- break a tie). Filing a new permission never changes an earlier one's
-- status, and an approval re-run gives the same answer as when it was filed.
-- The permission that goes over the quota is the one filed when the quota
-- was already used, whatever date it is for.
--
-- The nightly check for a permission charged within its quota is changed to
-- the same order, so the two agree.

create or replace function public.set_and_check_permission_minutes()
returns trigger
language plpgsql
as $$
declare v_quota integer; v_used integer;
begin
  if new.leave_type is distinct from 'Permission' then
    new.permission_minutes := null;
    new.permission_lop_half_day := false;
    return new;
  end if;

  if new.permission_minutes is null then
    new.permission_minutes :=
      public.permission_minutes_from_text(split_part(coalesce(new.reason,''), '|', 1));
  end if;

  if coalesce(public.is_exempt_from_leave_rules(new.employee_id, new.employee_name), false) then
    new.permission_lop_half_day := false;
    return new;
  end if;

  if new.permission_minutes is null or new.permission_minutes not in (30,60,120) then
    raise exception
      'Permission must be 30, 60 or 120 minutes. The allowance of 120 minutes per attendance cycle can be taken as 4x30, 2x60 or 1x120.'
      using errcode='check_violation';
  end if;

  select coalesce(permission_minutes_quota,120) into v_quota from app_users
   where (coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
      or (coalesce(new.employee_id,'') =  '' and lower(btrim(name)) = lower(btrim(new.employee_name)))
   limit 1;
  v_quota := coalesce(v_quota,120);

  -- Only permissions filed before this one.
  select coalesce(sum(permission_minutes),0) into v_used from leave_applications
   where leave_type='Permission' and id is distinct from new.id
     and public.leave_is_live(manager_status, management_status)
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date)
     and (applied_on < coalesce(new.applied_on, now())
          or (applied_on = new.applied_on and id < new.id))
     and ((coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
       or (coalesce(new.employee_id,'') =  '' and lower(btrim(employee_name)) = lower(btrim(new.employee_name))));

  new.permission_lop_half_day := (v_used + new.permission_minutes > v_quota);

  return new;
end;
$$;

-- The nightly check: same order as the rule.
do $$
declare
  src text := pg_get_functiondef('public.integrity_collect()'::regprocedure);
  old_order constant text := 'order by l.from_date, l.applied_on rows unbounded preceding';
  new_order constant text := 'order by l.applied_on, l.id rows unbounded preceding';
begin
  if position(old_order in src) > 0 then
    execute replace(src, old_order, new_order);
  elsif position(new_order in src) = 0 then
    raise exception 'integrity_collect() does not contain the expected permission ordering';
  end if;
end $$;
