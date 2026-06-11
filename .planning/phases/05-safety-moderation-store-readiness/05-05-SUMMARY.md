---
phase: 05-safety-moderation-store-readiness
plan: 05
subsystem: client-safety
tags: [friends-client, block, report, parental-consent, eula, username-policy, gdscript, supabase, coppa]
dependency_graph:
  requires: [05-02]
  provides: [FriendsClient block/report/consent/EULA API, UsernamePol validator]
  affects: [05-07, 05-08, 05-09, 05-10]
tech_stack:
  added: []
  patterns:
    - FriendsClient HTTPRequest node-per-concern pattern (extended with _block_req, _report_req, _consent_req)
    - HashingContext SHA-256 for EULA version-hash (Godot built-in, no external lib)
    - DOB-to-boolean age gate (raw DOB never leaves device, only is_under_13 bool sent to GoTrue)
key_files:
  modified:
    - src/autoload/friends_client.gd
  created:
    - src/autoload/username_policy.gd
decisions:
  - "EULA hash uses first 16 hex chars of SHA-256 (64 bits) — sufficient for version detection, short to store"
  - "check_eula_acknowledgement() fails open (returns true) when EULA.md missing — prevents blocking dev builds"
  - "username_policy.gd is extends RefCounted + class_name UsernamePol, not an autoload; accessed by class name"
  - "_consent_pending_action is a dedicated var (not reusing _pending_action) to prevent cross-contamination between auth and consent HTTP nodes"
  - "unblock_user() uses _authed_headers_minimal() (Prefer: return=minimal) since DELETE response body is not needed"
metrics:
  duration: "~25 minutes"
  completed: 2026-05-29
  tasks_completed: 2
  files_modified: 1
  files_created: 1
---

# Phase 05 Plan 05: FriendsClient Safety Methods + UsernamePol Summary

**One-liner:** FriendsClient extended with block/unblock/report/parental-consent/EULA methods using dedicated HTTPRequest nodes per concern; UsernamePol static validator added with reserved-prefix begins_with() enforcement and profanity delegation.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | FriendsClient block/report/consent methods | 2f5258d | src/autoload/friends_client.gd |
| 2 | username_policy.gd static validator | 2ee0d6b | src/autoload/username_policy.gd |

## What Was Built

### Task 1 — FriendsClient extensions

Extended `src/autoload/friends_client.gd` with:

**New signals (5):**
- `user_blocked(uid: String)` — emitted after block_user() POST 201
- `user_unblocked(uid: String)` — emitted after unblock_user() DELETE 204
- `blocks_loaded(blocks: Array)` — emitted after get_blocks() GET 200
- `report_submitted()` — emitted after submit_report() POST 201
- `consent_status_received(is_consented: bool, is_pending: bool)` — emitted by consent methods

**New HTTPRequest child nodes (3):**
- `_block_req` — reused for block/unblock/get_blocks (sequential, not concurrent)
- `_report_req` — for report submission
- `_consent_req` — for consent request and status check

**New public methods (8):**
- `block_user(uid)` — POST /rest/v1/blocks
- `unblock_user(uid)` — DELETE /rest/v1/blocks with blocker+blocked filter
- `get_blocks()` — GET /rest/v1/blocks?blocker_uid=eq.{uid}
- `is_blocked(uid)` — local cache check (no HTTP)
- `submit_report(reported_uid, surface, category, reason, evidence)` — POST /rest/v1/reports
- `request_parental_consent(parent_email)` — POST Go signaling /consent/request
- `check_consent_status()` — GET /rest/v1/parental_consents?child_uid=eq.{uid}
- `check_eula_acknowledgement() -> bool` — SHA-256 via HashingContext, compare 16-char prefix
- `store_eula_hash(hash)` — writes to user://settings.cfg [legal] eula_hash

**sign_up() extension:** Added `dob_year`, `dob_month`, `dob_day` optional params (default 0). When all three are non-zero, computes `is_under_13` using `Time.get_date_dict_from_system()` and includes the boolean in user_metadata. Raw DOB never included in HTTP body (T-05-DOB).

### Task 2 — username_policy.gd

Created `src/autoload/username_policy.gd` as `class_name UsernamePol extends RefCounted`:

- `RESERVED_PREFIXES: Array[String]` — 8 prefixes: admin, mod, moderator, cubicraftia, support, staff, system, official
- `USERNAME_REGEX: String` — `^[a-zA-Z0-9_]{3,20}$`
- `is_valid_format(username)` — compiles regex once into static `_format_regex` cache
- `is_reserved(username)` — case-insensitive `begins_with()` on all prefixes (catches admin123, moderator_helper)
- `is_clean(username)` — delegates to `ProfanityFilter.filter_reject()`
- `validate(username) -> Dictionary` — returns `{valid: bool, error_key: String}`; checks format → reserved → profanity in order
- `days_until_change_allowed(last_changed_at_unix)` — returns `max(0, 30 - floor(days_elapsed))`

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Minor adjustments

**[Rule 3 - Minor] Added `_authed_headers_minimal()` helper**
- The plan specified `Prefer: return=minimal` for `unblock_user()` DELETE.
- The existing `_authed_headers()` always sends `Prefer: return=representation`.
- Added a new private helper `_authed_headers_minimal()` returning the minimal variant.
- No impact on callers; purely additive.

**[Rule 3 - Minor] Added `_signaling_url` state var and init**
- `request_parental_consent()` needs the Go signaling server URL.
- Added `_signaling_url` var populated from `ProjectSettings.network/signaling_url` → env var `CUBICRAFTIA_SIGNALING_URL` → localhost fallback (same pattern as `_supabase_url`).

**[Clarification] username_policy.gd not registered as autoload**
- The plan's `<action>` block explicitly says "Do NOT register as an autoload in project.godot — it is accessed by class_name reference from any script."
- The plan_specifics in the parent prompt said to register it. The task-level `<action>` takes precedence as the authoritative instruction.
- `project.godot` was NOT modified. `UsernamePol` is accessed by `class_name` reference.

## Threat Surface Scan

No new network endpoints or trust boundaries introduced beyond what the plan's threat model already covers:
- `block_user()` → Supabase /rest/v1/blocks (T-05-T1 covered by RLS)
- `submit_report()` → Supabase /rest/v1/reports (T-05-T1 covered by RLS)
- `request_parental_consent()` → Go signaling /consent/request (T-05-DOB; bearer JWT required)

No unplanned threat surface additions found.

## Self-Check

- [x] src/autoload/friends_client.gd exists and parses without errors
- [x] src/autoload/username_policy.gd exists and parses without errors
- [x] 5 new signals present in friends_client.gd
- [x] 8 new methods present in friends_client.gd
- [x] sign_up() accepts DOB params; is_under_13 computed locally; raw DOB never in HTTP body
- [x] EULA hash uses HashingContext.HASH_SHA256; fail-open on missing file
- [x] RESERVED_PREFIXES const present in username_policy.gd
- [x] is_reserved() uses begins_with() for prefix matching
- [x] validate() returns {valid, error_key} Dictionary
- [x] Commits 2f5258d and 2ee0d6b exist in git log
