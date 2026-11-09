-- Payroll, balances and the attendance reports all asked the same question
-- ("was this leave actually granted?") and all answered it the same wrong
-- way: `manager_status = 'approved'`.
--
-- That ignores Management entirely. Management is the final authority, and
-- under the agreed chain their silence means approval — so a leave the
-- reporting manager never touched but Management approved was being counted
-- as absence. 14.5 days across 10 requests were being docked from pay that
-- way, including Saurabh Chandak's 5 days of 10-14 October, which Management
-- had approved. In the other direction, a leave the manager approved and
-- Management then overturned was still being paid.
--
-- One generated column so the rule lives in exactly one place:
--   * Management approved          -> granted, whatever the manager did
--   * Management denied            -> not granted, whatever the manager did
--   * Manager approved, Mgmt quiet -> granted (silence is approval)
--   * otherwise                    -> not granted
alter table public.leave_applications
  add column if not exists granted boolean
  generated always as (
    management_status = 'approved'
    or (manager_status = 'approved'
        and coalesce(management_status, 'pending') <> 'denied')
  ) stored;

create index if not exists leave_applications_granted_idx
  on public.leave_applications (employee_id, granted, from_date, to_date);

comment on column public.leave_applications.granted is
  'Whether the leave actually counts as taken. Management overrides the '
  'reporting manager in both directions; their silence means approval. '
  'Use this instead of manager_status anywhere leave is counted for pay, '
  'balance or attendance.';
