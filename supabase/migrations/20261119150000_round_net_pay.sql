-- Net pay is rounded to the nearest rupee.
--
-- HR checked the October 2026 payroll workbook (17 Nov 2026) and marked three
-- people wrong, all for the same reason: paise. Their salary structures carry
-- 40 paise on HRA and LTA, or 48 paise on EPF, so net pay came to 19,999.80,
-- 27,499.80 and 44,719.52 where HR pays 20,000, 27,500 and 44,720. Rounding
-- net pay to the nearest rupee gives exactly HR's figures, and is applied to
-- everyone so the rule is the same for all. Earnings and deductions keep their
-- paise; only the final figure is rounded, and a payslip shows the difference
-- as "Rounded off".

create or replace function public.payroll_round_net(p_amount numeric)
returns numeric
language sql
immutable
as $$ select round(p_amount, 0) $$;

comment on function public.payroll_round_net(numeric) is
  'Net pay to the nearest rupee; 50 paise rounds up. HR, October 2026.';

create or replace function public.generate_payroll(p_cycle_end date DEFAULT CURRENT_DATE)
 RETURNS TABLE(employee_code text, employee_name text, designation text, department text, date_of_joining text, nwd integer, nowd numeric, days_lost numeric, actual_gross numeric, basic numeric, da numeric, hra numeric, conveyance numeric, other_allowance numeric, educational numeric, lta numeric, gross numeric, late_count integer, late_lop numeric, professional_tax numeric, permission_lop numeric, total_deductions numeric, net_pay numeric)
 LANGUAGE sql
 STABLE
AS $function$
  with b as (
    select public.attendance_cycle_start(p_cycle_end) as cs,
           public.attendance_cycle_end(p_cycle_end)   as ce
  ),
  rpt as (select * from public.attendance_cycle_report(p_cycle_end)),
  calc as (
    select r.employee_code, r.employee_name, r.designation, r.department,
           r.date_of_joining, r.late_count,
           ((b.ce - b.cs) + 1)::numeric as cycle_days,
           ((b.ce - greatest(b.cs, coalesce(nullif(r.date_of_joining,'')::date, b.cs))) + 1)::numeric as eligible_days,
           r.total_working_days::numeric as twd,
           r.days_worked::numeric, r.leave_taken, (select coalesce(sum(l.lop_days), 0) from leave_applications l
               where l.employee_id = r.employee_code and l.granted
                 and l.leave_type <> 'Permission'
                 and l.from_date <= b.ce and l.to_date >= b.cs)::numeric as lop_days,
           public.permission_lop_days(r.employee_code, p_cycle_end) as perm_lop,
           public.late_lop_days(r.employee_code, p_cycle_end) as late_lop,
           s.*
      from rpt r cross join b
      join salary_structures s on s.employee_id = r.employee_code
  ),
  lost as (
    select c.*,
           greatest(0, (c.twd * (c.eligible_days / nullif(c.cycle_days,0)))
                       - c.days_worked - c.leave_taken)
           + c.lop_days + c.perm_lop + c.late_lop as days_lost
      from calc c
  ),
  final as (select l.*, greatest(0, l.eligible_days - l.days_lost) as nowd from lost l)
  select f.employee_code, f.employee_name, f.designation, f.department,
         f.date_of_joining, f.cycle_days::int, round(f.nowd,2), round(f.days_lost,2),
         f.actual_gross,
         round(f.basic*(f.nowd/f.cycle_days),2), round(f.da*(f.nowd/f.cycle_days),2),
         round(f.hra*(f.nowd/f.cycle_days),2), round(f.conveyance*(f.nowd/f.cycle_days),2),
         round(f.other_allowance*(f.nowd/f.cycle_days),2),
         round(f.educational*(f.nowd/f.cycle_days),2), round(f.lta*(f.nowd/f.cycle_days),2),
         round((f.basic+f.da+f.hra+f.conveyance+f.other_allowance+f.educational+f.lta)
               *(f.nowd/f.cycle_days),2),
         f.late_count, f.late_lop, f.professional_tax, f.perm_lop,
         f.professional_tax + coalesce(f.epf,0) + coalesce(f.esi,0) + coalesce(f.tds,0),
         -- Rounded to the nearest rupee: see the note at the top.
         public.payroll_round_net(
           round((f.basic+f.da+f.hra+f.conveyance+f.other_allowance+f.educational+f.lta)
                 *(f.nowd/f.cycle_days),2)
           - f.professional_tax - coalesce(f.epf,0) - coalesce(f.esi,0) - coalesce(f.tds,0))
    from final f order by f.employee_code;
$function$;

-- The money-rule tests gain the rounding cases. They are inserted into the
-- live run_money_rule_tests() just before its payroll row-count check, so
-- the existing tests are untouched; 20261113100100_money_rule_tests.sql
-- holds the full, commented source with the same block.
do $zzpatch$
declare
  d text;
  anchor constant text :=
    $a$    if (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%') <> 10 then$a$;
begin
  d := pg_get_functiondef('public.run_money_rule_tests()'::regprocedure);
  if position('payroll_round_net' in d) > 0 then
    return;  -- already added
  end if;
  if position(anchor in d) = 0 then
    raise exception 'run_money_rule_tests: insertion point not found';
  end if;
  d := replace(d, anchor, $blk$    -- Net pay is rounded to the nearest rupee (HR, October 2026 check:
    -- 19,999.80 is paid as 20,000). Halves round up.
    res := res || jsonb_build_array(
      jsonb_build_object('t', 'payroll: net pay rounds to the nearest rupee (19,999.80 -> 20,000)',
        'e', '20000', 'a', trim_scale(payroll_round_net(19999.80))::text),
      jsonb_build_object('t', 'payroll: net pay rounds to the nearest rupee (44,719.52 -> 44,720)',
        'e', '44720', 'a', trim_scale(payroll_round_net(44719.52))::text),
      jsonb_build_object('t', 'payroll: net pay rounds down below 50 paise (77,899.15 -> 77,899)',
        'e', '77899', 'a', trim_scale(payroll_round_net(77899.15))::text),
      jsonb_build_object('t', 'payroll: 50 paise rounds up',
        'e', '101', 'a', trim_scale(payroll_round_net(100.50))::text),
      jsonb_build_object('t', 'payroll: every net pay is a whole rupee',
        'e', '0', 'a', (select count(*) from generate_payroll(ce)
                         where employee_code like 'ZZT-%' and net_pay <> round(net_pay))::text));

$blk$ || anchor);
  execute d;
end $zzpatch$;
