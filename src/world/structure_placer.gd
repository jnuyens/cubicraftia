# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# structure_placer.gd — Deterministic blueprint placer for villages, temples,
# shipwrecks, and dungeons.
#
# Plan 03-08b additions:
#   _stamp_chest_slot(template, loot_chest_entry, world_anchor): rolls loot tables
#     deterministically and dispatches main_scene.spawn_chest for each loot_chests entry.
#   _load_structure_table(structure_type) → LootTable | null
#   _load_chest_table(tier) → LootTable | null
#   _world_to_chunk(world_pos) → Vector3i
#
#   stamp_template() now calls the chest-slot pass after brick placement.
#   LootRoller is used for both the tier roll (structure_<type>.tres) and the
#   contents roll (chest_<tier>.tres). Deterministic seed: LootRoller.seed_for_chest().
#   Dungeon final-room override: entry.get("is_final", false) forces tier="diamond"
#   and appends key_diamond to contents (D-04 + T-03-08b-INT-02 mitigation).
#   Locked status: locked = (tier != "regular") per CONTEXT.md D-04.
#
# Thread safety: all hashing + sampling functions are pure (no mutation of class
# state after _init). stamp_template is called from the world-open pre-stamp pass,
# not from godot_voxel worker threads. If Phase 4 needs worker-thread stamping,
# _hash and should_place_structure_at_cell are already side-effect-free.
# (02-PATTERNS.md §"src/world/structure_placer.gd", terrain_generator.gd lines 22-25)
#
# Blueprint cell sizes per CONTEXT.md D-08 rarity tiers:
#   village  = 128 m  (findable, every ~3-5 min of overland exploration)
#   temple   = 192 m  (notable, every ~10-15 min)
#   shipwreck = 128 m  (scattered across ocean biome)
#   dungeon  = 256 m  (rare loot moments, deep underground only)
#
# Spawn-chance gates per D-08 rarity:
#   village  0.60  — frequently encountered
#   temple   0.40  — notable rarity
#   shipwreck 0.75 — ~2-3 per ocean cluster
#   dungeon  0.50  — rare
#
# T-07-01 mitigation: stamp_template guards via BrickRegistry.get_definition(def_id) null
# check — missing bricks emit push_warning and are skipped, not crashed.
# T-07-02 mitigation: pre-stamp radius is bounded to ~10 structures on world-open.
# T-07-04 mitigation: RNG seeded from deterministic hash; all peers compute same results.
#
# References:
#   DOCS.md §2 — v1 generated structures contract
#   02-CONTEXT.md D-07 (variant counts), D-08 (rarity tiers)
#   02-RESEARCH.md §"Pattern 2: Structure placement" lines 504-566

class_name StructurePlacer
extends RefCounted

# Preload BrickTemplate and BiomeMap so class names are resolvable in headless/test mode.
# GDScript in headless mode requires explicit preloads for class_name resolution.
const BrickTemplateScript := preload("res://src/bricks/brick_template.gd")
const BiomeMapScript := preload("res://src/world/biome_map.gd")

# Plan 03-08b: LootRoller preload for chest-slot integration.
const LootRollerScript := preload("res://src/loot/loot_roller.gd")

# ─── Blueprint cell sizes (metres) per CONTEXT.md D-08 ─────────────────────

## One structure at most per blueprint cell of this size (metres per side).
const BLUEPRINT_CELL_M: Dictionary = {
	"village":   128.0,
	"temple":    192.0,
	"shipwreck": 128.0,
	"dungeon":   256.0,
}

## Probability [0..1] that a structure spawns in any given blueprint cell.
const SPAWN_CHANCE: Dictionary = {
	"village":   0.60,
	"temple":    0.40,
	"shipwreck": 0.75,
	"dungeon":   0.50,
}

## Fallback surface Y anchor for above-ground structures, used only when the height
## noise is somehow unavailable. Normal placement samples the real terrain surface per
## structure via _surface_y_at() (see should_place_structure_at_cell), so a stamped
## village floor (local cell Y=0) lands ON the generated ground instead of floating at
## this constant on uneven terrain.
const SURFACE_Y: int = 16

## Deep-underground Y anchor for dungeons. Placement gated to negative Y only.
const DUNGEON_Y: int = -32

