-- Migration 008_profiles_safety_columns.sql — Phase 5 Safety, Moderation & Store Readiness
-- Extends the existing profiles table (from migration 003) with safety columns:
--   is_under_13, eula_acknowledged_hash, eula_acknowledged_at
-- Adds two triggers:
--   1. username_reserved_check   — BEFORE INSERT OR UPDATE, blocks reserved prefixes
--   2. username_change_cooldown  — BEFORE UPDATE, enforces 30-day cooldown + logs change
-- Depends on: migration 007_username_change_log.sql (can_change_username function)

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_under_13          BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS eula_acknowledged_hash TEXT,
  ADD COLUMN IF NOT EXISTS eula_acknowledged_at   TIMESTAMPTZ;

-- Trigger function: enforce reserved username prefixes on INSERT and UPDATE.
-- Blocks exact matches AND prefix matches (e.g. 'admin_bot', 'moderator123').
-- Uses ERRCODE = 'check_violation' so the Godot client receives a 409/422 HTTP error
-- from Supabase PostgREST and can surface a generic rejection message without
-- echoing the matched word (per anti-pattern: do NOT echo the blocked pattern).
CREATE OR REPLACE FUNCTION public.check_username_reserved()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  reserved TEXT[] := ARRAY['admin', 'mod', 'moderator', 'cubicraftia',
                             'support', 'staff', 'system', 'official'];
  r TEXT;
BEGIN
  FOREACH r IN ARRAY reserved LOOP
    IF lower(NEW.username) = r OR lower(NEW.username) LIKE r || '%' THEN
      RAISE EXCEPTION 'Username is reserved'
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE TRIGGER username_reserved_check
  BEFORE INSERT OR UPDATE OF username ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.check_username_reserved();

-- Trigger function: enforce 30-day username change cooldown and log changes.
-- SECURITY DEFINER: required so this function can INSERT into username_change_log
-- (which has no user INSERT policy) and call can_change_username() (which reads
-- username_change_log via SECURITY DEFINER, bypassing RLS).
CREATE OR REPLACE FUNCTION public.enforce_username_change_cooldown()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF OLD.username IS DISTINCT FROM NEW.username THEN
    IF NOT public.can_change_username(NEW.id) THEN
      RAISE EXCEPTION 'Username can only be changed once every 30 days'
        USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO public.username_change_log (uid, old_username, new_username)
    VALUES (NEW.id, OLD.username, NEW.username);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER username_change_cooldown
  BEFORE UPDATE OF username ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.enforce_username_change_cooldown();

COMMIT;
