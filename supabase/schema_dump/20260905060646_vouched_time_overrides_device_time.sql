-- The confirmed time must win over whatever the device eventually recorded.
--
-- Akila arrived at 09:25, could not check in, and only got a working browser
-- at 18:30. The insert kept the existing 18:30 because it only filled an
-- EMPTY time, so after her manager confirmed 09:25 her day still read as a
-- nine-hour late arrival — the confirmation changed nothing, which is the one
-- outcome it exists to prevent.
--
-- The trade-off is deliberate: a confirmed time can overwrite a genuine late
-- check-in. That is what vouching IS — a manager taking responsibility for
-- the claim — and it is not silent: the row is marked verification='vouched',
-- names both approvers, keeps the original in the note, and Management can
-- overturn it.
create or replace function public.apply_attendance_confirmation()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_id   text;
  v_date text;
  v_note text;
  v_prev text;
begin
  if new.status <> 'confirmed' or new.hr_status <> 'approved' then
    return new;
  end if;

  v_date := to_char(new.date_iso, 'DD/MM/YYYY');
  v_id   := new.employee_id || '_' || to_char(new.date_iso, 'DD-MM-YYYY');

  select check_in_time into v_prev
    from attendance_records where id = v_id;

  v_note := 'Vouched by ' || coalesce(nullif(new.decided_by_name,''), new.decided_by)
            || ', approved by ' || coalesce(nullif(new.hr_decided_by_name,''), new.hr_decided_by)
            || case when coalesce(new.employee_note,'') <> ''
                    then ' — ' || new.employee_note else '' end
            -- Keeps what the device had, so the change is auditable rather
            -- than the earlier value simply disappearing.
            || case when new.kind = 'check_in' and coalesce(v_prev,'') <> ''
                         and v_prev <> new.claimed_time
                    then ' [device recorded ' || v_prev || ']' else '' end;

  insert into attendance_records (
    id, employee_id, employee_name, date,
    check_in_time, check_in_note,
    check_in_lat, check_in_lng, check_in_accuracy, check_in_within_radius,
    verification, vouched_by, vouched_hr_by
  )
  values (
    v_id, new.employee_id, new.employee_name, v_date,
    case when new.kind = 'check_in' then new.claimed_time else '' end,
    v_note, new.lat, new.lng, new.accuracy, null,
    'vouched',
    coalesce(nullif(new.decided_by_name,''), new.decided_by),
    coalesce(nullif(new.hr_decided_by_name,''), new.hr_decided_by)
  )
  on conflict (id) do update set
    check_in_time = case when new.kind = 'check_in'
                         then new.claimed_time
                         else attendance_records.check_in_time end,
    check_out_time = case when new.kind = 'check_out'
                          then new.claimed_time
                          else attendance_records.check_out_time end,
    check_in_note = v_note,
    verification  = 'vouched',
    vouched_by    = coalesce(nullif(new.decided_by_name,''), new.decided_by),
    vouched_hr_by = coalesce(nullif(new.hr_decided_by_name,''), new.hr_decided_by);

  return new;
end;
$fn$;
