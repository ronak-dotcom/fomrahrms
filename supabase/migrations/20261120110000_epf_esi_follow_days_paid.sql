-- EPF and ESI follow the days paid, from the November 2026 cycle.
--
-- They were deducted as the fixed monthly amounts in salary_structures, so
-- someone with loss of pay paid full PF and ESI on pay they did not earn.
-- Ronak, 20 Nov 2026: EPF and ESI are linked to the working days, and the
-- scaling is the same as for earnings - monthly amount x payable days /
-- days in the cycle. EPF is kept to the paisa, as the salary sheets keep it
-- (2,940.48); ESI is rounded up to the next rupee, as ESI is and as the
-- sheets show (113, 128). Professional tax and TDS stay as set.
--
-- For the current and future cycles only: cycles up to 25 Oct 2026 are paid
-- and keep the flat amounts. The check at the end confirms October 2026 still
-- matches its 12 issued payslips.

create or replace function public.payroll_scaled_epf(
  p_epf numeric, p_payable numeric, p_cycle_days numeric, p_cycle_end date)
returns numeric
language sql
immutable
as $$
  select case when p_cycle_end >= date '2026-11-25' and coalesce(p_cycle_days, 0) > 0
              then round(coalesce(p_epf, 0) * p_payable / p_cycle_days, 2)
              else coalesce(p_epf, 0) end
$$;

create or replace function public.payroll_scaled_esi(
  p_esi numeric, p_payable numeric, p_cycle_days numeric, p_cycle_end date)
returns numeric
language sql
immutable
as $$
  select case when p_cycle_end >= date '2026-11-25' and coalesce(p_cycle_days, 0) > 0
              then ceil(coalesce(p_esi, 0) * p_payable / p_cycle_days)
              else coalesce(p_esi, 0) end
$$;

comment on function public.payroll_scaled_epf(numeric, numeric, numeric, date) is
  'EPF for the days paid (monthly x payable / cycle days, to the paisa), from the November 2026 cycle.';
