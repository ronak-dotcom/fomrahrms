-- At most 2 paid CL days per pay cycle (Ronak, 27 Nov 2026).
--
-- "In a month max 2 CL allowed, after which if CL is taken it is LOP only."
-- Until now the only limit was per request (days beyond 2 in one request are
-- LOP), so CL taken as separate requests in the same cycle was all paid:
-- Saurabh took 2 + 0.5 + 2 CL days in November with no LOP.
--
-- Now, for confirmed staff, the paid CL days in a pay cycle (26th to 25th)
-- add up to at most 2, in the order the requests were made; every CL day
-- beyond that is LOP. Probation stays at 1 paid day per cycle (its own rule).
-- From the November 2026 cycle; earlier cycles are paid and closed.
-- A split HR or Management recorded on a leave (lop_days_override) still
-- wins. If an earlier CL leave is rejected or cancelled, the later ones in
-- the cycle are worked out again.

create or replace function public.leave_charge_bucket(p_leave_type text, p_bucket text)
returns text
language sql
immutable
as $$
  select case when p_leave_type ilike '%comp%off%' then 'CO'
              when coalesce(p_bucket, '') in ('CL', 'ML', 'EL', 'LOP') then p_bucket
              when p_leave_type ilike '%medical%' or p_leave_type ilike '%sick%' then 'ML'
              when p_leave_type ilike '%earned%' then 'EL'
              when p_leave_type ilike '%lop%' then 'LOP'
              else 'CL' end;
$$;

create or replace function public.enforce_monthly_cl_cap()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_used numeric := 0;
  v_this numeric;
begin
  if new.leave_type = 'Permission' then return new; end if;
  if public.leave_charge_bucket(new.leave_type, new.leave_bucket) <> 'CL' then return new; end if;
  if public.attendance_cycle_end(new.from_date) < date '2026-11-25' then return new; end if;
  if coalesce(public.is_exempt_from_leave_rules(new.employee_id, new.employee_name), false) then return new; end if;
  if not coalesce(public.is_employee_confirmed(new.employee_id, new.employee_name), false) then return new; end if;
  if not public.leave_is_live(new.manager_status, new.management_status) then return new; end if;
  if tg_op = 'UPDATE'
     and new.from_date = old.from_date and new.to_date = old.to_date
     and new.is_half_day is not distinct from old.is_half_day
     and new.leave_type = old.leave_type
     and new.leave_bucket is not distinct from old.leave_bucket
     and coalesce(current_setting('app.recalc_cl_cap', true), '') <> 'on' then
    return new;
  end if;

  -- Paid CL already taken this cycle by requests made before this one.
  select coalesce(sum(greatest(0,
           (case when l.is_half_day then 0.5 else l.days end) - coalesce(l.lop_days, 0))), 0)
    into v_used
    from public.leave_applications l
   where l.id is distinct from new.id
     and l.employee_id = new.employee_id
     and l.leave_type <> 'Permission'
     and public.leave_charge_bucket(l.leave_type, l.leave_bucket) = 'CL'
     and public.leave_is_live(l.manager_status, l.management_status)
     and public.attendance_cycle_start(l.from_date) = public.attendance_cycle_start(new.from_date)
     and (l.applied_on < coalesce(new.applied_on, now())
          or (l.applied_on = new.applied_on and l.id < new.id));

  v_this := case when coalesce(new.is_half_day, false) then 0.5 else coalesce(new.days, 0) end;
  new.lop_days := greatest(coalesce(new.lop_days, 0),
                           greatest(0, v_this - greatest(0, 2 - v_used)));
  return new;
end;
$$;

-- Runs after the sandwich rule and before the recorded split
-- (trg_zz_keep_lop_override), like the probation rule.
drop trigger if exists trg_enforce_monthly_cl_cap on public.leave_applications;
create trigger trg_enforce_monthly_cl_cap
  before insert or update on public.leave_applications
  for each row execute function public.enforce_monthly_cl_cap();

