-- Payslips follow their records; the salary master sheet.
--
-- Ronak, 20 Nov 2026: "Any changes in days LOP should reflect immediately",
-- and HR needs one sheet with the salary to credit to each person, with the
-- breakup.
--
-- Until now a draft payslip was a copy of the figures taken when HR pressed
-- Generate. If a leave's LOP was changed afterwards (the probation rule for
-- Akila and Deepak, a leave approved late, a check-in regularised), the draft
-- kept the old figures until someone generated it again, and Publish sent
-- the old figures to the employee.
--
-- Now:
--   * A DRAFT payslip is recalculated the moment any record behind it
--     changes: leave (including its agreed LOP), attendance and on-duty,
--     late-LOP decisions, leave adjustments, holidays, the salary structure,
--     or the person's joining date, weekly off or payroll status.
--   * Publishing recalculates the drafts once more first, so what employees
--     receive is always today's figures.
--   * A PUBLISHED payslip is not changed: it is what the salary was paid on.
--     If its records change afterwards, the payroll screen and the master
--     sheet flag it ("records changed since publishing") and HR reissues it.
--   * While a cycle is still running, a day with no check-in counts as
--     absent only once it has passed (up to yesterday). Before this, every
--     remaining day of the running cycle counted as absent, so mid-cycle
--     figures showed several days' LOP for everyone. Closed cycles count
--     every day, as before; October 2026 is unchanged.
--   * salary_master_sheet(cycle): one row per person, with bank details, the
--     days, LOP split by cause, the fixed and earned components, deductions
--     and the net pay to credit. A published payslip's own figures are used;
--     otherwise the current calculation.

-- ── 1. Absence in a running cycle ──────────────────────────────────────
-- The last day on which a missing check-in counts as absent: yesterday while
-- the cycle runs, its last day once it has closed.
create or replace function public.payroll_absence_until(
  p_cycle_start date, p_cycle_end date,
  p_today date default (now() at time zone 'Asia/Kolkata')::date)
returns date
language sql
stable
as $$
  select case when p_today between p_cycle_start and p_cycle_end
              then p_today - 1 else p_cycle_end end;
$$;

comment on function public.payroll_absence_until(date, date, date) is
  'Last day a missing check-in counts as absent in a cycle: yesterday while the cycle runs, otherwise its last day.';

do $zzpatch$
declare
  d text := pg_get_functiondef('public.generate_payroll(date)'::regprocedure);
  anchor constant text := $a$b.ce, interval '1 day') g2(d)$a$;
begin
  if position(anchor in d) = 0 then
    raise exception 'generate_payroll: absence series not found; patch not applied';
  end if;
  d := replace(d, anchor,
    $r$public.payroll_absence_until(b.cs, b.ce), interval '1 day') g2(d)$r$);
  execute d;
end $zzpatch$;

-- ── 2. Recalculate drafts ──────────────────────────────────────────────
-- Brings draft payslips for a cycle up to date with the payroll engine, in
-- place (same version; drafts are not seen by anyone but HR). Returns how
-- many changed.
create or replace function public._refresh_draft_payslips(
  p_cycle_end date, p_employee_ids text[] default null)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ce    date := public.attendance_cycle_end(p_cycle_end);
  v_label text := public.attendance_cycle_label(public.attendance_cycle_end(p_cycle_end));
  v_n     integer;
