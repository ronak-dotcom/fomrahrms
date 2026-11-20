-- Payslips are issued by the database, from the payroll engine.
--
-- Until now the payslip screen worked its own figures out in the app and
-- wrote them straight into `payslips`. Every saved payslip disagreed with
-- the payroll engine (generate_payroll), whose October 2026 figures HR has
-- checked against the salary sheet and confirmed (17 Nov 2026; the three
-- differences were paise, settled by rounding net pay to the rupee).
--
-- Now, agreed with HR and Management (Nov 2026):
--   * HR confirms the counts the system made for each person (CL, ML, EL,
--     comp off, permission, lates, LOP) and the database calculates the
--     payslip. Nobody types an amount. A wrong count is fixed at its source
--     (the leave, permission or attendance record), never on the payslip.
--   * Issuing makes DRAFTS. HR reviews them and then PUBLISHES; only then do
--     employees see the payslip and get the "payslip ready" notification.
--   * A payslip can only be issued once its cycle (26th to 25th) has closed,
--     and only for someone with a salary structure.
--   * Reissuing a published payslip keeps the old one in payslip_history.
--   * Only HR and Management write payslips. Employees read their own
--     published payslips, and can request one only for a closed cycle.

-- ── 1. What a payslip records ───────────────────────────────────────────
alter table public.payslips
  add column if not exists status text not null default 'published',
  add column if not exists source text not null default 'app',
  add column if not exists version integer not null default 1,
  add column if not exists cycle_start date,
  add column if not exists cycle_end date,
  add column if not exists attendance_working_days integer,
  add column if not exists days_present integer,
  add column if not exists gross_earned numeric,
  add column if not exists total_deductions numeric,
  add column if not exists net_pay numeric,
  add column if not exists rounded_off numeric,
  add column if not exists cl_used numeric,
  add column if not exists ml_used numeric,
  add column if not exists el_used numeric,
  add column if not exists comp_off_used numeric,
  add column if not exists lop_leave numeric,
  add column if not exists leave_lop numeric,
  add column if not exists permission_count integer,
  add column if not exists permission_minutes integer,
  add column if not exists late_count integer,
  add column if not exists late_lop numeric,
  add column if not exists permission_lop numeric,
  add column if not exists published_at timestamptz,
  add column if not exists published_by text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'payslips_status_check') then
    alter table public.payslips
      add constraint payslips_status_check check (status in ('draft', 'published'));
  end if;
end $$;

comment on column public.payslips.status is
  'draft: issued, waiting for HR to publish (employees cannot see it). published: visible to the employee.';
comment on column public.payslips.source is
  'engine: issued by issue_payslips() from generate_payroll(). app: written by the old payslip screen.';
comment on column public.payslips.net_pay is
  'Net pay as issued, rounded to the rupee. Use this rather than adding up the lines.';

-- What a payslip said before it was regenerated or reissued.
create table if not exists public.payslip_history (
  id          bigserial primary key,
  payslip_id  text not null,
  employee_id text,
  month_year  text,
  snapshot    jsonb not null,
  replaced_at timestamptz not null default now(),
  replaced_by text,
  reason      text
);
alter table public.payslip_history enable row level security;
drop policy if exists payslip_history_read on public.payslip_history;
create policy payslip_history_read on public.payslip_history
  for select to authenticated using (public.current_app_is_hr_or_mgmt());

-- ── 2. The figures for a cycle ──────────────────────────────────────────
-- One row per person on payroll: the counts HR confirms, and the money from
-- generate_payroll. The counts are the ones HR checked in the October 2026
-- workbook: leave days by balance (whole requests, as approved), the unpaid
-- part of that leave, permissions taken in the cycle, late arrivals.
create or replace function public._payslip_figures(p_cycle_end date)
returns table(
  employee_id text, employee_name text, designation text, department text,
  date_of_joining text, cycle_start date, cycle_end date, cycle_days integer,
  working_days integer, days_present integer,
  cl_used numeric, ml_used numeric, el_used numeric, comp_off_used numeric,
  lop_leave numeric, leave_lop numeric,
  permission_count integer, permission_minutes integer,
  late_count integer, late_lop numeric, permission_lop numeric,
  days_lost numeric, payable_days numeric,
  monthly_gross numeric, basic numeric, da numeric, hra numeric, conveyance numeric,
  other_allowance numeric, educational numeric, lta numeric, gross_earned numeric,
  professional_tax numeric, epf numeric, esi numeric, tds numeric,
  total_deductions numeric, net_pay numeric, rounded_off numeric,
  leave_details jsonb)
