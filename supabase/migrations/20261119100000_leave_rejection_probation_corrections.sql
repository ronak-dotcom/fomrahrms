-- Leave: rejection at either level, probation as LOP, accrual from
-- confirmation, and HR corrections approved by Management. 19 Nov 2026.
--
-- 1. A leave rejected or cancelled at EITHER level is dead.
--    Every rule asked only "did the manager deny it?". Management rejected
--    Jose's 19 Nov leave (filed as CL, should have been ML), the manager
--    status stayed 'pending', and the rejected request kept blocking the
--    date, so he could not reapply. leave_is_live() is now the one test,
--    used by the date-clash, clubbing, sandwich, permission-quota and
--    probation rules.
--
-- 2. Probation: one paid day of leave per cycle; anything beyond is LOP.
--    Previously a second leave in the cycle was refused outright, so a
--    probationer who was absent anyway had no way to record it. A half day
--    counts as half. Decided by Management on 14 Nov 2026.
--
-- 3. Probation CL lapses at the end of each cycle, and the balance screen
--    says so: 1 CL usable per cycle, not the confirmed staff's 2 per request
--    with days carried forward. Decided by Management on 19 Nov 2026.
--
-- 4. Leave accrues only from the confirmation date, for anyone confirmed
--    from now on (app_users.leave_accrual_from, set automatically when the
--    confirmation is recorded). Staff already confirmed keep their balances:
--    their recorded confirmation date is mostly the day it was entered in the
--    app (8 Sep 2026 for staff who joined as early as 2010), not a real
--    confirmation, and counting from it would wipe out most of their CL.
--
-- 5. Leave corrections: HR proposes a change to the type, balance, dates or
--    half / full day of a request, with a reason; Management approves or
--    rejects it, and can approve the leave in the same step.

-- ── 1. One definition of "still live" ───────────────────────────────────────
create or replace function public.leave_is_live(p_manager_status text, p_management_status text)
returns boolean
language sql
immutable
as $$
  select not (
    coalesce(p_management_status, '') in ('denied', 'cancelled')
    or (coalesce(p_manager_status, '') in ('denied', 'cancelled')
        and coalesce(p_management_status, '') <> 'approved')
  );
$$;

create or replace function public.has_leave_on(p_employee_name text, p_date date, p_exclude_id text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from leave_applications
     where lower(btrim(employee_name)) = lower(btrim(p_employee_name))
       and leave_type <> 'Permission'
       and public.leave_is_live(manager_status, management_status)
       and id is distinct from coalesce(p_exclude_id,'')
       and p_date between from_date and to_date
  );
$$;

create or replace function public.validate_leave_request()
returns trigger
language plpgsql
as $$
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

  -- (1) A new request always starts pending.
  if tg_op = 'INSERT'
     and coalesce(new.manager_status,'pending') <> 'pending'
     and not public.is_management_authority(coalesce(current_app_role(),''))
     and coalesce(current_app_role(),'') <> 'HR' then
    new.manager_status := 'pending';
  end if;

  -- (5) No second live request over the same dates with the same type. A
  -- request rejected or cancelled at either level no longer counts.
  if new.leave_type <> 'Permission' and public.leave_is_live(new.manager_status, new.management_status) then
    select * into v_clash from leave_applications l
     where l.id is distinct from new.id
       and l.leave_type = new.leave_type
       and public.leave_is_live(l.manager_status, l.management_status)
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
end; $$;

create or replace function public.enforce_leave_clubbing()
returns trigger
language plpgsql
as $$
declare
  v_clash record;
  v_days  int;
