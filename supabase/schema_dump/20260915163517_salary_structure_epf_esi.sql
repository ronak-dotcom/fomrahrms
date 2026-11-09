-- EPF was the constant 1800 for everyone. It does not apply to all staff —
-- it depends on wages and on whether the employee is enrolled — so a flat
-- constant deducts from people who owe nothing and cannot be corrected.
--
-- Nullable rather than defaulted to 1800: a null means "not set, fall back to
-- the old constant" while zero means "explicitly not applicable". Defaulting
-- to 1800 would silently re-apply the very problem to every existing row.
alter table salary_structures add column if not exists epf numeric;
alter table salary_structures add column if not exists esi numeric;
alter table salary_structures add column if not exists tds numeric;

comment on column salary_structures.epf is
  'Monthly EPF deduction. NULL = not set. 0 = explicitly not applicable — the two are different and payroll must not conflate them.';

-- Seed from what is already known, so HR is correcting rather than entering
-- from scratch. Only the 6 with structures; the rest get theirs when created.
update salary_structures s
   set epf = case when coalesce(u.pf_number,'') <> '' then 1800 else 0 end
  from app_users u
 where u.employee_id = s.employee_id and s.epf is null;

select s.employee_id, u.name, coalesce(u.pf_number,'(none)') as pf_no, s.epf
  from salary_structures s join app_users u on u.employee_id = s.employee_id
 order by s.employee_id;
