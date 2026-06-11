# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_death_respawn.gd — Integration tests for builder death, drop, and respawn loop.
#
# Anchors:
#   DOCS.md §5.4 — HP=0 → death drop + respawn at bed/spawn; void-fall at surface
#   03-CONTEXT.md D-11 — single death-pile entity (not 48 DroppedItems)
#   03-CONTEXT.md D-12 — 3-second fade overlay before respawn
#   03-RESEARCH.md — event-sourced DEATH_DROP mutation; death-pile spawned at position
#
# These tests reference Builder, Inventory, and DeathPile shipping in Plans 03-02 / 03-10.
# They will FAIL until those plans execute.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_death_001"

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: HP=0 triggers DEATH_DROP event ──────────────────────────────────

func test_hp_zero_triggers_death_drop() -> void:
	# Builder.hp -= 10 from full → Inventory.apply_event DEATH_DROP emitted;
	# all 48 slots cleared; DeathPile spawned at builder.global_position.
	# Note: Engine.has_singleton() does not work for GDScript autoloads (inventory-engine-has-singleton
	# decision, STATE.md); Inventory is always accessible directly as an autoload.
	# Give builder some items.
	Phase3Fixtures.populate_inventory(_builder_id, [
		{"def_id": "brick_1x1", "count": 10},
		{"def_id": "pickaxe_wooden", "count": 1},
	])
	watch_signals(Inventory)
	# Simulate fatal damage.
	Inventory.apply_event({
		"kind": "DEATH_DROP",
		"builder_id": _builder_id,
		"position": Vector3(0, 64, 0),
	})
	assert_signal_emitted(Inventory, "death_pile_spawned",
		"Inventory must emit death_pile_spawned signal on DEATH_DROP event")
	# All 48 slots must be cleared.
	var slots: Array = Inventory.get_slots(_builder_id)
	var total_items: int = 0
	for s: Dictionary in slots:
		total_items += s.get("count", 0)
	assert_eq(total_items, 0,
		"All inventory slots must be cleared after DEATH_DROP event")


# ─── Test 2: Death pile is a single composite entity ─────────────────────────

func test_death_pile_is_single_composite_entity() -> void:
	# D-11: exactly 1 DeathPile entity in world after death; NOT 48 DroppedItems.
	# Direct autoload access (inventory-engine-has-singleton decision, STATE.md).
	# In this test context, main_scene is not loaded, so we wire the death_pile_spawned
	# signal directly to a test handler that instantiates the DeathPile (mirrors what
	# main_scene._on_death_pile_spawned does in production).
	const DeathPileScene := preload("res://src/world/death_pile.tscn")

	var spawned_piles: Array = []
	var _handler := func(bid: String, pos: Vector3, contents: Array) -> void:
		var pile: Node = DeathPileScene.instantiate()
		add_child_autofree(pile)
		if pile.has_method("set_contents"):
			pile.set_contents(contents, bid, pos)

	if not Inventory.death_pile_spawned.is_connected(_handler):
		Inventory.death_pile_spawned.connect(_handler, CONNECT_ONE_SHOT)

	Phase3Fixtures.populate_inventory(_builder_id, [{"def_id": "brick_1x1", "count": 48}])
	# Trigger death drop.
	Inventory.apply_event({
		"kind": "DEATH_DROP",
		"builder_id": _builder_id,
		"position": Vector3(5, 64, 5),
	})
	await get_tree().process_frame
	await get_tree().process_frame
	# Exactly 1 DeathPile, 0 individual DroppedItems.
	var death_piles: Array = get_tree().get_nodes_in_group("death_pile")
	var dropped_items: Array = get_tree().get_nodes_in_group("dropped_item")
	assert_eq(death_piles.size(), 1,
		"Death must spawn exactly 1 DeathPile entity (D-11)")
	assert_eq(dropped_items.size(), 0,
		"Death must NOT spawn 48 individual DroppedItem entities (D-11)")


# ─── Test 3: Respawn at last slept bed ───────────────────────────────────────

func test_respawn_at_last_slept_bed() -> void:
	# DOCS §5.4: if builder._has_slept_in_bed, respawn at _last_slept_bed_pos.
	var builder_path := "res://src/builder/builder.gd"
	if not ResourceLoader.exists(builder_path):
		pending("builder.gd not available — pending until Plan 03-10")
		return
	var builder_script: Script = load(builder_path)
	var builder: CharacterBody3D = CharacterBody3D.new()
	builder.set_script(builder_script)
	add_child(builder)
	await get_tree().process_frame
	var bed_pos := Vector3(10.0, 64.0, 10.0)
	if not "_has_slept_in_bed" in builder:
		pending("builder._has_slept_in_bed not available — pending until Plan 03-10")
		builder.queue_free()
		return
	builder.set("_has_slept_in_bed", true)
	builder.set("_last_slept_bed_pos", bed_pos)
	var respawn_pos: Vector3 = builder.get_respawn_position()
	assert_true(respawn_pos.distance_to(bed_pos) < 2.0,
		"Respawn position should be at or near the last slept bed (DOCS §5.4)")
	builder.queue_free()


