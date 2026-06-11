# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_anim_hostiles.gd — ANIM-05: each of the 5 hostile types is wired to the
# correct animator path.
#
# Pure-API checks on .new() instances (the animator's load()/_ready needs a
# display, so full in-tree wiring is display-guarded with pending()):
#   - ghost / cube_slime / vampire override _art_kind() → "" so the base
#     _apply_art_mesh no-ops (Pitfall 2: no double mesh load; typed animator
#     is the sole visual).
#   - bat / laser_penguin keep their TripoSR _art_kind() and use the procedural
#     fallback.

extends GutTest

const ProcScript = preload("res://src/builder/procedural_creature_animator.gd")
const GhostScript = preload("res://src/combat/ghost.gd")
const SlimeScript = preload("res://src/combat/cube_slime.gd")
const VampireScript = preload("res://src/combat/vampire.gd")
const BatScript = preload("res://src/combat/bat.gd")
const PenguinScript = preload("res://src/combat/laser_penguin.gd")


func test_all_hostile_scripts_parse() -> void:
	for s in [GhostScript, SlimeScript, VampireScript, BatScript, PenguinScript]:
		assert_not_null(s, "hostile script must load without parse error")
	assert_not_null(ProcScript, "ProceduralCreatureAnimator must load")


# ─── v1.1 art pass: ghost/slime/vampire now use textured Meshy art meshes ─────
# (previously they returned "" so the wobble/minifig animator was the sole visual;
#  the art pass replaced those with textured meshes loaded via _apply_art_mesh.)

func test_ghost_art_kind_is_ghost() -> void:
	var g = GhostScript.new()
	assert_eq(g._art_kind(), "ghost", "ghost _art_kind() loads the textured ghost art mesh")
	g.free()


func test_slime_art_kind_is_slime() -> void:
	var s = SlimeScript.new()
	assert_eq(s._art_kind(), "slime", "cube_slime _art_kind() loads the textured slime art mesh")
	s.free()


func test_vampire_art_kind_is_vampire() -> void:
	var v = VampireScript.new()
	assert_eq(v._art_kind(), "vampire", "vampire _art_kind() loads the textured vampire art mesh")
	v.free()


# ─── Procedural-fallback mobs keep their TripoSR art ──────────────────────────

func test_bat_art_kind_triposr() -> void:
	var b = BatScript.new()
	assert_eq(b._art_kind(), "bat", "regular bat keeps its TripoSR 'bat' art")
	b.variant = "vampire"
	assert_eq(b._art_kind(), "vampire_bat", "vampire bat variant uses 'vampire_bat' art")
	b.free()


func test_penguin_art_kind_triposr() -> void:
	var p = PenguinScript.new()
	assert_eq(p._art_kind(), "laser_penguin", "penguin keeps its TripoSR 'laser_penguin' art")
	p.free()


# ─── Procedural animator API ──────────────────────────────────────────────────

func test_procedural_motion_enum() -> void:
	assert_eq(int(ProcScript.Motion.LAND), 0)
	assert_eq(int(ProcScript.Motion.AIR), 1)
	assert_eq(int(ProcScript.Motion.WATER), 2)


func test_procedural_update_null_safe() -> void:
	var a = ProcScript.new(ProcScript.Motion.LAND)
	# update() against a null mesh-root must not error.
	a.update(null, 0.016, false)
	pass_test("ProceduralCreatureAnimator.update(null, ...) is a safe no-op")


func test_procedural_land_writes_only_pos_y_and_rot_z() -> void:
	var a = ProcScript.new(ProcScript.Motion.LAND)
	var root := Node3D.new()
	a.update(root, 0.2, false)
	# Pitfall 1: never write rotation.x / rotation.y / scale on the mesh-root.
	assert_eq(root.rotation.x, 0.0, "LAND fallback must not touch rotation.x")
	assert_eq(root.rotation.y, 0.0, "LAND fallback must not touch rotation.y")
	assert_eq(root.scale, Vector3.ONE, "LAND fallback must not touch scale")
	root.free()


func test_procedural_water_does_not_write_position_y() -> void:
	var a = ProcScript.new(ProcScript.Motion.WATER)
	var root := Node3D.new()
	for _i in range(20):
		a.update(root, 0.05, false)
	# Pitfall 1: WATER/AIR must not write position.y (it fights _process_water/_air).
	assert_eq(root.position.y, 0.0, "WATER fallback must not write position.y")
	assert_eq(root.rotation.x, 0.0, "WATER fallback must not touch rotation.x")
	assert_eq(root.scale, Vector3.ONE, "WATER fallback must not touch scale")
	root.free()