language sql
stable
security definer
set search_path to 'public'
as $$
  with b as (
    select public.attendance_cycle_start(p_cycle_end) as cs,
           public.attendance_cycle_end(p_cycle_end)   as ce
  ),
  g as (select * from public.generate_payroll(p_cycle_end)),
  r as (select * from public.attendance_cycle_report(p_cycle_end, null)),
  lv as (
    select l.employee_id,
           case when l.leave_type ilike '%comp%off%' then 'CO'
                when l.leave_bucket in ('CL', 'ML', 'EL', 'LOP') then l.leave_bucket
                when l.leave_type ilike '%medical%' or l.leave_type ilike '%sick%' then 'ML'
                when l.leave_type ilike '%earned%' then 'EL'
                when l.leave_type ilike '%lop%' then 'LOP'
                else 'CL' end as bucket,
           case when l.is_half_day then 0.5 else l.days end as d,
           coalesce(l.lop_days, 0) as lop
      from public.leave_applications l, b
     where l.granted
       and l.leave_type <> 'Permission'
       and l.from_date <= b.ce and l.to_date >= b.cs
  ),
  lva as (
    select lv.employee_id,
           coalesce(sum(lv.d) filter (where lv.bucket = 'CL'), 0)  as cl,
           coalesce(sum(lv.d) filter (where lv.bucket = 'ML'), 0)  as ml,
           coalesce(sum(lv.d) filter (where lv.bucket = 'EL'), 0)  as el,
           coalesce(sum(lv.d) filter (where lv.bucket = 'CO'), 0)  as co,
           coalesce(sum(lv.d) filter (where lv.bucket = 'LOP'), 0) as lopl,
           coalesce(sum(lv.lop), 0) as lp,
           coalesce(sum(greatest(0, lv.d - lv.lop)) filter (where lv.bucket = 'CL'), 0) as cl_paid,
           coalesce(sum(greatest(0, lv.d - lv.lop)) filter (where lv.bucket = 'ML'), 0) as ml_paid,
           coalesce(sum(greatest(0, lv.d - lv.lop)) filter (where lv.bucket = 'EL'), 0) as el_paid
      from lv group by lv.employee_id
  ),
  pm as (
    select l.employee_id, count(*)::int as n,
           coalesce(sum(l.permission_minutes), 0)::int as mins
      from public.leave_applications l, b
     where l.granted and l.leave_type = 'Permission'
       and l.from_date between b.cs and b.ce
     group by l.employee_id
  )
  select g.employee_code, g.employee_name, g.designation, g.department,
         g.date_of_joining, b.cs, b.ce, g.nwd,
         r.total_working_days, r.days_worked,
         coalesce(lva.cl, 0), coalesce(lva.ml, 0), coalesce(lva.el, 0),
         coalesce(lva.co, 0), coalesce(lva.lopl, 0), coalesce(lva.lp, 0),
         coalesce(pm.n, 0), coalesce(pm.mins, 0),
         g.late_count, g.late_lop, g.permission_lop,
         g.days_lost, g.nowd,
         g.actual_gross, g.basic, g.da, g.hra, g.conveyance,
         g.other_allowance, g.educational, g.lta, g.gross,
         g.professional_tax, coalesce(s.epf, 0), coalesce(s.esi, 0), coalesce(s.tds, 0),
         g.total_deductions, g.net_pay,
         g.net_pay - (g.gross - g.total_deductions),
         -- Leave balance on the payslip: what was left at the cycle end, and
         -- what this cycle's paid leave took from it.
         (select jsonb_agg(jsonb_build_object(
                    'type', lb.bucket,
                    'taken', case lb.bucket when 'CL' then coalesce(lva.cl_paid, 0)
                                            when 'ML' then coalesce(lva.ml_paid, 0)
                                            else coalesce(lva.el_paid, 0) end,
                    'opening', lb.available
                               + case lb.bucket when 'CL' then coalesce(lva.cl_paid, 0)
                                                when 'ML' then coalesce(lva.ml_paid, 0)
                                                else coalesce(lva.el_paid, 0) end)
                  order by array_position(array['CL', 'ML', 'EL'], lb.bucket))
            from public.leave_balance(g.employee_code, b.ce) lb
           where lb.bucket in ('CL', 'ML', 'EL'))
    from g
    cross join b
    join r on r.employee_code = g.employee_code
    left join lva on lva.employee_id = g.employee_code
    left join pm on pm.employee_id = g.employee_code
    left join public.salary_structures s on s.employee_id = g.employee_code
   order by g.employee_code;
