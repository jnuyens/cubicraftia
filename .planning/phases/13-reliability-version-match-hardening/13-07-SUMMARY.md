---
phase: 13-reliability-version-match-hardening
plan: 07
subsystem: ui
tags: [godot, gdscript, networking, ui, tscn, connection-problem-overlay, network-hud, join-screen]

# Dependency graph
requires:
  - phase: 13-reliability-version-match-hardening
    provides: "13-05 built ConnectionProblemOverlay (Surface A); 13-06 migrated JoinScreen onto it, added the Connecting spinner, and added the always-visible NetworkHud Direct/Relay badge; 13-03 added the stale-invite report_connection_problem(\"expired\") call site on title_scene; 13-04 added PROTOCOL_VERSION handshake + ICE connection-type tracking"
provides:
  - "NetworkHud instanced under main_scene's UI CanvasLayer (top-right Direct/Relay badge)"
  - "ConnectionProblemOverlay instanced as a scene-root sibling CanvasLayer (layer=110) in both main_scene.tscn and title_scene.tscn"
  - "main_scene.gd _install_network_ui_wiring(): instantiates JoinScreen when the local peer is mid-handshake (STATE_CONNECTING) and not the session host"
affects: [phase-13-verification, future-multiplayer-ui-phases]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Scene-tree wiring for self-subscribing UI overlays: instance as a static child in .tscn, let the overlay's own _ready() subscribe to autoload signals, no extra glue code needed in the host scene's script"
    - "_install_network_ui_wiring() sibling method to the existing _install_parental_gate_wiring() precedent in main_scene.gd _ready(), reusing the same ResourceLoader.exists()/load()-as-PackedScene/null-check/instantiate() defensive sequence"

key-files:
  created: []
  modified:
    - "src/world/main_scene.tscn - added NetworkHud (under UI CanvasLayer) and ConnectionProblemOverlay (scene-root sibling, layer=110) ExtResource + node instances"
    - "src/world/main_scene.gd - added _install_network_ui_wiring(), called from _ready() alongside _install_parental_gate_wiring()"
    - "src/ui/title_scene.tscn - added ConnectionProblemOverlay ExtResource + node instance as a direct child of the TitleScene root CanvasLayer"

key-decisions:
  - "Explicitly call show() on the newly instantiated JoinScreen in _install_network_ui_wiring(), beyond the plan's literal text (Rule 1 bug fix): JoinScreen's own script only reveals itself in reaction to a session_state_changed signal firing after it enters the tree, but the state is already STATE_CONNECTING at the moment main_scene instantiates it (that is the very condition checked before instantiating), so no such signal fires again and the CanvasLayer would otherwise stay invisible (visible=false at scene load)."
  - "Used direct NetworkManager.<method>()/NetworkManager.STATE_CONNECTING autoload access in _install_network_ui_wiring() (matching the existing convention elsewhere in main_scene.gd, e.g. NetworkManager.get_session_id() at line 822) rather than a generic Node + string-based get_node_or_null()/call()/get() reflection pattern, since GDScript constants are not reliably retrievable via Object.get(String) on a loosely-typed Node reference."
  - "title_scene.tscn keeps its documented 'no child nodes in .tscn, all built in _build_ui()' convention as the general rule, with ConnectionProblemOverlay called out as the single explicit exception (own self-subscribing CanvasLayer, no code coupling to title_scene.gd's programmatic UI construction)."

patterns-established:
  - "Self-subscribing overlay pattern: a UI surface that subscribes to an autoload signal in its own _ready() only needs a static scene-tree instance wherever it should be reachable; the host scene needs zero additional script wiring for it to work."

requirements-completed: [RELY-01, RELY-02, RELY-03, RELY-05]

# Metrics
duration: 18min
completed: 2026-07-09
---

# Phase 13 Plan 07: Scene-Tree Wiring for Connection-Problem Overlay, NetworkHud, JoinScreen Summary

