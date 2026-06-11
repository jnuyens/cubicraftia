# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# multipass_generator.gd — VoxelGeneratorMultipassCB for mineshaft generation.
#
# Extends VoxelGeneratorMultipassCB (experimental in godot_voxel at addon commit 4a9d311).
# Two passes:
#   Pass 0 (extent 0): base terrain — delegates the column height-map logic to
#                       the same noise + biome algorithm as terrain_generator.gd.
#                       No neighbour access needed; each column is independent.
#   Pass 1 (extent 2): mineshaft corridor carving — picks one of the 5 BrickTemplate
#                       pieces and carves terrain_overrides into the voxel column.
#                       Extent 2 allows corridor pieces up to 12 m wide to write
#                       across chunk borders (chunk = 16 m, extent 2 = 2 chunks reach).
#
# Thread safety: VoxelGeneratorMultipassCB runs _generate_pass from a godot_voxel
# worker thread. The same rules as terrain_generator.gd lines 22-35 apply:
#   - FastNoiseLite get_noise_*() calls are pure; safe from any thread.
#   - BiomeMap noise reads are pure; safe from any thread.
#   - _pieces is built in _init() and never mutated after; safe to read from workers.
#   - VoxelToolMultipassGenerator is NOT stored as a member variable; only valid during
#     the _generate_pass call (per MULTIPASS-NOTE.md API contract + class XML doc).
#   - StudGrid / Node tree mutations are always deferred to the main thread via
#     call_deferred (T-08-01 mitigation — STRIDE threat register).
#
# VoxelToolMultipassGenerator API (from doc/classes/VoxelToolMultipassGenerator.xml):
#   - get_main_area_min() -> Vector3i  — lower corner of the main area in voxels
#   - get_main_area_max() -> Vector3i  — upper corner of the main area in voxels (exclusive)
#   - get_editable_area_min() / get_editable_area_max() — extended area (for pass 1 extent=2)
#   - set_voxel(pos: Vector3i, v: int) — write a voxel at world-space position
#   Inherits from VoxelTool; channel is set via VoxelTool.channel property.
#
# RESEARCH Pattern 2(a) — VoxelGeneratorMultipassCB (02-RESEARCH.md lines 504-515):
#   "Use set_pass_count(2) + set_pass_extent_blocks(1, 2) to declare two passes."
#
# Column-based generation: _generate_pass is called ONCE per column of blocks.
# A "column" spans the full height of the generator's range (column_height_blocks).
# The min/max area gives the XZ extent × full Y range of this column.
#
# Mineshaft depth gate (CONTEXT.md D-08): mineshafts only spawn at Y < -8.
# We check if the column's Y range covers any deep area (main_area_min.y < -8).
#
# References:
#   02-MULTIPASS-NOTE.md — multipass-available decision (Plan 02-02 spike)
#   02-CONTEXT.md D-07 — ~5 corridor/junction pieces; D-08 — mineshafts common at depth
#   02-RESEARCH.md §"Pattern 2(a)" — VoxelGeneratorMultipassCB description
#   02-RESEARCH.md §"Pitfall 1" — two-grid wall (corridor walls = TERRAIN voxels)
#   src/world/terrain_generator.gd — base terrain logic replicated in pass 0
#   src/world/structure_placer.gd — _hash() and _rotate_cell() patterns reused here

class_name MineshaftGenerator
extends VoxelGeneratorMultipassCB

# ─── Constants ────────────────────────────────────────────────────────────────

## AIR voxel ID (must match terrain.tscn VoxelBlockyLibrary index 0).
const AIR_ID: int = 0

## GRASS voxel ID (GRASSLAND_FOREST surface — index 1).
const GRASS_ID: int = 1

## SAND voxel ID (DESERT / OCEAN seabed — index 2).
const SAND_ID: int = 2

## SNOW voxel ID (SNOW surface — index 3).
const SNOW_ID: int = 3