begin
  if not exists (select 1 from public.payslips p
                  where p.month_year = v_label and p.status = 'draft'
                    and (p_employee_ids is null or p.employee_id = any(p_employee_ids))) then
    return 0;
  end if;

  update public.payslips p set
         emp_name = f.employee_name, department = f.department, designation = f.designation,
         date_of_joining = f.date_of_joining,
         working_days = f.cycle_days, days_worked = f.payable_days, lop_days = f.days_lost,
         gross_pay = f.monthly_gross,
         basic = f.basic, da = f.da, hra = f.hra, educational_allowance = f.educational,
         lta = f.lta, other_allowance = f.other_allowance, conveyance_allowance = f.conveyance,
         epf = f.epf, esi = f.esi, professional_tax = f.professional_tax, tds = f.tds,
         leave_details = coalesce(f.leave_details, '[]'::jsonb)::text,
         cycle_start = f.cycle_start, cycle_end = f.cycle_end,
         attendance_working_days = f.working_days, days_present = f.days_present,
         gross_earned = f.gross_earned, total_deductions = f.total_deductions,
         net_pay = f.net_pay, rounded_off = f.rounded_off,
         cl_used = f.cl_used, ml_used = f.ml_used, el_used = f.el_used,
         comp_off_used = f.comp_off_used, lop_leave = f.lop_leave, leave_lop = f.leave_lop,
         permission_count = f.permission_count, permission_minutes = f.permission_minutes,
         late_count = f.late_count, late_lop = f.late_lop, permission_lop = f.permission_lop,
         generated_at = now()
    from public._payslip_figures(v_ce) f
   where p.month_year = v_label and p.status = 'draft'
     and p.employee_id = f.employee_id
     and (p_employee_ids is null or p.employee_id = any(p_employee_ids))
     and (p.emp_name, p.department, p.designation, p.date_of_joining,
          p.working_days, p.days_worked, p.lop_days, p.gross_pay,
          p.basic, p.da, p.hra, p.educational_allowance, p.lta, p.other_allowance,
          p.conveyance_allowance, p.epf, p.esi, p.professional_tax, p.tds, p.leave_details,
          p.attendance_working_days, p.days_present, p.gross_earned, p.total_deductions,
          p.net_pay, p.rounded_off, p.cl_used, p.ml_used, p.el_used, p.comp_off_used,
          p.lop_leave, p.leave_lop, p.permission_count, p.permission_minutes,
          p.late_count, p.late_lop, p.permission_lop)
         is distinct from
         (f.employee_name, f.department, f.designation, f.date_of_joining,
          f.cycle_days, f.payable_days, f.days_lost, f.monthly_gross,
          f.basic, f.da, f.hra, f.educational, f.lta, f.other_allowance,
          f.conveyance, f.epf, f.esi, f.professional_tax, f.tds,
          coalesce(f.leave_details, '[]'::jsonb)::text,
          f.working_days, f.days_present, f.gross_earned, f.total_deductions,
          f.net_pay, f.rounded_off, f.cl_used, f.ml_used, f.el_used, f.comp_off_used,
          f.lop_leave, f.leave_lop, f.permission_count, f.permission_minutes,
          f.late_count, f.late_lop, f.permission_lop);
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Recalculates the drafts of one person (or everyone, when null) for every
-- cycle that overlaps [p_from, p_to] (open-ended when null). Never fails the
-- change that called it: a draft that could not be recalculated here is
-- recalculated again when it is published.
create or replace function public._payslip_drafts_follow(
  p_employee_id text, p_from date, p_to date)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ce date;
begin
  for v_ce in
    select distinct p.cycle_end from public.payslips p
     where p.status = 'draft' and p.cycle_end is not null
       and (p_employee_id is null or p.employee_id = p_employee_id)
       and p.cycle_end >= coalesce(p_from, '-infinity'::date)
       and p.cycle_start <= coalesce(p_to, 'infinity'::date)
  loop
    begin
      perform public._refresh_draft_payslips(
        v_ce, case when p_employee_id is null then null else array[p_employee_id] end);
    exception when others then
      raise warning 'Draft payslips for the cycle ending % were not recalculated: %', v_ce, sqlerrm;
    end;
  end loop;
end;
$$;

