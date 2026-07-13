---
phase: quick
plan: 260713-evx
type: execute
wave: 1
depends_on: []
files_modified:
  - src/world/main_scene.gd
  - tests/unit/test_spawn_on_land.gd
  - src/world/structure_placer.gd
  - tests/integration/test_structure_placement.gd
  - src/ui/title_scene.gd
  - tests/integration/test_title_scene_create_account.gd
autonomous: true
requirements: []

must_haves:
  truths:
    - "Starter chest and bed appear within a few metres of where the builder actually lands, even on seeds whose spawn column would otherwise be a MOUNTAIN-biome column"
    - "The submarine cave (underwater temple) only generates in the OCEAN biome, resting on the real submerged seabed, never standing exposed on dry land"
    - "The jungle temple sits flush on the ground surface with no floating gap"
    - "Clicking Create account on the title screen opens a visible sign-up panel"
  artifacts:
    - path: "src/world/main_scene.gd"
      provides: "search_land_spawn excludes MOUNTAIN biome columns (matches existing OCEAN exclusion)"
    - path: "src/world/structure_placer.gd"
      provides: "temple-specific anchor_y: seabed-aware for OCEAN-biome variants, ground-flush for land variants"
    - path: "src/ui/title_scene.gd"
      provides: "sign_in_panel overlay explicitly made visible on open"
    - path: "tests/integration/test_title_scene_create_account.gd"
      provides: "regression guard: pressing Create account leaves the panel visible"
  key_links:
    - from: "src/world/main_scene.gd search_land_spawn"
      to: "BiomeMap.Biome.MOUNTAIN"
      via: "biome exclusion check alongside the existing OCEAN check"
      pattern: "BiomeMap\\.Biome\\.MOUNTAIN"
    - from: "src/world/structure_placer.gd should_place_structure_at_cell"
      to: "_temple_anchor_y"
      via: "anchor_y assignment when structure_type == \"temple\""
      pattern: "_temple_anchor_y"
    - from: "src/ui/title_scene.gd _on_sign_in_pressed"
      to: "panel.visible"
      via: "explicit visible = true after instantiate"
      pattern: "panel\\.visible = true"
---

<objective>
Four real-device bug fixes: starter chest/bed not landing near the player's actual spawn
point, the underwater temple ("submarine cave") generating on dry land instead of submerged
in its OCEAN biome, the jungle temple floating one block above the ground, and the "Create
account" button on the title screen doing nothing when clicked.

Purpose: All four were found during real-device playtesting. Each has a concrete, narrow
root cause in already-shipped code (Phase 2/3/6 structure and spawn systems); none require
new systems, only correcting an existing formula or a missing property assignment.

Output:
  1. `search_land_spawn` (main_scene.gd) never chooses a MOUNTAIN-biome column as the world
     spawn, so the starter chest/bed (grounded via the mountain-lift-aware `_terrain_surface_at`)
     can no longer end up dozens of metres away from the builder (grounded via the
     mountain-lift-unaware spawn search).
  2. `structure_placer.gd` gets a temple-specific anchor helper that (a) uses the OCEAN seabed
     formula instead of the land formula when the picked template's biome is OCEAN, so the
     underwater temple sits truly submerged, and (b) accounts for temple templates authoring
     their floor at local cell Y=1 (not Y=0), fixing the 1-block float for both jungle and
     underwater temple variants.
  3. `title_scene.gd`'s `_on_sign_in_pressed` (used by both "Sign in" and "Create account")
     explicitly sets the instantiated `sign_in_panel.tscn`'s `visible = true`. The panel's own
     `.tscn` ships `visible = false` by contract ("call .visible = true" per its header comment),
     and the title screen never did.
</objective>

<execution_context>
@/Users/jnuyens/.claude/plugins/cache/gsd-plugin/gsd/4.0.4/workflows/execute-plan.md
@/Users/jnuyens/.claude/plugins/cache/gsd-plugin/gsd/4.0.4/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
</context>

<interfaces>
<!-- Key existing signatures the executor needs, extracted from the codebase. Use directly. -->

