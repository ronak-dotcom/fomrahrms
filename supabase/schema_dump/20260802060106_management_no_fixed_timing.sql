-- Management has no department and no fixed working hours, so they must not be
-- assessed against an office timing at all. Until now Sharad Fomra had a blank
-- department, which fell through to the 09:30 default — meaning Management was
-- silently being measured against Standard Hours and could be flagged late.
--
-- Modelled as an explicit property of a timing rather than a special-case
-- department, so the exemption is visible in the admin UI and does not depend
-- on a blank department (any future employee with a blank department would
-- otherwise inherit it by accident).
alter table office_timings
  add column if not exists no_fixed_timing boolean not null default false;

insert into office_timings (name, check_in_time, check_out_time, grace_minutes, working_hours, is_default, no_fixed_timing)
select 'Management — No Fixed Timing', '00:00', '23:59', 0, '0', false, true
where not exists (select 1 from office_timings where no_fixed_timing);

comment on column office_timings.no_fixed_timing is
  'When true, check-ins against this timing are never assessed for lateness. Used for Management, who have no fixed hours.';
