-- Applied live on 25 Nov 2026.
--
-- 1. PF, ESI and professional tax are fixed monthly amounts, not linked to
--    working days (Ronak, 25 Nov 2026). Replaces the 20 Nov rule that scaled
--    EPF and ESI to the days paid from the November 2026 cycle. The two
--    functions keep their signatures so every caller follows.
-- 2. The money-rule self-test now checks the fixed amounts.
-- 3. The attendance report (and so payroll) leaves out anyone who had not
--    joined by the cycle's last day. Aravindhasamy I (joined 28 Oct 2026)
--    appeared in October's payroll with 0 days and a net pay of -208.

create or replace function public.payroll_scaled_epf(p_epf numeric, p_payable numeric, p_cycle_days numeric, p_cycle_end date)
returns numeric language sql immutable as $$
  select coalesce(p_epf, 0)
$$;

create or replace function public.payroll_scaled_esi(p_esi numeric, p_payable numeric, p_cycle_days numeric, p_cycle_end date)
returns numeric language sql immutable as $$
  select coalesce(p_esi, 0)
$$;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.run_money_rule_tests()'::regprocedure);
  d := replace(d,
$o$    -- From the November 2026 cycle EPF and ESI follow the days paid (Ronak,
    -- 20 Nov 2026): EPF to the paisa, ESI rounded up to the rupee.
    select trim_scale(total_deductions)::text into t from generate_payroll(ce) where employee_code = 'ZZT-02';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payroll: EPF follows the days paid (29 of 30 days: 1,800 -> 1,740, plus PT 208)',
      'e', '1948', 'a', t));
    update salary_structures set esi = 128 where employee_id = 'ZZT-05';
    select trim_scale(total_deductions)::text into t from generate_payroll(ce) where employee_code = 'ZZT-05';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payroll: ESI follows the days paid, rounded up (28.5 of 30: 128 -> 122; EPF 1,710; PT 208)',
      'e', '2040', 'a', t));
    res := res || jsonb_build_array(
      jsonb_build_object('t', 'payroll: EPF and ESI are not scaled for cycles up to 25 Oct 2026',
        'e', '1800/128', 'a', trim_scale(payroll_scaled_epf(1800, 29, 30, date '2026-10-25'))::text || '/'
                              || trim_scale(payroll_scaled_esi(128, 29, 30, date '2026-10-25'))::text));$o$,
$n$    -- PF, ESI and professional tax are fixed monthly amounts, not linked to
    -- working days (Ronak, 25 Nov 2026).
    select trim_scale(total_deductions)::text into t from generate_payroll(ce) where employee_code = 'ZZT-02';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payroll: EPF is the full monthly amount with a day lost (29 of 30 days: EPF 1,800 + PT 208)',
      'e', '2008', 'a', t));
    update salary_structures set esi = 128 where employee_id = 'ZZT-05';
    select trim_scale(total_deductions)::text into t from generate_payroll(ce) where employee_code = 'ZZT-05';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payroll: ESI is the full monthly amount with LOP (28.5 of 30: EPF 1,800 + ESI 128 + PT 208)',
      'e', '2136', 'a', t));
    res := res || jsonb_build_array(
      jsonb_build_object('t', 'payroll: EPF and ESI are fixed whatever the days paid',
        'e', '1800/128', 'a', trim_scale(payroll_scaled_epf(1800, 20, 30, date '2026-11-25'))::text || '/'
                              || trim_scale(payroll_scaled_esi(128, 20, 30, date '2026-11-25'))::text));$n$);
  if position('EPF and ESI are fixed whatever the days paid' in d) = 0 then
    raise exception 'run_money_rule_tests patch did not apply';
  end if;
  execute d;

  d := pg_get_functiondef('public.attendance_cycle_report(date, text[])'::regprocedure);
  d := replace(d,
$o$       and not coalesce(u.oversight_only,false)
       and not coalesce(u.exempt_from_attendance,false)$o$,
$n$       and not coalesce(u.oversight_only,false)
       and not coalesce(u.exempt_from_attendance,false)
       -- Not in a cycle that ended before they joined: Aravindhasamy I
       -- (joined 28 Oct 2026) appeared in October's payroll with 0 days and
       -- professional tax only, a net pay of -208.
       and (nullif(u.date_of_joining,'') is null or nullif(u.date_of_joining,'')::date <= b.e)$n$);
  if position('Not in a cycle that ended before they joined' in d) = 0 then
    raise exception 'attendance_cycle_report patch did not apply';
  end if;
  execute d;
end $$;
