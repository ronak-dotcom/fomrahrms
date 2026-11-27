-- Employee exits: last working day, approval, automatic account close, and
-- the Full & Final settlement. Rules agreed with Ronak on 25 Nov 2026; see
-- the HRMS project doc "Employee exit, last working day and Full & Final
-- settlement".
--
-- HR records an exit, Management approves it. The person keeps access up to
-- the end of their last working day; that night the account is closed and
-- the login email archived so it can be reissued. Their final month is paid
-- through the monthly payroll for days up to the last working day only. The
-- F&F statement (EL encashment, gratuity, other lines) is prepared by HR,
-- approved by Management and marked paid by HR.

create table if not exists public.employee_exits (
  id                   uuid primary key default gen_random_uuid(),
  employee_id          text not null,
  employee_name        text not null default '',
  employee_email       text not null default '',
  exit_type            text not null
                         check (exit_type in ('resigned','terminated','absconded','other')),
  -- The day notice started. Resignations only.
  resignation_date     date,
  last_working_day     date not null,
  reason               text not null,
  notice_days_required integer not null default 30 check (notice_days_required >= 0),
  -- Management agreed to relieve them early; counts as notice served.
  notice_waived        boolean not null default false,
  -- pay: in the monthly payroll as usual. hold: in payroll but the payslip
  -- cannot be published until Management decides. withhold: not paid.
  -- settled: paid outside the app; left out of payroll.
  final_salary         text not null default 'pay'
                         check (final_salary in ('pay','hold','withhold','settled')),
  -- pay, hold (until Management decides) or forfeit (resigned without
  -- serving notice, HR policy as agreed 25 Nov 2026).
  fnf                  text not null default 'pay'
                         check (fnf in ('pay','hold','forfeit')),
  status               text not null default 'pending'
                         check (status in ('pending','approved','rejected','cancelled')),
  requested_by         text not null default '',
  requested_at         timestamptz not null default now(),
  decided_by           text not null default '',
  decided_at           timestamptz,
  decision_note        text not null default '',
  account_closed_at    timestamptz,
  fnf_status           text not null default 'draft'
                         check (fnf_status in ('draft','approved','paid')),
  fnf_total            numeric,
  fnf_lines            jsonb,
  fnf_approved_by      text not null default '',
  fnf_approved_at      timestamptz,
  fnf_paid_by          text not null default '',
  fnf_paid_at          timestamptz,
  fnf_payment_note     text not null default ''
);

-- One open exit per person.
create unique index if not exists employee_exits_one_open
  on public.employee_exits (employee_id) where status in ('pending','approved');

alter table public.employee_exits enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies
                  where schemaname='public' and tablename='employee_exits'
                    and policyname='employee_exits_hr_mgmt_read') then
    create policy employee_exits_hr_mgmt_read on public.employee_exits
      for select to authenticated using (public.current_app_is_hr_or_mgmt());
  end if;
end $$;
grant select on public.employee_exits to authenticated;

-- Extra lines on the F&F statement: positive pays the leaver, negative is a
-- recovery (company property lost or damaged, advance outstanding, ...).
-- Lines are voided rather than removed, so the statement's history stays.
create table if not exists public.exit_fnf_items (
  id         uuid primary key default gen_random_uuid(),
  exit_id    uuid not null references public.employee_exits(id),
  label      text not null,
  amount     numeric not null,
  note       text not null default '',
  added_by   text not null default '',
  added_at   timestamptz not null default now(),
  voided     boolean not null default false,
  voided_by  text not null default '',
  voided_at  timestamptz
);
alter table public.exit_fnf_items enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies
                  where schemaname='public' and tablename='exit_fnf_items'
                    and policyname='exit_fnf_items_hr_mgmt_read') then
    create policy exit_fnf_items_hr_mgmt_read on public.exit_fnf_items
      for select to authenticated using (public.current_app_is_hr_or_mgmt());
  end if;
