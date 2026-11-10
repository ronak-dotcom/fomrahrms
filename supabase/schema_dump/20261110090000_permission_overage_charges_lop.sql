-- Exceeding the permission allowance was supposed to be allowed and charged
-- as half a day's LOP, flagged in the month-end report. The app implements
-- exactly that: it warns "half a day will be marked as loss of pay", offers
-- "Submit with LOP", and sets permission_lop_half_day. The trigger then
-- threw the row out.
--
-- So an employee who needed the time was told they could have it, agreed to
-- the deduction, and the save failed with nothing on screen to explain it.
-- That is why Yuvaraj S could not file a 2-hour permission for 9 November
-- with 60 of his 120 minutes already spent. Blocking also defeats the point:
-- the time gets taken anyway and nothing records it.
--
-- The overage decision now lives here rather than in the client, so the flag
-- is right whatever filed the row. permission_lop_days() already turns the
-- flag into half a day and generate_payroll already reports it.
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

  -- Still enforced: the allowance is 4x30, 2x60 or 1x120, so anything else
  -- is a malformed request rather than an over-spend.
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

  select coalesce(sum(permission_minutes),0) into v_used from leave_applications
   where leave_type='Permission' and id is distinct from new.id
     and coalesce(manager_status,'') <> 'denied'
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date)
     and ((coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
       or (coalesce(new.employee_id,'') =  '' and lower(btrim(employee_name)) = lower(btrim(new.employee_name))));

  -- Over the allowance is permitted and costs half a day, rather than being
  -- refused. Decided here so the flag is authoritative.
  new.permission_lop_half_day := (v_used + new.permission_minutes > v_quota);

  return new;
end;
$$;

-- enforce_permission_quota() was a second copy of this rule that counted by
-- calendar month instead of the 26th-to-25th cycle, and still raised. It had
-- no trigger attached so it never fired, but it was a loaded gun for whoever
-- wired it up next. Dropped.
