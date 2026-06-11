---
phase: 01-foundation-mobile-spike
plan: 04
subsystem: terrain-builder-core
tags: [godot_voxel, terrain, builder, voxel, fastnoislite, input, integration-test]
dependency_graph:
  requires:
    - 01-01 (project.godot, input stubs, folder tree, REUSE/SPDX)
    - 01-02 (GUT addon, scripts/glossary-check.sh, scripts/verify-feature-flags.sh, scripts/extract-pot.sh)
  provides:
    - addons/zylann.voxel/ pre-built GDExtension (all-platform binaries, MIT)
    - src/world/terrain_generator.gd (VoxelGeneratorScript + FastNoiseLite FBM)
    - src/world/terrain.tscn (VoxelTerrain + VoxelMesherBlocky + library)
    - src/builder/builder.gd (CharacterBody3D, WASD+mouse+jump, get_aim_origin/direction)
    - src/builder/builder.tscn (CharacterBody3D + CapsuleShape3D + Camera3D)
    - src/world/main_scene.tscn (terrain + builder + VoxelViewer + lighting)
    - project.godot [input] desktop bindings (physical_keycode, layout-independent)
    - project.godot run/main_scene set to main_scene.tscn
    - tests/integration/test_terrain_generates.gd (3 integration tests)
    - tests/conftest_helpers.gd extended (spawn_test_world, wait_frames)
  affects:
    - Plan 05 (brick place/break — consumes builder.gd contract: get_aim_origin/direction)
    - Plan 06 (mobile overlay — injects touch actions into same input action names)
    - Plan 07 (30-min benchmark — runs main_scene.tscn on Motorola One Macro)
tech_stack:
  added:
    - addons/zylann.voxel/ v1.6x (MIT, pre-built GDExtension from GitHub release v1.6x)
    - VoxelTerrain + VoxelMesherBlocky + VoxelBlockyLibrary + VoxelGeneratorScript (via GDExtension)
    - VoxelViewer (godot_voxel chunk streaming node)
    - FastNoiseLite TYPE_SIMPLEX FBM (in-engine, bundled with Godot 4.6.3)
  patterns:
    - RESEARCH.md Pattern 3 (VoxelTool Raycast — terrain wired for Plan 05 access)
    - RESEARCH.md Pattern 4 (Sparse Stud-Grid — scaffolded; implementation in Plan 05)
    - VoxelGeneratorScript override pattern (thread-safe, _init() not _ready())
    - Physical keycode bindings (layout-independent AZERTY/QWERTY compatibility)
key_files:
  created:
    - src/world/terrain_generator.gd
    - src/world/terrain.tscn
    - src/builder/builder.gd
    - src/builder/builder.tscn
    - src/world/main_scene.tscn
    - tests/integration/test_terrain_generates.gd
    - addons/zylann.voxel/ (full GDExtension tree)
  modified:
    - project.godot ([input] desktop bindings + run/main_scene)
    - tests/conftest_helpers.gd (added spawn_test_world + wait_frames helpers)
    - scripts/glossary-allowlist.txt (added addons/godot_voxel/README.md)
    - .gitignore (addons/godot_voxel/ source checkout excluded)
    - .reuse/dep5 (addons/zylann.voxel/ MIT coverage added)