end $$;
grant select on public.exit_fnf_items to authenticated;

-- ── Helpers ───────────────────────────────────────────────────────────────

create or replace function public.employee_last_working_day(p_employee_id text)
returns date language sql stable security definer set search_path to 'public' as $$
  select x.last_working_day from public.employee_exits x
   where x.employee_id = p_employee_id and x.status = 'approved'
   order by x.requested_at desc limit 1;
$$;

-- HR policy 6.1: DGM and above 60 days, Jr. Executive to Senior Manager 30,
-- probationers (not yet confirmed on-roll) 15.
create or replace function public.exit_notice_default(p_employee_id text)
returns integer language sql stable security definer set search_path to 'public' as $$
  select case
           when coalesce(u.onroll_confirmed_at, '') = '' then 15
           when u.designation ilike any (array['%general manager%', '%chief%',
                  '%head of%', '%director%', '%vice president%', '%dgm%'])
             then 60
           else 30 end
    from public.app_users u where u.employee_id = p_employee_id limit 1;
$$;

-- Notice short, in days, for a resignation that Management has not waived.
create or replace function public.exit_notice_short(x public.employee_exits)
returns integer language sql immutable as $$
  select case when x.exit_type <> 'resigned' or x.notice_waived
                or x.resignation_date is null then 0
              else greatest(0, x.notice_days_required
                               - ((x.last_working_day - x.resignation_date) + 1)) end;
$$;

-- Payroll: the leaver's final month is not paid at all.
create or replace function public.payroll_final_salary_excluded(p_employee_id text, p_cycle_end date)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.employee_exits x
     where x.employee_id = p_employee_id and x.status = 'approved'
       and x.final_salary in ('withhold','settled')
       and x.last_working_day between public.attendance_cycle_start(p_cycle_end)
                                  and public.attendance_cycle_end(p_cycle_end));
$$;

-- Payslips: drafted as usual but not published until Management decides.
create or replace function public.payroll_final_salary_held(p_employee_id text, p_cycle_end date)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.employee_exits x
     where x.employee_id = p_employee_id and x.status = 'approved'
       and x.final_salary = 'hold'
       and x.last_working_day between public.attendance_cycle_start(p_cycle_end)
                                  and public.attendance_cycle_end(p_cycle_end));
$$;

-- ── Recording and deciding ────────────────────────────────────────────────

create or replace function public.record_exit(
  p_employee_id      text,
  p_exit_type        text,
  p_resignation_date date,
  p_last_working_day date,
  p_reason           text,
  p_notice_days      integer default null)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare
  u    public.app_users%rowtype;
  v_id uuid;
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can record an exit' using errcode = '42501';
  end if;
  select * into u from public.app_users where employee_id = btrim(p_employee_id) limit 1;
  if not found then
    raise exception 'No employee with ID %', p_employee_id;
  end if;
  if p_exit_type not in ('resigned','terminated','absconded','other') then
    raise exception 'Unknown exit type %', p_exit_type;
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'Please give the reason for the exit.';
  end if;
  if p_last_working_day is null then
    raise exception 'Please give the last working day.';
  end if;
  if nullif(u.date_of_joining, '') is not null
     and p_last_working_day < u.date_of_joining::date then
    raise exception 'The last working day is before % joined (%).', u.name, u.date_of_joining;
  end if;
  if p_exit_type = 'resigned' then
    if p_resignation_date is null then
      raise exception 'Please give the date % resigned.', u.name;
    end if;
    if p_resignation_date > p_last_working_day then
      raise exception 'The resignation date is after the last working day.';
    end if;
  end if;
  if exists (select 1 from public.employee_exits x
              where x.employee_id = u.employee_id and x.status in ('pending','approved')) then
    raise exception 'An exit is already recorded for %.', u.name;
  end if;

  insert into public.employee_exits
    (employee_id, employee_name, employee_email, exit_type, resignation_date,
     last_working_day, reason, notice_days_required, requested_by)
  values
    (u.employee_id, u.name, u.email, p_exit_type,
     case when p_exit_type = 'resigned' then p_resignation_date end,
     p_last_working_day, btrim(p_reason),
     coalesce(p_notice_days, public.exit_notice_default(u.employee_id), 30),
     coalesce(public.current_app_email(), ''))
  returning id into v_id;

  insert into public.notifications (type, title, body, route, target_role, source_id)
  values ('exit_recorded', 'Exit to approve',
          u.name || ' — last working day ' || to_char(p_last_working_day, 'DD Mon YYYY'),
          '/management/exits', 'Management', v_id::text);

  perform public.log_audit_event('exit_recorded', 'employee_exits', u.employee_id,
    jsonb_build_object('exit_id', v_id, 'type', p_exit_type,
                       'last_working_day', p_last_working_day));
  return v_id;
