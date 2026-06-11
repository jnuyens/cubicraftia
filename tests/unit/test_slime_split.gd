# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_slime_split.gd — Unit tests for cube slime tier-split on defeat.
#
# Anchors:
#   DOCS.md §5.2 — cube slime with 3-tier split: LARGE→3 MEDIUM, MEDIUM→2 SMALL, SMALL→none
#   03-CONTEXT.md D-09 — slime split with anticipation gather; green-particle burst
#   03-RESEARCH.md Pitfall 3 — use call_deferred for slime child spawn, not _ready()
#   03-RESEARCH.md Pattern 2 — HostileMob state machine (DEAD state → _on_die())
#
# These tests reference CubeSlime mob class shipping in Plan 03-09.
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


# ─── Test 1: LARGE slime splits into 3 MEDIUM on defeat ──────────────────────

func test_large_slime_split_into_three_mediums_on_defeat() -> void:
	# DOCS §5.2: LARGE cube_slime dies → 3 cube_slime at tier=MEDIUM are spawned.
	# Per 03-RESEARCH.md Pitfall 3: children spawned via call_deferred.
	if not ClassDB.class_exists("CubeSlime"):
		pending("CubeSlime class not available — pending until Plan 03-09")
		return
	var slime: Object = ClassDB.instantiate("CubeSlime")
	if slime == null:
		pending("CubeSlime could not be instantiated — pending until Plan 03-09")
		return
	add_child(slime)
	slime.set("tier", slime.get("Tier_LARGE") if slime.has_meta("Tier_LARGE") else 0)
	slime.hp = 1
	# Track children added to the parent.
	var spawned_children: Array = []
	# Monitor for newly added slimes in the group.
	get_tree().call_group("cube_slime", "queue_free")  # Clear any existing slimes.
	slime._on_die()
	await get_tree().process_frame
	await get_tree().process_frame
	var slimes_in_world: Array = get_tree().get_nodes_in_group("cube_slime")
	assert_eq(slimes_in_world.size(), 3,
		"LARGE cube_slime death should spawn exactly 3 children (MEDIUM tier per DOCS §5.2)")
	for child: Node in slimes_in_world:
		var child_tier: int = child.get("tier")
		var medium_tier: int = child.get("Tier_MEDIUM") if child.has_meta("Tier_MEDIUM") else 1
		assert_eq(child_tier, medium_tier,
			"All spawned children of LARGE slime must be tier=MEDIUM")
	slime.queue_free()


# ─── Test 2: MEDIUM slime splits into 2 SMALL on defeat ──────────────────────

func test_medium_slime_split_into_two_smalls_each() -> void:
	# DOCS §5.2: MEDIUM cube_slime dies → 2 cube_slime at tier=SMALL.
	if not ClassDB.class_exists("CubeSlime"):
		pending("CubeSlime class not available — pending until Plan 03-09")
		return
	var slime: Object = ClassDB.instantiate("CubeSlime")
	if slime == null:
		pending("CubeSlime could not be instantiated — pending until Plan 03-09")
		return
	add_child(slime)
	slime.set("tier", slime.get("Tier_MEDIUM") if slime.has_meta("Tier_MEDIUM") else 1)
	slime.hp = 1
	get_tree().call_group("cube_slime", "queue_free")
	slime._on_die()
	await get_tree().process_frame
	await get_tree().process_frame
	var slimes_in_world: Array = get_tree().get_nodes_in_group("cube_slime")
	assert_eq(slimes_in_world.size(), 2,
		"MEDIUM cube_slime death should spawn exactly 2 children (SMALL tier per DOCS §5.2)")
	slime.queue_free()


# ─── Test 3: SMALL slime does not split ───────────────────────────────────────

func test_small_slime_no_split() -> void:
	# DOCS §5.2: SMALL cube_slime dies → no children spawned.
	if not ClassDB.class_exists("CubeSlime"):
		pending("CubeSlime class not available — pending until Plan 03-09")
		return
	var slime: Object = ClassDB.instantiate("CubeSlime")
	if slime == null:
		pending("CubeSlime could not be instantiated — pending until Plan 03-09")
		return
	add_child(slime)
	slime.set("tier", slime.get("Tier_SMALL") if slime.has_meta("Tier_SMALL") else 2)
	slime.hp = 1
	get_tree().call_group("cube_slime", "queue_free")
	slime._on_die()
	await get_tree().process_frame
	await get_tree().process_frame
	var slimes_in_world: Array = get_tree().get_nodes_in_group("cube_slime")
	assert_eq(slimes_in_world.size(), 0,
		"SMALL cube_slime death must NOT spawn any children (DOCS §5.2)")
	slime.queue_free()


# ─── Test 4: Split children spawn outside parent collider footprint ───────────

func test_split_children_spawn_outside_parent_collider_footprint() -> void:
	# 03-RESEARCH.md Pitfall 3: child slimes must spawn at a position offset from parent
	# so they don't overlap and cause physics tunneling.
	if not ClassDB.class_exists("CubeSlime"):
		pending("CubeSlime class not available — pending until Plan 03-09")
		return
	var slime: Object = ClassDB.instantiate("CubeSlime")
	if slime == null:
		pending("CubeSlime could not be instantiated — pending until Plan 03-09")
		return
	add_child(slime)
	slime.global_position = Vector3(0.0, 1.0, 0.0)
	slime.set("tier", slime.get("Tier_LARGE") if slime.has_meta("Tier_LARGE") else 0)
	slime.hp = 1
	get_tree().call_group("cube_slime", "queue_free")
	slime._on_die()
	await get_tree().process_frame
	await get_tree().process_frame
	var slimes_in_world: Array = get_tree().get_nodes_in_group("cube_slime")
	for child: Node in slimes_in_world:
		var dist: float = (child as Node3D).global_position.distance_to(slime.global_position)
		assert_true(dist > 0.1,
			"Spawned child slime must be offset from parent position (Pitfall 3 — no collider overlap)")
	slime.queue_free()