$$;

-- ── 3. Issue drafts ─────────────────────────────────────────────────────
-- p_as_of is "today": a parameter so the tests can issue for their 2030
-- cycle. The public issue_payslips() passes today's date in India.
create or replace function public._issue_payslips(
  p_cycle_end date, p_employee_ids text[], p_reissue boolean, p_as_of date, p_actor text)
returns table(employee_id text, employee_name text, outcome text, net_pay numeric)
language plpgsql
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
declare
  v_cs    date := public.attendance_cycle_start(p_cycle_end);
  v_ce    date := public.attendance_cycle_end(p_cycle_end);
  v_label text := public.attendance_cycle_label(public.attendance_cycle_end(p_cycle_end));
  f       record;
  old     public.payslips%rowtype;
  v_id    text;
  v_ver   integer;
begin
  if v_ce >= p_as_of then
    raise exception 'The % cycle (% to %) has not closed yet. Its payslips can be issued from %.',
      to_char(v_ce, 'FMMonth YYYY'), to_char(v_cs, 'DD Mon'), to_char(v_ce, 'DD Mon YYYY'),
      to_char(v_ce + 1, 'DD Mon YYYY')
      using errcode = 'check_violation';
  end if;

  -- Asked for by name but no salary structure: say so, do not guess a figure.
  if p_employee_ids is not null then
    for f in
      select u.employee_id as eid, u.name as nm
        from public.app_users u
       where u.employee_id = any(p_employee_ids)
         and not exists (select 1 from public.salary_structures s where s.employee_id = u.employee_id)
    loop
      employee_id := f.eid; employee_name := f.nm;
      outcome := 'no_salary_structure'; net_pay := null;
      return next;
    end loop;
  end if;

  for f in
    select * from public._payslip_figures(v_ce) x
     where p_employee_ids is null or x.employee_id = any(p_employee_ids)
  loop
    v_id := f.employee_id || '_' || v_label;

    select * into old from public.payslips p
     where p.employee_id = f.employee_id and p.month_year = v_label
     order by (p.status = 'published') desc
     limit 1;
    if found and old.status = 'published' and not p_reissue then
      employee_id := f.employee_id; employee_name := f.employee_name;
      outcome := 'already_published'; net_pay := old.net_pay;
      return next;
      continue;
    end if;

    -- Keep whatever is being replaced, including a payslip for this month
    -- filed under another ID.
    v_ver := 1;
    for old in
      select * from public.payslips p
       where p.employee_id = f.employee_id and p.month_year = v_label
    loop
      insert into public.payslip_history(payslip_id, employee_id, month_year, snapshot, replaced_by, reason)
      values (old.id, old.employee_id, old.month_year, to_jsonb(old), p_actor,
              case when old.status = 'published' then 'reissued' else 'draft regenerated' end);
      v_ver := greatest(v_ver, coalesce(old.version, 1) + 1);
      delete from public.payslips p where p.id = old.id;
    end loop;

    insert into public.payslips(
      id, employee_id, month_year, emp_name, department, designation, band, date_of_joining,
      working_days, days_worked, lop_days, gross_pay,
      basic, da, hra, educational_allowance, lta, other_allowance, conveyance_allowance,
      special_allowance, epf, esi, professional_tax, tds, late_deductions, cug,
      excess_leave_deduction, leave_details, generated_at, generated_by,
      status, source, version, cycle_start, cycle_end, attendance_working_days, days_present,
      gross_earned, total_deductions, net_pay, rounded_off,
      cl_used, ml_used, el_used, comp_off_used, lop_leave, leave_lop,
      permission_count, permission_minutes, late_count, late_lop, permission_lop)
    values (
      v_id, f.employee_id, v_label, f.employee_name, f.department, f.designation, '', f.date_of_joining,
      f.cycle_days, f.payable_days, f.days_lost, f.monthly_gross,
      f.basic, f.da, f.hra, f.educational, f.lta, f.other_allowance, f.conveyance,
      0, f.epf, f.esi, f.professional_tax, f.tds, 0, 0,
      0, coalesce(f.leave_details, '[]'::jsonb)::text, now(), p_actor,
      'draft', 'engine', v_ver, f.cycle_start, f.cycle_end, f.working_days, f.days_present,
      f.gross_earned, f.total_deductions, f.net_pay, f.rounded_off,
      f.cl_used, f.ml_used, f.el_used, f.comp_off_used, f.lop_leave, f.leave_lop,
      f.permission_count, f.permission_minutes, f.late_count, f.late_lop, f.permission_lop);

    employee_id := f.employee_id; employee_name := f.employee_name;
    outcome := 'draft'; net_pay := f.net_pay;
    return next;
  end loop;