From src/world/biome_map.gd:
```gdscript
enum Biome {
    GRASSLAND_FOREST = 0, DESERT = 1, SNOW = 2, JUNGLE = 3,
    SAVANNAH = 4, OCEAN = 5, MOUNTAIN = 6,
}
func biome_at(x: float, z: float) -> Biome
```

From src/world/multipass_generator.gd (the real generator; mirror these exact constants,
do not invent new values):
```gdscript
const OCEAN_FLOOR_DEPTH: int = 9
const OCEAN_FLOOR_RELIEF: int = 4
# ocean branch: return sea_level - OCEAN_FLOOR_DEPTH + int(noise_val * OCEAN_FLOOR_RELIEF)
```

From src/world/main_scene.gd (existing precedent for the same OCEAN-aware pattern; do not
modify this function, it is the reference implementation to mirror in structure_placer.gd):
```gdscript
func _seabed_surface_at(x: float, z: float) -> float:
    if _biome_map == null or not _biome_map.has_method("biome_at"):
        return _terrain_surface_at(x, z)
    if int(_biome_map.biome_at(x, z)) != int(BiomeMap.Biome.OCEAN):
        return _terrain_surface_at(x, z)
    var noise_val: float = _surface_noise.get_noise_2d(float(floori(x)), float(floori(z)))
    var seabed_y: int = 12 - 9 + int(noise_val * 4.0)
    return float(seabed_y) + 1.0
```

From src/world/structure_placer.gd (the function being modified):
```gdscript
func should_place_structure_at_cell(structure_type: String, blueprint_cell_x: int,
                                    blueprint_cell_z: int) -> Dictionary
func _surface_y_at(x: int, z: int) -> int   # solid_top + 1, LAND formula only
var _biome_map: RefCounted = null
var _height_noise: FastNoiseLite = null
const SEA_LEVEL: float = 12.0
```

From src/ui/sign_in_panel.tscn header (the contract every caller must honour):
```
; Root: CanvasLayer (layer=10), not visible by default.
; Usage: instantiate this scene, add to the scene tree, then call .visible = true
;   when the player has not yet signed in.
```
</interfaces>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Exclude MOUNTAIN biome from world-spawn search (fixes starter chest/bed distance)</name>
  <files>src/world/main_scene.gd, tests/unit/test_spawn_on_land.gd</files>
  <behavior>
    - `search_land_spawn` never returns a candidate whose column is biome MOUNTAIN (mirrors the
      existing OCEAN exclusion).
    - Existing 4 tests in test_spawn_on_land.gd (never-below-sea-level, not-ocean, relocates-off-
      origin, matches-generator-formula) continue to pass unchanged. The fix only narrows which
      candidate wins; it does not change the height formula itself.
    - New test: for the same 11-seed spread already used in the file, the returned spawn column is
      never biome MOUNTAIN.
  </behavior>
  <action>
