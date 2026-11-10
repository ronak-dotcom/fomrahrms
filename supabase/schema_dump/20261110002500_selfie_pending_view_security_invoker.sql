-- v_attendance_selfie_pending was created with the default view semantics,
-- which run as the view's owner and bypass the caller's RLS — the
-- security_definer_view finding. It lists who owes a selfie, which is
-- ordinary attendance data and should be visible exactly as the underlying
-- rows are. security_invoker makes it obey the caller's policies instead.
alter view public.v_attendance_selfie_pending set (security_invoker = true);
