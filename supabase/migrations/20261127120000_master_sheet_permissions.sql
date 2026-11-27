-- Salary master sheet: permissions taken in the cycle (HR's report, 27 Nov
-- 2026: "Permission not captured in master sheet"). Adds the number of
-- permissions and their minutes next to the leave columns; the half-day LOP
-- for going over 2 hours was already in permission_lop. A published payslip
-- shows what it was published with.

drop function if exists public.salary_master_sheet(date);
create function public.salary_master_sheet(p_cycle_end date)
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
  absence_counted_to date,
  cl_opening numeric, cl_availed numeric, cl_closing numeric,
  ml_opening numeric, ml_availed numeric, ml_closing numeric,
  el_opening numeric, el_availed numeric, el_closing numeric,
  permission_count integer, permission_minutes integer)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
#variable_conflict use_column
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can see the salary master sheet' using errcode = '42501';
  end if;
  return query
    with f as (select x.employee_id as eid, x.leave_details as ld,
                      x.permission_count as pc, x.permission_minutes as pm
                 from public._payslip_figures(p_cycle_end) x),
         ps as (select distinct on (y.employee_id) y.employee_id as eid, y.leave_details as ld,
                       y.permission_count as pc, y.permission_minutes as pm
                  from public.payslips y
                 where y.month_year = public.attendance_cycle_label(public.attendance_cycle_end(p_cycle_end))
                   and y.status = 'published'
                 order by y.employee_id, y.version desc)
    select m.*,
           (b.cl->>'opening')::numeric, (b.cl->>'taken')::numeric,
           (b.cl->>'opening')::numeric - (b.cl->>'taken')::numeric,
           (b.ml->>'opening')::numeric, (b.ml->>'taken')::numeric,
           (b.ml->>'opening')::numeric - (b.ml->>'taken')::numeric,
           (b.el->>'opening')::numeric, (b.el->>'taken')::numeric,
           (b.el->>'opening')::numeric - (b.el->>'taken')::numeric,
           case when m.payslip_status = 'published' and ps.eid is not null then ps.pc else f.pc end,
           case when m.payslip_status = 'published' and ps.eid is not null then ps.pm else f.pm end
      from public._salary_master_sheet(p_cycle_end) m
      left join f on f.eid = m.employee_id
      left join ps on ps.eid = m.employee_id
      cross join lateral (
        select case when m.payslip_status = 'published' and coalesce(ps.ld, '') like '[%'
                    then ps.ld::jsonb else f.ld end as ld) k
      cross join lateral (
        select (select e from jsonb_array_elements(coalesce(k.ld, '[]'::jsonb)) e where e->>'type' = 'CL' limit 1) as cl,
               (select e from jsonb_array_elements(coalesce(k.ld, '[]'::jsonb)) e where e->>'type' = 'ML' limit 1) as ml,
               (select e from jsonb_array_elements(coalesce(k.ld, '[]'::jsonb)) e where e->>'type' = 'EL' limit 1) as el) b
     order by m.employee_id;
end;
$$;

revoke all on function public.salary_master_sheet(date) from public, anon;
grant execute on function public.salary_master_sheet(date) to authenticated;
