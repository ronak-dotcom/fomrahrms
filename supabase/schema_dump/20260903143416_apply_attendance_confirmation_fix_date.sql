-- date_iso is GENERATED ALWAYS from slash_date_to_date(date), so the insert
-- must write the dd/MM/yyyy `date` column and let date_iso derive itself.
create or replace function public.apply_attendance_confirmation()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_id   text;
  v_date text;
  v_note text;
begin
  if new.status <> 'confirmed' then return new; end if;

  v_date := to_char(new.date_iso, 'DD/MM/YYYY');
  v_id   := new.employee_id || '_' || to_char(new.date_iso, 'DD-MM-YYYY');
  v_note := 'Confirmed by ' || coalesce(nullif(new.decided_by_name,''), new.decided_by)
            || case when coalesce(new.employee_note,'') <> ''
                    then ' — ' || new.employee_note else '' end;

  insert into attendance_records (
    id, employee_id, employee_name, date,
    check_in_time, check_in_note,
    check_in_lat, check_in_lng, check_in_accuracy,
    check_in_within_radius
  )
  values (
    v_id, new.employee_id, new.employee_name, v_date,
    case when new.kind = 'check_in' then new.claimed_time else '' end,
    v_note, new.lat, new.lng, new.accuracy,
    -- Explicitly unknown, not true: a person verified the presence, not a
    -- geofence. Recording it as within-radius would launder a human
    -- judgement into a GPS fact and corrupt the location reporting.
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
