-- Migration 002: Invites table
-- Single-use invite links with 24-hour TTL.
-- Token is a 26-char base32-encoded random 128-bit value.
-- Single-use enforcement is the DB's job: RLS UPDATE policy uses
-- USING (redeemed_by IS NULL) so concurrent redemptions cannot race.

CREATE TABLE public.invites (
  token        TEXT PRIMARY KEY,         -- 26-char base32 token
  host_uid     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id   TEXT NOT NULL,
  expires_at   TIMESTAMPTZ NOT NULL,
  redeemed_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX invites_token_idx ON public.invites (token);
CREATE INDEX invites_host_idx  ON public.invites (host_uid);

ALTER TABLE public.invites ENABLE ROW LEVEL SECURITY;

-- Hosts can see invites they issued
CREATE POLICY "Hosts view own invites"
  ON public.invites FOR SELECT
  TO authenticated
  USING ( (SELECT auth.uid()) = host_uid );

-- Hosts can create invites
CREATE POLICY "Hosts create invites"
  ON public.invites FOR INSERT
  TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = host_uid );

-- Any authenticated user can redeem a valid, unexpired, unredeemed invite.
-- (UPDATE sets redeemed_by to the caller's UID.)
-- USING clause checks redeemed_by IS NULL — this is the atomic single-use enforcement:
-- Postgres locks the row for the UPDATE; a concurrent redemption will see
-- redeemed_by already set and fail the USING check, preventing double-use.
CREATE POLICY "Users redeem invites"
  ON public.invites FOR UPDATE
  TO authenticated
  USING ( expires_at > NOW() AND redeemed_by IS NULL )
  WITH CHECK ( redeemed_by = (SELECT auth.uid()) );
