# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# main_scene.gd — Main scene controller (Plan 02-07: StructurePlacer wiring added).
# Plan 02-07 territory: _structure_placer creation and pre-stamp in _ready().
# Plan 02-08.5 must NOT modify the _structure_placer block (leave comment in place).
# Plan 03-10 additions:
#   - _HOSTILE_MOB_SCENES: preloaded scene dictionary for all 5 hostile creature types.
#   - spawn_hostile_mob(kind, position, params): instantiates a hostile mob + wires loot drop.
#   - _on_hostile_died(kind, death_pos): rolls creature_drops.tres loot; D-04 light-level gate.
#   - _on_spawning_should_spawn(kind, position): handler for Spawning.should_spawn signal.
#   - hostile_mob_active_cap: @export for adaptive-quality dispatch (Tier-3 may set to 6).
#   - Spawning.should_spawn wired in _ready() (after Plans 03-03's signal is defined).
#   References: 03-10-PLAN.md, DOCS.md §5.2, 03-CONTEXT.md D-04, 03-PATTERNS.md L988-993.
# Plan 02-13 additions:
#   - spawn_village_npc(template, world_anchor, slot_index): instantiates VillageNpc
#     per npc_spawns slot of a stamped village template (D-09 atmosphere-only NPCs).
#   - _pre_stamp_structures_near_spawn() now calls spawn_village_npc for each NPC slot
#     in every stamped village template.
#   References: DOCS.md §2 (Inhabitants), CONTEXT.md D-09, biomes/{desert,snow,savannah}.md §11.
# Plan 02-14 additions:
#   - _on_weather_state_changed(new_state): toggles RainParticles.emitting + RainVignette.visible
#     based on Weather.State.RAIN vs Weather.State.CLEAR.
#   - Weather.state_changed.connect(_on_weather_state_changed) wired in _ready().
#   - dynamite_particle_count: public int read by DynamiteHandler.light_fuse at fuse time;
#     adaptive-quality preset dispatcher (settings_menu.gd) sets this value.
#   References: 02-14-PLAN.md, 02-UI-SPEC.md §"Surface (rain overlay)", threat T-14-03.
#
# Extends Plan 04/05 main_scene.gd with:
#   - WorldClock subscription (phase_changed signal)
#   - per-frame day_progress uniform → sky_procedural.gdshader
#   - Sun + Moon rotation from WorldClock.current_day_progress()
#   - Sun light_energy adjusted per WorldClock phase (DAY=1.2, DAWN/DUSK=0.6, NIGHT=0.1)
#   - set_sky_mode() for adaptive-quality sky switch (procedural vs panorama_low)
#   - Lighting channel partition constants (Pitfall 9 mitigation)
#
# Lighting channel constants (Pitfall 9 — lantern channel partition):
#   CHANNEL_VISUAL_MASK  = 1  — sun, moon, placed lanterns, torches
#   CHANNEL_BUILDER_ONLY = 2  — handheld lantern attached to builder
# is_deep_dark() (in WorldClock) checks channel 1 only. The handheld lantern on
# channel 2 does NOT suppress hostile mob spawning in dungeons.
#
# References:
#   DOCS.md §2.3 — day/night cycle, deep-dark spawn gating
#   02-RESEARCH.md §"Pitfall 9" — lighting channel partition
#   02-RESEARCH.md §"Pitfall 11" — Tier-3 panorama-sky fallback
#   02-PATTERNS.md §"src/world/main_scene.tscn (EXTEND IN PLACE)"
#   assets/shaders/sky_procedural.gdshader — the shader this script drives

class_name MainScene
extends Node3D

# Preloads for Plan 02-07 types (headless GDScript type resolution requires explicit preloads).
const StructurePlacerScript := preload("res://src/world/structure_placer.gd")
const BrickTemplateScript := preload("res://src/bricks/brick_template.gd")
const BiomeMapScript := preload("res://src/world/biome_map.gd")

# Preloads for Plan 02-11 dropped-item pool types.
const BrickPalette := preload("res://src/bricks/palette.gd")

# Preload for Plan 03-04 death-pile entity.
const _DEATH_PILE_SCENE := preload("res://src/world/death_pile.tscn")

# ─── Plan 03-10: Hostile mob scenes + loot roller ────────────────────────────

## Preloaded scenes for all 5 hostile mob types. Keys match Spawning.should_spawn kinds.
## "bat_vampire" → same scene as "bat" (variant set via params).
## main_scene.spawn_hostile_mob() validates kind against this dictionary (T-03-10).
const _HOSTILE_MOB_SCENES: Dictionary = {
	"laser_penguin": preload("res://src/combat/laser_penguin.tscn"),
	"ghost":         preload("res://src/combat/ghost.tscn"),
	"vampire":       preload("res://src/combat/vampire.tscn"),
	"bat":           preload("res://src/combat/bat.tscn"),
	"bat_vampire":   preload("res://src/combat/bat.tscn"),  # variant; same scene
	"cube_slime":    preload("res://src/combat/cube_slime.tscn"),
	"wolf":          preload("res://src/combat/wolf.tscn"),
	# art-figures sheet 3 humanoid melee hostiles (Meshy).
	"zombie":        preload("res://src/combat/zombie.tscn"),
	"skeleton":      preload("res://src/combat/skeleton.tscn"),
	"goblin":        preload("res://src/combat/goblin.tscn"),
	"orc":           preload("res://src/combat/orc.tscn"),
}

## Per-chunk hostile mob cap. Written by the adaptive-quality dispatcher (Plan 03-11).
## At Tier-3 mobile quality, may be set even lower to stay within §7.2 frame budget.
## Passed to Spawning.set_hostile_mob_cap_override() at runtime.
## v1.1 QA: dropped 10→3 — the old 10 silently overrode Spawning's tuned-down default and
## made nights swarm. The global cap (Spawning.MAX_ACTIVE_HOSTILES_GLOBAL) is the real bound.
@export var hostile_mob_active_cap: int = 2

# Preload for Plan 03-08b chest entity.
# ChestEntity (StaticBody3D) — walk-up interact, lock/unlock, double-chest pairing.
const _CHEST_ENTITY_SCENE := preload("res://src/world/chest_entity.tscn")

# ─── Plan 03-11: BedEntity scene + starter-kit contents ──────────────────────

## BedEntity scene (Plan 03-11 — survival starter kit + walk-up sleep interact).
## Registered in group "bed_entity" for Builder._try_sleep_interact() + Spawning.register_bed.
const _BED_ENTITY_SCENE := preload("res://src/world/bed_entity.tscn")

## WelcomeSign script (decorative "Welcome to Cubicraftia" sign at the starter-kit spawn).
const _WelcomeSignScript := preload("res://src/world/welcome_sign.gd")

## D-15 verbatim starter chest contents — single source of truth.
## test_starter_chest_contents_match_D15_verbatim asserts exact equality against this constant.
## NOTE: def_id values must match brick_id in the corresponding .tres file in
## src/bricks/. CONTEXT D-15 spec'd "pickaxe_wooden / shovel_wooden /
## brick_plank_wooden" but the actual brick definitions in src/bricks/ use the
## shorter ids "pickaxe / shovel / wood_plank". Mismatches are silently
## rejected by Inventory and the chest appears nearly empty (UAT test 7).
const _STARTER_CHEST_CONTENTS: Array = [
	{"def_id": "pickaxe",             "count": 1},
	{"def_id": "shovel",              "count": 1},
	{"def_id": "lantern",             "count": 1},
	{"def_id": "wood_plank",          "count": 8},
	{"def_id": "food_cooked_generic", "count": 4},
]

# ─── Plan 03-11: StrawberrySpawner + chunk-load dispatch ─────────────────────

## StrawberrySpawner helper — static methods only; no instantiation needed.
const _StrawberrySpawnerScript := preload("res://src/world/strawberry_spawner.gd")

## Preloaded Strawberry scene for chunk-load spawning (Plan 03-09 entity).
const _STRAWBERRY_SCENE := preload("res://src/world/strawberry.tscn")

## Cache of chunks that have already been processed for strawberry spawning this session.
## Prevents double-spawn when the chunk-load signal fires multiple times for the same chunk.
var _processed_strawberry_chunks: Dictionary = {}

## CropSpawner helper (static) + per-chunk dedup cache for harvestable crops (wheat, sugar_cane).
const _CropSpawnerScript := preload("res://src/world/crop_spawner.gd")
const _CropScript := preload("res://src/world/crop.gd")
var _processed_crop_chunks: Dictionary = {}

## StructureSpawner helper (static) + per-chunk dedup for rare biome landmark buildings.
const _StructureSpawnerScript := preload("res://src/world/structure_spawner.gd")
const _WorldStructureScript := preload("res://src/world/world_structure.gd")
var _processed_structure_chunks: Dictionary = {}

## FoliageSpawner helper — static methods only; no instantiation needed.
const _FoliageSpawnerScript := preload("res://src/world/foliage_spawner.gd")

## Preloaded flower mesh for foliage decoration (decorative only, no physics).
const _FLOWER_MESH := preload("res://assets/meshes/flower.glb")

## Cache of chunks that have already been processed for foliage spawning this session.
## Prevents double-spawn when the chunk-load signal fires multiple times for the same chunk.
var _processed_foliage_chunks: Dictionary = {}

## OceanDecorSpawner helper — static methods only; scatters static coral/kelp/shell decor on
## the OCEAN seabed (art-ocean set), batched into per-kind MultiMesh draw calls per chunk.
const _OceanDecorSpawnerScript := preload("res://src/world/ocean_decor_spawner.gd")

## Cache of chunks already processed for ocean-floor decor this session (own dedup, like foliage).
var _processed_ocean_decor_chunks: Dictionary = {}

## Lazily-extracted decor meshes (kind → Mesh), pulled once from res://assets/meshes/decor/*.glb
## for MultiMesh batching. Keyed by kind; a null value caches a missing/failed extraction so we
## don't retry every chunk. Mirrors _flower_mesh_cache but multi-kind.
var _ocean_decor_mesh_cache: Dictionary = {}

## WildlifeSpawner helper — static methods only; no instantiation needed.
const _WildlifeSpawnerScript := preload("res://src/world/wildlife_spawner.gd")

## Wildlife script for dynamic instantiation (no .tscn; built purely in code).
const _WildlifeScript := preload("res://src/world/wildlife.gd")

## Cache of chunks already processed for wildlife spawning this session.
var _processed_wildlife_chunks: Dictionary = {}

## Active wildlife count — capped at _WILDLIFE_ACTIVE_CAP to keep performance sane.
var _wildlife_active_count: int = 0

## Hard cap on simultaneously active wildlife nodes. Lowered 60 → 22: the art pass replaced
## the light TripoSR meshes with heavier textured Meshy creatures (2048² maps, ~5-8k verts),
## so 60 live animals tanked the frame rate. 22 keeps the world lively within budget.
const _WILDLIFE_ACTIVE_CAP: int = 16

## Wildlife beyond this distance (m) from the builder are culled so the active-cap frees
## up as the player roams — otherwise animals pile up near spawn and the world reads empty
## elsewhere. Comfortably past the streaming/view radius so culls are never visible.
const _WILDLIFE_DESPAWN_DIST_M: float = 110.0

## Seconds between distance-cull passes (cheap; only walks the "wildlife" group).
const _WILDLIFE_CULL_INTERVAL_S: float = 2.0

## Time accumulator for the throttled wildlife cull.
var _wildlife_cull_accum: float = 0.0

## Cached noise for _terrain_surface_at — mirrors multipass_generator's height noise.
var _surface_noise: FastNoiseLite = null

## Per-chunk grass dedup + cached procedural grass-tuft mesh (built once, shared by all
## chunk MultiMeshes). Grass scatters on grass/jungle/savannah surfaces as cheap decor.
var _processed_grass_chunks: Dictionary = {}
var _grass_tuft_mesh: Mesh = null

## BiomeMap reference stored for use in chunk-load callbacks (set in _ready).
var _biome_map: RefCounted = null

## Active mini rain/snow cloud fx nodes (children of Builder) shown while it rains.
var _weather_clouds: Array = []

# Preloads for Plan 03-10 loot roller types (headless GDScript type resolution).
const _LootTableScript := preload("res://src/loot/loot_table.gd")
const _LootRollerScript := preload("res://src/loot/loot_roller.gd")

# Preload for Plan 02-13 VillageNpc scene (D-09 atmosphere-only inhabitants).
const VillageNpcScene := preload("res://src/world/village_npc.tscn")

# ─── Lighting channel constants (Pitfall 9 mitigation) ─────────────────────

## Renders sun, moon, placed lanterns, and torches.
## is_deep_dark() checks contributions from this channel to determine spawn eligibility.
const CHANNEL_VISUAL_MASK: int = 1

## Used for the handheld lantern attached to the builder only.
## is_deep_dark() ignores this channel — a builder holding a lantern does NOT
## suppress hostile mob spawning in dungeons.
const CHANNEL_BUILDER_ONLY: int = 2

# ─── Sun light-energy per WorldClock phase ───────────────────────────────────

const _SUN_ENERGY_DAY: float = 1.2
const _SUN_ENERGY_DAWN_DUSK: float = 0.6
const _SUN_ENERGY_NIGHT: float = 0.1

# ─── Node references ─────────────────────────────────────────────────────────

@onready var _ui: CanvasLayer = $UI
@onready var _sun: DirectionalLight3D = $Sun
@onready var _moon: DirectionalLight3D = $Moon
@onready var _world_env: WorldEnvironment = $WorldEnvironment

# ─── WATER overhaul: finite-volume discrete fluid sim ─────────────────────────
## FluidSim node (src/world/fluid_sim.gd). Created in _ready(), wired to the Terrain
## VoxelTerrain. The builder's mine path calls _fluid_sim.notify_block_mined(cell) so
## damming a block lets the water flow into the lower terrain (volume-conserved,
## animated). Null in headless/no-terrain contexts.
var _fluid_sim: FluidSim = null

## Cached "is the camera underwater" state so the underwater fog/tint is only
## re-applied on a transition, not every frame. Throttled sample (see _process).
var _camera_submerged: bool = false
var _water_fog_accum: float = 0.0
## How often (s) we sample whether the active camera is submerged. Cheap single
## voxel read; 0.2 s is responsive enough for an enter/exit fog swap.
const _WATER_FOG_SAMPLE_INTERVAL_S: float = 0.2
## Underwater fog distance (m) before the view goes murky (behaviour 4: ~30 m).
const _UNDERWATER_FOG_FAR_M: float = 30.0
## Underwater fog colour — a deep blue-green murk matching the water tint.
const _UNDERWATER_FOG_COLOR: Color = Color(0.10, 0.34, 0.46, 1.0)
## WATER voxel id (must match terrain.tscn / fluid_sim.gd / multipass_generator.gd).
const _WATER_VOXEL_ID: int = 7

## Cached sky ShaderMaterial reference (avoid repeated tree lookups in _process).
var _sky_shader_material: ShaderMaterial = null

## Ambient world music — swaps between day and night loops on WorldClock phase changes.
var _ambient_player: AudioStreamPlayer = null
var _ambient_is_night: bool = false
const _AMBIENT_DAY := "res://assets/audio/world_day.ogg"
const _AMBIENT_NIGHT := "res://assets/audio/world_night.ogg"

# ─── Plan 02-07: StructurePlacer (do not touch from Plan 02-08.5) ────────────

## StructurePlacer instance created at world-open. Stamp structures within
## ±256m of spawn at startup. Persisted stamp state lives in WorldSave (Phase 3).
var _structure_placer: RefCounted = null

## World seed for ALL deterministic generation — terrain noise, biomes, structure
## placement, and every per-chunk spawner. Loaded from WorldSave's world_meta in _ready()
## (see _apply_world_seed) and pushed into the VoxelTerrain generator so each world the
## player creates actually uses its chosen seed. Defaults to 1234 only as a headless/test
## fallback when no world is open. Was previously a hardcoded const, which made every
## created world generate identical terrain regardless of the chosen seed.
var _world_seed: int = 1234

# ─── Plan 02-14: adaptive-quality dynamite particle count ────────────────────

## DynamiteHandler reads this at light_fuse() time to size FlashParticles.amount.
## The §7.6 adaptive-quality preset dispatcher (_apply_live_settings in settings_menu.gd)
## writes this value to apply per-tier budgets (Tier-1: 120, Tier-2: 80, Tier-3: 30).
var dynamite_particle_count: int = 120

## Pre-stamp radius in metres (half-side of the square around spawn). Lowered 256 → 160:
## the structure pre-stamp placed 200k–400k bricks into ONE un-culled BrickRenderer
## MultiMesh, so facing the village rendered ~5–9M primitives in a frame (the worst FPS
## dips). 160 m keeps villages near spawn while cutting that brick count to ~40%.
const _PRE_STAMP_RADIUS_M: float = 160.0

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted once main_scene._ready() has finished its synchronous initialisation
## (StructurePlacer pre-stamp, NPC pre-stamp, autoload signal wiring,
## starter-kit spawn). Boot.gd listens and fades the splash overlay out so the
## player never sees a half-built world.
signal world_ready

# ─── Lifecycle ───────────────────────────────────────────────────────────────

## Loading-overlay state. We show a CanvasLayer on top of the 3D world from the
## first frame of _ready() until VoxelTerrain has streamed at least
## _CHUNKS_NEEDED_FOR_READY blocks (or until a hard timeout fires). Without
## this the player would see a few frames of empty sky + naked capsule while
## the first chunks bake.
const _CHUNKS_NEEDED_FOR_READY: int = 32
const _LOADING_TIMEOUT_MS: int = 25000
var _loaded_chunks_so_far: int = 0
var _loading_overlay: CanvasLayer = null
var _loading_bar: ProgressBar = null
var _loading_label: Label = null
var _loading_started_msec: int = 0
var _loading_done: bool = false
## Set true once the spawn-area structure pre-stamp finishes. The splash will NOT fade
## until this is true, so the player never sees the world mid-stamp (bricks popping in).
var _pre_stamp_done: bool = false


