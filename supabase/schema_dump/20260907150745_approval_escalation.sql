-- Anything outside policy is Management's call, but there was no way to hand
-- it to them: an approver facing an exception could only approve it (quietly
-- setting a precedent they had no authority to set) or reject it and tell the
-- employee to ask someone else outside the system.
--
-- Escalation makes that a first-class action. Any approver, at any stage, can
-- pass a request to Management with a reason. It leaves the normal queue and
-- appears in Management's, so it cannot be decided at the wrong level and
-- cannot be lost in between.
alter table leave_applications
  add column if not exists escalated boolean not null default false;
alter table leave_applications
  add column if not exists escalated_by text default '';
alter table leave_applications
  add column if not exists escalated_at timestamptz;
alter table leave_applications
  add column if not exists escalation_reason text default '';

comment on column leave_applications.escalated is
  'Handed to Management as a policy exception. Removed from the manager/HR queue so it cannot be decided at the wrong level.';

alter table on_duty_requests
  add column if not exists escalated boolean not null default false;
alter table on_duty_requests
  add column if not exists escalated_by text default '';
alter table on_duty_requests
  add column if not exists escalation_reason text default '';

alter table attendance_confirmations
  add column if not exists escalated boolean not null default false;
alter table attendance_confirmations
  add column if not exists escalated_by text default '';
alter table attendance_confirmations
  add column if not exists escalation_reason text default '';

-- Escalated items are Management's, so they are listed under Management
-- rather than whichever stage they left.
create or replace view v_pending_approvals as
  select 'Leave'::text as process,
         l.employee_name as raised_by,
         l.leave_type || ' · ' || l.from_date
           || case when l.escalated then '  [ESCALATED]' else '' end as detail,
         case when l.escalated then 'Management'
              else coalesce(nullif(u.reporting_manager,''), 'Unassigned') end as waiting_on,
         case when l.escalated then 'Management' else 'Reporting Manager' end as stage,
         l.applied_on::date as raised_on
    from leave_applications l
    left join app_users u on lower(trim(u.name)) = lower(trim(l.employee_name))
   where l.manager_status = 'pending' and l.management_status = 'pending'

  union all
  select 'Confirmation', u.name, 'On-roll since ' || left(u.onroll_requested_at,10),
         'HR', 'HR', left(u.onroll_requested_at,10)::date
    from app_users u
   where u.active and coalesce(u.onroll_requested_at,'') <> ''
     and coalesce(u.onroll_confirmed_at,'') = '' and u.onroll_hr_status = 'pending'

  union all
  select 'Confirmation', u.name, 'On-roll since ' || left(u.onroll_requested_at,10),
         coalesce(nullif(u.reporting_manager,''),'Unassigned'), 'Reporting Manager',
         left(u.onroll_requested_at,10)::date
    from app_users u
   where u.active and coalesce(u.onroll_requested_at,'') <> ''
     and coalesce(u.onroll_confirmed_at,'') = '' and u.onroll_manager_status = 'pending'

  union all
  select 'Confirmation', u.name, 'Both stages cleared', 'Management', 'Management',
         left(u.onroll_requested_at,10)::date
    from app_users u
   where u.active and coalesce(u.onroll_requested_at,'') <> ''
     and coalesce(u.onroll_confirmed_at,'') = ''
     and u.onroll_hr_status = 'accepted' and u.onroll_manager_status = 'accepted'
     and u.onroll_management_status = 'pending'

  union all
  select 'Attendance', c.employee_name,
         'Could not check in on ' || c.date_iso
           || case when c.escalated then '  [ESCALATED]' else '' end,
         case when c.escalated then 'Management'
              else coalesce(nullif(e.reporting_manager,''),'Unassigned') end,
         case when c.escalated then 'Management' else 'Reporting Manager' end,
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
  select 'On Duty', d.employee_name,
         d.reason || ' · ' || d.date_iso
           || case when d.escalated then '  [ESCALATED]' else '' end,
         case when d.escalated then 'Management'
              else coalesce(nullif(e.reporting_manager,''),'Unassigned') end,
         case when d.escalated then 'Management' else 'Reporting Manager' end,
         d.requested_at::date
    from on_duty_requests d
    left join app_users e on e.employee_id = d.employee_id
   where d.status = 'pending'

  union all
  select 'Onboarding', o.name, 'Forwarded, awaiting approval',
         'Management', 'Management', o.submitted_at::date
    from onboarding_forms o
   where o.status = 'hr_approved' and not o.superseded;