## ── Terrain height-map parameters ──────────────────────────────────────────────
## These MUST match multipass_generator.gd exactly so a stamped structure's surface Y
## equals the meshed terrain surface the generator produces (and matches main_scene's
## _terrain_surface_at, which grounds the villagers — so structures and villagers agree).
##   surface_solid_top = int(noise(x, z) * HEIGHT_AMPLITUDE + SEA_LEVEL)
##   anchor_y          = surface_solid_top + 1   (first cell above the solid column; the
##                       same +1 top-face convention _terrain_surface_at uses)
## Noise: Simplex FBM, 4 octaves, lacunarity 2.0, gain 0.5, freq 0.01, seed = world_seed.
const HEIGHT_AMPLITUDE: float = 8.0
const SEA_LEVEL: float = 12.0
const HEIGHT_NOISE_FREQUENCY: float = 0.01

## Template directories per structure type.
const TEMPLATE_DIRS: Dictionary = {
	"village":   "res://assets/templates/villages/",
	"temple":    "res://assets/templates/temples/",
	"shipwreck": "res://assets/templates/shipwrecks/",
	"dungeon":   "res://assets/templates/dungeons/",
}

# ─── Private state ────────────────────────────────────────────────────────────

## World seed driving all placement decisions.
var _world_seed: int = 0

## BiomeMap instance for biome-restriction checks (typed as RefCounted for headless compat).
var _biome_map: RefCounted = null

## Templates indexed by structure type.
## Dictionary[String, Array[BrickTemplate]]
var _templates_by_type: Dictionary = {}

## BrickRegistry autoload node (set in _init; used in stamp_template).
var _brick_registry: Node = null

## Terrain height-map noise. Mirrors multipass_generator's base-terrain noise exactly so the
## per-structure surface Y matches the meshed ground. Immutable after _init(); get_noise_2d()
## is pure, so _surface_y_at() is deterministic (same seed -> same anchor) and thread-safe.
var _height_noise: FastNoiseLite = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Construct a StructurePlacer with the given world seed and BiomeMap.
## Loads all templates from disk immediately.
func _init(world_seed: int, biome_map: RefCounted) -> void:
	_world_seed = world_seed
	_biome_map = biome_map
	# Resolve BrickRegistry from the scene tree at init time.
	# In headless tests, BrickRegistry may not be an autoload; fall back gracefully.
	if Engine.has_singleton("BrickRegistry"):
		_brick_registry = Engine.get_singleton("BrickRegistry")
	_build_height_noise()
	_load_templates()


## Build the terrain height noise. Same shape/params as multipass_generator._rebuild_noise
## and main_scene._terrain_surface_at so all three agree on the surface column.
func _build_height_noise() -> void:
	_height_noise = FastNoiseLite.new()
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_height_noise.fractal_octaves = 4
	_height_noise.fractal_lacunarity = 2.0
	_height_noise.fractal_gain = 0.5
	_height_noise.frequency = HEIGHT_NOISE_FREQUENCY
	_height_noise.seed = _world_seed


## Load all templates from assets/templates/{type}/ into _templates_by_type.
## Validates each template's brick IDs against BrickRegistry on load.
func _load_templates() -> void:
	for structure_type: String in TEMPLATE_DIRS.keys():
		var dir_path: String = TEMPLATE_DIRS[structure_type]
		var dir := DirAccess.open(dir_path)
		var templates: Array = []
		if dir == null:
			push_warning("StructurePlacer._load_templates: cannot open '%s' — type '%s' will have no templates." % [dir_path, structure_type])
			_templates_by_type[structure_type] = templates
			continue
		for file_name: String in dir.get_files():
			if not file_name.ends_with(".tres"):
				continue
			var path: String = dir_path + file_name
			var tmpl: Resource = load(path) as Resource
			if tmpl == null:
				push_error("StructurePlacer._load_templates: '%s' did not load as BrickTemplate." % path)
				continue
			# T-07-01 mitigation: validate brick IDs at boot.
			if _brick_registry != null:
				var errors: Array = tmpl.validate(_brick_registry)
				for err: String in errors:
					push_error("StructurePlacer._load_templates: template '%s' validation error: %s" % [file_name, err])
			templates.append(tmpl)
		_templates_by_type[structure_type] = templates