## Build the in-scene loading overlay (CanvasLayer on top of everything) — splash
## image + progress bar. Stays visible until the world has streamed enough
## chunks underneath the spawn that the player won't fall into the void.
func _build_loading_overlay() -> void:
	_loading_overlay = CanvasLayer.new()
	_loading_overlay.layer = 128  # above the UI CanvasLayer (layer = 10)
	add_child(_loading_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.078, 0.165, 0.310, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.add_child(bg)

	# Splash artwork — falls back gracefully through 3 paths
	# (Cubicraftia.png at repo root was a v1.0 placeholder; wordmark is the canonical asset).
	var splash := TextureRect.new()
	# Constrain the wordmark to a centred band (~44% width, upper-middle) rather than
	# stretching it to the full screen width — full-width made the wordmark huge.
	splash.anchor_left = 0.28
	splash.anchor_right = 0.72
	splash.anchor_top = 0.22
	splash.anchor_bottom = 0.48
	splash.offset_left = 0.0
	splash.offset_right = 0.0
	splash.offset_top = 0.0
	splash.offset_bottom = 0.0
	for sp: String in [
		"res://assets/textures/icons/cubicraftia_wordmark.png",
		"res://assets/textures/icons/title_bg.png",
		"res://Cubicraftia.png",
	]:
		if ResourceLoader.exists(sp):
			splash.texture = load(sp) as Texture2D
			break
	# IGNORE_SIZE + KEEP_ASPECT_CENTERED: scale the wordmark to fit inside the band,
	# preserving aspect and centring it — never larger than the band.
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	splash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(splash)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -120.0
	bottom.offset_bottom = -32.0
	bottom.add_theme_constant_override("separation", 12)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(bottom)

	_loading_label = Label.new()
	_loading_label.text = "Generating terrain…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_loading_label.add_theme_font_size_override("font_size", 20)
	bottom.add_child(_loading_label)

	var bar_center := CenterContainer.new()
	bottom.add_child(bar_center)
	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(520, 18)
	_loading_bar.max_value = float(_CHUNKS_NEEDED_FOR_READY)
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false
	bar_center.add_child(_loading_bar)

	_loading_started_msec = Time.get_ticks_msec()


## Called every time VoxelTerrain finishes streaming a block (chunk). Updates
## the bar and fades the overlay out once we've crossed the threshold.
func _on_loading_chunk_progress() -> void:
	if _loading_done:
		return
	_loaded_chunks_so_far += 1
	if _loading_bar != null:
		_loading_bar.value = min(float(_loaded_chunks_so_far), float(_CHUNKS_NEEDED_FOR_READY))
	# Hold the splash until enough chunks streamed, the pre-stamp finished, AND there is
	# actual collidable ground under the builder — otherwise the splash fades onto a builder
	# floating in the sky while terrain under spawn is still meshing.
	if _loaded_chunks_so_far >= _CHUNKS_NEEDED_FOR_READY and _pre_stamp_done and _builder_grounded():
		_finish_loading_overlay()


## True when a short downward ray from the builder hits terrain collision (layer 1) — i.e.
## the chunk under the spawn has meshed + baked collision and the builder can stand.
func _builder_grounded() -> bool:
	var b: Node3D = get_node_or_null("Builder") as Node3D
	if b == null:
		return true  # no builder (tests) — don't block the fade
	var space := b.get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(b.global_position + Vector3(0, 1, 0),
		b.global_position + Vector3(0, -6.0, 0))
	q.collision_mask = 1
	q.exclude = [b.get_rid()]
	return not space.intersect_ray(q).is_empty()


## Hard timeout — fade the overlay regardless of chunk count so a slow stream
## doesn't soft-lock the player at the splash.
func _on_loading_timeout() -> void:
	if Time.get_ticks_msec() - _loading_started_msec < _LOADING_TIMEOUT_MS:
		return
	_finish_loading_overlay()


func _finish_loading_overlay() -> void:
	if _loading_done or _loading_overlay == null:
		return
	_loading_done = true
	if _loading_bar != null:
		_loading_bar.value = float(_CHUNKS_NEEDED_FOR_READY)
	if _loading_label != null:
		_loading_label.text = "Welcome to Cubicraftia"
	var tween: Tween = create_tween()
	tween.tween_interval(0.25)
	# (Removed a no-op "transform:y" placeholder tween — CanvasLayer transform
	# is a Transform2D, so :y is a Vector2 not a float, throwing a type-mismatch
	# error at animation validation time. The fade-out below is the only effect.)
	tween.tween_method(func(a: float) -> void:
		if _loading_overlay != null:
			for c in _loading_overlay.get_children():
				if c is Control:
					(c as Control).modulate.a = a
	, 1.0, 0.0, 0.6)
	tween.tween_callback(func() -> void:
		if _loading_overlay != null:
			_loading_overlay.queue_free()
			_loading_overlay = null
	)


func _ready() -> void:
	# Plan 03-08b: Register in the "main_scene" group so StructurePlacer._stamp_chest_slot
	# can locate this node via SceneTree.get_first_node_in_group("main_scene").
	# Must be the first action in _ready() so the group is set before any structure stamps fire.
	add_to_group("main_scene")

	# Cap the frame rate at 30 for battery life + headroom for background work (chunk meshing,
	# threaded structure streaming). Engine.max_fps persists for the session once set.
	Engine.max_fps = 30

	# Build the loading overlay BEFORE any of the heavy _ready work below so it
	# covers the first rendered frame. Stays up until the VoxelTerrain has
	# streamed enough chunks around spawn that the player can land safely.
	_build_loading_overlay()
	# Hard timeout safety net — never leave the player stuck at the splash.
	get_tree().create_timer(_LOADING_TIMEOUT_MS / 1000.0).timeout.connect(_on_loading_timeout)

	# CRITICAL: bake the VoxelBlockyLibrary or VoxelMesherBlocky produces 0 meshes.
	# terrain.tscn instantiates the library declaratively but never calls bake() on
	# it. Without an explicit bake the library's internal model index is empty, so
	# the mesher reports updated_blocks=0 every tick (confirmed via a diag run:
	# `updated_blocks: 0` even though pass-0 generation ran 183 times). That's
	# what caused the "no visible terrain" bug — voxel data populates fine, the
	# meshing stage just produces nothing to render.
	var terrain_node: Node = get_node_or_null("Terrain")
	if terrain_node != null and terrain_node.has_method("get_mesher"):
		var mesher: Resource = terrain_node.get_mesher()
		if mesher != null and "library" in mesher:
			var library: Resource = mesher.library
			# Fix(07): atlas-based texturing for VoxelBlockyModelCube.
			# All cube models share ONE StandardMaterial3D whose albedo_texture is a
			# packed atlas (1280×1024, 5 cols × 4 rows of 256×256 tiles).
			# Per-face UV is selected via atlas_size_in_tiles + set_tile().
			#
			# Atlas tile layout (col, row):
			#   (0,0) grass_top      (1,0) grass_face    (2,0) sand_top
			#   (3,0) sand_face      (4,0) snow_top
			#   (0,1) snow_face      (1,1) stone_top     (2,1) stone_face
			#   (3,1) sandstone_top  (4,1) sandstone_face
			#   (0,2) ice_top        (1,2) ice_face       (2,2) water_top
			#   (3,2) water_face     (4,2) wood_log_top
			#   (0,3) wood_log_face  (1,3) dirt_top       (2,3) dirt_face
			#   (3,3) leaves_top    (4,3) leaves_face
			#
			# VoxelBlockyModel.Side enum (confirmed from VoxelBlockyModel.xml):
			#   SIDE_POSITIVE_X=0, SIDE_NEGATIVE_X=1, SIDE_NEGATIVE_Y=2,
			#   SIDE_POSITIVE_Y=3 (TOP), SIDE_NEGATIVE_Z=4, SIDE_POSITIVE_Z=5
			#
			# Voxel IDs: 0=air, 1=grass, 2=sand, 3=snow, 4=stone, 5=sandstone,
			#   6=ice, 7=water, 8=jungle_grass, 9=savannah_grass, 10=wood_log, 11=dirt,
			#   12=leaves
			if library != null and library.has_method("get_model"):
				const _ATLAS_PATH := "res://assets/textures/voxel_blocks/voxel_atlas.png"
				# Atlas dimensions in tiles (5 cols × 4 rows).
				const _ATLAS_SIZE := Vector2i(5, 4)
				# VoxelBlockyModel.Side constants (value-confirmed from XML).
				const _SIDE_POSITIVE_X: int = 0
				const _SIDE_NEGATIVE_X: int = 1
				const _SIDE_NEGATIVE_Y: int = 2
				const _SIDE_POSITIVE_Y: int = 3  # TOP face
				const _SIDE_NEGATIVE_Z: int = 4
				const _SIDE_POSITIVE_Z: int = 5

				# Per voxel_id: [top_tile: Vector2i, side_tile: Vector2i]
				# Tiles are (col, row) into the 5×4 atlas.
				# IDs 8 and 9 reuse grass / sand tiles (biome tint via model color).
				const _VOXEL_TILES: Dictionary = {
					1:  [Vector2i(0, 0), Vector2i(1, 0)],  # grass
					2:  [Vector2i(2, 0), Vector2i(3, 0)],  # sand
					3:  [Vector2i(4, 0), Vector2i(0, 1)],  # snow
					4:  [Vector2i(1, 1), Vector2i(2, 1)],  # stone
					5:  [Vector2i(3, 1), Vector2i(4, 1)],  # sandstone
					6:  [Vector2i(0, 2), Vector2i(1, 2)],  # ice
					7:  [Vector2i(2, 2), Vector2i(3, 2)],  # water
					8:  [Vector2i(0, 0), Vector2i(1, 0)],  # jungle_grass  -> reuse grass
					9:  [Vector2i(2, 0), Vector2i(3, 0)],  # savannah_grass -> reuse sand
					10: [Vector2i(4, 2), Vector2i(0, 3)],  # wood_log
					11: [Vector2i(1, 3), Vector2i(2, 3)],  # dirt
					12: [Vector2i(3, 3), Vector2i(4, 3)],  # leaves
				}

				if not ResourceLoader.exists(_ATLAS_PATH):
					push_warning("main_scene: voxel atlas missing: '%s'" % _ATLAS_PATH)
				else:
					var atlas_tex: Texture2D = load(_ATLAS_PATH) as Texture2D
					if atlas_tex == null:
						push_warning("main_scene: failed to load voxel atlas '%s'" % _ATLAS_PATH)
					else:
						# Single shared material — VoxelMesherBlocky batches all cube
						# geometry into one surface per material, so one shared mat is
						# both correct and optimal. We use the brick-stud ShaderMaterial so
						# every UP-FACING block surface shows 2×2 cylinder studs (the brick
						# look) — pure per-fragment shading, no extra geometry (mobile-safe).
						# The shader samples the atlas (nearest filter) and multiplies the
						# mesher's baked-AO vertex COLOR, matching the old material's
						# vertex_color_use_as_albedo behaviour.
						var shared_mat := ShaderMaterial.new()
						var stud_shader: Shader = load("res://assets/shaders/brick_terrain.gdshader") as Shader
						if stud_shader != null:
							shared_mat.shader = stud_shader
							shared_mat.set_shader_parameter("atlas", atlas_tex)
						else:
							push_warning("main_scene: brick_terrain.gdshader missing — terrain will be untextured.")

						for voxel_id: int in _VOXEL_TILES.keys():
							var tiles: Array = _VOXEL_TILES[voxel_id] as Array
							var top_tile: Vector2i = tiles[0] as Vector2i
							var side_tile: Vector2i = tiles[1] as Vector2i

							var model: Resource = library.get_model(voxel_id)
							if model == null:
								push_warning("main_scene: no model at voxel_id %d" % voxel_id)
								continue

							if not model.has_method("set_tile"):
								push_warning("main_scene: model at id %d has no set_tile — not a VoxelBlockyModelCube?" % voxel_id)
								continue

							# Apply atlas size and material.
							model.atlas_size_in_tiles = _ATLAS_SIZE
							model.set_material_override(0, shared_mat)
							# Neutralise the flat per-block colour to white so the atlas texture
							# shows true colours; the mesher's AO (baked in vertex colour) still
							# modulates because shared_mat.vertex_color_use_as_albedo is true.
							if "color" in model:
								model.color = Color(1, 1, 1, 1)

							# TOP face (POSITIVE_Y=3) and BOTTOM face (NEGATIVE_Y=2) use top tile.
							model.set_tile(_SIDE_POSITIVE_Y, top_tile)
							model.set_tile(_SIDE_NEGATIVE_Y, top_tile)

							# Four side faces use the side (face) tile.
							model.set_tile(_SIDE_POSITIVE_X, side_tile)
							model.set_tile(_SIDE_NEGATIVE_X, side_tile)
							model.set_tile(_SIDE_POSITIVE_Z, side_tile)
							model.set_tile(_SIDE_NEGATIVE_Z, side_tile)

			if library != null and library.has_method("bake"):
				library.bake()

	# Phase 6: dev auto-open removed. World must be opened by world_select_screen
	# before main_scene is loaded. If no world is open at this point, warn and return
	# early to avoid undefined behaviour in survival HUD, hostile spawns, etc.
	if not WorldSave.is_open():
		push_warning("main_scene: WorldSave not open — world_select_screen should have opened it first")
		return

	# Load THIS world's seed and push it into the terrain generator BEFORE any chunk
	# streams. Without this every world generated with the baked-in seed 1234 and looked
	# identical no matter what the player chose. Runs here (still frame 0, before the first
	# _process where VoxelTerrain begins generating) so all chunks use the correct seed.
	_apply_world_seed()

	# Wire ThermalProbe signal for adaptive quality toast (DOCS.md §7.6 plumbing).
	if ThermalProbe.has_signal("thermal_throttled"):
		ThermalProbe.thermal_throttled.connect(_on_thermal_throttled)

	# Cache the sky ShaderMaterial from the WorldEnvironment.
	# If the material is not a ShaderMaterial (e.g. panorama fallback already set),
	# _sky_shader_material stays null and the shader update in _process is skipped.
	if _world_env != null and _world_env.environment != null:
		var sky: Sky = _world_env.environment.sky
		if sky != null and sky.sky_material is ShaderMaterial:
			_sky_shader_material = sky.sky_material as ShaderMaterial

	# Subscribe to WorldClock phase changes.
	WorldClock.phase_changed.connect(_on_phase_changed)

	# Ambient world music — day/night loops driven by WorldClock phase.
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.name = "AmbientMusic"
	_ambient_player.volume_db = -14.0
	add_child(_ambient_player)
	_set_ambient_music(WorldClock.is_night())

	# Decorative floating islands / sky cities in the distance (splash-art backdrop).
	var sky_decor := SkyDecor.new()
	sky_decor.name = "SkyDecor"
	add_child(sky_decor)

	# Brick sun + brick moon arcing across the sky with the day/night cycle.
	var celestial := CelestialBodies.new()
	celestial.name = "CelestialBodies"
	add_child(celestial)

	# Plan 02-14: Subscribe to Weather state changes to toggle rain VFX.
	# Safe double-connect guard: connect() on an already-connected signal in Godot 4
	# is a no-op with the default CONNECT_ONE_SHOT off; no guard needed here.
	Weather.state_changed.connect(_on_weather_state_changed)
	# Apply initial weather state in case RAIN is already active when the scene loads.
	_on_weather_state_changed(Weather.state)

	# ─── Plan 03-04: Wire death-pile spawning ────────────────────────────────
	# Inventory autoload emits death_pile_spawned when a DEATH_DROP event drains
	# all builder slots. main_scene listens and instantiates the DeathPile entity.
	if Inventory.has_signal("death_pile_spawned"):
		Inventory.death_pile_spawned.connect(_on_death_pile_spawned)

	# ─── Plan 03-10: Wire Spawning.should_spawn → spawn_hostile_mob ──────────
	# Spawning autoload emits should_spawn(kind, position) when a hostile spawn
	# is eligible. main_scene instantiates the actual mob (Plan 03-10 wiring).
	# Per 03-CONTEXT.md D-01: only wired in survival mode (Spawning gates in-process).
	if Spawning.has_signal("should_spawn") and \
			not Spawning.should_spawn.is_connected(_on_spawning_should_spawn):
		Spawning.should_spawn.connect(_on_spawning_should_spawn)
	# Apply the hostile mob cap to Spawning autoload (adaptive-quality hook).
	if Spawning.has_method("set_hostile_mob_cap_override"):
		Spawning.set_hostile_mob_cap_override(hostile_mob_active_cap)

	# ─── Plan 02-07: StructurePlacer pre-stamp (do not modify from 02-08.5) ──
	# Create the BiomeMap with the same seed as terrain_generator uses.
	var biome_map: RefCounted = BiomeMapScript.new(_world_seed)
	_biome_map = biome_map  # Store for chunk-load strawberry dispatch (Plan 03-11).
	_structure_placer = StructurePlacerScript.new(_world_seed, biome_map)
	# Pre-stamp structures within ±256m of spawn. Idempotent: StudGrid.place()
	# returns false for already-occupied cells; duplicates are silently dropped.
	# Phase 3 will track stamped anchors in WorldSave to skip on world reload.
	_pre_stamp_structures_near_spawn()
	# Scattered structures are handled by the proximity streamer in _process (threaded loads
	# ahead of the player, freed when far) — not by a chunk-load dispatch or an upfront warm.

	# Start the clock at midday so the player spawns into bright daylight rather
	# than the orange dawn sky (sky_procedural.gdshader's dawn_tint dominates the
	# screen at day_progress=0.0, making the whole world look orange and hiding
	# the terrain-sky horizon).
	# 0.35 * SECONDS_PER_DAY ≈ midday in the DAY phase [0.05, 0.65).
	# WorldSave integration (loading elapsed_seconds from save) is Plan 02-11.
	if not WorldClock._running:
		WorldClock.start(WorldClock.SECONDS_PER_DAY * 0.35)

	# ─── Land-safe spawn (BOTH modes) ────────────────────────────────────────
	# Always (re)write world_spawn so we recover from earlier dev builds that wrote a
	# bad value (a stub once returned 64.0 → respawn 50 m up → instant death loop), AND
	# so we never strand the builder over open ocean. World origin (0,0) is ocean for
	# many seeds; with water now non-collidable that left the builder underwater /
	# floating with no ground ("terrain gone"). _find_world_spawn searches outward for
	# solid land above the waterline. Done in BOTH modes so sandbox players land safely.
	var _world_spawn: Vector3 = _find_world_spawn(biome_map)
	WorldSave.set_world_meta("world_spawn", var_to_bytes(_world_spawn))
	# Move the builder to the computed spawn directly so the first frame doesn't drop
	# 30 m from the .tscn-baked Vector3(0, 32, 0). The spawn grace gate in builder.gd
	# holds them in place until terrain collision bakes underneath.
	var builder: Node3D = get_node_or_null("Builder") as Node3D
	if builder != null:
		builder.global_position = _world_spawn + Vector3(0.0, 0.5, 0.0)

	# ─── Plan 03-11: Survival starter kit (D-15 + DOCS §5.6) ─────────────────
	# In survival worlds, spawn a starter chest + bed near the spawn every session. We
	# do NOT gate on the starter_kit_spawned meta any more because ChestEntity /
	# BedEntity are runtime nodes that don't persist across sessions yet (Phase 3 ships
	# the data layer but the actual chunk-save integration is Phase 4). Without
	# re-spawning each session the starter kit disappears the first time the player quits
	# and reopens the world. Sandbox worlds do NOT get the starter kit (D-01).
	if Features.is_survival_mode():
		# Spawn the starter kit every session (see note above on persistence).
		spawn_starter_chest_and_bed(_world_spawn)
		# Force HP bar visibility — hp_bar._ready() runs before main_scene._ready
		# in Godot's child-first init order, so it checked is_survival_mode()
		# BEFORE WorldSave was open and set visible=false permanently. Re-show
		# now that survival mode is actually active.
		var hp_bar: CanvasItem = $UI.get_node_or_null("HpBar") as CanvasItem
		if hp_bar != null:
			hp_bar.visible = true
		if WorldSave.get_world_meta("session_id") == null:
			# Prefer NetworkManager.get_session_id() if a multiplayer session is active
			# (A3 cleanup — Plan 04-09). Fall back to timestamp token for solo play.
			var _session_token: String = ""
			if is_instance_valid(NetworkManager) and not NetworkManager.get_session_id().is_empty():
				_session_token = NetworkManager.get_session_id()
			else:
				_session_token = str(int(Time.get_unix_time_from_system()))
			WorldSave.set_world_meta("session_id", var_to_bytes(_session_token))

	# ─── Plan 03-11: Tier-3 adaptive hostile cap (03-PATTERNS.md L1046) ──────
	# If the device is Tier-3 (Motorola-class), reduce the per-chunk hostile cap to 6
	# so the §7.2 mobile frame budget is respected. Reverts to MAX_HOSTILES_PER_CHUNK_DEFAULT
	# on Tier-1/Tier-2 hardware (ThermalProbe.is_tier_3() returns false on those devices).
	if ThermalProbe != null and ThermalProbe.has_method("is_tier_3") and ThermalProbe.is_tier_3():
		Spawning.set_hostile_mob_cap_override(6)
		hostile_mob_active_cap = 6

	# ─── Plan 03-11: StrawberrySpawner chunk-load signal wiring ──────────────
	# Attempt to connect to the VoxelTerrain block_loaded signal (godot_voxel 1.6x).
	# If neither a VoxelTerrain nor a multipass_generator chunk_loaded signal exists,
	# the periodic scan fallback in _process covers new chunks every 5 s.
	var _voxel_terrain: Node = get_node_or_null("VoxelTerrain")
	if _voxel_terrain != null and _voxel_terrain.has_signal("block_loaded"):
		if not _voxel_terrain.block_loaded.is_connected(_on_voxel_block_loaded):
			_voxel_terrain.block_loaded.connect(_on_voxel_block_loaded)
		# Also advance the loading-overlay bar each time a block is streamed.
		_voxel_terrain.block_loaded.connect(_on_loading_chunk_progress.unbind(1))
	# VoxelTerrain in this project is actually instantiated under the "Terrain"
	# node name (from terrain.tscn root). Hook block_loaded there too if the
	# VoxelTerrain alias above is missing.
	var _terrain_alias: Node = get_node_or_null("Terrain")
	if _terrain_alias != null and _terrain_alias.has_signal("block_loaded"):
		# The VoxelTerrain node is named "Terrain" (terrain.tscn root), NOT
		# "VoxelTerrain", so the spawn-handler connection above never matched and
		# per-chunk content (strawberries/foliage/wildlife) never spawned. Wire the
		# spawn dispatch here, where the real terrain node lives.
		if not _terrain_alias.block_loaded.is_connected(_on_voxel_block_loaded):
			_terrain_alias.block_loaded.connect(_on_voxel_block_loaded)
		if not _terrain_alias.block_loaded.is_connected(_on_loading_chunk_progress.unbind(1)):
			_terrain_alias.block_loaded.connect(_on_loading_chunk_progress.unbind(1))
	var _mpgen: Node = get_node_or_null("MultipassGenerator")
	if _mpgen != null and _mpgen.has_signal("chunk_loaded"):
		if not _mpgen.chunk_loaded.is_connected(_on_chunk_loaded):
			_mpgen.chunk_loaded.connect(_on_chunk_loaded)

	# ─── WATER overhaul: create the finite-volume fluid sim ───────────────────
	# One FluidSim beside the terrain. The builder's mine path notifies it when a
	# damming block is removed, and it floods the lower terrain over several ticks
	# (volume-conserving). Wired to the "Terrain" VoxelTerrain (where the real node
	# lives — see the block_loaded note above).
	_fluid_sim = FluidSim.new()
	_fluid_sim.name = "FluidSim"
	add_child(_fluid_sim)
	var _fluid_terrain: Node = _terrain_alias if _terrain_alias != null else get_node_or_null("Terrain")
	_fluid_sim.set_terrain(_fluid_terrain)

	# ─── Plan 05-09: EULA re-acknowledge gate ────────────────────────────────
	# If the user is already signed in, check immediately. Otherwise, connect to
	# FriendsClient.signed_in so the check fires after every sign-in.
	var _fc: Node = get_node_or_null("/root/FriendsClient")
	if _fc != null:
		if _fc.has_signal("signed_in"):
			_fc.signed_in.connect(_check_eula_on_sign_in)
		# Also check now in case FriendsClient already emitted signed_in before
		# this scene was ready (token restore path in FriendsClient._ready()).
		if _fc.has_method("is_signed_in") and _fc.is_signed_in():
			_check_eula_on_sign_in("")

	# Boot scene listens to this signal to fade its splash overlay out once the
	# world has finished its synchronous init. Deferred by one frame so the
	# engine has time to render the first 3D frame before the fade begins.
	call_deferred("emit_signal", "world_ready")

	# Plan 06-06: wire up the FTUE overlay for first-time survival worlds.
	# _maybe_start_ftue() is deferred one frame after world_ready so the FTUE
	# overlay instantiates AFTER the world_ready signal has been emitted and
	# the first 3D frame has been rendered (signal connect → _maybe_start_ftue
	# pattern avoids a race where signal wiring outruns the first chunk stream).
	world_ready.connect(_maybe_start_ftue, CONNECT_ONE_SHOT)

	# Plan 06-08: telemetry world_loaded — fires when world_ready fires.
	world_ready.connect(_on_world_ready_telemetry, CONNECT_ONE_SHOT)

	# Plan 06-08: pending_ftue_complete check for invite joiners (T-06-T2).
	# If title_scene wrote pending_ftue_complete=true before this scene loaded,
	# pre-set ftue_complete on the world meta so FTUE overlay never triggers.
	_apply_pending_ftue_complete_if_set()

	# Milestone v1.0 cross-phase wiring (integration check B1+B2):
	# 1. Mount restricted-account amber banner into the HUD CanvasLayer so under-13
	#    accounts awaiting parental confirmation see Surface F from anywhere in-world.
	# 2. Connect NetworkManager.join_blocked → ParentalGatePanel.show_join_blocked_modal
	#    so under-13 unconsented session joins get user-visible feedback (not silent fail).
	_install_parental_gate_wiring()


func _process(delta: float) -> void:
	# Distance-cull roaming wildlife so the active-cap frees as the player explores.
	# Runs regardless of the clock so animals keep cycling even while time is paused.
	# Structure proximity streaming runs every frame (it self-throttles its heavy scan).
	_stream_structures(delta)

	_wildlife_cull_accum += delta
	if _wildlife_cull_accum >= _WILDLIFE_CULL_INTERVAL_S:
		_wildlife_cull_accum = 0.0
		_cull_distant_wildlife()

	# ─── WATER overhaul (behaviour 4): underwater fog/tint ────────────────────
	# Sample whether the active camera is submerged (throttled). On a transition
	# we toggle a murky underwater fog on the WorldEnvironment so visibility is
	# limited to ~30 m, restored above water. Runs regardless of the clock so the
	# fog is correct even while time is paused.
	_water_fog_accum += delta
	if _water_fog_accum >= _WATER_FOG_SAMPLE_INTERVAL_S:
		_water_fog_accum = 0.0
		_update_underwater_fog()

	if not WorldClock._running:
		return

	var day_progress: float = WorldClock.current_day_progress()

	# Update sky shader uniform.
	if _sky_shader_material != null:
		_sky_shader_material.set_shader_parameter("day_progress", day_progress)

	# Rotate Sun: -PI/2 at dawn (0.0) → 0 at noon (0.5 within day) → PI/2 at dusk.
	# day_progress 0.0 = dawn, 0.35 = midday (centre of 0.05..0.65 day band), 0.70 = night start.
	# Linear mapping of day_progress to Sun rotation X in [-PI/2, PI/2].
	if _sun != null:
		_sun.rotation.x = lerp(-PI / 2.0, PI / 2.0, day_progress)

	# Moon counter-rotates (always opposite the Sun).
	if _moon != null:
		_moon.rotation.x = _sun.rotation.x + PI


# ─── Plan 05-09: EULA re-acknowledge gate ────────────────────────────────────

## Check whether the bundled EULA has been acknowledged by the signed-in user.
## Called from _ready() (if already signed in) and connected to FriendsClient.signed_in.
## If the hash has changed, shows EulaAcknowledgeModal before any other UI.
func _check_eula_on_sign_in(_user_id: String = "") -> void:
	var fc: Node = get_node_or_null("/root/FriendsClient")
	if fc == null or not fc.has_method("check_eula_acknowledgement"):
		return
	if fc.check_eula_acknowledgement():
		# Hash matches stored hash — user has already accepted this version.
		return
	# Hash mismatch or no stored hash — show the re-acknowledge modal.
	var modal_scene: PackedScene = load("res://src/ui/eula_acknowledge_modal.tscn")
	if modal_scene == null:
		push_warning("main_scene._check_eula_on_sign_in: could not load eula_acknowledge_modal.tscn")
		return
	var modal: Node = modal_scene.instantiate()
	get_tree().root.add_child(modal)
	if modal.has_method("show_modal"):
		modal.show_modal()


# ─── Plan 06-06: FTUE overlay ───────────────────────────────────────────────

## Instantiate and attach the FTUE overlay if this is a first-time survival world.
##
## Conditions (all must be true):
##   - Features.is_survival_mode() → true
##   - WorldSave.get_world_meta("ftue_complete") == null (never completed)
##
## The overlay wires all its signal connections internally in its own _ready().
## main_scene only instantiates it; ftue_overlay handles step detection and cleanup.
##
## Connected via world_ready.connect(..., CONNECT_ONE_SHOT) in _ready().
func _maybe_start_ftue() -> void:
	if not Features.is_survival_mode():
		return
	if WorldSave.get_world_meta("ftue_complete") != null:
		return
	var ftue_scene: PackedScene = load("res://src/ui/ftue_overlay.tscn")
	if ftue_scene == null:
		push_warning("main_scene._maybe_start_ftue: could not load ftue_overlay.tscn — FTUE skipped.")
		return
	var ftue: Node = ftue_scene.instantiate()
	add_child(ftue)


# ─── Plan 06-08: Telemetry + invite-joiner ftue helpers ──────────────────────

## Called ONE_SHOT on world_ready: log world_loaded telemetry event.
func _on_world_ready_telemetry() -> void:
	if is_instance_valid(OnboardingTelemetry):
		OnboardingTelemetry.log(OnboardingTelemetry.WORLD_LOADED)


## Called from _ready() to check user://ftue.cfg for pending_ftue_complete=true.
## If set, pre-sets ftue_complete on the world meta so the FTUE overlay never
## triggers for invite joiners. Clears the flag after applying.
##
## T-06-T2 mitigation: this is only applied after main_scene loads, which only
## happens after the invite-join flow has initiated the session join. The world
## belongs to the host who accepted the invite.
func _apply_pending_ftue_complete_if_set() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://ftue.cfg") != OK:
		return
	var pending: bool = cfg.get_value("state", "pending_ftue_complete", false)
	if not pending:
		return
	# Pre-set ftue_complete in world meta before _maybe_start_ftue() runs.
	if is_instance_valid(WorldSave) and WorldSave.has_method("set_world_meta"):
		WorldSave.set_world_meta("ftue_complete", var_to_bytes(true))
	# Clear the pending flag to avoid re-applying on subsequent loads.
	cfg.set_value("state", "pending_ftue_complete", false)
	cfg.save("user://ftue.cfg")


## Mount the restricted-account banner into the HUD CanvasLayer and wire
## NetworkManager.join_blocked into ParentalGatePanel.show_join_blocked_modal.
## Closes integration-checker BLOCKERs B1 (signal had zero subscribers) and
## B2 (install_banner was never called).
func _install_parental_gate_wiring() -> void:
	const _PANEL_SCENE_PATH := "res://src/ui/parental_gate_panel.tscn"
	if not ResourceLoader.exists(_PANEL_SCENE_PATH):
		return
	var scn: PackedScene = load(_PANEL_SCENE_PATH) as PackedScene
	if scn == null:
		return
	var panel: Node = scn.instantiate()
	if panel == null:
		return
	# Add to scene tree first so @onready vars resolve before banner install.
	add_child(panel)
	# B2: mount banner into UI CanvasLayer so it's visible in-world.
	if panel.has_method("install_banner") and is_instance_valid(_ui):
		panel.call("install_banner", _ui)
	# B1: connect join_blocked → show_join_blocked_modal.
	var nm: Node = get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_signal("join_blocked") and panel.has_method("show_join_blocked_modal"):
		if not nm.join_blocked.is_connected(panel.show_join_blocked_modal):
			nm.join_blocked.connect(panel.show_join_blocked_modal)


## _notification handler: log app_resumed telemetry when the app returns from
## background (NOTIFICATION_APPLICATION_RESUMED — iOS/Android app lifecycle).
## This is a supplementary event beyond the 15 locked Phase 6 events; it uses
## a plain string key because it is not in the locked onboarding_telemetry constants.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		if is_instance_valid(OnboardingTelemetry):
			OnboardingTelemetry.log("app_resumed")

# ─── WorldClock signal handlers ──────────────────────────────────────────────

## Called when WorldClock transitions between Phase.DAWN / DAY / DUSK / NIGHT.
func _on_phase_changed(new_phase: WorldClock.Phase, _day_progress: float) -> void:
	# Swap ambient music regardless of sun state.
	_set_ambient_music(new_phase == WorldClock.Phase.NIGHT)

	if _sun == null:
		return
	match new_phase:
		WorldClock.Phase.DAY:
			_sun.light_energy = _SUN_ENERGY_DAY
		WorldClock.Phase.DAWN, WorldClock.Phase.DUSK:
			_sun.light_energy = _SUN_ENERGY_DAWN_DUSK
		WorldClock.Phase.NIGHT:
			_sun.light_energy = _SUN_ENERGY_NIGHT


## Swap ambient world music between the day and night loops.
## No-op if already playing the requested track (DAWN/DAY/DUSK share the day loop).
func _set_ambient_music(want_night: bool) -> void:
	if _ambient_player == null:
		return
	if _ambient_player.playing and want_night == _ambient_is_night:
		return
	_ambient_is_night = want_night
	var path: String = _AMBIENT_NIGHT if want_night else _AMBIENT_DAY
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	# Loop the track (OGG import may default loop off).
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_ambient_player.stream = stream
	_ambient_player.play()


# ─── Plan 02-14: Weather VFX handler ────────────────────────────────────────

## Called when Weather.state_changed fires (and once at scene load to sync initial state).
##
## Toggles:
##   - Builder/Camera3D/RainParticles: GPUParticles3D emitting on/off.
##   - UI/RainVignette: ColorRect visible on/off.
##     Vignette = #1B2C56 at 0.08α (UI-SPEC.md "Surface (rain overlay)").
##     mouse_filter=IGNORE (T-14-04) set in main_scene.tscn — Control tree unimpeded.
##
## @param new_state  The new Weather.State value (CLEAR or RAIN).
func _on_weather_state_changed(new_state: int) -> void:
	var rain_active: bool = (new_state == Weather.State.RAIN)

	# Toggle GPUParticles3D (RainParticles child of Builder/Camera3D).
	var rain_particles: GPUParticles3D = get_node_or_null("Builder/Camera3D/RainParticles")
	if rain_particles == null:
		# Also try ChaseCamera path for CHASE mode (Phase 2 uses FPV Camera3D as primary).
		rain_particles = get_node_or_null("Builder/CameraPivot/SpringArm3D/ChaseCamera/RainParticles")
	if rain_particles != null:
		rain_particles.emitting = rain_active

	# Toggle RainVignette ColorRect.
	var vignette: ColorRect = get_node_or_null("UI/RainVignette")
	if vignette != null:
		vignette.visible = rain_active

	# Mini rain/snow clouds (art-movements fx) that drift with the builder while it rains.
	_update_weather_clouds(rain_active)


## Spawn or remove the sky clouds that appear during rain. Uses the snow-cloud variant when the
## builder is in the SNOW biome, the rain-cloud otherwise. The clouds are parented to the WORLD
## (this scene root) at a high sky altitude so they read as real clouds rather than player-locked
## props — they hover over the play area but do NOT track the builder 1:1. Freed when sky clears.
const _WEATHER_CLOUD_ALTITUDE: float = 70.0
func _update_weather_clouds(rain_active: bool) -> void:
	if not rain_active:
		for c: Node in _weather_clouds:
			if is_instance_valid(c):
				c.queue_free()
		_weather_clouds.clear()
		return
	if not _weather_clouds.is_empty():
		return  # already showing
	var builder: Node3D = get_node_or_null("Builder") as Node3D
	if builder == null:
		return
	var fx_name: String = "rain_cloud"
	if _biome_map != null and _biome_map.has_method("biome_at"):
		if int(_biome_map.biome_at(builder.global_position.x, builder.global_position.z)) == int(BiomeMap.Biome.SNOW):
			fx_name = "snow_cloud"
	# Three large clouds spread across the sky high above the play area, persisting (lifetime 0)
	# and slowly spinning; parented to the world root (self) so they stay fixed in world space as
	# the builder moves. The XZ centre is anchored to the builder's spawn-time position but the
	# clouds do NOT follow him afterward (they're in world space, not under Builder).
	var base: Vector3 = Vector3(builder.global_position.x, _WEATHER_CLOUD_ALTITUDE, builder.global_position.z)
	var offsets: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(28.0, 6.0, -18.0), Vector3(-24.0, 3.0, 22.0)]
	for off: Vector3 in offsets:
		var cloud: Node3D = EffectsLibrary.spawn(self, fx_name,
			base + off, {"size": 14.0, "lifetime": 0.0, "fade": false, "spin": 0.05, "ground": false})
		if cloud != null:
			_weather_clouds.append(cloud)


