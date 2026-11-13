-- Nightly consistency check.
--
-- Compares things that should agree and records every disagreement as a
-- finding that Management can see on the App Health page. Mismatches used
-- to surface only when an employee noticed their payslip, or a warning on a
-- form, and reported it by screenshot.
--
-- A finding is keyed by (check_code, subject_key), so the same problem is one
-- row however many nights it persists. Each run:
--   * inserts findings it has not seen before,
--   * refreshes last_seen_at on ones still present,
--   * marks findings it no longer sees as resolved,
--   * reopens a resolved finding if it comes back.
-- Acknowledging a finding ("known, accepted") hides it from the open count
-- without deleting it; if the finding resolves and later reappears, the
-- acknowledgement is cleared because it is a new occurrence.
--
-- Every check runs in its own block, so one broken check is reported as a
-- finding of its own instead of stopping the rest.
--
-- Run by hand:   select * from run_integrity_checks('manual');
-- Scheduled:     01:30 IST nightly (20:00 UTC), job 'integrity-checks-nightly'.

create table if not exists public.integrity_check_runs (
  id                bigint generated always as identity primary key,
  started_at        timestamptz not null default now(),
  finished_at       timestamptz,
  trigger           text not null default 'nightly',
  triggered_by      text,
  findings_open     int,
  findings_new      int,
  findings_resolved int,
  tests_passed      int,
  tests_failed      int,
  error             text
);

create table if not exists public.integrity_findings (
  id               bigint generated always as identity primary key,
  check_code       text not null,
  subject_key      text not null,
  severity         text not null check (severity in ('high', 'medium', 'low')),
  employee_id      text,
  employee_name    text,
  title            text not null,
  details          jsonb not null default '{}'::jsonb,
  first_seen_at    timestamptz not null default now(),
  last_seen_at     timestamptz not null default now(),
  resolved_at      timestamptz,
  acknowledged_at  timestamptz,
  acknowledged_by  text,
  ack_note         text,
  unique (check_code, subject_key)
);

create index if not exists integrity_findings_open_idx
  on public.integrity_findings (severity, last_seen_at desc) where resolved_at is null;

alter table public.integrity_check_runs enable row level security;
alter table public.integrity_findings   enable row level security;

-- Read-only from the app, for HR and Management. All writes go through the
-- functions below, which run as their owner.
drop policy if exists integrity_runs_read on public.integrity_check_runs;
create policy integrity_runs_read on public.integrity_check_runs
  for select to authenticated using (current_app_is_hr_or_mgmt());

drop policy if exists integrity_findings_read on public.integrity_findings;
create policy integrity_findings_read on public.integrity_findings
  for select to authenticated using (current_app_is_hr_or_mgmt());

-- ---------------------------------------------------------------------------
-- The checks. Each returns rows shaped like integrity_findings.
-- ---------------------------------------------------------------------------
create or replace function public.integrity_collect()
returns table(check_code text, subject_key text, severity text, employee_id text,
              employee_name text, title text, details jsonb)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
declare
  today       date := (now() at time zone 'Asia/Kolkata')::date;
  -- Start of the previous attendance cycle: the window that can still
  -- affect a payslip.
  window_from date := attendance_cycle_start(attendance_cycle_start(
                        (now() at time zone 'Asia/Kolkata')::date) - 1);
  r record;