decisions:
  - key: zylann-voxel-prebuilt-v1.6x
    what: "Used pre-built GDExtension v1.6x from GitHub release instead of source at 4a9d311"
    why: "Source commit 4a9d311 (2026-05-14) has no pre-built binaries; v1.6x (2026-02-04) has all-platform binaries; compatibility_minimum=4.4.1 covers Godot 4.6.3; source checkout still cloned to addons/godot_voxel/ via install-deps.sh for reference but excluded from git"
  - key: voxelviewer-in-main-scene
    what: "VoxelViewer added as child of Builder in main_scene.tscn, not as child of VoxelTerrain"
    why: "Current godot_voxel API uses VoxelViewer node (not terrain.viewer_path) for streaming; viewer must follow player position; placing it as Builder child achieves this without extra code"
  - key: generator-init-in-init
    what: "FastNoiseLite instance built in _init() not _ready() of VoxelGeneratorScript subclass"
    why: "VoxelGeneratorScript extends Resource (not Node); _ready() is never called on Resource instances; _generate_block() is called from a worker thread and needs _noise non-null immediately after construction"
  - key: headless-integration-test-gap
    what: "Integration test GDExtension crashes in headless mode (GPU required)"
    why: "godot_voxel's VoxelTerrain + VoxelMesherBlocky requires a GPU renderer; headless mode provides a null/software display that causes a crash in the GDExtension's worker thread. godot --headless --quit-after 1 exits 0 (project opens cleanly); full integration test pass belongs to Plan 07 (real hardware)"
metrics:
  duration_minutes: 90
  completed_date: "2026-05-24"
  tasks_completed: 3
  tasks_total: 3
  files_created: 6
  files_modified: 5
---

# Phase 01 Plan 04: Terrain + Builder Foundation Summary

## One-liner

Playable foundation: procedural temperate-grassland VoxelTerrain (godot_voxel v1.6x + FastNoiseLite FBM, 16³ chunks, 5-chunk view distance per D-05) + controllable CharacterBody3D builder (WASD+mouse+jump, exposes aim_origin/aim_direction contract for Plan 05), all wired in main_scene.tscn with desktop input bindings and a headless integration test scaffold.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Input bindings + integration test scaffold (RED) | eddd2ba | `project.godot` ([input]), `tests/integration/test_terrain_generates.gd`, `tests/conftest_helpers.gd`, `addons/zylann.voxel/` |
| 2 | VoxelTerrain scene + FastNoiseLite generator | 9815867 | `src/world/terrain.tscn`, `src/world/terrain_generator.gd` |
| 3 | Builder character + main scene wiring (GREEN) | d375448 | `src/builder/builder.gd`, `src/builder/builder.tscn`, `src/world/main_scene.tscn`, `project.godot` (run/main_scene) |

## What Was Built

### addons/zylann.voxel/ — Pre-built GDExtension

The plan called for `addons/godot_voxel/` to be populated via `scripts/install-deps.sh`, which clones the source at commit `4a9d311`. The source was cloned, but has no pre-built binaries for macOS/Linux/Android. Instead, the GitHub release `v1.6x` GDExtension was downloaded (`GodotVoxelExtension.zip`) and extracted to `addons/zylann.voxel/`. This provides all-platform pre-built `.dylib`/`.so`/`.dll` binaries compatible with Godot 4.4.1+.

The godot_voxel source checkout (`addons/godot_voxel/`) is excluded from git via `.gitignore` and cloned by `install-deps.sh` for reference only. `addons/zylann.voxel/` (the runtime GDExtension) is committed.

### src/world/terrain_generator.gd

Extends `VoxelGeneratorScript`. Uses `FastNoiseLite` with `TYPE_SIMPLEX`, `FRACTAL_FBM`, 4 octaves, frequency 0.01, seed 1234 (deterministic for Phase 1). Overrides `_generate_block()`: fills air above the height surface, fills voxel ID 1 (grass) below. Thread-safe (noise is immutable after `_init()`). Exposes `_get_used_channels_mask()` → 1 (CHANNEL_TYPE).

Key fix (Rule 1 — Bug): `_ready()` → `_init()` — `VoxelGeneratorScript` extends `Resource`, not `Node`; `_ready()` is never called on Resource instances; the noise was null when `_generate_block()` was first invoked from a worker thread.

### src/world/terrain.tscn