## STONE voxel ID (deep underground, all biomes — index 4).
const STONE_ID: int = 4

## SANDSTONE voxel ID (DESERT sub-surface — index 5).
const SANDSTONE_ID: int = 5

## ICE voxel ID (SNOW sub-surface — index 6).
const ICE_ID: int = 6

## WATER voxel ID (OCEAN water column — index 7).
const WATER_ID: int = 7

## JUNGLE_GRASS voxel ID (JUNGLE surface — index 8).
const JUNGLE_GRASS_ID: int = 8

## SAVANNAH_GRASS voxel ID (SAVANNAH surface — index 9).
const SAVANNAH_GRASS_ID: int = 9

## WOOD_LOG voxel ID (tree column — index 10).
const WOOD_LOG_ID: int = 10

## DIRT voxel ID (sub-surface for GRASSLAND/JUNGLE/SAVANNAH — index 11).
const DIRT_ID: int = 11

## LEAVES voxel ID (tree canopy — index 12; must match terrain.tscn VoxelBlockyLibrary).
const LEAVES_ID: int = 12

## Number of dirt/biome-material layers below surface before transitioning to stone.
const DIRT_LAYERS: int = 3

## Y-voxel depth threshold: mineshafts only spawn in areas where Y < MINESHAFT_DEPTH_GATE.
## Matches CONTEXT.md D-08 "deeper stone layers" + plan spec "Y < -8".
const MINESHAFT_DEPTH_GATE: int = -8

## Probability (0..1) that a mineshaft piece spawns at any given deep chunk column.
## CONTEXT.md D-08: mineshafts are "common while digging deeper stone layers".
## T-08-02: tunable; if Tier-3 benchmark shows perf hit, reduce this constant.
const MINESHAFT_SPAWN_CHANCE: float = 0.35

## Per-CELL tree spawn probabilities (0..1). Trees are placed at most one per
## TREE_CELL×TREE_CELL cell at a deterministic jittered column (see _generate_trees_pass),
## which guarantees a minimum spacing between trunks so their 5-wide canopies no longer
## merge into solid walls. Per-cell (not per-column), so these are much higher than the
## old per-column values: grassland reads as scattered solo trees, jungle as denser woodland.
const TREE_SPAWN_CHANCE_GRASSLAND: float = 0.40
const TREE_SPAWN_CHANCE_JUNGLE: float = 0.72

## Tree placement cell size in voxels. One candidate tree per cell, placed at a
## hash-jittered column kept to the cell's centre band so adjacent-cell trunks stay
## >= ~5 voxels apart (canopy half-width is 2, so 5 apart = canopies just touch, never wall).
const TREE_CELL: int = 7

## A guaranteed starter tree is forced at this column (a few voxels +X from the
## world origin/spawn) regardless of biome density, so the FTUE "mine a tree" step
## is always completable even when the spawn biome has no nearby trees.
const STARTER_TREE_X: int = 8
const STARTER_TREE_Z: int = 0

## Trunk height range (inclusive). Picked deterministically per tree.
const TREE_TRUNK_MIN: int = 4
const TREE_TRUNK_MAX: int = 6

## Leaf canopy half-radius in XZ (total width = 2*LEAF_RADIUS+1 = 5 voxels for radius=2).
## Canopy spans from trunk_top-1 to trunk_top+1 in Y (3 layers).
const LEAF_RADIUS: int = 2

## Chunk size in voxels (16 is the godot_voxel default; must match terrain.tscn).
const CHUNK_SIZE: int = 16

## Paths to the 5 mineshaft BrickTemplate .tres pieces.
const PIECE_PATHS: Array[String] = [
	"res://assets/templates/mineshafts/corridor_straight.tres",
	"res://assets/templates/mineshafts/corridor_t_junction.tres",
	"res://assets/templates/mineshafts/corridor_cross.tres",
	"res://assets/templates/mineshafts/corridor_dead_end.tres",
	"res://assets/templates/mineshafts/corridor_room.tres",
]

