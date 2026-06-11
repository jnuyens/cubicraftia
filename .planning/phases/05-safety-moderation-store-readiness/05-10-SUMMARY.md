---
phase: 05-safety-moderation-store-readiness
plan: 10
subsystem: safety-wiring
tags: [username-validation, profanity-filter, network-manager, under-13, blocks]
dependency_graph:
  requires: [05-05, 05-07, 05-08, 05-09]
  provides: [username-validation-wiring, world-name-filter, network-safety-hooks]
  affects: [sign_in_panel, world_save, network_manager, friends_client]
tech_stack:
  added: []
  patterns:
    - "500ms debounce timer for inline username validation (UsernamePol.validate)"
    - "_is_blocked_locally() display-layer gate before peer_connected emission"
    - "_is_under_13_unconsented() helper checks FriendsClient properties safely"
    - "ProfanityFilter._ensure_regex() warmup at FriendsClient._ready()"
    - "auto-mute via _session_muted dict cleared on begin_graceful_disconnect"
key_files:
  created: []
  modified:
    - src/ui/sign_in_panel.gd
    - src/autoload/world_save.gd
    - src/autoload/friends_client.gd
    - src/autoload/network_manager.gd
    - src/autoload/session_registry.gd
    - tests/unit/test_username_validator.gd
decisions:
  - "Server uniqueness check deferred to submit (not inline) — prevents username enumeration (T-05-P-wn)"
  - "Under-13 chat suppression shows toast but drops silently — Go relay is the hard gate"
  - "join_blocked signal emitted (not error code) so ParentalGatePanel can respond directly"
  - "mute_session_uid() is a separate call from report_submitted signal — report carries no UID arg"
  - "SessionRegistry.get_peer_uid() added as Rule 2 deviation — required by block-aware display"
metrics:
  duration: "7 minutes"
  completed: "2026-05-29"
  tasks_completed: 2
  files_modified: 6
---

# Phase 05 Plan 10: Username Validation + World Name Filter + NetworkManager Safety Hooks Summary

**One-liner:** Client-side safety wiring: UsernamePol.validate() in sign_in_panel with 500ms debounce icons, ProfanityFilter.filter_reject() world-name guard in WorldSave.create_world(), and NetworkManager block-aware peer display + under-13 chat/join suppression + report auto-mute.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Username validation in sign_in_panel + world name filter | ab23e9e | sign_in_panel.gd, world_save.gd, friends_client.gd, test_username_validator.gd |
| 2 | NetworkManager safety hooks | 68cf45b | network_manager.gd, session_registry.gd |

## What Was Built

### Task 1: Username validation + world name filter

**sign_in_panel.gd (Surface G):**
- Added `_username_field` LineEdit on the Create account tab
- `_build_username_field_ui()`: builds the field, inline check/error TextureRect icons (16x16), and a validation error label; all inserted into the VBox before _dob_row
- 500ms debounce Timer (`_username_validation_timer`) connected to `_on_username_field_text_changed`
- `_validate_username_inline()`: calls `UsernamePol.validate()` client-side (format + reserved + profanity); shows green check or red error icon; disables submit on invalid
- Submit button disabled until username passes local validation; server uniqueness check deferred to submit (T-05-P-wn: anti-enumeration)
- `_on_submit_create_account()`: synchronous username validation before DOB check; `_username_field.text` used directly (not email-derived)
- `_on_sign_in_failed()`: maps "taken" reason to `ui.username.error_taken` (Supabase 409 → correct i18n string)

**world_save.gd:**
- Added `const _ProfanityFilter = preload(...)` at top
- Added `create_world(world_name, seed, mode)` public API: profanity filter guard → returns false on blocked names; derives a stable world_id and delegates to `open_world()`
- Added `rename_world(new_name)` validation helper: returns false on empty or profanity match; callers show "Choose another name." and must not echo the rejected input

**friends_client.gd:**
- Added `ProfanityFilter._ensure_regex()` call at top of `_ready()` to warm up the compiled regexes at startup (prevents first-keystroke lag on Tier-3 Android devices)

