-- Unpaid absence is counted day by day, from the November 2026 cycle.
--
-- Until now absence was worked out as a difference: expected working days
-- less days with a check-in less leave days. A check-in on a Sunday, a
-- holiday or a day of approved comp off counted as a day present, so it
-- silently cancelled a weekday absence that had no leave behind it (in
-- October 2026: Devaraj and R. Chandru, absent Mon 19 Oct, had worked the
-- 2 Oct holiday). Joiners' expected days were also an estimate.
--
-- Now each working day from the joining date is either attended (a
-- check-in, or on-duty), covered by approved leave or comp off, or unpaid;
-- a half-day leave on a day not attended leaves half a day unpaid. Working
-- an off day counts only through an approved comp off.
--
-- Decided by Ronak on 20 Nov 2026, for the current and future cycles only:
-- cycles up to 25 Oct 2026 are paid and keep the rule they were paid
-- under, so October's issued figures do not change. The value of a day is
-- unchanged: monthly pay divided by the days in the 26th-to-25th cycle.

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
         f.professional_tax + coalesce(f.epf,0) + coalesce(f.esi,0) + coalesce(f.tds,0),
         -- Rounded to the nearest rupee (HR, October 2026).
         public.payroll_round_net(
           round((f.basic+f.da+f.hra+f.conveyance+f.other_allowance+f.educational+f.lta)
                 *(f.nowd/f.cycle_days),2)
           - f.professional_tax - coalesce(f.epf,0) - coalesce(f.esi,0) - coalesce(f.tds,0))
    from final f order by f.employee_code;
$function$;

-- The money-rule tests gain the case. Inserted into the live function before
-- its payroll row-count check; 20261113100100_money_rule_tests.sql holds the
-- full source.
do $zzpatch$
declare
  d text;
  anchor constant text :=
    $a$    if (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%') <> 10 then$a$;
begin
  d := pg_get_functiondef('public.run_money_rule_tests()'::regprocedure);
  if position('working a Sunday does not cancel' in d) > 0 then
    return;  -- already added
  end if;
  if position(anchor in d) = 0 then
    raise exception 'run_money_rule_tests: insertion point not found';
  end if;
  d := replace(d, anchor, $blk$    -- From the November 2026 cycle, absence is counted day by day: working a
    -- Sunday does not cancel a weekday absence (Ronak, 20 Nov 2026).
    insert into attendance_records(id, employee_name, employee_id, date, check_in_time, check_out_time)
    values ('ZZT-02_06-10-2030', 'ZZ Selftest ZZT-02', 'ZZT-02', '06/10/2030', '10:00', '14:00');
    select trim_scale(days_lost)::text into t from generate_payroll(ce) where employee_code = 'ZZT-02';
    res := res || jsonb_build_array(jsonb_build_object('t', 'payroll: working a Sunday does not cancel a weekday absence',
      'e', '1', 'a', t));

$blk$ || anchor);
  execute d;
end $zzpatch$;

-- Check before committing: every money rule passes, and October 2026 still
-- comes out exactly as issued.
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
   where p.month_year = '2026-10' and p.net_pay = g.net_pay and p.lop_days = g.days_lost;
  if v_n <> 12 then
    raise exception 'October 2026 no longer matches its issued payslips (% of 12 agree)', v_n;
  end if;
end $zzcheck$;