**Instanced the three Phase 13 UI surfaces (ConnectionProblemOverlay, NetworkHud, JoinScreen) into main_scene.tscn and title_scene.tscn, which previously existed only as orphaned .tscn files never reachable in a running game.**

## Performance

- **Duration:** ~18 min (autonomous tasks 1-2; task 3 is a blocking human-verify checkpoint, not yet run)
- **Started:** 2026-07-09T23:30:00+02:00 (approx)
- **Completed (autonomous tasks):** 2026-07-09T23:49:18+02:00
- **Tasks:** 2 of 3 (Task 3 is `checkpoint:human-verify`, gate=blocking, awaiting a human)
- **Files modified:** 3

## Accomplishments

- `NetworkHud` (top-right Direct/Relay badge) is now instanced under `main_scene.tscn`'s `UI` CanvasLayer, following the exact `instance=ExtResource(...)` pattern already used by `MobileOverlay`/`Toast`/`Crosshair`/`Compass`/`HpBar`/`DeathScreen`/`InventorySlideIn`.
- `ConnectionProblemOverlay` (Surface A, own `CanvasLayer` layer=110) is now instanced as a direct child of the scene root in **both** `main_scene.tscn` (in-session coverage) and `title_scene.tscn` (pre-join stale-invite coverage per RELY-04 / Plan 13-03). It is self-subscribing (its own `_ready()` connects to `NetworkManager.connection_problem`), so no additional glue code was needed in either host scene's script.
- `main_scene.gd` gained `_install_network_ui_wiring()`, a sibling method to the existing `_install_parental_gate_wiring()` precedent, called from `_ready()` right after it. It instantiates `JoinScreen` only when `NetworkManager.get_state() == NetworkManager.STATE_CONNECTING` and `NetworkManager.is_session_host()` is false (i.e., the local peer loaded `main_scene` mid-handshake as a joiner, not a host), reusing the same `ResourceLoader.exists()` / `load()` as `PackedScene` / null-check / `instantiate()` defensive sequence already established for the parental-gate panel.
- All three surfaces are now reachable in a real running session rather than existing only as orphaned scene files, closing the gap the plan objective identified across RELY-01/02/03/05.

## Task Commits

Each autonomous task was committed atomically:

1. **Task 1: Wire NetworkHud + ConnectionProblemOverlay + conditional JoinScreen into main_scene** - `5a6910b` (feat)
2. **Task 2: Wire ConnectionProblemOverlay into title_scene** - `578ebe6` (feat)

Task 3 (`checkpoint:human-verify`, gate=blocking) has not been executed — see "Checkpoint Reached" below.

**Plan metadata commit:** not yet created — deferred until the human-verify checkpoint is resolved by a follow-up execution pass, per the plan's own gating (the plan's `<verification>` block requires "Human-verify checkpoint approved" as one of its four conditions, which cannot be satisfied by this agent).

## Files Created/Modified

- `src/world/main_scene.tscn` - Added `ExtResource` entries for `network_hud.tscn` (`16_network_hud`) and `connection_problem_overlay.tscn` (`17_connproblem`); added `NetworkHud` node instance under `UI` (parent="UI"); added `ConnectionProblemOverlay` node instance as a scene-root sibling (parent="."). Bumped `load_steps` 25 → 27.
- `src/world/main_scene.gd` - Added `_install_network_ui_wiring()` and its call site in `_ready()` immediately after `_install_parental_gate_wiring()`.
- `src/ui/title_scene.tscn` - Added `ExtResource` entry for `connection_problem_overlay.tscn` (`2_connproblem`); added `ConnectionProblemOverlay` node instance as a direct child of the `TitleScene` root `CanvasLayer`. Bumped `load_steps` 2 → 3. Updated the file's header comment to note this one exception to the "all UI built programmatically" convention.

## Decisions Made

