-- '1 Hour 30 Minutes' contains '1 Hour', so a substring match read it as 60.
-- 90 minutes is no longer a permitted slot at all (30 / 60 / 120 only), so any
-- 90-minute phrasing must be rejected outright rather than silently rounded
-- down to the nearest permitted value — which would quietly under-credit an
-- employee and expose them to a late deduction.
create or replace function public.permission_minutes_from_text(p text)
returns integer
language sql
immutable
as $function$
  select case
    when p is null                      then null
    -- Explicitly reject the retired 90-minute slot, before any substring test.
    when p ilike '%1½%'                 then null
    when p ilike '%1 1/2%'              then null
    when p ilike '%90%'                 then null
    when p ilike '%1 Hour 30%'          then null
    when p ilike '%1 Hr 30%'            then null
    -- Permitted slots.
    when p ilike '%2 Hours%'            then 120
    when p ilike '%2 Hrs%'              then 120
    when p ilike '%120%'                then 120
    when p ilike '%1 Hour%'             then 60
    when p ilike '%1 Hr%'               then 60
    when p ilike '%60%'                 then 60
    when p ilike '%30 Minutes%'         then 30
    when p ilike '%30 Mins%'            then 30
    when p ilike '%30%'                 then 30
    else null
  end;
$function$;
