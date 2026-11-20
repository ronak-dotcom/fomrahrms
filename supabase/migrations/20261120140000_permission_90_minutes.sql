-- Permission may also be taken as 90 minutes (Ronak, 20 Nov 2026).
--
-- The allowance stays 2 hours per attendance cycle, in 30-minute steps:
-- 4 x 30, 2 x 60, 90 + 30, or 120 at once. Going over is not refused; each
-- permission over the allowance is half a day's LOP, as before.
-- 90 minutes was withdrawn earlier; the app's start/end-time picker could
-- still produce it, and the database then refused the request outright.

create or replace function public.permission_minutes_from_text(p text)
returns integer
language sql
immutable
as $$
  select case
    when p is null                      then null
    -- 90 first: '1 Hour 30 Minutes' also contains '1 Hour' and '30'.
    when p ilike '%1½%'                 then 90
    when p ilike '%1 1/2%'              then 90
    when p ilike '%1 Hour 30%'          then 90
    when p ilike '%1 Hr 30%'            then 90
    when p ilike '%90%'                 then 90
    when p ilike '%2 Hours%'            then 120
    when p ilike '%2 Hrs%'              then 120
    when p ilike '%120%'                then 120
    when p ilike '%1 Hour%'             then 60
    when p ilike '%1 Hr%'               then 60
    when p ilike '%60%'                 then 60
    when p ilike '%30 Minutes%'         then 30
    when p ilike '%30 Mins%'            then 30
    when p ilike '%30%'                 then 30
    else null
  end;
$$;

do $zzpatch$
declare
  d text := pg_get_functiondef('public.set_and_check_permission_minutes()'::regprocedure);
  a1 constant text := $a$new.permission_minutes not in (30,60,120)$a$;
  a2 constant text := $a$'Permission must be 30, 60 or 120 minutes. The allowance of 120 minutes per attendance cycle can be taken as 4x30, 2x60 or 1x120.'$a$;
begin
  if position(a1 in d) = 0 or position(a2 in d) = 0 then
    raise exception 'set_and_check_permission_minutes: text not found; not changed';
  end if;
  d := replace(d, a1, $r$new.permission_minutes not in (30,60,90,120)$r$);
  d := replace(d, a2, $r$'Permission is taken in 30-minute steps: 30, 60, 90 or 120 minutes. The allowance is 2 hours per attendance cycle; beyond it each permission is half a day''s loss of pay.'$r$);
  execute d;
end $zzpatch$;

-- Tests, added before the payroll row-count check of run_money_rule_tests().
do $zzpatch$
declare
  d text := pg_get_functiondef('public.run_money_rule_tests()'::regprocedure);
  anchor constant text := $a$    if (select count(*) from generate_payroll(ce) where employee_code like 'ZZT-%') <> 10 then$a$;
  block constant text := $b$    -- Permission may be 90 minutes (Ronak, 20 Nov 2026); 90 + 30 is the
    -- whole 2-hour allowance, and another 30 is half a day's LOP.
    insert into leave_applications(id, employee_name, employee_id, department, leave_type,
                                   from_date, to_date, days, reason, applied_on,
                                   manager_status, management_status, leave_bucket, is_half_day,
                                   permission_minutes)
    values ('zzt-06-p90', 'ZZ Selftest ZZT-06', 'ZZT-06', 'ZZ Selftest Dept', 'Permission',
            date '2030-10-14', date '2030-10-14', 1, 'Permission: 09:30–11:00 (90 min) | selftest',
            now() - interval '3 minutes', 'pending', 'pending', null, true, 90),
           ('zzt-06-p30', 'ZZ Selftest ZZT-06', 'ZZT-06', 'ZZ Selftest Dept', 'Permission',
            date '2030-10-15', date '2030-10-15', 1, 'Permission: 09:30–10:00 (30 min) | selftest',
            now() - interval '2 minutes', 'pending', 'pending', null, true, 30),
           ('zzt-06-p30b', 'ZZ Selftest ZZT-06', 'ZZT-06', 'ZZ Selftest Dept', 'Permission',
            date '2030-10-16', date '2030-10-16', 1, 'Permission: 09:30–10:00 (30 min) | selftest',
            now() - interval '1 minute', 'pending', 'pending', null, true, 30);
    select string_agg(id || ':' || permission_lop_half_day::text, ',' order by id) into t
      from leave_applications where id like 'zzt-06-p%';
    res := res || jsonb_build_array(
      jsonb_build_object('t', 'permission: 90 minutes is accepted; 90 + 30 fills the 2 hours; one more is half-day LOP',
        'e', 'zzt-06-p30:false,zzt-06-p30b:true,zzt-06-p90:false', 'a', t),
      jsonb_build_object('t', 'permission: "1 Hour 30 Minutes" reads as 90',
        'e', '90', 'a', permission_minutes_from_text('1 Hour 30 Minutes')::text));
    begin
      insert into leave_applications(id, employee_name, employee_id, department, leave_type,
                                     from_date, to_date, days, reason, applied_on,
                                     manager_status, management_status, is_half_day, permission_minutes)
      values ('zzt-06-p45', 'ZZ Selftest ZZT-06', 'ZZT-06', 'ZZ Selftest Dept', 'Permission',
              date '2030-10-17', date '2030-10-17', 1, 'Permission: 45 min | selftest', now(),
              'pending', 'pending', true, 45);
      t := 'accepted';
    exception when others then
      t := 'refused';
    end;
    res := res || jsonb_build_array(jsonb_build_object('t', 'permission: 45 minutes is not a 30-minute step',
      'e', 'refused', 'a', t));

$b$;
begin
  if position(anchor in d) = 0 then
    raise exception 'run_money_rule_tests: anchor not found';
  end if;
  execute replace(d, anchor, block || anchor);
end $zzpatch$;

do $zzcheck$
declare v_fail text;
begin
  select string_agg(test_name || ' (expected ' || coalesce(expected, 'null') || ', got ' || coalesce(actual, 'null') || ')', '; ')
    into v_fail from public.run_money_rule_tests() where not passed;
  if v_fail is not null then
    raise exception 'Money-rule tests failed: %', v_fail;
  end if;
end $zzcheck$;
