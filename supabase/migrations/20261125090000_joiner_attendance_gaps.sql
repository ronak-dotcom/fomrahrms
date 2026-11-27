-- New joiners' first month: days before their app account opened.
--
-- A joiner cannot check in until Management approves the onboarding and
-- they set a password, which can be days after their date of joining.
-- Aravindhasamy I joined on 28 Oct 2026 but his account opened on 30 Oct,
-- so 28 and 29 Oct had no check-in and payroll counted both as unpaid.
--
-- Rule (Ronak, 25 Nov 2026): for the first month only, each working day
-- from the date of joining up to the day before the account opened that
-- has no attendance and no leave is listed for HR, and HR is notified. HR
-- marks each day Present (a vouched attendance record at office hours) or
-- Absent (stays unpaid). Until HR decides, payroll treats the day as any
-- other absence.

create table if not exists public.joiner_attendance_gaps (
  employee_id       text not null,
  day               date not null,
  employee_name     text not null default '',
  date_of_joining   date,
  account_active_on date,
  found_at          timestamptz not null default now(),
  notified_at       timestamptz,
  resolution        text check (resolution in ('present','absent')),
  resolved_by       text not null default '',
  resolved_at       timestamptz,
  note              text not null default '',
  primary key (employee_id, day)
);
alter table public.joiner_attendance_gaps enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies
                  where schemaname='public' and tablename='joiner_attendance_gaps'
                    and policyname='joiner_gaps_hr_mgmt_read') then
    create policy joiner_gaps_hr_mgmt_read on public.joiner_attendance_gaps
      for select to authenticated using (public.current_app_is_hr_or_mgmt());
  end if;
end $$;
grant select on public.joiner_attendance_gaps to authenticated;

-- The day the joiner could first use the app: when the onboarding record
-- says the account went live, else their first device check-in.
create or replace function public.joiner_account_active_on(p_employee_id text)
returns date language sql stable security definer set search_path to 'public' as $$
  select coalesce(
    (select min((o.account_active_at at time zone 'Asia/Kolkata')::date)
       from public.onboarding_forms o
      where o.account_active_at is not null
        and (o.assigned_emp_id = p_employee_id
             or regexp_replace(o.assigned_emp_id, '-0+([0-9])', '-\1') = p_employee_id)),
    (select min(a.date_iso) from public.attendance_records a
      where a.employee_id = p_employee_id and a.verification = 'device'
        and coalesce(a.check_in_time, '') <> ''));
$$;

-- Finds new gaps and notifies HR once per joiner. Runs every morning.
create or replace function public.find_joiner_attendance_gaps()
returns integer language plpgsql security definer set search_path to 'public' as $$
declare
  v_today date := (now() at time zone 'Asia/Kolkata')::date;
  r record;
  n integer := 0;
begin
  insert into public.joiner_attendance_gaps
    (employee_id, day, employee_name, date_of_joining, account_active_on)
  select u.employee_id, g.d::date, u.name, j.doj, j.active_on
    from public.app_users u
    cross join lateral (
      select nullif(u.date_of_joining, '')::date as doj,
             public.joiner_account_active_on(u.employee_id) as active_on) j
    cross join lateral generate_series(
      j.doj,
      -- First month only, before the account opened, and not today.
      least(j.active_on - 1,
            (j.doj + interval '1 month' - interval '1 day')::date,
            v_today - 1),
      interval '1 day') g(d)
   where u.active
     and not coalesce(u.oversight_only, false)
     and not coalesce(u.exempt_from_attendance, false)
     and j.doj is not null and j.active_on is not null
     and j.doj >= v_today - 62
     and not public.is_non_working_day(u.name, g.d::date)
     and not exists (select 1 from public.attendance_records a
                      where a.employee_id = u.employee_id and a.date_iso = g.d::date
                        and (coalesce(a.check_in_time, '') <> '' or coalesce(a.on_duty, false)))
     and not exists (select 1 from public.leave_applications l
                      where l.employee_id = u.employee_id and l.granted
                        and l.leave_type <> 'Permission'
                        and g.d::date between l.from_date and l.to_date)
  on conflict (employee_id, day) do nothing;

  for r in
    select x.employee_id, max(x.employee_name) as nm, max(x.date_of_joining) as doj,
           max(x.account_active_on) as act, count(*) as days,
           string_agg(to_char(x.day, 'DD Mon'), ', ' order by x.day) as list
      from public.joiner_attendance_gaps x
     where x.notified_at is null and x.resolution is null
     group by x.employee_id
  loop
    insert into public.notifications (type, title, body, route, target_role, source_id)
    values ('joiner_attendance_gap', 'New joiner: attendance to confirm',
            r.nm || ' joined on ' || to_char(r.doj, 'DD Mon YYYY')
              || ' but the app account opened on ' || to_char(r.act, 'DD Mon YYYY') || '. '
              || r.days || ' working day' || case when r.days = 1 then '' else 's' end
              || ' with no attendance (' || r.list || ') will be unpaid unless you mark them present.',
            '/joiner-attendance', 'HR', r.employee_id);
    update public.joiner_attendance_gaps
       set notified_at = now()
     where employee_id = r.employee_id and notified_at is null and resolution is null;
    n := n + r.days;
  end loop;
  return n;