begin
  if new.leave_type = 'Permission' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.from_date = old.from_date
     and new.to_date   = old.to_date
     and new.leave_type = old.leave_type then
    return new;
  end if;

  v_days := (new.to_date - new.from_date) + 1;

  new.needs_medical_certificate :=
    (new.leave_type ilike '%Medical%' or new.leave_type ilike '%Sick%') and v_days > 3;

  select * into v_clash
    from leave_applications l
   where l.id is distinct from new.id
     and l.leave_type <> 'Permission'
     and public.leave_is_live(l.manager_status, l.management_status)
     and lower(btrim(l.employee_name)) = lower(btrim(new.employee_name))
     and l.from_date <= (new.to_date + 1)
     and l.to_date   >= (new.from_date - 1)
   limit 1;

  if v_clash.id is null then
    return new;
  end if;

  if new.leave_type ilike '%Comp%' or v_clash.leave_type ilike '%Comp%' then
    new.requires_management_approval := true;
    return new;
  end if;

  if new.leave_type <> v_clash.leave_type then
    raise exception
      'CL, ML and EL cannot be combined. This request is % and runs next to an existing % leave (% to %). Take them separately, or use Comp Off, which can be combined.',
      new.leave_type, v_clash.leave_type,
      to_char(v_clash.from_date,'DD Mon'), to_char(v_clash.to_date,'DD Mon')
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create or replace function public.apply_sandwich_policy()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare d date; v_outside int := 0; v_inside int := 0;
        v_working int := 0; v_first_w date; v_last_w date;
        v_prior int; v_total numeric(5,1);
begin
  if new.leave_type = 'Permission' then return new; end if;
  if tg_op = 'UPDATE' and new.from_date = old.from_date and new.to_date = old.to_date
     and new.is_half_day is not distinct from old.is_half_day
     and coalesce(current_setting('app.recalc_sandwich', true), '') <> 'on' then
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

  select min(dd), max(dd), count(*)
    into v_first_w, v_last_w, v_working
    from generate_series(new.from_date, new.to_date, interval '1 day') g(dd)
   where not public.is_non_working_day(new.employee_name, g.dd::date);

  d := new.from_date;
  while d <= new.to_date loop
    if public.is_non_working_day(new.employee_name, d)
       and v_first_w is not null and d > v_first_w and d < v_last_w then
      v_inside := v_inside + 1;
    end if;
    d := d + 1;
  end loop;

  new.sandwich_days := v_outside + v_inside;
  v_total := v_working + v_inside + v_outside;

  if coalesce(new.is_half_day,false) and (new.to_date = new.from_date) then
    v_total := 0.5;
    new.sandwich_days := 0;
  end if;
  if v_total < 0 then v_total := 0; end if;

  select coalesce(sum(sandwich_days),0) into v_prior from leave_applications
   where lower(btrim(employee_name)) = lower(btrim(new.employee_name))
     and leave_type <> 'Permission'
     and public.leave_is_live(manager_status, management_status)
     and id is distinct from new.id
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date);

  if new.sandwich_days > 0 and v_prior > 0 then
    new.lop_days := ceil(v_total);
  else
    new.lop_days := greatest(ceil(v_total) - 2, 0);
  end if;

  new.days := v_total;
  return new;
end;
$$;

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

  select coalesce(sum(permission_minutes),0) into v_used from leave_applications
   where leave_type='Permission' and id is distinct from new.id
     and public.leave_is_live(manager_status, management_status)
     and public.attendance_cycle_start(from_date) = public.attendance_cycle_start(new.from_date)
     and ((coalesce(new.employee_id,'') <> '' and employee_id = new.employee_id)
       or (coalesce(new.employee_id,'') =  '' and lower(btrim(employee_name)) = lower(btrim(new.employee_name))));

  new.permission_lop_half_day := (v_used + new.permission_minutes > v_quota);

  return new;
end;
$$;

-- ── 2. Probation: beyond one paid day per cycle is LOP, not refused ─────────
create or replace function public.enforce_probation_leave_rules()
returns trigger
language plpgsql
as $$
declare
  v_used numeric := 0;
  v_this numeric;
  v_lop  numeric;