Root cause (grounded in code): `_find_world_spawn` / `search_land_spawn` (main_scene.gd, function
starts ~line 2717) picks the player's world-spawn column by searching outward from the origin and
excluding only OCEAN columns. Its height value ignores `_mountain_lift_at` entirely, by design:
`test_spawn_y_matches_generator_surface_formula` in tests/unit/test_spawn_on_land.gd pins the
plain `noise*8+sea_level+1` formula with NO lift term. But the REAL terrain surface used to ground
the starter chest/bed/sign (`_terrain_surface_at`, also ~line 3600) DOES add `_mountain_lift_at`
(up to +40..+130 voxels when the column's elevation noise crosses `BiomeMap.MOUNTAIN_ELEVATION_
THRESHOLD`, classifying it MOUNTAIN biome=6). If the deterministic search happens to land the
spawn column in a MOUNTAIN-biome cell, the builder is placed at `world_spawn.y` (no lift, often
buried inside/underneath the real, lifted terrain), while `spawn_starter_chest_and_bed` grounds the
chest 1m away and the bed 6m away using `_terrain_surface_at` (WITH lift, i.e. the real, much
higher mountain surface). The two props therefore land tens of metres away from, and often far
above, the buried player: exactly the "chest and bed not near spawn" symptom from the real-device
report.

Fix: in `search_land_spawn` (a static, pure function shared with tests/unit/test_spawn_on_land.gd;
do not change its signature or the height formula it returns), extend the existing biome-exclusion
check to also skip MOUNTAIN columns. Current code:

  for c: Vector2 in candidates:
      if biome_map != null and biome_map.has_method("biome_at") \
              and int(biome_map.biome_at(c.x, c.y)) == int(BiomeMap.Biome.OCEAN):
          continue

Change to:

  for c: Vector2 in candidates:
      if biome_map != null and biome_map.has_method("biome_at"):
          var candidate_biome: int = int(biome_map.biome_at(c.x, c.y))
          if candidate_biome == int(BiomeMap.Biome.OCEAN) or candidate_biome == int(BiomeMap.Biome.MOUNTAIN):
              continue

Do not touch the height-formula lines below this (the `sy`/`top` computation). Those remain the
plain land formula, which is now guaranteed correct because MOUNTAIN columns (the only case where
that formula diverges from `_terrain_surface_at`) can no longer be selected. Do not touch
`_terrain_surface_at`, `_mountain_lift_at`, or `spawn_starter_chest_and_bed`. They are already
correct and are the reference the spawn search must now agree with.

Then add a new test to tests/unit/test_spawn_on_land.gd, following the exact style of
`test_spawn_column_is_not_ocean` (same SEEDS array, same `_height_noise` helper already in the
file):

  ## The spawn column must not be MOUNTAIN either. A mountain column's REAL terrain height
  ## (used by _terrain_surface_at / spawn_starter_chest_and_bed to ground the starter chest, bed,
  ## and welcome sign) includes _mountain_lift_at, which this pure search does not replicate. If
  ## the search ever chose a mountain column, the chest/bed would be grounded at the true (much
  ## higher) mountain surface tens of metres away from the builder (placed without the lift):
  ## the real-device "chest and bed not near spawn" bug.
  func test_spawn_column_is_not_mountain() -> void:
      for seed_v: int in SEEDS:
          var bm := BiomeMap.new(seed_v)
          var spawn: Vector3 = MainScene.search_land_spawn(bm, _height_noise(seed_v), SEA_LEVEL)
          assert_ne(int(bm.biome_at(spawn.x, spawn.z)), int(BiomeMap.Biome.MOUNTAIN),
              "seed %d: spawn (%.0f,%.0f) is in a MOUNTAIN column, chest/bed would ground at the real (lifted) surface, far from the builder" % [seed_v, spawn.x, spawn.z])

Place the new test function anywhere after the existing four tests in the file.
  </action>
  <verify>
    <automated>godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/unit -gselect=test_spawn_on_land.gd -gexit</automated>
  </verify>
  <done>`search_land_spawn` skips both OCEAN and MOUNTAIN biome candidates. All 5 tests in test_spawn_on_land.gd pass (4 pre-existing + 1 new `test_spawn_column_is_not_mountain`), for every seed in the existing 11-seed SEEDS array.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Temple-specific anchor, seabed-aware for OCEAN variants, ground-flush for all variants</name>
  <files>src/world/structure_placer.gd, tests/integration/test_structure_placement.gd</files>
  <behavior>
    - For structure_type == "temple" where the biome at the anchor column is OCEAN, the computed
      world Y of the template's floor (local cell Y=1, confirmed the lowest authored cell in all 6
      temple .tres files) lands strictly below SEA_LEVEL (12): i.e. genuinely submerged, not "on
      land".
    - For structure_type == "temple" where the biome is NOT OCEAN (e.g. JUNGLE), the floor (local
      cell Y=1) lands exactly at the real ground surface (`_surface_y_at`'s solid_top+1), not one
      block above it.
    - village/shipwreck/dungeon anchor_y computation is completely unchanged (only the "temple"
      branch is touched).
  </behavior>
  <action>
Two independent root causes, both inside `should_place_structure_at_cell` (structure_placer.gd,
~line 240), both scoped to structure_type "temple":

ROOT CAUSE A (submarine cave on land, bug #2): `anchor_y` for every non-dungeon structure type
(including "temple") is computed by `_surface_y_at(anchor_x, anchor_z)`, the plain LAND height
formula (`int(noise*HEIGHT_AMPLITUDE + SEA_LEVEL) + 1`, ~line 490-497). This formula has no idea
about OCEAN seabed deepening. `underwater_temple_a/b/c.tres` (assets/templates/temples/,
allowed_biomes=Array[int]([5]) i.e. OCEAN) IS correctly restricted by the existing biome gate
(line 243-246: `if not template.allowed_biomes.has(biome): return {}`) to only spawn where
`biome_at(anchor_x, anchor_z) == OCEAN`. But because the LAND formula ignores the real ocean-floor
deepening that `multipass_generator.gd`'s ocean branch applies at that exact column (`sea_level -
OCEAN_FLOOR_DEPTH(9) + noise*OCEAN_FLOOR_RELIEF(4)`, i.e. Y roughly [-1..7], well below SEA_LEVEL
12), the computed anchor lands at the LAND-formula height (Y roughly [5..21]) instead, frequently
AT or ABOVE sea level. The temple then appears standing above/at the waterline on what reads as
exposed ground, instead of resting on the true, much lower seabed under the water column. This is
the reported "submarine cave spawned on land" bug: the biome gate is fine, the anchor HEIGHT is
wrong for the OCEAN case.

ROOT CAUSE B (jungle temple 1 block too high, bug #3): every temple template's LOWEST authored
brick is at local cell Y=1, not Y=0 (confirmed via `grep -oE "Vector3i\([0-9-]+, [0-9-]+,
[0-9-]+\)"` across all 6 files in assets/templates/temples/; jungle_temple_a/b/c and
underwater_temple_a/b/c all bottom out at Y=1; compare to village/dungeon templates, which bottom
out at Y=0). `stamp_template` places each brick at `world_cell = anchor + local_cell` with no
per-type offset. Since `anchor_y` is the generic "first air cell above ground" convention
(solid_top+1), a template whose floor is at local Y=1 (not Y=0) lands its floor ONE CELL ABOVE
where a Y=0-floored template like village/dungeon would: floating one block above the real ground.
This affects BOTH jungle_temple and underwater_temple variants identically (both bottom out at
Y=1), so a single fix in the "temple" anchor branch addresses both bug #2 and bug #3 together.