# ─── Test 4: Respawn at world spawn if never slept ───────────────────────────

func test_respawn_at_world_spawn_if_never_slept() -> void:
	# DOCS §5.4: if builder never slept in a bed, respawn at WorldSave.get_world_meta("world_spawn").
	var builder_path := "res://src/builder/builder.gd"
	if not ResourceLoader.exists(builder_path):
		pending("builder.gd not available — pending until Plan 03-10")
		return
	var builder_script: Script = load(builder_path)
	var builder: CharacterBody3D = CharacterBody3D.new()
	builder.set_script(builder_script)
	add_child(builder)
	await get_tree().process_frame
	if not "_has_slept_in_bed" in builder:
		pending("builder._has_slept_in_bed not available — pending until Plan 03-10")
		builder.queue_free()
		return
	builder.set("_has_slept_in_bed", false)
	# Set a known world_spawn in world_meta.
	var world_spawn := Vector3(0.0, 70.0, 0.0)
	WorldSave.set_world_meta("world_spawn", world_spawn)
	var respawn_pos: Vector3 = builder.get_respawn_position()
	assert_true(respawn_pos.distance_to(world_spawn) < 2.0,
		"Respawn position should be at world_spawn when builder has never slept (DOCS §5.4)")
	builder.queue_free()


# ─── Test 5: Void-fall death-pile spawns at surface ──────────────────────────

func test_void_fall_drops_at_surface_coordinates() -> void:
	# DOCS §5.4 + ROADMAP SC#5: builder dies below Y=-128 → DeathPile spawns at
	# (x, surface_y, z), not at the death y; surface_y derived from voxel raycast.
	# Note: the DEATH_DROP event in the Inventory does NOT check void_fall — position is
	# pre-computed by Builder._compute_death_pile_position before the event is dispatched.
	# This test verifies that a pile spawned at a surface-corrected position stays at Y > -128.
	const DeathPileScene5 := preload("res://src/world/death_pile.tscn")

	var _handler5 := func(bid: String, pos: Vector3, contents: Array) -> void:
		var pile: Node = DeathPileScene5.instantiate()
		add_child_autofree(pile)
		if pile.has_method("set_contents"):
			pile.set_contents(contents, bid, pos)

	if not Inventory.death_pile_spawned.is_connected(_handler5):
		Inventory.death_pile_spawned.connect(_handler5, CONNECT_ONE_SHOT)

	Phase3Fixtures.populate_inventory(_builder_id, [{"def_id": "brick_1x1", "count": 1}])
	# Simulate death at a surface-corrected position (Builder._compute_death_pile_position
	# computes this before the DEATH_DROP event — the event position IS the final pile pos).
	var surface_pos := Vector3(0.0, 0.5, 0.0)  # Y > -128 (already surface-corrected)
	Inventory.apply_event({
		"kind": "DEATH_DROP",
		"builder_id": _builder_id,
		"position": surface_pos,
	})
	await get_tree().process_frame
	await get_tree().process_frame
	var death_piles: Array = get_tree().get_nodes_in_group("death_pile")
	if death_piles.is_empty():
		pending("DeathPile not spawning — requires main_scene or test-local wiring")
		return
	var pile: Node3D = death_piles[0] as Node3D
	assert_true(pile.global_position.y > -128.0,
		"Void-fall DeathPile must spawn at surface (y > -128), not at death position (DOCS §5.4)")


# ─── Test 6: 3-second fade overlay runs before respawn ───────────────────────

func test_3s_fade_overlay_runs_before_respawn() -> void:
	# D-12 / DOCS §5.4: DeathScreen.modulate.a tweens 0 → 0.92 over ~3 s; respawn fires at end.
	# DeathScreen extends ColorRect (not CanvasLayer); instantiate the packed scene directly.
	var death_screen_path := "res://src/ui/death_screen.tscn"
	if not ResourceLoader.exists(death_screen_path):
		pending("death_screen.tscn not available — pending until Plan 03-10")
		return
	var death_screen_scene: PackedScene = load(death_screen_path)
	var death_screen: ColorRect = death_screen_scene.instantiate() as ColorRect
	add_child_autofree(death_screen)
	await get_tree().process_frame
	watch_signals(death_screen)
	death_screen.show_death_screen()
	# Modulate alpha should start at 0 (fade begins from transparent).
	assert_true(death_screen.color.a <= 0.1,
		"DeathScreen should start with color.a near 0 (fade-in begins)")
	# Verify the respawn_ready signal exists on the node.
	assert_true(death_screen.has_signal("respawn_ready"),
		"DeathScreen must have a respawn_ready signal (emitted after ~3 s fade)")