begin
  if coalesce(public.is_exempt_from_leave_rules(new.employee_id, new.employee_name), false) then
    return new;
  end if;
  if new.leave_type = 'Permission' or new.leave_type ilike '%comp%off%' then
    return new;
  end if;
  if coalesce(public.is_employee_confirmed(new.employee_id, new.employee_name), false) then
    return new;
  end if;
  if not public.leave_is_live(new.manager_status, new.management_status) then
    return new;
  end if;
  -- Decided when the request is made or its dates change, not again on
  -- every approval: an approval must not move the paid / LOP split.
  if tg_op = 'UPDATE'
     and new.from_date = old.from_date and new.to_date = old.to_date
     and new.is_half_day is not distinct from old.is_half_day
     and new.leave_type = old.leave_type then
    return new;
  end if;

  -- Paid leave already taken in this cycle by requests made before this one.
  select coalesce(sum(greatest(0,
           (case when l.is_half_day then 0.5 else l.days end) - coalesce(l.lop_days, 0))), 0)
    into v_used
    from leave_applications l
   where l.id is distinct from new.id
     and l.leave_type <> 'Permission'
     and l.leave_type not ilike '%comp%off%'
     and public.leave_is_live(l.manager_status, l.management_status)
     and public.attendance_cycle_start(l.from_date) = public.attendance_cycle_start(new.from_date)
     and (l.applied_on < coalesce(new.applied_on, now())
          or (l.applied_on = new.applied_on and l.id < new.id))
     and ((coalesce(new.employee_id,'') <> '' and l.employee_id = new.employee_id)
       or (coalesce(new.employee_id,'') =  '' and lower(btrim(l.employee_name)) = lower(btrim(new.employee_name))));

  v_this := case when coalesce(new.is_half_day, false) then 0.5 else coalesce(new.days, 0) end;
  v_lop  := greatest(0, v_this - greatest(0, 1 - v_used));
  new.lop_days := greatest(coalesce(new.lop_days, 0), v_lop);
  return new;
end;
$$;

-- ── 4. Accrual from the confirmation date, for confirmations from now on ───
alter table public.app_users add column if not exists leave_accrual_from date;

comment on column public.app_users.leave_accrual_from is
  'Leave accrues from the attendance cycle containing this date. Set when an employee is confirmed (from 19 Nov 2026). Null: the older rule, from the leave year or date of joining.';

create or replace function public.set_leave_accrual_from()
returns trigger
language plpgsql
as $$
begin
  if coalesce(btrim(new.onroll_confirmed_at), '') <> ''
     and coalesce(btrim(old.onroll_confirmed_at), '') = '' then
    new.leave_accrual_from := coalesce(new.leave_accrual_from,
      public.try_timestamptz(new.onroll_confirmed_at)::date, current_date);
  elsif coalesce(btrim(new.onroll_confirmed_at), '') = ''
        and coalesce(btrim(old.onroll_confirmed_at), '') <> '' then
    -- Confirmation undone: back on probation.
    new.leave_accrual_from := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_leave_accrual_from on public.app_users;
create trigger trg_set_leave_accrual_from
  before update of onroll_confirmed_at on public.app_users
  for each row execute function public.set_leave_accrual_from();