create or replace function public.trg_payslip_drafts_follow()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  -- Most of the time there are no drafts at all (they exist between Generate
  -- and Publish), and a check-in costs nothing more than this.
  if not exists (select 1 from public.payslips where status = 'draft') then
    return null;
  end if;

  if tg_table_name = 'leave_applications' then
    -- A leave also moves the balance shown on later payslips.
    if tg_op <> 'INSERT' then
      perform public._payslip_drafts_follow(old.employee_id, old.from_date, null);
    end if;
    if tg_op <> 'DELETE' and (tg_op = 'INSERT' or new.employee_id is distinct from old.employee_id
                              or new.from_date is distinct from old.from_date) then
      perform public._payslip_drafts_follow(new.employee_id, new.from_date, null);
    end if;
  elsif tg_table_name = 'attendance_records' then
    if tg_op <> 'INSERT' then
      perform public._payslip_drafts_follow(old.employee_id, old.date_iso, old.date_iso);
    end if;
    if tg_op <> 'DELETE' and (tg_op = 'INSERT' or new.employee_id is distinct from old.employee_id
                              or new.date_iso is distinct from old.date_iso) then
      perform public._payslip_drafts_follow(new.employee_id, new.date_iso, new.date_iso);
    end if;
  elsif tg_table_name = 'late_lop_decisions' then
    if tg_op <> 'INSERT' then
      perform public._payslip_drafts_follow(old.employee_id,
        to_date(old.cycle_label || '-25', 'YYYY-MM-DD'), to_date(old.cycle_label || '-25', 'YYYY-MM-DD'));
    end if;
    if tg_op <> 'DELETE' then
      perform public._payslip_drafts_follow(new.employee_id,
        to_date(new.cycle_label || '-25', 'YYYY-MM-DD'), to_date(new.cycle_label || '-25', 'YYYY-MM-DD'));
    end if;
  elsif tg_table_name = 'leave_adjustments' then
    if tg_op <> 'INSERT' then
      perform public._payslip_drafts_follow(old.employee_id, old.effective_on, null);
    end if;
    if tg_op <> 'DELETE' then
      perform public._payslip_drafts_follow(new.employee_id, new.effective_on, null);
    end if;
  elsif tg_table_name = 'holidays' then
    if tg_op <> 'INSERT' then
      perform public._payslip_drafts_follow(null, old.holiday_date, old.holiday_date);
    end if;
    if tg_op <> 'DELETE' then
      perform public._payslip_drafts_follow(null, new.holiday_date, new.holiday_date);
    end if;
  elsif tg_table_name in ('salary_structures', 'app_users') then
    if tg_op <> 'INSERT' then
      perform public._payslip_drafts_follow(old.employee_id, null, null);
    end if;
    if tg_op <> 'DELETE' and (tg_op = 'INSERT' or new.employee_id is distinct from old.employee_id) then
      perform public._payslip_drafts_follow(new.employee_id, null, null);
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_payslip_drafts_follow on public.leave_applications;
create trigger trg_payslip_drafts_follow
  after insert or update or delete on public.leave_applications
  for each row execute function public.trg_payslip_drafts_follow();

drop trigger if exists trg_payslip_drafts_follow on public.attendance_records;
create trigger trg_payslip_drafts_follow
  after insert or update or delete on public.attendance_records
  for each row execute function public.trg_payslip_drafts_follow();

drop trigger if exists trg_payslip_drafts_follow on public.late_lop_decisions;
create trigger trg_payslip_drafts_follow
  after insert or update or delete on public.late_lop_decisions
  for each row execute function public.trg_payslip_drafts_follow();

drop trigger if exists trg_payslip_drafts_follow on public.leave_adjustments;
create trigger trg_payslip_drafts_follow
  after insert or update or delete on public.leave_adjustments
  for each row execute function public.trg_payslip_drafts_follow();

drop trigger if exists trg_payslip_drafts_follow on public.holidays;
create trigger trg_payslip_drafts_follow
  after insert or update or delete on public.holidays
  for each row execute function public.trg_payslip_drafts_follow();

drop trigger if exists trg_payslip_drafts_follow on public.salary_structures;
create trigger trg_payslip_drafts_follow
  after insert or update or delete on public.salary_structures
  for each row execute function public.trg_payslip_drafts_follow();

-- Only the person's details that a payslip uses.
drop trigger if exists trg_payslip_drafts_follow on public.app_users;
create trigger trg_payslip_drafts_follow
  after update of name, department, designation, date_of_joining, weekly_off_day,
                  payroll_eligible, active, onroll_confirmed_at, leave_accrual_from
  on public.app_users
  for each row
  when ((old.name, old.department, old.designation, old.date_of_joining, old.weekly_off_day,
         old.payroll_eligible, old.active, old.onroll_confirmed_at, old.leave_accrual_from)
        is distinct from
        (new.name, new.department, new.designation, new.date_of_joining, new.weekly_off_day,
         new.payroll_eligible, new.active, new.onroll_confirmed_at, new.leave_accrual_from))
  execute function public.trg_payslip_drafts_follow();

-- ── 3. Publish today's figures ─────────────────────────────────────────
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
  -- Whatever changed since the drafts were made is on the payslip.
  perform public._refresh_draft_payslips(v_ce, p_employee_ids);

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