comment on function public.payroll_scaled_esi(numeric, numeric, numeric, date) is
  'ESI for the days paid (monthly x payable / cycle days, rounded up), from the November 2026 cycle.';

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
           b.ce as cycle_end_,
           ab.absent,
           r.days_worked::numeric, r.leave_taken, (select coalesce(sum(l.lop_days), 0) from leave_applications l
               where l.employee_id = r.employee_code and l.granted
                 and l.leave_type <> 'Permission'
                 and l.from_date <= b.ce and l.to_date >= b.cs)::numeric as lop_days,
           public.permission_lop_days(r.employee_code, p_cycle_end) as perm_lop,
           public.late_lop_days(r.employee_code, p_cycle_end) as late_lop,
           s.*
      from rpt r cross join b
      join salary_structures s on s.employee_id = r.employee_code
      -- Day by day (from the November 2026 cycle): each working day from the
      -- joining date with no check-in and no approved leave, comp off or
      -- on-duty is unpaid; a half-day leave on such a day leaves half unpaid.
      -- Working a holiday or weekly off does not cancel it; that is what an
      -- approved comp off is for.
      left join lateral (
        select coalesce(sum(
                 case when exists (select 1 from public.attendance_records a
                                    where a.employee_id = r.employee_code and a.date_iso = x.dd
                                      and (coalesce(a.check_in_time, '') <> '' or coalesce(a.on_duty, false)))
                        then 0
                      when exists (select 1 from public.leave_applications l
                                    where l.employee_id = r.employee_code and l.granted
                                      and l.leave_type <> 'Permission'
                                      and x.dd between l.from_date and l.to_date
                                      and not coalesce(l.is_half_day, false))
                        then 0
                      when exists (select 1 from public.leave_applications l
                                    where l.employee_id = r.employee_code and l.granted
                                      and l.leave_type <> 'Permission'
                                      and x.dd between l.from_date and l.to_date)
                        then 0.5
                      else 1 end), 0)::numeric as absent
          from generate_series(greatest(b.cs, coalesce(nullif(r.date_of_joining, '')::date, b.cs)),
                               b.ce, interval '1 day') g2(d)
          cross join lateral (select g2.d::date as dd) x
         where not public.is_non_working_day(r.employee_name, x.dd)
      ) ab on true
  ),
  lost as (
    select c.*,
           -- Cycles up to 25 Oct 2026 keep the rule they were paid under.
           case when c.cycle_end_ >= date '2026-11-25' then c.absent
                else greatest(0, (c.twd * (c.eligible_days / nullif(c.cycle_days,0)))
                                 - c.days_worked - c.leave_taken) end
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
         -- EPF and ESI follow the days paid from the November 2026 cycle;
         -- professional tax and TDS stay as set.
         f.professional_tax
           + public.payroll_scaled_epf(f.epf, f.nowd, f.cycle_days, f.cycle_end_)
           + public.payroll_scaled_esi(f.esi, f.nowd, f.cycle_days, f.cycle_end_)
           + coalesce(f.tds,0),
         -- Rounded to the nearest rupee (HR, October 2026).
         public.payroll_round_net(
           round((f.basic+f.da+f.hra+f.conveyance+f.other_allowance+f.educational+f.lta)
                 *(f.nowd/f.cycle_days),2)
           - f.professional_tax
           - public.payroll_scaled_epf(f.epf, f.nowd, f.cycle_days, f.cycle_end_)
           - public.payroll_scaled_esi(f.esi, f.nowd, f.cycle_days, f.cycle_end_)
           - coalesce(f.tds,0))
    from final f order by f.employee_code;
$function$;

-- The payslip lines show the same EPF and ESI the totals use.
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
         g.professional_tax,
         public.payroll_scaled_epf(s.epf, g.nowd, g.nwd, b.ce),
         public.payroll_scaled_esi(s.esi, g.nowd, g.nwd, b.ce),
         coalesce(s.tds, 0),
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

do $zzpatch$
declare
  d text;
  anchor constant text :=
    $a$    if (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%') <> 10 then$a$;
begin
  d := pg_get_functiondef('public.run_money_rule_tests()'::regprocedure);
  if position('EPF follows the days paid' in d) > 0 then
    return;  -- already added
  end if;
  if position(anchor in d) = 0 then
    raise exception 'run_money_rule_tests: insertion point not found';
  end if;
  d := replace(d, anchor, $blk$    -- From the November 2026 cycle EPF and ESI follow the days paid (Ronak,
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
                              || trim_scale(payroll_scaled_esi(128, 29, 30, date '2026-10-25'))::text));

$blk$ || anchor);
  execute d;
end $zzpatch$;

-- Check before committing: every money rule passes, October 2026 still
-- matches its issued payslips, and the November figures' lines add up.
do $zzcheck$
declare v_fail text; v_n int;
begin
  select string_agg(test_name || ' (expected ' || expected || ', got ' || actual || ')', '; ')
    into v_fail from public.run_money_rule_tests() where not passed;
  if v_fail is not null then
    raise exception 'Money-rule tests failing: %', v_fail;
  end if;
  select count(*) into v_n
    from public.payslips p
    join public.generate_payroll(date '2026-10-25') g on g.employee_code = p.employee_id
   where p.month_year = '2026-10' and p.net_pay = g.net_pay and p.total_deductions = g.total_deductions;
  if v_n <> 12 then
    raise exception 'October 2026 no longer matches its issued payslips (% of 12 agree)', v_n;
  end if;
  select count(*) into v_n
    from public._payslip_figures(date '2026-11-25') f
   where f.professional_tax + f.epf + f.esi + f.tds <> f.total_deductions;
  if v_n <> 0 then
    raise exception 'November 2026: % payslip(s) whose deduction lines do not add up to the total', v_n;
  end if;
end $zzcheck$;