-- ── 3 + 4. The balance ──────────────────────────────────────────────────────
create or replace function public.leave_balance(p_employee_id text, p_date date default current_date)
returns table(bucket text, accrued numeric, used numeric, adjusted numeric, available numeric, usable numeric, cap numeric)
language sql
stable
as $$
  with emp as (
    select u.employee_id,
           nullif(u.date_of_joining,'')::date as doj,
           coalesce(u.onroll_confirmed_at,'') <> '' as confirmed,
           coalesce(u.exempt_from_leave_rules,false) as unlimited,
           u.leave_accrual_from
      from app_users u where u.employee_id = p_employee_id
  ),
  n as (
    select e.*,
           (not e.confirmed and not e.unlimited) as probation,
           -- Where the counting starts. Probation: this cycle only (CL lapses
           -- on the 25th). Confirmed from 19 Nov 2026 on: the cycle the
           -- confirmation falls in. Otherwise the leave year, as before.
           case when not e.confirmed and not e.unlimited
                  then public.attendance_cycle_start(p_date)
                when e.leave_accrual_from is not null
                  then greatest(public.leave_year_start(p_date),
                                public.attendance_cycle_start(e.leave_accrual_from))
                else public.leave_year_start(p_date) end as window_start,
           public.cycles_accrued(coalesce(e.leave_accrual_from, e.doj), p_date) as cycles
      from emp e
  ),
  accrual as (
    select 'CL' as bucket,
           case when n.unlimited then 9999 when n.probation then 1 else n.cycles end::numeric as accrued,
           case when n.unlimited then 9999 when n.probation then 1 else 2 end::numeric as cap
      from n
    union all
    select 'ML',
           case when n.unlimited then 9999
                when n.confirmed then n.cycles else 0 end::numeric, 9999::numeric
      from n
    union all
    select 'EL',
           case when n.unlimited then 9999
                when n.confirmed then least(n.cycles, 25) else 0 end::numeric, 9999::numeric
      from n
  ),
  used as (
    select l.bucket, sum(l.days)::numeric as used
      from (
        select coalesce(nullif(la.leave_bucket,''),
                        case when la.leave_type ilike '%medical%'
                               or la.leave_type ilike '%sick%' then 'ML'
                             when la.leave_type ilike '%earned%' then 'EL'
                             when la.leave_type ilike '%lop%'    then 'LOP'
                             else 'CL' end) as bucket,
               greatest(0, (case when la.is_half_day then 0.5 else la.days end) - coalesce(la.lop_days, 0)) as days
          from leave_applications la, n
         where la.employee_id = p_employee_id
           and la.leave_type <> 'Permission'
           and la.leave_type not ilike '%comp%off%'
           and case when la.management_status <> 'pending'
                    then la.management_status else la.manager_status end = 'approved'
           and la.from_date >= n.window_start
           and la.from_date <= p_date
      ) l group by l.bucket
  ),
  adj as (
    select a.bucket, sum(a.days)::numeric as adjusted
      from leave_adjustments a, n
     where a.employee_id = p_employee_id
       and a.effective_on >= n.window_start
       and a.effective_on <= p_date
     group by a.bucket
  ),
  calc as (
    select ac.bucket, ac.accrued, ac.cap,
           coalesce(us.used,0) as used,
           coalesce(ad.adjusted,0) as adjusted,
           case when ac.accrued >= 9999 then 9999
                else greatest(0, ac.accrued + coalesce(ad.adjusted,0) - coalesce(us.used,0))
           end as available
      from accrual ac
      left join used us on us.bucket = ac.bucket
      left join adj  ad on ad.bucket = ac.bucket
  )
  select bucket, accrued, used, adjusted, available,
         least(available, cap) as usable, cap
    from calc
   order by case bucket when 'CL' then 1 when 'ML' then 2 else 3 end;
$$;

-- ── 5. Corrections: HR proposes, Management approves ────────────────────────
create table if not exists public.leave_corrections (
  id               bigint generated always as identity primary key,
  leave_id         text not null references public.leave_applications(id) on delete cascade,
  previous         jsonb not null,
  proposed         jsonb not null,
  reason           text not null,
  proposed_by      text not null,
  proposed_at      timestamptz not null default now(),
  status           text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_by       text,
  decided_at       timestamptz,
  decision_note    text,
  leave_approved   boolean not null default false
);
create unique index if not exists leave_corrections_one_pending
  on public.leave_corrections (leave_id) where status = 'pending';

alter table public.leave_corrections enable row level security;
create policy leave_corrections_read on public.leave_corrections
  for select to authenticated
  using (current_app_is_hr_or_mgmt()
         or exists (select 1 from leave_applications l
                     where l.id = leave_id and l.employee_id = current_app_employee_id()));

create or replace function public.propose_leave_correction(
  p_leave_id    text,
  p_leave_type  text,
  p_bucket      text,
  p_from        date,
  p_to          date,
  p_half_day    boolean,
  p_reason      text)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v leave_applications%rowtype;
  v_id bigint;