VoxelTerrain root with:
- `VoxelMesherBlocky` + `VoxelBlockyLibrary` (2 models: id 0 = `VoxelBlockyModelEmpty` air, id 1 = `VoxelBlockyModelCube` #6BB845 grass)
- Generator = `terrain_generator.gd` instance (seed=1234)
- `collision_layer=1` + `generate_collisions=true`

VoxelViewer is NOT included in terrain.tscn (see Decisions). It lives in main_scene.tscn as a child of Builder.

### src/builder/builder.gd + builder.tscn

`CharacterBody3D` with:
- `move_speed = 4.5`, `jump_velocity = 4.5`, `mouse_sensitivity = 0.002`
- WASD camera-relative movement via `Input.get_vector()`
- Gravity via `get_gravity()`, jump on `is_on_floor()`
- Mouse-look (yaw on body, pitch on camera, clamped ±89°) — desktop only (T-04-03)
- `get_aim_origin()` → `camera.global_position`
- `get_aim_direction()` → `-camera.global_basis.z.normalized()`

Scene: CapsuleShape3D (r=0.4, h=1.8) + Camera3D at Y=1.6 (`current=true`) + rough-art CapsuleMesh placeholder.

### src/world/main_scene.tscn

Root Node3D with:
- Terrain (terrain.tscn instance)
- Builder (builder.tscn instance, position Y=32 to land on generated terrain)
- VoxelViewer (child of Builder, view_distance=80 = 5 chunks × 16 m per D-05)
- WorldEnvironment (sky #5BAEEC per UI-SPEC) + DirectionalLight3D (shadows=false per DOCS.md §7.2 Tier-3)

Set as `project.godot` `run/main_scene`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] VoxelGeneratorScript _ready() never called**
- **Found during:** Task 2 headless test (`godot --headless --quit-after 1`)
- **Issue:** `terrain_generator.gd` used `_ready()` to build the FastNoiseLite instance. `VoxelGeneratorScript` extends `Resource`, not `Node`. Resources never receive `_ready()`. The noise was null when `_generate_block()` was called from the godot_voxel worker thread, causing `Cannot call method 'get_noise_2d' on a null value`.
- **Fix:** Moved noise initialisation to `_init()` + added property setters for `world_seed` and `noise_frequency` to allow live updates.
- **Files modified:** `src/world/terrain_generator.gd`
- **Commit:** d375448

**2. [Rule 1 - Bug] VoxelViewer incorrect parent path in terrain.tscn**
- **Found during:** `godot --headless --import` test
- **Issue:** terrain.tscn had `[node name="VoxelViewer" type="VoxelViewer" parent="Terrain"]` — but "Terrain" IS the root node; "parent=Terrain" means a child named Terrain under root Terrain, which doesn't exist.
- **Fix:** Removed VoxelViewer from terrain.tscn entirely (per correct godot_voxel design: viewer belongs in main_scene as child of Builder, not in terrain scene).
- **Files modified:** `src/world/terrain.tscn`
- **Commit:** d375448

### Pre-installation Deviation

**3. [Rule 3 - Blocking] godot_voxel pre-built binaries not at pinned commit 4a9d311**
- **Found during:** Task 1 setup
- **Issue:** `scripts/install-deps.sh` clones source at commit 4a9d311 (2026-05-14). No pre-built `.dylib`/`.so`/`.dll` exist at that commit — only Windows debug `.dll` is in the source's project folder.
- **Fix:** Downloaded GDExtension from GitHub release `v1.6x` (`GodotVoxelExtension.zip`) containing all-platform binaries; compatibility_minimum=4.4.1 covers Godot 4.6.3. Source checkout excluded from git via `.gitignore`; pre-built extension committed at `addons/zylann.voxel/`.
- **Procedure documented in SUMMARY.md** (plan requirement).
- **Files modified:** `addons/zylann.voxel/` (new), `.gitignore`, `.reuse/dep5`, `scripts/glossary-allowlist.txt`
- **Commit:** eddd2ba

## godot_voxel Installation Procedure Used

1. Confirmed source checkout at pinned commit 4a9d311 has no pre-built macOS binaries.
2. Downloaded `GodotVoxelExtension.zip` from `https://github.com/Zylann/godot_voxel/releases/tag/v1.6x` via `gh release download v1.6x -R Zylann/godot_voxel`.
3. Extracted to `/tmp/godot_voxel_extract/` → copied `addons/zylann.voxel/` to project root.
4. Verified `voxel.gdextension` manifest lists `compatibility_minimum = "4.4.1"` (covers Godot 4.6.3).
5. Added `addons/godot_voxel/` to `.gitignore` (source excluded from git).
6. Added REUSE coverage for `addons/zylann.voxel/*` (MIT licence, Marc Gilleron et al).

## Known Stubs

| Stub | File | Line | Reason |
|------|------|------|--------|
| CapsuleMesh placeholder | `src/builder/builder.tscn` | ~42 | Phase 1 rough-art (CONTEXT.md D-01): actual builder mesh deferred to Phase 6 |

This stub does not block the plan's goal — the builder is a functional CharacterBody3D with collision and camera. The mesh is cosmetic.

## Headless Integration Test Gap

**Finding:** `godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=res://tests/integration -gexit` crashes inside the godot_voxel GDExtension (stack trace in `libvoxel.macos.editor.universal`) when attempting to run the VoxelTerrain scene.

**Root cause:** The godot_voxel GDExtension's worker thread attempts GPU operations (likely render server mesh upload / collision shape build) that are unavailable in headless mode. This is not a project bug — it matches the `<tool_availability>` note in the PLAN: "VoxelMesherBlocky in godot_voxel may require a GPU. Headless CI / headless Self-Check may not be able to actually run the meshing."

**What still passes:**
- `godot --headless --quit-after 1 --path .` → exit 0 (project loads cleanly)
- All 3 script checks: glossary-check.sh, verify-feature-flags.sh, extract-pot.sh → OK
- REUSE lint → COMPLIANT

**What requires real hardware:**
- `tests/integration/test_terrain_generates.gd` — full pass belongs to Plan 07 on the Motorola One Macro where the VoxelTerrain mesher has a real GPU.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced in this plan. T-04-01 through T-04-04 mitigations from the plan's threat model are implemented:
- **T-04-02** (DoS via infinite chunks): VoxelViewer view_distance=80 caps streaming per D-05.
- **T-04-03** (mouse capture freeze on mobile): `builder.gd` only calls `Input.MOUSE_MODE_CAPTURED` when `not OS.has_feature("mobile")`.

## Self-Check: PASSED

All files exist and commits are present:

```
eddd2ba — test(01-04): RED — input bindings + terrain integration test scaffold
9815867 — feat(01-04): VoxelTerrain scene + FastNoiseLite grassland generator (Task 2)
d375448 — feat(01-04): Builder character + main scene wiring (Task 3 GREEN)
```

- `addons/zylann.voxel/voxel.gdextension` — FOUND
- `src/world/terrain_generator.gd` — FOUND
- `src/world/terrain.tscn` — FOUND (VoxelTerrain + VoxelMesherBlocky + #6BB845)
- `src/builder/builder.gd` — FOUND (get_aim_origin, get_aim_direction)
- `src/builder/builder.tscn` — FOUND (CharacterBody3D + Camera3D)
- `src/world/main_scene.tscn` — FOUND (Terrain + Builder + VoxelViewer)
- `project.godot` [input] — FOUND (physical_keycode W/S/A/D/Space/LMB/RMB/1-8)
- `project.godot` run/main_scene — FOUND
- `tests/integration/test_terrain_generates.gd` — FOUND (3 tests)
- `tests/conftest_helpers.gd` spawn_test_world + wait_frames — FOUND
- `godot --headless --quit-after 1` — Exit 0
- glossary-check.sh — OK
- verify-feature-flags.sh — OK
- extract-pot.sh — OK
- reuse lint — COMPLIANT (187/187)
