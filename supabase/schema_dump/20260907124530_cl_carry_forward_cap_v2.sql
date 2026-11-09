drop function if exists public.leave_balance(text, date);

-- CL accrues and carries forward, but no more than 2 days may actually be
-- taken. The accrued figure still shows so the employee sees what they have
-- earned; what they may spend is capped.
--
-- `usable` is separate from `available` on purpose: an employee looking at 9
-- and being allowed 2 needs to see the difference, not have it silently
-- applied and wonder why the number moved.
create function public.leave_balance(
  p_employee_id text, p_date date default current_date
)
returns table(
  bucket text, accrued numeric, used numeric, adjusted numeric,
  available numeric, usable numeric, cap numeric
)
language sql stable as $fn$
  with emp as (
    select u.employee_id,
           nullif(u.date_of_joining,'')::date as doj,
           coalesce(u.onroll_confirmed_at,'') <> '' as confirmed,
           coalesce(u.exempt_from_leave_rules,false) as unlimited
      from app_users u where u.employee_id = p_employee_id
  ),
  n as (select e.*, public.cycles_accrued(e.doj, p_date) as cycles from emp e),
  accrual as (
    select 'CL' as bucket,
           case when n.unlimited then 9999 else n.cycles end::numeric as accrued,
           case when n.unlimited then 9999 else 2 end::numeric as cap
      from n
    union all
    select 'ML',
           case when n.unlimited then 9999
                when n.confirmed then n.cycles else 0 end::numeric, 9999::numeric
      from n
    union all
    select 'EL',
           case when n.unlimited then 9999
                when n.confirmed then least(n.cycles, 25) else 0 end::numeric, 9999::numeric
      from n
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
  ),
  calc as (
    select ac.bucket, ac.accrued, ac.cap,
           coalesce(us.used,0) as used,
           coalesce(ad.adjusted,0) as adjusted,
           case when ac.accrued >= 9999 then 9999
                else greatest(0, ac.accrued + coalesce(ad.adjusted,0) - coalesce(us.used,0))
           end as available
      from accrual ac
      left join used us on us.bucket = ac.bucket
      left join adj  ad on ad.bucket = ac.bucket
  )
  select bucket, accrued, used, adjusted, available,
         least(available, cap) as usable, cap
    from calc
   order by case bucket when 'CL' then 1 when 'ML' then 2 else 3 end;
$fn$;