-- ── 4. The salary master sheet ─────────────────────────────────────────
-- One row per person in the cycle's attendance. Someone with no salary
-- structure is listed with payslip_status 'no_salary_structure' and no
-- amounts, so HR sees who is missing rather than a shorter sheet.
create or replace function public._salary_master_sheet(p_cycle_end date)
returns table(
  employee_id text, employee_name text, designation text, department text, date_of_joining text,
  bank_account text, ifsc text, pf_number text, esi_number text,
  cycle_start date, cycle_end date, cycle_days integer, working_days integer, days_present integer,
  cl_used numeric, ml_used numeric, el_used numeric, comp_off_used numeric, lop_leave numeric,
  absence_lop numeric, leave_lop numeric, late_lop numeric, permission_lop numeric,
  days_lost numeric, payable_days numeric,
  monthly_gross numeric, fixed_basic numeric, fixed_da numeric, fixed_hra numeric,
  fixed_conveyance numeric, fixed_other_allowance numeric, fixed_educational numeric, fixed_lta numeric,
  basic numeric, da numeric, hra numeric, conveyance numeric, other_allowance numeric,
  educational numeric, lta numeric, gross_earned numeric, lop_amount numeric,
  epf numeric, esi numeric, professional_tax numeric, tds numeric, total_deductions numeric,
  rounded_off numeric, net_pay numeric,
  payslip_status text, payslip_version integer, live_net_pay numeric, records_changed boolean,
  absence_counted_to date)
language sql
stable
security definer
set search_path to 'public'
as $$
  with b as (
    select public.attendance_cycle_start(p_cycle_end) as cs,
           public.attendance_cycle_end(p_cycle_end)   as ce,
           public.attendance_cycle_label(public.attendance_cycle_end(p_cycle_end)) as lbl
  ),
  r as (select * from public.attendance_cycle_report(p_cycle_end, null)),
  f as (select * from public._payslip_figures(p_cycle_end)),
  ps as (
    select distinct on (x.employee_id) x.*
      from public.payslips x, b
     where x.month_year = b.lbl
     order by x.employee_id, (x.status = 'published') desc
  )
  select r.employee_code,
         coalesce(f.employee_name, r.employee_name),
         coalesce(f.designation, r.designation),
         coalesce(f.department, r.department),
         coalesce(f.date_of_joining, r.date_of_joining),
         nullif(btrim(u.bank_account), ''), nullif(btrim(u.ifsc), ''),
         nullif(btrim(u.pf_number), ''), nullif(btrim(u.esi_number), ''),
         b.cs, b.ce, v.c_days, v.w_days, v.present,
         v.cl, v.ml, v.el, v.co, v.lopl,
         case when k.on_payroll or k.pub then v.lost - v.llop - v.ltlop - v.pmlop end,
         v.llop, v.ltlop, v.pmlop,
         v.lost, v.payable,
         v.mgross, s.basic, s.da, s.hra, s.conveyance,
         s.other_allowance, s.educational, s.lta,
         v.e_basic, v.e_da, v.e_hra, v.e_conv, v.e_other, v.e_edu, v.e_lta,
         v.earned, v.mgross - v.earned,
         v.d_epf, v.d_esi, v.d_pt, v.d_tds, v.d_total,
         v.rnd, v.net,
         case when not k.on_payroll and not k.pub then 'no_salary_structure' else ps.status end,
         ps.version,
         f.net_pay,
         coalesce(ps.employee_id is not null and k.on_payroll
                  and (ps.net_pay, ps.lop_days, ps.gross_earned, ps.total_deductions)
                      is distinct from (f.net_pay, f.days_lost, f.gross_earned, f.total_deductions),
                  false),
         public.payroll_absence_until(b.cs, b.ce)
    from r
    cross join b
    left join f on f.employee_id = r.employee_code
    left join ps on ps.employee_id = r.employee_code
    left join public.salary_structures s on s.employee_id = r.employee_code
    left join lateral (select au.bank_account, au.ifsc, au.pf_number, au.esi_number
                         from public.app_users au
                        where au.employee_id = r.employee_code
                        order by au.active desc limit 1) u on true
    cross join lateral (select coalesce(ps.status = 'published', false) as pub,
                               f.employee_id is not null as on_payroll) k
    -- A published payslip's own figures; otherwise the engine's now.
    cross join lateral (
      select case when k.pub then ps.working_days else f.cycle_days end as c_days,
             case when k.pub then ps.attendance_working_days else f.working_days end as w_days,
             case when k.pub then ps.days_present else f.days_present end as present,
             case when k.pub then ps.cl_used else f.cl_used end as cl,
             case when k.pub then ps.ml_used else f.ml_used end as ml,
             case when k.pub then ps.el_used else f.el_used end as el,
             case when k.pub then ps.comp_off_used else f.comp_off_used end as co,
             case when k.pub then ps.lop_leave else f.lop_leave end as lopl,
             case when k.pub then coalesce(ps.leave_lop, 0) else f.leave_lop end as llop,
             case when k.pub then coalesce(ps.late_lop, 0) else f.late_lop end as ltlop,
             case when k.pub then coalesce(ps.permission_lop, 0) else f.permission_lop end as pmlop,
             case when k.pub then ps.lop_days else f.days_lost end as lost,
             case when k.pub then ps.days_worked else f.payable_days end as payable,
             case when k.pub then ps.gross_pay else f.monthly_gross end as mgross,
             case when k.pub then ps.basic else f.basic end as e_basic,
             case when k.pub then ps.da else f.da end as e_da,
             case when k.pub then ps.hra else f.hra end as e_hra,
             case when k.pub then ps.conveyance_allowance else f.conveyance end as e_conv,
             case when k.pub then ps.other_allowance else f.other_allowance end as e_other,
             case when k.pub then ps.educational_allowance else f.educational end as e_edu,
             case when k.pub then ps.lta else f.lta end as e_lta,
             case when k.pub then ps.gross_earned else f.gross_earned end as earned,
             case when k.pub then ps.epf else f.epf end as d_epf,
             case when k.pub then ps.esi else f.esi end as d_esi,
             case when k.pub then ps.professional_tax else f.professional_tax end as d_pt,
             case when k.pub then ps.tds else f.tds end as d_tds,
             case when k.pub then ps.total_deductions else f.total_deductions end as d_total,
             case when k.pub then ps.rounded_off else f.rounded_off end as rnd,
             case when k.pub then ps.net_pay else f.net_pay end as net) v
   order by r.employee_code;