# ─── Input handling ──────────────────────────────────────────────────────────

## Tab is intercepted here in _input — NOT _unhandled_key_input — because Godot's
## built-in ui_focus_next action is also bound to Tab and the Control focus
## chain would consume the event before reaching _unhandled_key_input. We also
## proactively release GUI focus on every toggle so that no settings-menu or
## hotbar Control retains focus and tries to absorb the next Tab.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed:
		return
	# Match the raw Tab key directly (physical_keycode 4194306 = KEY_TAB) rather
	# than only is_action_pressed("ui_release_mouse"), because the built-in
	# ui_focus_next action also matches Tab and may consume the event before
	# our custom action fires reliably when no Control has focus.
	if event.physical_keycode != KEY_TAB:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Clear any GUI focus so subsequent Tabs don't traverse Controls instead of
	# re-firing this handler. Also mark input as handled so the focus chain
	# doesn't run for this event.
	get_viewport().gui_release_focus()
	get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	# Esc TOGGLES the Settings menu: open if closed, close if already open.
	if event.physical_keycode == KEY_ESCAPE:
		if is_instance_valid(_open_settings_node):
			_open_settings_node.queue_free()  # tree_exited restores mouse mode
		else:
			_open_settings()
		get_viewport().set_input_as_handled()
		return

	# B TOGGLES the brick palette. On desktop nothing else opened it (the
	# ui_brick_palette_toggle action had no handler), so the player could never
	# equip a brick to place — this is the desktop palette opener.
	if event.physical_keycode == KEY_B:
		_toggle_brick_palette()
		get_viewport().set_input_as_handled()
		return