begin
  -- 1. Payslip saved before its attendance cycle closed. The figures were
  --    worked out while days were still to come, so they cannot be final.
  begin
    return query
    select 'payslip_generated_early', p.id, 'high', p.employee_id, p.emp_name,
           format('Payslip for %s was generated on %s, before the cycle closed on %s',
                  p.month_year,
                  to_char((p.generated_at at time zone 'Asia/Kolkata')::date, 'DD Mon YYYY'),
                  to_char(make_date(split_part(p.month_year,'-',1)::int,
                                    split_part(p.month_year,'-',2)::int, 25), 'DD Mon YYYY')),
           jsonb_build_object('payslip_id', p.id, 'month', p.month_year,
                              'generated_at', p.generated_at, 'generated_by', p.generated_by)
      from payslips p
     where p.month_year ~ '^\d{4}-\d{2}$'
       and (p.generated_at at time zone 'Asia/Kolkata')::date
           <= make_date(split_part(p.month_year,'-',1)::int, split_part(p.month_year,'-',2)::int, 25);
  exception when others then
    return query select 'check_failed', 'payslip_generated_early', 'medium', null::text, null::text,
                        'The early-payslip check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 2. Saved payslip against what the payroll engine says for that cycle
  --    now: earnings, net pay and days lost. Closed cycles in the last
  --    four months only; older engine figures are not comparable once
  --    salaries have been revised.
  begin
    for r in
      select distinct make_date(split_part(p.month_year,'-',1)::int,
                                split_part(p.month_year,'-',2)::int, 25) as ce
        from payslips p
       where p.month_year ~ '^\d{4}-\d{2}$'
         and make_date(split_part(p.month_year,'-',1)::int, split_part(p.month_year,'-',2)::int, 25)
             between today - 120 and today - 1
    loop
      return query
      with g as (select * from generate_payroll(r.ce)),
      s as (
        select p.*,
               p.basic + p.da + p.hra + p.conveyance_allowance + p.other_allowance
                 + p.educational_allowance + p.lta + p.special_allowance as earnings,
               p.epf + p.esi + p.professional_tax + p.tds + p.late_deductions
                 + p.excess_leave_deduction + p.cug as deductions
          from payslips p
         where p.month_year = to_char(r.ce, 'YYYY-MM')
      )
      select 'payslip_vs_payroll', s.id, 'high', s.employee_id, s.emp_name,
             format('Payslip for %s does not match payroll: %s', s.month_year,
                    concat_ws('; ',
                      case when abs(s.earnings - g.gross) > 1
                           then format('earnings %s, payroll says %s', round(s.earnings), round(g.gross)) end,
                      case when abs((s.earnings - s.deductions) - g.net_pay) > 1
                           then format('net %s, payroll says %s', round(s.earnings - s.deductions), round(g.net_pay)) end,
                      case when abs(s.lop_days - g.days_lost) > 0.01
                           then format('LOP %s days, payroll says %s', trim_scale(s.lop_days), trim_scale(g.days_lost)) end)),
             jsonb_build_object('payslip_id', s.id, 'month', s.month_year,
                                'payslip', jsonb_build_object('earnings', s.earnings,
                                   'deductions', s.deductions, 'net', s.earnings - s.deductions,
                                   'lop_days', s.lop_days, 'days_worked', s.days_worked,
                                   'working_days', s.working_days),
                                'payroll', jsonb_build_object('gross', g.gross,
                                   'deductions', g.total_deductions, 'net', g.net_pay,
                                   'days_lost', g.days_lost, 'payable_days', g.nowd,
                                   'late_lop', g.late_lop, 'permission_lop', g.permission_lop))
        from s join g on g.employee_code = s.employee_id
       where abs(s.earnings - g.gross) > 1
          or abs((s.earnings - s.deductions) - g.net_pay) > 1
          or abs(s.lop_days - g.days_lost) > 0.01;
    end loop;
  exception when others then
    return query select 'check_failed', 'payslip_vs_payroll', 'medium', null::text, null::text,
                        'The payslip-versus-payroll check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 3. Monthly gross on the payslip against the salary master.
  begin
    return query
    select 'payslip_vs_salary_master', p.id, 'high', p.employee_id, p.emp_name,
           format('Payslip for %s shows monthly gross %s; the salary master says %s',
                  p.month_year, round(p.gross_pay), round(s.actual_gross)),
           jsonb_build_object('payslip_id', p.id, 'month', p.month_year,
                              'payslip_gross', p.gross_pay, 'salary_master_gross', s.actual_gross)
      from payslips p
      join salary_structures s on s.employee_id = p.employee_id
      join app_users u on u.employee_id = p.employee_id and u.active
     where p.month_year ~ '^\d{4}-\d{2}$'
       and make_date(split_part(p.month_year,'-',1)::int, split_part(p.month_year,'-',2)::int, 25)
           >= coalesce(s.effective_from, date '2000-01-01')
       and abs(coalesce(p.gross_pay,0) - s.actual_gross) > 1;
  exception when others then
    return query select 'check_failed', 'payslip_vs_salary_master', 'medium', null::text, null::text,
                        'The payslip-versus-salary-master check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 4. Payslip filed under the wrong person or month.
  begin
    return query
    select 'payslip_identity', p.id, 'medium', p.employee_id, p.emp_name,
           case when u.employee_id is null
                then format('Payslip %s belongs to employee ID %s, which no employee holds', p.id, p.employee_id)
                else format('Payslip %s is filed under %s for %s; its ID does not match', p.id, p.employee_id, p.month_year) end,
           jsonb_build_object('payslip_id', p.id, 'employee_id', p.employee_id, 'month', p.month_year)
      from payslips p
      left join app_users u on u.employee_id = p.employee_id
     where u.employee_id is null
        or p.id <> p.employee_id || '_' || p.month_year;
  exception when others then
    return query select 'check_failed', 'payslip_identity', 'medium', null::text, null::text,
                        'The payslip identity check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 5. Salary master that does not add up, or disagrees with the profile.
  begin
    return query
    select 'salary_components', s.employee_id, 'medium', s.employee_id, u.name,
           format('Salary components add up to %s, but actual gross is %s',
                  round(s.basic + s.da + s.hra + s.conveyance + s.other_allowance + s.educational + s.lta),
                  round(s.actual_gross)),
           jsonb_build_object('actual_gross', s.actual_gross,
                              'components', s.basic + s.da + s.hra + s.conveyance
                                            + s.other_allowance + s.educational + s.lta)
      from salary_structures s
      join app_users u on u.employee_id = s.employee_id and u.active
     where coalesce(jsonb_array_length(nullif(s.custom_components, 'null'::jsonb)), 0) = 0
       and abs(s.actual_gross - (s.basic + s.da + s.hra + s.conveyance + s.other_allowance
                                 + s.educational + s.lta)) > 1;

    return query
    select 'profile_gross_vs_salary', s.employee_id, 'medium', s.employee_id, u.name,
           format('Profile shows gross pay %s; the salary master says %s',
                  round(coalesce(u.gross_pay,0)), round(s.actual_gross)),
           jsonb_build_object('profile_gross', u.gross_pay, 'salary_master_gross', s.actual_gross)
      from salary_structures s
      join app_users u on u.employee_id = s.employee_id and u.active
     where abs(coalesce(u.gross_pay,0) - s.actual_gross) > 1;

    return query
    select 'payroll_no_salary', e.employee_id, 'medium', e.employee_id, e.name,
           'On payroll but has no salary structure, so generate_payroll leaves them out',
           '{}'::jsonb
      from v_payroll_eligible_employees e
     where not exists (select 1 from salary_structures s where s.employee_id = e.employee_id)
       and not exists (select 1 from app_users u where u.employee_id = e.employee_id
                          and coalesce(u.exempt_from_attendance, false));
  exception when others then
    return query select 'check_failed', 'salary_master', 'medium', null::text, null::text,
                        'The salary master checks could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 6. Leave balance against approved leave: more days used than accrued
  --    plus adjustments. leave_balance() clamps "available" at zero, which
  --    is exactly how an overdraw stays hidden, so this works from the parts.
  begin
    return query
    select 'leave_overdrawn', u.employee_id || '|' || lb.bucket || '|' || leave_year_start(today),
           'high', u.employee_id, u.name,
           format('%s balance is overdrawn by %s day(s): %s accrued, %s adjusted, %s used',
                  lb.bucket, trim_scale(lb.used - lb.accrued - lb.adjusted),
                  trim_scale(lb.accrued), trim_scale(lb.adjusted), trim_scale(lb.used)),
           jsonb_build_object('bucket', lb.bucket, 'accrued', lb.accrued,
                              'adjusted', lb.adjusted, 'used', lb.used)
      from app_users u
      cross join lateral leave_balance(u.employee_id, today) lb
     where u.active and coalesce(u.employee_id,'') <> ''
       and not coalesce(u.oversight_only, false)
       and not coalesce(u.exempt_from_leave_rules, false)
       and lb.accrued < 9999
       and lb.accrued + lb.adjusted - lb.used < -0.01;
  exception when others then
    return query select 'check_failed', 'leave_overdrawn', 'medium', null::text, null::text,
                        'The leave balance check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 7. LOP recorded on a leave although the balance before it covered more
  --    of it. A manual split (lop_days_override) is a decision and is left
  --    alone. CL's two-days-per-request cap is respected via "usable".
  begin
    return query
    with l as (
      select la.*,
             coalesce(nullif(la.leave_bucket,''),
                      case when la.leave_type ilike '%medical%' or la.leave_type ilike '%sick%' then 'ML'
                           when la.leave_type ilike '%earned%' then 'EL' else 'CL' end) as bkt
        from leave_applications la
       where la.leave_type <> 'Permission'
         and la.leave_type not ilike '%comp%off%'
         and coalesce(la.lop_days, 0) > 0
         and la.lop_days_override is null
         and coalesce(la.manager_status,'') not in ('denied','cancelled')
         and coalesce(la.management_status,'') not in ('denied','cancelled')
         and la.from_date >= window_from
    )
    select 'lop_despite_balance', l.id, 'medium', l.employee_id, l.employee_name,
           format('%s on %s: %s of %s day(s) recorded as LOP, but %s %s day(s) were available',
                  l.leave_type, to_char(l.from_date, 'DD Mon'), trim_scale(l.lop_days),
                  trim_scale(l.days), trim_scale(lb.usable), l.bkt),
           jsonb_build_object('leave_id', l.id, 'bucket', l.bkt, 'days', l.days,
                              'lop_days', l.lop_days, 'usable_before', lb.usable)
      from l
      cross join lateral leave_balance(l.employee_id, l.from_date - 1) lb
     where lb.bucket = l.bkt
       and lb.usable < 9999
       and (l.days - l.lop_days) + 0.01 < least(l.days, lb.usable);
  exception when others then
    return query select 'check_failed', 'lop_despite_balance', 'medium', null::text, null::text,
                        'The LOP-versus-balance check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 8. Leave rows whose numbers cannot be right.
  begin
    return query
    select 'leave_figures_invalid', la.id, 'medium', la.employee_id, la.employee_name,
           format('%s on %s has %s day(s) with %s LOP: %s', la.leave_type,
                  to_char(la.from_date, 'DD Mon YYYY'), trim_scale(la.days),
                  trim_scale(coalesce(la.lop_days,0)),
                  case when la.is_half_day and la.days <> 0.5 then 'a half day must be 0.5'
                       when coalesce(la.lop_days,0) > la.days then 'more LOP than days'
                       when coalesce(la.lop_days,0) < 0 then 'negative LOP'
                       else 'LOP is not in half-day steps' end),
           jsonb_build_object('leave_id', la.id, 'days', la.days, 'lop_days', la.lop_days,
                              'is_half_day', la.is_half_day)
      from leave_applications la
     where la.leave_type <> 'Permission'
       and la.from_date >= window_from
       and ((la.is_half_day and la.days <> 0.5)
            or coalesce(la.lop_days,0) > la.days
            or coalesce(la.lop_days,0) < 0
            or coalesce(la.lop_days,0) * 2 <> floor(coalesce(la.lop_days,0) * 2));
  exception when others then
    return query select 'check_failed', 'leave_figures_invalid', 'medium', null::text, null::text,
                        'The leave figures check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 9. Attendance: checked in, never checked out (before today), and
  --    check-out earlier than check-in.
  begin
    return query
    select 'missing_checkout', a.id, 'medium', a.employee_id, a.employee_name,
           format('Checked in at %s on %s but never checked out', a.check_in_time,
                  to_char(a.date_iso, 'Dy DD Mon')),
           jsonb_build_object('attendance_id', a.id, 'date', a.date_iso, 'check_in', a.check_in_time)
      from attendance_records a
     where a.date_iso between window_from and today - 1
       and coalesce(a.check_in_time,'') <> ''
       and coalesce(a.check_out_time,'') = '';

    return query
    select 'checkout_before_checkin', a.id, 'medium', a.employee_id, a.employee_name,
           format('Checked out at %s, before checking in at %s, on %s', a.check_out_time,
                  a.check_in_time, to_char(a.date_iso, 'Dy DD Mon')),
           jsonb_build_object('attendance_id', a.id, 'date', a.date_iso,
                              'check_in', a.check_in_time, 'check_out', a.check_out_time)
      from attendance_records a
     where a.date_iso >= window_from
       and coalesce(a.check_in_time,'') <> '' and coalesce(a.check_out_time,'') <> ''
       and a.check_out_time < a.check_in_time;
  exception when others then
    return query select 'check_failed', 'attendance', 'medium', null::text, null::text,
                        'The attendance checks could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 10. Checked in on a day covered by approved full-day leave. Payroll
  --     counts the day as both worked and on leave.
  begin
    return query
    select 'attended_on_leave', a.id || '|' || la.id, 'medium', a.employee_id, a.employee_name,
           format('Checked in on %s while on approved %s', to_char(a.date_iso, 'Dy DD Mon'), la.leave_type),
           jsonb_build_object('attendance_id', a.id, 'leave_id', la.id, 'date', a.date_iso)
      from attendance_records a
      join leave_applications la
        on la.employee_id = a.employee_id
       and a.date_iso between la.from_date and la.to_date
     where a.date_iso >= window_from
       and coalesce(a.check_in_time,'') <> ''
       and la.granted
       and la.leave_type <> 'Permission'
       and not coalesce(la.is_half_day, false)
       and not coalesce(a.on_duty, false);
  exception when others then
    return query select 'check_failed', 'attended_on_leave', 'medium', null::text, null::text,
                        'The attendance-on-leave check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 11. Permission charged half a day although, taken in date order, it was
  --     still inside the quota. set_and_check_permission_minutes() re-runs
  --     on every update and counts all the cycle's other permissions,
  --     including later ones, so approving an earlier permission after a
  --     later one was filed charges both. Pinned by run_money_rule_tests().
  begin
    return query
    with p as (
      select l.*, coalesce(u.permission_minutes_quota, 120) as quota,
             sum(coalesce(l.permission_minutes, 0)) over (
               partition by l.employee_id, attendance_cycle_start(l.from_date)
               order by l.from_date, l.applied_on rows unbounded preceding) as running
        from leave_applications l
        left join app_users u on u.employee_id = l.employee_id
       where l.leave_type = 'Permission'
         and coalesce(l.manager_status,'') not in ('denied','cancelled')
         and l.from_date >= window_from
    )
    select 'permission_charged_within_quota', p.id, 'high', p.employee_id, p.employee_name,
           format('Permission on %s is charged half a day, but only %s of %s minutes had been used by then',
                  to_char(p.from_date, 'DD Mon'), p.running, p.quota),
           jsonb_build_object('leave_id', p.id, 'minutes', p.permission_minutes,
                              'running_total', p.running, 'quota', p.quota)
      from p
     where p.permission_lop_half_day and p.running <= p.quota;
  exception when others then
    return query select 'check_failed', 'permission_charged_within_quota', 'medium', null::text, null::text,
                        'The permission quota check could not run: ' || sqlerrm, '{}'::jsonb;
  end;

  -- 12. The integrity views already in the schema, so nobody has to
  --     remember to look at them.
  begin
    return query
    select 'orphaned_attendance', coalesce(v.employee_id,'') || '|' || coalesce(v.employee_name,''),
           'medium', v.employee_id, v.employee_name,
           format('%s attendance row(s) from %s to %s belong to no current employee',
                  v.rows, to_char(v.first_day,'DD Mon YYYY'), to_char(v.last_day,'DD Mon YYYY')),
           to_jsonb(v)
      from v_orphaned_attendance v;

    return query
    select 'attendance_identity_mismatch', v.row_employee_id || '|' || v.expected_employee_id,
           'medium', v.expected_employee_id, v.employee_name,
           format('%s attendance row(s) carry ID %s, but %s is %s', v.rows,
                  v.row_employee_id, v.employee_name, v.expected_employee_id),
           to_jsonb(v)
      from v_attendance_identity_mismatch v;

    return query
    select 'dangling_reporting_manager', v.employee_id, 'low', v.employee_id, v.name,
           format('Reports to "%s", who is not an active employee', v.reporting_manager),
           to_jsonb(v)
      from v_dangling_reporting_managers v;
  exception when others then
    return query select 'check_failed', 'integrity_views', 'medium', null::text, null::text,
                        'The integrity views could not be read: ' || sqlerrm, '{}'::jsonb;
  end;