$$;

create or replace function public.salary_master_sheet(p_cycle_end date)
returns table(
  employee_id text, employee_name text, designation text, department text, date_of_joining text,
  bank_account text, ifsc text, pf_number text, esi_number text,
  cycle_start date, cycle_end date, cycle_days integer, working_days integer, days_present integer,
  cl_used numeric, ml_used numeric, el_used numeric, comp_off_used numeric, lop_leave numeric,
  absence_lop numeric, leave_lop numeric, late_lop numeric, permission_lop numeric,
  days_lost numeric, payable_days numeric,
  monthly_gross numeric, fixed_basic numeric, fixed_da numeric, fixed_hra numeric,
  fixed_conveyance numeric, fixed_other_allowance numeric, fixed_educational numeric, fixed_lta numeric,
  basic numeric, da numeric, hra numeric, conveyance numeric, other_allowance numeric,
  educational numeric, lta numeric, gross_earned numeric, lop_amount numeric,
  epf numeric, esi numeric, professional_tax numeric, tds numeric, total_deductions numeric,
  rounded_off numeric, net_pay numeric,
  payslip_status text, payslip_version integer, live_net_pay numeric, records_changed boolean,
  absence_counted_to date)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can see the salary master sheet' using errcode = '42501';
  end if;
  return query select * from public._salary_master_sheet(p_cycle_end);
end;
$$;

comment on function public.salary_master_sheet(date) is
  'Salary to credit for a cycle, per person, with the breakup. Published payslips are shown as published; everyone else as the payroll engine calculates them now.';

