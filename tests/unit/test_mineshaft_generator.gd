# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_mineshaft_generator.gd — Unit tests for MineshaftGenerator.
#
# Tests (all headless — no live VoxelTerrain or godot_voxel scene needed):
#   1. test_pieces_load — 5 BrickTemplate pieces loaded at _init
#   2. test_depth_gate_constant — MINESHAFT_DEPTH_GATE is -8 per plan spec
#   3. test_depth_gate_blocks_shallow_chunks — depth gate blocks Y >= -8
#   4. test_depth_gate_allows_deep_chunks — depth gate allows Y < -8
#   5. test_hash_is_deterministic — same seed + chunk coords produce same hash
#   6. test_hash_differs_for_different_coords — different coords produce different hash
#   7. test_spawn_chance_35_percent — approximately 35% of deep chunks spawn pieces
#   8. test_rotate_cell_identity — rotation=0 returns original cell
#   9. test_rotate_cell_quarter_turn — rotation=1 swaps X/Z correctly
#   10. test_dead_end_has_regular_chest — corridor_dead_end.tres has regular chest
#   11. test_room_has_bronze_chest — corridor_room.tres has bronze chest
#   12. test_all_pieces_have_allowed_biomes_empty — depth-gated, not biome-gated
#   13. test_generate_block_fallback_returns_bedrock_below_column — Ex5 bugfix: BEDROCK below column floor
#   14. test_generate_block_fallback_returns_air_above_column — Ex5 bugfix: AIR above column ceiling
#   15. test_lava_floor_band_at_column_bottom — Ex5 bugfix: LAVA band at the bottom of every column
#
# Note: MineshaftGenerator extends VoxelGeneratorMultipassCB (experimental in godot_voxel
# at addon commit 4a9d311). Type hints use plain Object/RefCounted to avoid class_name
# resolution issues in headless GUT runs (VoxelGeneratorMultipassCB is a C++ type that
# must be registered before GDScript class_name resolution runs).
#
# Anchors:
#   02-MULTIPASS-NOTE.md — multipass-available decision; Pass 1 extent=2; depth gate Y < -8
#   02-CONTEXT.md D-07 — 5 mineshaft corridor pieces
#   02-CONTEXT.md D-08 — mineshafts common at depth (35% chunk spawn chance)
#   02-RESEARCH.md §"Pitfall 1" — corridor walls = TERRAIN voxels; decorations via StudGrid

extends GutTest

const MineshaftGeneratorScript = preload("res://src/world/multipass_generator.gd")
const BrickTemplateScript = preload("res://src/bricks/brick_template.gd")

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _make_generator(seed: int = 1234) -> Object:
	var gen = MineshaftGeneratorScript.new()
	gen.world_seed = seed
	return gen


# ─── Test 1: pieces load ──────────────────────────────────────────────────────

func test_pieces_load() -> void:
	# All 5 .tres files must be loadable as BrickTemplate resources.
	assert_eq(MineshaftGeneratorScript.PIECE_PATHS.size(), 5,
		"PIECE_PATHS constant must list exactly 5 mineshaft pieces (CONTEXT.md D-07)")
	for path in MineshaftGeneratorScript.PIECE_PATHS:
		var res = load(path)
		assert_not_null(res, "BrickTemplate .tres must be loadable: %s" % path)
		assert_true(res is BrickTemplateScript,
			"Each mineshaft piece must be a BrickTemplate resource: %s" % path)


# ─── Test 2: depth gate constant ──────────────────────────────────────────────

func test_depth_gate_constant() -> void:
	assert_eq(MineshaftGeneratorScript.MINESHAFT_DEPTH_GATE, -8,
		"MINESHAFT_DEPTH_GATE must be -8 per plan spec (CONTEXT.md D-08)")


# ─── Test 3: depth gate blocks shallow chunks ──────────────────────────────────

func test_depth_gate_blocks_shallow_chunks() -> void:
	# Simulate the gate condition directly (no VoxelTool needed).
	var gate: int = MineshaftGeneratorScript.MINESHAFT_DEPTH_GATE
	# surface Y=0 must be blocked (Y >= gate → block).
	assert_true(0 >= gate, "surface Y=0 must be blocked by depth gate (Y >= -8)")
	# Positive Y (above ground) must also be blocked.
	assert_true(16 >= gate, "above-ground Y=16 must be blocked by depth gate")
	# Y=-8 exactly must also be blocked (< -8 is the pass condition).
	assert_true(-8 >= gate, "boundary Y=-8 must be blocked (condition is Y < -8)")


