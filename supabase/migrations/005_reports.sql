-- Migration 005_reports.sql — Phase 5 Safety, Moderation & Store Readiness
-- reports table: immutable audit trail of user reports.
-- Reporter can INSERT and SELECT their own rows only.
-- No UPDATE or DELETE policies — immutable by design.
-- Service role (Go signaling /admin/reports) bypasses RLS to read all rows.

BEGIN;

CREATE TYPE report_surface AS ENUM ('player', 'build', 'chat_message');
CREATE TYPE report_category AS ENUM ('harassment', 'spam', 'cheating', 'csam', 'other');

CREATE TABLE public.reports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  reported_uid UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  surface      report_surface NOT NULL,
  category     report_category NOT NULL,
  reason       TEXT CHECK (char_length(reason) <= 500),
  evidence     JSONB,
  session_id   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
  -- No resolved_at / resolved_by in v1 — operator triages manually via /admin/reports
);

CREATE INDEX reports_reporter_idx   ON public.reports (reporter_uid);
CREATE INDEX reports_reported_idx   ON public.reports (reported_uid);
CREATE INDEX reports_created_at_idx ON public.reports (created_at DESC);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Reporter can submit a new report (INSERT).
-- Uses (SELECT auth.uid()) wrapper to avoid per-row function calls (Pitfall 4).
CREATE POLICY "Reporters submit reports"
  ON public.reports FOR INSERT
  TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = reporter_uid );

-- Reporter can view their own submissions (for UI confirmation).
CREATE POLICY "Reporters view own reports"
  ON public.reports FOR SELECT
  TO authenticated
  USING ( (SELECT auth.uid()) = reporter_uid );

-- No UPDATE or DELETE policies — immutable audit trail.
-- Reported user (reported_uid) has NO SELECT policy — cannot discover they were reported.

COMMIT;