-- Works a person's CL in one cycle out again, in the order requested: the
-- per-request rule first (sandwich), then this cap.
create or replace function public.recalc_cl_cap(p_employee_id text, p_cycle_end date)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r record;
  n integer := 0;
begin
  -- Confirmed staff only: the cap governs their CL. Working probation staff's
  -- leave out again here would drop the LOP their own rule set.
  if coalesce(public.is_exempt_from_leave_rules(p_employee_id, ''), false)
     or not coalesce(public.is_employee_confirmed(p_employee_id, ''), false) then
    return 0;
  end if;
  perform set_config('app.recalc_sandwich', 'on', true);
  perform set_config('app.recalc_cl_cap', 'on', true);
  for r in
    select l.id from public.leave_applications l
     where l.employee_id = p_employee_id
       and l.leave_type <> 'Permission'
       and public.leave_charge_bucket(l.leave_type, l.leave_bucket) = 'CL'
       and public.leave_is_live(l.manager_status, l.management_status)
       and public.attendance_cycle_end(l.from_date) = public.attendance_cycle_end(p_cycle_end)
     order by l.applied_on, l.id
  loop
    update public.leave_applications set days = days where id = r.id;
    n := n + 1;
  end loop;
  perform set_config('app.recalc_sandwich', '', true);
  perform set_config('app.recalc_cl_cap', '', true);
  return n;
end;
$$;

-- A CL leave rejected, cancelled or removed frees its paid days for the
-- later requests in the cycle.
create or replace function public.trg_cl_cap_follow_status()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if pg_trigger_depth() > 1 then return null; end if;
  if tg_op = 'DELETE' then
    if public.leave_charge_bucket(old.leave_type, old.leave_bucket) = 'CL' and old.leave_type <> 'Permission' then
      perform public.recalc_cl_cap(old.employee_id, public.attendance_cycle_end(old.from_date));
    end if;
    return null;
  end if;
  if public.leave_charge_bucket(new.leave_type, new.leave_bucket) = 'CL' and new.leave_type <> 'Permission'
     and public.leave_is_live(old.manager_status, old.management_status)
     and not public.leave_is_live(new.manager_status, new.management_status) then
    perform public.recalc_cl_cap(new.employee_id, public.attendance_cycle_end(new.from_date));
  end if;
  return null;
end;
$$;

drop trigger if exists trg_cl_cap_follow_status on public.leave_applications;
create trigger trg_cl_cap_follow_status
  after update or delete on public.leave_applications
  for each row execute function public.trg_cl_cap_follow_status();

revoke all on function public.recalc_cl_cap(text, date) from public, anon, authenticated;