# ─── Test 4: depth gate allows deep chunks ────────────────────────────────────

func test_depth_gate_allows_deep_chunks() -> void:
	var gate: int = MineshaftGeneratorScript.MINESHAFT_DEPTH_GATE
	# Y=-16 (one chunk below surface) must pass.
	assert_false(-16 >= gate, "deep Y=-16 must pass the depth gate (Y < -8)")
	# Y=-32 (deep stone) must pass.
	assert_false(-32 >= gate, "deep Y=-32 must pass the depth gate (Y < -8)")
	# Y=-9 (just below threshold) must pass.
	assert_false(-9 >= gate, "Y=-9 must pass the depth gate (Y < -8)")


# ─── Test 5: hash is deterministic ────────────────────────────────────────────

func test_hash_is_deterministic() -> void:
	var gen = _make_generator(42)
	var h1: int = gen._hash_chunk(42, 3, -5, 7)
	var h2: int = gen._hash_chunk(42, 3, -5, 7)
	assert_eq(h1, h2, "_hash_chunk must be deterministic for the same inputs")


# ─── Test 6: hash differs for different coords ────────────────────────────────

func test_hash_differs_for_different_coords() -> void:
	var gen = _make_generator(42)
	var h1: int = gen._hash_chunk(42, 3, -5, 7)
	var h2: int = gen._hash_chunk(42, 3, -5, 8)
	assert_ne(h1, h2, "_hash_chunk must differ for different chunk_z")
	var h3: int = gen._hash_chunk(42, 4, -5, 7)
	assert_ne(h1, h3, "_hash_chunk must differ for different chunk_x")


# ─── Test 7: spawn chance approximately 35% ───────────────────────────────────

func test_spawn_chance_35_percent() -> void:
	var gen = _make_generator(1234)
	var spawn_count: int = 0
	var total: int = 1000
	for i in range(total):
		var h: int = gen._hash_chunk(1234, i, -5, i * 3 + 7)
		var roll: float = float(h & 0xFFFF) / float(0xFFFF)
		if roll <= MineshaftGeneratorScript.MINESHAFT_SPAWN_CHANCE:
			spawn_count += 1
	var rate: float = float(spawn_count) / float(total)
	# Allow ±10% tolerance around the 35% target.
	assert_true(rate >= 0.25 and rate <= 0.45,
		"Spawn rate must be approximately 35%% (got %.1f%%, expected 25%%..45%%)" % (rate * 100.0))


# ─── Test 8: rotate_cell identity ─────────────────────────────────────────────

func test_rotate_cell_identity() -> void:
	var gen = _make_generator()
	var bbox: AABB = AABB(Vector3.ZERO, Vector3(8, 4, 3))
	var cell: Vector3i = Vector3i(2, 1, 1)
	var result: Vector3i = gen._rotate_cell(cell, 0, bbox)
	assert_eq(result, cell, "_rotate_cell with rotation=0 must return the original cell")


# ─── Test 9: rotate_cell quarter turn ─────────────────────────────────────────

func test_rotate_cell_quarter_turn() -> void:
	var gen = _make_generator()
	# 4×4 bbox. Rotate cell (1, 0, 0) by 1 quarter-turn (90° clockwise on XZ).
	# cx=2, cz=2. lx=1-2=-1, lz=0-2=-2. After rot1: rx=-lz=2, rz=lx=-1.
	# Result: rx+cx=4, y=0, rz+cz=1 → Vector3i(4, 0, 1).
	var bbox: AABB = AABB(Vector3.ZERO, Vector3(4, 4, 4))
	var cell: Vector3i = Vector3i(1, 0, 0)
	var result: Vector3i = gen._rotate_cell(cell, 1, bbox)
	assert_eq(result, Vector3i(4, 0, 1),
		"_rotate_cell with rotation=1 on a 4×4 bbox must rotate XZ by 90 degrees clockwise")


# ─── Test 10: dead_end has regular chest ──────────────────────────────────────

func test_dead_end_has_regular_chest() -> void:
	var piece = load("res://assets/templates/mineshafts/corridor_dead_end.tres")
	assert_not_null(piece, "corridor_dead_end.tres must be loadable")
	assert_true(piece.loot_chests.size() > 0,
		"corridor_dead_end must have at least one loot chest")
	var chest: Dictionary = piece.loot_chests[0]
	assert_eq(chest.get("chest_type", ""), "regular",
		"corridor_dead_end loot chest must be type 'regular' (DOCS section 4.4)")


