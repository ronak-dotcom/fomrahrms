-- Per-bucket balance for one employee: what they have accrued this leave
-- year, what they have used, HR's adjustments, and what remains.
create or replace function public.leave_balance(
  p_employee_id text, p_date date default current_date
)
returns table(
  bucket text, accrued numeric, used numeric, adjusted numeric, available numeric
)
language sql stable as $fn$
  with emp as (
    select u.employee_id, u.name,
           nullif(u.date_of_joining,'')::date as doj,
           coalesce(u.onroll_confirmed_at,'') <> '' as confirmed,
           coalesce(u.exempt_from_leave_rules,false) as unlimited
      from app_users u where u.employee_id = p_employee_id
  ),
  n as (
    select e.*, public.cycles_accrued(e.doj, p_date) as cycles from emp e
  ),
  accrual as (
    select 'CL' as bucket,
           case when n.unlimited then 9999
                -- Probation earns CL only: one leave of any type per cycle,
                -- and CL is the bucket it draws from.
                else n.cycles end::numeric as accrued
      from n
    union all
    select 'ML', case when n.unlimited then 9999
                      when n.confirmed then n.cycles else 0 end::numeric from n
    union all
    -- EL keeps accumulating across leave years but never past 25.
    select 'EL', case when n.unlimited then 9999
                      when n.confirmed then least(n.cycles, 25) else 0 end::numeric from n
  ),
  used as (
    select l.bucket, sum(l.days)::numeric as used
      from (
        select coalesce(nullif(la.leave_bucket,''),
                        case when la.leave_type ilike '%medical%'
                               or la.leave_type ilike '%sick%' then 'ML'
                             when la.leave_type ilike '%earned%' then 'EL'
                             when la.leave_type ilike '%lop%'    then 'LOP'
                             else 'CL' end) as bucket,
               case when la.is_half_day then 0.5 else la.days end as days
          from leave_applications la
         where la.employee_id = p_employee_id
           and la.leave_type <> 'Permission'
           -- Management's decision wins where it exists, exactly as the app
           -- resolves it; counting a manager-approved day that Management
           -- later denied would overstate usage.
           and case when la.management_status <> 'pending'
                    then la.management_status else la.manager_status end = 'approved'
           and la.from_date >= public.leave_year_start(p_date)
           and la.from_date <= p_date
      ) l group by l.bucket
  ),
  adj as (
    select a.bucket, sum(a.days)::numeric as adjusted
      from leave_adjustments a
     where a.employee_id = p_employee_id
       and a.effective_on >= public.leave_year_start(p_date)
       and a.effective_on <= p_date
     group by a.bucket
  )
  select ac.bucket,
         ac.accrued,
         coalesce(us.used, 0),
         coalesce(ad.adjusted, 0),
         case when ac.accrued >= 9999 then 9999
              else greatest(0, ac.accrued + coalesce(ad.adjusted,0) - coalesce(us.used,0))
         end
    from accrual ac
    left join used us on us.bucket = ac.bucket
    left join adj  ad on ad.bucket = ac.bucket
   order by case ac.bucket when 'CL' then 1 when 'ML' then 2 else 3 end;
$fn$;
