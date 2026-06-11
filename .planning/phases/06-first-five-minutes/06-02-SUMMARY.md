---
phase: 06-first-five-minutes
plan: "02"
subsystem: onboarding-infrastructure
tags: [autoload, deep-link, telemetry, supabase, migration]
dependency_graph:
  requires: []
  provides:
    - supabase/migrations/009_avatar.sql
    - src/autoload/deep_link_handler.gd
    - src/autoload/onboarding_telemetry.gd
  affects:
    - project.godot
tech_stack:
  added: []
  patterns:
    - ConfigFile persistence for local-only telemetry (user://telemetry.cfg)
    - CLI arg parsing for cubicraftia:// deep-link URIs
    - In-memory queue with timed + close-event flush
key_files:
  created:
    - supabase/migrations/009_avatar.sql
    - src/autoload/deep_link_handler.gd
    - src/autoload/onboarding_telemetry.gd
  modified:
    - project.godot
decisions:
  - "DeepLinkHandler uses 20-char minimum token length as client-side T-06-T1 mitigation; server validates single-use in FriendsClient.redeem_invite()"
  - "OnboardingTelemetry.log() is an instance method (not static) since GDScript static methods cannot access instance _queue; autoload singleton name makes it callable as OnboardingTelemetry.log()"
  - "FIFO rotation via _rotate_oldest() sorts [event_N] sections by numeric suffix and erases the smallest N values (oldest events)"
  - "DeepLinkHandler registered after FriendsClient so is_signed_in() is available; OnboardingTelemetry registered last to avoid blocking startup"
metrics:
  duration: "117s"
  completed: "2026-05-30"
  tasks: 2
  files: 4
---

# Phase 6 Plan 02: Infrastructure Autoloads and Avatar Migration Summary

Supabase migration 009_avatar.sql, DeepLinkHandler autoload with cubicraftia:// URI parsing, and OnboardingTelemetry autoload with 10k-cap local event log — foundational dependencies for title_scene (Wave 2).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Supabase migration 009_avatar.sql | 7d35c67 | supabase/migrations/009_avatar.sql |
| 2 | DeepLinkHandler + OnboardingTelemetry autoloads + project.godot | 6cb5686 | src/autoload/deep_link_handler.gd, src/autoload/onboarding_telemetry.gd, project.godot |

## Verification Results

1. `ls supabase/migrations/009_avatar.sql` — EXISTS
2. `grep "ADD COLUMN IF NOT EXISTS avatar_json" 009_avatar.sql` — PRESENT (count: 1)
3. No prior migration contains `avatar_json` — CONFIRMED (grep returned NOT FOUND)
4. `grep "DeepLinkHandler" project.godot` — line 51: `DeepLinkHandler="*res://src/autoload/deep_link_handler.gd"`
5. `grep "OnboardingTelemetry" project.godot` — line 55: `OnboardingTelemetry="*res://src/autoload/onboarding_telemetry.gd"`
6. DeepLinkHandler appears immediately after FriendsClient in the autoload list — CONFIRMED
7. `grep "get_pending_token" deep_link_handler.gd` — method at line 80
8. `grep "MAX_EVENTS.*10" onboarding_telemetry.gd` — `const MAX_EVENTS: int = 10_000` at line 58

## Implementation Details

### 009_avatar.sql

Simple idempotent migration wrapped in `BEGIN`/`COMMIT`. Uses `ADD COLUMN IF NOT EXISTS` per the established pattern in migration 008. Covered by existing "Users update own profile" UPDATE policy from migration 003 — no RLS changes needed.

### DeepLinkHandler

- Parses two arg forms: `--invite=TOKEN` (bare token, desktop) and `--uri=cubicraftia://invite/TOKEN` (full URI, all platforms via Godot's OS CLI arg passthrough)
- `_handled` guard ensures `invite_token_received` fires at most once even if both arg forms are present
- `consume_pending_token()` solves the title_scene `_ready()` race: the signal may have already fired by the time title_scene connects; callers check `has_pending_token()` after connecting and consume immediately if needed
- `MIN_TOKEN_LENGTH = 20` is the T-06-T1 client-side sanity check — trivially short tokens (e.g. `--invite=abc`) are rejected with a push_warning; server-side validation is NOT skipped

### OnboardingTelemetry

- 15 event name constants matching the locked list in 06-CONTEXT.md Area 6: TITLE_SHOWN, DEEP_LINK_RECEIVED, SIGNUP_STARTED, SIGNUP_COMPLETE, SIGNIN_COMPLETE, AVATAR_PICKER_SHOWN, AVATAR_COMPLETE, WORLD_SELECT_SHOWN, WORLD_CREATED, WORLD_LOADED, FTUE_STEP_1_COMPLETE, FTUE_STEP_2_COMPLETE, FTUE_STEP_3_COMPLETE, FTUE_COMPLETE, INVITE_JOINED
- `log()` instance method appends `{ts: int, event: String}` to `_queue` — zero disk I/O in the hot path
- 60-second Timer auto-flushes; `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` flushes on close (covers both desktop and mobile home-button)
- `_flush_to_disk()` appends to existing ConfigFile sections, updating `[meta] event_count` as the monotonic counter
- `_rotate_oldest()` sorts `[event_N]` sections by numeric suffix and calls `cfg.erase_section()` on the oldest N entries — pure FIFO semantics
- T-06-D1 (disk fill): 10,000-event cap enforced after every flush
- T-06-I1 (PII): only `ts` (int) and `event` (String) stored — no user IDs, no positions, no usernames

### project.godot

`DeepLinkHandler` inserted after `FriendsClient` (line 51) so `FriendsClient.is_signed_in()` is available during deep-link processing. `OnboardingTelemetry` appended last (line 55) so it cannot delay startup of any other autoload.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. Both autoloads are fully implemented; no placeholder or hardcoded values that block plan goals.

## Threat Flags

No new network endpoints, auth paths, or trust-boundary surfaces introduced beyond what the plan's threat model already covers (T-06-T1 deep-link CLI args, T-06-D1 disk cap, T-06-I1 PII exclusion).

## Self-Check: PASSED

- [x] `supabase/migrations/009_avatar.sql` exists with correct idempotent ALTER TABLE
- [x] `src/autoload/deep_link_handler.gd` exists with `get_pending_token`, `consume_pending_token`, `has_pending_token`, `invite_token_received` signal
- [x] `src/autoload/onboarding_telemetry.gd` exists with all 15 event constants and `MAX_EVENTS = 10_000`
- [x] `project.godot` registers `DeepLinkHandler` after `FriendsClient` and `OnboardingTelemetry` last
- [x] Task 1 commit 7d35c67 exists in git log
- [x] Task 2 commit 6cb5686 exists in git log