# ─── Exports ──────────────────────────────────────────────────────────────────

## World seed — drives all noise and mineshaft placement decisions.
## Changing this rebuilds noise and BiomeMap (same pattern as terrain_generator.gd).
@export var world_seed: int = 1234:
	set(v):
		world_seed = v
		if _noise != null:
			_noise.seed = world_seed
		_biome_map = BiomeMap.new(world_seed)

## Terrain height amplitude in voxels (± from sea_level).
@export var height_amplitude: float = 8.0

## Sea level in voxels (centre of the height range).
@export var sea_level: int = 12

## Noise frequency for the base terrain layer.
@export var noise_frequency: float = 0.01:
	set(v):
		noise_frequency = v
		if _noise != null:
			_noise.frequency = noise_frequency

# ─── Private state ────────────────────────────────────────────────────────────

## FastNoiseLite for base terrain height-map (same algorithm as terrain_generator.gd).
var _noise: FastNoiseLite

## BiomeMap instance seeded from world_seed. Immutable after _init().
var _biome_map: BiomeMap

## Loaded mineshaft BrickTemplate pieces. Loaded at _init(); never mutated.
var _pieces: Array = []

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _init() -> void:
	# Build noise (mirrors terrain_generator._rebuild_noise pattern).
	_rebuild_noise()
	# Build BiomeMap.
	_biome_map = BiomeMap.new(world_seed)
	# Load the 5 BrickTemplate pieces. Done once at boot; immutable after _init().
	_load_pieces()
	# Configure two passes:
	#   Pass 0: extent 0 (no cross-chunk reach — height-map is per-column)
	#   Pass 1: extent 2 (reach up to 2 chunks for mineshaft corridor pieces up to 12 m)
	# Note: set_pass_count must be called BEFORE set_pass_extent_blocks.
	# Per XML doc: first pass extent is always 0; extent > 0 only valid for pass index >= 1.
	pass_count = 2
	set_pass_extent_blocks(1, 2)


func _rebuild_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5
	_noise.frequency = noise_frequency
	_noise.seed = world_seed


func _load_pieces() -> void:
	for path in PIECE_PATHS:
		var res = load(path)
		if res == null:
			push_warning("MineshaftGenerator: failed to load piece at %s" % path)
			continue
		_pieces.append(res)
	if _pieces.is_empty():
		push_warning("MineshaftGenerator: no mineshaft pieces loaded — mineshafts will not spawn.")


# ─── VoxelGeneratorMultipassCB override ────────────────────────────────────────

## Called once per pass per column of blocks (from a godot_voxel worker thread).
## voxel_tool: VoxelToolMultipassGenerator — do NOT store; only valid during this call.
## pass_index: 0 = base terrain; 1 = mineshaft carving + tree placement.
func _generate_pass(voxel_tool: VoxelToolMultipassGenerator, pass_index: int) -> void:
	if pass_index == 0:
		_generate_base_terrain(voxel_tool)
	elif pass_index == 1:
		_generate_mineshaft_pass(voxel_tool)
		_generate_trees_pass(voxel_tool)


## Tell godot_voxel which VoxelBuffer channels this generator writes.
## CHANNEL_TYPE_BIT = 1 << 0 = 1 (the TYPE channel used by VoxelMesherBlocky).
func _get_used_channels_mask() -> int:
	return 1


# ─── Pass 0: base terrain ─────────────────────────────────────────────────────