# ─── Public API ───────────────────────────────────────────────────────────────

## Deterministically decide whether a structure of the given type spawns at the
## given blueprint cell coordinates.
##
## Returns a Dictionary with keys {"template", "anchor", "rotation"} if a
## structure should be placed, or an empty Dictionary if not.
##
## Pure function: no side effects, safe to call from any thread.
func should_place_structure_at_cell(structure_type: String,
                                    blueprint_cell_x: int,
                                    blueprint_cell_z: int) -> Dictionary:
	if not BLUEPRINT_CELL_M.has(structure_type):
		push_warning("StructurePlacer.should_place_structure_at_cell: unknown type '%s'" % structure_type)
		return {}

	var templates: Array = _templates_by_type.get(structure_type, [])
	if templates.is_empty():
		return {}

	# ── Deterministic hash ───────────────────────────────────────────────────
	# Mix world_seed × type × cell_x × cell_z via Knuth multiplicative hashing.
	# All arithmetic is bitwise-safe in GDScript int (64-bit signed).
	var h: int = _world_seed
	h = (h * 2654435761) ^ structure_type.hash()
	h = (h * 2654435761) ^ blueprint_cell_x
	h = (h * 2654435761) ^ blueprint_cell_z
	# Ensure positive for bitmask operations.
	h = h & 0x7FFFFFFFFFFFFFFF

	# ── Spawn-chance gate ────────────────────────────────────────────────────
	var chance: float = SPAWN_CHANCE.get(structure_type, 0.5)
	var roll: float = float(h & 0xFFFFFF) / float(0xFFFFFF)
	if roll > chance:
		return {}

	# ── Variant selection ────────────────────────────────────────────────────
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var variant_idx: int = rng.randi() % templates.size()
	var template: Resource = templates[variant_idx]

	# ── Anchor within blueprint cell ─────────────────────────────────────────
	var cell_size: float = BLUEPRINT_CELL_M[structure_type]
	var base_x: float = float(blueprint_cell_x) * cell_size
	var base_z: float = float(blueprint_cell_z) * cell_size
	# Offset within the cell, leaving a 10% margin from the edge.
	var margin: float = cell_size * 0.1
	var usable: float = cell_size - margin * 2.0
	var anchor_x: int = int(base_x + margin + rng.randf() * usable)
	var anchor_z: int = int(base_z + margin + rng.randf() * usable)

	# ── Y anchor per type ────────────────────────────────────────────────────
	# Dungeons stay at the fixed deep-underground depth. Above-ground structures anchor to
	# the REAL terrain surface at the structure's XZ (a pure noise function — no VoxelTool),
	# so house-brick floors (local cell Y=0) rest on the generated ground on uneven terrain
	# instead of floating/sinking at the old placeholder SURFACE_Y.
	var anchor_y: int = DUNGEON_Y if structure_type == "dungeon" else _surface_y_at(anchor_x, anchor_z)

	# ── Biome-restriction gate ────────────────────────────────────────────────
	if _biome_map != null and not template.allowed_biomes.is_empty():
		var biome: int = int(_biome_map.biome_at(float(anchor_x), float(anchor_z)))
		if not template.allowed_biomes.has(biome):
			return {}

	# ── Rotation (0..3 = 0°, 90°, 180°, 270°) ───────────────────────────────
	var rotation: int = int((h >> 24) & 3)

	return {
		"template": template,
		"anchor":   Vector3i(anchor_x, anchor_y, anchor_z),
		"rotation": rotation,
	}


