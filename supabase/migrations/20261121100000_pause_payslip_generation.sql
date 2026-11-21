-- Generating and reissuing payslips is paused for the time being (Ronak,
-- 21 Nov 2026). The app's button is off; this also stops an older copy of
-- the app. Publishing drafts already made, the figures and the master sheet
-- are not affected. To resume: create or replace payslip_generation_paused()
-- to return false.
create or replace function public.payslip_generation_paused()
returns boolean
language sql
immutable
as $$ select true $$;

do $zzpatch$
declare
  d text := pg_get_functiondef('public.issue_payslips(date, text[], boolean)'::regprocedure);
  anchor constant text := $a$    raise exception 'Only HR or Management can issue payslips' using errcode = '42501';
  end if;$a$;
begin
  if position(anchor in d) = 0 then
    raise exception 'issue_payslips: anchor not found';
  end if;
  execute replace(d, anchor, anchor || $b$
  if public.payslip_generation_paused() then
    raise exception 'Generating payslips is paused for now.' using errcode = 'check_violation';
  end if;$b$);
end $zzpatch$;

-- The internal function is untouched, so the money-rule tests still run it.
do $zzcheck$
declare v_fail text;
begin
  select string_agg(test_name, '; ') into v_fail from public.run_money_rule_tests() where not passed;
  if v_fail is not null then raise exception 'Money-rule tests failed: %', v_fail; end if;
end $zzcheck$;
