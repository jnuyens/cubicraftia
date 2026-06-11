-- Migration 001: Friendships table
-- Friends graph schema for Cubicraftia: one row per friendship, canonical ordering enforced.
-- RLS policies prevent cross-user visibility.

CREATE TABLE public.friendships (
  user_a     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_b     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status     TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'blocked'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_a, user_b),
  CONSTRAINT canonical_order CHECK (user_a < user_b)
);

-- Index both directions for fast adjacency queries
CREATE INDEX friendships_user_a_idx ON public.friendships (user_a);
CREATE INDEX friendships_user_b_idx ON public.friendships (user_b);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- Users may SELECT their own friendships (either side)
-- Uses (SELECT auth.uid()) instead of bare auth.uid() to avoid a per-row function call.
CREATE POLICY "Users view own friendships"
  ON public.friendships FOR SELECT
  TO authenticated
  USING (
    (SELECT auth.uid()) = user_a
    OR (SELECT auth.uid()) = user_b
  );

-- Users may INSERT a friendship if they are one of the members.
-- The CHECK (user_a < user_b) constraint enforces canonical ordering.
CREATE POLICY "Users create friendships"
  ON public.friendships FOR INSERT
  TO authenticated
  WITH CHECK (
    ((SELECT auth.uid()) = user_a OR (SELECT auth.uid()) = user_b)
    AND user_a < user_b
  );

-- Users may DELETE (unfriend) a friendship they are part of.
CREATE POLICY "Users delete own friendships"
  ON public.friendships FOR DELETE
  TO authenticated
  USING (
    (SELECT auth.uid()) = user_a
    OR (SELECT auth.uid()) = user_b
  );
