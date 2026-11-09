-- Payroll for a cycle, built from the stored structure and the attendance the
-- system already records. Replaces maintaining it in a spreadsheet.
--
-- Pro-rating follows the sheet: each component is scaled by
-- days_worked / working_days, not just gross, so a payslip shows the same
-- component breakdown at part attendance as at full.
create or replace function public.generate_payroll(p_cycle_end date default current_date)
returns table(
  employee_code text, employee_name text, designation text, department text,
  date_of_joining text, nwd integer, nowd numeric,
  actual_gross numeric, basic numeric, da numeric, hra numeric,
  conveyance numeric, other_allowance numeric, educational numeric,
  lta numeric, gross numeric,
  late_deduction numeric, professional_tax numeric,
  permission_lop numeric, total_deductions numeric, net_pay numeric
)
language sql stable as $fn$
  with rpt as (
    select * from public.attendance_cycle_report(p_cycle_end)
  ),
  calc as (
    select r.employee_code, r.employee_name, r.designation, r.department,
           r.date_of_joining,
           r.total_working_days as nwd,
           -- Days actually paid for: worked, plus approved leave, less LOP.
           -- Leave is paid, so excluding it would dock someone for taking it.
           greatest(0, r.days_worked + r.leave_taken - r.lop_days
                       - public.permission_lop_days(r.employee_code, p_cycle_end))::numeric as nowd,
           s.*
      from rpt r
      join salary_structures s on s.employee_id = r.employee_code
  ),
  prorated as (
    select c.*,
           -- Guarded: a cycle with no working days would divide by zero.
           case when c.nwd > 0 then least(1.0, c.nowd / c.nwd::numeric) else 0 end as ratio
      from calc c
  )
  select p.employee_code, p.employee_name, p.designation, p.department,
         p.date_of_joining, p.nwd, p.nowd,
         p.actual_gross,
         round(p.basic * p.ratio, 2),
         round(p.da * p.ratio, 2),
         round(p.hra * p.ratio, 2),
         round(p.conveyance * p.ratio, 2),
         round(p.other_allowance * p.ratio, 2),
         round(p.educational * p.ratio, 2),
         round(p.lta * p.ratio, 2),
         round((p.basic + p.da + p.hra + p.conveyance + p.other_allowance
                + p.educational + p.lta) * p.ratio, 2) as gross,
         0::numeric as late_deduction,
         p.professional_tax,
         -- Already removed from nowd above; reported so the sheet shows why.
         public.permission_lop_days(p.employee_code, p_cycle_end),
         p.professional_tax as total_deductions,
         round((p.basic + p.da + p.hra + p.conveyance + p.other_allowance
                + p.educational + p.lta) * p.ratio - p.professional_tax, 2) as net_pay
    from prorated p
   order by p.employee_code;
$fn$;