end;
$$;

revoke all on function public.integrity_collect() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- One run: collect, merge into integrity_findings, record the run.
-- ---------------------------------------------------------------------------
create or replace function public.run_integrity_checks(p_trigger text default 'nightly')
returns table(run_id bigint, findings_open int, findings_new int,
              findings_resolved int, tests_failed int)
language plpgsql
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
declare
  v_run   bigint;
  v_new   int := 0;
  v_res   int := 0;
  v_open  int := 0;
  v_pass  int := 0;
  v_fail  int := 0;
  v_high_new int := 0;
begin
  if current_app_email() is not null and not current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can run the consistency check';
  end if;

  insert into integrity_check_runs(trigger, triggered_by)
  values (coalesce(p_trigger, 'nightly'), current_app_email())
  returning id into v_run;

  create temp table if not exists _integrity_seen (
    check_code text, subject_key text, severity text, employee_id text,
    employee_name text, title text, details jsonb
  ) on commit drop;
  truncate _integrity_seen;

  insert into _integrity_seen select * from integrity_collect();

  -- The money-rule tests, as findings when they fail.
  begin
    create temp table if not exists _integrity_tests (
      test_name text, passed boolean, expected text, actual text
    ) on commit drop;
    truncate _integrity_tests;
    insert into _integrity_tests select * from run_money_rule_tests();
    select count(*) filter (where passed), count(*) filter (where not passed)
      into v_pass, v_fail from _integrity_tests;

    insert into _integrity_seen
    select 'money_rule_test', t.test_name, 'high', null, null,
           'Money rule test failed: ' || t.test_name,
           jsonb_build_object('expected', t.expected, 'actual', t.actual)
      from _integrity_tests t
     where not t.passed;
  exception when others then
    insert into _integrity_seen values ('check_failed', 'money_rule_tests', 'medium', null, null,
      'The money-rule tests could not run: ' || sqlerrm, '{}'::jsonb);
  end;

  -- Same subject reported twice in one run (e.g. a leave covering two
  -- attendance days): keep one.
  delete from _integrity_seen a using _integrity_seen b
   where a.ctid > b.ctid and a.check_code = b.check_code and a.subject_key = b.subject_key;

  select count(*) into v_new from _integrity_seen s
   where not exists (select 1 from integrity_findings f
                      where f.check_code = s.check_code and f.subject_key = s.subject_key
                        and f.resolved_at is null);
  select count(*) into v_high_new from _integrity_seen s
   where s.severity = 'high'
     and not exists (select 1 from integrity_findings f
                      where f.check_code = s.check_code and f.subject_key = s.subject_key
                        and f.resolved_at is null);

  insert into integrity_findings as f
         (check_code, subject_key, severity, employee_id, employee_name, title, details)
  select check_code, subject_key, severity, employee_id, employee_name, title, details
    from _integrity_seen
  on conflict (check_code, subject_key) do update
     set severity      = excluded.severity,
         employee_id   = excluded.employee_id,
         employee_name = excluded.employee_name,
         title         = excluded.title,
         details       = excluded.details,
         last_seen_at  = now(),
         -- A resolved finding that comes back is a new occurrence.
         first_seen_at   = case when f.resolved_at is not null then now() else f.first_seen_at end,
         acknowledged_at = case when f.resolved_at is not null then null else f.acknowledged_at end,
         acknowledged_by = case when f.resolved_at is not null then null else f.acknowledged_by end,
         ack_note        = case when f.resolved_at is not null then null else f.ack_note end,
         resolved_at     = null;

  update integrity_findings f set resolved_at = now()
   where f.resolved_at is null
     and not exists (select 1 from _integrity_seen s
                      where s.check_code = f.check_code and s.subject_key = f.subject_key);
  get diagnostics v_res = row_count;

  select count(*) into v_open from integrity_findings
   where resolved_at is null and acknowledged_at is null;

  update integrity_check_runs
     set finished_at = now(), findings_open = v_open, findings_new = v_new,
         findings_resolved = v_res, tests_passed = v_pass, tests_failed = v_fail
   where id = v_run;

  if v_high_new > 0 then
    insert into notifications(type, title, body, route, target_role, source_id)
    values ('integrity_findings',
            format('Consistency check: %s new high-priority issue(s)', v_high_new),
            'Payroll, leave or attendance figures disagree. Open App Health to review.',
            '/management/app-health', 'Management', 'integrity_run_' || v_run);
  end if;

  return query select v_run, v_open, v_new, v_res, v_fail;
