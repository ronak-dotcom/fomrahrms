-- attendance_records.date is TEXT in dd/MM/yyyy, so it sorts lexically:
-- '01/08/2026' sorts BEFORE '30/07/2026'. Any report, export or query ordered
-- by that column misorders across a month boundary.
--
-- Converting the column outright would require changing the Flutter app's
-- storage-key sites at the same time; doing the DB half alone makes the app's
-- .eq('date', '31/07/2026') lookups miss, so today's check-in would not be
-- found and duplicate rows would be created. This adds a STORED GENERATED
-- column instead: a real DATE, always in step, zero app changes required.
--
-- to_date()/::date are only STABLE (they depend on the DateStyle setting), so
-- a generated column cannot use them. make_date() on extracted integer parts
-- is genuinely immutable.
create or replace function public.slash_date_to_date(p text)
returns date
language sql
immutable
returns null on null input
as $function$
  select case
    when p ~ '^\d{2}/\d{2}/\d{4}$'
      then make_date(substr(p,7,4)::int, substr(p,4,2)::int, substr(p,1,2)::int)
    when p ~ '^\d{4}-\d{2}-\d{2}$'
      then make_date(substr(p,1,4)::int, substr(p,6,2)::int, substr(p,9,2)::int)
    else null
  end;
$function$;

alter table attendance_records drop column if exists date_iso;

alter table attendance_records
  add column date_iso date
  generated always as (public.slash_date_to_date(date)) stored;

create index if not exists attendance_records_date_iso_idx
  on attendance_records (date_iso);

create index if not exists attendance_records_emp_date_iso_idx
  on attendance_records (employee_id, date_iso);
