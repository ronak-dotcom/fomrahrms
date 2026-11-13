-- Automated tests for the money rules: payroll, leave balance, late and
-- permission LOP.
--
-- These rules live in the database (generate_payroll, leave_balance,
-- late_lop_days, permission_lop_days and the leave triggers), so that is
-- where they are tested. run_money_rule_tests() builds a small set of
-- made-up employees in a far-future cycle (26 Sep - 25 Oct 2030), runs the
-- real functions against them, compares each figure with the one the rule
-- says it should be, and then throws the whole fixture away. Nothing it
-- writes survives the call: the work happens inside a block that always
-- ends by raising, which rolls back every insert, update and delete.
--
-- The nightly consistency run calls it and turns any failure into a
-- high-severity finding on the App Health page. Run it by hand after any
-- change to a payroll, leave or attendance function:
--
--     select * from run_money_rule_tests() where not passed;
--
-- An empty result means every rule still gives the expected figure.
--
-- The 2030 cycle used:
--   30 calendar days, 4 Sundays (29 Sep, 6, 13, 20 Oct), 1 holiday (2 Oct)
--   -> 25 working days. Real holidays in that window are removed for the
--   duration of the test so a future holiday list cannot move the figures.
-- Every fixture employee earns 30,000 a month (basic 15,000, HRA 7,500,
-- other 7,500), so one day's pay is exactly 1,000, with PT 208 and EPF 1,800.

create or replace function public.run_money_rule_tests()
returns table(test_name text, passed boolean, expected text, actual text)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  cs constant date := date '2030-09-26';
  ce constant date := date '2030-10-25';
  res jsonb := '[]'::jsonb;
  p record;
  b record;
  v numeric;
  t text;
  i int;
  emp_ids constant text[] := array['ZZT-01','ZZT-02','ZZT-03','ZZT-04','ZZT-05','ZZT-06','ZZT-07','ZZT-08','ZZT-09','ZZT-10'];
