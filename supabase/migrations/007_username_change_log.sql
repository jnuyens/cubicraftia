-- Migration 007_username_change_log.sql — Phase 5 Safety, Moderation & Store Readiness
-- username_change_log table: INSERT-only audit trail of username changes.
-- No user-facing SELECT policy — moderation team reads via service role.
-- can_change_username(uid) SECURITY DEFINER function enforces 30-day cooldown.
-- The trigger on profiles.username (migration 008) calls this function.

BEGIN;

CREATE TABLE public.username_change_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  old_username TEXT NOT NULL,
  new_username TEXT NOT NULL,
  changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX username_change_log_uid_idx ON public.username_change_log (uid, changed_at DESC);

ALTER TABLE public.username_change_log ENABLE ROW LEVEL SECURITY;

-- No SELECT policy for users — moderation team only via service role.
-- INSERT is performed by the SECURITY DEFINER trigger function in migration 008,
-- which bypasses RLS when writing to this table on behalf of the user.

-- Function: can the user change their username?
-- SECURITY DEFINER: runs as the function owner, not the caller, to bypass RLS
-- and read username_change_log (which has no user SELECT policy).
CREATE OR REPLACE FUNCTION public.can_change_username(user_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  last_change TIMESTAMPTZ;
BEGIN
  SELECT changed_at INTO last_change
  FROM public.username_change_log
  WHERE uid = user_uid
  ORDER BY changed_at DESC
  LIMIT 1;

  IF last_change IS NULL THEN
    RETURN TRUE;  -- No previous change — user is free to set username
  END IF;
  RETURN last_change < NOW() - INTERVAL '30 days';
END;
$$;

COMMIT;
