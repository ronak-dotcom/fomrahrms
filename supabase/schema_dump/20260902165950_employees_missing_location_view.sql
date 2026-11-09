-- Every recurring check-in complaint traced back to the same thing: a new
-- joiner with no row in employee_locations. Nothing surfaced that, so it
-- was only discovered when the person complained, and on 02/09 people
-- standing 19-47 metres from the office were still marked outside while a
-- colleague 2km away passed.
--
-- The geofence code no longer punishes a missing assignment, but an
-- unassigned employee is still a setup gap: their attendance carries no
-- meaningful within-radius verdict. This view makes the gap visible so it
-- can be caught on day one instead of on complaint.
create or replace view v_employees_missing_location as
select u.employee_id, u.name, u.department, u.designation,
       u.date_of_joining, u.work_location
  from app_users u
  left join employee_locations el on el.employee_id = u.employee_id
 where u.active
   and not coalesce(u.exempt_from_attendance, false)
   and not coalesce(u.oversight_only, false)
   and not coalesce(u.exempt_from_geofence, false)
   and u.work_location is distinct from 'Field'   -- Field staff are geofence-exempt by design
   and el.employee_id is null;

comment on view v_employees_missing_location is
  'Active, attendance-tracked employees with no assigned office/site. Their check-ins cannot be verified against any geofence. Should normally be empty.';