-- What the apply-leave form offers as usable CL: what is left of this
-- cycle's 2 paid days (confirmed staff), not 2 per request.
do $zzpatch$
declare
  d text := pg_get_functiondef('public.leave_balance(text, date)'::regprocedure);
  a1 constant text := $a$  select bucket, accrued, used, adjusted, available,
         least(available, cap) as usable, cap
    from calc$a$;
  b1 constant text := $b$  select calc.bucket, accrued, used, adjusted, available,
         least(available,
               case when calc.bucket = 'CL' and calc.cap = 2
                    then greatest(0, 2 - coalesce((select cu.paid from cycle_cl cu), 0))
                    else calc.cap end) as usable,
         cap
    from calc$b$;
  a2 constant text := $a$  calc as ($a$;
  b2 constant text := $b$  cycle_cl as (
    select coalesce(sum(greatest(0, (case when la.is_half_day then 0.5 else la.days end)
                                     - coalesce(la.lop_days, 0))), 0) as paid
      from leave_applications la
     where la.employee_id = p_employee_id
       and la.leave_type <> 'Permission'
       and public.leave_charge_bucket(la.leave_type, la.leave_bucket) = 'CL'
       and public.leave_is_live(la.manager_status, la.management_status)
       and public.attendance_cycle_start(la.from_date) = public.attendance_cycle_start(p_date)
  ),
  calc as ($b$;
begin
  if position(a1 in d) = 0 or position(a2 in d) = 0 then
    raise exception 'leave_balance: text not found';
  end if;
  d := replace(d, a1, b1);
  d := replace(d, a2, b2);
  execute d;
end $zzpatch$;

-- Tests, before the payroll row-count check of run_money_rule_tests().
do $zzpatch$
declare
  d text := pg_get_functiondef('public.run_money_rule_tests()'::regprocedure);
  anchor constant text := $a$    if (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%') <> 10 then$a$;
  block constant text := $b$    -- At most 2 paid CL days per cycle (Ronak, 27 Nov 2026). ZZT-09 has
    -- already used 2 paid CL days (12-14 Oct, 3 days, 1 LOP); one more CL
    -- day in the cycle is all LOP. Rejecting the first frees the days.
    insert into leave_applications(id, employee_name, employee_id, department, leave_type,
                                   from_date, to_date, days, reason, applied_on,
                                   manager_status, management_status, leave_bucket, is_half_day)
    values ('zzt-09-cl2', 'ZZ Selftest ZZT-09', 'ZZT-09', 'ZZ Selftest Dept', 'Personal Leave',
            date '2030-10-21', date '2030-10-21', 1, 'selftest', now() + interval '1 minute',
            'pending', 'pending', 'CL', false);
    update leave_applications set management_status = 'approved' where id = 'zzt-09-cl2';
    select trim_scale(lop_days)::text into t from leave_applications where id = 'zzt-09-cl2';
    res := res || jsonb_build_array(jsonb_build_object('t', 'CL: beyond 2 paid days in a cycle, a further CL day is LOP',
      'e', '1', 'a', t));
    select trim_scale(usable)::text into t from leave_balance('ZZT-09', date '2030-10-21') where bucket = 'CL';
    res := res || jsonb_build_array(jsonb_build_object('t', 'CL: nothing usable once 2 paid days are taken in the cycle',
      'e', '0', 'a', t));
    update leave_applications set management_status = 'denied' where id = 'zzt-09-cl';
    select trim_scale(lop_days)::text into t from leave_applications where id = 'zzt-09-cl2';
    res := res || jsonb_build_array(jsonb_build_object('t', 'CL: rejecting the earlier leave makes the later one paid',
      'e', '0', 'a', t));
    update leave_applications set management_status = 'approved' where id = 'zzt-09-cl';
    delete from leave_applications where id = 'zzt-09-cl2';
    res := res || jsonb_build_array(jsonb_build_object('t', 'CL: the cap does not apply to cycles up to 25 Oct 2026',
      'e', 'CL', 'a', leave_charge_bucket('Personal Leave', 'CL')));

$b$;
begin
  if position(anchor in d) = 0 then raise exception 'run_money_rule_tests: anchor not found'; end if;
  execute replace(d, anchor, block || anchor);
end $zzpatch$;

-- November 2026 and later: apply the cap to CL already on record.
do $zzapply$
declare r record;
begin
  for r in
    select distinct l.employee_id, public.attendance_cycle_end(l.from_date) as ce
      from public.leave_applications l
     where l.leave_type <> 'Permission'
       and public.leave_charge_bucket(l.leave_type, l.leave_bucket) = 'CL'
       and public.leave_is_live(l.manager_status, l.management_status)
       and public.attendance_cycle_end(l.from_date) >= date '2026-11-25'
       and coalesce(l.employee_id, '') <> ''
  loop
    perform public.recalc_cl_cap(r.employee_id, r.ce);
  end loop;
end $zzapply$;

do $zzcheck$
declare v_fail text;
begin
  select string_agg(test_name || ' (expected ' || coalesce(expected, 'null') || ', got ' || coalesce(actual, 'null') || ')', '; ')
    into v_fail from public.run_money_rule_tests() where not passed;
  if v_fail is not null then raise exception 'Money-rule tests failed: %', v_fail; end if;
  if (select sum(net_pay) from public.payslips where month_year = '2026-10') <> 580025 then
    raise exception 'October 2026 payslips changed';
  end if;
end $zzcheck$;
