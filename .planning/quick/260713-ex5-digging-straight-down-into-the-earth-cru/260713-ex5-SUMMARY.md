---
phase: quick
plan: 260713-ex5
subsystem: worldgen
tags: [godot_voxel, VoxelGeneratorMultipassCB, terrain-generation, gut-tests]

requires: []
provides:
  - "BEDROCK_ID=13 / LAVA_ID=14 constants in multipass_generator.gd"
  - "_generate_block_fallback override (BEDROCK below column, AIR above column)"
  - "LAVA_BAND_THICKNESS=4 floor band written by pass 0 at the bottom of every column"
  - "terrain.tscn VoxelBlockyLibrary grown to 15 models (bedrock + lava added)"
affects: [worldgen, mineshaft-generation, terrain-rendering]

tech-stack:
  added: []
  patterns:
    - "VoxelGeneratorMultipassCB._generate_block_fallback(out_buffer, origin_in_voxels) implemented per the class doc's own suggested pattern (air above, bedrock below)"

key-files:
  created: []
  modified:
    - src/world/multipass_generator.gd
    - tests/unit/test_mineshaft_generator.gd
    - src/world/terrain.tscn
    - tests/unit/test_terrain_library.gd

key-decisions:
  - "Lava band thickness fixed at 4 voxels, anchored to area_min.y (not a hardcoded world Y) so it stays correct if column_base_y_blocks is ever retuned"
  - "Bedrock/lava modeled as fully solid/opaque/collidable VoxelBlockyModelCube (a walkable floor), not a FluidSim liquid, matching the plan's explicit spec"

patterns-established:
  - "_generate_block_fallback is now the canonical backstop for any block outside the generator's column region — future multipass generators should implement it rather than relying on godot_voxel's zero-filled (AIR) default"

requirements-completed: []

duration: 25min
completed: 2026-07-13
---

# Quick Task 260713-ex5: Digging Straight Down Into The Earth Summary

**Digging straight down now always ends in a visible lava floor then an unconditional bedrock backstop, instead of falling into open void past world Y=-64.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-13T09:00:00Z (approx)
- **Completed:** 2026-07-13T09:23:47Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- `multipass_generator.gd` writes a 4-voxel LAVA band at the bottom of every column (pass 0), anchored to `area_min.y` so it never collides with any biome's surface
- `_generate_block_fallback` implemented for the first time: unconditional BEDROCK below the column floor (the true void-proof backstop, independent of pass 1 mineshaft carving), AIR above the column ceiling
- `terrain.tscn`'s VoxelBlockyLibrary grown from 13 to 15 models so the new bedrock/lava voxel ids render and collide
- 3 new regression tests added to `test_mineshaft_generator.gd`; `test_terrain_library.gd`'s `EXPECTED_MODEL_COUNT` bumped 13 -> 15

## Task Commits

Each task was committed atomically:

1. **Task 1: Lava floor band (pass 0) + BEDROCK/AIR fallback** - `a1a817d` (fix)
2. **Task 2: Add BEDROCK (13) and LAVA (14) to the VoxelBlockyLibrary in terrain.tscn** - `4a23ecf` (fix)
3. **Style follow-up: remove em-dashes introduced in new comments** - `4e85f14` (style)

_No plan metadata commit for this quick task — SUMMARY.md and STATE.md are not committed per this session's instructions (docs are intentionally left uncommitted for the orchestrator/user)._

## Files Created/Modified
- `src/world/multipass_generator.gd` - Adds BEDROCK_ID/LAVA_ID/LAVA_BAND_THICKNESS constants, lava band write in `_generate_base_terrain`, and the new `_generate_block_fallback` override
- `tests/unit/test_mineshaft_generator.gd` - 3 new tests: fallback returns bedrock below column, fallback returns air above column, lava floor band at column bottom (no-mineshaft column 0,0 / seed 1234)
- `src/world/terrain.tscn` - Two new `VoxelBlockyModelCube` sub_resources (bedrock id 15_bedrock, lava id 16_lava), `load_steps` bumped 21->23, `models` array extended, header comment corrected (added missing `12 = leaves` line + new `13`/`14` lines)
- `tests/unit/test_terrain_library.gd` - `EXPECTED_MODEL_COUNT` 13 -> 15, header comment updated

## Decisions Made
- Lava/bedrock use `VoxelBlockyModelCube` (solid, collidable) exactly as the plan specified — a walkable floor a player hits when digging down, not a liquid the FluidSim manages.
- No locale/*.po changes: lava and bedrock are terrain materials referenced only in code comments and .tscn resource names, not in any player-facing UI string, so no i18n surface was introduced.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 / CLAUDE.md compliance] Removed em-dashes introduced in newly added comments**
- **Found during:** Post-Task-2 hygiene pass (before final self-check)
- **Issue:** Three new test-list comment lines in `test_mineshaft_generator.gd` and two touched header lines in `test_terrain_library.gd` used em-dashes ("—"), copying the pre-existing file's stylistic convention. This violates the project's and user's global CLAUDE.md hard constraint ("Never use em-dashes or en-dashes in any output... prose, code, comments...").
- **Fix:** Replaced em-dashes with parentheses or a colon in the newly-added/touched lines only. Pre-existing em-dashes elsewhere in both files (not touched by this task) were left as-is per the deviation-rules scope boundary (out-of-scope pre-existing content).
- **Files modified:** `tests/unit/test_mineshaft_generator.gd`, `tests/unit/test_terrain_library.gd`
- **Verification:** Both GUT test files re-run green (15/15 and 4/4); `git diff` of the fix contains no em-dash/en-dash characters.
- **Committed in:** `4e85f14`

---

**Total deviations:** 1 auto-fixed (CLAUDE.md style compliance, no functional change)
**Impact on plan:** Cosmetic only. No scope creep; all test logic and generator behavior unchanged from the plan's exact spec.

## Issues Encountered
None.

## Known Limitation (documented, not a defect)

Per the plan's explicit scope: on the ~35% of columns where a mineshaft spawns, pass 1's corridor template always carves starting at `area_min.y` (the same Y range as the new lava band), so a minority of columns show a mineshaft corridor floor instead of a lava floor at the very bottom. This does NOT reintroduce the void bug — the BEDROCK fallback one block below the column is completely independent of pass 1 and always holds. Flagged as a known, accepted limitation, not fixed in this task (out of scope per plan).

## Verification Results

**Automated (all green):**
- `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_mineshaft_generator.gd -gexit` -> 15/15 passed (12 pre-existing + 3 new)
- `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_terrain_library.gd -gexit` -> 4/4 passed (EXPECTED_MODEL_COUNT=15)
- `godot --headless --path . --quit` -> no parse errors (only a pre-existing, unrelated ObjectDB-leak warning on exit, not caused by this task's changes)

**Manual (display-gated, NOT performed in this headless session — left for the user):**
1. Start/continue a world, dig straight down with LMB at the same column. Expect to hit a bright orange LAVA layer around Y=-60..-64 (band thickness 4), then a dark BEDROCK floor immediately below that you stand on and cannot fall past.
2. Repeat at a second spawn location/biome to confirm the floor is universal, not just near world origin.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- The void-fall bug is fully closed at the engine/generator level; only in-viewport human confirmation (item 2 above) remains, which is display-gated and cannot run headlessly.
- No blockers for other in-flight work (Phases 10-16); this is an isolated worldgen fix touching only `multipass_generator.gd` and `terrain.tscn`.

---
*Phase: quick*
*Completed: 2026-07-13*