# ─── Test 11: room has bronze chest ───────────────────────────────────────────

func test_room_has_bronze_chest() -> void:
	var piece = load("res://assets/templates/mineshafts/corridor_room.tres")
	assert_not_null(piece, "corridor_room.tres must be loadable")
	assert_true(piece.loot_chests.size() > 0,
		"corridor_room must have at least one loot chest")
	var chest: Dictionary = piece.loot_chests[0]
	assert_eq(chest.get("chest_type", ""), "bronze",
		"corridor_room loot chest must be type 'bronze' (DOCS section 4.4 mineshaft loot tier)")


# ─── Test 12: all pieces have allowed_biomes empty ───────────────────────────

func test_all_pieces_have_allowed_biomes_empty() -> void:
	for path in MineshaftGeneratorScript.PIECE_PATHS:
		var piece = load(path)
		assert_not_null(piece, "BrickTemplate must be loadable: %s" % path)
		assert_eq(piece.allowed_biomes.size(), 0,
			"Mineshaft pieces must have allowed_biomes=[] (depth-gated, not biome-gated): %s" % path)


# ─── Test 13: _generate_block_fallback returns BEDROCK below the column ───────

func test_generate_block_fallback_returns_bedrock_below_column() -> void:
	var gen = _make_generator()
	var column_floor_y: int = int(gen.column_base_y_blocks) * MineshaftGeneratorScript.CHUNK_SIZE
	var buf := VoxelBuffer.new()
	buf.create(16, 16, 16)
	gen._generate_block_fallback(buf, Vector3i(0, column_floor_y - MineshaftGeneratorScript.CHUNK_SIZE, 0))
	for x in [0, 8, 15]:
		for z in [0, 8, 15]:
			assert_eq(buf.get_voxel(x, 0, z), MineshaftGeneratorScript.BEDROCK_ID,
				"block below the column floor must be solid BEDROCK, not void, at local (%d,0,%d)" % [x, z])
			assert_eq(buf.get_voxel(x, 15, z), MineshaftGeneratorScript.BEDROCK_ID,
				"block below the column floor must be solid BEDROCK throughout, at local (%d,15,%d)" % [x, z])


# ─── Test 14: _generate_block_fallback returns AIR above the column ──────────

func test_generate_block_fallback_returns_air_above_column() -> void:
	var gen = _make_generator()
	var column_ceiling_y: int = (int(gen.column_base_y_blocks) + int(gen.column_height_blocks)) * MineshaftGeneratorScript.CHUNK_SIZE
	var buf := VoxelBuffer.new()
	buf.create(16, 16, 16)
	gen._generate_block_fallback(buf, Vector3i(0, column_ceiling_y, 0))
	assert_eq(buf.get_voxel(8, 8, 8), MineshaftGeneratorScript.AIR_ID,
		"block above the column ceiling must be AIR (open sky)")


# ─── Test 15: lava floor band at the bottom of every column ───────────────────

func test_lava_floor_band_at_column_bottom() -> void:
	# Column (block coords 0,0), world_seed=1234: deterministically no mineshaft spawn on
	# this column (verified roll ~0.867 vs. the 0.35 threshold), so the bottom band is pure
	# pass-0 output with no pass-1 corridor carving to confuse the assertion.
	var gen = _make_generator(1234)
	var blocks: Array = gen.debug_generate_test_column(Vector2i(0, 0))
	assert_true(blocks.size() > 0, "debug_generate_test_column must return at least one block")
	if blocks.is_empty():
		return
	var bottom_block: VoxelBuffer = blocks[0]
	for i in range(MineshaftGeneratorScript.LAVA_BAND_THICKNESS):
		assert_eq(bottom_block.get_voxel(0, i, 0), MineshaftGeneratorScript.LAVA_ID,
			"world floor local Y=%d must be LAVA (Ex5 bugfix -- no open void at the column bottom)" % i)
	assert_eq(bottom_block.get_voxel(0, MineshaftGeneratorScript.LAVA_BAND_THICKNESS, 0),
		MineshaftGeneratorScript.STONE_ID,
		"just above the lava band must resume normal STONE, not lava filling the whole block")
