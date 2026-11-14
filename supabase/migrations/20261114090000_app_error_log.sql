-- App error capture and "Report a problem".
--
-- When a screen crashed or threw on someone's phone, nothing recorded it;
-- problems reached Management by screenshot. Both now land in one table:
--
--   kind = 'crash'        an uncaught error (Flutter framework or async)
--   kind = 'error'        a caught failure the app chose to log
--   kind = 'write_failed' a database write that failed (supabase_service)
--   kind = 'report'       "Report a problem", sent by the user
--
-- The client never says who it is: log_app_error() and report_problem() take
-- the user from the signed-in session, so a report cannot be filed as
-- someone else. Messages and stacks are truncated, and each user (or the
-- signed-out app as a whole) is rate-limited so a crash loop cannot fill
-- the table.
--
-- Management and HR read it on the App Health page; resolve_app_issue()
-- marks an entry handled.

create table if not exists public.app_error_logs (
  id               bigint generated always as identity primary key,
  occurred_at      timestamptz not null default now(),
  kind             text not null check (kind in ('crash', 'error', 'write_failed', 'report')),
  employee_id      text,
  employee_name    text,
  user_email       text,
  user_role        text,
  screen           text,
  message          text not null,
  stack            text,
  platform         text,
  app_version      text,
  user_note        text,
  screenshot_path  text,
  context          jsonb not null default '{}'::jsonb,
  fingerprint      text,
  status           text not null default 'open' check (status in ('open', 'resolved')),
  resolved_by      text,
  resolved_at      timestamptz,
  resolution_note  text
);

create index if not exists app_error_logs_recent_idx on public.app_error_logs (occurred_at desc);
create index if not exists app_error_logs_open_idx on public.app_error_logs (kind, status, occurred_at desc);
create index if not exists app_error_logs_rate_idx on public.app_error_logs (user_email, occurred_at desc);

alter table public.app_error_logs enable row level security;

create policy app_error_logs_read on public.app_error_logs
  for select to authenticated using (current_app_is_hr_or_mgmt());

-- Who is calling, from the session rather than from the client.
create or replace function public._app_caller()
returns table(email text, employee_id text, name text, role text)
language sql
stable
security definer
set search_path to 'public'
as $$
  select e.email, u.employee_id, u.name, u.role
    from (select current_app_email() as email) e
    left join app_users u on lower(u.email) = e.email;
$$;
revoke all on function public._app_caller() from public, anon, authenticated;