-- ── 5. The payroll screen sees what changed ────────────────────────────
drop function if exists public.payslip_preview(date);
create function public.payslip_preview(p_cycle_end date)
returns table(
  employee_id text, employee_name text, department text,
  working_days integer, days_present integer,
  cl_used numeric, ml_used numeric, el_used numeric, comp_off_used numeric,
  lop_leave numeric, leave_lop numeric,
  permission_count integer, permission_minutes integer,
  late_count integer, late_lop numeric, permission_lop numeric,
  days_lost numeric, payable_days numeric, cycle_days integer,
  monthly_gross numeric, gross_earned numeric, total_deductions numeric, net_pay numeric,
  payslip_status text, payslip_version integer, payslip_net numeric,
  payslip_days_lost numeric, records_changed boolean)
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
           p.status, p.version, p.net_pay, p.lop_days,
           coalesce(p.status is not null
                    and (p.net_pay, p.lop_days, p.gross_earned, p.total_deductions)
                        is distinct from (f.net_pay, f.days_lost, f.gross_earned, f.total_deductions),
                    false)
      from public._payslip_figures(p_cycle_end) f
      left join lateral (
        select x.status, x.version, x.net_pay, x.lop_days, x.gross_earned, x.total_deductions
          from public.payslips x
         where x.employee_id = f.employee_id
           and x.month_year = public.attendance_cycle_label(public.attendance_cycle_end(p_cycle_end))
         order by (x.status = 'published') desc limit 1) p on true;
end;
$$;

revoke all on function public._refresh_draft_payslips(date, text[]) from public, anon, authenticated;
revoke all on function public._payslip_drafts_follow(text, date, date) from public, anon, authenticated;
revoke all on function public._publish_payslips(date, text[], text) from public, anon, authenticated;
revoke all on function public._salary_master_sheet(date) from public, anon, authenticated;
revoke all on function public.salary_master_sheet(date) from public, anon;
grant execute on function public.salary_master_sheet(date) to authenticated;
revoke all on function public.payslip_preview(date) from public, anon;
grant execute on function public.payslip_preview(date) to authenticated;

-- ── 6. Tests ───────────────────────────────────────────────────────────
-- Added to run_money_rule_tests() just before its payroll row-count check;
-- 20261113100100_money_rule_tests.sql holds the full source.
do $zzpatch$
declare
  d text := pg_get_functiondef('public.run_money_rule_tests()'::regprocedure);
  anchor constant text := $a$    if (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%') <> 10 then$a$;
  block constant text := $b$    -- Draft payslips follow their records (Ronak, 20 Nov 2026). ZZT-05's
    -- three CL days were agreed as 1.5 LOP; making it 2.5 shows on the draft
    -- at once, with the engine's figures.
    select lop_days into v from payslips where employee_id = 'ZZT-05' and status = 'draft';
    update leave_applications set lop_days_override = 2.5, lop_days = 2.5 where id = 'zzt-05-cl';
    select trim_scale(ps.lop_days - v)::text || ' ' || (ps.net_pay = g.net_pay and ps.lop_days = g.days_lost)::text
      into t
      from payslips ps join generate_payroll(ce) g on g.employee_code = ps.employee_id
     where ps.employee_id = 'ZZT-05' and ps.status = 'draft';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: a draft follows a change in agreed LOP at once (1 more day, as the engine)',
      'e', '1 true', 'a', t));
    -- ...and back again (the leave-balance tests below rely on 1.5).
    update leave_applications set lop_days_override = 1.5, lop_days = 1.5 where id = 'zzt-05-cl';
    select trim_scale(ps.lop_days - v)::text into t from payslips ps
     where ps.employee_id = 'ZZT-05' and ps.status = 'draft';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: a draft follows the LOP back when it is changed back',
      'e', '0', 'a', t));
    perform _issue_payslips(ce, array['ZZT-10'], false, ce + 1, 'selftest');
    select lop_days into v from payslips where employee_id = 'ZZT-10';
    delete from attendance_records where employee_id = 'ZZT-10' and date_iso = date '2030-10-09';
    select trim_scale(lop_days - v)::text into t from payslips where employee_id = 'ZZT-10';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: a draft follows attendance at once (a check-in removed: 1 more LOP day)',
      'e', '1', 'a', t));
    -- A published payslip is what was paid: it is not changed, it is flagged.
    perform _issue_payslips(ce, array['ZZT-03'], false, ce + 1, 'selftest');
    perform _publish_payslips(ce, array['ZZT-03'], 'selftest');
    select net_pay into v from payslips where employee_id = 'ZZT-03';
    delete from attendance_records where employee_id = 'ZZT-03' and date_iso = date '2030-10-09';
    select (ps.net_pay = v)::text || ' ' || (m.net_pay = v)::text || ' ' || m.records_changed::text
      into t
      from payslips ps join _salary_master_sheet(ce) m on m.employee_id = ps.employee_id
     where ps.employee_id = 'ZZT-03';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payslip: later records do not change a published payslip; the master sheet shows it as paid and flags it',
      'e', 'true true true', 'a', t));
    -- While a cycle runs, a day with no check-in counts once it has passed.
    res := res || jsonb_build_array(
      jsonb_build_object('t', 'payroll: in a running cycle, absence is counted up to yesterday',
        'e', '2030-10-14', 'a', payroll_absence_until(cs, ce, date '2030-10-15')::text),
      jsonb_build_object('t', 'payroll: a closed cycle counts every day',
        'e', '2030-10-25', 'a', payroll_absence_until(cs, ce, date '2030-10-26')::text));
    -- The master sheet: everyone on payroll, each line adds up, LOP split by
    -- cause adds up, and the person with no salary structure is listed.
    select (count(*) filter (where m.payslip_status is distinct from 'no_salary_structure'))::text || ' '
           || coalesce(bool_and(m.net_pay = m.gross_earned - m.total_deductions + m.rounded_off)
                         filter (where m.payslip_status is distinct from 'no_salary_structure'), false)::text || ' '
           || coalesce(bool_and(m.absence_lop + m.leave_lop + m.late_lop + m.permission_lop = m.days_lost)
                         filter (where m.payslip_status is distinct from 'no_salary_structure'), false)::text || ' '
           || string_agg(m.employee_id, ',') filter (where m.payslip_status = 'no_salary_structure')
      into t
      from _salary_master_sheet(ce) m where m.employee_id like 'ZZT-%';
    res := res || jsonb_build_array(jsonb_build_object('t', 'master sheet: 10 on payroll, each net = earned - deductions +/- rounding, LOP causes add up, ZZT-11 listed without a structure',
      'e', '10 true true ZZT-11', 'a', t));

