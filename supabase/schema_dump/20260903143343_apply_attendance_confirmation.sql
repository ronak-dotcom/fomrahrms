-- A confirmation is only meaningful if it produces the attendance record.
-- Done in the database rather than the client so the two cannot diverge if
-- the manager's app closes mid-action.
create or replace function public.apply_attendance_confirmation()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_id text;
  v_note text;
begin
  if new.status <> 'confirmed' then return new; end if;

  v_id := new.employee_id || '_' ||
          to_char(new.date_iso, 'DD-MM-YYYY');
  v_note := 'Confirmed by ' || coalesce(nullif(new.decided_by_name,''), new.decided_by)
            || case when coalesce(new.employee_note,'') <> ''
                    then ' — ' || new.employee_note else '' end;

  insert into attendance_records (
    id, employee_id, employee_name, date_iso,
    check_in_time, check_in_note,
    check_in_lat, check_in_lng, check_in_accuracy,
    check_in_within_radius
  )
  values (
    v_id, new.employee_id, new.employee_name, new.date_iso,
    case when new.kind = 'check_in' then new.claimed_time else '' end,
    v_note, new.lat, new.lng, new.accuracy,
    -- Explicitly unknown, not true: nobody verified the location, a person
    -- verified the presence. Recording it as within-radius would launder a
    -- human judgement into a GPS fact.
    null
  )
  on conflict (id) do update set
    check_in_time = case
      when new.kind = 'check_in' and coalesce(attendance_records.check_in_time,'') = ''
      then new.claimed_time else attendance_records.check_in_time end,
    check_out_time = case
      when new.kind = 'check_out'
      then new.claimed_time else attendance_records.check_out_time end,
    check_in_note = v_note;

  return new;
end;
$fn$;

drop trigger if exists trg_apply_attendance_confirmation on attendance_confirmations;
create trigger trg_apply_attendance_confirmation
  after update of status on attendance_confirmations
  for each row execute function apply_attendance_confirmation();
