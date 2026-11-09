-- Closes the QA findings: input validation, self-approval, half-days,
-- holidays, cancellation.

-- days must hold 0.5 for a half day. numeric(5,1) rather than float: leave is
-- counted in halves, and binary floating point would eventually show 2.9999.
alter table leave_applications alter column days type numeric(5,1) using days::numeric;

-- Cancellation states. 'cancel_requested' is the employee asking; only
-- Management moves it to 'cancelled', matching how they approve.
alter table leave_applications
  add column if not exists cancel_reason      text default '',
  add column if not exists cancel_requested_at timestamptz,
  add column if not exists cancelled_by       text default '',
  add column if not exists cancelled_at       timestamptz;

-- (6) Status vocabulary. Anything outside this set used to be stored verbatim
-- AND counted as live leave, because every quota check tests <> 'denied'.
alter table leave_applications drop constraint if exists leave_status_vocabulary;
alter table leave_applications add constraint leave_status_vocabulary
  check (coalesce(manager_status,'pending') in
         ('pending','approved','denied','cancel_requested','cancelled'));

-- (2) Start must not be after end. This stored days = -9, which poisons every
-- SUM over the column.
alter table leave_applications drop constraint if exists leave_dates_ordered;
alter table leave_applications add constraint leave_dates_ordered
  check (to_date >= from_date);

-- (3) Leave type must be named.
alter table leave_applications drop constraint if exists leave_type_present;
alter table leave_applications add constraint leave_type_present
  check (coalesce(btrim(leave_type),'') <> '');

-- (1)(4)(5) Employee must exist; leave starts pending; no same-type overlap.
create or replace function public.validate_leave_request()
returns trigger
language plpgsql
as $function$
declare v_exists boolean; v_clash record; begin
  -- (4) The employee must be a real person.
  select exists (
    select 1 from app_users
     where (coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
        or (lower(btrim(name)) = lower(btrim(coalesce(new.employee_name,''))))
  ) into v_exists;
  if not v_exists then
    raise exception 'No employee matches "%" (%). Leave cannot be filed for an unknown person.',
      coalesce(nullif(new.employee_name,''),'(blank)'), coalesce(nullif(new.employee_id,''),'no id')
      using errcode = 'foreign_key_violation';
  end if;

  -- (1) A new request always starts pending. Previously an employee could
  -- insert their own leave already marked 'approved' — RLS let them write
  -- their own row, and nothing checked the status it arrived with.
  if tg_op = 'INSERT'
     and coalesce(new.manager_status,'pending') <> 'pending'
     and not public.is_management_authority(coalesce(current_app_role(),''))
     and coalesce(current_app_role(),'') <> 'HR' then
    new.manager_status := 'pending';
  end if;

  -- (5) No second request over the same dates with the same type. Different
  -- types are already refused by the clubbing rule; this closes same-type,
  -- which was double-counting the overlapping day.
  if new.leave_type <> 'Permission' then
    select * into v_clash from leave_applications l
     where l.id is distinct from new.id
       and l.leave_type = new.leave_type
       and coalesce(l.manager_status,'') not in ('denied','cancelled')
       and lower(btrim(l.employee_name)) = lower(btrim(new.employee_name))
       and l.from_date <= new.to_date and l.to_date >= new.from_date
     limit 1;
    if v_clash.id is not null then
      raise exception
        'You already have % leave from % to % covering these dates.',
        v_clash.leave_type, to_char(v_clash.from_date,'DD Mon'), to_char(v_clash.to_date,'DD Mon')
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end; $function$;

drop trigger if exists trg_validate_leave_request on leave_applications;
create trigger trg_validate_leave_request
  before insert or update on leave_applications
  for each row execute function public.validate_leave_request();

-- (7)(8) Half-days count 0.5; public holidays inside a request are not charged.
create or replace function public.apply_sandwich_policy()
returns trigger language plpgsql as $function$
declare d date; v_outside int := 0; v_inside int := 0; v_holidays int := 0;
        v_prior int; v_total numeric(5,1);
begin
  if new.leave_type = 'Permission' then return new; end if;
  if tg_op = 'UPDATE' and new.from_date = old.from_date and new.to_date = old.to_date
     and new.is_half_day is not distinct from old.is_half_day then
    return new;
  end if;

  d := new.from_date - 1;
  if public.is_non_working_day(new.employee_name, d)
     and public.has_leave_on(new.employee_name, d - 1, new.id) then
    v_outside := v_outside + 1;
  end if;
  d := new.to_date + 1;
  if public.is_non_working_day(new.employee_name, d)
     and public.has_leave_on(new.employee_name, d + 1, new.id) then
    v_outside := v_outside + 1;
  end if;

  d := new.from_date;
  while d <= new.to_date loop
    if exists (select 1 from holidays where holiday_date = d) then
      -- (8) A public holiday is not a working day, so it is not charged. The
      -- employee was never due to work it; taking leave around it must not
      -- cost them the day.
      v_holidays := v_holidays + 1;
    elsif public.is_non_working_day(new.employee_name, d) then
      v_inside := v_inside + 1;
    end if;
    d := d + 1;
  end loop;

  new.sandwich_days := v_outside + v_inside;
  v_total := (new.to_date - new.from_date) + 1 + v_outside - v_holidays;

  -- (7) A half day is 0.5, and only meaningful on a single-day request.
  if coalesce(new.is_half_day,false) and (new.to_date = new.from_date) then
    v_total := 0.5;
    new.sandwich_days := 0;
  end if;
  if v_total < 0 then v_total := 0; end if;

  select coalesce(sum(sandwich_days),0) into v_prior from leave_applications
   where lower(btrim(employee_name)) = lower(btrim(new.employee_name))
     and leave_type <> 'Permission'
     and coalesce(manager_status,'') not in ('denied','cancelled')
     and id is distinct from new.id
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date);

  if new.sandwich_days > 0 and v_prior > 0 then
    new.lop_days := ceil(v_total);
  else
    new.lop_days := greatest(ceil(v_total) - 2, 0);
  end if;

  new.days := v_total;
  return new;