end $$;
revoke all on function public.find_joiner_attendance_gaps() from public, anon, authenticated;

-- HR (or Management) decides a day. Present records a vouched attendance
-- at the department's office hours; Absent leaves it unpaid.
create or replace function public.resolve_joiner_gap(
  p_employee_id text, p_day date, p_present boolean, p_note text default '')
returns void language plpgsql security definer set search_path to 'public' as $$
declare
  x      public.joiner_attendance_gaps%rowtype;
  u      public.app_users%rowtype;
  v_in   text;
  v_out  text;
  v_who  text;
begin
  if not public.current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can update a joiner''s attendance' using errcode = '42501';
  end if;
  select * into x from public.joiner_attendance_gaps
   where employee_id = p_employee_id and day = p_day for update;
  if not found then raise exception 'This day is not on the new-joiner list.'; end if;
  if x.resolution is not null then raise exception 'This day has already been decided.'; end if;
  select * into u from public.app_users where employee_id = p_employee_id limit 1;
  select coalesce(nullif(u2.name, ''), public.current_app_email()) into v_who
    from public.app_users u2 where lower(u2.email) = public.current_app_email() limit 1;
  v_who := coalesce(v_who, public.current_app_email(), '');

  if p_present then
    select coalesce(nullif(o.check_in_time, ''), '09:30'), coalesce(nullif(o.check_out_time, ''), '18:30')
      into v_in, v_out
      from public.department_office_timings dt
      join public.office_timings o on o.id = dt.office_timing_id
     where dt.department = u.department limit 1;
    insert into public.attendance_records
      (id, employee_id, employee_name, date, check_in_time, check_out_time,
       check_in_note, verification, vouched_by, vouched_hr_by, location_policy_name)
    values
      (p_employee_id || '_' || to_char(p_day, 'DD-MM-YYYY'), p_employee_id, u.name,
       to_char(p_day, 'DD/MM/YYYY'), coalesce(v_in, '09:30'), coalesce(v_out, '18:30'),
       'Present before the app account opened (joined '
         || to_char(x.date_of_joining, 'DD Mon YYYY') || ', account opened '
         || to_char(x.account_active_on, 'DD Mon YYYY') || '). Marked by ' || v_who
         || case when coalesce(btrim(p_note), '') <> '' then ' — ' || btrim(p_note) else '' end
         || '. Times are office hours, not recorded.',
       'vouched', v_who, v_who, 'New joiner, before account opened')
    on conflict (id) do update set
      check_in_time = coalesce(nullif(attendance_records.check_in_time, ''), excluded.check_in_time),
      check_out_time = coalesce(nullif(attendance_records.check_out_time, ''), excluded.check_out_time),
      check_in_note = excluded.check_in_note,
      verification = 'vouched', vouched_by = excluded.vouched_by, vouched_hr_by = excluded.vouched_hr_by;
  end if;

  update public.joiner_attendance_gaps
     set resolution = case when p_present then 'present' else 'absent' end,
         resolved_by = v_who, resolved_at = now(), note = coalesce(btrim(p_note), '')
   where employee_id = p_employee_id and day = p_day;

  perform public.log_audit_event('joiner_attendance_resolved', 'attendance_records', p_employee_id,
    jsonb_build_object('day', p_day, 'present', p_present, 'note', p_note));
end $$;
revoke all on function public.resolve_joiner_gap(text, date, boolean, text) from anon;

-- Aravindhasamy I's 28 and 29 Oct were marked present by Ronak on 25 Nov
-- before this existed; record them as decided so they are not listed.
insert into public.joiner_attendance_gaps
  (employee_id, day, employee_name, date_of_joining, account_active_on,
   notified_at, resolution, resolved_by, resolved_at, note)
values
  ('FD-11', date '2026-10-28', 'Aravindhasamy I', date '2026-10-28', date '2026-10-30',
   now(), 'present', 'Ronak', now(), 'Confirmed present by Ronak'),
  ('FD-11', date '2026-10-29', 'Aravindhasamy I', date '2026-10-28', date '2026-10-30',
   now(), 'present', 'Ronak', now(), 'Confirmed present by Ronak')
on conflict (employee_id, day) do nothing;

-- 07:00 IST every morning.
select cron.schedule('find-joiner-attendance-gaps', '30 1 * * *',
                     'select public.find_joiner_attendance_gaps()');
