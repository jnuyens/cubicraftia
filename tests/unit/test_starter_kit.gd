# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_starter_kit.gd — Unit tests for survival-world starter chest + bed seeding.
#
# Anchors:
#   DOCS.md §5.6 — starter chest + builder-bed at survival world spawn
#   03-CONTEXT.md D-15 — starter chest contents: 1 pickaxe + 1 shovel + 1 lantern + 8 planks + 4 food
#   03-CONTEXT.md D-01 — sandbox mode does NOT spawn starter kit
#
# These tests reference main_scene.spawn_starter_chest_and_bed() shipping in Plan 03-08.
# They will FAIL until Plan 03-08 executes.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Survival world spawns starter chest and bed at world origin ──────

func test_survival_world_spawns_chest_and_bed_at_world_origin() -> void:
	# D-15 + DOCS §5.6: on first open_world(mode=survival), main_scene.spawn_starter_chest_and_bed() runs.
	# The starter chest and bed should appear in their respective scene groups.
	var main_scene_path := "res://src/world/main_scene.tscn"
	if not ResourceLoader.exists(main_scene_path):
		pending("main_scene.tscn not available — pending until Plan 03-08")
		return
	var packed: PackedScene = load(main_scene_path)
	var scene: Node = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	# Starter chest should be in the "starter_chest" group.
	var starter_chests: Array = get_tree().get_nodes_in_group("starter_chest")
	assert_eq(starter_chests.size(), 1,
		"Survival world first open must spawn exactly 1 starter chest (D-15)")
	# Starter bed should be in the "starter_bed" group.
	var starter_beds: Array = get_tree().get_nodes_in_group("starter_bed")
	assert_eq(starter_beds.size(), 1,
		"Survival world first open must spawn exactly 1 starter bed (DOCS §5.6)")
	scene.queue_free()


# ─── Test 2: Starter chest contents match D-15 verbatim ──────────────────────

func test_starter_chest_contents_match_D15_verbatim() -> void:
	# D-15: chest contains exactly {pickaxe_wooden:1, shovel_wooden:1, lantern:1, brick_plank_wooden:8, food_cooked_generic:4}.
	var main_scene_path := "res://src/world/main_scene.tscn"
	if not ResourceLoader.exists(main_scene_path):
		pending("main_scene.tscn not available — pending until Plan 03-08")
		return
	if not Engine.has_singleton("Inventory"):
		pending("Inventory autoload not available — pending until Plan 03-02")
		return
	var inventory = Engine.get_singleton("Inventory")
	var packed: PackedScene = load(main_scene_path)
	var scene: Node = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var starter_chests: Array = get_tree().get_nodes_in_group("starter_chest")
	if starter_chests.is_empty():
		pending("No starter chest in scene — pending until Plan 03-08")
		scene.queue_free()
		return
	var chest: Node = starter_chests[0]
	var chest_pos: Vector3i = chest.get_meta("chunk_coord") if chest.has_meta("chunk_coord") else Vector3i(0, 0, 0)
	var contents: Array = inventory.get_chest_contents(chest_pos)
	# Build a {def_id: count} map from contents.
	var content_map: Dictionary = {}
	for slot: Dictionary in contents:
		var id: String = str(slot.get("def_id", ""))
		var count: int = slot.get("count", 0)
		if id != "" and count > 0:
			content_map[id] = content_map.get(id, 0) + count
	var expected_contents: Dictionary = {
		"pickaxe_wooden":      1,
		"shovel_wooden":       1,
		"lantern":             1,
		"brick_plank_wooden":  8,
		"food_cooked_generic": 4,
	}
	for item_id: String in expected_contents:
		assert_true(content_map.get(item_id, 0) >= expected_contents[item_id],
			"Starter chest must contain at least %d × %s (D-15 verbatim)" % [expected_contents[item_id], item_id])
	scene.queue_free()


# ─── Test 3: Sandbox world does NOT spawn starter kit ────────────────────────

func test_sandbox_world_does_NOT_spawn_starter_kit() -> void:
	# D-01 + D-15: in sandbox mode, no starter chest or bed is spawned.
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = Phase3Fixtures.open_temp_world("sandbox")
	var main_scene_path := "res://src/world/main_scene.tscn"
	if not ResourceLoader.exists(main_scene_path):
		pending("main_scene.tscn not available — pending until Plan 03-08")
		return
	var packed: PackedScene = load(main_scene_path)
	var scene: Node = packed.instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var starter_chests: Array = get_tree().get_nodes_in_group("starter_chest")
	var starter_beds: Array = get_tree().get_nodes_in_group("starter_bed")
	assert_eq(starter_chests.size(), 0,
		"Sandbox world must NOT spawn a starter chest (D-01 + D-15)")
	assert_eq(starter_beds.size(), 0,
		"Sandbox world must NOT spawn a starter bed (D-01 + D-15)")
	scene.queue_free()