end;
$$;

-- ── 4. Publish ──────────────────────────────────────────────────────────
-- Makes drafts visible, tells each employee (the link opens their own
-- payslips page for their role), and settles any pending request for that
-- month.
create or replace function public._publish_payslips(
  p_cycle_end date, p_employee_ids text[], p_actor text)
returns table(employee_id text, employee_name text, outcome text, net_pay numeric)
language plpgsql
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
declare
  v_ce    date := public.attendance_cycle_end(p_cycle_end);
  v_label text := public.attendance_cycle_label(public.attendance_cycle_end(p_cycle_end));
  f       record;
begin
  for f in
    update public.payslips p
       set status = 'published', published_at = now(), published_by = p_actor
     where p.month_year = v_label and p.status = 'draft'
       and (p_employee_ids is null or p.employee_id = any(p_employee_ids))
    returning p.id as pid, p.employee_id as eid, p.emp_name as nm, p.net_pay as np
  loop
    insert into public.notifications(type, title, body, route, target_email, source_id)
    select 'payslip_ready', 'New payslip available',
           'Your payslip for ' || to_char(v_ce, 'FMMonth YYYY') || ' is ready.',
           case u.role when 'Employee' then '/employee/payslips'
                       when 'HR' then '/hr/my-payslips'
                       when 'Manager' then '/manager/my-payslips'
                       else '/management/my-payslips' end,
           u.email, f.pid
      from public.app_users u
     where u.employee_id = f.eid and coalesce(u.email, '') <> ''
     limit 1;

    update public.payslip_requests q
       set status = 'approved', decided_at = now(), decided_by = p_actor
     where q.employee_id = f.eid and q.month_year = v_label and q.status = 'pending';

    employee_id := f.eid; employee_name := f.nm; outcome := 'published'; net_pay := f.np;
    return next;
  end loop;
end;
$$;

-- The working functions are reached only through the checked ones below.
revoke all on function public._payslip_figures(date) from public, anon, authenticated;
revoke all on function public._issue_payslips(date, text[], boolean, date, text) from public, anon, authenticated;
revoke all on function public._publish_payslips(date, text[], text) from public, anon, authenticated;

create or replace function public._payroll_actor()
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (select u.name from public.app_users u
      where lower(u.email) = lower(public.current_app_email()) limit 1),
    public.current_app_email(), 'system');
$$;

-- ── 5. What HR calls ────────────────────────────────────────────────────
-- The confirmation screen: every person on payroll for the cycle, their
-- counts and figures, and where their payslip stands.
create or replace function public.payslip_preview(p_cycle_end date)
returns table(
  employee_id text, employee_name text, department text,
  working_days integer, days_present integer,
  cl_used numeric, ml_used numeric, el_used numeric, comp_off_used numeric,
  lop_leave numeric, leave_lop numeric,
  permission_count integer, permission_minutes integer,
  late_count integer, late_lop numeric, permission_lop numeric,
  days_lost numeric, payable_days numeric, cycle_days integer,
  monthly_gross numeric, gross_earned numeric, total_deductions numeric, net_pay numeric,
  payslip_status text, payslip_version integer, payslip_net numeric)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can see payroll for everyone' using errcode = '42501';
  end if;
  return query
    select f.employee_id, f.employee_name, f.department,
           f.working_days, f.days_present,
           f.cl_used, f.ml_used, f.el_used, f.comp_off_used, f.lop_leave, f.leave_lop,
           f.permission_count, f.permission_minutes, f.late_count, f.late_lop, f.permission_lop,
           f.days_lost, f.payable_days, f.cycle_days,
           f.monthly_gross, f.gross_earned, f.total_deductions, f.net_pay,
           p.status, p.version, p.net_pay
      from public._payslip_figures(p_cycle_end) f
      left join lateral (
        select x.status, x.version, x.net_pay from public.payslips x
         where x.employee_id = f.employee_id
           and x.month_year = public.attendance_cycle_label(public.attendance_cycle_end(p_cycle_end))
         order by (x.status = 'published') desc limit 1) p on true;
