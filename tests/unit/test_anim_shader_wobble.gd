# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_anim_shader_wobble.gd — ANIM-01: GPU wobble animator (slime/fish/ghost).
#
# The animator load()s a .glb + shader in _ready() and needs a GPU, so in-tree
# wiring is display-guarded with pending(); the rest is parse + pure-API checks.

extends GutTest

const WobbleScript = preload("res://src/builder/shader_wobble_animator.gd")
const CubeSlimeScript = preload("res://src/combat/cube_slime.gd")
const GhostScript = preload("res://src/combat/ghost.gd")


func test_class_parses() -> void:
	assert_not_null(WobbleScript, "ShaderWobbleAnimator must load without parse error")


func test_body_type_enum_has_three_kinds() -> void:
	assert_eq(int(WobbleScript.BodyType.SLIME), 0, "SLIME == 0")
	assert_eq(int(WobbleScript.BodyType.FISH), 1, "FISH == 1")
	assert_eq(int(WobbleScript.BodyType.GHOST), 2, "GHOST == 2")


func test_new_instance_has_expected_default_properties() -> void:
	var a = WobbleScript.new()
	assert_eq(a.mesh_set, "slime", "default mesh_set is slime")
	assert_eq(int(a.body_type), int(WobbleScript.BodyType.SLIME), "default body_type is SLIME")
	assert_eq(a.time_offset, 0.0, "default time_offset is 0")
	a.free()


func test_properties_are_settable() -> void:
	var a = WobbleScript.new()
	a.mesh_set = "fish_blue"
	a.body_type = WobbleScript.BodyType.FISH
	a.body_colour = Color("#1E69C6")
	a.time_offset = 1.23
	assert_eq(a.mesh_set, "fish_blue")
	assert_eq(int(a.body_type), int(WobbleScript.BodyType.FISH))
	assert_almost_eq(a.time_offset, 1.23, 0.001)
	a.free()


func test_in_tree_ready_attaches_visual() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display/GPU for shader + .glb load")
		return
	var a = add_child_autofree(WobbleScript.new())
	a.mesh_set = "ghost"
	a.body_type = WobbleScript.BodyType.GHOST
	await get_tree().process_frame
	assert_gt(a.get_child_count(), 0, "ShaderWobbleAnimator._ready should add the mesh instance")


# ─── ANIM-01 gap-closure (08-05): hostile soft-body wobble dispatch ────────────
# cube_slime + ghost are hostiles (not wildlife kinds); SC1 names both as soft-body
# wobble creatures. After _ready() each must resolve _anim to a ShaderWobbleAnimator
# with the matching BodyType. Display-gated because the .glb + shader load needs a GPU.

func test_cube_slime_anim_is_shader_wobble_slime() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display/GPU for shader + .glb load")
		return
	var slime = add_child_autofree(CubeSlimeScript.new())
	await get_tree().process_frame
	assert_true(slime._anim is ShaderWobbleAnimator,
		"cube_slime._anim should be a ShaderWobbleAnimator")
	assert_eq(int(slime._anim.body_type), int(WobbleScript.BodyType.SLIME),
		"cube_slime wobble body_type should be SLIME")


func test_ghost_anim_is_shader_wobble_ghost() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display/GPU for shader + .glb load")
		return
	var ghost = add_child_autofree(GhostScript.new())
	await get_tree().process_frame
	assert_true(ghost._anim is ShaderWobbleAnimator,
		"ghost._anim should be a ShaderWobbleAnimator")
	assert_eq(int(ghost._anim.body_type), int(WobbleScript.BodyType.GHOST),
		"ghost wobble body_type should be GHOST")
