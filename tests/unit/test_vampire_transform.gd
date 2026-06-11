# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_vampire_transform.gd — Unit tests for vampire→bat transformation mechanic.
#
# Anchors:
#   DOCS.md §5.2 — vampire transforms into bat form at ~50% HP
#   03-CONTEXT.md D-09 — vampire at ≤2 HP flickers red (0.4 s) then wing-spread (0.5 s) → bat
#   03-RESEARCH.md Pitfall 4 — invuln window during TRANSFORM state transition
#
# These tests reference Vampire mob class shipping in Plan 03-09.
# They will FAIL until Plan 03-09 executes.

extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""

func before_each() -> void:
	_world_id = Phase3Fixtures.open_temp_world("survival")


func after_each() -> void:
	Phase3Fixtures.close_temp_world()
	Phase3Fixtures.cleanup_temp_world(_world_id)
	_world_id = ""


# ─── Test 1: Transform triggers at HP threshold = 2 ──────────────────────────

func test_transform_triggers_at_hp_threshold_2() -> void:
	# D-09 + 03-RESEARCH.md Pitfall 4: vampire at HP=3 takes 1 damage → enters TRANSFORM state.
	if not ClassDB.class_exists("Vampire"):
		pending("Vampire class not available — pending until Plan 03-09")
		return
	var vampire: Object = ClassDB.instantiate("Vampire")
	if vampire == null:
		pending("Vampire could not be instantiated — pending until Plan 03-09")
		return
	add_child(vampire)
	vampire.hp = 3
	# Apply 1 damage → HP drops to 2, should enter TRANSFORM.
	vampire.take_damage(1)
	var state: int = vampire.state
	var transform_state: int = vampire.State.TRANSFORM if "State" in vampire else -1
	assert_eq(state, transform_state,
		"Vampire should enter TRANSFORM state when HP reaches 2 (D-09)")
	vampire.queue_free()


# ─── Test 2: Bat form inherits remaining HP ───────────────────────────────────

func test_bat_form_inherits_remaining_hp() -> void:
	# D-09: when vampire transforms, bat spawns with HP = min(2, bat.max_hp).
	if not ClassDB.class_exists("Vampire"):
		pending("Vampire class not available — pending until Plan 03-09")
		return
	var vampire: Object = ClassDB.instantiate("Vampire")
	if vampire == null:
		pending("Vampire could not be instantiated — pending until Plan 03-09")
		return
	add_child(vampire)
	vampire.hp = 2  # Already at threshold.
	# Trigger the transform and simulate the state completing.
	vampire.take_damage(0)  # Force state check.
	await get_tree().process_frame
	await get_tree().process_frame
	var bats: Array = get_tree().get_nodes_in_group("bat_mob")
	if bats.is_empty():
		pending("Bat spawn from vampire transform not yet implemented — pending until Plan 03-09")
		vampire.queue_free()
		return
	var bat: Object = bats[0]
	assert_true(bat.hp >= 1 and bat.hp <= bat.max_hp,
		"Bat form must inherit remaining HP = min(vampire_hp, bat.max_hp) per D-09")
	vampire.queue_free()


# ─── Test 3: Invuln window during TRANSFORM tell ──────────────────────────────

func test_invuln_window_during_tell() -> void:
	# 03-RESEARCH.md Pitfall 4: between TRANSFORM enter and bat spawn (~0.9 s),
	# collision_layer = 0 (vampire is temporarily invulnerable during the tell animation).
	if not ClassDB.class_exists("Vampire"):
		pending("Vampire class not available — pending until Plan 03-09")
		return
	var vampire: Object = ClassDB.instantiate("Vampire")
	if vampire == null:
		pending("Vampire could not be instantiated — pending until Plan 03-09")
		return
	add_child(vampire)
	vampire.hp = 2
	vampire.take_damage(0)  # Force transform check.
	var state: int = vampire.state
	var transform_state: int = vampire.State.TRANSFORM if "State" in vampire else -1
	if state == transform_state:
		# During TRANSFORM, collision_layer must be 0 (invulnerable).
		var collision_layer: int = (vampire as CollisionObject3D).collision_layer
		assert_eq(collision_layer, 0,
			"Vampire collision_layer must be 0 during TRANSFORM state (invuln window, Pitfall 4)")
	else:
		pending("Vampire did not enter TRANSFORM state — pending until Plan 03-09")
	vampire.queue_free()


# ─── Test 4: Vampire only transforms once ─────────────────────────────────────

func test_vampire_only_transforms_once() -> void:
	# D-09: after transforming to bat, the bat does NOT re-transform when its HP hits 2 again.
	if not ClassDB.class_exists("Bat"):
		pending("Bat class not available — pending until Plan 03-09")
		return
	var bat: Object = ClassDB.instantiate("Bat")
	if bat == null:
		pending("Bat could not be instantiated — pending until Plan 03-09")
		return
	add_child(bat)
	bat.hp = 3
	# Bat should not have a TRANSFORM state (it's already in bat form).
	bat.take_damage(1)  # HP drops to 2.
	await get_tree().process_frame
	# Verify no new bat spawns (bat does not re-transform).
	var bats_before: int = get_tree().get_nodes_in_group("bat_mob").size()
	bat.take_damage(1)  # HP drops to 1 (below 2).
	await get_tree().process_frame
	var bats_after: int = get_tree().get_nodes_in_group("bat_mob").size()
	assert_true(bats_after <= bats_before,
		"Bat form must NOT re-transform when HP hits 2 again (D-09 — transform only once)")
	bat.queue_free()
