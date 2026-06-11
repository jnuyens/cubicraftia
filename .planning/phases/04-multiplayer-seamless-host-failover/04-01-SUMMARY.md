---
phase: 04-multiplayer-seamless-host-failover
plan: "01"
subsystem: test-scaffold, i18n, webrtc-addon
tags: [gut, test-stubs, i18n, webrtc, wave-0, foundation]
dependency_graph:
  requires: []
  provides:
    - tests/conftest_phase4.gd
    - tests/unit/test_election_algorithm.gd
    - tests/unit/test_event_replication.gd
    - tests/unit/test_keepalive_logic.gd
    - tests/unit/test_friends_schema.gd
    - tests/unit/test_invite_token.gd
    - tests/unit/test_chat_rate_limit.gd
    - tests/integration/test_snapshot_migration.gd
    - locale/en.po (Phase 4 keys)
    - addons/webrtc-native/webrtc_native.gdextension
  affects: []
tech_stack:
  added:
    - webrtc-native GDExtension v1.1.0-stable (godotengine/webrtc-native, MPL-2.0/libdatachannel)
  patterns:
    - wave-0-pending-pattern (GUT pending() not skip())
    - Phase4Fixtures extends RefCounted (mirrors Phase3Fixtures)
    - binaries-gitignored-install-via-script (mirrors godot-sqlite pattern)
key_files:
  created:
    - tests/conftest_phase4.gd
    - tests/unit/test_election_algorithm.gd
    - tests/unit/test_event_replication.gd
    - tests/unit/test_keepalive_logic.gd
    - tests/unit/test_friends_schema.gd
    - tests/unit/test_invite_token.gd
    - tests/unit/test_chat_rate_limit.gd
    - tests/integration/test_snapshot_migration.gd
    - addons/webrtc-native/webrtc_native.gdextension
  modified:
    - locale/en.po
    - .gitignore
    - scripts/install-deps.sh
decisions:
  - "webrtc-native-bin-gitignored: webrtc-native platform binaries placed in bin/ (gitignored); manifest committed; install-deps.sh handles download — mirrors godot-sqlite pattern"
  - "webrtc-manifest-renamed: upstream zip uses webrtc.gdextension; renamed to webrtc_native.gdextension per must_haves artifact path; bin/ paths updated to match"
  - "phase4-i18n-84-keys: 84 Phase 4 msgid keys added (above the 65 minimum); all 10 surfaces covered including ui.join.error_unverified_session_age (plan revision)"
metrics:
  duration_minutes: 6
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 9
  files_modified: 3
---

# Phase 4 Plan 01: Wave-0 Foundation — GUT Scaffold, WebRTC Addon, i18n Keys

**One-liner:** GUT test scaffold with Phase4Fixtures class, 8 pending test stubs (7 unit + 1 integration), webrtc-native GDExtension v1.1.0-stable manifest, and 84 Phase 4 i18n keys across 10 UI surfaces.

## What Was Built

### Task 1 — GUT test scaffold (commit: 54687d1)

Created `tests/conftest_phase4.gd` as a `class_name Phase4Fixtures extends RefCounted` helper
(NOT an autoload) with four static methods:
- `make_rtt_table(peer_ids, rtts)` — builds `{peer_id: rtt_ms}` for election tests
- `make_join_order(peer_ids)` — builds `{peer_id: index}` for tiebreaker tests
- `open_temp_world(mode)` — verbatim Phase3Fixtures pattern with `phase4_test_` prefix
- `cleanup_temp_world(world_id)` — cleans up SQLite temp world

Created 7 unit test stubs and 1 integration test stub. All tests call `pending("pending until Plan 04-XX implements <feature>")` with the correct target plan reference. All use the wave-0-pending-pattern (GUT counts as Risky/Pending, not FAILED).

| File | Target plan | Pending tests |
|------|-------------|---------------|
| test_election_algorithm.gd | 04-05 | 4 |
| test_event_replication.gd | 04-05 | 3 |
| test_keepalive_logic.gd | 04-05 | 3 |
| test_friends_schema.gd | 04-04 | 3 |
| test_invite_token.gd | 04-04 | 3 |
| test_chat_rate_limit.gd | 04-08 | 3 |
| test_snapshot_migration.gd (integration) | 04-10 | 2 |

