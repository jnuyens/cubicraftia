# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_brick_definition.gd — Unit tests for BrickDefinition Resource and brick_1x1.tres.
#
# Tests:
#   1. test_loads_brick_1x1              — from_gltf returns non-null BrickDefinition
#   2. test_extras_round_trip            — dimensions, studs_top size, and stud position correct
#   3. test_concave_top_marker           — stud_profile == "concave_top" (D-08 invariant)
#   4. test_mesh_loads                   — def.mesh is non-null and is a Mesh
#   5. test_category_enum_values         — Category enum has correct int values
#   6. test_colour_swappable_default     — colour_swappable defaults to true
#   7. test_natural_colour_token_default — natural_colour_token defaults to -1
#   8. test_iap_pack_origin_default      — iap_pack_origin defaults to empty string
#   9. test_footprint_cells_default      — footprint_cells defaults to single cell

extends GutTest

const GLTF_PATH := "res://assets/meshes/brick_1x1.glb"
const BRICK_1X1_TRES := "res://src/bricks/brick_1x1.tres"

# ─── Test 1 ────────────────────────────────────────────────────────────────────

func test_loads_brick_1x1() -> void:
	var def: BrickDefinition = BrickDefinition.from_gltf(GLTF_PATH)
	assert_not_null(def, "from_gltf should return a non-null BrickDefinition")
	assert_eq(def.brick_id, "brick_1x1", "brick_id should be 'brick_1x1'")

# ─── Test 2 ────────────────────────────────────────────────────────────────────

func test_extras_round_trip() -> void:
	var def: BrickDefinition = BrickDefinition.from_gltf(GLTF_PATH)
	assert_not_null(def, "from_gltf should return a non-null BrickDefinition")
	assert_eq(def.dimensions, Vector3i(1, 1, 1), "dimensions should be Vector3i(1,1,1)")
	assert_eq(def.studs_top.size(), 1, "studs_top should have exactly 1 stud")
	var stud: Dictionary = def.studs_top[0]
	assert_true(stud.has("x") and stud.has("y") and stud.has("z"),
		"stud entry should have x, y, z keys")
	assert_almost_eq(float(stud["y"]), 1.0, 0.001,
		"stud y position should be 1.0 (top face)")

# ─── Test 3 ────────────────────────────────────────────────────────────────────

func test_concave_top_marker() -> void:
	var def: BrickDefinition = BrickDefinition.from_gltf(GLTF_PATH)
	assert_not_null(def, "from_gltf should return a non-null BrickDefinition")
	assert_eq(def.stud_profile, "concave_top",
		"stud_profile must be 'concave_top' per D-08 invariant")

# ─── Test 4 ────────────────────────────────────────────────────────────────────

func test_mesh_loads() -> void:
	var def: BrickDefinition = BrickDefinition.from_gltf(GLTF_PATH)
	assert_not_null(def, "from_gltf should return a non-null BrickDefinition")
	assert_not_null(def.mesh, "def.mesh should not be null")
	assert_true(def.mesh is Mesh, "def.mesh should be a Mesh instance")

# ─── Test 5 — Phase 2 Plan 02-04 new exports ──────────────────────────────────

func test_category_enum_values() -> void:
	assert_eq(BrickDefinition.Category.RECTANGULAR,  0, "RECTANGULAR must be 0")
	assert_eq(BrickDefinition.Category.PLATE,        1, "PLATE must be 1")
	assert_eq(BrickDefinition.Category.SLOPE,        2, "SLOPE must be 2")
	assert_eq(BrickDefinition.Category.TILE,         3, "TILE must be 3")
	assert_eq(BrickDefinition.Category.ROUND,        4, "ROUND must be 4")
	assert_eq(BrickDefinition.Category.FUNCTIONAL,   5, "FUNCTIONAL must be 5")
	assert_eq(BrickDefinition.Category.DECORATIVE,   6, "DECORATIVE must be 6")
	assert_eq(BrickDefinition.Category.MATERIAL_ORE, 7, "MATERIAL_ORE must be 7")
	assert_eq(BrickDefinition.Category.ACCESSORY,    8, "ACCESSORY must be 8")
	assert_eq(BrickDefinition.Category.MOB_DROP,     9, "MOB_DROP must be 9")

# ─── Test 6 ────────────────────────────────────────────────────────────────────

func test_colour_swappable_default() -> void:
	var def := BrickDefinition.new()
	assert_true(def.colour_swappable, "colour_swappable should default to true")

# ─── Test 7 ────────────────────────────────────────────────────────────────────

func test_natural_colour_token_default() -> void:
	var def := BrickDefinition.new()
	assert_eq(def.natural_colour_token, -1, "natural_colour_token should default to -1")

# ─── Test 8 ────────────────────────────────────────────────────────────────────

func test_iap_pack_origin_default() -> void:
	var def := BrickDefinition.new()
	assert_eq(def.iap_pack_origin, "", "iap_pack_origin should default to empty string")

# ─── Test 9 ────────────────────────────────────────────────────────────────────

func test_footprint_cells_default() -> void:
	var def := BrickDefinition.new()
	assert_eq(def.footprint_cells.size(), 1, "footprint_cells should default to single cell")
	assert_eq(def.footprint_cells[0], Vector3i(0, 0, 0), "default footprint cell should be Vector3i(0,0,0)")