See `key-decisions` in frontmatter. In summary:
1. Added an explicit `.show()` call on the newly instantiated `JoinScreen` in `_install_network_ui_wiring()` — the plan's literal action text stopped at `setup()`, but without this call the overlay would silently never appear (Rule 1 bug fix, documented below).
2. Used the codebase's established direct-autoload-access convention (`NetworkManager.get_state()`, `NetworkManager.STATE_CONNECTING`, `NetworkManager.is_session_host()`, `NetworkManager.get_session_id()`) rather than string-based `get_node_or_null()` + `call()`/`get()` reflection, matching how `main_scene.gd` already accesses `NetworkManager` elsewhere (e.g. line 822) and how `join_screen.gd` itself accesses `NetworkManager.STATE_CONNECTING`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] JoinScreen would never become visible when instantiated mid-connecting**
- **Found during:** Task 1 (writing `_install_network_ui_wiring()`)
- **Issue:** `join_screen.gd`'s root `CanvasLayer` has `visible = false` at scene load. The script's own `_on_session_state_changed()` handler only calls `show()` in reaction to a `NetworkManager.session_state_changed` signal transitioning into `STATE_CONNECTING`. Since `main_scene.gd` only instantiates `JoinScreen` when the state is **already** `STATE_CONNECTING` (that is the literal precondition the plan specifies for instantiating it at all), the signal that would normally trigger visibility has already fired before `JoinScreen` entered the tree, and no further transition into `STATE_CONNECTING` will occur. Without a fix, the newly wired `JoinScreen` would be instantiated, correctly configured via `setup()`, but permanently invisible — silently defeating the entire purpose of this task.
- **Fix:** Added an explicit `join_screen.call("show")` immediately after `setup()` in `_install_network_ui_wiring()`, gated by `has_method("show")` for defensive consistency with the rest of the function.
- **Files modified:** `src/world/main_scene.gd`
- **Verification:** Headless project boot (`godot --headless --path . --quit`) shows no parse/scene errors; full GUT suite (492 tests) passes with 0 failures (463 passing, 29 pre-existing pending/risky unrelated to this change). Full in-viewport visual confirmation of `JoinScreen` actually appearing during a real join is part of the Task 3 human-verify checkpoint below (display-gated, cannot be verified headless).
- **Committed in:** `5a6910b` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix, Rule 1)
**Impact on plan:** Necessary for the plan's own stated goal — an instantiated-but-invisible `JoinScreen` would not satisfy "reachable in a running game session, not orphaned scene files." No scope creep beyond `_install_network_ui_wiring()` itself.

## Issues Encountered

None beyond the deviation documented above.

## Verification Performed (autonomous scope only)

- `grep -c "NetworkHud" src/world/main_scene.tscn` → 2 (ExtResource declaration + node instance)
- `grep -c "ConnectionProblemOverlay" src/world/main_scene.tscn` → 2 (comment + node instance)
- `grep -c "func _install_network_ui_wiring" src/world/main_scene.gd` → 1
- `grep -c "ConnectionProblemOverlay" src/ui/title_scene.tscn` → 3 (header comment mention, section comment, node instance)
- `godot --headless --path . --quit` → exit code 0, no parse/scene errors referencing `main_scene`/`title_scene`/`network_hud`/`join_screen`/`connection_problem` (grep for those terms in the output returned nothing). Engine-teardown noise (orphan StringName counts, "N resources still in use at exit") is generic Godot 4.6 shutdown chatter unrelated to these scene edits — confirmed by `--verbose` output showing only engine-internal class names (`VoxelMesher`, `WebRTCPeerConnection`, etc.), none of which reference the files this plan touched.
- Full GUT suite (`godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://tests/gut_config.cfg`): **463 passing, 0 failing**, 29 pre-existing pending/risky (unrelated to this plan — e.g. tests pending GPU/display, or pending future Plans 03-02/03-04/03-09). No new failures introduced.

## CHECKPOINT REACHED

**Type:** human-verify
**Plan:** 13-07
**Progress:** 2/3 tasks complete

