# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_anim_quadruped.gd — ANIM-02: rigid-piece quadruped animator (panda).
#
# The animator load()s the rig pieces in _ready() (needs a display), so in-tree
# wiring is display-guarded; the rest is parse + pure-API checks.

extends GutTest

const QuadScript = preload("res://src/builder/quadruped_animator.gd")
const WildlifeScript = preload("res://src/world/wildlife.gd")


func test_class_parses() -> void:
	assert_not_null(QuadScript, "QuadrupedAnimator must load without parse error")


func test_default_properties() -> void:
	var a = QuadScript.new()
	assert_eq(a.mesh_set, "panda", "default mesh_set is panda")
	assert_eq(a.gait, "idle", "default gait is idle")
	a.free()


func test_piece_names_cover_four_legs_body_head_tail() -> void:
	var names: Array = QuadScript.PIECE_NAMES
	assert_eq(names.size(), 7, "quadruped rig has 7 pieces (4 legs + body + head + tail)")
	for leg: String in ["panda_leg_fl", "panda_leg_fr", "panda_leg_bl", "panda_leg_br"]:
		assert_true(names.has(leg), "rig includes %s" % leg)


func test_gait_is_plain_assignable() -> void:
	var a = QuadScript.new()
	a.gait = "walk"
	assert_eq(a.gait, "walk", "gait set by plain assignment")
	a.gait = "idle"
	assert_eq(a.gait, "idle")
	a.free()


func test_in_tree_ready_builds_rig() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display for rig .glb load")
		return
	var a = add_child_autofree(QuadScript.new())
	await get_tree().process_frame
	assert_gt(a.get_child_count(), 0, "QuadrupedAnimator._ready should add pivot nodes")


# ── 08 gap-closure: dispatch-level wiring (SC2 / ANIM-02) ──────────────────────

func test_wildlife_quadruped_sets_has_panda() -> void:
	# const-level (no display): the panda dispatch dict is populated, so the
	# QUADRUPED branch in wildlife._setup_animator is reachable.
	assert_true(WildlifeScript._QUADRUPED_SETS.has("panda"),
		"_QUADRUPED_SETS maps panda — QuadrupedAnimator branch is live")


func test_in_tree_panda_wildlife_resolves_to_quadruped() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display for panda rig .glb load")
		return
	var w = WildlifeScript.new()
	w.kind = "panda"
	add_child_autofree(w)
	await get_tree().process_frame
	assert_true(w._anim is QuadScript,
		"panda wildlife resolves _anim to QuadrupedAnimator (not the procedural fallback)")