end;
$$;

revoke all on function public.run_integrity_checks(text) from public, anon;
grant execute on function public.run_integrity_checks(text) to authenticated;

-- Acknowledge ("known, accepted") or un-acknowledge a finding.
create or replace function public.acknowledge_integrity_finding(
  p_id bigint, p_acknowledge boolean default true, p_note text default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can acknowledge a finding';
  end if;
  update integrity_findings
     set acknowledged_at = case when p_acknowledge then now() end,
         acknowledged_by = case when p_acknowledge then current_app_email() end,
         ack_note        = case when p_acknowledge then nullif(btrim(p_note), '') end
   where id = p_id;
  perform log_audit_event(
    case when p_acknowledge then 'integrity_finding_acknowledged' else 'integrity_finding_reopened' end,
    'integrity_findings', p_id::text, jsonb_build_object('note', p_note));
end;
$$;

revoke all on function public.acknowledge_integrity_finding(bigint, boolean, text) from public, anon;
grant execute on function public.acknowledge_integrity_finding(bigint, boolean, text) to authenticated;

-- 01:30 IST every night.
select cron.unschedule(jobid) from cron.job where jobname = 'integrity-checks-nightly';
select cron.schedule('integrity-checks-nightly', '0 20 * * *',
                     $cron$ select public.run_integrity_checks('nightly') $cron$);