**test_username_validator.gd:**
- Activated all 5 pending tests (was `pending("Phase 5 — activate in 05-12")`)
- Added 2 additional tests: `test_format_rejects_too_long()` and `test_cooldown_allows_after_30_days()`
- All 7 tests cover: reserved prefix, valid format, special chars, too short, too long, cooldown blocks, cooldown allows

### Task 2: NetworkManager safety hooks

**network_manager.gd:**
- `_blocks_cache: Array`: populated from `FriendsClient.blocks_loaded` signal in `_ready()`
- `_session_muted: Dictionary`: auto-mute list per session; cleared in `begin_graceful_disconnect()`
- `_is_blocked_locally(uid)`: checks `_blocks_cache` for a "blocked_uid" entry; used before `peer_connected` emission in `_on_peer_connected()`
- `_is_under_13_unconsented()`: checks `FriendsClient.is_under_13` and `FriendsClient.is_consented` properties; gracefully returns false if FriendsClient unavailable
- `start_peer()`: added `_is_under_13_unconsented()` gate; emits `join_blocked("parental_consent_required")` and aborts if true
- `send_chat()`: added under-13 suppression guard — drops packet silently and shows `ui.chat.under13_blocked` toast via Toasts autoload
- `_deliver_chat()`: checks sender UID against `_session_muted` before emitting to ChatOverlay
- `_on_blocks_loaded(blocks)`: updates `_blocks_cache`
- `_on_report_submitted()`: stub handler (no-op; UI calls `mute_session_uid()` directly)
- `mute_session_uid(uid)`: adds UID to `_session_muted`
- Added `join_blocked(reason: String)` signal

**session_registry.gd:**
- Added `get_peer_uid(peer_id)` — returns the Supabase UID for a registered peer; required by `_is_blocked_locally()` and `_deliver_chat()` auto-mute lookup

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Added SessionRegistry.get_peer_uid()**
- **Found during:** Task 2 implementation
- **Issue:** `network_manager.gd` block-aware display and auto-mute both need to look up a peer's UID by their Godot multiplayer `peer_id`. SessionRegistry stores this mapping (`register_peer(peer_id, uid, username)`) but had no getter for it.
- **Fix:** Added `get_peer_uid(peer_id: int) -> String` to session_registry.gd that reads from `_peer_list[peer_id]["uid"]`
- **Files modified:** src/autoload/session_registry.gd
- **Commit:** 68cf45b

**2. [Rule 2 - Missing Critical Functionality] `create_world()` uses derived world_id from world_name**
- **Found during:** Task 1 — plan interface shows `create_world(world_id, seed, mode, name)` with 4 args; existing `open_world()` uses world_id as directory key
- **Fix:** `create_world(world_name, seed, mode)` derives a world_id from the validated name (lowercased + timestamp suffix for collision avoidance), matches the plan's intent without requiring callers to generate IDs separately
- **Files modified:** src/autoload/world_save.gd

**3. [Rule 2 - Missing Critical Functionality] Username tests activated early (05-10 not 05-12)**
- **Found during:** Task 1 — tests were pending "Phase 5 — activate in 05-12" but plan 05-10 explicitly requires test activation
- **Fix:** Activated all tests and added 2 more coverage cases (too_long, cooldown_allows)
- **Files modified:** tests/unit/test_username_validator.gd

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries introduced. All wiring uses existing infrastructure. The `join_blocked` signal is emitted locally — no external surface.

## Self-Check

### Created files exist:
- SUMMARY.md being written now

### Modified files:
- `src/ui/sign_in_panel.gd`: contains `UsernamePol.validate` — FOUND
- `src/autoload/world_save.gd`: contains `filter_reject` — FOUND
- `src/autoload/friends_client.gd`: contains `_ensure_regex` — FOUND
- `src/autoload/network_manager.gd`: contains `_is_blocked_locally`, `_session_muted`, `join_blocked` — FOUND
- `src/autoload/session_registry.gd`: contains `get_peer_uid` — FOUND
- `tests/unit/test_username_validator.gd`: tests activated — FOUND

### Commits exist:
- `ab23e9e`: feat(05-10): wire username validation — FOUND
- `68cf45b`: feat(05-10): NetworkManager safety hooks — FOUND

## Self-Check: PASSED