begin
  if not current_app_is_hr_or_mgmt() then
    raise exception 'Only HR can propose a correction to a leave';
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'Give a reason for the correction';
  end if;
  select * into v from leave_applications where id = p_leave_id;
  if not found then raise exception 'Leave request % not found', p_leave_id; end if;
  if v.leave_type = 'Permission' then
    raise exception 'A permission cannot be corrected this way';
  end if;
  if p_bucket is not null and p_bucket not in ('CL','ML','EL','LOP') then
    raise exception 'Balance must be CL, ML, EL or LOP';
  end if;
  if coalesce(p_to, v.to_date) < coalesce(p_from, v.from_date) then
    raise exception 'The end date is before the start date';
  end if;
  if coalesce(p_half_day, v.is_half_day) and coalesce(p_from, v.from_date) <> coalesce(p_to, v.to_date) then
    raise exception 'A half day must be a single date';
  end if;
  if exists (select 1 from leave_corrections where leave_id = p_leave_id and status = 'pending') then
    raise exception 'A correction for this leave is already waiting for Management';
  end if;

  insert into leave_corrections(leave_id, previous, proposed, reason, proposed_by)
  values (p_leave_id,
          jsonb_build_object('leave_type', v.leave_type, 'leave_bucket', v.leave_bucket,
                             'from_date', v.from_date, 'to_date', v.to_date,
                             'is_half_day', v.is_half_day, 'days', v.days),
          jsonb_build_object('leave_type', coalesce(nullif(btrim(p_leave_type),''), v.leave_type),
                             'leave_bucket', coalesce(p_bucket, v.leave_bucket),
                             'from_date', coalesce(p_from, v.from_date),
                             'to_date', coalesce(p_to, v.to_date),
                             'is_half_day', coalesce(p_half_day, v.is_half_day)),
          btrim(p_reason), coalesce(current_app_email(), 'unknown'))
  returning id into v_id;

  insert into notifications(type, title, body, route, target_role, source_id)
  values ('leave_correction_proposed',
          format('Leave correction for %s needs approval', v.employee_name),
          format('%s on %s: %s', v.leave_type, to_char(v.from_date, 'DD Mon'), btrim(p_reason)),
          '/management/leave/approvals', 'Management', 'leave_correction_' || v_id);

  perform log_audit_event('leave_correction_proposed', 'leave_applications', p_leave_id,
    jsonb_build_object('correction_id', v_id, 'reason', p_reason));
  return v_id;
end;
$$;
revoke all on function public.propose_leave_correction(text, text, text, date, date, boolean, text) from public, anon;
grant execute on function public.propose_leave_correction(text, text, text, date, date, boolean, text) to authenticated;

create or replace function public.decide_leave_correction(
  p_id             bigint,
  p_approve        boolean,
  p_note           text default null,
  p_approve_leave  boolean default false)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  c leave_corrections%rowtype;
  v leave_applications%rowtype;
  v_name text;
  v_email text;
begin
  if not public.is_management_authority(coalesce(current_app_role(), '')) then
    raise exception 'Only Management can approve a leave correction';
  end if;
  select * into c from leave_corrections where id = p_id for update;
  if not found then raise exception 'Correction % not found', p_id; end if;
  if c.status <> 'pending' then raise exception 'This correction has already been decided'; end if;
  select name into v_name from app_users where lower(email) = current_app_email() limit 1;

  if p_approve then
    update leave_applications l
       set leave_type   = c.proposed->>'leave_type',
           leave_bucket = c.proposed->>'leave_bucket',
           from_date    = (c.proposed->>'from_date')::date,
           to_date      = (c.proposed->>'to_date')::date,
           is_half_day  = (c.proposed->>'is_half_day')::boolean,
           management_status     = case when p_approve_leave then 'approved' else l.management_status end,
           management_decided_by = case when p_approve_leave then coalesce(v_name, current_app_email()) else l.management_decided_by end
     where l.id = c.leave_id;
  end if;

  update leave_corrections
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = coalesce(current_app_email(), 'unknown'),
         decided_at = now(),
         decision_note = nullif(btrim(p_note), ''),
         leave_approved = p_approve and p_approve_leave
   where id = p_id;

  select * into v from leave_applications where id = c.leave_id;
  select email into v_email from app_users where employee_id = v.employee_id limit 1;
  if p_approve and v_email is not null then
    insert into notifications(type, title, body, route, target_email, source_id)
    values ('leave_corrected',
            'Your leave request was corrected',
            format('Now %s on %s%s. Reason: %s', v.leave_type, to_char(v.from_date, 'DD Mon'),
                   case when p_approve_leave then ', and approved' else '' end, c.reason),
            '', v_email, 'leave_correction_' || p_id);
  end if;

  perform log_audit_event(
    case when p_approve then 'leave_correction_approved' else 'leave_correction_rejected' end,
    'leave_applications', c.leave_id,
    jsonb_build_object('correction_id', p_id, 'note', p_note, 'leave_approved', p_approve and p_approve_leave,
                       'previous', c.previous, 'proposed', c.proposed));
end;
$$;
revoke all on function public.decide_leave_correction(bigint, boolean, text, boolean) from public, anon;
grant execute on function public.decide_leave_correction(bigint, boolean, text, boolean) to authenticated;
