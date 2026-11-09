-- Every approval process depends on a notification firing to be discovered.
-- When one fails — a bad route, a write that did not land, a manager who
-- does not use the system — the request sits with nobody aware it exists.
-- That has happened repeatedly and each time it was found by someone
-- complaining, not by the system.
--
-- This computes what is outstanding directly from the data, so a request is
-- visible whether or not any notification worked. It is the safety net the
-- notifications never were.
create or replace view v_pending_approvals as
  -- Leave, permission and comp-off awaiting the reporting manager.
  select 'Leave'::text                        as process,
         l.employee_name                      as raised_by,
         l.leave_type || ' · ' || l.from_date as detail,
         coalesce(nullif(u.reporting_manager,''), 'Unassigned') as waiting_on,
         'Reporting Manager'::text            as stage,
         l.applied_on::date                   as raised_on
    from leave_applications l
    left join app_users u on lower(trim(u.name)) = lower(trim(l.employee_name))
   where l.manager_status = 'pending' and l.management_status = 'pending'

  union all
  -- On-roll: HR and the manager act independently, so each is listed
  -- separately — otherwise a request waiting on only one of them looks
  -- fully blocked.
  select 'Confirmation', u.name, 'On-roll since ' || left(u.onroll_requested_at,10),
         'HR', 'HR', left(u.onroll_requested_at,10)::date
    from app_users u
   where u.active and coalesce(u.onroll_requested_at,'') <> ''
     and coalesce(u.onroll_confirmed_at,'') = ''
     and u.onroll_hr_status = 'pending'

  union all
  select 'Confirmation', u.name, 'On-roll since ' || left(u.onroll_requested_at,10),
         coalesce(nullif(u.reporting_manager,''),'Unassigned'), 'Reporting Manager',
         left(u.onroll_requested_at,10)::date
    from app_users u
   where u.active and coalesce(u.onroll_requested_at,'') <> ''
     and coalesce(u.onroll_confirmed_at,'') = ''
     and u.onroll_manager_status = 'pending'

  union all
  select 'Confirmation', u.name, 'Both stages cleared',
         'Management', 'Management', left(u.onroll_requested_at,10)::date
    from app_users u
   where u.active and coalesce(u.onroll_requested_at,'') <> ''
     and coalesce(u.onroll_confirmed_at,'') = ''
     and u.onroll_hr_status = 'accepted' and u.onroll_manager_status = 'accepted'
     and u.onroll_management_status = 'pending'

  union all
  select 'Attendance', c.employee_name, 'Could not check in on ' || c.date_iso,
         coalesce(nullif(e.reporting_manager,''),'Unassigned'), 'Reporting Manager',
         c.requested_at::date
    from attendance_confirmations c
    left join app_users e on e.employee_id = c.employee_id
   where c.status = 'pending'

  union all
  select 'Attendance', c.employee_name, 'Manager confirmed, HR to approve',
         'HR', 'HR', c.requested_at::date
    from attendance_confirmations c
   where c.status = 'confirmed' and c.hr_status = 'pending'

  union all
  select 'On Duty', d.employee_name, d.reason || ' · ' || d.date_iso,
         coalesce(nullif(e.reporting_manager,''),'Unassigned'), 'Reporting Manager',
         d.requested_at::date
    from on_duty_requests d
    left join app_users e on e.employee_id = d.employee_id
   where d.status = 'pending'

  union all
  select 'Onboarding', o.name, 'Forwarded, awaiting approval',
         'Management', 'Management', o.submitted_at::date
    from onboarding_forms o
   where o.status = 'hr_approved' and not o.superseded;

comment on view v_pending_approvals is
  'Everything awaiting a decision, computed from the data rather than from whether a notification fired. A request appears here even if nobody was ever told about it.';
