-- Without this a vouched day is indistinguishable from a normal one in every
-- report: same check-in time, an empty selfie path nobody notices, and a
-- null within_radius that renders as the same dash as "no GPS". The only
-- trace was free text in a note column no report reads. A day where nobody
-- verified the location and no selfie exists must be visibly different from
-- one where both checks passed, or the control is decorative.
alter table attendance_records
  add column if not exists verification text not null default 'device';
  -- device  = GPS and selfie as normal
  -- vouched = manager confirmed, HR approved; no device evidence

alter table attendance_records
  add column if not exists vouched_by text default '';
alter table attendance_records
  add column if not exists vouched_hr_by text default '';

comment on column attendance_records.verification is
  'How presence was established. vouched = a person confirmed it, no GPS or selfie. Surfaced in the attendance sheet and punctuality export so payroll can see it.';

-- Now requires BOTH signatures. Previously a single manager confirmation
-- wrote the record straight through.
create or replace function public.apply_attendance_confirmation()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_id   text;
  v_date text;
  v_note text;
begin
  if new.status <> 'confirmed' or new.hr_status <> 'approved' then
    return new;
  end if;

  v_date := to_char(new.date_iso, 'DD/MM/YYYY');
  v_id   := new.employee_id || '_' || to_char(new.date_iso, 'DD-MM-YYYY');
  v_note := 'Vouched by ' || coalesce(nullif(new.decided_by_name,''), new.decided_by)
            || ', approved by ' || coalesce(nullif(new.hr_decided_by_name,''), new.hr_decided_by)
            || case when coalesce(new.employee_note,'') <> ''
                    then ' — ' || new.employee_note else '' end;

  insert into attendance_records (
    id, employee_id, employee_name, date,
    check_in_time, check_in_note,
    check_in_lat, check_in_lng, check_in_accuracy, check_in_within_radius,
    verification, vouched_by, vouched_hr_by
  )
  values (
    v_id, new.employee_id, new.employee_name, v_date,
    case when new.kind = 'check_in' then new.claimed_time else '' end,
    v_note, new.lat, new.lng, new.accuracy,
    -- Explicitly unknown, never true: a person verified presence, not a
    -- geofence. Marking it within-radius would launder a human judgement
    -- into a GPS fact.
    null,
    'vouched',
    coalesce(nullif(new.decided_by_name,''), new.decided_by),
    coalesce(nullif(new.hr_decided_by_name,''), new.hr_decided_by)
  )
  on conflict (id) do update set
    check_in_time = case
      when new.kind = 'check_in' and coalesce(attendance_records.check_in_time,'') = ''
      then new.claimed_time else attendance_records.check_in_time end,
    check_out_time = case
      when new.kind = 'check_out'
      then new.claimed_time else attendance_records.check_out_time end,
    check_in_note = v_note,
    verification  = 'vouched',
    vouched_by    = coalesce(nullif(new.decided_by_name,''), new.decided_by),
    vouched_hr_by = coalesce(nullif(new.hr_decided_by_name,''), new.hr_decided_by);

  return new;
end;
$fn$;

drop trigger if exists trg_apply_attendance_confirmation on attendance_confirmations;
create trigger trg_apply_attendance_confirmation
  after update of status, hr_status on attendance_confirmations
  for each row execute function apply_attendance_confirmation();