end; $function$;

-- (9) Cancellation. The employee asks; Management decides — same authority
-- that approved it. A cancelled leave stops counting as non-denied, so the
-- entitlement it consumed returns automatically.
create or replace function public.request_leave_cancellation(p_id text, p_reason text)
returns boolean language plpgsql security definer set search_path to 'public'
as $function$
declare v_name text; begin
  select employee_name into v_name from leave_applications where id = p_id;
  if v_name is null then return false; end if;

  if lower(btrim(v_name)) <> lower(btrim(coalesce(current_app_name(),'')))
     and not public.is_management_authority(coalesce(current_app_role(),''))
     and coalesce(current_app_role(),'') <> 'HR' then
    raise exception 'You can only request cancellation of your own leave.'
      using errcode = 'insufficient_privilege';
  end if;

  update leave_applications
     set manager_status = 'cancel_requested',
         cancel_reason = coalesce(btrim(p_reason),''),
         cancel_requested_at = now()
   where id = p_id and coalesce(manager_status,'') in ('pending','approved');
  return found;
end; $function$;

create or replace function public.decide_leave_cancellation(p_id text, p_approve boolean)
returns boolean language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_management_authority(coalesce(current_app_role(),'')) then
    raise exception 'Only Management can approve a leave cancellation.'
      using errcode = 'insufficient_privilege';
  end if;
  update leave_applications
     set manager_status = case when p_approve then 'cancelled' else 'approved' end,
         cancelled_by   = case when p_approve then coalesce(current_app_name(),'') else '' end,
         cancelled_at   = case when p_approve then now() else null end
   where id = p_id and manager_status = 'cancel_requested';
  return found;
end; $function$;

revoke all on function public.request_leave_cancellation(text,text) from public, anon;
revoke all on function public.decide_leave_cancellation(text,boolean) from public, anon;
grant execute on function public.request_leave_cancellation(text,text) to authenticated, service_role;
grant execute on function public.decide_leave_cancellation(text,boolean) to authenticated, service_role;