## The currently-open Settings menu instance, or null/invalid when closed. Tracked so
## Esc can toggle it shut instead of stacking a second copy on top.
var _open_settings_node: Node = null

## Lazily-instantiated desktop brick-palette sidebar (B key toggles it).
var _brick_palette_node: CanvasItem = null


## Desktop brick-palette toggle (B key). Lazily instantiates the sidebar palette into
## the UI layer, then shows/hides it. Releases the mouse so tiles can be clicked, and
## recaptures it when the palette closes (matching the settings-menu pattern).
func _toggle_brick_palette() -> void:
	if not is_instance_valid(_brick_palette_node):
		var palette_scene: PackedScene = load("res://src/ui/brick_palette_sidebar.tscn")
		if palette_scene == null:
			return
		_brick_palette_node = palette_scene.instantiate() as CanvasItem
		if _brick_palette_node == null:
			return
		_ui.add_child(_brick_palette_node)
		_brick_palette_node.visible = false

	var opening: bool = not _brick_palette_node.visible
	if opening and _brick_palette_node.has_method("open"):
		_brick_palette_node.call("open")
	elif not opening and _brick_palette_node.has_method("close"):
		_brick_palette_node.call("close")
	else:
		_brick_palette_node.visible = opening

	# Free the cursor while the palette is open so the player can click tiles;
	# recapture for gameplay when it closes.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED


# ─── Bed sleep cutscene ──────────────────────────────────────────────────────

## True while the sleep fade cutscene is playing (guards against re-entry).
var _sleeping_cutscene: bool = false
## Full-screen black fade overlay (lazily created).
var _sleep_overlay: ColorRect = null


## Play the bed sleep cutscene: the builder lies down, the screen fades to black, the
## clock skips to morning while every night creature is despawned, then it fades back
## into the day and the builder stands up. Triggered by Builder._try_sleep_interact.
func sleep_in_bed(builder: Node, bed_pos: Vector3) -> void:
	if _sleeping_cutscene:
		return
	_sleeping_cutscene = true
	_ensure_sleep_overlay()
	if builder != null and builder.has_method("start_sleep_pose"):
		builder.call("start_sleep_pose", bed_pos)
	# Fade to black.
	await _tween_sleep_overlay(1.0, 1.0)
	# Hidden by the black: jump to morning + clear all night creatures. HP is restored
	# by WorldClock.sleep_lapse_ended → Builder._on_sleep_lapse_ended.
	WorldClock.skip_to_morning()
	Spawning.despawn_all_hostiles()
	# Hold on black.
	await get_tree().create_timer(1.0).timeout
	# Fade back into the day.
	await _tween_sleep_overlay(0.0, 1.0)
	if builder != null and builder.has_method("end_sleep_pose"):
		builder.call("end_sleep_pose")
	_sleeping_cutscene = false


## Lazily build the black fade overlay on a CanvasLayer above the HUD (below the loading
## overlay). Starts fully transparent.
func _ensure_sleep_overlay() -> void:
	if is_instance_valid(_sleep_overlay):
		return
	var layer := CanvasLayer.new()
	layer.name = "SleepFadeLayer"
	layer.layer = 64
	add_child(layer)
	_sleep_overlay = ColorRect.new()
	_sleep_overlay.name = "SleepFade"
	_sleep_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	_sleep_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sleep_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)  # transparent until faded in
	layer.add_child(_sleep_overlay)


## Tween the fade overlay's alpha to `target_a` over `dur` seconds; await completion.
func _tween_sleep_overlay(target_a: float, dur: float) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(_sleep_overlay, "modulate:a", target_a, dur)
	await tw.finished


func _open_settings() -> void:
	# Guard against double-open (e.g. Esc + an in-menu button both firing).
	if is_instance_valid(_open_settings_node):
		return
	var settings_scene: PackedScene = load("res://src/ui/settings_menu.tscn")
	if settings_scene == null:
		return
	var settings: Node = settings_scene.instantiate()
	_ui.add_child(settings)
	_open_settings_node = settings
	# Release mouse capture so the user can click menu buttons. Restored on
	# settings close via the tree_exited signal.
	var previous_mouse_mode: int = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings.tree_exited.connect(func() -> void:
		_open_settings_node = null
		Input.mouse_mode = previous_mouse_mode
	)


# ─── Adaptive-quality sky mode switch ────────────────────────────────────────

## Switch the sky rendering mode.
##
## "procedural" (default): ShaderMaterial bound to sky_procedural.gdshader.
##   Tier-1/Tier-2 hardware. Per-frame day_progress update in _process().
##
## "panorama_low": PanoramaSkyMaterial for Tier-3 (Motorola-class) hardware.
##   Uses assets/textures/sky/sky_day_panorama.jpg (2048×1024 equirectangular).
##   If the file is absent at runtime, the assignment goes through (no crash);
##   the sky renders as solid colour.
##
## Called by the §7.6 adaptive-quality hook in settings_menu.gd (Plan 14).
# ─── WATER overhaul (behaviour 4): underwater fog ────────────────────────────

## Sample whether the active camera is submerged in a WATER voxel and toggle a
## murky underwater fog on the WorldEnvironment accordingly.
##
## When submerged: enable depth fog (light = deep blue-green, far = ~30 m) so the
## view goes murky past the visibility limit — behaviour 4. When the camera surfaces
## the fog is disabled and the environment reverts to its above-water state.
##
## Only re-applies on a transition (tracked by _camera_submerged) so we don't thrash
## the Environment every sample. Cheap: one VoxelTool.get_voxel read per sample tick.
func _update_underwater_fog() -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var submerged: bool = _voxel_is_water_at(cam.global_position)
	if submerged == _camera_submerged:
		return  # no transition — nothing to do
	_camera_submerged = submerged
	var env: Environment = _world_env.environment
	if submerged:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = _UNDERWATER_FOG_COLOR
		env.fog_light_energy = 1.0
		# Aerial-perspective fog: dense near the far plane so 30 m reads as the murk wall.
		env.fog_depth_begin = 1.0
		env.fog_depth_end = _UNDERWATER_FOG_FAR_M
		env.fog_depth_curve = 1.0
		env.fog_density = 1.0
		# Don't let the bright sky bleed through underwater.
		env.fog_sky_affect = 0.0
	else:
		# Restore the above-water default: the scene ships with fog disabled.
		env.fog_enabled = false


## True if the WATER voxel id occupies the cell containing world position `pos`.
## Uses the Terrain VoxelTool (the authoritative voxel grid, which the fluid sim
## also writes to). Returns false if no terrain/tool is available.
func _voxel_is_water_at(pos: Vector3) -> bool:
	var terrain: Node = get_node_or_null("Terrain")
	if terrain == null or not terrain.has_method("get_voxel_tool"):
		return false
	var tool: Object = terrain.get_voxel_tool()
	if tool == null:
		return false
	if "channel" in tool:
		tool.channel = 0  # VoxelBuffer.CHANNEL_TYPE
	var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
	return tool.get_voxel(cell) == _WATER_VOXEL_ID


func set_sky_mode(mode: String) -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var env: Environment = _world_env.environment
	if env.sky == null:
		env.sky = Sky.new()

	if mode == "procedural":
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://assets/shaders/sky_procedural.gdshader")
		env.sky.sky_material = mat
		_sky_shader_material = mat  # update cache so _process writes to the new material
	elif mode == "panorama_low":
		var panorama_mat := PanoramaSkyMaterial.new()
		var tex_path := "res://assets/textures/sky/sky_day_panorama.jpg"
		if FileAccess.file_exists(tex_path):
			panorama_mat.panorama = load(tex_path)
		env.sky.sky_material = panorama_mat
		_sky_shader_material = null  # no shader to update in _process
		if not FileAccess.file_exists(tex_path):
			print_debug("sky_mode: panorama_low not yet authored")


# ─── Lighting utility ─────────────────────────────────────────────────────────

## Estimate the visual-channel (Channel 1) world light level at a given position.
##
## Sums contributions from all DirectionalLight3D and OmniLight3D nodes in the
## SceneTree that have light_cull_mask & CHANNEL_VISUAL_MASK > 0.
##
## This is the function used by tests/unit/test_lighting_channels.gd to verify
## that handheld lanterns (Channel 2) do NOT contribute to spawn-suppression light.
##
## Returns a normalised light estimate in [0.0, ∞). Values > 0.1 are "lit"
## (not deep-dark) per WorldClock.is_deep_dark().
##
## Note: This is a simplified approximation for v1. A full radiosity solution
## is out of scope for Phase 2.
func world_light_at(pos: Vector3) -> float:
	var total: float = 0.0
	var tree := get_tree()
	if tree == null:
		return 0.0

	# Sum all DirectionalLight3D in visual channel (e.g. Sun + Moon).
	for node in tree.get_nodes_in_group(""):
		pass  # traversal via get_nodes_in_group("") is empty — use root scan below

	# Walk the scene tree from root to collect lights.
	var root := tree.get_root()
	if root != null:
		total += _sum_lights_recursive(root, pos)

	return total


## Recursively walk scene tree to sum visible-channel light contributions.
func _sum_lights_recursive(node: Node, pos: Vector3) -> float:
	var sum: float = 0.0

	if node is DirectionalLight3D:
		var dl: DirectionalLight3D = node as DirectionalLight3D
		if dl.light_cull_mask & CHANNEL_VISUAL_MASK:
			sum += dl.light_energy

	elif node is OmniLight3D:
		var ol: OmniLight3D = node as OmniLight3D
		if ol.light_cull_mask & CHANNEL_VISUAL_MASK:
			# Distance-based attenuation approximation.
			var dist: float = ol.global_position.distance_to(pos)
			if dist < ol.omni_range:
				var atten: float = 1.0 - (dist / ol.omni_range)
				sum += ol.light_energy * atten

	for child in node.get_children():
		sum += _sum_lights_recursive(child, pos)

	return sum


# ─── Thermal signal handler ──────────────────────────────────────────────────

func _on_thermal_throttled() -> void:
	Toasts.show("ui.toast.graphics_adjusted", "info")


# ─── Plan 02-11: DroppedItem settled-MultiMesh pool ─────────────────────────

## Sparse pool of settled dropped-item MultiMeshInstance3D nodes.
## Key = "def_id::colour" (String), value = MultiMeshInstance3D.
## One MMI per (def_id, colour_index) pair, allocated lazily.
##
## Per RESEARCH.md §"Pitfall 7" and 02-11-PLAN.md Task 1:
##   - Active RigidBody3D dropped items are capped at 30 concurrent.
##   - Items beyond the cap are spawned directly into the settled pool.
##   - After ~1.5 s the physics item calls transition_to_settled_pool().
##
## References:
##   DOCS.md §3.3 — "broken brick drops as glowing floating item"
##   DOCS.md §4.3 — dropped-item glow (OmniLight3D on the settled pool MMI)
##   02-RESEARCH.md §"Pitfall 7" — two-phase RigidBody → MultiMesh
##   02-UI-SPEC.md §"Dynamite VFX sequence" step 6
var _settled_dropped_pools: Dictionary = {}  # Dictionary[String, MultiMeshInstance3D]

## Preloaded DroppedItem scene for physics-active spawning.
const _DROPPED_ITEM_SCENE := preload("res://src/world/dropped_item.tscn")

## Maximum concurrent active RigidBody3D dropped items (Pitfall 7 cap).
const _MAX_ACTIVE_DROPPED_ITEMS: int = 30


## Count the number of currently active RigidBody3D dropped-item children.
func _active_dropped_items_count() -> int:
	var n: int = 0
	for c in get_children():
		if c is DroppedItem:
			n += 1
	return n


## Return (or lazily create) the MultiMeshInstance3D for the given (def_id, colour_index) pair.
##
## The MMI holds all settled dropped items of this type so they render in one draw call.
## The mesh defaults to a small BoxMesh placeholder (Phase 2 art pass deferred).
## Per Pitfall 9 mitigation: settled dropped items glow via an OmniLight3D attached
## to the MMI, with light_cull_mask = CHANNEL_VISUAL_MASK (1).
func get_settled_pool(def_id: String, colour_index: int) -> MultiMeshInstance3D:
	var key: String = "%s::%d" % [def_id, colour_index]
	if _settled_dropped_pools.has(key):
		return _settled_dropped_pools[key] as MultiMeshInstance3D

	# Lazily create a new MultiMeshInstance3D for this (def_id, colour) pair.
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 0
	mm.use_colors = true
	# Placeholder mesh: small box; runtime art pass replaces with the brick's actual mesh.
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.4, 0.4, 0.4)
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.name = "DroppedPool_" + key.replace("::", "_").replace("-", "").left(32)
	add_child(mmi)
	_settled_dropped_pools[key] = mmi
	return mmi


## Transition a physics-active DroppedItem into the settled MultiMesh pool.
##
## Called by DroppedItem._settle() after ~1.5 s of physics.
## Records the item's world position into the appropriate MultiMesh instance,
## then queue_frees the RigidBody3D node.
func transition_to_settled_pool(item: DroppedItem) -> void:
	var mmi: MultiMeshInstance3D = get_settled_pool(item.def_id, item.colour_index)
	var idx: int = mmi.multimesh.instance_count
	mmi.multimesh.instance_count = idx + 1
	mmi.multimesh.set_instance_transform(idx, Transform3D(Basis(), item.global_position))
	# Tint with the palette colour if assigned; otherwise use white (natural colour).
	if item.colour_index >= 0 and item.colour_index < BrickPalette.COLOURS.size():
		mmi.multimesh.set_instance_color(idx, BrickPalette.COLOURS[item.colour_index])
	else:
		mmi.multimesh.set_instance_color(idx, Color.WHITE)
	item.queue_free()