create or replace function public.log_app_error(
  p_kind        text,
  p_screen      text,
  p_message     text,
  p_stack       text default null,
  p_platform    text default null,
  p_app_version text default null,
  p_context     jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  c   record;
  v_id bigint;
  v_kind text := case when p_kind in ('crash', 'error', 'write_failed') then p_kind else 'error' end;
  v_msg  text := left(coalesce(nullif(btrim(p_message), ''), '(no message)'), 2000);
  v_fp   text;
begin
  select * into c from _app_caller();

  -- At most 30 entries per user per 10 minutes; 200 an hour from the
  -- signed-out app (login screen, public forms).
  if c.email is not null then
    if (select count(*) from app_error_logs
         where user_email = c.email and occurred_at > now() - interval '10 minutes') >= 30 then
      return null;
    end if;
  elsif (select count(*) from app_error_logs
          where user_email is null and occurred_at > now() - interval '1 hour') >= 200 then
    return null;
  end if;

  v_fp := md5(v_kind || '|' || coalesce(p_screen, '') || '|' || split_part(v_msg, E'\n', 1));

  -- The same error from the same person on the same screen within a minute
  -- is one entry (a rebuild loop throws on every frame).
  if exists (select 1 from app_error_logs
              where fingerprint = v_fp and user_email is not distinct from c.email
                and occurred_at > now() - interval '1 minute') then
    return null;
  end if;

  insert into app_error_logs(kind, employee_id, employee_name, user_email, user_role,
                             screen, message, stack, platform, app_version, context, fingerprint)
  values (v_kind, c.employee_id, c.name, c.email, c.role,
          left(p_screen, 300), v_msg, left(p_stack, 8000), left(p_platform, 100),
          left(p_app_version, 50), coalesce(p_context, '{}'::jsonb), v_fp)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.log_app_error(text, text, text, text, text, text, jsonb) from public;
grant execute on function public.log_app_error(text, text, text, text, text, text, jsonb) to anon, authenticated;

create or replace function public.report_problem(
  p_screen          text,
  p_note            text,
  p_screenshot_path text default null,
  p_platform        text default null,
  p_app_version     text default null,
  p_context         jsonb default '{}'::jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  c    record;
  v_id bigint;
begin
  select * into c from _app_caller();
  if c.email is null then
    raise exception 'Sign in to report a problem';
  end if;
  if coalesce(btrim(p_note), '') = '' then
    raise exception 'Please describe the problem';
  end if;
  if (select count(*) from app_error_logs
       where user_email = c.email and kind = 'report'
         and occurred_at > now() - interval '1 hour') >= 10 then
    raise exception 'You have sent 10 reports in the last hour. Please try again later.';
  end if;
  -- A screenshot must be this user's own upload.
  if p_screenshot_path is not null
     and split_part(p_screenshot_path, '/', 1) <> coalesce(auth.uid()::text, '-') then
    p_screenshot_path := null;
  end if;

  insert into app_error_logs(kind, employee_id, employee_name, user_email, user_role,
                             screen, message, user_note, screenshot_path, platform,
                             app_version, context)
  values ('report', c.employee_id, c.name, c.email, c.role,
          left(p_screen, 300), left(btrim(p_note), 200), left(btrim(p_note), 4000),
          p_screenshot_path, left(p_platform, 100), left(p_app_version, 50),
          coalesce(p_context, '{}'::jsonb))
  returning id into v_id;

  insert into notifications(type, title, body, route, target_role, source_id)
  values ('problem_reported',
          format('%s reported a problem', coalesce(c.name, c.email)),
          format('On %s: %s', coalesce(nullif(p_screen, ''), 'an unknown screen'), left(btrim(p_note), 140)),
          '/management/app-health', 'Management', 'app_error_' || v_id);

  return v_id;
end;
$$;
revoke all on function public.report_problem(text, text, text, text, text, jsonb) from public, anon;
grant execute on function public.report_problem(text, text, text, text, text, jsonb) to authenticated;

create or replace function public.resolve_app_issue(
  p_id bigint, p_resolved boolean default true, p_note text default null)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not current_app_is_hr_or_mgmt() then
    raise exception 'Only HR or Management can resolve an issue';
  end if;
  update app_error_logs
     set status          = case when p_resolved then 'resolved' else 'open' end,
         resolved_by     = case when p_resolved then current_app_email() end,
         resolved_at     = case when p_resolved then now() end,
         resolution_note = case when p_resolved then nullif(btrim(p_note), '') end
   where id = p_id;
end;
$$;
revoke all on function public.resolve_app_issue(bigint, boolean, text) from public, anon;
grant execute on function public.resolve_app_issue(bigint, boolean, text) to authenticated;

-- Screenshots for problem reports: private, PNG/JPEG, 2 MB. Each user writes
-- only under their own auth uid; HR and Management read.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('problem-reports', 'problem-reports', false, 2097152, array['image/png', 'image/jpeg'])
on conflict (id) do nothing;

create policy problem_reports_insert_own on storage.objects
  for insert to authenticated
  with check (bucket_id = 'problem-reports'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy problem_reports_select_hr_management on storage.objects
  for select to authenticated
  using (bucket_id = 'problem-reports' and current_app_is_hr_or_mgmt());

-- Keep 90 days of crashes and errors; problem reports stay until resolved
-- and then 180 days.
select cron.schedule('purge-app-error-logs', '15 3 * * *', $cron$
  delete from public.app_error_logs
   where (kind <> 'report' and occurred_at < now() - interval '90 days')
      or (kind = 'report' and status = 'resolved' and resolved_at < now() - interval '180 days')
$cron$);
