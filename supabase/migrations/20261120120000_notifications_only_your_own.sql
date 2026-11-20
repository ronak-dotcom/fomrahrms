-- Notifications: each person reads only what is addressed to them.
--
-- The table had one policy, "authenticated_full_access" (all commands,
-- using true): anyone signed in could read every notification in the company
-- (payslip ready, leave approved or rejected, with names), mark them read for
-- others, edit them or delete them. The app only ever asks for its own
-- (by email, by role, to everyone, or to the team it manages) and filters to
-- those; the database now holds the same line.
--
--   read / mark read : notifications addressed to you
--   send             : anyone signed in (the app notifies managers, HR and
--                      Management on people's behalf)
--   delete           : HR and Management only (the app never deletes)

create or replace function public.notification_is_mine(
  p_target_email text, p_target_role text, p_target_rm text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  with me as (
    select public.current_app_email() as email,
           (select case lower(btrim(u.role))
                     when 'hr' then 'HR'
                     when 'manager' then 'Manager'
                     when 'management' then 'Management'
                     when 'ceo' then 'Management'
                     else 'Employee' end
              from public.app_users u
             where lower(u.email) = public.current_app_email() limit 1) as role_label,
           (select btrim(u.name) from public.app_users u
             where lower(u.email) = public.current_app_email() limit 1) as name
  )
  select coalesce(
       (btrim(coalesce(p_target_email, '')) <> '' and lower(btrim(p_target_email)) = me.email)
    or p_target_role = 'ALL'
    or (coalesce(p_target_role, '') <> '' and p_target_role = me.role_label)
    or (btrim(coalesce(p_target_rm, '')) <> '' and btrim(p_target_rm) = me.name),
    false)
  from me;
$$;

comment on function public.notification_is_mine(text, text, text) is
  'True when a notification is addressed to the signed-in user: by email, by role, to ALL, or to the team they manage. Mirrors NotificationStore.isForCurrentUser in the app.';

drop policy if exists authenticated_full_access on public.notifications;
drop policy if exists notifications_read_own on public.notifications;
drop policy if exists notifications_send on public.notifications;
drop policy if exists notifications_mark_read on public.notifications;
drop policy if exists notifications_delete_hr on public.notifications;

create policy notifications_read_own on public.notifications
  for select to authenticated
  using (public.notification_is_mine(target_email, target_role, target_reporting_manager));
create policy notifications_send on public.notifications
  for insert to authenticated
  with check (true);
create policy notifications_mark_read on public.notifications
  for update to authenticated
  using (public.notification_is_mine(target_email, target_role, target_reporting_manager))
  with check (public.notification_is_mine(target_email, target_role, target_reporting_manager));
create policy notifications_delete_hr on public.notifications
  for delete to authenticated
  using (public.current_app_is_hr_or_mgmt());

-- Check before committing: signed in as an employee, the database returns
-- exactly what the app's own filter would, and nothing addressed elsewhere.
do $zzcheck$
declare
  v_email text;
  v_name text;
  v_expected int;
  v_seen int;
  v_foreign int;
begin
  select lower(u.email), btrim(u.name) into v_email, v_name
    from public.app_users u
   where u.active and lower(btrim(u.role)) = 'employee' and coalesce(u.email, '') <> ''
   order by u.employee_id limit 1;
  if v_email is null then
    return;
  end if;
  select count(*) into v_expected from public.notifications n
   where lower(btrim(n.target_email)) = v_email
      or n.target_role in ('Employee', 'ALL')
      or (btrim(n.target_reporting_manager) <> '' and btrim(n.target_reporting_manager) = v_name);

  perform set_config('request.jwt.claims', json_build_object('email', v_email, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_seen from public.notifications;
  select count(*) into v_foreign from public.notifications n
   where lower(btrim(n.target_email)) <> v_email and coalesce(n.target_role, '') not in ('Employee', 'ALL')
     and btrim(coalesce(n.target_reporting_manager, '')) <> v_name;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);

  if v_seen <> v_expected or v_foreign <> 0 then
    raise exception 'Notification access check failed: an employee sees % (expected %), % addressed elsewhere',
      v_seen, v_expected, v_foreign;
  end if;
end $zzcheck$;