## Spawn a dropped item at world_pos.
##
## Two-phase dispatch (RESEARCH.md Pitfall 7 mitigation):
##   - If active_physics == true AND active count < _MAX_ACTIVE_DROPPED_ITEMS:
##       Instantiate dropped_item.tscn as a RigidBody3D child (physics-active).
##   - Otherwise: spawn directly into the settled MultiMesh pool (skips physics).
##
## @param def_id         BrickRegistry def_id ("wood_plank", "stone", etc.).
## @param colour_index   Palette colour index (-1 = natural colour).
## @param world_pos      World-space position for the item.
## @param active_physics Whether to attempt a physics-active spawn first.
func spawn_dropped_item(def_id: String, colour_index: int, world_pos: Vector3,
		active_physics: bool) -> void:
	# Validate def_id against BrickRegistry; warn and skip if unknown (T-11-04).
	if def_id == "" or def_id == null:
		return
	var brick_def: BrickDefinition = BrickRegistry.get_definition(def_id)
	if brick_def == null:
		push_warning("spawn_dropped_item: unknown def_id '%s'; dropping nothing." % def_id)
		return

	if active_physics and _active_dropped_items_count() < _MAX_ACTIVE_DROPPED_ITEMS:
		# Physics-active spawn.
		var item: DroppedItem = _DROPPED_ITEM_SCENE.instantiate() as DroppedItem
		item.def_id = def_id
		item.colour_index = colour_index
		item.global_position = world_pos
		item.set_main_scene(self)
		add_child(item)
	else:
		# Settle directly into the MultiMesh pool — no physics bounce.
		var mmi: MultiMeshInstance3D = get_settled_pool(def_id, colour_index)
		var idx: int = mmi.multimesh.instance_count
		mmi.multimesh.instance_count = idx + 1
		mmi.multimesh.set_instance_transform(idx, Transform3D(Basis(), world_pos))
		if colour_index >= 0 and colour_index < BrickPalette.COLOURS.size():
			mmi.multimesh.set_instance_color(idx, BrickPalette.COLOURS[colour_index])
		else:
			mmi.multimesh.set_instance_color(idx, Color.WHITE)


# ─── Plan 03-04: DeathPile spawning ──────────────────────────────────────────

## Instantiate a DeathPile entity at world_pos and populate it with the builder's
## dropped inventory contents. Called by _on_death_pile_spawned (Inventory signal).
##
## @param builder_id  UUID of the builder whose death spawned the pile.
## @param position    World-space position for the pile (Builder._compute_death_pile_position).
## @param contents    Array[Dictionary] of {def_id, count} — the dropped inventory slots.
## @return            The instantiated DeathPile node.
func spawn_death_pile(builder_id: String, position: Vector3, contents: Array) -> Node:
	var pile: Node = _DEATH_PILE_SCENE.instantiate()
	add_child(pile)
	if pile.has_method("set_contents"):
		pile.set_contents(contents, builder_id, position)
	if pile.has_method("set_main_scene"):
		pile.set_main_scene(self)
	return pile


## Signal handler for Inventory.death_pile_spawned.
## Instantiates the DeathPile entity when the Inventory autoload fires the signal.
func _on_death_pile_spawned(builder_id: String, position: Vector3, contents: Array) -> void:
	spawn_death_pile(builder_id, position, contents)


# ─── Plan 03-08b: ChestEntity spawning ───────────────────────────────────────

## Instantiate a ChestEntity at world_pos with pre-rolled loot contents.
##
## Called by StructurePlacer._stamp_chest_slot after rolling loot tables
## deterministically. Also callable directly for debug or test spawning.
##
## Locked status: locked = (tier != "regular") per CONTEXT.md D-04.
## bronze+ tiers spawn locked (require their respective key to open).
##
## @param tier      Chest tier: "regular"|"bronze"|"silver"|"gold"|"diamond".
## @param position  World-space position for the chest StaticBody3D.
## @param contents  Array[Dictionary] of {def_id: String, count: int} — pre-rolled loot.
## @param locked    Whether the chest spawns locked (defaults to tier != "regular").
## @return          The instantiated ChestEntity node.
func spawn_chest(tier: String, position: Vector3, contents: Array,
                 locked: bool = false, force_replace: bool = false) -> Node:
	# Duck-typed as Node3D to avoid class_name resolution ordering issue in headless
	# parse context — mirrors the VillageNpcScene + DroppedItem pattern used elsewhere.
	# ChestEntity extends StaticBody3D (which extends Node3D), so global_position is safe.
	var chest: Node3D = _CHEST_ENTITY_SCENE.instantiate() as Node3D
	chest.set("tier", tier)
	chest.set("locked", locked)
	chest.set("initial_contents", contents)
	# Must be set BEFORE add_child so chest_entity._ready() passes the flag
	# through to Inventory.register_chest on first registration.
	chest.set("force_replace_on_register", force_replace)
	add_child(chest)
	chest.global_position = position
	if chest.has_method("set_main_scene"):
		chest.set_main_scene(self)
	return chest


## Spawn a BedEntity at `position` (world space) and return it. Used both by the starter
## kit and by the player re-placing a picked-up bed (Builder._try_place). BedEntity._ready
## registers it into the "bed_entity" group + the Spawning bed-bubble, so sleep works
## immediately. Mirrors spawn_chest's duck-typed Node3D shape.
func spawn_bed(position: Vector3) -> Node:
	var bed: Node3D = _BED_ENTITY_SCENE.instantiate() as Node3D
	add_child(bed)
	bed.global_position = position
	return bed


# ─── Plan 03-11: Starter kit spawning ───────────────────────────────────────

## Spawn the survival starter chest and builder-bed at the given world spawn position.
##
## Called once on first open_world() in survival mode (one-shot gate via WorldSave
## "starter_kit_spawned" meta key). Sandbox worlds do NOT call this function (D-01).
##
## Chest contents match D-15 verbatim (single source of truth: _STARTER_CHEST_CONTENTS).
## Chest spawns at world_spawn + (1, 0.5, 0); bed spawns at world_spawn + (-1, 0, 0).
## Both nodes added to their respective groups for test assertions + Phase-4 replication.
##
## @param world_spawn  World-space position for the kit centre (typically world origin).
func spawn_starter_chest_and_bed(world_spawn: Vector3) -> void:
	if not Features.is_survival_mode():
		return  # D-01 sandbox row: no starter kit

	# Chest at +X so it doesn't overlap the bed. Ground its Y at the chest's OWN column
	# (world_spawn.y is only the origin's surface height — using it for an offset prop
	# leaves it floating/buried where the terrain height differs).
	var chest_x: float = world_spawn.x + 1.0
	var chest_z: float = world_spawn.z
	var chest_pos := Vector3(chest_x, _terrain_surface_at(chest_x, chest_z) + 0.5, chest_z)
	var chest: Node = spawn_chest("regular", chest_pos, _STARTER_CHEST_CONTENTS.duplicate(true), false, true)
	if chest != null:
		chest.add_to_group("starter_chest")

	# Bed set well away from the chest (~6 m to the -X side) so the two starter props
	# don't crowd the spawn point. Ground it at the bed's OWN column surface — at -6 m
	# the terrain height differs from the origin, which is why the bed floated before.
	var bed_x: float = world_spawn.x - 6.0
	var bed_z: float = world_spawn.z
	var bed: Node = spawn_bed(Vector3(bed_x, _terrain_surface_at(bed_x, bed_z), bed_z))
	if bed != null:
		bed.add_to_group("starter_bed")

	# Decorative engraved "Welcome to Cubicraftia" sign-post (welcome_post.glb), placed OFF TO THE
	# SIDE of the spawn point rather than dead-centre in front of the player — so it greets without
	# blocking the view down the spawn axis. Offset +X (right) and slightly -Z (behind the spawn
	# line), clear of the chest (+1 X) and bed (-6 X) footprints. Ground it at its OWN column
	# surface like the chest/bed (world_spawn.y is only the origin's height).
	#
	# Orient the engraving to face back toward the spawn point so a player at spawn can read it by
	# glancing over. The GLB's boards face local +Z; look_at points local -Z at the target, so we
	# aim local -Z AWAY from spawn first, then flip 180° so +Z (the engraved face) points at spawn.
	var sign_offset := Vector3(5.0, 0.0, -2.0)
	var sign_x: float = world_spawn.x + sign_offset.x
	var sign_z: float = world_spawn.z + sign_offset.z
	var sign := _WelcomeSignScript.new() as Node3D
	add_child(sign)
	var sign_pos := Vector3(sign_x, _terrain_surface_at(sign_x, sign_z), sign_z)
	sign.global_position = sign_pos
	# Yaw so the engraved (+Z) face points back at the spawn origin.
	var to_spawn := Vector2(world_spawn.x - sign_x, world_spawn.z - sign_z)
	if to_spawn.length() > 0.01:
		sign.rotation.y = atan2(to_spawn.x, to_spawn.y)
	sign.add_to_group("starter_welcome_sign")


## Sample the terrain surface height at the world origin for the starter-kit spawn.
##
## Uses BiomeMap.sample(0, 0) to determine the surface from terrain_generator's
## noise — Phase 2's terrain heights are procedural. Falls back to Y = 64.0 if
## biome_map is unavailable (headless test context).
##
## @param biome_map  The BiomeMap instance created in _ready(). May be null in tests.
## @return           Terrain surface Y in world space.
##
## NOTE: Phase 3 plan 03-11 left this as a Y=64 stub. The real generator uses
## sea_level=12 + height_amplitude=8 (multipass_generator.gd) → terrain surface
## is in [4, 20]. Y=64 made the builder fall 50m to terrain and die from impact
## velocity > LETHAL_FALL_VELOCITY every respawn.
##
## We sample the multipass generator's noise at the spawn coordinate to get the
## actual surface height, then add 1 m so the builder lands cleanly. If the
## generator is unavailable (e.g. tests with a different terrain.tscn), fall back
## to sea_level + 2 = 14, which is at-or-above any terrain produced by the
## current generator parameters.
## Find a spawn on solid, dry LAND, searching outward from the world origin. Hardcoding
## spawn at (0,0) put the builder over open ocean for many seeds — and since water is
## non-collidable, that left them underwater / floating with no ground ("terrain gone").
## Returns a world-space position whose Y is the ground surface top (caller adds the
## standing offset). Deterministic per seed, so the spawn is stable across sessions.
func _find_world_spawn(biome_map: RefCounted) -> Vector3:
	_terrain_surface_at(0.0, 0.0)  # lazily builds _surface_noise (the generator's height noise)
	return search_land_spawn(biome_map, _surface_noise, 12.0)


## Pure, static land search shared by _find_world_spawn AND the regression test
## (tests/unit/test_spawn_on_land.gd). Searches concentric rings outward from the origin
## for the nearest column that is (a) not OCEAN and (b) has ground above the waterline.
## `height_noise` MUST match the generator's height noise (Simplex FBM, 4 octaves,
## freq 0.01, seed = world_seed) so the surface_y here equals the meshed terrain. Returns
## the ground-top world pos; falls back to sea_level+2 at origin only if no land is found
## within the (large) search radius — the contract is "Y is never below the waterline".
static func search_land_spawn(biome_map: RefCounted, height_noise: FastNoiseLite,
		sea_level: float = 12.0) -> Vector3:
	var min_land_top: float = sea_level + 1.5  # ground top clearly above the waterline
	# 96 rings × 16 m ≈ 1.5 km radius — exceeds an ocean-biome wavelength (freq 0.001 →
	# ~1 km), so a land column is found for any realistic seed. Rings ascend so the
	# CLOSEST land to origin wins.
	for ring: int in range(97):
		var r: float = float(ring) * 16.0
		var candidates: Array[Vector2] = []
		if ring == 0:
			candidates.append(Vector2.ZERO)
		else:
			for ang: int in range(8):
				var a: float = float(ang) * (TAU / 8.0)
				candidates.append(Vector2(roundf(cos(a) * r), roundf(sin(a) * r)))
		for c: Vector2 in candidates:
			if biome_map != null and biome_map.has_method("biome_at") \
					and int(biome_map.biome_at(c.x, c.y)) == int(BiomeMap.Biome.OCEAN):
				continue
			# Replicates terrain_generator/_terrain_surface_at: surface_y = int(noise*8+12),
			# ground top face at +1.
			var sy: int = int(height_noise.get_noise_2d(float(int(c.x)), float(int(c.y))) \
					* 8.0 + sea_level)
			var top: float = float(sy) + 1.0
			if top >= min_land_top:
				return Vector3(c.x, top, c.y)
	return Vector3(0.0, sea_level + 2.0, 0.0)


# ─── Plan 03-11: StrawberrySpawner chunk-load dispatch ───────────────────────

## Adapter for VoxelTerrain.block_loaded signal (godot_voxel 1.6x).
## Converts the block position to a chunk coordinate and delegates to _on_chunk_loaded.
## @param block_position  VoxelTerrain block position (may be block-space, not world-space).
func _on_voxel_block_loaded(block_position: Vector3i) -> void:
	# godot_voxel block_loaded gives the chunk grid position directly.
	_on_chunk_loaded(block_position)


## Called when a terrain chunk enters the streaming radius (VoxelTerrain.block_loaded
## or multipass_generator.chunk_loaded signal). Dispatches strawberry spawning if the
## chunk is a grassland biome chunk that has not been picked this session.
##
## Strawberries spawn in BOTH survival and sandbox modes (D-16 + DOCS §2 — overworld
## collectables; the super-heal effect is survival-relevant but the entity spawns
## regardless of mode for exploration reward consistency).
##
## @param chunk_coord  Chunk grid coordinate (chunk_coord * 16 = world-space origin of chunk).
func _on_chunk_loaded(chunk_coord: Vector3i) -> void:
	# Determine biome at the chunk's world-space centre (shared by all dispatchers).
	var biome: int = BiomeMap.Biome.GRASSLAND_FOREST  # default fallback
	if _biome_map != null and _biome_map.has_method("biome_at"):
		var chunk_centre_x: float = chunk_coord.x * 16.0 + 8.0
		var chunk_centre_z: float = chunk_coord.z * 16.0 + 8.0
		biome = _biome_map.biome_at(chunk_centre_x, chunk_centre_z)

	# Each dispatcher owns its OWN dedup cache and gates. They are called
	# independently so a chunk that spawns no strawberries (most chunks) still gets
	# a chance at foliage and wildlife. (Previously the strawberry early-returns
	# short-circuited both — wildlife/foliage almost never spawned.)
	_dispatch_strawberries(chunk_coord, biome)
	_dispatch_crops(chunk_coord, biome)
	# Structures are now handled by the _process proximity streamer (async load + despawn),
	# NOT here — a synchronous GLB decode on chunk-load caused the fps=1-3 hiccups.
	# Decorations (foliage flowers + grass) are deferred a frame so the VoxelTerrain chunk
	# mesh/collision has a chance to bake first — dispatching them synchronously on block_loaded
	# made grass/flowers pop in BEFORE the ground beneath them rendered (they appeared to float
	# over not-yet-visible terrain during streaming). The per-dispatcher dedup caches make the
	# deferred call safe against double-spawn. Wildlife is grounded via its own ground_y clamp so
	# it is dispatched immediately.
	_dispatch_decorations_deferred(chunk_coord, biome)
	_dispatch_wildlife(chunk_coord, biome)


## Defer grass/flower decoration spawning by one frame so the chunk's terrain mesh exists before
## the decorations are placed (prevents foliage floating over not-yet-rendered ground). The
## foliage/grass dispatchers carry their own dedup caches, so the deferred re-entry never
## double-spawns. Guarded by is_inside_tree() in case the scene is torn down mid-await.
func _dispatch_decorations_deferred(chunk_coord: Vector3i, biome: int) -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_dispatch_foliage(chunk_coord, biome)
	_dispatch_grass(chunk_coord, biome)
	_dispatch_ocean_decor(chunk_coord, biome)