end;
$$;

create or replace function public.issue_payslips(
  p_cycle_end date, p_employee_ids text[] default null, p_reissue boolean default false)
returns table(employee_id text, employee_name text, outcome text, net_pay numeric)
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can issue payslips' using errcode = '42501';
  end if;
  return query select * from public._issue_payslips(
    p_cycle_end, p_employee_ids, p_reissue,
    (now() at time zone 'Asia/Kolkata')::date, public._payroll_actor());
end;
$$;

create or replace function public.publish_payslips(
  p_cycle_end date, p_employee_ids text[] default null)
returns table(employee_id text, employee_name text, outcome text, net_pay numeric)
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can publish payslips' using errcode = '42501';
  end if;
  return query select * from public._publish_payslips(
    p_cycle_end, p_employee_ids, public._payroll_actor());
end;
$$;

-- ── 6. Who can read and write ───────────────────────────────────────────
-- Was one policy for everything: an employee could write their own payslip
-- and mark their own payslip request approved.
create or replace function public.payslip_month_closed(p_month_year text)
returns boolean
language sql
stable
as $$
  select p_month_year ~ '^\d{4}-\d{2}$'
     and make_date(split_part(p_month_year, '-', 1)::int,
                   split_part(p_month_year, '-', 2)::int, 25)
         < (now() at time zone 'Asia/Kolkata')::date;
$$;

drop policy if exists payslips_all on public.payslips;
drop policy if exists payslips_read on public.payslips;
drop policy if exists payslips_write_hr on public.payslips;
create policy payslips_read on public.payslips
  for select to authenticated
  using (public.current_app_is_hr_or_mgmt()
         or (employee_id = public.current_app_employee_id() and status = 'published'));
create policy payslips_write_hr on public.payslips
  for all to authenticated
  using (public.current_app_is_hr_or_mgmt())
  with check (public.current_app_is_hr_or_mgmt());

drop policy if exists payslip_requests_all on public.payslip_requests;
drop policy if exists payslip_requests_read on public.payslip_requests;
drop policy if exists payslip_requests_ask on public.payslip_requests;
drop policy if exists payslip_requests_reask on public.payslip_requests;
drop policy if exists payslip_requests_hr on public.payslip_requests;
create policy payslip_requests_read on public.payslip_requests
  for select to authenticated
  using (employee_id = public.current_app_employee_id() or public.current_app_is_hr_or_mgmt());
-- An employee asks for their own payslip, for a cycle that has closed.
create policy payslip_requests_ask on public.payslip_requests
  for insert to authenticated
  with check (employee_id = public.current_app_employee_id()
              and status = 'pending'
              and public.payslip_month_closed(month_year));
-- ...and can ask again after a rejection, but cannot decide their own.
create policy payslip_requests_reask on public.payslip_requests
  for update to authenticated
  using (employee_id = public.current_app_employee_id())
  with check (employee_id = public.current_app_employee_id()
              and status = 'pending'
              and public.payslip_month_closed(month_year));
create policy payslip_requests_hr on public.payslip_requests
  for all to authenticated
  using (public.current_app_is_hr_or_mgmt())
  with check (public.current_app_is_hr_or_mgmt());

-- ── 7. Tidy what is there ───────────────────────────────────────────────
-- Nirmal's July payslip was filed under another person's ID prefix.
update public.payslips
   set id = 'FD-04_2026-07'
 where id = 'FHIPL-08_2026-07' and employee_id = 'FD-04'
   and not exists (select 1 from public.payslips where id = 'FD-04_2026-07');

