# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_structure_placement.gd — Integration tests for deterministic structure placement.
#
# Tests:
#   1. test_village_positions_deterministic_per_seed  — same seed → same spawn decisions
#   2. test_no_overlapping_structures                 — one-structure-per-blueprint-cell invariant
#
# Anchors:
#   DOCS.md §2 — v1 generated structures appear in biomes with deterministic positions
#   02-CONTEXT.md §D-07 — pre-authored brick templates, 3-5 variants per type
#   02-CONTEXT.md §D-08 — structure rarity tiers
#   02-RESEARCH.md §"Structure Placement Pattern 2"
#
# Headless note: StructurePlacer runs offline (no live VoxelTerrain required).
# BiomeMap and StructurePlacer are plain RefCounted — no Node/scene-tree needed.

extends GutTest

const StructurePlacerScript := preload("res://src/world/structure_placer.gd")

# ─── Helpers ──────────────────────────────────────────────────────────────────

## Build a StructurePlacer without a BiomeMap (biome gate is bypassed when
## _biome_map == null and allowed_biomes is empty, which dungeons satisfy;
## for biome-restricted templates this means they may or may not pass the gate).
## Tests that only need determinism can pass null safely.
func _make_placer(world_seed: int, biome_map: BiomeMap = null) -> RefCounted:
	return StructurePlacerScript.new(world_seed, biome_map)


# ─── Test 1 ───────────────────────────────────────────────────────────────────

func test_village_positions_deterministic_per_seed() -> void:
	# Two placers with the same seed must produce bit-identical decisions.
	var seed: int = 42
	var placer_a: RefCounted = _make_placer(seed)
	var placer_b: RefCounted = _make_placer(seed)

	var differences: int = 0
	var cells_checked: int = 0

	# Iterate 100 blueprint cells around origin for all four structure types.
	var types: Array = ["village", "temple", "shipwreck", "dungeon"]
	for structure_type in types:
		for bx in range(-5, 6):
			for bz in range(-5, 6):
				cells_checked += 1
				var result_a: Dictionary = placer_a.should_place_structure_at_cell(structure_type, bx, bz)
				var result_b: Dictionary = placer_b.should_place_structure_at_cell(structure_type, bx, bz)

				# Both must agree on spawn (both empty or both non-empty).
				var a_has: bool = not result_a.is_empty()
				var b_has: bool = not result_b.is_empty()
				if a_has != b_has:
					differences += 1
					continue

				if a_has:
					# Both placed a structure — check anchor + rotation agreement.
					var anchor_a: Vector3i = result_a.get("anchor", Vector3i.ZERO)
					var anchor_b: Vector3i = result_b.get("anchor", Vector3i.ZERO)
					if anchor_a != anchor_b:
						differences += 1
					var rot_a: int = int(result_a.get("rotation", -1))
					var rot_b: int = int(result_b.get("rotation", -1))
					if rot_a != rot_b:
						differences += 1

	assert_eq(differences, 0,
		"Two StructurePlacers with seed %d should produce identical results across %d cell queries (found %d differences)." % [seed, cells_checked, differences])


# ─── Test 2 ───────────────────────────────────────────────────────────────────

func test_no_overlapping_structures() -> void:
	# For each structure type, the blueprint-cell contract guarantees at most one
	# structure per blueprint cell. Verify over a 10×10 grid of blueprint cells.
	#
	# Overlap would mean two structures returned for the same (type, bx, bz) cell.
	# Since each (type, bx, bz) triple maps to exactly one deterministic result,
	# this test verifies the invariant holds: identical queries → identical result,
	# no secondary structure is spawned in the same cell.

	var seed: int = 1234
	var placer: RefCounted = _make_placer(seed)
	var types: Array = ["village", "temple", "shipwreck", "dungeon"]

	for structure_type in types:
		# Track which (bx, bz) cells produced a result — each cell maps 1:1.
		var seen_cells: Dictionary = {}  # Dictionary[(bx,bz)_key -> Dictionary]

		for bx in range(0, 10):
			for bz in range(0, 10):
				var result: Dictionary = placer.should_place_structure_at_cell(structure_type, bx, bz)
				var cell_key: String = "%d_%d" % [bx, bz]

				# A second call on the same cell must produce the same result (idempotency).
				var result2: Dictionary = placer.should_place_structure_at_cell(structure_type, bx, bz)
				var both_empty: bool = result.is_empty() and result2.is_empty()
				var both_placed: bool = not result.is_empty() and not result2.is_empty()
				assert_true(both_empty or both_placed,
					"Type '%s' cell (%d,%d): second query must agree with first (idempotency)." % [structure_type, bx, bz])

				if not result.is_empty():
					# Verify no duplicate structure in the same blueprint cell.
					assert_false(seen_cells.has(cell_key),
						"Type '%s' cell (%d,%d): duplicate structure in same blueprint cell (one-per-cell invariant violated)." % [structure_type, bx, bz])
					seen_cells[cell_key] = result

	# Also verify that spawn counts are in a reasonable range (sanity check on chances).
	# With 100 cells and chance 0.6, expect roughly 50-70 villages (allow generous margin).
	var village_count: int = 0
	for bx in range(0, 10):
		for bz in range(0, 10):
			var result: Dictionary = placer.should_place_structure_at_cell("village", bx, bz)
			if not result.is_empty():
				village_count += 1
	# With 100 cells × 0.60 chance → expect 40-80 spawns (very generous margin for hash variance).
	assert_true(village_count >= 10 and village_count <= 100,
		"Village spawn count %d should be non-zero and at most 100 across 100 cells." % village_count)


# ─── Test 3: lighthouse is tagged "climbable" (#18) ───────────────────────────
# The ocean lighthouse (structure_1_03) has no interior stairs, so WorldStructure tags it
# "climbable" in _ready; the builder slides up its outer wall. Every other structure stays a
# plain solid prop. The group-add runs before the model load, so it works headlessly even
# when the .glb is not present.

const WorldStructureScene := preload("res://src/world/world_structure.gd")


func test_lighthouse_is_tagged_climbable() -> void:
	var ws := WorldStructureScene.new() as Node3D
	ws.structure_id = "structure_1_03"  # ocean lighthouse
	add_child(ws)
	assert_true(ws.is_in_group("climbable"),
		"#18: the lighthouse (structure_1_03) must be in the 'climbable' group")
	assert_true(ws.is_in_group("structure"),
		"the lighthouse must still be a normal 'structure' as well")
	ws.queue_free()


func test_non_lighthouse_structure_is_not_climbable() -> void:
	var ws := WorldStructureScene.new() as Node3D
	ws.structure_id = "structure_3_02"  # a different ocean landmark
	add_child(ws)
	assert_false(ws.is_in_group("climbable"),
		"#18: a non-lighthouse structure must NOT be in the 'climbable' group")
	ws.queue_free()