## Generate height-map terrain for a column of blocks.
## Mirrors terrain_generator.gd _generate_block logic, adapted for the multipass API.
## VoxelToolMultipassGenerator.get_main_area_min/max gives the column's full Y range.
## We iterate all XYZ voxels within [area_min, area_max) and set them by height-map.
func _generate_base_terrain(voxel_tool: VoxelToolMultipassGenerator) -> void:
	var area_min: Vector3i = voxel_tool.get_main_area_min()
	var area_max: Vector3i = voxel_tool.get_main_area_max()

	# Height-map pass per (x, z) column within this block column.
	for x: int in range(area_min.x, area_max.x):
		for z: int in range(area_min.z, area_max.z):
			var world_x: float = float(x)
			var world_z: float = float(z)

			var noise_val: float = _noise.get_noise_2d(world_x, world_z)
			var surface_y: int = int(noise_val * height_amplitude + float(sea_level))

			var biome: BiomeMap.Biome = _biome_map.biome_at(world_x, world_z)
			var surface_id: int = _surface_block_for(biome)

			for y: int in range(area_min.y, area_max.y):
				var voxel_id: int
				if y > surface_y:
					voxel_id = AIR_ID  # above surface
				elif y == surface_y:
					voxel_id = surface_id  # surface layer
				else:
					var depth_below_surface: int = surface_y - y
					voxel_id = _underground_block_for(biome, depth_below_surface)
				voxel_tool.set_voxel(Vector3i(x, y, z), voxel_id)

			# Ocean water column: fill from surface+1 to sea_level with water.
			if biome == BiomeMap.Biome.OCEAN:
				for wy: int in range(surface_y + 1, sea_level + 1):
					if wy >= area_min.y and wy < area_max.y:
						voxel_tool.set_voxel(Vector3i(x, wy, z), WATER_ID)


# ─── Pass 1: mineshaft carving ────────────────────────────────────────────────

## Carve mineshaft corridors into deep-stone columns (pass_index == 1, extent 2).
## For each column, check if any part of it is deep enough for mineshafts.
## Pick a piece via deterministic hash, stamp terrain_overrides into voxels.
## StudGrid brick placements (supports, lanterns, ladders) are queued via call_deferred
## to the main thread (T-08-01 — worker threads must not mutate the Node tree).
func _generate_mineshaft_pass(voxel_tool: VoxelToolMultipassGenerator) -> void:
	if _pieces.is_empty():
		return

	var area_min: Vector3i = voxel_tool.get_main_area_min()
	var area_max: Vector3i = voxel_tool.get_main_area_max()

	# Depth gate: mineshafts only in deep areas.
	# If the column's minimum Y is at or above the gate, skip this column entirely.
	if area_min.y >= MINESHAFT_DEPTH_GATE:
		return

	# Use the column's XZ centre as the chunk coordinate for hashing.
	# This gives one deterministic decision per column (not per individual chunk).
	var col_x: int = (area_min.x + area_max.x) / 2 / CHUNK_SIZE
	var col_z: int = (area_min.z + area_max.z) / 2 / CHUNK_SIZE
	var col_y: int = area_min.y / CHUNK_SIZE

	# Deterministic hash: same Knuth multiplicative mix as structure_placer._hash.
	var h: int = _hash_chunk(world_seed, col_x, col_y, col_z)

	# Spawn-chance roll: only MINESHAFT_SPAWN_CHANCE of eligible deep columns host a piece.
	var roll: float = float(h & 0xFFFF) / float(0xFFFF)
	if roll > MINESHAFT_SPAWN_CHANCE:
		return

	# Pick piece and rotation deterministically from the hash.
	var piece_index: int = (h >> 8) % _pieces.size()
	var rotation: int = (h >> 24) & 3
	var piece = _pieces[piece_index]

	# Stamp terrain_overrides into the voxel column (carve corridors into stone).
	# We place the piece's origin at area_min to stamp within the current column.
	_stamp_terrain_overrides(piece, area_min, rotation, area_min, area_max, voxel_tool)

	# Queue StudGrid brick placements (supports, ladders, lanterns) to main thread.
	# The call_deferred ensures StudGrid mutations happen on the main thread only.
	# Phase 4 will convert this to a properly queued command; for Phase 2 the deferred
	# call emits a push_warning trace confirming the placement was scheduled.
	call_deferred("_queue_stud_bricks", piece, area_min, rotation)


