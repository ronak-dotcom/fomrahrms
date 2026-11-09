-- Sales staff work Sundays and take a weekday off, but not always the one on
-- their record. Sijo is assigned Tuesday: two weeks he took it, the third he
-- worked Tuesday and took Wednesday instead. That produced two errors from one
-- swap — Tuesday read "Week Off" though he worked, and Wednesday read "Absent"
-- though it was his day off.
--
-- Inferred rather than declared. HR and Management do not know about these
-- swaps today, which means nobody is telling them, and a weekly form people
-- must remember will leave the report wrong whenever they forget.
--
-- Returns the date actually taken off in the week containing p_date, or null.
create or replace function public.effective_weekly_off(
  p_employee_id text, p_date date
) returns date language plpgsql stable as $fn$
declare
  v_off_dow int;
  v_week_start date;
  v_week_end date;
  v_assigned date;
  v_worked_assigned boolean;
  v_gaps date[];
begin
  select case lower(trim(coalesce(u.weekly_off_day,'')))
           when 'sunday' then 0 when 'monday' then 1 when 'tuesday' then 2
           when 'wednesday' then 3 when 'thursday' then 4
           when 'friday' then 5 when 'saturday' then 6 else null end
    into v_off_dow
    from app_users u where u.employee_id = p_employee_id;
  if v_off_dow is null then return null; end if;

  -- Monday-based week, so a Sunday worked sits with the weekday taken off in
  -- lieu of it rather than in the previous week.
  v_week_start := p_date - ((extract(dow from p_date)::int + 6) % 7);
  v_week_end   := v_week_start + 6;
  v_assigned   := v_week_start + ((v_off_dow + 6) % 7);

  select exists (
    select 1 from attendance_records a
     where a.employee_id = p_employee_id and a.date_iso = v_assigned
       and coalesce(a.check_in_time,'') <> ''
  ) into v_worked_assigned;

  -- Assigned day not worked: it was taken as normal.
  if not v_worked_assigned then return v_assigned; end if;

  -- Worked it, so the day off moved. Find weekdays in the week with no
  -- attendance, no approved leave and no holiday.
  select array_agg(d order by d) into v_gaps
    from generate_series(v_week_start, v_week_end, interval '1 day') g(d)
   where extract(dow from g.d) <> 0                      -- Sunday is a workday here
     and g.d <= current_date
     and not exists (
       select 1 from attendance_records a
        where a.employee_id = p_employee_id and a.date_iso = g.d::date
          and coalesce(a.check_in_time,'') <> '')
     and not exists (
       select 1 from leave_applications l
        where l.employee_id = p_employee_id
          and g.d::date between l.from_date and l.to_date
          and l.leave_type <> 'Permission'
          and case when l.management_status <> 'pending'
                   then l.management_status else l.manager_status end = 'approved')
     and not exists (
       select 1 from holidays h where h.holiday_date = g.d::date);

  -- Exactly one gap is an unambiguous swap. Two or more and one of them may
  -- be a genuine absence, so nothing is inferred and HR is left to ask.
  if v_gaps is null or array_length(v_gaps,1) <> 1 then return null; end if;
  return v_gaps[1];
end;
$fn$;

comment on function public.effective_weekly_off(text, date) is
  'The day actually taken off in that week. Falls back to the assigned day; where the assigned day was worked and exactly one weekday is otherwise unexplained, that day is treated as the swap. Null where it cannot be told.';
