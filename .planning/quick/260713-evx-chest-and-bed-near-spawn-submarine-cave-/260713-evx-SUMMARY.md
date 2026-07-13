---
phase: quick
plan: 260713-evx
subsystem: world-gen, ui
tags: [gdscript, godot, structure-placement, spawn, biome, sign-in-panel]

requires: []
provides:
  - "search_land_spawn excludes MOUNTAIN biome columns (matches existing OCEAN exclusion)"
  - "_temple_anchor_y helper: seabed-aware anchor for OCEAN-biome temple variants, ground-flush anchor for land variants"
  - "title_scene.gd sign_in_panel overlay explicitly made visible on open (both entry points)"
affects: [world-spawn, structure-placement, title-screen-onboarding]

tech-stack:
  added: []
  patterns:
    - "Temple-specific anchor helper mirrors an already-shipped formula (main_scene._seabed_surface_at) rather than duplicating logic ad hoc"

key-files:
  created:
    - tests/integration/test_title_scene_create_account.gd
  modified:
    - src/world/main_scene.gd
    - tests/unit/test_spawn_on_land.gd
    - src/world/structure_placer.gd
    - tests/integration/test_structure_placement.gd
    - src/ui/title_scene.gd

key-decisions:
  - "Fixed the identical missing-visible bug in _show_inline_sign_in_for_invite (deep-link entry point) in the same task/commit as the title-screen Create account fix, per explicit plan expansion instruction — same one-line root cause, same file, same scope."

patterns-established: []

requirements-completed: []

duration: 4min
completed: 2026-07-13
---

# Quick Task 260713-evx: Chest/Bed Spawn, Submarine Cave, Jungle Temple, Create Account Summary

**Four narrow real-device bug fixes: MOUNTAIN-biome exclusion in world-spawn search, a temple-specific seabed/ground-flush anchor helper in structure placement, and a missing `panel.visible = true` in both sign-in-panel entry points on the title screen.**

## Performance

- **Duration:** ~4 min (execution only; excludes read/planning time)
- **Started:** 2026-07-13T09:01:40Z
- **Completed:** 2026-07-13T09:05:09Z
- **Tasks:** 3/3 completed
- **Files modified:** 5 modified, 1 created

## Accomplishments
- `search_land_spawn` (src/world/main_scene.gd) now skips both OCEAN and MOUNTAIN biome candidates, so the deterministic spawn column always agrees with `_terrain_surface_at` (which includes `_mountain_lift_at`). Fixes the starter chest/bed landing tens of metres from the builder on mountain-adjacent spawns.
- `structure_placer.gd` gained a `_temple_anchor_y` helper used only for `structure_type == "temple"`: OCEAN-biome temple variants (underwater_temple_*) now anchor on the real, deepened seabed (mirroring `main_scene._seabed_surface_at`'s formula) instead of the land height formula; all temple variants (land and OCEAN) now account for their template floor being authored at local cell Y=1 (not Y=0), fixing the 1-block float. village/shipwreck/dungeon anchor logic is untouched.
- `title_scene.gd`'s `_on_sign_in_pressed` now sets `panel.visible = true` immediately after instantiating `sign_in_panel.tscn` (which ships `visible = false` by contract). Fixes both "Sign in" and "Create account" appearing to do nothing when clicked.
- **Scope expansion (per plan instruction):** the identical missing-visible bug in `_show_inline_sign_in_for_invite` (the deep-link invite entry point, ~line 590) was fixed in the same commit — same one-line root cause, same file.

## Task Commits

Each task was committed atomically:

1. **Task 1: Exclude MOUNTAIN biome from world-spawn search** - `a3833fe` (fix)
2. **Task 2: Temple-specific anchor, seabed-aware and ground-flush** - `333bb03` (fix)
3. **Task 3: Fix "Create account" button + sibling invite-flow sign-in panel** - `3bc16c0` (fix)

_No plan metadata commit yet — orchestrator handles STATE.md/SUMMARY.md commit separately._

## Files Created/Modified
- `src/world/main_scene.gd` - `search_land_spawn` biome-exclusion loop now excludes MOUNTAIN alongside OCEAN
- `tests/unit/test_spawn_on_land.gd` - added `test_spawn_column_is_not_mountain` (5/5 pass)
- `src/world/structure_placer.gd` - added `OCEAN_FLOOR_DEPTH`/`OCEAN_FLOOR_RELIEF` constants, `_temple_anchor_y` helper, wired into the "temple" branch of `should_place_structure_at_cell`'s anchor_y assignment
- `tests/integration/test_structure_placement.gd` - added `test_underwater_temple_anchors_below_sea_level` and `test_jungle_temple_floor_flush_with_ground` (6/6 pass)
- `src/ui/title_scene.gd` - `panel.visible = true` added in `_on_sign_in_pressed` (both Sign in / Create account) and in `_show_inline_sign_in_for_invite` (deep-link sign-in)
- `tests/integration/test_title_scene_create_account.gd` - new file, `test_create_account_button_opens_visible_panel` + `test_sign_in_button_opens_visible_panel` (2/2 pass)

## Decisions Made
None beyond the plan's own explicit scope-expansion instruction (fix the sibling `_show_inline_sign_in_for_invite` visibility bug in Task 3, documented above).

## Deviations from Plan

None beyond the plan's own explicitly authorized expansion (fixing `_show_inline_sign_in_for_invite` alongside `_on_sign_in_pressed` in Task 3, which the plan itself flagged and the execution instructions directed to include in scope). No Rule 1/2/3/4 auto-fixes were needed; the plan's action blocks were followed as specified.

## Issues Encountered
None. All three GUT test files passed headlessly on the first run after implementation; the headless boot check (`godot --headless --path . --quit`) showed no parse errors (only pre-existing engine shutdown noise: ObjectDB/resource leak warnings unrelated to these changes).

## User Setup Required

None - no external service configuration required.

## Verification Status

**Automated (confirmed green, headless):**
- `tests/unit/test_spawn_on_land.gd` - 5/5 passed (55 asserts)
- `tests/integration/test_structure_placement.gd` - 6/6 passed (783 asserts)
- `tests/integration/test_title_scene_create_account.gd` - 2/2 passed (6 asserts)
- Boot check `godot --headless --path . --quit` - no SCRIPT ERROR / parse errors

**Manual (in-viewport, display-gated, NOT verified in this session — left for the user to spot-check per the plan's verification section):**
1. Chest/bed near spawn on a fresh SURVIVAL world across several seeds, including a mountain-adjacent one.
2. Submarine cave / underwater temple genuinely submerged (glass dome + water on all sides, resting on seabed).
3. Jungle temple base flush with the ground, no floating gap.
4. Clicking "Create account" on the title screen visibly opens the sign-up panel; "Sign in" also still opens correctly.

## Next Phase Readiness
All three fixes are self-contained bug corrections in already-shipped Phase 2/3/6 systems; no new systems introduced, no follow-on work required. The four real-device-reported bugs are closed pending the user's manual in-viewport spot-check (display-gated, cannot be verified headlessly).

---
*Phase: quick*
*Completed: 2026-07-13*

## Self-Check: PASSED

All 6 modified/created source and test files verified present on disk. All 3 task commits (a3833fe, 333bb03, 3bc16c0) verified present in git log.