## Write a piece's terrain_overrides into the voxel column.
## Applies optional Y-axis rotation (0..3 quarter-turns around the bbox centre).
## Only writes cells that land within the editable area bounds.
## stamp_origin: world-space offset of the piece's local (0,0,0) cell.
func _stamp_terrain_overrides(
		piece: Resource,
		stamp_origin: Vector3i,
		rotation: int,
		area_min: Vector3i,
		area_max: Vector3i,
		voxel_tool: VoxelToolMultipassGenerator) -> void:
	var bbox: AABB = piece.bbox
	for override in piece.terrain_overrides:
		var local_cell: Vector3i = override["cell"]
		var rotated_cell: Vector3i = _rotate_cell(local_cell, rotation, bbox)
		var world_pos: Vector3i = Vector3i(
			stamp_origin.x + rotated_cell.x,
			stamp_origin.y + rotated_cell.y,
			stamp_origin.z + rotated_cell.z)
		# Only write if within the editable area (including the extent=2 reach).
		var editable_min: Vector3i = voxel_tool.get_editable_area_min()
		var editable_max: Vector3i = voxel_tool.get_editable_area_max()
		if world_pos.x >= editable_min.x and world_pos.x < editable_max.x and \
		   world_pos.y >= editable_min.y and world_pos.y < editable_max.y and \
		   world_pos.z >= editable_min.z and world_pos.z < editable_max.z:
			voxel_tool.set_voxel(world_pos, override["voxel_id"])


## Pass 1: tree placement — scatter wood_log trunks + leaf canopies on grassland/jungle.
##
## Runs after _generate_mineshaft_pass in the same pass-1 invocation so trees can
## span chunk borders (extent=2 reach). Each (x, z) column in the MAIN area is tested
## independently with a deterministic per-column hash; the trunk + canopy writes are
## guarded to the EDITABLE area (main + extent reach).
##
## Thread safety: same rules as the rest of _generate_pass — pure reads + voxel_tool.set_voxel
## only; no Node tree mutations.
func _generate_trees_pass(voxel_tool: VoxelToolMultipassGenerator) -> void:
	var area_min: Vector3i = voxel_tool.get_main_area_min()
	var area_max: Vector3i = voxel_tool.get_main_area_max()
	var editable_min: Vector3i = voxel_tool.get_editable_area_min()
	var editable_max: Vector3i = voxel_tool.get_editable_area_max()

	# Iterate every (x, z) column in the main area.
	for x: int in range(area_min.x, area_max.x):
		for z: int in range(area_min.z, area_max.z):
			var world_x: float = float(x)
			var world_z: float = float(z)

			# Guaranteed starter tree near spawn — forced regardless of biome/chance
			# so the FTUE "mine a tree" step is always completable.
			if x == STARTER_TREE_X and z == STARTER_TREE_Z:
				var starter_noise: float = _noise.get_noise_2d(world_x, world_z)
				var starter_surface: int = int(starter_noise * height_amplitude + float(sea_level))
				_place_tree(x, starter_surface, z, TREE_TRUNK_MAX, editable_min, editable_max, voxel_tool)
				continue

			# Cell-based placement: one candidate tree per TREE_CELL×TREE_CELL cell, at a
			# deterministic jittered column inside the cell. Only the chosen column proceeds;
			# all others skip. This keeps trunks spaced apart so canopies don't form walls.
			# Keyed on absolute world coords so the choice is identical across chunk borders.
			var cell_x: int = floori(float(x) / float(TREE_CELL))
			var cell_z: int = floori(float(z) / float(TREE_CELL))
			var ch: int = _hash_chunk(world_seed, cell_x, 1, cell_z)
			# Jitter the trunk to the cell's centre band [2 .. TREE_CELL-2] (3 choices for cell=7)
			# so adjacent-cell trunks stay >= ~5 voxels apart.
			var jspan: int = TREE_CELL - 4
			var jx: int = 2 + (ch & 0xFF) % jspan
			var jz: int = 2 + ((ch >> 8) & 0xFF) % jspan
			if x != cell_x * TREE_CELL + jx or z != cell_z * TREE_CELL + jz:
				continue

			# Determine biome for this column.
			var biome: BiomeMap.Biome = _biome_map.biome_at(world_x, world_z)

			# Only grassland and jungle grow trees.
			var spawn_chance: float
			match biome:
				BiomeMap.Biome.GRASSLAND_FOREST:
					spawn_chance = TREE_SPAWN_CHANCE_GRASSLAND
				BiomeMap.Biome.JUNGLE:
					spawn_chance = TREE_SPAWN_CHANCE_JUNGLE
				_:
					continue

			# Per-cell spawn roll (reuse the cell hash so the decision is stable per cell).
			var h: int = ch
			var roll: float = float((ch >> 16) & 0xFFFF) / float(0xFFFF)
			if roll >= spawn_chance:
				continue

			# Compute surface height using the same formula as pass 0.
			var noise_val: float = _noise.get_noise_2d(world_x, world_z)
			var surface_y: int = int(noise_val * height_amplitude + float(sea_level))

			# Trunk height: TREE_TRUNK_MIN..TREE_TRUNK_MAX, determined from hash.
			var trunk_h: int = TREE_TRUNK_MIN + int((h >> 8) & 0xFF) % (TREE_TRUNK_MAX - TREE_TRUNK_MIN + 1)

			_place_tree(x, surface_y, z, trunk_h, editable_min, editable_max, voxel_tool)


