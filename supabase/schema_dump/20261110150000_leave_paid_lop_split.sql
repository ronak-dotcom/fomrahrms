-- Applied 10 Nov 2026 as two migrations (leave_paid_lop_split_editable and
-- balance_and_payroll_use_exact_lop); recorded here together.
--
-- How a leave divides between paid days and loss of pay was fixed by rule
-- (two paid days per request, the rest unpaid) with no way to record what
-- was actually agreed. lop_days is now fractional and HR or Management can
-- set the split per request through set_leave_lop_split(). The manual value
-- is kept in lop_days_override so the sandwich recalculation cannot undo it.
--
-- Two readers were also corrected in place:
--   leave_balance     charged unpaid days to the leave bucket as well.
--   generate_payroll  took LOP as a whole number from the cycle report.
alter table public.leave_applications
  alter column lop_days type numeric(5,1) using lop_days::numeric;

alter table public.leave_applications
  add column if not exists lop_days_override numeric(5,1),
  add column if not exists lop_override_by   text,
  add column if not exists lop_override_at   timestamptz,
  add column if not exists lop_override_note text;

create or replace function public.keep_lop_override()
returns trigger language plpgsql as $$
begin
  if new.lop_days_override is not null then
    new.lop_days := least(greatest(new.lop_days_override, 0), coalesce(new.days, 0));
  end if;
  return new;
end;
$$;

create trigger trg_zz_keep_lop_override
  before insert or update on public.leave_applications
  for each row execute function public.keep_lop_override();

-- set_leave_lop_split(p_leave_id, p_lop_days, p_bucket, p_note): see the
-- live definition (pg_get_functiondef). HR or Management only; LOP between
-- 0 and the length of the leave, in half-day steps; null returns the request
-- to the rule; every change is written to audit_log.
--
-- leave_balance:    used = days - lop_days per request.
-- generate_payroll: lop_days read as an exact sum from leave_applications.