Fix: add named OCEAN-floor constants (mirroring multipass_generator.gd exactly) near the existing
HEIGHT_AMPLITUDE/SEA_LEVEL block (~line 96-98):

  const HEIGHT_AMPLITUDE: float = 8.0
  const SEA_LEVEL: float = 12.0
  const HEIGHT_NOISE_FREQUENCY: float = 0.01
  ## Mirrors multipass_generator.gd's OCEAN branch exactly. Used only by _temple_anchor_y so
  ## underwater temple variants anchor on the real submerged seabed, not the land formula.
  const OCEAN_FLOOR_DEPTH: int = 9
  const OCEAN_FLOOR_RELIEF: int = 4

Add a new private helper near `_surface_y_at` (~line 497, right after it):

  ## Temple-specific anchor Y. Every temple template (jungle_temple_*, underwater_temple_*)
  ## authors its lowest brick at LOCAL cell Y=1, not Y=0 (unlike village/dungeon, which start at
  ## Y=0), so the generic "_surface_y_at() = first air cell" convention floats the floor one
  ## block above the real ground/seabed. This helper returns (ground-or-seabed top) - 1 so local
  ## Y=1 lands exactly flush. Additionally: when the column's biome is OCEAN (true for all
  ## underwater_temple_* variants, whose allowed_biomes gate already restricts them there), this
  ## uses the OCEAN seabed formula (mirrors main_scene._seabed_surface_at) instead of the land
  ## formula, so the temple rests on the real, deepened seabed rather than standing exposed above
  ## the waterline ("on land").
  ## Pure function (T-07-01 style): deterministic, thread-safe (read-only noise + biome_map).
  func _temple_anchor_y(x: int, z: int) -> int:
      if _biome_map != null and _biome_map.has_method("biome_at") \
              and int(_biome_map.biome_at(float(x), float(z))) == int(BiomeMapScript.Biome.OCEAN):
          var noise_val: float = _height_noise.get_noise_2d(float(x), float(z))
          var seabed_solid_top: int = int(SEA_LEVEL) - OCEAN_FLOOR_DEPTH + int(noise_val * OCEAN_FLOOR_RELIEF)
          return seabed_solid_top  # local Y=1 floor lands at seabed_solid_top + 1, below SEA_LEVEL
      return _surface_y_at(x, z) - 1  # local Y=1 floor lands at solid_top + 1, flush with ground