## Place a single tree at (col_x, surface_y, col_z) with the given trunk height.
## Writes WOOD_LOG_ID voxels for the trunk (surface_y+1 to surface_y+trunk_h) and
## LEAVES_ID voxels for a 5×5-trimmed-corners canopy at trunk top ± 1 Y layers.
## All writes are bounds-checked against [editable_min, editable_max).
##
## Conservative design (safety-first):
##   - Only writes to Y > surface_y so trunk never overwrites terrain below.
##   - Corners of the 5×5 canopy are trimmed to give a rounded look.
##   - Skips writes outside editable area silently (no crash on edge columns).
func _place_tree(
		col_x: int, surface_y: int, col_z: int, trunk_h: int,
		editable_min: Vector3i, editable_max: Vector3i,
		voxel_tool: VoxelToolMultipassGenerator) -> void:
	var trunk_top_y: int = surface_y + trunk_h

	# Place trunk voxels: from surface_y+1 up to trunk_top_y (inclusive).
	for ty: int in range(surface_y + 1, trunk_top_y + 1):
		if ty >= editable_min.y and ty < editable_max.y:
			voxel_tool.set_voxel(Vector3i(col_x, ty, col_z), WOOD_LOG_ID)

	# Place leaf canopy: 3 Y layers centred at trunk_top_y, radius LEAF_RADIUS in XZ.
	# Trim corners of the 5×5 grid (|dx|+|dz| <= LEAF_RADIUS*2-1) for a round look.
	for dy: int in range(-1, 2):  # Y offsets: trunk_top-1, trunk_top, trunk_top+1
		var leaf_y: int = trunk_top_y + dy
		if leaf_y < editable_min.y or leaf_y >= editable_max.y:
			continue
		for dx: int in range(-LEAF_RADIUS, LEAF_RADIUS + 1):
			for dz: int in range(-LEAF_RADIUS, LEAF_RADIUS + 1):
				# Trim the four corner cells for a rounded canopy shape.
				if abs(dx) == LEAF_RADIUS and abs(dz) == LEAF_RADIUS:
					continue
				var lx: int = col_x + dx
				var lz: int = col_z + dz
				if lx < editable_min.x or lx >= editable_max.x:
					continue
				if lz < editable_min.z or lz >= editable_max.z:
					continue
				# Skip the trunk column cells — trunk is already written above.
				# (This avoids overwriting wood_log with leaves at the top trunk.)
				if dx == 0 and dz == 0 and dy <= 0:
					continue
				voxel_tool.set_voxel(Vector3i(lx, leaf_y, lz), LEAVES_ID)