## Stamp a template into the StudGrid at the given anchor + rotation.
## Returns the count of bricks successfully placed.
##
## Rotation is 0..3 (0° / 90° / 180° / 270° around Y axis).
## Phase 2 collapses unknown brick IDs to push_warning + skip (T-07-01 mitigation).
## terrain_overrides are intentionally no-op in Phase 2 (Phase 4 wires VoxelTool).
##
## Plan 03-08b: After the brick loop, iterates template.loot_chests and calls
## _stamp_chest_slot for each entry, rolling loot deterministically and spawning
## ChestEntity nodes via main_scene.spawn_chest.
func stamp_template(template: Resource, anchor: Vector3i, rotation: int,
                    stud_grid: StudGrid) -> int:
	if stud_grid == null:
		push_error("StructurePlacer.stamp_template: stud_grid is null.")
		return 0
	var stamped: int = 0
	for entry: Variant in template.bricks:
		var d: Dictionary = entry as Dictionary
		if not d.has("def_id") or not d.has("cell"):
			push_warning("StructurePlacer.stamp_template: malformed brick entry (missing def_id or cell).")
			continue
		var def_id: String = str(d["def_id"])
		var local_cell: Vector3i = d["cell"] as Vector3i
		var colour_index: int = int(d.get("colour_index", -1))

		# T-07-01: validate brick ID; skip if not found.
		if _brick_registry != null:
			var def = _brick_registry.get_definition(def_id)
			if def == null:
				push_warning("StructurePlacer.stamp_template: def_id '%s' not in BrickRegistry — skipped." % def_id)
				continue
			var world_cell: Vector3i = anchor + _rotate_cell(local_cell, rotation, template.bbox)
			# StudGrid.place signature (Phase 1): place(anchor_cell, definition) -> bool
			# Phase 2 extends it with colour_index; for now we call the existing API.
			# The colour is stored in WorldSave's brick record separately in Phase 3.
			if stud_grid.place(world_cell, def):
				stamped += 1
		else:
			# No BrickRegistry in headless test mode — place without validation.
			var world_cell: Vector3i = anchor + _rotate_cell(local_cell, rotation, template.bbox)
			stamped += 1  # count as placed (test-only path, no StudGrid mutated)

	# ── Plan 03-08b: Chest-slot pass ─────────────────────────────────────────
	# After all bricks are placed, spawn chests at each loot_chests slot.
	# Uses the template's structure_type to resolve the appropriate loot tables.
	# Access loot_chests directly as @export var (defined in BrickTemplate).
	var loot_chests: Array = []
	if template != null and "loot_chests" in template:
		loot_chests = template.loot_chests
	for chest_entry: Variant in loot_chests:
		var chest_dict: Dictionary = chest_entry as Dictionary
		_stamp_chest_slot(template, chest_dict, anchor)

	return stamped


## Return all {template, anchor, rotation} records for structures that overlap
## the given chunk (chunk_x, chunk_z in voxel-chunk coordinates, chunk size 16m).
##
## Iterates all four structure types and their blueprint cells that cover this chunk.
func structures_intersecting_chunk(chunk_x: int, chunk_z: int) -> Array:
	var results: Array = []
	const CHUNK_SIZE_M: float = 16.0

	for structure_type: String in BLUEPRINT_CELL_M.keys():
		var cell_size: float = BLUEPRINT_CELL_M[structure_type]
		# World-space position of the chunk's bottom-left corner.
		var chunk_world_x: float = float(chunk_x) * CHUNK_SIZE_M
		var chunk_world_z: float = float(chunk_z) * CHUNK_SIZE_M

		# Which blueprint cells could overlap this chunk?
		# A structure anchored anywhere in blueprint cell (bx, bz) could extend into
		# adjacent chunks via its bbox. We check the cell containing the chunk plus
		# one cell in each direction (conservative overlap guard).
		var base_bx: int = int(chunk_world_x / cell_size)
		var base_bz: int = int(chunk_world_z / cell_size)

		for dbx: int in [-1, 0, 1]:
			for dbz: int in [-1, 0, 1]:
				var bx: int = base_bx + dbx
				var bz: int = base_bz + dbz
				var result: Dictionary = should_place_structure_at_cell(structure_type, bx, bz)
				if not result.is_empty():
					results.append(result)
	return results

# ─── Private helpers ──────────────────────────────────────────────────────────

# ── Plan 03-08b: Chest-slot helpers ──────────────────────────────────────────

