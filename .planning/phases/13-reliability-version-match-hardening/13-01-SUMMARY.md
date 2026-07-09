---
phase: 13-reliability-version-match-hardening
plan: 01
subsystem: networking
tags: [gdscript, godot, webrtc, network-manager, gut, failover, timeouts]

# Dependency graph
requires: []
provides:
  - "connection_problem(reason) signal + last_failure_reason + report_connection_problem() public API on NetworkManager"
  - "Go signaling 'error' message mapping (blocked/session_full/peer_not_found/version_mismatch -> canonical reason)"
  - "Bounded CONNECTING_TIMEOUT_S (12s) for the initial join Connecting state"
  - "Bounded FAILOVER_RECONNECT_TIMEOUT_S (5s) silent grace window for failover reconnect"
affects: [13-04-version-handshake, 13-05-connection-problem-overlay, 13-06-relay-badge, 13-07-invite-expiry-ux]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single reason-enum signal (connection_problem) driving a future shared overlay, extending NetworkManager's existing string-constant state machine rather than adding a parallel signal system"
    - "One-shot bounded Timer pattern (mirrors existing _failover_timer/_snapshot_timer) for both the Connecting timeout and the failover-reconnect grace window"
    - "Off-tree NetworkManager.new()/.free() GUT unit tests (no add_child) for pure state-machine/signal logic that doesn't need _ready()'s autoload wiring"

key-files:
  created:
    - tests/unit/test_connection_problem_reasons.gd
    - tests/unit/test_connecting_timeout.gd
    - tests/unit/test_reconnect_grace_timeout.gd
  modified:
    - src/autoload/network_manager.gd

key-decisions:
  - "consent_required signaling error code stays on the existing join_blocked('parental_consent_required') flow, NOT routed through connection_problem, per the interface contract (it has its own ParentalGatePanel UI)"
  - "Unknown/unwhitelisted signaling error codes only push_warning() server-side; never surface a player-facing connection_problem overlay (T-13-01-01 mitigation)"
  - "get_connection_state()-based relay_failed/timeout split degrades gracefully to 'timeout' when no live WebRTCPeerConnection exists (defensive has_method guard), matching the plan's off-tree test expectation"

patterns-established:
  - "Any future NetworkManager failure path should call report_connection_problem(reason) rather than inventing a new signal — this is now the single funnel for RELY-01's shared connection-problem screen"

requirements-completed: [RELY-01, RELY-02, RELY-03]

# Metrics
duration: ~25min
completed: 2026-07-09
---

# Phase 13 Plan 01: NetworkManager Connection-Problem Plumbing + Bounded Timeouts Summary

**NetworkManager gained a single `connection_problem(reason)` signal funnel (7 canonical reasons), wired the previously-silently-dropped Go signaling `"error"` message into it, and replaced two indefinite-hang states (initial join Connecting, failover-reconnect wait) with bounded one-shot timers (12s / 5s).**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-07-09
- **Tasks:** 2/2 completed
- **Files modified:** 1 (`src/autoload/network_manager.gd`), 3 test files created

## Accomplishments
- `NetworkManager.connection_problem(reason)` signal + `last_failure_reason` + `report_connection_problem()` public API, backed by a `CONNECTION_PROBLEM_REASONS` const (`expired`, `full`, `ended`, `blocked`, `version_mismatch`, `relay_failed`, `timeout`)
- The Go signaling server's `"error"` message type — previously falling through to the silent `_: pass` default arm — now maps `blocked`→`blocked`, `session_full`→`full`, `peer_not_found`→`ended`, `version_mismatch`→`version_mismatch`; `consent_required` still routes to the pre-existing `join_blocked` flow; every other code only `push_warning()`s (no player-facing leak of raw server error text)
- `start_peer()` no longer optimistically flips to `STATE_CONNECTED_AS_PEER` before the WebRTC handshake completes — it now starts a bounded 12s `_connecting_timeout_timer`; the real transition happens only when `_on_peer_connected(1)` genuinely fires
- `_on_connecting_timeout()` resolves a stalled join to `relay_failed` (ICE `STATE_FAILED`) or `timeout` (no response), then disconnects — a join attempt can never hang indefinitely
- `_do_failover_waiting()` starts a silent 5s `_reconnect_grace_timer` covering both `FAILOVER_WAITING` and the subsequent `RECONNECTING` attempt; stopped on success (`_on_snapshot_received_during_failover`), otherwise `_on_reconnect_grace_timeout()` reports `"ended"` and disconnects

## Task Commits

Each task was committed atomically:

1. **Task 1: Add connection_problem reason plumbing + wire the signaling "error" message** - `095c818` (feat) — see note below on a follow-up correction commit
2. **Task 2: Add bounded Connecting timeout (RELY-03) and failover-reconnect grace window (RELY-02)** - `46c4d7d` (feat)

**Correction commit:** `989934c` (fix) — the initial Task 1 commit's plain `git commit -m` (no pathspec) accidentally swept in `src/autoload/session_registry.gd` and `tests/unit/test_session_registry_version_filter.gd`, which had already been `git add`-staged by a concurrently-running sibling plan (13-02) in this shared working directory at commit time. This commit reverted both files to their state at 13-02's own RED-test commit (`b2278f8`) and the working-tree content was reapplied unstaged, so 13-02's executor could commit its own GREEN implementation independently. No 13-01 files were affected by this correction; it exists purely to keep 13-01's and 13-02's commit history correctly attributed.

_Note: this is not a TDD plan (`tdd_mode: false`), Task 2 used `tdd="true"` at the task level per the plan's `<behavior>`/`<action>` split; both tasks landed as single `feat` commits since the plan's `<done>` criteria for Task 2 were verified via the new test files in the same commit rather than a separate RED/GREEN sequence._