begin
  -- The nightly job runs with no signed-in user; from the app, HR and
  -- Management only.
  if current_app_email() is not null and not current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can run the money-rule tests';
  end if;

  begin
    ------------------------------------------------------------------ setup
    delete from holidays where holiday_date between cs and ce;
    insert into holidays(name, holiday_date) values ('ZZ test holiday', date '2030-10-02');

    for i in 1 .. array_length(emp_ids, 1) loop
      insert into app_users(email, name, employee_id, role, active, date_of_joining,
                            department, designation, onroll_confirmed_at,
                            weekly_off_day, payroll_eligible, permission_minutes_quota)
      values (lower(emp_ids[i]) || '@selftest.invalid', 'ZZ Selftest ' || emp_ids[i],
              emp_ids[i], 'Employee', true,
              case emp_ids[i] when 'ZZT-06' then '2030-10-11'
                              when 'ZZT-08' then '2030-06-01'
                              else '2025-01-01' end,
              'ZZ Selftest Dept', 'Tester',
              case emp_ids[i] when 'ZZT-08' then '' else '2025-04-01' end,
              'Sunday', true, 120);
      insert into salary_structures(employee_id, actual_gross, basic, da, hra, conveyance,
                                    other_allowance, educational, lta, professional_tax,
                                    effective_from, epf, esi, tds)
      values (emp_ids[i], 30000, 15000, 0, 7500, 0, 7500, 0, 0, 208,
              date '2025-01-01', 1800, 0, 0);
    end loop;

    -- Attendance on every working day at 09:25, except the gaps each case
    -- needs. ZZT-06 joins on 11 Oct and works from then.
    insert into attendance_records(id, employee_name, employee_id, date, check_in_time, check_out_time)
    select e || '_' || to_char(d, 'DD-MM-YYYY'), 'ZZ Selftest ' || e, e,
           to_char(d, 'DD/MM/YYYY'), '09:25', '18:30'
      from unnest(emp_ids) e,
           generate_series(cs, ce, interval '1 day') g(d)
     where extract(isodow from d) <> 7
       and d::date <> date '2030-10-02'
       and not (e = 'ZZT-02' and d::date = date '2030-10-07')
       and not (e = 'ZZT-03' and d::date = date '2030-10-07')
       and not (e = 'ZZT-05' and d::date between date '2030-10-07' and date '2030-10-09')
       and not (e = 'ZZT-06' and d::date < date '2030-10-11')
       and not (e = 'ZZT-09' and d::date in (date '2030-10-12', date '2030-10-14'))
       and not (e = 'ZZT-10' and d::date = date '2030-10-08');

    -- ZZT-04: five late arrivals (start 09:30, grace 10 minutes).
    update attendance_records set check_in_time = '09:45'
     where employee_id = 'ZZT-04' and date_iso in (date '2030-09-26', date '2030-09-27', date '2030-09-28');
    update attendance_records set check_in_time = '09:50'
     where employee_id = 'ZZT-04' and date_iso = date '2030-09-30';
    update attendance_records set check_in_time = '12:45'
     where employee_id = 'ZZT-04' and date_iso = date '2030-10-01';

    -- Leave goes in pending and is then approved, as in the app.
    insert into leave_applications(id, employee_name, employee_id, department, leave_type,
                                   from_date, to_date, days, reason, applied_on,
                                   manager_status, management_status, leave_bucket, is_half_day)
    values
      ('zzt-03-cl', 'ZZ Selftest ZZT-03', 'ZZT-03', 'ZZ Selftest Dept', 'Casual Leave',
       date '2030-10-07', date '2030-10-07', 1, 'selftest', now(), 'pending', 'pending', 'CL', false),
      ('zzt-05-cl', 'ZZ Selftest ZZT-05', 'ZZT-05', 'ZZ Selftest Dept', 'Casual Leave',
       date '2030-10-07', date '2030-10-09', 3, 'selftest', now(), 'pending', 'pending', 'CL', false),
      ('zzt-09-cl', 'ZZ Selftest ZZT-09', 'ZZT-09', 'ZZ Selftest Dept', 'Casual Leave',
       date '2030-10-12', date '2030-10-14', 2, 'selftest', now(), 'pending', 'pending', 'CL', false),
      ('zzt-10-half', 'ZZ Selftest ZZT-10', 'ZZT-10', 'ZZ Selftest Dept', 'Casual Leave',
       date '2030-10-08', date '2030-10-08', 0.5, 'selftest', now(), 'pending', 'pending', 'CL', true),
      ('zzt-07-p1', 'ZZ Selftest ZZT-07', 'ZZT-07', 'ZZ Selftest Dept', 'Permission',
       date '2030-10-03', date '2030-10-03', 0, 'Permission: 2 Hours | selftest', now(),
       'pending', 'pending', null, false),
      ('zzt-07-p2', 'ZZ Selftest ZZT-07', 'ZZT-07', 'ZZ Selftest Dept', 'Permission',
       date '2030-10-10', date '2030-10-10', 0, 'Permission: 30 Minutes | selftest', now(),
       'pending', 'pending', null, false);

    -- Approved at Management level: a Reporting Manager may approve only up
    -- to two days, and the three-day request below would be refused.
    update leave_applications set management_status = 'approved'
     where id like 'zzt-%';

    -- ZZT-05: three days agreed as 1.5 paid and 1.5 LOP.
    update leave_applications set lop_days_override = 1.5, lop_days = 1.5
     where id = 'zzt-05-cl';

    --------------------------------------------------------- cycle bounds
    res := res || jsonb_build_array(
      jsonb_build_object('t', 'cycle: 10 Oct falls in the cycle starting 26 Sep',
        'e', '2030-09-26', 'a', attendance_cycle_start(date '2030-10-10')::text),
      jsonb_build_object('t', 'cycle: 26 Oct starts a new cycle',
        'e', '2030-10-26', 'a', attendance_cycle_start(date '2030-10-26')::text),
      jsonb_build_object('t', 'cycle: ends on the 25th',
        'e', '2030-10-25', 'a', attendance_cycle_end(date '2030-10-01')::text),
      jsonb_build_object('t', 'cycle: 26 Dec - 25 Jan crosses the year',
        'e', '2031-01-25', 'a', attendance_cycle_end(date '2030-12-27')::text),
      jsonb_build_object('t', 'cycle: label is the month the cycle ends in',
        'e', '2030-10', 'a', attendance_cycle_label(date '2030-09-30')));

    -------------------------------------------------------------- payroll
    for p in select * from generate_payroll(ce) where employee_code like 'ZZT-%' loop
      t := 'payroll ' || p.employee_code || ': ';
      case p.employee_code
        when 'ZZT-01' then
          res := res || jsonb_build_array(
            jsonb_build_object('t', t || 'full attendance loses no days', 'e', '0', 'a', trim_scale(p.days_lost)::text),
            jsonb_build_object('t', t || 'full attendance is paid the full gross', 'e', '30000', 'a', trim_scale(p.gross)::text),
            jsonb_build_object('t', t || 'deductions are PT + EPF + ESI + TDS', 'e', '2008', 'a', trim_scale(p.total_deductions)::text),
            jsonb_build_object('t', t || 'net pay is gross less deductions', 'e', '27992', 'a', trim_scale(p.net_pay)::text));
        when 'ZZT-02' then
          res := res || jsonb_build_array(
            jsonb_build_object('t', t || 'one absence with no leave costs one day', 'e', '1', 'a', trim_scale(p.days_lost)::text),
            jsonb_build_object('t', t || 'one unpaid day is 1/30 of gross', 'e', '29000', 'a', trim_scale(p.gross)::text));
        when 'ZZT-03' then
          res := res || jsonb_build_array(
            jsonb_build_object('t', t || 'an absence covered by approved CL costs nothing', 'e', '0', 'a', trim_scale(p.days_lost)::text),
            jsonb_build_object('t', t || 'approved CL is paid', 'e', '30000', 'a', trim_scale(p.gross)::text));
        when 'ZZT-04' then
          res := res || jsonb_build_array(
            jsonb_build_object('t', t || 'three lates free, 4th bought from the permission pool, 5th (over 2h) is half a day',
              'e', '0.5', 'a', trim_scale(p.late_lop)::text),
            jsonb_build_object('t', t || 'late LOP reduces pay', 'e', '29500', 'a', trim_scale(p.gross)::text));
        when 'ZZT-05' then
          res := res || jsonb_build_array(
            jsonb_build_object('t', t || 'agreed 1.5 LOP on a 3-day leave costs exactly 1.5 days', 'e', '1.5', 'a', trim_scale(p.days_lost)::text),
            jsonb_build_object('t', t || 'half-day LOP is not rounded', 'e', '28500', 'a', trim_scale(p.gross)::text));
        when 'ZZT-06' then
          res := res || jsonb_build_array(
            jsonb_build_object('t', t || 'joiner on 11 Oct is paid for 15 of 30 days', 'e', '15', 'a', trim_scale(p.nowd)::text),
            jsonb_build_object('t', t || 'joiner gross is pro-rated', 'e', '15000', 'a', trim_scale(p.gross)::text));
        when 'ZZT-07' then
          res := res || jsonb_build_array(
            -- 2 hours then 30 minutes: only the second goes over the 120-minute
            -- quota, so only it costs half a day.
            jsonb_build_object('t', t || 'only the permission that goes over the 120-minute quota costs half a day',
              'e', '0.5', 'a', trim_scale(p.permission_lop)::text),
            jsonb_build_object('t', t || 'permission LOP reduces pay', 'e', '29500', 'a', trim_scale(p.gross)::text));
        when 'ZZT-09' then
          res := res || jsonb_build_array(
            jsonb_build_object('t', t || 'Sat-Mon CL is 3 days with the Sunday; the third is LOP (two paid days per request)',
              'e', '1', 'a', trim_scale(p.days_lost)::text));
        when 'ZZT-10' then
          res := res || jsonb_build_array(
            jsonb_build_object('t', t || 'a half-day CL on a day not worked: half paid by leave, half unpaid',
              'e', '0.5', 'a', trim_scale(p.days_lost)::text));
        else null;
      end case;
    end loop;

    if (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%') <> 10 then
      res := res || jsonb_build_array(jsonb_build_object('t', 'payroll: every active payroll employee gets a row',
        'e', '10', 'a', (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%')::text));
    end if;

    -- A settled late LOP replaces the rule's figure.
    insert into late_lop_decisions(employee_id, cycle_label, action, note, decided_by, decided_at, lop_days_override)
    values ('ZZT-04', '2030-10', 'override', 'selftest', 'selftest', now(), 0);
    res := res || jsonb_build_array(jsonb_build_object('t', 'late LOP: a settled override replaces the rule',
      'e', '0', 'a', trim_scale(late_lop_days('ZZT-04', ce))::text));

    -------------------------------------------------------- leave balance
    select * into b from leave_balance('ZZT-01', ce) where bucket = 'CL';
    res := res || jsonb_build_array(
      jsonb_build_object('t', 'leave balance: CL accrues one per cycle from the leave year (10 cycles to Oct)',
        'e', '10', 'a', trim_scale(b.accrued)::text),
      jsonb_build_object('t', 'leave balance: CL usable in one go is capped at 2', 'e', '2', 'a', trim_scale(b.usable)::text));

    select * into b from leave_balance('ZZT-03', ce) where bucket = 'CL';
    res := res || jsonb_build_array(jsonb_build_object('t', 'leave balance: one approved CL day is one day used',
      'e', '1', 'a', trim_scale(b.used)::text));

    select * into b from leave_balance('ZZT-05', ce) where bucket = 'CL';
    res := res || jsonb_build_array(jsonb_build_object('t', 'leave balance: LOP days are not charged to CL',
      'e', '1.5', 'a', trim_scale(b.used)::text));

    select * into b from leave_balance('ZZT-10', ce) where bucket = 'CL';
    res := res || jsonb_build_array(jsonb_build_object('t', 'leave balance: a half day uses half a day',
      'e', '0.5', 'a', trim_scale(b.used)::text));

    select days into v from leave_applications where id = 'zzt-09-cl';
    res := res || jsonb_build_array(jsonb_build_object('t', 'sandwich: Sat to Mon charges the Sunday between',
      'e', '3', 'a', trim_scale(v)::text));

    select * into b from leave_balance('ZZT-08', ce) where bucket = 'ML';
    res := res || jsonb_build_array(jsonb_build_object('t', 'leave balance: no ML before confirmation',
      'e', '0', 'a', trim_scale(b.accrued)::text));
    select * into b from leave_balance('ZZT-08', ce) where bucket = 'CL';
    res := res || jsonb_build_array(jsonb_build_object('t', 'leave balance: CL accrues from the joining cycle (Jun - Oct = 5)',
      'e', '5', 'a', trim_scale(b.accrued)::text));

    raise exception using errcode = 'ZZTST', message = 'selftest rollback';
  exception
    when sqlstate 'ZZTST' then
      null;  -- the expected end: everything above is rolled back
    when others then
      res := res || jsonb_build_array(jsonb_build_object('t', 'test fixture could not be built',
        'e', 'no error', 'a', sqlerrm));
  end;

  return query
    select r->>'t', (r->>'e') is not distinct from (r->>'a'), r->>'e', r->>'a'
      from jsonb_array_elements(res) r;
end;
$$;

revoke all on function public.run_money_rule_tests() from public, anon;
grant execute on function public.run_money_rule_tests() to authenticated;