## Ocean-floor decor dispatch (own dedup + gates). Scatters static coral/kelp/shell meshes on
## the submerged seabed of OCEAN chunks, batched into one MultiMeshInstance3D per kind (mobile-
## cheap, like _dispatch_foliage). Decor is purely visual: no physics, no persistence; it is
## re-created from the deterministic seed on each chunk-load. Only seabed cells that are
## actually below the water surface get decor, so nothing decorates dry "ocean" cells.
func _dispatch_ocean_decor(chunk_coord: Vector3i, biome: int) -> void:
	if _processed_ocean_decor_chunks.has(chunk_coord):
		return
	_processed_ocean_decor_chunks[chunk_coord] = true
	if not _OceanDecorSpawnerScript.should_spawn_in_chunk(chunk_coord, biome, _world_seed):
		return
	var count: int = _OceanDecorSpawnerScript.spawn_count_for_chunk(chunk_coord, _world_seed)
	if count <= 0:
		return
	var entries: Array = _OceanDecorSpawnerScript.pick_spawn_entries(chunk_coord, count, _world_seed)
	if entries.is_empty():
		return

	const _SEA_LEVEL: float = 12.0  # sea_level in multipass_generator (same value structures use).
	# Group surface-corrected, below-water placements by kind so each kind batches into ONE
	# MultiMeshInstance3D (1 draw call per kind per chunk) instead of N individual nodes.
	var by_kind: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = (_world_seed ^ ((chunk_coord.x * 73856093) ^ (chunk_coord.z * 19349663)) \
		^ "ocean_decor_scatter".hash()) & 0x7FFFFFFFFFFFFFFF
	for entry: Dictionary in entries:
		var kind: String = entry.get("kind", "")
		var raw_pos: Vector3 = entry.get("pos", Vector3.ZERO)
		var seabed_y: float = _terrain_surface_at(raw_pos.x, raw_pos.z)
		# Only decorate cells whose seabed is actually under water — skip "ocean" cells that
		# happen to poke above the waterline so we never strand coral on a dry sandbar.
		if seabed_y >= _SEA_LEVEL:
			continue
		var yaw: float = rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw)
		var pos := Vector3(raw_pos.x, seabed_y, raw_pos.z)
		if not by_kind.has(kind):
			by_kind[kind] = []
		(by_kind[kind] as Array).append(Transform3D(basis, pos))

	for kind: String in by_kind.keys():
		var xforms: Array = by_kind[kind]
		var mesh: Mesh = _get_ocean_decor_mesh(kind)
		if mesh == null or xforms.is_empty():
			continue
		var centre := Vector3(float(chunk_coord.x) * 16.0 + 8.0, 0.0, float(chunk_coord.z) * 16.0 + 8.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		var placed: int = 0
		for xf: Transform3D in xforms:
			var local := Transform3D(xf.basis, xf.origin - centre)
			mm.set_instance_transform(placed, local)
			placed += 1
		mm.instance_count = placed
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.add_to_group("ocean_decor")
		mmi.set_meta("origin_chunk", chunk_coord)
		add_child(mmi)
		mmi.global_position = centre


## Lazily extract + cache the decor Mesh for `kind` from res://assets/meshes/decor/<kind>.glb.
## Returns null (and caches the miss) when the asset or its mesh is unavailable. Mirrors
## _get_flower_mesh but keyed per decor kind for the MultiMesh batcher above.
func _get_ocean_decor_mesh(kind: String) -> Mesh:
	if _ocean_decor_mesh_cache.has(kind):
		return _ocean_decor_mesh_cache[kind]
	var path: String = "res://assets/meshes/decor/%s.glb" % kind
	if not ResourceLoader.exists(path):
		_ocean_decor_mesh_cache[kind] = null
		return null
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		_ocean_decor_mesh_cache[kind] = null
		return null
	var inst: Node3D = scene.instantiate() as Node3D
	var mesh: Mesh = null
	if inst != null:
		for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
			if (n as MeshInstance3D).mesh != null:
				mesh = (n as MeshInstance3D).mesh
				break
		inst.queue_free()
	_ocean_decor_mesh_cache[kind] = mesh
	return mesh


## Rare biome-landmark structure dispatch (own dedup + gates). At most one building per
## eligible chunk, surface-grounded, kept clear of the world origin.
func _dispatch_structures(chunk_coord: Vector3i, biome: int) -> void:
	if _processed_structure_chunks.has(chunk_coord):
		return
	_processed_structure_chunks[chunk_coord] = true
	if not _StructureSpawnerScript.should_spawn_in_chunk(chunk_coord, biome, _world_seed):
		return
	var pick: Dictionary = _StructureSpawnerScript.pick_structure(chunk_coord, biome, _world_seed)
	if pick.is_empty():
		return
	var raw_pos: Vector3 = pick.get("pos", Vector3.ZERO)
	var surface_y: float = _terrain_surface_at(raw_pos.x, raw_pos.z)
	# OCEAN structures (shipwreck/lighthouse) must sit IN the water, not on dry land. Only
	# place them where the terrain is actually below sea level, and float them at the water
	# surface (partly submerged) rather than on the seabed. (sea_level=12 in multipass_generator.)
	if biome == int(BiomeMap.Biome.OCEAN):
		const _SEA_LEVEL: float = 12.0
		if surface_y >= _SEA_LEVEL:
			return  # this "ocean" chunk is above water here — don't strand a ship on land
		surface_y = _SEA_LEVEL - 1.0  # waterline, partly submerged
	spawn_structure(pick.get("id", ""), Vector3(raw_pos.x, surface_y, raw_pos.z))


## Instantiate a WorldStructure of `id` at `world_pos` (base on the surface).
func spawn_structure(id: String, world_pos: Vector3, scene: PackedScene = null) -> Node3D:
	if id == "":
		return null
	var s: Node3D = _WorldStructureScript.new() as Node3D
	if s == null:
		return null
	s.set("structure_id", id)
	if scene != null:
		s.set("preloaded_scene", scene)
	s.position = world_pos
	add_child(s)
	return s


## Harvestable-crop per-chunk dispatch (own dedup + gates). Wheat in grassland/savannah,
## sugar_cane in jungle; surface-corrected like strawberries/flowers.
func _dispatch_crops(chunk_coord: Vector3i, biome: int) -> void:
	if _processed_crop_chunks.has(chunk_coord):
		return
	_processed_crop_chunks[chunk_coord] = true
	if not _CropSpawnerScript.should_spawn_in_chunk(chunk_coord, biome, _world_seed):
		return
	var count: int = _CropSpawnerScript.spawn_count_for_chunk(chunk_coord, _world_seed)
	if count <= 0:
		return
	var entries: Array = _CropSpawnerScript.pick_spawn_entries(chunk_coord, count, biome, _world_seed)
	for entry: Dictionary in entries:
		var kind: String = entry.get("kind", "")
		var raw_pos: Vector3 = entry.get("pos", Vector3.ZERO)
		if kind.is_empty():
			continue
		var surface_y: float = _terrain_surface_at(raw_pos.x, raw_pos.z)
		spawn_crop(kind, Vector3(raw_pos.x, surface_y, raw_pos.z))


## Instantiate a harvestable Crop of `kind` at `world_pos` (feet on the surface).
func spawn_crop(kind: String, world_pos: Vector3) -> void:
	var crop: Node3D = _CropScript.new() as Node3D
	if crop == null:
		return
	crop.set("crop_kind", kind)
	crop.position = world_pos
	add_child(crop)


## Strawberry per-chunk dispatch (own dedup + gates).
func _dispatch_strawberries(chunk_coord: Vector3i, biome: int) -> void:
	if _processed_strawberry_chunks.has(chunk_coord):
		return
	var session_id: String = _get_session_id()
	if not _StrawberrySpawnerScript.should_spawn_in_chunk(chunk_coord, biome, session_id):
		_processed_strawberry_chunks[chunk_coord] = true
		return
	var count: int = _StrawberrySpawnerScript.spawn_count_for_chunk(chunk_coord, _world_seed)
	if count == 0:
		_processed_strawberry_chunks[chunk_coord] = true
		return
	var positions: Array = _StrawberrySpawnerScript.pick_spawn_positions(chunk_coord, count, _world_seed)
	for raw_pos: Vector3 in positions:
		var surface_y: float = _terrain_surface_at(raw_pos.x, raw_pos.z)
		var world_pos: Vector3 = Vector3(raw_pos.x, surface_y + 0.3, raw_pos.z)
		var strawberry: Node = spawn_strawberry(world_pos)
		if strawberry != null and strawberry.has_method("set_chunk_coord"):
			strawberry.set_chunk_coord(chunk_coord)
	_processed_strawberry_chunks[chunk_coord] = true


## Flower-decoration per-chunk dispatch (own dedup + gates).
func _dispatch_foliage(chunk_coord: Vector3i, biome: int) -> void:
	if _processed_foliage_chunks.has(chunk_coord):
		return
	_processed_foliage_chunks[chunk_coord] = true
	if not _FoliageSpawnerScript.should_spawn_in_chunk(chunk_coord, biome, _world_seed):
		return
	var flower_count: int = _FoliageSpawnerScript.spawn_count_for_chunk(chunk_coord, _world_seed)
	if flower_count <= 0:
		return
	var flower_positions: Array = _FoliageSpawnerScript.pick_spawn_positions(
		chunk_coord, flower_count, _world_seed)
	# Batch the whole chunk's flowers into ONE MultiMeshInstance3D (1 draw call) instead of
	# N individual flower nodes — individual flower meshes were the dominant draw-call source
	# and caused the frame-rate jitter. Mirrors _dispatch_grass.
	var fmesh: Mesh = _get_flower_mesh()
	if fmesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = fmesh
	mm.instance_count = flower_positions.size()
	var centre := Vector3(float(chunk_coord.x) * 16.0 + 8.0, 0.0, float(chunk_coord.z) * 16.0 + 8.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = (_world_seed ^ ((chunk_coord.x * 73856093) ^ (chunk_coord.z * 19349663)) ^ "flower_scatter".hash()) & 0x7FFFFFFFFFFFFFFF
	var placed: int = 0
	for f_pos: Vector3 in flower_positions:
		var f_surface_y: float = _terrain_surface_at(f_pos.x, f_pos.z)
		var yaw: float = rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw)
		mm.set_instance_transform(placed, Transform3D(basis, Vector3(f_pos.x, f_surface_y + 0.1, f_pos.z) - centre))
		placed += 1
	mm.instance_count = placed
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# No material_override: the flower mesh carries its own per-surface materials from the
	# glTF import (an override would flatten petals + stem to one material).
	mmi.add_to_group("flower")
	mmi.set_meta("origin_chunk", chunk_coord)
	add_child(mmi)
	mmi.global_position = centre


## Cached flower mesh + material, extracted once from flower.glb for MultiMesh batching.
var _flower_mesh_cache: Mesh = null
var _flower_material: Material = null
var _flower_mesh_extracted: bool = false

func _get_flower_mesh() -> Mesh:
	if _flower_mesh_extracted:
		return _flower_mesh_cache
	_flower_mesh_extracted = true
	var inst: Node3D = _FLOWER_MESH.instantiate() as Node3D
	if inst == null:
		return null
	var mi: MeshInstance3D = null
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null:
			mi = n as MeshInstance3D
			break
	if mi != null:
		_flower_mesh_cache = mi.mesh
		_flower_material = mi.material_override if mi.material_override != null else mi.get_active_material(0)
	inst.queue_free()
	return _flower_mesh_cache


## Passive-wildlife per-chunk dispatch (own dedup + gates + active cap).
func _dispatch_wildlife(chunk_coord: Vector3i, biome: int) -> void:
	if _processed_wildlife_chunks.has(chunk_coord):
		return
	if _wildlife_active_count >= _WILDLIFE_ACTIVE_CAP:
		# Cap saturated — leave this chunk UNPROCESSED so it gets another chance to spawn
		# once the distance-cull frees slots (or on a later reload). Marking it processed
		# here is exactly what previously left the world empty beyond the spawn area.
		return
	_processed_wildlife_chunks[chunk_coord] = true
	if not _WildlifeSpawnerScript.should_spawn_in_chunk(chunk_coord, biome, _world_seed):
		return
	var wl_count: int = _WildlifeSpawnerScript.spawn_count_for_chunk(chunk_coord, _world_seed)
	if wl_count <= 0:
		return
	var wl_entries: Array = _WildlifeSpawnerScript.pick_spawn_entries(
		chunk_coord, wl_count, biome, _world_seed)
	for entry: Dictionary in wl_entries:
		if _wildlife_active_count >= _WILDLIFE_ACTIVE_CAP:
			break
		var wl_kind: String = entry.get("kind", "")
		var raw_wl_pos: Vector3 = entry.get("pos", Vector3.ZERO)
		# Ocean animals use the spawner Y directly; land animals get surface-corrected Y.
		var wl_y: float = raw_wl_pos.y
		var wl_ground: float = INF
		if biome != 5:  # not OCEAN
			wl_ground = _terrain_surface_at(raw_wl_pos.x, raw_wl_pos.z)
			wl_y = wl_ground + 0.5
		spawn_wildlife(wl_kind, Vector3(raw_wl_pos.x, wl_y, raw_wl_pos.z), chunk_coord, wl_ground)


## Instantiate a Strawberry entity at the given world position.
## Called by _on_chunk_loaded for each spawn position.
##
## @param world_pos  World-space position (surface-corrected Y).
## @return           The instantiated Strawberry node.
func spawn_strawberry(world_pos: Vector3) -> Node:
	var strawberry: Node = _STRAWBERRY_SCENE.instantiate()
	add_child(strawberry)
	(strawberry as Node3D).global_position = world_pos
	return strawberry


## Instantiate a decorative flower at the given world position.
##
## Spawns the flower.glb as a MeshInstance3D child of main_scene.
## Purely visual — no physics, no inventory interaction, no persistence.
## Called by the foliage dispatch in _on_chunk_loaded.
##
## @param world_pos  World-space position (surface-corrected Y).
func spawn_flower(world_pos: Vector3, origin_chunk: Vector3i = Vector3i.ZERO) -> void:
	# _FLOWER_MESH is a PackedScene (glb import), instantiate it as a Node3D subtree.
	var flower: Node3D = _FLOWER_MESH.instantiate() as Node3D
	if flower == null:
		return
	add_child(flower)
	flower.global_position = world_pos
	# Grouped + origin-chunk meta so the distance-cull frees flowers as the player roams —
	# otherwise these individual (un-batched) meshes accumulate unbounded and their draw
	# calls pile up into the frame-rate jitter on dense views.
	flower.add_to_group("flower")
	flower.set_meta("origin_chunk", origin_chunk)


## Grass scatter: one MultiMeshInstance3D per grass/jungle/savannah chunk holding a
## handful of procedural grass tufts. MultiMesh keeps it to one draw call per chunk.
## Grouped + origin-chunk meta so the distance-cull frees it as the player roams.
func _dispatch_grass(chunk_coord: Vector3i, biome: int) -> void:
	if _processed_grass_chunks.has(chunk_coord):
		return
	_processed_grass_chunks[chunk_coord] = true
	# Grass biomes only: GRASSLAND_FOREST(0), JUNGLE(3), SAVANNAH(4).
	if biome != 0 and biome != 3 and biome != 4:
		return

	var rng := RandomNumberGenerator.new()
	var coord_hash: int = (chunk_coord.x * 73856093) ^ (chunk_coord.z * 19349663)
	rng.seed = (_world_seed ^ coord_hash ^ "grass_scatter".hash()) & 0x7FFFFFFFFFFFFFFF
	var count: int = rng.randi_range(30, 50)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _get_grass_tuft_mesh()
	mm.instance_count = count
	# Anchor the node at the chunk centre and store instances in LOCAL space, so the
	# node's global_position is meaningful for the distance-cull (instances at world
	# coords on an origin-anchored node would make the cull measure from (0,0,0)).
	var centre := Vector3(float(chunk_coord.x) * 16.0 + 8.0, 0.0, float(chunk_coord.z) * 16.0 + 8.0)
	var placed: int = 0
	for i: int in count:
		var wx: float = centre.x - 8.0 + rng.randf_range(0.5, 15.5)
		var wz: float = centre.z - 8.0 + rng.randf_range(0.5, 15.5)
		var wy: float = _terrain_surface_at(wx, wz)
		var yaw: float = rng.randf() * TAU
		var sc: float = rng.randf_range(0.8, 1.35)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sc, rng.randf_range(0.9, 1.5), sc))
		# Local position relative to the chunk-centre anchor.
		mm.set_instance_transform(placed, Transform3D(basis, Vector3(wx, wy, wz) - centre))
		placed += 1
	mm.instance_count = placed

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.add_to_group("grass")
	mmi.set_meta("origin_chunk", chunk_coord)
	add_child(mmi)
	mmi.global_position = centre


## Build (once) a small grass-tuft mesh: a fan of thin tapered blades with a
## base→tip green vertex-colour gradient. Double-sided, unlit-ish. Shared by every
## chunk's grass MultiMesh.
func _get_grass_tuft_mesh() -> Mesh:
	if _grass_tuft_mesh != null:
		return _grass_tuft_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades: int = 5
	for b: int in blades:
		var ang: float = TAU * float(b) / float(blades) + 0.4
		var dx: float = cos(ang)
		var dz: float = sin(ang)
		var spread: float = 0.10  # blade base offset from tuft centre
		var lean: float = 0.10    # tip leans outward
		var w: float = 0.035      # half-width of the blade base
		var h: float = 0.28
		var bx: float = dx * spread
		var bz: float = dz * spread
		var px: float = -dz * w
		var pz: float = dx * w
		st.add_vertex(Vector3(bx - px, 0.0, bz - pz))
		st.add_vertex(Vector3(bx + px, 0.0, bz + pz))
		st.add_vertex(Vector3(bx + dx * lean, h, bz + dz * lean))
	st.generate_normals()
	# Solid saturated grass-green albedo (a touch darker/greener than the terrain so the
	# tufts read against the ground). Double-sided so the thin blades show from both faces.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.52, 0.20)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	st.set_material(mat)
	_grass_tuft_mesh = st.commit()
	return _grass_tuft_mesh


# ─── Plan 07: Wildlife spawning (passive roaming animals) ────────────────────

## Instantiate a passive Wildlife animal of the given kind at world_pos.
##
## Creates a Wildlife node (src/world/wildlife.gd), sets its kind, places it
## at world_pos, and increments _wildlife_active_count. When the node is freed
## (e.g. the chunk unloads), the count is decremented via the tree_exited signal.
##
## Guarded: unknown kinds are silently skipped; _WildlifeScript must load cleanly
## or the call is a no-op.
##
## @param kind       Creature kind string (must be a key in WildlifeSpawner._BIOME_ROSTER).
## @param world_pos  Surface-corrected world-space position.
func spawn_wildlife(kind: String, world_pos: Vector3, origin_chunk: Vector3i = Vector3i.ZERO,
		ground_top_y: float = INF) -> void:
	if kind.is_empty():
		return
	if _wildlife_active_count >= _WILDLIFE_ACTIVE_CAP:
		return
	var wildlife: Node3D = _WildlifeScript.new() as Node3D
	if wildlife == null:
		return
	wildlife.set("kind", kind)
	# Known terrain top-face Y for land creatures: lets them clamp to the ground instead of
	# free-falling through a chunk whose collision mesh hasn't baked yet (the "buried, only
	# head sticking out" bug). INF = unknown (ocean/air) → normal physics only.
	wildlife.set("ground_y", ground_top_y)
	# Set position before add_child so _ready() sees the correct global_position
	# when it stores _spawn_origin.
	wildlife.position = world_pos
	# Issue #17: inject the scene ref so the animal's death drop (raw_meat) can spawn a
	# collectable pickup via spawn_dropped_item — the same flow mined materials use.
	if wildlife.has_method("set_main_scene"):
		wildlife.set_main_scene(self)
	add_child(wildlife)
	# Group + origin-chunk meta let _cull_distant_wildlife() find roaming animals and
	# free the chunk's dedup entry so it can repopulate when the player returns.
	wildlife.add_to_group("wildlife")
	wildlife.set_meta("origin_chunk", origin_chunk)
	_wildlife_active_count += 1
	# Decrement the global cap when the node is freed (cull, chunk unload, or world close).
	wildlife.tree_exited.connect(_on_wildlife_tree_exited)


