# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_wildlife_combat.gd — Issue #17: passive animals are killable and drop meat.
#
# Covers the damage/health/die pipeline added to wildlife.gd (mirrors the HostileMob
# pattern): take_damage decrements hp, a fatal hit emits `died` and drops MEAT_DROP_COUNT
# raw_meat via main_scene.spawn_dropped_item, and the meat brick is registered.
#
# The combat methods (take_damage / _die / _drop_meat) are deliberately tree-light, so these
# run headless WITHOUT a display: we build a BARE Wildlife (no _ready / no mesh+animator load)
# and inject a stub main_scene to capture the drop. The in-tree hurtbox-raycast path is
# display-gated (it needs the spawned colliders) and lives in the builder; it's verified by
# the const-level layer-sync assertion below plus manual QA.

extends GutTest

const WildlifeScript = preload("res://src/world/wildlife.gd")
const BuilderScript = preload("res://src/builder/builder.gd")


## Minimal main_scene stub that records spawn_dropped_item calls so the death drop is
## observable without a real MainScene / DroppedItem scene / physics.
class StubMainScene:
	extends Node
	var drops: Array = []  # Array of {def_id, colour_index, pos, active}
	func spawn_dropped_item(def_id: String, colour_index: int, world_pos: Vector3,
			active_physics: bool) -> void:
		drops.append({
			"def_id": def_id,
			"colour_index": colour_index,
			"pos": world_pos,
			"active": active_physics,
		})


# ─── Constants / contract ─────────────────────────────────────────────────────

func test_wildlife_has_health_constants() -> void:
	assert_gt(WildlifeScript.MAX_HP, 0, "Wildlife.MAX_HP must be a positive number of hits")
	assert_lte(WildlifeScript.MAX_HP, 10, "Wildlife.MAX_HP stays small — a few hits kill a small animal")
	assert_gt(WildlifeScript.MEAT_DROP_COUNT, 0, "Killing an animal drops at least one meat")


func test_meat_brick_is_registered() -> void:
	# raw_meat must resolve via BrickRegistry (manifest wiring) so the drop + inventory path work.
	var def = BrickRegistry.get_definition("raw_meat")
	assert_not_null(def, "raw_meat BrickDefinition must be registered in BrickRegistry")
	if def != null:
		assert_eq(def.brick_id, "raw_meat", "raw_meat def has the expected brick_id")
		assert_eq(int(def.category), int(BrickDefinition.Category.MOB_DROP),
			"raw_meat is a MOB_DROP")


func test_sashimi_brick_is_registered() -> void:
	# sashimi (the WATER-creature drop) must resolve via BrickRegistry so the sea-creature
	# death drop + inventory path work, exactly like raw_meat for land animals.
	var def = BrickRegistry.get_definition("sashimi")
	assert_not_null(def, "sashimi BrickDefinition must be registered in BrickRegistry")
	if def != null:
		assert_eq(def.brick_id, "sashimi", "sashimi def has the expected brick_id")
		assert_eq(int(def.category), int(BrickDefinition.Category.MOB_DROP),
			"sashimi is a MOB_DROP")


func test_builder_attack_layer_matches_wildlife_hurtbox() -> void:
	# The builder's attack ray queries _WILDLIFE_HURTBOX_MASK; the hurtbox sits on
	# _HURTBOX_LAYER_BIT. If these drift apart, the attack ray silently stops hitting animals.
	assert_eq(BuilderScript._WILDLIFE_HURTBOX_MASK, WildlifeScript._HURTBOX_LAYER_BIT,
		"builder attack mask must match wildlife hurtbox layer bit")


# ─── Damage / death pipeline ──────────────────────────────────────────────────

func test_non_fatal_hit_decrements_hp_without_dying() -> void:
	var w = WildlifeScript.new()
	# Bare instance: do NOT add to tree (skips the display-dependent _ready mesh/animator load).
	w.kind = "pig"
	w.hp = WildlifeScript.MAX_HP
	var died := [false]
	w.died.connect(func() -> void: died[0] = true)
	w.take_damage(1, Vector3.ZERO)
	assert_eq(w.hp, WildlifeScript.MAX_HP - 1, "a single hit removes exactly its damage from hp")
	assert_false(died[0], "a non-fatal hit must not emit died")
	w.free()


func test_fatal_hit_emits_died_and_drops_meat() -> void:
	# LAND creature (pig): a fatal hit drops raw_meat (sea creatures drop sashimi instead,
	# see test_killing_water_creature_drops_sashimi).
	var stub := StubMainScene.new()
	add_child_autofree(stub)
	var w = WildlifeScript.new()
	w.kind = "pig"
	w.hp = WildlifeScript.MAX_HP
	w.set_main_scene(stub)
	var died := [false]
	w.died.connect(func() -> void: died[0] = true)
	# Deal lethal damage in one blow.
	w.take_damage(WildlifeScript.MAX_HP, Vector3(1, 2, 3))
	assert_eq(w.hp, 0, "hp clamps to 0 on a lethal hit")
	assert_true(died[0], "a lethal hit emits died")
	assert_eq(stub.drops.size(), WildlifeScript.MEAT_DROP_COUNT,
		"a killed animal drops MEAT_DROP_COUNT meat via spawn_dropped_item")
	if stub.drops.size() > 0:
		assert_eq(str(stub.drops[0]["def_id"]), "raw_meat", "a land animal drops raw_meat")
		assert_true(bool(stub.drops[0]["active"]), "meat drops as an active (collectable) pickup")
	# w is freed by _die() (queue_free); nothing to free here.


func test_killing_water_creature_drops_sashimi() -> void:
	# WATER creature (shark): a fatal hit drops sashimi instead of raw_meat, via the SAME
	# spawn_dropped_item flow, count, and active-pickup behaviour. Branch is keyed off
	# _KIND_TYPE by kind, so it's correct on this bare instance (no _ready / no display).
	var stub := StubMainScene.new()
	add_child_autofree(stub)
	var w = WildlifeScript.new()
	w.kind = "shark_great_white"
	w.hp = WildlifeScript.MAX_HP
	w.set_main_scene(stub)
	var died := [false]
	w.died.connect(func() -> void: died[0] = true)
	w.take_damage(WildlifeScript.MAX_HP, Vector3(4, 5, 6))
	assert_eq(w.hp, 0, "hp clamps to 0 on a lethal hit")
	assert_true(died[0], "a lethal hit emits died")
	assert_eq(stub.drops.size(), WildlifeScript.MEAT_DROP_COUNT,
		"a killed sea creature drops MEAT_DROP_COUNT items via spawn_dropped_item")
	if stub.drops.size() > 0:
		assert_eq(str(stub.drops[0]["def_id"]), "sashimi", "a sea creature drops sashimi, not raw_meat")
		assert_true(bool(stub.drops[0]["active"]), "sashimi drops as an active (collectable) pickup")
	# w is freed by _die() (queue_free); nothing to free here.


func test_second_hit_after_death_does_not_double_drop() -> void:
	var stub := StubMainScene.new()
	add_child_autofree(stub)
	var w = WildlifeScript.new()
	w.kind = "pig"
	w.hp = 1
	w.set_main_scene(stub)
	w.take_damage(5, Vector3.ZERO)   # kills + drops once
	w.take_damage(5, Vector3.ZERO)   # guarded by _dead — must be a no-op
	assert_eq(stub.drops.size(), WildlifeScript.MEAT_DROP_COUNT,
		"a dead animal cannot be hit again to drop more meat")