### Completed Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Wire NetworkHud + ConnectionProblemOverlay + conditional JoinScreen into main_scene | `5a6910b` | `src/world/main_scene.tscn`, `src/world/main_scene.gd` |
| 2 | Wire ConnectionProblemOverlay into title_scene | `578ebe6` | `src/ui/title_scene.tscn` |

### Current Task

**Task 3:** Human-verify the full Phase 13 UI-SPEC Acceptance Checkpoints end-to-end
**Status:** blocked — requires a human running the actual game client(s) in-viewport; cannot be verified headless or self-approved.
**Blocked by:** Needs a real running two-client session (host + peer) to visually confirm spinner animation, overlay copy/buttons, badge rendering, and the version-mismatch reject path — none of which a headless boot or GUT test can observe.

### Checkpoint Details

**What was built:** The full Phase 13 reliability/version-match surface, now actually wired into the scene tree: the shared connection-problem overlay (7 reasons) on both `title_scene` and `main_scene`, the non-frozen Connecting spinner in `JoinScreen` with a bounded timeout, the silent auto-reconnect grace window, the always-visible Direct/Relay badge in `NetworkHud`, and the `PROTOCOL_VERSION` join-handshake reject.

**How to verify** (walk the 13-UI-SPEC.md "Acceptance Checkpoints" list end-to-end against a running two-client session — host + peer on the same machine or two machines):

1. Trigger each of the 7 `connection_problem` reasons (easiest via a temporary direct call to `NetworkManager.report_connection_problem("<reason>")` from the in-editor Remote inspector, or by exercising the real trigger: expired invite link, 5th peer joining a 4-peer session, mismatched `PROTOCOL_VERSION` build, killing the signaling connection mid-join for timeout, etc.) and confirm each shows distinct body copy under one shared heading, with the correct button set (Retry+Back for `relay_failed`/`timeout`, Back only for the other 5).
2. Confirm the `blocked` reason's copy never contains the word "blocked".
3. Confirm Escape and clicking the scrim do NOT dismiss the overlay; only its own button(s) do.
4. Join a session and confirm the Connecting spinner animates (not frozen) and, if the host is unreachable, resolves to the timeout/relay_failed reason within 10-15 seconds (never hangs indefinitely).
5. Confirm the NetworkHud badge shows "Direct" or "Relay" for every connected peer at all times (never hidden), with no hover/click affordance.
6. Confirm a build with a deliberately bumped `BuildInfo.PROTOCOL_VERSION` is cleanly rejected with the `version_mismatch` reason when it tries to join a session hosted by an unmodified build.

### Awaiting

A human must launch the actual game (editor Play or an exported build) with a two-client session and confirm all six checks above pass in-viewport. Type "approved" once all six checks pass, or describe which checkpoint failed, to resume this plan.

## User Setup Required

None - no external service configuration required. The checkpoint above requires manual in-app verification, not external service setup.

## Next Phase Readiness

- Scene-tree wiring is complete and verified headlessly (no parse errors, full GUT suite green).
- Phase 13 cannot be marked fully verified/complete until Task 3's human-verify checkpoint is explicitly approved (or a described failure is triaged and fixed) by a human running the actual client.
- This plan's own `<verification>` block requires "Human-verify checkpoint approved" as one of four conditions — that condition is not yet met, so this plan is NOT closed out with a `docs(13-07): complete` metadata commit yet. Once approved, run a follow-up pass to: (a) update `STATE.md`/`ROADMAP.md`/`REQUIREMENTS.md`, and (b) create the final `docs(13-07): complete` commit.

---
*Phase: 13-reliability-version-match-hardening*
*Completed (autonomous scope): 2026-07-09 — Task 3 (human-verify) still pending*

## Self-Check: PASSED

- FOUND: `src/world/main_scene.tscn`
- FOUND: `src/world/main_scene.gd`
- FOUND: `src/ui/title_scene.tscn`
- FOUND: commit `5a6910b`
- FOUND: commit `578ebe6`
