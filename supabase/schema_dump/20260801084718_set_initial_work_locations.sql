-- Initial set of work_location, consistent with the geofence assignments.
-- Head-office staff -> Office; Sijo is at a project site and Saurabh is field
-- based -> Onsite. This feeds the attendance-policy fallback chain
-- (policyForEmployee -> _fallbackPolicyIdByWorkLocation).
--
-- Note: protect_app_users_sensitive_columns() pins work_location for anyone
-- who is not service_role or HR/Management, so a plain SQL session as
-- `postgres` silently has this update reverted rather than rejected.
update app_users set work_location = 'Office' where employee_id in ('FHIPL-08','FHIPL-01');
update app_users set work_location = 'Onsite' where employee_id in ('FHIPL-03','FD-01');
