-- Migration 009: Avatar JSON column for player builder customisation
-- Adds nullable avatar_json TEXT column to existing profiles table.
-- No data migration required — existing rows retain NULL (client uses defaults).
-- Called by FriendsClient.save_avatar() via PATCH /rest/v1/profiles?id=eq.<uid>
-- RLS: covered by existing "Users update own profile" UPDATE policy from migration 003.
-- Safe to re-run: ADD COLUMN IF NOT EXISTS is idempotent.

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_json TEXT;

COMMIT;