$b$;
begin
  if position(anchor in d) = 0 then
    raise exception 'run_money_rule_tests: anchor not found; tests not added';
  end if;
  d := replace(d, anchor, block || anchor);
  execute d;
end $zzpatch$;

-- ── 7. Check before committing ─────────────────────────────────────────
-- Every money rule passes; October 2026 is unchanged (closed cycle, same
-- figures as the drafts HR checked); the October drafts need no change; the
-- master sheet for October adds up to what HR agreed.
do $zzcheck$
declare
  v_fail text;
  v_diff int;
  v_total numeric;
begin
  select string_agg(test_name || ' (expected ' || coalesce(expected, 'null') || ', got ' || coalesce(actual, 'null') || ')', '; ')
    into v_fail from public.run_money_rule_tests() where not passed;
  if v_fail is not null then
    raise exception 'Money-rule tests failed: %', v_fail;
  end if;

  select count(*) into v_diff
    from public.payslips p
    join public._payslip_figures(date '2026-10-25') f on f.employee_id = p.employee_id
   where p.month_year = '2026-10'
     and (p.net_pay, p.lop_days, p.gross_earned, p.total_deductions)
         is distinct from (f.net_pay, f.days_lost, f.gross_earned, f.total_deductions);
  if v_diff <> 0 then
    raise exception 'October 2026 figures changed for % people', v_diff;
  end if;

  -- Bringing the October drafts up to date may refresh the leave balances
  -- they show, never their money (checked above and again here).
  raise notice 'October 2026 drafts brought up to date: %', public._refresh_draft_payslips(date '2026-10-25');
  select count(*) into v_diff
    from public.payslips p
    join public._payslip_figures(date '2026-10-25') f on f.employee_id = p.employee_id
   where p.month_year = '2026-10'
     and (p.net_pay, p.lop_days, p.gross_earned, p.total_deductions)
         is distinct from (f.net_pay, f.days_lost, f.gross_earned, f.total_deductions);
  if v_diff <> 0 or (select sum(p.net_pay) from public.payslips p where p.month_year = '2026-10') <> 580025 then
    raise exception 'October 2026 drafts changed money for % people', v_diff;
  end if;

  select sum(m.net_pay) into v_total
    from public._salary_master_sheet(date '2026-10-25') m
   where m.payslip_status is distinct from 'no_salary_structure';
  if v_total is distinct from 580025 then
    raise exception 'October 2026 master sheet totals % (HR agreed 5,80,025)', v_total;
  end if;
end $zzcheck$;