end $$;

-- Closes the leaver's account: sign-in stops, push is revoked, the employee
-- ID is retired and the login email archived for reuse. Runs the night of
-- the last working day, or at once when the exit is approved afterwards.
create or replace function public._close_exit_account(p_exit_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
declare
  x public.employee_exits%rowtype;
  u public.app_users%rowtype;
  v_reason text;
begin
  select * into x from public.employee_exits where id = p_exit_id;
  if not found or x.status <> 'approved' or x.account_closed_at is not null then
    return;
  end if;
  select * into u from public.app_users where employee_id = x.employee_id limit 1;
  if found then
    -- retire_employee and release_login_email check the caller is HR or
    -- Management. At night nobody is signed in, so they run as the person
    -- who approved the exit, who also appears in the audit log.
    if not public.current_app_is_hr_or_mgmt() then
      perform set_config('request.jwt.claims',
        jsonb_build_object('email', x.decided_by, 'role', 'authenticated')::text, true);
    end if;
    v_reason := 'Exit - last working day ' || to_char(x.last_working_day, 'DD Mon YYYY');
    if coalesce(u.active, false) then
      perform public.retire_employee(u.email, v_reason);
    end if;
    if u.email not ilike '%@exited.fomrahousing.in' then
      perform public.release_login_email(u.email, v_reason);
    end if;
  end if;
  update public.employee_exits set account_closed_at = now() where id = p_exit_id;
end $$;
revoke all on function public._close_exit_account(uuid) from public, anon, authenticated;

-- Management approves, or changes an earlier decision on an approved exit
-- (for example releasing a held final salary). Arguments left null keep
-- the rule's default.
create or replace function public.approve_exit(
  p_exit_id       uuid,
  p_notice_waived boolean default null,
  p_final_salary  text default null,
  p_fnf           text default null,
  p_note          text default null)
returns public.employee_exits language plpgsql security definer set search_path to 'public' as $$
declare
  x       public.employee_exits%rowtype;
  v_short integer;
  v_final text;
  v_fnf   text;
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if not public.is_management_authority(coalesce(public.current_app_role(), '')) then
    raise exception 'Only Management can approve an exit' using errcode = '42501';
  end if;
  select * into x from public.employee_exits where id = p_exit_id for update;
  if not found or x.status not in ('pending','approved') then
    raise exception 'This exit is not open.';
  end if;
  if x.fnf_status <> 'draft' and (p_fnf is not null or p_notice_waived is not null) then
    raise exception 'The F&F has already been approved.';
  end if;

  x.notice_waived := coalesce(p_notice_waived, x.notice_waived);
  v_short := public.exit_notice_short(x);

  -- Defaults by exit type (agreed 25 Nov 2026).
  v_final := case x.exit_type
               when 'absconded' then 'hold'
               when 'resigned'  then case when v_short > 0 then 'hold' else 'pay' end
               else 'pay' end;
  v_fnf   := case x.exit_type when 'absconded' then 'hold' else 'pay' end;
  if x.status = 'approved' then
    v_final := x.final_salary;
    v_fnf   := case when x.fnf = 'forfeit' then 'pay' else x.fnf end;
  end if;
  v_final := coalesce(p_final_salary, v_final);
  v_fnf   := coalesce(p_fnf, v_fnf);
  -- Resigned without serving notice: not eligible for the F&F.
  if v_short > 0 then v_fnf := 'forfeit'; end if;

  if v_final not in ('pay','hold','withhold','settled') then
    raise exception 'Unknown final salary decision %', v_final;
  end if;
  if v_fnf not in ('pay','hold','forfeit') then
    raise exception 'Unknown F&F decision %', v_fnf;
  end if;

  update public.employee_exits
     set status = 'approved', notice_waived = x.notice_waived,
         final_salary = v_final, fnf = v_fnf,
         decided_by = coalesce(public.current_app_email(), ''),
         decided_at = now(),
         decision_note = coalesce(nullif(btrim(p_note), ''), decision_note)
   where id = p_exit_id
  returning * into x;

  perform public.log_audit_event('exit_approved', 'employee_exits', x.employee_id,
    jsonb_build_object('exit_id', x.id, 'final_salary', v_final, 'fnf', v_fnf,
                       'notice_waived', x.notice_waived, 'notice_short', v_short));

  insert into public.notifications (type, title, body, route, target_role, source_id)
  values ('exit_approved', 'Exit approved',
          x.employee_name || ' — last working day ' || to_char(x.last_working_day, 'DD Mon YYYY'),
          '/exits', 'HR', x.id::text);

  -- Approved after the last working day: nothing left to wait for.
  if x.last_working_day < v_today then
    perform public._close_exit_account(x.id);
    select * into x from public.employee_exits where id = p_exit_id;
  end if;
  return x;
end $$;

create or replace function public.reject_exit(p_exit_id uuid, p_note text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare x public.employee_exits%rowtype;
begin
  if not public.is_management_authority(coalesce(public.current_app_role(), '')) then
    raise exception 'Only Management can reject an exit' using errcode = '42501';
  end if;
  update public.employee_exits
     set status = 'rejected', decided_by = coalesce(public.current_app_email(), ''),
         decided_at = now(), decision_note = coalesce(btrim(p_note), '')
   where id = p_exit_id and status = 'pending'
  returning * into x;
  if not found then raise exception 'This exit is not waiting for approval.'; end if;
  perform public.log_audit_event('exit_rejected', 'employee_exits', x.employee_id,
    jsonb_build_object('exit_id', x.id, 'note', p_note));
end $$;

-- Withdrawn (e.g. resignation taken back). Possible until the account closes.
create or replace function public.cancel_exit(p_exit_id uuid, p_note text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare x public.employee_exits%rowtype;
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can withdraw an exit' using errcode = '42501';
  end if;
  update public.employee_exits
     set status = 'cancelled', decision_note = coalesce(btrim(p_note), '')
   where id = p_exit_id and status in ('pending','approved') and account_closed_at is null
  returning * into x;
  if not found then
    raise exception 'This exit can no longer be withdrawn: the account is already closed.';
  end if;
  perform public.log_audit_event('exit_cancelled', 'employee_exits', x.employee_id,
    jsonb_build_object('exit_id', x.id, 'note', p_note));
end $$;

create or replace function public.close_exited_accounts()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare r record; n integer := 0;
begin
  for r in
    select id from public.employee_exits
     where status = 'approved' and account_closed_at is null
       and last_working_day <= (now() at time zone 'Asia/Kolkata')::date
  loop
    perform public._close_exit_account(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.close_exited_accounts() from public, anon, authenticated;

-- ── Full & Final statement ────────────────────────────────────────────────

create or replace function public.fnf_statement(p_exit_id uuid)
returns table(sort integer, kind text, label text, amount numeric, note text)
language plpgsql stable security definer set search_path to 'public' as $$
declare
  x       public.employee_exits%rowtype;
  u       public.app_users%rowtype;
  v_basic numeric := 0;
  v_doj   date;
  v_years integer := 0;
  v_svc   interval;
  v_el    numeric := 0;
  v_dim   integer;
  v_enc   numeric := 0;
  v_grat  numeric := 0;
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can see an F&F statement' using errcode = '42501';
  end if;
  select * into x from public.employee_exits where id = p_exit_id;
  if not found then raise exception 'No such exit'; end if;
  select * into u from public.app_users where employee_id = x.employee_id limit 1;
  select coalesce(s.basic, 0) into v_basic
    from public.salary_structures s where s.employee_id = x.employee_id;
  v_basic := coalesce(v_basic, 0);
  v_doj   := nullif(u.date_of_joining, '')::date;
  if v_doj is not null then
    v_svc   := age(x.last_working_day + 1, v_doj);
    v_years := extract(year from v_svc)::int;
  end if;
  v_dim := extract(day from (date_trunc('month', x.last_working_day)
                             + interval '1 month - 1 day'))::int;
  select coalesce(b.available, 0) into v_el
    from public.leave_balance(x.employee_id, x.last_working_day) b where b.bucket = 'EL';
  v_el := coalesce(v_el, 0);

  -- HR policy 3.5, as in service: 2+ years, and the last 10 days are not paid.
  if v_years >= 2 then
    v_enc := round(greatest(0, v_el - 10) * v_basic / v_dim, 2);
  end if;
  -- HR policy 4: 5+ years of continuous service.
  if v_years >= 5 then
    v_grat := round(v_basic * 15 * v_years / 30, 2);
  end if;

  sort := 1; kind := 'earning'; label := 'EL encashment';
  amount := v_enc;
  note := case when v_doj is null then 'No date of joining on record'
               when v_years < 2 then 'Not eligible: under 2 years of service'
               else trim(to_char(greatest(0, v_el - 10), 'FM990.0')) || ' of '
                    || trim(to_char(v_el, 'FM990.0')) || ' EL days (last 10 kept) x basic '
                    || v_basic || ' / ' || v_dim || ' days' end;
  return next;

  sort := 2; kind := 'earning'; label := 'Gratuity';
  amount := v_grat;
  note := case when v_years < 5 then 'Not eligible: under 5 years of service'
               else 'Basic ' || v_basic || ' x 15 x ' || v_years || ' years / 30' end;
  return next;

  return query
    select 10 + (row_number() over (order by i.added_at))::int,
           case when i.amount >= 0 then 'earning' else 'deduction' end,
           i.label, i.amount, i.note
      from public.exit_fnf_items i
     where i.exit_id = p_exit_id and not i.voided
     order by i.added_at;

  sort := 90; kind := 'info'; label := 'CL and ML';
  amount := 0; note := 'Lapse on exit (HR policy 3.11)';
  return next;

  sort := 91; kind := 'info'; label := 'Final month''s salary';
  amount := 0;
  note := case x.final_salary
            when 'pay'      then 'Paid in the monthly payroll, for days up to the last working day'
            when 'hold'     then 'Held until Management decides'
            when 'withhold' then 'Withheld by Management'
            else 'Settled outside the app' end;
  return next;

  sort := 99; kind := 'total'; label := 'Net F&F payable';
  select case when x.fnf = 'forfeit' then 0 else coalesce(sum(s.a), 0) end into amount
    from (select v_enc as a union all select v_grat
          union all select i.amount from public.exit_fnf_items i
                     where i.exit_id = p_exit_id and not i.voided) s;
  note := case x.fnf
            when 'forfeit' then 'Not eligible: resigned without serving notice'
            when 'hold'    then 'Held until Management decides'
            else '' end;
  return next;
end $$;

create or replace function public.add_fnf_item(p_exit_id uuid, p_label text, p_amount numeric, p_note text)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid;
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can change an F&F' using errcode = '42501';
  end if;
  if not exists (select 1 from public.employee_exits
                  where id = p_exit_id and status = 'approved' and fnf_status = 'draft') then
    raise exception 'This F&F can no longer be changed.';
  end if;
  if coalesce(btrim(p_label), '') = '' or p_amount is null or p_amount = 0 then
    raise exception 'Give a description and a non-zero amount.';
  end if;
  insert into public.exit_fnf_items (exit_id, label, amount, note, added_by)
  values (p_exit_id, btrim(p_label), p_amount, coalesce(btrim(p_note), ''),
          coalesce(public.current_app_email(), ''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.void_fnf_item(p_item_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can change an F&F' using errcode = '42501';
  end if;
  update public.exit_fnf_items i
     set voided = true, voided_by = coalesce(public.current_app_email(), ''), voided_at = now()
   where i.id = p_item_id and not i.voided
     and exists (select 1 from public.employee_exits x
                  where x.id = i.exit_id and x.fnf_status = 'draft');
  if not found then raise exception 'This line can no longer be changed.'; end if;
end $$;

create or replace function public.approve_fnf(p_exit_id uuid)
returns numeric language plpgsql security definer set search_path to 'public' as $$
declare x public.employee_exits%rowtype; v_total numeric; v_lines jsonb;
begin
  if not public.is_management_authority(coalesce(public.current_app_role(), '')) then
    raise exception 'Only Management can approve an F&F' using errcode = '42501';
  end if;
  select * into x from public.employee_exits where id = p_exit_id for update;
  if not found or x.status <> 'approved' or x.fnf_status <> 'draft' then
    raise exception 'This F&F is not waiting for approval.';
  end if;
  if x.fnf = 'hold' then
    raise exception 'Decide first whether the F&F is paid (it is on hold).';
  end if;
  select jsonb_agg(to_jsonb(s) order by s.sort) into v_lines from public.fnf_statement(p_exit_id) s;
  select s.amount into v_total from public.fnf_statement(p_exit_id) s where s.kind = 'total';
  update public.employee_exits
     set fnf_status = 'approved', fnf_total = v_total, fnf_lines = v_lines,
         fnf_approved_by = coalesce(public.current_app_email(), ''), fnf_approved_at = now()
   where id = p_exit_id;
  perform public.log_audit_event('fnf_approved', 'employee_exits', x.employee_id,
    jsonb_build_object('exit_id', x.id, 'total', v_total));
  return v_total;
end $$;

create or replace function public.mark_fnf_paid(p_exit_id uuid, p_note text)
returns void language plpgsql security definer set search_path to 'public' as $$
declare x public.employee_exits%rowtype;
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can mark an F&F paid' using errcode = '42501';
  end if;
  update public.employee_exits
     set fnf_status = 'paid', fnf_paid_by = coalesce(public.current_app_email(), ''),
         fnf_paid_at = now(), fnf_payment_note = coalesce(btrim(p_note), '')
   where id = p_exit_id and fnf_status = 'approved'
  returning * into x;
  if not found then raise exception 'Approve the F&F before marking it paid.'; end if;
  perform public.log_audit_event('fnf_paid', 'employee_exits', x.employee_id,
    jsonb_build_object('exit_id', x.id, 'total', x.fnf_total, 'note', p_note));
end $$;

revoke all on function public.record_exit(text,text,date,date,text,integer) from anon;
revoke all on function public.approve_exit(uuid,boolean,text,text,text) from anon;
revoke all on function public.reject_exit(uuid,text) from anon;
revoke all on function public.cancel_exit(uuid,text) from anon;
revoke all on function public.fnf_statement(uuid) from anon;
revoke all on function public.add_fnf_item(uuid,text,numeric,text) from anon;
revoke all on function public.void_fnf_item(uuid) from anon;
revoke all on function public.approve_fnf(uuid) from anon;
revoke all on function public.mark_fnf_paid(uuid,text) from anon;
