# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_anim_minifigure.gd — ANIM-03/04: rigid-piece minifigure rig + builder
# speed→gait mapping.
#
# The animator load()s rig pieces in _ready() (needs a display), so in-tree
# wiring is display-guarded; the speed→gait mapping is tested as pure logic.

extends GutTest

const MinifigScript = preload("res://src/builder/minifigure_animator.gd")
const BuilderScript = preload("res://src/builder/builder.gd")


func test_class_parses() -> void:
	assert_not_null(MinifigScript, "MinifigureAnimator must load without parse error")


func test_rig_has_seven_pieces() -> void:
	assert_eq(MinifigScript.PIECE_NAMES.size(), 7, "builder rig has 7 pieces")
	for piece: String in ["builder_head", "builder_torso", "builder_arm_l",
			"builder_arm_r", "builder_pelvis", "builder_legs_l", "builder_legs_r"]:
		assert_true(MinifigScript.PIECE_NAMES.has(piece), "rig includes %s" % piece)


func test_default_gait_is_idle() -> void:
	var a = MinifigScript.new()
	assert_eq(a.gait, "idle", "default gait is idle")
	a.free()


# ─── ANIM-04: builder horizontal-speed → gait mapping ─────────────────────────
# Mirrors builder.gd _physics_process: idle when |h_velocity| < threshold, else walk.

func _gait_for_speed(h_speed: float) -> String:
	var threshold: float = BuilderScript._RIG_IDLE_SPEED_THRESHOLD
	return "idle" if h_speed < threshold else "walk"


func test_speed_zero_maps_to_idle() -> void:
	assert_eq(_gait_for_speed(0.0), "idle", "0 m/s → idle")


func test_speed_just_below_threshold_maps_to_idle() -> void:
	assert_eq(_gait_for_speed(0.49), "idle", "0.49 m/s → idle (< 0.5)")


func test_speed_above_threshold_maps_to_walk() -> void:
	assert_eq(_gait_for_speed(0.6), "walk", "0.6 m/s → walk")
	assert_eq(_gait_for_speed(4.0), "walk", "running speed → walk")


func test_threshold_constant_is_half_metre_per_second() -> void:
	assert_almost_eq(BuilderScript._RIG_IDLE_SPEED_THRESHOLD, 0.5, 0.0001,
		"idle/walk threshold is 0.5 m/s per ANIM-04")


func test_in_tree_ready_builds_rig() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display for rig .glb load")
		return
	var a = add_child_autofree(MinifigScript.new())
	await get_tree().process_frame
	assert_gt(a.get_child_count(), 0, "MinifigureAnimator._ready should add pivot nodes")
