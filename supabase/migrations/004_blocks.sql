-- Migration 004_blocks.sql — Phase 5 Safety, Moderation & Store Readiness
-- blocks table: asymmetric block relationship.
-- blocker_uid is the initiator; blocked_uid is the target.
-- Asymmetric RLS: blocker can SELECT/INSERT/DELETE their own rows;
-- blocked_uid has NO SELECT policy (cannot discover they are blocked).

BEGIN;

CREATE TABLE public.blocks (
  blocker_uid  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_uid  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_uid, blocked_uid),
  CONSTRAINT no_self_block CHECK (blocker_uid != blocked_uid)
);

CREATE INDEX blocks_blocker_idx ON public.blocks (blocker_uid);
CREATE INDEX blocks_blocked_idx ON public.blocks (blocked_uid);

ALTER TABLE public.blocks ENABLE ROW LEVEL SECURITY;

-- Blocker can see who they have blocked (their own rows as initiator).
-- Uses (SELECT auth.uid()) wrapper to avoid per-row function calls (Pitfall 4).
CREATE POLICY "Blockers view own blocks"
  ON public.blocks FOR SELECT
  TO authenticated
  USING ( (SELECT auth.uid()) = blocker_uid );

-- Users can INSERT blocks where they are the initiator.
CREATE POLICY "Users create blocks"
  ON public.blocks FOR INSERT
  TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = blocker_uid );

-- Users can remove blocks they created (unblock).
CREATE POLICY "Users remove own blocks"
  ON public.blocks FOR DELETE
  TO authenticated
  USING ( (SELECT auth.uid()) = blocker_uid );

-- Note: blocked_uid has NO SELECT policy.
-- The blocked party cannot discover they are blocked.
-- Go signaling server uses service role (bypasses RLS) for mutual enforcement checks.

COMMIT;
