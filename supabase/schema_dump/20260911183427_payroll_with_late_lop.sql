drop function if exists public.generate_payroll(date);

-- Late LOP joins the other day losses. A day is charged once: late_lop_days
-- counts only lates the permission pool could not absorb, and
-- permission_lop_days only permissions beyond the allowance, so the two
-- cannot deduct for the same minutes twice.
create function public.generate_payroll(p_cycle_end date default current_date)
returns table(
  employee_code text, employee_name text, designation text, department text,
  date_of_joining text, nwd integer, nowd numeric, days_lost numeric,
  actual_gross numeric, basic numeric, da numeric, hra numeric,
  conveyance numeric, other_allowance numeric, educational numeric,
  lta numeric, gross numeric,
  late_count integer, late_lop numeric, professional_tax numeric,
  permission_lop numeric, total_deductions numeric, net_pay numeric
)
language sql stable as $fn$
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
           r.days_worked::numeric, r.leave_taken, r.lop_days::numeric,
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
         f.professional_tax,
         round((f.basic+f.da+f.hra+f.conveyance+f.other_allowance+f.educational+f.lta)
               *(f.nowd/f.cycle_days) - f.professional_tax, 2)
    from final f order by f.employee_code;
$fn$;