## Roll loot and spawn a ChestEntity for one loot_chests entry.
##
## Flow (two-step roll per Plan 03-08a interface):
##   1. Load structure_<type>.tres → roll chest tier (def_id like "chest_bronze").
##   2. Strip "chest_" prefix → tier string ("regular" | "bronze" | ...).
##   3. Load chest_<tier>.tres → roll contents.
##   4. If entry.is_final == true: force tier="diamond" + append key_diamond.
##   5. Call main_scene.spawn_chest(tier, world_pos, contents, locked).
##
## Determinism: seed = LootRoller.seed_for_chest(world_seed, chunk_coord, table_id).
## Locked status: locked = (tier != "regular") per CONTEXT.md D-04.
## T-03-08b-INT-04: if main_scene not found → push_warning + return (graceful drop).
func _stamp_chest_slot(template: Resource, chest_entry: Dictionary,
                       world_anchor: Vector3i) -> void:
	# Resolve world position from template-local cell.
	var local_cell: Vector3i = chest_entry.get("cell", Vector3i.ZERO) as Vector3i
	var world_pos: Vector3 = Vector3(world_anchor) + Vector3(local_cell)
	var chunk_coord: Vector3i = _world_to_chunk(world_pos)

	# Determine structure type (e.g. "mineshaft", "jungle_temple").
	# BrickTemplate.structure_type field added by Plan 03-08b.
	var structure_type: String = ""
	if template != null and "structure_type" in template:
		structure_type = str(template.structure_type)
	if structure_type.is_empty():
		# Legacy Phase 2 templates have no structure_type — skip loot rolling silently.
		# Backfilling templates is tracked as a follow-up.
		return

	# Step 1 — Roll chest tier from the structure loot table.
	var structure_table: Resource = _load_structure_table(structure_type)
	var tier: String = ""

	if structure_table != null:
		# Resolve table_id from the LootTable resource (@export var table_id: String).
		var struct_table_id: String = structure_type
		if "table_id" in structure_table:
			struct_table_id = str(structure_table.table_id)
		var tier_seed: int = LootRollerScript.seed_for_chest(_world_seed, chunk_coord, struct_table_id)
		var tier_rng := RandomNumberGenerator.new()
		tier_rng.seed = tier_seed
		var tier_rolls: Array = LootRollerScript.roll(structure_table, tier_rng)
		if not tier_rolls.is_empty():
			# def_id is e.g. "chest_bronze" — strip the "chest_" prefix.
			var raw_tier: String = str(tier_rolls[0].get("def_id", ""))
			tier = raw_tier.replace("chest_", "")  # "regular" | "bronze" | "silver" | "gold" | "diamond"
	# Fallback: use the hint stored in the template entry itself (Phase 2 authored).
	if tier.is_empty():
		tier = chest_entry.get("chest_type", "regular")

	# Step 2 — Dungeon final-room override (T-03-08b-INT-02 + D-04).
	var is_final: bool = chest_entry.get("is_final", false)
	if is_final:
		tier = "diamond"

	# Validate tier against known SLOT_COUNTS (mirrors ChestEntity._ready() guard).
	var valid_tiers: Array = ["regular", "bronze", "silver", "gold", "diamond"]
	if not valid_tiers.has(tier):
		push_warning("StructurePlacer._stamp_chest_slot: invalid tier '%s' — using 'regular'." % tier)
		tier = "regular"

	# Step 3 — Roll chest contents from the tier loot table.
	var contents: Array = []
	var contents_table: Resource = _load_chest_table(tier)
	if contents_table != null:
		# Resolve table_id from the LootTable resource (@export var table_id: String).
		var chest_table_id: String = "chest_" + tier
		if "table_id" in contents_table:
			chest_table_id = str(contents_table.table_id)
		var contents_seed: int = LootRollerScript.seed_for_chest(_world_seed, chunk_coord, chest_table_id)
		var contents_rng := RandomNumberGenerator.new()
		contents_rng.seed = contents_seed
		contents = LootRollerScript.roll(contents_table, contents_rng)

	# Step 4 — Append guaranteed diamond key for dungeon final rooms (D-04).
	if is_final:
		contents.append({"def_id": "key_diamond", "count": 1})

	# Step 5 — Dispatch to main_scene.spawn_chest (T-03-08b-INT-04: null-safe).
	var main_scene: Node = null
	if Engine.get_main_loop() != null and Engine.get_main_loop().root != null:
		main_scene = Engine.get_main_loop().root.get_first_child_in_group("main_scene") \
			if Engine.get_main_loop().root.has_method("get_first_child_in_group") \
			else null
		if main_scene == null:
			# Use scene tree group lookup via SceneTree.get_first_node_in_group.
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
			if tree != null:
				main_scene = tree.get_first_node_in_group("main_scene")

	if main_scene == null or not main_scene.has_method("spawn_chest"):
		push_warning("StructurePlacer._stamp_chest_slot: main_scene not found or lacks spawn_chest — chest at %s dropped." % str(world_pos))
		return

	var locked: bool = (tier != "regular")  # bronze+ tiers spawn locked per D-04.
	main_scene.spawn_chest(tier, world_pos, contents, locked)