## Files Created/Modified
- `src/autoload/network_manager.gd` - `connection_problem` signal, `last_failure_reason`, `CONNECTION_PROBLEM_REASONS`, `report_connection_problem()`, `"error"` match arm in `_on_signaling_message()`, `_connecting_timeout_timer` / `_reconnect_grace_timer` Timers + `CONNECTING_TIMEOUT_S` / `FAILOVER_RECONNECT_TIMEOUT_S` consts, `_on_connecting_timeout()`, `_on_reconnect_grace_timeout()`, updated `start_peer()` / `_on_peer_connected()` / `_do_failover_waiting()` / `_on_snapshot_received_during_failover()`
- `tests/unit/test_connection_problem_reasons.gd` - covers `report_connection_problem()` and all 5 signaling `"error"` code mappings (including the `consent_required` exclusion and unknown-code no-op)
- `tests/unit/test_connecting_timeout.gd` - covers the bounded Connecting timeout firing `timeout` + `DISCONNECTED`, and its defensive no-op guard outside `STATE_CONNECTING`
- `tests/unit/test_reconnect_grace_timeout.gd` - covers the grace window firing `ended` + `DISCONNECTED` from both `FAILOVER_WAITING` and `RECONNECTING`, and its defensive no-op guard after a successful reconnect

## Decisions Made
- Placed `CONNECTION_PROBLEM_REASONS` and `last_failure_reason` near the existing `STATE_*` constant block (rather than only "next to `_state`" as literally stated) since they are conceptually part of the same canonical-constant-list pattern already established there.
- `report_connection_problem()` was added to the "Public API" section (near `get_state()`) since it is explicitly documented as public API in the plan's must_haves, not a private helper.
- `_on_connecting_timeout()`'s ICE-state check uses `conn.has_method("get_connection_state")` as the defensive fallback the plan specified for "if `get_connection_state()` is unavailable in this Godot/GDExtension build" — in practice this also transparently covers the off-tree unit-test case where `_rtc_mp` is `null`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed accidental sibling-plan file inclusion in Task 1's commit**
- **Found during:** Task 1 commit (post-commit verification)
- **Issue:** `git status` at commit time showed `session_registry.gd` and `test_session_registry_version_filter.gd` already staged (`M ` index status) by a concurrently-running sibling plan (13-02) sharing this working directory. A plain `git commit -m "..."` with no pathspec committed the entire index, not just the files this plan's `git add` had just staged, pulling 13-02's unrelated GREEN implementation into a 13-01-labeled commit.
- **Fix:** Diffed `b2278f8` (13-02's own prior RED-test commit) against the erroneous commit to isolate the 2 sibling-plan files, saved their post-change content to the scratchpad, `git checkout b2278f8 -- <2 files>` to restore them in the index+worktree, committed that correction (`989934c`), then copied the saved content back into the working tree unstaged so 13-02's executor can `git add` + commit it independently.
- **Files modified:** `src/autoload/session_registry.gd`, `tests/unit/test_session_registry_version_filter.gd` (both restored to unstaged working-tree state matching 13-02's intended content; no 13-01-owned files affected)
- **Verification:** `git show --stat` on both `095c818`+`989934c` confirms the net diff across the two commits touches only `src/autoload/network_manager.gd` and `tests/unit/test_connection_problem_reasons.gd`; `git status --short` after the correction shows the 2 sibling files back in the unstaged working tree, not staged or committed by 13-01.
- **Committed in:** `989934c`

---

**Total deviations:** 1 auto-fixed (1 blocking — git workflow hygiene in a shared, non-worktree-isolated working directory with concurrent sibling-plan execution)
**Impact on plan:** No functional code changes were needed; this was purely a git-staging discipline fix. All 13-01 source and test changes are correctly and exclusively attributed to `095c818` + `46c4d7d`. Executors running plans in parallel against the same working directory (rather than isolated worktrees) should always verify `git status --short` immediately before every commit, not just before `git add`, since another agent's concurrent `git add` can land between your own `add` and `commit`.

## Issues Encountered
- GUT 9.4.0's `assert_signal_emitted_with_parameters(object, signal_name, params)` takes an optional 4th positional `index` (int) argument, NOT a free-text message string. Passing a message string there (as several other assertion helpers in this codebase accept) silently corrupts the internal `signal_watcher` lookup, producing internal `SCRIPT ERROR`s (`Invalid operands 'String' and 'int'`, `Nonexistent function 'size' in base 'Nil'`) while the test still technically reports a pass. Caught during the Task 1 test run by inspecting the full godot stdout (not just the pass/fail summary) and fixed by dropping the 4th argument in all 5 call sites in `test_connection_problem_reasons.gd`. No other test files in this plan made the same mistake.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `connection_problem(reason)` + `last_failure_reason` + `report_connection_problem()` are now available for Plan 13-04 (version handshake `version_mismatch` emission), Plan 13-05 (the shared connection-problem overlay UI consuming this signal), and any other Phase 13 plan needing a "surface a connection failure" hook.
- The `# VER-01 protocol-version report hook added in Plan 13-04` anchor comment is in place in `_on_peer_connected()`'s new `peer_id == 1` block, exactly where Plan 13-04 needs to add the protocol-version exchange/check.
- No blockers. Full `tests/unit` suite (402 tests) run clean at 0 failures after this plan's changes (25 pre-existing pending/risky tests unrelated to this work).

## Self-Check: PASSED

All created/modified files confirmed present on disk; all 3 task/correction commits (`095c818`, `989934c`, `46c4d7d`) confirmed present in `git log --oneline --all`.

---
*Phase: 13-reliability-version-match-hardening*
*Completed: 2026-07-09*