Then change the anchor_y assignment (current line ~240):

  var anchor_y: int = DUNGEON_Y if structure_type == "dungeon" else _surface_y_at(anchor_x, anchor_z)

to:

  var anchor_y: int
  if structure_type == "dungeon":
      anchor_y = DUNGEON_Y
  elif structure_type == "temple":
      anchor_y = _temple_anchor_y(anchor_x, anchor_z)
  else:
      anchor_y = _surface_y_at(anchor_x, anchor_z)

Do NOT change the biome-restriction gate (lines 243-246). It already correctly restricts
underwater_temple_* to OCEAN and jungle_temple_* to JUNGLE; this task only fixes the HEIGHT
computed for the "temple" branch. Do NOT touch village/shipwreck/dungeon anchor computation.

Then add two new tests to tests/integration/test_structure_placement.gd, following the file's
existing `_make_placer(world_seed, biome_map)` helper pattern (a real `BiomeMap.new(seed)`, not
null, is required here since these tests need real biome classification):

  ## Bug #2 regression: underwater_temple variants (allowed_biomes=[OCEAN]) must anchor so their
  ## floor (local Y=1) sits BELOW sea level: i.e. genuinely submerged, never "on land".
  func test_underwater_temple_anchors_below_sea_level() -> void:
      const SEA_LEVEL: float = 12.0
      var found_one: bool = false
      for seed_v in range(1, 60):
          var bm := BiomeMap.new(seed_v)
          var placer: RefCounted = _make_placer(seed_v, bm)
          for bx in range(-3, 4):
              for bz in range(-3, 4):
                  var result: Dictionary = placer.should_place_structure_at_cell("temple", bx, bz)
                  if result.is_empty():
                      continue
                  var template: Resource = result.get("template")
                  if not ("underwater" in str(template.resource_path)):
                      continue
                  found_one = true
                  var anchor: Vector3i = result.get("anchor")
                  var floor_world_y: int = anchor.y + 1  # local cell Y=1 is the lowest authored brick
                  assert_true(floor_world_y < int(SEA_LEVEL),
                      "underwater temple floor at world Y=%d must be below sea level (%d), found standing on/above land" % [floor_world_y, int(SEA_LEVEL)])
      assert_true(found_one, "test setup: no underwater_temple placement found in the scanned seed/cell range, widen the scan")


  ## Bug #3 regression: temple floor (local Y=1) must land exactly flush with the real ground,
  ## not one block above it. Uses the same land-height formula the plan mirrors from
  ## structure_placer._surface_y_at (solid_top + 1), replicated locally per the project's existing
  ## test_spawn_on_land.gd pattern (build an identical FastNoiseLite rather than reaching into
  ## private members).
  func test_jungle_temple_floor_flush_with_ground() -> void:
      var found_one: bool = false
      for seed_v in range(1, 60):
          var bm := BiomeMap.new(seed_v)
          var placer: RefCounted = _make_placer(seed_v, bm)
          var noise := FastNoiseLite.new()
          noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
          noise.fractal_type = FastNoiseLite.FRACTAL_FBM
          noise.fractal_octaves = 4
          noise.fractal_lacunarity = 2.0
          noise.fractal_gain = 0.5
          noise.frequency = 0.01
          noise.seed = seed_v
          for bx in range(-3, 4):
              for bz in range(-3, 4):
                  var result: Dictionary = placer.should_place_structure_at_cell("temple", bx, bz)
                  if result.is_empty():
                      continue
                  var template: Resource = result.get("template")
                  if not ("jungle" in str(template.resource_path)):
                      continue
                  found_one = true
                  var anchor: Vector3i = result.get("anchor")
                  var floor_world_y: int = anchor.y + 1
                  var expected_ground_top: int = int(noise.get_noise_2d(float(anchor.x), float(anchor.z)) * 8.0 + 12.0) + 1
                  assert_eq(floor_world_y, expected_ground_top,
                      "jungle temple floor at world Y=%d must equal the real ground top (%d), found floating" % [floor_world_y, expected_ground_top])
      assert_true(found_one, "test setup: no jungle_temple placement found in the scanned seed/cell range, widen the scan")

