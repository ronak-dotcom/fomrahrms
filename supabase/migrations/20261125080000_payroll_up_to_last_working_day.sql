-- Applied live on 25 Nov 2026, after 20261125070000_employee_exits.sql.
--
-- Payroll pays a leaver only up to their last working day, leaves out a
-- final month Management withheld or that was settled outside the app, and
-- will not publish a payslip whose final salary is on hold. Also fixes
-- retire_employee, which had never once completed, and schedules the
-- nightly close of exited accounts.

do $$
declare d text;
begin
  -- Attendance report: leavers are in the cycles up to their last working
  -- day, and working days and pay days stop there.
  d := pg_get_functiondef('public.attendance_cycle_report(date, text[])'::regprocedure);
  d := replace(d,
$o$           greatest(b.s, coalesce(nullif(u.date_of_joining,'')::date, b.s)) as pay_from
      from app_users u cross join bounds b$o$,
$n$           greatest(b.s, coalesce(nullif(u.date_of_joining,'')::date, b.s)) as pay_from,
           least(b.e, coalesce(public.employee_last_working_day(u.employee_id), b.e)) as pay_until
      from app_users u cross join bounds b$n$);
  d := replace(d,
$o$                          and b.e >= date '2026-11-25'))$o$,
$n$                          and b.e >= date '2026-11-25')
            -- An approved exit: in every cycle up to the last working day.
            or exists (select 1 from employee_exits xe
                        where xe.employee_id = u.employee_id and xe.status = 'approved'
                          and xe.last_working_day >= b.s))
       -- Never in a cycle that starts after their last working day.
       and not exists (select 1 from employee_exits xe
                        where xe.employee_id = u.employee_id and xe.status = 'approved'
                          and xe.last_working_day < b.s)$n$);
  d := replace(d,
$o$      from emp e, bounds b, generate_series(b.s, b.e, interval '1 day') d$o$,
$n$      from emp e, bounds b, generate_series(b.s, e.pay_until, interval '1 day') d$n$);
  d := replace(d,
$o$         (((select e2.e from bounds e2) - e.pay_from) + 1 - coalesce(lv.lop_days,0))::numeric,$o$,
$n$         ((e.pay_until - e.pay_from) + 1 - coalesce(lv.lop_days,0))::numeric,$n$);
  if position('e.pay_until - e.pay_from' in d) = 0
     or position('generate_series(b.s, e.pay_until' in d) = 0
     or position('An approved exit' in d) = 0
     or position('as pay_until' in d) = 0 then
    raise exception 'attendance_cycle_report patch did not apply';
  end if;
  execute d;

  -- Payroll engine: days payable stop at the last working day, absence is
  -- not counted after it, and a withheld or settled final month is left out.
  d := pg_get_functiondef('public.generate_payroll(date)'::regprocedure);
  d := replace(d,
$o$           ((b.ce - greatest(b.cs, coalesce(nullif(r.date_of_joining,'')::date, b.cs))) + 1)::numeric as eligible_days,$o$,
$n$           greatest(0, (least(b.ce, coalesce(public.employee_last_working_day(r.employee_code), b.ce))
                        - greatest(b.cs, coalesce(nullif(r.date_of_joining,'')::date, b.cs))) + 1)::numeric as eligible_days,$n$);
  d := replace(d,
$o$                               public.payroll_absence_until(b.cs, b.ce), interval '1 day') g2(d)$o$,
$n$                               least(public.payroll_absence_until(b.cs, b.ce),
                                     coalesce(public.employee_last_working_day(r.employee_code), b.ce)),
                               interval '1 day') g2(d)$n$);
  d := replace(d,
$o$    from final f order by f.employee_code;$o$,
$n$    from final f
   where not public.payroll_final_salary_excluded(f.employee_code, f.cycle_end_)
   order by f.employee_code;$n$);
  if position('payroll_final_salary_excluded' in d) = 0
     or position('coalesce(public.employee_last_working_day(r.employee_code), b.ce)),' in d) = 0
     or position('greatest(0, (least(b.ce' in d) = 0 then
    raise exception 'generate_payroll patch did not apply';
  end if;
  execute d;

  -- Publishing: a held final month stays a draft until Management decides.
  d := pg_get_functiondef('public._publish_payslips(date,text[],text)'::regprocedure);
  d := replace(d,
$o$     where p.month_year = v_label and p.status = 'draft'
       and (p_employee_ids is null or p.employee_id = any(p_employee_ids))
    returning$o$,
$n$     where p.month_year = v_label and p.status = 'draft'
       and (p_employee_ids is null or p.employee_id = any(p_employee_ids))
       and not public.payroll_final_salary_held(p.employee_id, v_ce)
    returning$n$);
  d := replace(d,
$o$    employee_id := f.eid; employee_name := f.nm; outcome := 'published'; net_pay := f.np;
    return next;
  end loop;$o$,
$n$    employee_id := f.eid; employee_name := f.nm; outcome := 'published'; net_pay := f.np;
    return next;
  end loop;

  -- Leavers whose final salary Management has not released yet.
  for f in
    select p.employee_id as eid, p.emp_name as nm, p.net_pay as np
      from public.payslips p
     where p.month_year = v_label and p.status = 'draft'
       and (p_employee_ids is null or p.employee_id = any(p_employee_ids))
       and public.payroll_final_salary_held(p.employee_id, v_ce)
  loop
    employee_id := f.eid; employee_name := f.nm; outcome := 'held'; net_pay := f.np;
    return next;
  end loop;$n$);
  if position('payroll_final_salary_held(p.employee_id, v_ce)' in d) = 0
     or position('outcome := ''held''' in d) = 0 then
    raise exception '_publish_payslips patch did not apply';
  end if;
  execute d;

  -- retire_employee: employee_id is both an output column of the function
  -- and a column of retired_employee_ids, so "on conflict (employee_id)" was
  -- ambiguous and the function never once completed. Columns win.
  d := pg_get_functiondef('public.retire_employee(text,text)'::regprocedure);
  if position('#variable_conflict use_column' in d) = 0 then
    d := replace(d, E'AS $function$\ndeclare', E'AS $function$\n#variable_conflict use_column\ndeclare');
    if position('#variable_conflict use_column' in d) = 0 then
      raise exception 'retire_employee patch did not apply';
    end if;
    execute d;
  end if;
end $$;

-- 23:30 IST every night: close the accounts of people whose last working
-- day has come.
select cron.schedule('close-exited-accounts', '0 18 * * *',
                     'select public.close_exited_accounts()');
