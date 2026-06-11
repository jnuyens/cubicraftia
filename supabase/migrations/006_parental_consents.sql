-- Migration 006_parental_consents.sql — Phase 5 Safety, Moderation & Store Readiness
-- parental_consents table: COPPA/GDPR-K consent lifecycle for under-13 accounts.
-- child_uid is the primary key — one consent record per child account.
-- Tokens are random 128-bit base32 strings; UNIQUE constraint creates implicit indexes.
-- RLS: child can SELECT their own row (for "Waiting for parent" UI state).
-- No INSERT/UPDATE/DELETE policies for users — Go service role writes via BYPASSRLS.

BEGIN;

CREATE TABLE public.parental_consents (
  child_uid     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  parent_email  TEXT NOT NULL,
  requested_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  consented_at  TIMESTAMPTZ,
  revoked_at    TIMESTAMPTZ,
  consent_token TEXT UNIQUE NOT NULL,
  revoke_token  TEXT UNIQUE NOT NULL
);

-- No additional indexes needed — UNIQUE constraints on tokens create implicit indexes.
-- child_uid is the primary key so it is already indexed.

ALTER TABLE public.parental_consents ENABLE ROW LEVEL SECURITY;

-- Child can read their own consent row to show "Waiting for parent" UI state.
-- Uses (SELECT auth.uid()) wrapper to avoid per-row function calls (Pitfall 4).
CREATE POLICY "Child views own consent"
  ON public.parental_consents FOR SELECT
  TO authenticated
  USING ( (SELECT auth.uid()) = child_uid );

-- No INSERT or UPDATE policies for users.
-- All writes are performed by the Go signaling server using SupabaseServiceKey (BYPASSRLS).

COMMIT;