### Task 2 — webrtc-native addon + i18n keys (commit: 1bd2164)

**webrtc-native GDExtension:**
- Downloaded `godot-extension-webrtc.zip` from `godotengine/webrtc-native` v1.1.0-stable
- Created `addons/webrtc-native/webrtc_native.gdextension` manifest (committed to git)
- Extracted platform binaries to `addons/webrtc-native/bin/` (gitignored, installed via script)
- Added `addons/webrtc-native/bin/` to `.gitignore` (mirrors godot-sqlite pattern)
- Updated `scripts/install-deps.sh` with idempotent installation logic and `--check` support

**Phase 4 i18n keys:**
- Appended 84 new `msgid` keys to `locale/en.po` across 10 surfaces
- All keys follow the `ui.<surface>.<key>` namespace
- Includes `ui.join.error_unverified_session_age` (added in plan revision)
- Copywriting strings match the 04-UI-SPEC.md Copywriting Contract exactly
- No "Lego" or "Minecraft" strings in any msgstr values

## Deviations from Plan

### Auto-handled implementation details

**1. [Rule 2 - Missing] webrtc manifest renamed**
- **Found during:** Task 2 extraction
- **Issue:** Upstream zip names the manifest `webrtc.gdextension`; must_haves artifact path requires `webrtc_native.gdextension`
- **Fix:** Created `webrtc_native.gdextension` with corrected `bin/` paths (matching the install-deps.sh extraction target)
- **Files modified:** `addons/webrtc-native/webrtc_native.gdextension`, `.gitignore`, `scripts/install-deps.sh`
- **Commit:** 1bd2164

**2. [Rule 2 - Missing] install-deps.sh webrtc installation**
- **Found during:** Task 2
- **Issue:** Plan required addon install but no script existed for it
- **Fix:** Added webrtc-native installation section to `install-deps.sh` with idempotent download + check logic
- **Files modified:** `scripts/install-deps.sh`
- **Commit:** 1bd2164

**3. [Count discrepancy] i18n key counts**
- The plan describes "15 keys" for signin, "16 keys" for friends, "10 keys" for invite, "10 keys" for chat — actual key counts when listing individual keys are 15/17/9/9 respectively. I added all keys exactly as listed per surface; the discrepancy was in the plan's count summaries vs. the actual item lists.
- Final total: 84 keys (well above the 65-key minimum)

### Out-of-scope observations (logged, not fixed)

Pre-existing glossary violations found in unrelated files by `scripts/glossary-check.sh`:
- `src/crafting/recipes/recipe_stick.tres:8` — "Minecraft" in comment
- `src/autoload/inventory.gd:1131` — "Minecraft" in comment
- `src/ui/hp_bar.gd:50` — "Minecraft" in comment

These are in files not modified in Plan 04-01. Per deviation rules, out-of-scope issues are logged here only — not fixed in this plan.

## Known Stubs

All 8 test files intentionally call `pending()` — this is the Wave-0 design. Not unintended stubs.
No locale keys have empty msgstr values — all 84 keys have English translations.

## Threat Flags

None. The webrtc-native binary is from the official `godotengine/webrtc-native` GitHub release (T-04-01-SC mitigation verified: downloaded directly from `github.com/godotengine/webrtc-native/releases`). The `.gdextension` manifest was verified to exist before committing.

## Self-Check: PASSED

**Files exist:**
- `tests/conftest_phase4.gd` ✓
- `tests/unit/test_election_algorithm.gd` ✓
- `tests/unit/test_event_replication.gd` ✓
- `tests/unit/test_keepalive_logic.gd` ✓
- `tests/unit/test_friends_schema.gd` ✓
- `tests/unit/test_invite_token.gd` ✓
- `tests/unit/test_chat_rate_limit.gd` ✓
- `tests/integration/test_snapshot_migration.gd` ✓
- `addons/webrtc-native/webrtc_native.gdextension` ✓

**Commits exist:**
- `54687d1` — feat(04-01): Phase 4 GUT test scaffold ✓
- `1bd2164` — chore(04-01): webrtc-native GDExtension + all Phase 4 i18n keys ✓

**i18n verification:**
- `ui.signin.*` — 15 keys ✓
- `ui.handover.*` — 3 keys ✓
- `ui.settings.show_nameplates` — present ✓
- `ui.join.error_unverified_session_age` — present ✓