## Load the structure loot table for the given structure type.
## Returns null (with push_warning) if the .tres file does not exist.
func _load_structure_table(structure_type: String) -> Resource:
	var path: String = "res://src/loot/tables/structure_" + structure_type + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("StructurePlacer._load_structure_table: no table at '%s'." % path)
		return null
	return ResourceLoader.load(path)


## Load the chest contents loot table for the given tier.
## Returns null (with push_warning) if the .tres file does not exist.
func _load_chest_table(tier: String) -> Resource:
	var path: String = "res://src/loot/tables/chest_" + tier + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("StructurePlacer._load_chest_table: no table at '%s'." % path)
		return null
	return ResourceLoader.load(path)


## Convert a world-space position to a chunk coordinate (chunk size = 16 m).
## Mirrors ChestEntity._world_to_chunk and Spawning autoload chunk convention.
func _world_to_chunk(world_pos: Vector3) -> Vector3i:
	const CHUNK_SIZE_M: float = 16.0
	return Vector3i(
		int(floor(world_pos.x / CHUNK_SIZE_M)),
		int(floor(world_pos.y / CHUNK_SIZE_M)),
		int(floor(world_pos.z / CHUNK_SIZE_M))
	)


## Real terrain surface Y at world (x, z) — the anchor a stamped above-ground structure
## sits on so its floor (local cell Y=0) rests on the generated ground.
##
## Replicates multipass_generator._surface_top_for (land branch) plus main_scene's
## _terrain_surface_at: solid_top = int(noise * HEIGHT_AMPLITUDE + SEA_LEVEL); the returned
## anchor is solid_top + 1 (first cell above the solid column, the same +1 top-face convention
## the villager grounding uses), so structures and villagers agree at the anchor column.
##
## Pure function of world_seed + (x, z) — deterministic (same seed -> same anchor) and
## thread-safe (read-only noise). Floors x/z to the integer column the generator sampled,
## avoiding an off-by-one at column boundaries. OCEAN seabed deepening is intentionally NOT
## applied: above-ground structures spawn on land (biome gate / ocean structures are landmarks,
## not stamped brick villages), so the plain land height-map is the correct anchor.
func _surface_y_at(x: int, z: int) -> int:
	if _height_noise == null:
		_build_height_noise()
		if _height_noise == null:
			return SURFACE_Y  # extreme fallback (should never happen)
	var noise_val: float = _height_noise.get_noise_2d(float(x), float(z))
	var solid_top: int = int(noise_val * HEIGHT_AMPLITUDE + SEA_LEVEL)
	return solid_top + 1


## Deterministic hash for (world_seed, structure_type, cell_x, cell_z).
## Kept as a standalone helper so tests can call it directly.
func _hash(world_seed: int, structure_type: String,
           cell_x: int, cell_z: int) -> int:
	var h: int = world_seed
	h = (h * 2654435761) ^ structure_type.hash()
	h = (h * 2654435761) ^ cell_x
	h = (h * 2654435761) ^ cell_z
	return h & 0x7FFFFFFFFFFFFFFF


## Rotate a template-local cell by 0..3 quarter-turns around the bbox centre (Y axis).
## Template is authored at rotation 0; rotation 1 = 90° clockwise, etc.
func _rotate_cell(local_cell: Vector3i, rotation: int, bbox: AABB) -> Vector3i:
	if rotation == 0:
		return local_cell
	# Centre of the bounding box (integer approximation).
	var cx: int = int(bbox.size.x / 2.0)
	var cz: int = int(bbox.size.z / 2.0)
	# Translate to bbox-centre, rotate, translate back.
	var lx: int = local_cell.x - cx
	var lz: int = local_cell.z - cz
	var rx: int = lx
	var rz: int = lz
	for _i in range(rotation):
		var tmp_x: int = rx
		rx = -rz
		rz = tmp_x
	return Vector3i(rx + cx, local_cell.y, rz + cz)
