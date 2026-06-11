---
phase: 05-safety-moderation-store-readiness
plan: "02"
subsystem: supabase-migrations
tags: [sql, rls, postgres, safety, blocks, reports, parental-consent, username-policy]
dependency_graph:
  requires: []
  provides:
    - blocks table with asymmetric RLS
    - reports immutable audit table with ENUM types
    - parental_consents table with service-role-only writes
    - username_change_log table with can_change_username SECURITY DEFINER function
    - profiles safety columns (is_under_13, eula_acknowledged_hash, eula_acknowledged_at)
    - username_reserved_check trigger
    - username_change_cooldown trigger
  affects:
    - supabase/migrations/003_profiles.sql (extended by 008)
    - Go signaling server (Plan 05-04, reads blocks/parental_consents via service role)
    - FriendsClient (Plan 05-05, POSTs to blocks/reports endpoints)
tech_stack:
  added: []
  patterns:
    - "(SELECT auth.uid()) RLS wrapper for all USING/WITH CHECK clauses"
    - "SECURITY DEFINER function for cross-table writes from triggers"
    - "Asymmetric RLS: blocked party cannot discover they are blocked"
    - "Immutable audit trail: no UPDATE/DELETE policies on reports"
    - "Service-role-only writes via BYPASSRLS for parental consent lifecycle"
    - "LIKE r || '%' pattern for reserved username prefix matching"
key_files:
  created:
    - supabase/migrations/004_blocks.sql
    - supabase/migrations/005_reports.sql
    - supabase/migrations/006_parental_consents.sql
    - supabase/migrations/007_username_change_log.sql
    - supabase/migrations/008_profiles_safety_columns.sql
  modified: []
decisions:
  - "No reason column in blocks table (CONTEXT.md Area 1 decision — v1 scope)"
  - "reports uses ENUMs report_surface and report_category (not TEXT) for type safety"
  - "parental_consents has no expires_at column (Go signaling enforces 7-day TTL via requested_at + 7 days in application logic)"
  - "check_username_reserved does not require SECURITY DEFINER (reads only NEW row)"
  - "enforce_username_change_cooldown is SECURITY DEFINER (must write to username_change_log which has no user INSERT policy)"
  - "Reserved prefix list: admin, mod, moderator, cubicraftia, support, staff, system, official"
metrics:
  duration: "~8 minutes"
  completed: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 5
  files_modified: 0
---

# Phase 5 Plan 02: Supabase Safety Migrations Summary

**One-liner:** Five Supabase migrations adding blocks (asymmetric RLS), reports (immutable audit ENUM table), parental_consents (service-role-only writes), username_change_log (SECURITY DEFINER 30-day cooldown), and profiles safety columns with reserved-prefix trigger.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | blocks, reports, parental_consents migrations | 1e86204 | 004_blocks.sql, 005_reports.sql, 006_parental_consents.sql |
| 2 | username_change_log + profiles safety columns | 349f6ab | 007_username_change_log.sql, 008_profiles_safety_columns.sql |

## Migration Summary

### 004_blocks.sql
- `blocks(blocker_uid UUID, blocked_uid UUID, created_at TIMESTAMPTZ)`
- `PRIMARY KEY (blocker_uid, blocked_uid)`, `CONSTRAINT no_self_block CHECK (blocker_uid != blocked_uid)`
- Two indexes: `blocks_blocker_idx`, `blocks_blocked_idx`
- Asymmetric RLS: blocker SELECT/INSERT/DELETE; `blocked_uid` has NO SELECT policy
- All policies use `(SELECT auth.uid())` wrapper

### 005_reports.sql
- `CREATE TYPE report_surface AS ENUM ('player', 'build', 'chat_message')`
- `CREATE TYPE report_category AS ENUM ('harassment', 'spam', 'cheating', 'csam', 'other')`
- `reports(id UUID PK, reporter_uid, reported_uid, surface, category, reason TEXT CHECK <=500, evidence JSONB, session_id TEXT, created_at)`
- Three indexes on reporter, reported, created_at DESC
- Immutable: reporter INSERT + reporter SELECT own; no UPDATE or DELETE policies
- Reported user has no SELECT policy

### 006_parental_consents.sql
- `parental_consents(child_uid UUID PK, parent_email TEXT, requested_at, consented_at, revoked_at, consent_token TEXT UNIQUE NOT NULL, revoke_token TEXT UNIQUE NOT NULL)`
- Child SELECT own only; no user INSERT/UPDATE/DELETE policies
- Go service role writes via BYPASSRLS

### 007_username_change_log.sql
- `username_change_log(id UUID PK, uid, old_username, new_username, changed_at)`
- Index on `(uid, changed_at DESC)`
- No user SELECT policy — moderation only via service role
- `can_change_username(user_uid UUID) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER` — returns TRUE if no prior change or last change > 30 days ago

### 008_profiles_safety_columns.sql
- `ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_under_13 BOOLEAN NOT NULL DEFAULT FALSE, eula_acknowledged_hash TEXT, eula_acknowledged_at TIMESTAMPTZ`
- `check_username_reserved()` trigger: blocks exact match OR LIKE `r || '%'` for `['admin','mod','moderator','cubicraftia','support','staff','system','official']`; `ERRCODE = 'check_violation'`
- `TRIGGER username_reserved_check BEFORE INSERT OR UPDATE OF username ON public.profiles`
- `enforce_username_change_cooldown()` SECURITY DEFINER trigger: checks `OLD.username IS DISTINCT FROM NEW.username`, calls `can_change_username(NEW.id)`, raises exception or INSERTs into `username_change_log`
- `TRIGGER username_change_cooldown BEFORE UPDATE OF username ON public.profiles`

## Deviations from Plan

None — plan executed exactly as written.

The PLAN.md spec mentioned a `009_reserved_prefix_trigger.sql` as a separate migration in the prompt objective, but the authoritative plan file (05-02-PLAN.md) and 05-RESEARCH.md Migration 008 specify both triggers in `008_profiles_safety_columns.sql`. The research spec was followed — reserved-prefix trigger is in 008 alongside the safety columns.

## Known Stubs

None. All migrations are complete SQL ready for `supabase db push`. No placeholder values.

## Threat Flags

No new trust boundaries beyond those documented in the plan's `<threat_model>`. All STRIDE mitigations are implemented:

| Mitigation | Implementation |
|------------|----------------|
| T-05-T1: Forged reporter_uid | RLS `WITH CHECK (SELECT auth.uid()) = reporter_uid` on 005 |
| T-05-E1: Reserved username bypass | `check_username_reserved` trigger in 008 with ERRCODE='check_violation' |

## Self-Check: PASSED

Files exist:
- FOUND: supabase/migrations/004_blocks.sql
- FOUND: supabase/migrations/005_reports.sql
- FOUND: supabase/migrations/006_parental_consents.sql
- FOUND: supabase/migrations/007_username_change_log.sql
- FOUND: supabase/migrations/008_profiles_safety_columns.sql

Commits exist:
- FOUND: 1e86204 (feat(05-02): add blocks, reports, parental_consents migrations)
- FOUND: 349f6ab (feat(05-02): add username_change_log and profiles safety columns migrations)
