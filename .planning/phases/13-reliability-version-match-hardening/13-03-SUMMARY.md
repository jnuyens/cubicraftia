---
phase: 13-reliability-version-match-hardening
plan: 03
subsystem: networking
tags: [gdscript, godot, supabase, postgrest, invites, gut-tests]

# Dependency graph
requires:
  - phase: 04-friends-invites (prior)
    provides: FriendsClient.redeem_invite() / invite token model / title_scene deep-link flow
provides:
  - "FriendsClient.invite_redeem_failed(reason) signal, emitted on a zero-row redeem_invite PATCH result instead of a phantom friendship_created('')"
  - "title_scene._on_invite_redeem_failed handler that restores the title UI and reports the failure via NetworkManager.report_connection_problem when available"
  - "Fail-closed guard in title_scene._on_friendship_created: empty host_uid never reaches start_peer/change_scene_to_file"
affects: [13-01-reliability-version-match-hardening, 13-reliability-version-match-hardening (overlay wiring in a later plan)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Fail-closed signal contract: PostgREST returning HTTP 200 + empty array is treated as failure, not success, at the earliest possible point (_on_invite_completed), with a defense-in-depth guard at the UI layer as well"

key-files:
  created: [tests/unit/test_invite_redeem_expired.gd]
  modified: [src/autoload/friends_client.gd, src/ui/title_scene.gd]

key-decisions:
  - "Used a single generic 'expired' reason string for all three zero-row causes (expired, already-redeemed, nonexistent token) rather than distinguishing them, matching the plan's accepted information-disclosure disposition (T-13-03-02)"
  - "Guarded the NetworkManager.report_connection_problem call with has_method() so this plan works standalone even though 13-01 (which adds that method) has not necessarily landed first"

patterns-established:
  - "Zero-row PostgREST PATCH result treated as fail-closed at the client parsing layer, with a redundant fail-closed guard at the UI consumption layer for defense-in-depth"

requirements-completed: [RELY-04]

# Metrics
duration: ~25min
completed: 2026-07-09
---

# Phase 13 Plan 03: Invite Redeem Fail-Closed Handling Summary

**Fixed the silent stale/invalid invite-redeem bug: FriendsClient now emits `invite_redeem_failed("expired")` instead of a phantom `friendship_created("")` on a zero-row PATCH result, and title_scene restores the title UI instead of attempting a broken join.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-07-09T22:05:00Z (approx)
- **Completed:** 2026-07-09T22:32:02+02:00
- **Tasks:** 2 completed
- **Files modified:** 2 (+1 test file created)

## Accomplishments
- `FriendsClient._on_invite_completed()`'s `redeem_invite` branch now fails closed: a parsed body that is not a non-empty Array emits `invite_redeem_failed("expired")` and returns before ever reaching the `host_uid` extraction / `friendship_created` emit.
- `title_scene.gd` wires the new signal to `_on_invite_redeem_failed`, which restores the title UI (`_content_column` visible, `_joining_label` hidden, `_pending_invite_token` cleared) and calls `NetworkManager.report_connection_problem(reason)` when that method exists.
- `_on_friendship_created` gained a fail-closed guard as its first statement: an empty `host_uid` now short-circuits to `_on_invite_redeem_failed("expired")` instead of proceeding to `start_peer("", 0)` and `change_scene_to_file`.
- New GUT test `test_invite_redeem_expired.gd` proves both the zero-row failure path and the unchanged non-empty success path (regression guard).

## Task Commits

Each task was committed atomically:

1. **Task 1: FriendsClient stops emitting friendship_created on a zero-row redeem result** - `62b7582` (fix)
2. **Task 2: title_scene guards against empty host_uid and restores UI on redeem failure** - `5b0afe8` (fix)

_Note: this plan's tasks were TDD-flavored (test file written and verified alongside Task 1) but committed as a single `fix` commit per task rather than split RED/GREEN/REFACTOR commits, consistent with `tdd_mode: false` in project config._

## Files Created/Modified
- `src/autoload/friends_client.gd` - Added `invite_redeem_failed(reason)` signal; `_on_invite_completed()`'s `redeem_invite` branch now returns early with that signal on a zero-row parsed body instead of falling through to `friendship_created.emit("")`
- `src/ui/title_scene.gd` - Wired `invite_redeem_failed` to a new `_on_invite_redeem_failed(reason)` handler (restores title UI, reports to NetworkManager); added an empty-`host_uid` guard as the first statement of `_on_friendship_created`
- `tests/unit/test_invite_redeem_expired.gd` - New GUT test: zero-row body emits `invite_redeem_failed("expired")` and not `friendship_created`; non-empty body still emits `friendship_created("uid-x")` and not `invite_redeem_failed`

## Decisions Made
- Single generic "expired" reason for all three failure causes (expired / already-redeemed / nonexistent), per the plan's threat-model disposition (T-13-03-02, accepted).
- `NetworkManager.report_connection_problem` call is guarded with `has_method()` so this plan's UI-restore behavior works correctly regardless of whether sibling plan 13-01 (which adds that method to `network_manager.gd`) has landed yet.

## Deviations from Plan

None - plan executed exactly as written. Both tasks matched the `<action>` and `<done>` specs precisely; no Rule 1-4 fixes were needed.

## Issues Encountered

- During execution, `git status` briefly showed unrelated modifications to `src/autoload/network_manager.gd` and `src/autoload/session_registry.gd` that this executor never touched (owned by sibling Wave-1 plans 13-01/13-02, apparently running concurrently in the same working tree). These files were deliberately excluded from both commits by staging only `src/autoload/friends_client.gd`, `src/ui/title_scene.gd`, and the new test file individually (never `git add -A`). By the time of the second commit, the sibling plan had already committed its own changes, confirming they were never part of this plan's history.
- A direct `godot --headless --script src/ui/title_scene.gd --check-only` invocation fails with "Identifier not found: OnboardingTelemetry" because autoloads are not registered in that isolated check mode; this is a pre-existing limitation unrelated to this plan's edit (confirmed no new parse errors via a full `godot --headless --path . --quit` project boot, which loads autoloads and registers `title_scene.gd` without error).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `invite_redeem_failed(reason)` is available for the later plan that wires the "This invite has expired" overlay with a Back-to-menu action (per this plan's `<success_criteria>`).
- `NetworkManager.report_connection_problem` is called defensively via `has_method()`; once sibling plan 13-01 lands `report_connection_problem` + `connection_problem(reason)` on `network_manager.gd`, invite-redeem failures will automatically flow into that reason-surfacing pipeline with no further changes needed here.
- No blockers.

## Self-Check: PASSED

All created/modified files verified present on disk; both task commits (`62b7582`, `5b0afe8`) verified present in `git log --oneline --all`.

---
*Phase: 13-reliability-version-match-hardening*
*Completed: 2026-07-09*