## Decrement the active wildlife counter when a Wildlife node leaves the tree.
func _on_wildlife_tree_exited() -> void:
	_wildlife_active_count = maxi(_wildlife_active_count - 1, 0)


## Free wildlife further than _WILDLIFE_DESPAWN_DIST_M from the builder. Frees the
## active-cap so fresh chunks ahead of the player can spawn, and clears each culled
## animal's origin chunk from the dedup set so the area repopulates on return.
func _cull_distant_wildlife() -> void:
	var builder: Node3D = get_node_or_null("Builder") as Node3D
	if builder == null:
		return
	var bpos: Vector3 = builder.global_position
	for wl: Node in get_tree().get_nodes_in_group("wildlife"):
		var n3: Node3D = wl as Node3D
		if n3 == null:
			continue
		if n3.global_position.distance_to(bpos) <= _WILDLIFE_DESPAWN_DIST_M:
			continue
		if n3.has_meta("origin_chunk"):
			_processed_wildlife_chunks.erase(n3.get_meta("origin_chunk"))
		n3.queue_free()  # tree_exited decrements _wildlife_active_count

	# Same treatment for grass chunk-decor (cheap MultiMesh nodes, but unbounded if never
	# freed). Clear the dedup key so the chunk re-scatters grass when revisited.
	for g: Node in get_tree().get_nodes_in_group("grass"):
		var gn: Node3D = g as Node3D
		if gn == null:
			continue
		if gn.global_position.distance_to(bpos) <= _WILDLIFE_DESPAWN_DIST_M:
			continue
		if gn.has_meta("origin_chunk"):
			_processed_grass_chunks.erase(gn.get_meta("origin_chunk"))
		gn.queue_free()

	# And scattered flowers (individual meshes — biggest draw-call source if unbounded).
	for fl: Node in get_tree().get_nodes_in_group("flower"):
		var fn: Node3D = fl as Node3D
		if fn == null:
			continue
		if fn.global_position.distance_to(bpos) <= _WILDLIFE_DESPAWN_DIST_M:
			continue
		if fn.has_meta("origin_chunk"):
			_processed_foliage_chunks.erase(fn.get_meta("origin_chunk"))
		fn.queue_free()


# ─── Structure proximity streaming ───────────────────────────────────────────
# Structures are NOT spawned on terrain chunk-load any more. Instead this streamer scans a
# radius AHEAD of the player, threaded-loads each eligible structure's GLB on a worker
# thread (no main-thread decode freeze), instantiates it when ready, and frees both the node
# AND its resource once the player moves far away — so memory stays bounded to what's nearby.
const _STRUCT_STREAM_DIST_M: float = 144.0    # load radius (> terrain view distance ~80 m)
const _STRUCT_DESPAWN_DIST_M: float = 176.0   # free beyond this (hysteresis vs the load radius)
const _STRUCT_STREAM_INTERVAL_S: float = 0.6  # how often we re-scan / despawn

## Per-chunk stream state: Vector2i(cx,cz) -> {state, id, pos, path, node}. state ∈
## {"empty","want","spawned"}. Only holds chunks within the despawn radius (bounded).
var _ss: Dictionary = {}
## path -> threaded PackedScene held while >0 live structures use it (dropped on count 0).
var _ss_scene: Dictionary = {}
var _ss_refs: Dictionary = {}
## path -> true while a threaded load is in flight (single-flight per path).
var _ss_loading: Dictionary = {}
var _struct_stream_accum: float = 999.0  # force a scan on the first tick


## Per-frame streamer step: poll loads + spawn ready ones (cheap, every frame); scan for new
## chunks, request loads, and despawn far ones on a throttle.
func _stream_structures(delta: float) -> void:
	# Don't stream structures until the world has finished loading: the threaded GLB loads
	# otherwise compete with VoxelTerrain's mesh worker threads during the critical spawn
	# window, so terrain under the builder doesn't bake before the spawn-grace times out and
	# the builder floats/falls (the "missing terrain" regression).
	if not _loading_done:
		return
	var builder: Node3D = get_node_or_null("Builder") as Node3D
	if builder == null:
		return
	var bpos: Vector3 = builder.global_position

	# Poll in-flight threaded loads.
	for path: String in _ss_loading.keys():
		var stt: int = ResourceLoader.load_threaded_get_status(path)
		if stt == ResourceLoader.THREAD_LOAD_LOADED:
			_ss_scene[path] = ResourceLoader.load_threaded_get(path)
			_ss_loading.erase(path)
		elif stt == ResourceLoader.THREAD_LOAD_FAILED or stt == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_ss_loading.erase(path)

	# Spawn any "want" chunks whose scene is ready AND whose terrain has loaded under them, so a
	# structure never appears floating before the ground streams in (v1.1 QA #8).
	var _svt: Object = _structure_voxel_tool()
	for key: Vector2i in _ss.keys():
		var e: Dictionary = _ss[key]
		if e.get("state", "") == "want" and _ss_scene.has(e["path"]):
			if not _terrain_ready_at(_svt, e["pos"]):
				continue  # ground under this structure not loaded yet — retry next pass
			e["node"] = spawn_structure(e["id"], e["pos"], _ss_scene[e["path"]])
			e["state"] = "spawned"
			_ss_refs[e["path"]] = int(_ss_refs.get(e["path"], 0)) + 1

	_struct_stream_accum += delta
	if _struct_stream_accum < _STRUCT_STREAM_INTERVAL_S:
		return
	_struct_stream_accum = 0.0

	# Scan chunks within the load radius and evaluate any not seen yet.
	var pcx: int = int(floor(bpos.x / 16.0))
	var pcz: int = int(floor(bpos.z / 16.0))
	var r: int = int(ceil(_STRUCT_STREAM_DIST_M / 16.0))
	for cx: int in range(pcx - r, pcx + r + 1):
		for cz: int in range(pcz - r, pcz + r + 1):
			var key := Vector2i(cx, cz)
			if _ss.has(key):
				continue
			var ccx: float = (cx + 0.5) * 16.0
			var ccz: float = (cz + 0.5) * 16.0
			if Vector2(ccx - bpos.x, ccz - bpos.z).length() > _STRUCT_STREAM_DIST_M:
				continue
			_eval_structure_chunk(key, cx, cz, ccx, ccz)

	# Kick off threaded loads for "want" chunks not already loading/loaded (single-flight).
	for key: Vector2i in _ss.keys():
		var e: Dictionary = _ss[key]
		if e.get("state", "") == "want":
			var path: String = e["path"]
			if not _ss_scene.has(path) and not _ss_loading.has(path):
				ResourceLoader.load_threaded_request(path, "", false, ResourceLoader.CACHE_MODE_IGNORE)
				_ss_loading[path] = true

	# Despawn far chunks (and free the scene resource when its last user goes — bounded memory).
	for key: Vector2i in _ss.keys():
		var ccx: float = (key.x + 0.5) * 16.0
		var ccz: float = (key.y + 0.5) * 16.0
		if Vector2(ccx - bpos.x, ccz - bpos.z).length() <= _STRUCT_DESPAWN_DIST_M:
			continue
		var e: Dictionary = _ss[key]
		if e.get("state", "") == "spawned":
			var n: Variant = e.get("node")
			if is_instance_valid(n):
				(n as Node).queue_free()
			var path: String = e["path"]
			_ss_refs[path] = int(_ss_refs.get(path, 0)) - 1
			if _ss_refs[path] <= 0:
				_ss_refs.erase(path)
				_ss_scene.erase(path)  # CACHE_MODE_IGNORE: dropping the ref frees the resource
		_ss.erase(key)


## Evaluate one chunk for a structure (biome gate + rare roll + ocean-water gate) and record
## its stream state. Mirrors the old _dispatch_structures logic, minus the synchronous load.
func _eval_structure_chunk(key: Vector2i, cx: int, cz: int, ccx: float, ccz: float) -> void:
	var biome: int = 0
	if _biome_map != null and _biome_map.has_method("biome_at"):
		biome = int(_biome_map.biome_at(ccx, ccz))
	var chunk := Vector3i(cx, 0, cz)
	if not _StructureSpawnerScript.should_spawn_in_chunk(chunk, biome, _world_seed):
		_ss[key] = {"state": "empty"}
		return
	var pick: Dictionary = _StructureSpawnerScript.pick_structure(chunk, biome, _world_seed)
	if pick.is_empty():
		_ss[key] = {"state": "empty"}
		return
	var raw: Vector3 = pick.get("pos", Vector3.ZERO)
	var id: String = pick.get("id", "")
	var placement: String = _StructureSpawnerScript.placement_for(id)
	const _SEA_LEVEL: float = 12.0
	const _FOOT: float = 5.0  # ~half a structure footprint

	# Ground to the LOWEST SOLID surface under the structure's footprint (centre + corners) so no
	# edge floats over a slope. _seabed_surface_at is OCEAN-aware (deepened seabed) so underwater
	# structures land on the real seabed (QA #7), not the old shallow height.
	var sy: float = _seabed_surface_at(raw.x, raw.z)
	for off: Vector2 in [Vector2(-_FOOT, -_FOOT), Vector2(_FOOT, -_FOOT), Vector2(-_FOOT, _FOOT), Vector2(_FOOT, _FOOT)]:
		sy = minf(sy, _seabed_surface_at(raw.x + off.x, raw.z + off.y))

	# Per-placement grounding (QA #3/#4):
	var base_y: float
	match placement:
		"underwater":
			# Shipwreck / underwater ruin: REQUIRE the seabed to be below sea level (truly
			# submerged), then rest the base ON the seabed. Skip if the spot is actually dry land.
			if sy >= _SEA_LEVEL:
				_ss[key] = {"state": "empty"}
				return
			base_y = sy  # sits on the seabed; the water column above hides the join
		"beach":
			# Sandcastle: only at the sand/water EDGE — the lowest footprint ground must sit in a
			# narrow coastal band around the waterline (a beach), not deep underwater nor high
			# inland. Place its base just above the waterline so it stands on wet sand.
			if sy < _SEA_LEVEL - 3.0 or sy > _SEA_LEVEL + 2.0:
				_ss[key] = {"state": "empty"}
				return
			base_y = maxf(sy, _SEA_LEVEL)
		_:  # "land"
			# Never strand a land structure underwater / half-submerged (this is what put
			# lighthouses + igloos sticking out of the ocean before).
			if sy < _SEA_LEVEL:
				_ss[key] = {"state": "empty"}
				return
			# Big landmarks (castles, large ruins) sit cleanly ON the surface — no embed, so the
			# castle is not half-buried (QA #3). Generic props keep the small embed so their
			# footprint edges rest in the terrain instead of floating.
			base_y = sy if _WorldStructureScript.is_no_embed(id) else sy - 0.6

	_ss[key] = {
		"state": "want", "id": id, "pos": Vector3(raw.x, base_y, raw.z),
		"path": "res://assets/meshes/structures/" + id + ".glb", "node": null,
	}


## The VoxelTerrain's VoxelTool (duck-typed; null when the voxel module/terrain is absent, e.g.
## headless tests). Used to gate structure spawning on terrain readiness.
##
## QA #2 fix: the terrain node in this project is named "Terrain" (terrain.tscn root), NOT
## "VoxelTerrain" — the old lookup returned null every time, so _terrain_ready_at degenerated to
## "always true" and structures spawned over not-yet-generated ground (the floating bug). Look up
## "Terrain" first, keep "VoxelTerrain" as a fallback for any scene that does use that name.
func _structure_voxel_tool() -> Object:
	var vterrain: Node = get_node_or_null("Terrain")
	if vterrain == null:
		vterrain = get_node_or_null("VoxelTerrain")
	if vterrain == null or not vterrain.has_method("get_voxel_tool"):
		return null
	return vterrain.get_voxel_tool()


## True only when the terrain under `pos` is BOTH (a) generated as voxel data AND (b) meshed with
## baked collision at this location — so a structure is never revealed floating over ground that
## has not streamed/meshed yet, even at far LOD (QA #2).
##
## Two independent checks, both required:
##   1. is_area_editable() — the voxel DATA for the footprint column exists (generation done).
##   2. a downward raycast from above the footprint hits terrain collision (layer 1) — collision
##      is only baked AFTER the chunk meshes, so a hit is a reliable "meshed at this LOD" proxy.
##      At far LOD the data can be present long before the mesh bakes; check (1) alone passed too
##      early and let structures pop in over flat/empty ground. The ray closes that gap.
##
## Defaults to permissive (true) only when neither a VoxelTool nor a physics space is available
## (headless tests / no terrain) so the spawn path has no regression there.
func _terrain_ready_at(vt: Object, pos: Vector3) -> bool:
	# (1) Voxel data present for the footprint.
	if vt != null and vt.has_method("is_area_editable"):
		if not vt.is_area_editable(AABB(pos - Vector3(2.0, 4.0, 2.0), Vector3(4.0, 8.0, 4.0))):
			return false
	# (2) Collision baked under the footprint (mesh exists). Skip if no physics space (tests).
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	if space == null:
		return true
	# Ray from well above the structure base down through it — a hit means the chunk meshed and
	# baked collision here. `pos.y` is the (slightly embedded) base, so start a few m higher.
	var q := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0.0, 6.0, 0.0), pos - Vector3(0.0, 3.0, 0.0))
	q.collision_mask = 1
	return not space.intersect_ray(q).is_empty()


## Get the current world session ID.
## Prefers NetworkManager.get_session_id() (multiplayer-aware) when available.
## Falls back to the WorldSave "session_id" meta key written at world-open (Plan 03-11).
## Finally generates a timestamp token if neither source has a value
## (STATE.md decision strawberry-session-id-fallback cleanup, Plan 04-09).
func _get_session_id() -> String:
	# Prefer NetworkManager session ID when multiplayer is active (A3 cleanup).
	var _session_token: String = ""
	if is_instance_valid(NetworkManager) and not NetworkManager.get_session_id().is_empty():
		_session_token = NetworkManager.get_session_id()
	if not _session_token.is_empty():
		return _session_token
	# Fall back to WorldSave meta "session_id" (written by Plan 03-11 at world-open).
	var raw: Variant = WorldSave.get_world_meta("session_id")
	if raw == null:
		_session_token = str(int(Time.get_unix_time_from_system()))
		WorldSave.set_world_meta("session_id", var_to_bytes(_session_token))
		return _session_token
	if raw is PackedByteArray:
		var decoded: Variant = bytes_to_var(raw as PackedByteArray)
		return str(decoded)
	return str(raw)


## Estimate the terrain surface Y at the given (x, z) world position.
## Phase 2 terrain_generator centres its surface at Y = 64; this is the v1 approximation.
## A proper raycast would require the VoxelTerrain node and is deferred to future phases.
##
## @param x  World-space X coordinate.
## @param z  World-space Z coordinate.
## @return   Estimated surface Y (64.0 fallback in Phase 3).
func _terrain_surface_at(x: float, z: float) -> float:
	# Deterministic GROUND height — replicates multipass_generator._generate_base_terrain
	# exactly: surface_y = int(noise * height_amplitude + sea_level), top face at +1.
	#
	# This is formula-based, NOT a raycast, on purpose:
	#   - The old Y=64 stub floated everything ~45 m up ("red dots in the sky").
	#   - A downward voxel raycast (the first fix attempt) hit TREE canopies/logs and
	#     stranded strawberries + grass on top of trees — still floating in the air.
	# The formula ignores trees and load timing, so items always sit on the real ground
	# (same surface_y the tree trunks are planted on).
	if _surface_noise == null:
		_surface_noise = FastNoiseLite.new()
		_surface_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_surface_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_surface_noise.fractal_octaves = 4
		_surface_noise.fractal_lacunarity = 2.0
		_surface_noise.fractal_gain = 0.5
		_surface_noise.frequency = 0.01
		_surface_noise.seed = _world_seed
	# Floor to the integer column the generator actually sampled, so the height matches
	# the voxel surface exactly (no off-by-one float at column boundaries).
	var noise_val: float = _surface_noise.get_noise_2d(float(floori(x)), float(floori(z)))
	var surface_y: int = int(noise_val * 8.0 + 12.0)  # height_amplitude 8, sea_level 12
	return float(surface_y) + 1.0


## SOLID-ground (seabed) surface height at (x, z), accounting for the OCEAN floor deepening that
## multipass_generator applies to OCEAN-biome columns (QA #7). For land columns this equals
## _terrain_surface_at; for OCEAN columns it returns the DEEPENED seabed top, so underwater
## structures rest on the real seabed rather than floating at the old shallow height. Mirrors
## multipass_generator._generate_base_terrain's ocean branch exactly.
func _seabed_surface_at(x: float, z: float) -> float:
	if _biome_map == null or not _biome_map.has_method("biome_at"):
		return _terrain_surface_at(x, z)
	if int(_biome_map.biome_at(x, z)) != int(BiomeMap.Biome.OCEAN):
		return _terrain_surface_at(x, z)
	# Ensure the noise instance exists (built lazily by _terrain_surface_at).
	if _surface_noise == null:
		_terrain_surface_at(x, z)
	# OCEAN seabed: sea_level - OCEAN_FLOOR_DEPTH(9) + noise*OCEAN_FLOOR_RELIEF(4); top face +1.
	var noise_val: float = _surface_noise.get_noise_2d(float(floori(x)), float(floori(z)))
	var seabed_y: int = 12 - 9 + int(noise_val * 4.0)  # sea_level - OCEAN_FLOOR_DEPTH + relief
	return float(seabed_y) + 1.0


