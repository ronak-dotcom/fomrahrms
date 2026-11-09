-- Two-step approval. The reporting manager vouches for presence because
-- they are the one who knows; HR approves separately before it becomes a
-- paid day, because a vouched day has no GPS and no selfie behind it -
-- nothing verified it except a person saying so. One signature should not
-- be able to turn that into pay.
alter table attendance_confirmations
  add column if not exists hr_status text not null default 'pending';  -- pending | approved | rejected
alter table attendance_confirmations
  add column if not exists hr_decided_by text default '';
alter table attendance_confirmations
  add column if not exists hr_decided_by_name text default '';
alter table attendance_confirmations
  add column if not exists hr_decided_at timestamptz;
alter table attendance_confirmations
  add column if not exists hr_note text default '';

-- A device that fails once a week is a different problem from one that
-- fails every day. The cap (2 per week) keeps vouching an exception rather
-- than a standing route around the selfie. But one employee's browser has
-- refused the camera every day since 27/08 - capping her would just move
-- the problem, losing her the days over the limit through no fault of her
-- own. So HR can grant a dated exception, deliberately and visibly, rather
-- than a manager quietly vouching daily until it becomes permanent.
alter table app_users
  add column if not exists vouching_exception_until date;
alter table app_users
  add column if not exists vouching_exception_reason text default '';

comment on column app_users.vouching_exception_until is
  'Set by HR when a device persistently cannot verify attendance. Lifts the 2-per-week vouching cap until this date, after which HR must review. Null = normal cap applies.';

-- Counts vouched days in the same Mon-Sun week, so the cap is checked
-- server-side rather than trusted to the client.
create or replace function public.vouched_days_this_week(
  p_employee_id text, p_date date
) returns integer
language sql stable as $fn$
  select count(*)::int
    from attendance_confirmations
   where employee_id = p_employee_id
     and status = 'confirmed'
     and date_iso >= date_trunc('week', p_date)::date
     and date_iso <  date_trunc('week', p_date)::date + 7
     and date_iso <> p_date;
$fn$;

-- Single source of truth for "may this be vouched?", used by the request
-- path and by HR's screen so the two cannot disagree.
create or replace function public.can_vouch_attendance(
  p_employee_id text, p_date date
) returns table(allowed boolean, used integer, cap integer, reason text)
language sql stable as $fn$
  select
    case when u.vouching_exception_until is not null
              and p_date <= u.vouching_exception_until then true
         when public.vouched_days_this_week(p_employee_id, p_date) < 2 then true
         else false end,
    public.vouched_days_this_week(p_employee_id, p_date),
    2,
    case when u.vouching_exception_until is not null
              and p_date <= u.vouching_exception_until
           then 'HR exception until ' || to_char(u.vouching_exception_until, 'DD/MM/YYYY')
         when public.vouched_days_this_week(p_employee_id, p_date) < 2
           then 'within the weekly limit'
         else 'weekly limit of 2 reached - HR must grant an exception' end
  from app_users u where u.employee_id = p_employee_id;
$fn$;