Place both new test functions at the end of the file.
  </action>
  <verify>
    <automated>godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/integration -gselect=test_structure_placement.gd -gexit</automated>
  </verify>
  <done>`_temple_anchor_y` exists in structure_placer.gd and is used for structure_type=="temple" in `should_place_structure_at_cell`. All 4 tests in test_structure_placement.gd pass (2 pre-existing determinism/overlap tests + 2 new: underwater-temple-below-sea-level, jungle-temple-flush-with-ground).</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Fix "Create account" button, make the sign-in panel actually visible</name>
  <files>src/ui/title_scene.gd, tests/integration/test_title_scene_create_account.gd</files>
  <behavior>
    - Calling `_on_sign_in_pressed(true)` (Create account) results in `_open_overlay`'s child panel
      having `visible == true`.
    - Calling `_on_sign_in_pressed(false)` (Sign in), the same shared function, also results in
      `visible == true` (this was equally broken; both buttons route through the same code, so the
      one-line fix repairs both without any additional change).
  </behavior>
  <action>
Root cause (grounded in code): `sign_in_panel.tscn`'s root `CanvasLayer` ships with `visible =
false` (src/ui/sign_in_panel.tscn line 21) BY CONTRACT. The file's own header comment states:
"Usage: instantiate this scene, add to the scene tree, then call .visible = true when the player
has not yet signed in." `sign_in_panel.gd` itself never sets `visible = true` anywhere (only
`visible = false`, used to close the panel after completion/back; confirmed via grep, no bare
`visible = true` assignment exists in the whole file). The caller is therefore responsible for
making the panel visible after instantiating it.

`title_scene.gd`'s `_on_sign_in_pressed(create_account_mode: bool)` (~line 458), the single
handler wired to BOTH `_sign_in_button.pressed` (bind(false)) and `_create_account_button.pressed`
(bind(true)) at ~line 443-445, instantiates `sign_in_panel.tscn`, configures it
(`show_back_button`, `set_create_account_mode`), wires its signals, wraps it in a new
`CanvasLayer`, and adds that to the tree, but never sets `panel.visible = true`. The panel is
therefore correctly built and correctly added to the scene tree, but stays fully hidden. Pressing
"Create account" (or "Sign in") appears to do nothing.

Current code (~line 471-478):

  var panel: Node = panel_scene.instantiate()

  # Set back button and tab pre-selection via the properties added in this plan.
  if panel.has_method("set") and "show_back_button" in panel:
      panel.show_back_button = true
  if create_account_mode and panel.has_method("set_create_account_mode"):
      panel.set_create_account_mode(true)

Change to (add the new line immediately after `instantiate()`):

  var panel: Node = panel_scene.instantiate()
  # sign_in_panel.tscn ships `visible = false` by contract (see its own header comment). The
  # caller must explicitly show it. This line was missing, which made BOTH "Sign in" and
  # "Create account" appear to do nothing when clicked (T-evx-04 real-device report).
  panel.visible = true

  # Set back button and tab pre-selection via the properties added in this plan.
  if panel.has_method("set") and "show_back_button" in panel:
      panel.show_back_button = true
  if create_account_mode and panel.has_method("set_create_account_mode"):
      panel.set_create_account_mode(true)

Do NOT modify `_show_inline_sign_in_for_invite` (~line 590, the separate invite-deep-link overlay
path). It has the identical missing-visible pattern but is NOT part of this bug report's scope
(it's a different entry point, untested in the real-device session); flag it to the user as a
related follow-up rather than fixing it here. Do NOT modify sign_in_panel.gd or its .tscn. The
`visible = false` default is correct/intentional per its own contract; the fix belongs entirely at
the call site.

Then create a new headless GUT test, tests/integration/test_title_scene_create_account.gd:

  # SPDX-FileCopyrightText: 2026 Cubicraftia contributors
  # SPDX-License-Identifier: GPL-3.0-or-later
  #
  # test_title_scene_create_account.gd - Regression guard for the real-device "Create account
  # button does nothing" bug.
  #
  # Root cause: sign_in_panel.tscn ships `visible = false` by contract (its own header comment
  # requires the caller to set `.visible = true` after instantiating). title_scene.gd's
  # _on_sign_in_pressed() (shared by both the "Sign in" and "Create account" buttons) never did.
  # This test instantiates TitleScene, invokes _on_sign_in_pressed() directly (bypassing the
  # button-press animation/tween), and asserts the resulting overlay panel is actually visible.
  #
  # Headless note: TitleScene extends CanvasLayer and only constructs Control/Button/Label/
  # AudioStreamPlayer nodes in _build_ui() (no GPU-only resources), so it instantiates safely
  # under `godot --headless`. Autoloads (FriendsClient, DeepLinkHandler, OnboardingTelemetry) are
  # project-registered singletons, available in any run including headless GUT.
  #
  # Anchor: src/ui/title_scene.gd _on_sign_in_pressed(); src/ui/sign_in_panel.tscn header contract.

  extends GutTest

  const TitleSceneScript := preload("res://src/ui/title_scene.gd")

  func test_create_account_button_opens_visible_panel() -> void:
      var scene: CanvasLayer = TitleSceneScript.new()
      add_child_autofree(scene)
      await get_tree().process_frame  # let _ready() finish building the UI + tween setup

      scene.call("_on_sign_in_pressed", true)  # simulates the Create account button

      var overlay: Node = scene.get("_open_overlay")
      assert_not_null(overlay, "Create account press must create an overlay CanvasLayer")
      if overlay == null:
          return
      var panel: Node = overlay.get_child(0) if overlay.get_child_count() > 0 else null
      assert_not_null(panel, "overlay must contain the instantiated sign_in_panel")
      if panel != null:
          assert_true(panel.visible,
              "sign_in_panel must be visible after Create account is pressed; it ships visible=false by contract and the caller must show it")


  func test_sign_in_button_opens_visible_panel() -> void:
      # Same shared _on_sign_in_pressed() handler, create_account_mode=false: must be equally fixed.
      var scene: CanvasLayer = TitleSceneScript.new()
      add_child_autofree(scene)
      await get_tree().process_frame

      scene.call("_on_sign_in_pressed", false)

      var overlay: Node = scene.get("_open_overlay")
      assert_not_null(overlay, "Sign in press must create an overlay CanvasLayer")
      if overlay == null:
          return
      var panel: Node = overlay.get_child(0) if overlay.get_child_count() > 0 else null
      assert_not_null(panel, "overlay must contain the instantiated sign_in_panel")
      if panel != null:
          assert_true(panel.visible,
              "sign_in_panel must be visible after Sign in is pressed")

If `add_child_autofree` plus awaiting a process frame triggers unrelated autoload/telemetry errors
in your headless run (e.g. from `_check_ftue_marker_on_ready` or deep-link consumption touching
disk-backed `user://` state), that is pre-existing `_ready()` behaviour unrelated to this fix.
Do not suppress it by editing `_ready()`; only fall back to constructing the scene without
`add_child` (call `_build_ui()` directly instead of relying on `_ready()`) if `add_child_autofree`
proves genuinely unworkable headlessly, and note that fallback in the plan SUMMARY.
  </action>
  <verify>
    <automated>godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/integration -gselect=test_title_scene_create_account.gd -gexit</automated>
  </verify>
  <done>`_on_sign_in_pressed` sets `panel.visible = true` immediately after instantiating sign_in_panel.tscn. Both new tests (create-account, sign-in) pass headlessly. Manually pressing "Create account" on the title screen (F5 in the Godot editor) now visibly opens the sign-up panel; this in-viewport confirmation is display-gated and left for the user to spot-check.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| world_seed -> procedural placement | Spawn/structure formulas are pure functions of the (already-trusted) world seed; no new external input |