# ─── Plan 02-07: Structure pre-stamp (do not modify from 02-08.5) ─────────────

## Pre-stamp all structures within ±_PRE_STAMP_RADIUS_M of the world origin.
##
## Uses structures_intersecting_chunk() per chunk in the radius. StudGrid must
## be present as a sibling node of this scene. If StudGrid is null (headless
## test or pre-Phase-1 scene), the stamp is silently skipped.
##
## Toast emission for structure discovery (ui.world.found_*) is wired in
## Plan 02-09 when a BoxArea3D per-structure trigger is implemented. This
## method only performs the placement.
## Read this world's seed from WorldSave (world_meta) into _world_seed and push it into the
## VoxelTerrain generator so the chosen seed actually drives terrain + biomes. Must run in
## _ready before the first _process (chunk streaming) so every generated chunk uses it.
func _apply_world_seed() -> void:
	var raw: Variant = WorldSave.get_world_meta("world_seed")
	if raw is int:
		_world_seed = raw as int
	elif raw is float:
		_world_seed = int(raw)
	# else: keep the 1234 fallback (e.g. legacy worlds with no stored seed).

	# Push into the generator. Its world_seed setter rebuilds the height noise + BiomeMap,
	# so this fully re-seeds terrain generation. Guard every access — headless/test scenes
	# may use a different terrain.tscn or none at all.
	var terrain: Node = get_node_or_null("Terrain")
	if terrain == null:
		return
	var generator: Resource = terrain.get("generator") as Resource
	if generator == null:
		return
	if "world_seed" in generator:
		generator.world_seed = _world_seed


func _pre_stamp_structures_near_spawn() -> void:
	if _structure_placer == null:
		_pre_stamp_done = true
		return
	# Locate StudGrid sibling node; null-safe.
	var stud_grid := get_node_or_null("StudGrid") as StudGrid
	# Even without a StudGrid, run the placer for determinism tests.

	# Defer the heavy work past the first rendered frames. This is CRITICAL: stamping
	# ~340k bricks synchronously in _ready blocked the main thread for several seconds,
	# during which (a) the splash never painted and (b) VoxelTerrain could not mesh or
	# bake collision near spawn — so the spawn-grace timer expired with no ground under
	# the builder and it fell through the world to the bottom (Y≈-64). Yielding here lets
	# the splash show, the loading bar animate, and terrain collision bake while we stamp.
	await get_tree().process_frame
	await get_tree().process_frame

	var chunk_size_m: float = 16.0
	var radius_chunks: int = int(_PRE_STAMP_RADIUS_M / chunk_size_m)

	# Bulk mode: suppress the per-brick `placed` signal during the (huge) pre-stamp so the
	# BrickRenderer doesn't grow its MultiMesh one instance at a time (O(n²) realloc that
	# froze the main thread and left the world an empty sky). A single bulk_changed at
	# end_bulk() triggers one O(n) BrickRenderer resync. Pre-stamped bricks are determini-
	# stic and re-stamped every load, so suppressing `placed` also correctly avoids marking
	# them dirty for persistence.
	if stud_grid != null:
		stud_grid.begin_bulk()

	var total_stamped: int = 0
	var row_count: int = 2 * radius_chunks + 1
	var row_idx: int = 0
	for cx: int in range(-radius_chunks, radius_chunks + 1):
		for cz: int in range(-radius_chunks, radius_chunks + 1):
			var hits: Array = _structure_placer.structures_intersecting_chunk(cx, cz)
			for hit: Variant in hits:
				var hit_dict: Dictionary = hit as Dictionary
				if hit_dict.is_empty():
					continue
				var template: Resource = hit_dict.get("template", null)
				var anchor: Vector3i = hit_dict.get("anchor", Vector3i.ZERO)
				var rotation: int = int(hit_dict.get("rotation", 0))
				if template == null:
					continue
				if stud_grid != null:
					total_stamped += _structure_placer.stamp_template(template, anchor, rotation, stud_grid)
		# Yield every few rows so meshing/collision + the splash bar keep ticking while we
		# stamp the spawn area. The bar tracks terrain chunks; the label shows stamp phase.
		row_idx += 1
		if (row_idx & 1) == 0:
			if _loading_label != null:
				_loading_label.text = "Building the world… %d%%" % int(100.0 * float(row_idx) / float(row_count))
			await get_tree().process_frame

	# End bulk: emits bulk_changed → one O(n) BrickRenderer resync (see begin_bulk above).
	if stud_grid != null:
		stud_grid.end_bulk()
	if _loading_label != null:
		_loading_label.text = "Generating terrain…"

	if total_stamped > 0:
		print_debug("StructurePlacer: pre-stamped %d bricks near spawn." % total_stamped)

	# ─── Plan 02-13: Spawn village NPCs for each stamped village template ────
	# Village templates carry npc_spawns slots (populated by Plan 02-13). For each
	# stamped village template, instantiate one VillageNpc per slot.
	#
	# NPCs use a TIGHTER radius than the structure pre-stamp + a hard count cap.
	# The structure-placement loop above pre-stamps bricks across the full
	# _PRE_STAMP_RADIUS_M (256 m) so the world is visually complete, but
	# instantiating an NPC CharacterBody3D across that whole area would spawn
	# >1500 NPCs (≈57 villages × 3 slots) — far more than can be visible at
	# once and very expensive per-frame for AI + collision.
	# Proper streaming (lazy per-chunk NPC spawn on block_loaded) is tracked
	# as a follow-up phase.
	const _NPC_PRESTAMP_RADIUS_M: float = 64.0
	# Capped low: each village NPC now renders a real ~7-8k-vert figure with an 11 MB texture
	# (was a tinted capsule), so far fewer can be on-screen within the mobile frame budget.
	const _NPC_SPAWN_CAP: int = 12
	var npc_radius_chunks: int = int(_NPC_PRESTAMP_RADIUS_M / chunk_size_m)
	var total_npcs: int = 0
	var npc_cap_reached: bool = false
	for cx_npc: int in range(-npc_radius_chunks, npc_radius_chunks + 1):
		if npc_cap_reached:
			break
		for cz_npc: int in range(-npc_radius_chunks, npc_radius_chunks + 1):
			if npc_cap_reached:
				break
			var hits_npc: Array = _structure_placer.structures_intersecting_chunk(cx_npc, cz_npc)
			for hit_npc: Variant in hits_npc:
				var hit_dict_npc: Dictionary = hit_npc as Dictionary
				if hit_dict_npc.is_empty():
					continue
				var npc_template: Resource = hit_dict_npc.get("template", null)
				var npc_anchor: Vector3i = hit_dict_npc.get("anchor", Vector3i.ZERO)
				if npc_template == null:
					continue
				# Only village templates carry npc_spawns; other templates have empty arrays.
				# Access npc_spawns directly as @export var (BrickTemplate) — Object.get()
				# does not accept a default argument in GDScript 4; use property access.
				var _npc_spawns_arr: Array = npc_template.npc_spawns if "npc_spawns" in npc_template else []
				if not _npc_spawns_arr.is_empty():
					for slot_idx: int in range(npc_template.npc_spawns.size()):
						if total_npcs >= _NPC_SPAWN_CAP:
							npc_cap_reached = true
							break
						spawn_village_npc(npc_template, npc_anchor, slot_idx)
						total_npcs += 1
					if npc_cap_reached:
						break
	if total_npcs > 0:
		print_debug("VillageNpc: spawned %d NPCs (cap %d, radius %dm) — lazy chunk-load streaming TBD." % [total_npcs, _NPC_SPAWN_CAP, int(_NPC_PRESTAMP_RADIUS_M)])

	# Pre-stamp complete — allow the loading splash to fade once terrain has streamed AND the
	# builder has ground under it (else it would reveal a floating builder).
	_pre_stamp_done = true
	if _loaded_chunks_so_far >= _CHUNKS_NEEDED_FOR_READY and _builder_grounded():
		_finish_loading_overlay()


# ─── Plan 02-13: Village NPC spawning (D-09 atmosphere-only inhabitants) ─────

## Instantiate one VillageNpc at the given npc_spawns slot of a village template.
##
## Called by _pre_stamp_structures_near_spawn() after stamp_template completes for
## every stamped village. Also callable from test code for determinism checks.
##
## @param template      BrickTemplate resource carrying npc_spawns metadata.
## @param world_anchor  World-space anchor matching the stamp_template anchor (Vector3i).
## @param slot_index    Index into template.npc_spawns (0-based).
##
## Patrol paths are stored in template-local space; this function converts to world space
## by adding world_anchor (as a Vector3 offset). Seeded determinism: the patrol paths
## themselves are authored as fixed waypoints per template, so the same template stamped
## at the same anchor always produces the same patrol pattern.
##
## Scope boundary (D-09): no combat, no inventory, no interaction — atmosphere only.
## NEVER calls into hostile-mob systems; VillageNpc is dependency-light by design.
func spawn_village_npc(template: Resource, world_anchor: Vector3i, slot_index: int) -> void:
	# Guard: validate slot index.
	# Access npc_spawns as @export var (BrickTemplate) — Object.get() in GDScript 4
	# does not accept a default argument; use direct property access with "in" guard.
	var npc_spawns: Array = template.npc_spawns if "npc_spawns" in template else []
	if slot_index < 0 or slot_index >= npc_spawns.size():
		return

	var slot: Dictionary = npc_spawns[slot_index] as Dictionary

	# Build world-space patrol path from template-local waypoints.
	var local_path: PackedVector3Array = slot.get("patrol_path", PackedVector3Array())
	if local_path.is_empty():
		# Slot has no patrol path — NPC will stand idle at anchor. Still spawn for atmosphere.
		pass

	var path_world: PackedVector3Array = PackedVector3Array()
	for local_wp: Vector3 in local_path:
		path_world.append(Vector3(world_anchor) + local_wp)

	# Determine NPC spawn position: first waypoint if available, else anchor.
	var spawn_pos: Vector3 = path_world[0] if path_world.size() > 0 else Vector3(world_anchor)

	# Instantiate and configure the NPC. add_child() FIRST so the node is in the tree before
	# we touch global_position — setting it off-tree spammed "is_inside_tree() is false"
	# errors (12× per village load). _ready (figure load) runs at add_child with the NPC at
	# origin, which is fine: the figure is positioned locally, then moved by global_position.
	var npc: VillageNpc = VillageNpcScene.instantiate() as VillageNpc
	add_child(npc)
	npc.global_position = spawn_pos
	npc.set_skin_variant(slot.get("skin_variant", "desert"))
	npc.set_patrol_path(path_world)


# ─── Plan 03-10: Hostile mob spawning ────────────────────────────────────────

## Instantiate a hostile mob of the given kind at position.
##
## Validates kind against _HOSTILE_MOB_SCENES (T-03-10: unknown kind → push_warning + null).
## Applies optional params: tier (CubeSlime), variant (Bat), hp carry (bat_vampire).
## Wires the mob's died signal to _on_hostile_died for loot rolling.
##
## Called by:
##   - _on_spawning_should_spawn (Spawning.should_spawn signal handler)
##   - CubeSlime._spawn_children (slime tier split)
##   - Vampire._run_transform_async (transform to bat form)
##
## @param kind      Mob type: "laser_penguin"|"ghost"|"vampire"|"bat"|"bat_vampire"|"cube_slime".
## @param position  World-space spawn position.
## @param params    Optional: {tier: int, variant: String, hp: int}.
## @return          The instantiated mob node, or null if kind is unknown.
func spawn_hostile_mob(kind: String, position: Vector3, params: Dictionary = {}) -> Node:
	if not _HOSTILE_MOB_SCENES.has(kind):
		push_warning("spawn_hostile_mob: unknown kind '%s'" % kind)
		return null
	var mob: Node = _HOSTILE_MOB_SCENES[kind].instantiate()
	add_child(mob)
	if mob is Node3D:
		(mob as Node3D).global_position = position
	if mob.has_method("set_main_scene"):
		mob.set_main_scene(self)
	# Apply kind-specific params.
	if kind == "bat_vampire" and "variant" in mob:
		mob.variant = "vampire"
	if params.has("tier") and "tier" in mob:
		mob.tier = params.get("tier")
	if params.has("variant") and "variant" in mob:
		mob.variant = params.get("variant")
	if params.has("hp") and "_hp_override" in mob:
		mob._hp_override = params.get("hp")
	# Wire loot drop: connect died signal (T-03-10-MB-07: pass death_pos by value).
	if mob.has_signal("died"):
		var death_pos_capture: Vector3 = position
		mob.died.connect(_on_hostile_died.bind(kind, death_pos_capture))
	return mob


## Handler for HostileMob.died — rolls creature_drops loot table.
##
## D-04 filter: only includes bronze keys if world light at death_pos < 0.1 (dim cave).
## Calls spawn_dropped_item for each rolled item per the loot-drop pipeline.
##
## Per T-03-10-MB-07: death_pos is passed by value in the signal connect (not read from
## the mob after queue_free) to avoid invalid-instance access.
##
## @param kind       Mob kind (for future per-creature table lookup — v1 uses one shared table).
## @param death_pos  World-space position of the kill (captured before queue_free).
func _on_hostile_died(kind: String, death_pos: Vector3) -> void:
	# Prefer a per-mob thematic loot table (creature_drops_<kind>.tres) so each creature drops
	# what it is/does — wolf→leather/bone, bat→leather/coal, slime→slime, vampire→treasure, etc.
	# Falls back to the shared creature_drops.tres for kinds without a dedicated table.
	var per_kind: String = "res://src/loot/tables/creature_drops_%s.tres" % kind
	var table: Resource = null
	if ResourceLoader.exists(per_kind):
		table = ResourceLoader.load(per_kind)
	if table == null:
		table = ResourceLoader.load("res://src/loot/tables/creature_drops.tres")
	if table == null:
		push_warning("spawn_hostile_mob: creature_drops table could not be loaded")
		return

	var rng := RandomNumberGenerator.new()
	# Deterministic seed: world_seed ^ chunk ^ table_id (RESEARCH Pattern 4).
	# WorldSave._world_seed is the same constant used by main_scene._world_seed.
	var world_seed: int = _world_seed
	var chunk_coord: Vector3i = Vector3i(
		floori(death_pos.x / 16.0),
		floori(death_pos.y / 16.0),
		floori(death_pos.z / 16.0)
	)
	var table_id: String = table.get("table_id") if "table_id" in table else "creature_drops"
	rng.seed = LootRoller.seed_for_chest(world_seed, chunk_coord, table_id) \
		^ int(death_pos.x) ^ int(death_pos.z) ^ kind.hash()

	var rolled: Array = LootRoller.roll(table, rng)

	# D-04 filter: bronze keys only in dim caves (light_level < 0.1).
	var light_level: float = world_light_at(death_pos)
	for drop: Dictionary in rolled:
		var def_id: String = drop.get("def_id", "")
		# Filter out key_bronze when the death position is lit (D-04 per T-03-10-MB-06).
		if def_id == "key_bronze" and light_level >= 0.1:
			continue
		var count: int = drop.get("count", 1)
		for _i: int in range(count):
			var offset := Vector3(
				randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)
			)
			spawn_dropped_item(def_id, 0, death_pos + offset, true)


## Handler for Spawning.should_spawn signal.
## Delegates to spawn_hostile_mob for the given kind at the given position.
## Called at ~1 Hz per chunk when Spawning._run_spawn_tick() emits should_spawn.
##
## @param kind      Mob kind from Spawning.spawn_kinds list.
## @param position  World-space candidate spawn position (already gate-checked by Spawning).
## Biome → which of the new humanoid hostiles may spawn there (BiomeMap.Biome ints:
## 0 GRASSLAND, 1 DESERT, 2 SNOW, 3 JUNGLE, 4 SAVANNAH, 5 OCEAN). The original mobs
## (bat/ghost/vampire/cube_slime/wolf/laser_penguin) are NOT restricted.
const _BIOME_NEW_MOBS: Dictionary = {
	0: ["zombie"],            # grassland
	1: ["skeleton", "orc"],   # desert
	2: ["skeleton"],          # snow
	3: ["zombie", "goblin"],  # jungle
	4: ["goblin", "orc"],     # savannah
	5: [],                    # ocean — no land humanoids
}
const _NEW_MOB_KINDS: Array[String] = ["zombie", "skeleton", "goblin", "orc"]


func _on_spawning_should_spawn(kind: String, position: Vector3) -> void:
	# Biome-restrict the new humanoid hostiles: if the rolled kind is a new mob that doesn't
	# belong in this biome, remap to one that does (or fall back to a universal bat) so the
	# spawn isn't wasted. Original mobs pass through unchanged.
	if kind in _NEW_MOB_KINDS:
		var biome: int = 0
		if _biome_map != null and _biome_map.has_method("biome_at"):
			biome = int(_biome_map.biome_at(position.x, position.z))
		var allowed: Array = _BIOME_NEW_MOBS.get(biome, [])
		if not (kind in allowed):
			kind = String(allowed[randi() % allowed.size()]) if not allowed.is_empty() else "bat"
	# Ground-snap the spawn Y. Spawning.gd builds candidates at the builder's Y (it has no
	# terrain access), which buries land mobs inside the terrain. Snap to the terrain surface
	# (+0.5 m) so the mob settles onto the ground instead of inside a block. Flying mobs
	# (bat/ghost) are fine spawning a touch above the surface too.
	var grounded := Vector3(position.x, _terrain_surface_at(position.x, position.z) + 0.5, position.z)
	spawn_hostile_mob(kind, grounded)
