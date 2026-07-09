---
phase: 13-reliability-version-match-hardening
fixed_at: 2026-07-10T00:20:00Z
review_path: .planning/phases/13-reliability-version-match-hardening/13-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 6
skipped: 0
status: all_fixed
---

# Phase 13: Code Review Fix Report

**Fixed at:** 2026-07-10T00:20:00Z
**Source review:** .planning/phases/13-reliability-version-match-hardening/13-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (CR-01, WR-01, WR-02, WR-03, WR-04, IN-02; IN-01 skipped per instruction)
- Fixed: 6
- Skipped: 0

## Fixed Issues

### CR-01: `_start_as_peer_rtc()` never wires `multiplayer.peer_connected`

**Files modified:** `src/autoload/network_manager.gd`
**Commit:** `f0ccfc6`
**Applied fix:** Added the same `multiplayer.peer_connected` / `multiplayer.peer_disconnected`
wiring (guarded with `is_connected()`) that `_start_as_host_rtc()` and
`_do_failover_elected()` already use, immediately after the existing
`server_disconnected` wiring in `_start_as_peer_rtc()`. Before this fix, a joining
peer's `_on_peer_connected(1)` could never fire, so the RELY-03 state transition to
`CONNECTED_AS_PEER` and the PROTOCOL_VERSION handshake RPC never ran, and every join
would hang until the 12s Connecting timeout. Verified the regression by reverting
the fix locally and re-running the new test (WR-04): it failed exactly as predicted,
then passed again once the fix was restored.

### WR-04: No test drives the real peer-join signal path

**Files modified:** `tests/integration/test_protocol_version_handshake.gd`
**Commit:** `f0ccfc6` (same commit as CR-01, since the test is the direct regression
guard for that fix)
**Applied fix:** Added `test_start_peer_wires_peer_connected_signal()`, which calls
the real public `start_peer()` entry point (rather than driving
`_on_peer_connected`/`_handle_reported_protocol_version` directly, as every other
test in the file intentionally does) and asserts
`multiplayer.peer_connected.is_connected(_nm._on_peer_connected)`,
`multiplayer.peer_disconnected.is_connected(_nm._on_peer_disconnected)`, and
`get_state() == "CONNECTING"`. Added a matching `after_each()` reset
(`multiplayer.multiplayer_peer = null`) so the real `WebRTCMultiplayerPeer` this
test creates doesn't leak into other tests in the same headless GUT run (mirrors
`test_failover_fault_injection.gd`'s existing convention). Confirmed the test fails
without the CR-01 fix and passes with it.

### WR-02: `clear_all_peers()` doesn't clear `_peer_protocol_version`

**Files modified:** `src/autoload/session_registry.gd`
**Commit:** `f268e1d`
**Applied fix:** Added `_peer_protocol_version.clear()` to `clear_all_peers()`,
mirroring `unregister_peer()`'s per-peer cleanup, so a promoted host's bulk peer
reset during failover can't leave a stale version-compatibility verdict recorded
against a numeric peer_id that a later-reconnecting peer reuses.

### WR-01: invite-redeem success path could still emit `friendship_created("")`

**Files modified:** `src/autoload/friends_client.gd`
**Commit:** `327114d`
**Applied fix:** Added an `if host_uid.is_empty(): invite_redeem_failed.emit("expired"); return`
guard immediately after computing `host_uid` from the redeem-PATCH row, before the
`create_friendship()` / `friendship_created.emit()` calls. This closes the gap where
a non-empty response array with a missing/empty `host_uid` field still fell through
to `friendship_created.emit("")`, violating the signal's own documented invariant.
Simplified the subsequent `create_friendship` condition to `host_uid != _user_id`
since emptiness is now handled above.

### WR-03: New Phase 13 comments introduce em-dashes/en-dashes

**Files modified:** `src/autoload/network_manager.gd` (bundled into commit `f0ccfc6`,
see note below), `src/ui/connection_problem_overlay.gd`, `src/ui/connection_problem_overlay.tscn`
**Commit:** `f0ccfc6` (network_manager.gd portion) + `97b1607` (overlay .gd/.tscn portion)
**Applied fix:** Replaced every em-dash (—) / en-dash (–) introduced by Phase 13 in
`network_manager.gd` (lines 426, 1077, 1167, 1213/1214, 1323 in the pre-fix
numbering), `connection_problem_overlay.gd` (11 occurrences), and
`connection_problem_overlay.tscn` (12 occurrences) with commas, colons, or
parentheticals, per CLAUDE.md's dash ban. Left pre-existing (pre-Phase-13) dashes
elsewhere in `network_manager.gd` and `friends_client.gd` untouched, and did not
touch the decorative `───` box-drawing section dividers (a different Unicode
character, not the em/en-dash the rule targets).

**Note on commit grouping:** `git commit <pathspec>` stages the full current
working-tree diff for the named file(s), not just a previously-staged hunk. Because
the CR-01 fix and the network_manager.gd dash cleanups live in the same file, they
landed together in commit `f0ccfc6` when `network_manager.gd` was named on that
commit's pathspec. This was verified deliberate (checked `git show --stat` after
committing) rather than accidental scope creep; the overlay `.gd`/`.tscn` dash
cleanup, being in separate untouched-by-CR-01 files, was committed independently
in `97b1607`.

### IN-02: `JoinScreen._get_host_username()` hardcoded English fallback

**Files modified:** `src/ui/join_screen.gd`
**Commit:** `bc1021d`
**Applied fix:** Replaced `return "your host"` with `return tr("ui.common.generic_host")`,
using the i18n key already added by Plan 13-05 for `ConnectionProblemOverlay`'s
identical fallback, so the Dutch locale no longer ships English text here.

## Skipped Issues

None. IN-01 (doc-comment wording in `session_registry.gd`) was explicitly excluded
from scope by the task instructions ("Skip IN-01 ... unless trivial") and was left
untouched since it required careful rewording rather than a mechanical change.

## Test Results

- `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -gexit`
  (the project's `-gexit`-only invocation with no `-gdir` prints "Nothing was run" —
  GUT requires an explicit test directory; `ci.yml`/`pr-checks.yml` both use
  `-gdir=tests/unit`, which excludes `tests/integration` entirely. Ran both
  directories here since the CR-01 regression test lives in `tests/integration/`.)
  - **Scripts:** 98, **Tests:** 493, **Passing:** 446, **Failing:** 17,
    **Risky/Pending:** 30, **Asserts:** 4627.
  - The 17 failing tests (`test_death_respawn.gd`, `test_save_corruption.gd`,
    `test_save_roundtrip.gd`, `test_schema_migration.gd`, `test_snapshot_migration.gd`)
    are all pre-existing world-save/SQLite-migration failures, confirmed identical
    (same test names, same count) on the unmodified base commit (`db4b084`) before
    any of this session's fixes were applied. Unrelated to Phase 13 or this fix
    session.
  - All tests in `test_protocol_version_handshake.gd` (including the new
    `test_start_peer_wires_peer_connected_signal`), `test_connecting_timeout.gd`,
    and every other Phase 13 test file pass.
- `godot --headless --path . --quit`: exits 0 (boots clean). The
  `libwebrtc_native.macos.template_debug.universal.framework` dynamic-library load
  error printed during boot is a pre-existing environment condition (reproduced
  identically on the unmodified checkout outside this fix's worktree), not caused
  by any change in this session.

---

_Fixed: 2026-07-10T00:20:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