| Title-screen button -> sign_in_panel overlay | Local UI visibility fix only; no new network/auth surface (FriendsClient.sign_up() call path is unchanged) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation |
|-----------|----------|-----------|-------------|------------|
| T-evx-01 | Tampering | search_land_spawn biome exclusion | accept | Pure, deterministic, no user input; narrows candidate set, does not change trust boundary |
| T-evx-02 | Tampering | structure_placer temple anchor formula | accept | Pure function of world_seed + biome noise; mirrors an already-shipped formula (main_scene._seabed_surface_at) |
| T-evx-03 | Information Disclosure | title_scene panel visibility fix | accept | Making an existing, already-instantiated panel visible does not expose new data; sign-up flow itself (FriendsClient.sign_up) is unchanged by this plan |
| T-evx-SC | Tampering | npm/pip/cargo installs | accept | No new packages installed in this task set |
</threat_model>

<verification>
Automated (run after all three tasks land):
  godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/unit -gselect=test_spawn_on_land.gd -gexit
  godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/integration -gselect=test_structure_placement.gd -gexit
  godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/integration -gselect=test_title_scene_create_account.gd -gexit

Manual (in-viewport, display-gated, F5 in the Godot 4.6 editor):
1. **Chest/bed near spawn:** Create a fresh SURVIVAL world with a few different seeds (including
   one likely to land near a mountainous area; try several seeds and watch the console for
   `_find_world_spawn` behaviour). The builder should land standing on solid ground, with the
   starter chest ~1m to one side and the bed ~6m to the other, both clearly visible without
   needing to travel.