## Deferred: log that a piece's stud bricks should be placed via StudGrid.
## Runs on the main thread (called via call_deferred from the worker thread).
## Phase 2 records the intent; Phase 4 wires the actual StudGrid.place() call.
##
## Silenced by default — every mineshaft piece would otherwise emit a warning
## per chunk-load, flooding the log and stalling the main thread. Re-enable by
## setting MINESHAFT_DEBUG=true in the project settings.
func _queue_stud_bricks(_piece: Resource, _stamp_origin: Vector3i, _rotation: int) -> void:
	pass  # no-op until Phase 4 wires StudGrid.place()


# ─── Biome helpers (mirrors terrain_generator.gd) ────────────────────────────

func _surface_block_for(biome: BiomeMap.Biome) -> int:
	match biome:
		BiomeMap.Biome.GRASSLAND_FOREST:
			return GRASS_ID
		BiomeMap.Biome.DESERT:
			return SAND_ID
		BiomeMap.Biome.SNOW:
			return SNOW_ID
		BiomeMap.Biome.JUNGLE:
			return JUNGLE_GRASS_ID
		BiomeMap.Biome.SAVANNAH:
			return SAVANNAH_GRASS_ID
		BiomeMap.Biome.OCEAN:
			return SAND_ID
	return GRASS_ID


func _underground_block_for(biome: BiomeMap.Biome, depth_below_surface: int) -> int:
	match biome:
		BiomeMap.Biome.GRASSLAND_FOREST, BiomeMap.Biome.JUNGLE, BiomeMap.Biome.SAVANNAH:
			if depth_below_surface <= DIRT_LAYERS:
				return DIRT_ID
			return STONE_ID
		BiomeMap.Biome.DESERT:
			if depth_below_surface <= DIRT_LAYERS:
				return SANDSTONE_ID
			return STONE_ID
		BiomeMap.Biome.SNOW:
			if depth_below_surface <= DIRT_LAYERS:
				return ICE_ID
			return STONE_ID
		BiomeMap.Biome.OCEAN:
			return STONE_ID
	return STONE_ID


# ─── Hash + rotation helpers (mirrors structure_placer.gd) ───────────────────

## Deterministic hash for (world_seed, chunk_x, chunk_y, chunk_z).
## Same Knuth multiplicative mix as structure_placer._hash for cross-plan consistency.
## T-08-03 mitigation: both peers compute identical piece + rotation from the same hash.
func _hash_chunk(seed: int, cx: int, cy: int, cz: int) -> int:
	var h: int = seed
	h = (h * 2654435761) ^ cx
	h = (h * 2654435761) ^ cy
	h = (h * 2654435761) ^ cz
	return h & 0x7FFFFFFFFFFFFFFF


## Rotate a template-local cell by 0..3 quarter-turns around the bbox centre (Y axis).
## Mirrors structure_placer._rotate_cell exactly (same XZ permutation pattern).
func _rotate_cell(local_cell: Vector3i, rotation: int, bbox: AABB) -> Vector3i:
	if rotation == 0:
		return local_cell
	var cx: int = int(bbox.size.x / 2.0)
	var cz: int = int(bbox.size.z / 2.0)
	var lx: int = local_cell.x - cx
	var lz: int = local_cell.z - cz
	var rx: int = lx
	var rz: int = lz
	for _i in range(rotation):
		var tmp: int = rx
		rx = -rz
		rz = tmp
	return Vector3i(rx + cx, local_cell.y, rz + cz)