-- ── 8. Tests ────────────────────────────────────────────────────────────
-- Added to run_money_rule_tests() just before its payroll row-count check;
-- 20261113100100_money_rule_tests.sql holds the full source.
do $zzpatch$
declare
  d text;
  anchor constant text :=
    $a$    if (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%') <> 10 then$a$;
begin
  d := pg_get_functiondef('public.run_money_rule_tests()'::regprocedure);
  if position('_issue_payslips' in d) > 0 then
    return;  -- already added
  end if;
  if position(anchor in d) = 0 then
    raise exception 'run_money_rule_tests: insertion point not found';
  end if;
  d := replace(d, anchor, $blk$    -- Payslips are issued from the payroll engine (Nov 2026).
    begin
      perform _issue_payslips(ce, array['ZZT-01'], false, ce, 'selftest');
      t := 'issued';
    exception when others then
      t := 'refused';
    end;
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: refused while the cycle is still running',
      'e', 'refused', 'a', t));
    perform _issue_payslips(ce, array['ZZT-01', 'ZZT-05'], false, ce + 1, 'selftest');
    select string_agg(ps.employee_id || ':' || ps.status, ',' order by ps.employee_id) into t
      from payslips ps where ps.employee_id in ('ZZT-01', 'ZZT-05');
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: issued as drafts once the cycle has closed',
      'e', 'ZZT-01:draft,ZZT-05:draft', 'a', t));
    select count(*)::text into t
      from payslips ps join generate_payroll(ce) g on g.employee_code = ps.employee_id
     where ps.employee_id in ('ZZT-01', 'ZZT-05')
       and ps.net_pay = g.net_pay and ps.gross_earned = g.gross
       and ps.lop_days = g.days_lost and ps.days_worked = g.nowd;
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: net pay, gross and LOP are the payroll engine''s',
      'e', '2', 'a', t));
    select trim_scale(cl_used)::text || '/' || trim_scale(leave_lop)::text into t
      from payslips where employee_id = 'ZZT-05';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: records 3 CL days of which 1.5 LOP',
      'e', '3/1.5', 'a', t));
    perform _publish_payslips(ce, array['ZZT-01'], 'selftest');
    select string_agg(outcome, ',') into t from _issue_payslips(ce, array['ZZT-01'], false, ce + 1, 'selftest');
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: a published payslip is not overwritten without a reissue',
      'e', 'already_published', 'a', t));
    perform _issue_payslips(ce, array['ZZT-01'], true, ce + 1, 'selftest');
    select ps.status || ' v' || ps.version || ', history ' ||
           (select count(*) from payslip_history h where h.employee_id = 'ZZT-01')
      into t from payslips ps where ps.employee_id = 'ZZT-01';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: a reissue is a new draft and keeps the old one',
      'e', 'draft v2, history 1', 'a', t));
    insert into app_users(email, name, employee_id, role, active, date_of_joining,
                          department, designation, onroll_confirmed_at,
                          weekly_off_day, payroll_eligible, permission_minutes_quota)
    values ('zzt-11@selftest.invalid', 'ZZ Selftest ZZT-11', 'ZZT-11', 'Employee', true, '2025-01-01',
            'ZZ Selftest Dept', 'Tester', '2025-04-01', 'Sunday', true, 120);
    select string_agg(outcome, ',') into t from _issue_payslips(ce, array['ZZT-11'], false, ce + 1, 'selftest');
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: refused without a salary structure',
      'e', 'no_salary_structure', 'a', t));

$blk$ || anchor);
  execute d;
end $zzpatch$;

-- ── 9. Check before committing ──────────────────────────────────────────
-- If any money rule now fails, or October's figures no longer match the
-- engine's, the whole migration is undone.
do $zzcheck$
declare v_fail text; v_n int;
begin
  select string_agg(test_name || ' (expected ' || expected || ', got ' || actual || ')', '; ')
    into v_fail from public.run_money_rule_tests() where not passed;
  if v_fail is not null then
    raise exception 'Money-rule tests failing: %', v_fail;
  end if;
  select count(*) into v_n
    from public._payslip_figures(date '2026-10-25') f
    join public.generate_payroll(date '2026-10-25') g on g.employee_code = f.employee_id
   where f.net_pay = g.net_pay and f.gross_earned = g.gross and f.days_lost = g.days_lost;
  if v_n <> (select count(*) from public.generate_payroll(date '2026-10-25')) then
    raise exception 'October 2026 payslip figures do not match the payroll engine (% rows agree)', v_n;
  end if;
end $zzcheck$;