2. **Submarine cave / underwater temple:** Explore an ocean biome (may require sailing/swimming
   out from spawn) until an underwater temple generates. It should be visually submerged: glass
   dome walls surrounded by water on all sides, resting on the seabed, not standing on an exposed
   sandbar or dry beach.
3. **Jungle temple flush:** Find a jungle-biome temple (stepped stone/cobblestone pyramid). Its
   base should sit directly on the ground with no visible gap/floating block underneath.
4. **Create account button:** On the title screen, click "Create account". A sign-up panel must
   visibly appear (email/password/DOB fields, "Create account" tab pre-selected). Click "Sign in"
   separately to confirm it also still opens correctly (same shared code path).
</verification>

<success_criteria>
- `search_land_spawn` in src/world/main_scene.gd excludes both OCEAN and MOUNTAIN biome candidates
- `structure_placer.gd` has a `_temple_anchor_y` helper used for structure_type=="temple", leaving village/shipwreck/dungeon anchor logic untouched
- `title_scene.gd`'s `_on_sign_in_pressed` sets `panel.visible = true` after instantiating sign_in_panel.tscn
- All 3 new/extended automated GUT test files pass (test_spawn_on_land.gd, test_structure_placement.gd, test_title_scene_create_account.gd)
- No regressions: existing 4 tests in test_spawn_on_land.gd and existing 2 tests in test_structure_placement.gd continue to pass; village/shipwreck/dungeon structure placement is unchanged; sign-in (non-create-account) flow is unchanged apart from now also being visible
- No em-dashes/en-dashes introduced in any comment, string, or commit message; no "Lego"/"Minecraft" terminology introduced
</success_criteria>

<output>
Create `.planning/quick/260713-evx-chest-and-bed-near-spawn-submarine-cave-/260713-evx-SUMMARY.md` when done
</output>
