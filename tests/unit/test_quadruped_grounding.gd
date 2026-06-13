# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_quadruped_grounding.gd: Regression guard: the panda (the one creature driven by the
# rigid-piece QuadrupedAnimator leg-rig, not a skinned GLB) must stand with its FEET ON the
# terrain surface, both idle and while the leg rig animates, never half-buried, never
# floating. Pins the contract that the assembled-rig foot datum is measured and grounded to.
#
# Mechanism under test:
#   - QuadrupedAnimator.assembled_local_min_y(), lowest mesh point of the built rig.
#   - wildlife.gd _setup_animator (QUADRUPED branch), base_y = -assembled_local_min_y()*scale.
#   - wildlife.gd _ground_to_collision / _visible_mesh_min_world_y, drop the body so the
#     rig's lowest visible piece rests on the meshed terrain.
#   - wildlife.gd _process_land ground_y clamp, catch the body on the known surface until it
#     first lands on real collision.
#
# Anchors:
#   src/builder/quadruped_animator.gd
#   src/world/wildlife.gd

extends GutTest

const Wildlife := preload("res://src/world/wildlife.gd")
const QuadrupedAnimator := preload("res://src/builder/quadruped_animator.gd")

## Tolerance (m): feet must contact the surface within this band. The contact settle +
## per-frame gravity micro-bounce keep the body within a few mm; 0.25 m is generous yet
## small enough that a real burial (feet a full leg-length, ~0.3-0.4 m, under the surface)
## or a float fails the assertion.
const _CONTACT_TOL: float = 0.25


## Lowest world-Y of every VISIBLE MeshInstance3D / posed Skeleton3D bone under `node`.
## Mirrors wildlife.gd._visible_mesh_min_world_y, this is the creature's true foot level.
func _visible_feet_y(node: Node) -> float:
	var lowest: float = INF
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			for i in range(sk.get_bone_count()):
				lowest = minf(lowest, (sk.global_transform * sk.get_bone_global_pose(i).origin).y)
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			lowest = minf(lowest, (mi.global_transform * mi.mesh.get_aabb()).position.y)
		for c in n.get_children():
			stack.append(c)
	return lowest


## Build a flat collidable floor whose TOP face is at `top_y`, on physics layer 1 (the
## layer the wildlife grounding cast queries).
func _make_floor(parent: Node, top_y: float) -> void:
	var fb := StaticBody3D.new()
	fb.collision_layer = 1
	fb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(200, 4, 200)
	cs.shape = b
	cs.position = Vector3(0, top_y - 2.0, 0)
	fb.add_child(cs)
	parent.add_child(fb)


func _spawn_panda(parent: Node, ground_y: float, spawn_above: float) -> Node3D:
	var w: Node3D = Wildlife.new()
	w.set("kind", "panda")
	w.set("ground_y", ground_y)
	w.position = Vector3(0, ground_y + spawn_above, 0)
	parent.add_child(w)
	return w


# The assembled rig measures a real, finite, non-positive-only foot datum (legs reach the
# bottom of the rig). If this returned a wrong value, base_y would mis-ground the panda.
func test_assembled_rig_min_y_is_measured() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var quad: Node3D = QuadrupedAnimator.new()
	quad.set("mesh_set", "panda")
	root.add_child(quad)  # _ready builds the rig synchronously
	var min_y: float = quad.assembled_local_min_y()
	# The panda rig's lowest piece (feet) is its bottom; assert it was actually found
	# (a finite number) and is at/below the body pivots (<= the body piece's bottom ~0.2).
	assert_true(min_y < 0.21, "assembled rig min_y (%.4f) should be at the feet, below the body" % min_y)
	assert_true(min_y > -2.0 and min_y < 2.0, "assembled rig min_y (%.4f) should be finite/sane" % min_y)


func test_panda_feet_on_surface_idle() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_y := 20.0
	_make_floor(root, floor_y)
	var w := _spawn_panda(root, floor_y, 0.5)
	for i in range(45):
		await get_tree().physics_frame
	var feet: float = _visible_feet_y(w.get("_body"))
	assert_almost_eq(feet, floor_y, _CONTACT_TOL,
		"idle panda feet (%.3f) must rest on the surface (%.1f)" % [feet, floor_y])


func test_panda_feet_on_surface_walking() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_y := 20.0
	_make_floor(root, floor_y)
	var w := _spawn_panda(root, floor_y, 0.5)
	for i in range(45):
		await get_tree().physics_frame
	# Force a sustained walk so the leg rig animates while we sample.
	w.set("_is_walking", true)
	w.set("_phase_timer", 99999.0)
	var anim: Node = w.get("_anim")
	if anim != null:
		anim.set("gait", "walk")
	var worst_below := 0.0
	for i in range(90):
		await get_tree().physics_frame
		var feet: float = _visible_feet_y(w.get("_body"))
		worst_below = minf(worst_below, feet - floor_y)
	var feet_final: float = _visible_feet_y(w.get("_body"))
	assert_almost_eq(feet_final, floor_y, _CONTACT_TOL,
		"walking panda feet (%.3f) must rest on the surface (%.1f)" % [feet_final, floor_y])
	assert_true(worst_below >= -_CONTACT_TOL,
		"walking panda must never sink %.3f m below the surface" % (-worst_below))


# Real-world case: main_scene's noise ground_y estimate sits ABOVE the actual meshed
# collision top. The collision re-ground must still drop the panda onto the REAL surface,
# not strand it floating at the noise height nor leave it buried.
func test_panda_grounds_to_real_collision_when_groundy_estimate_is_high() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var real_top := 20.0
	_make_floor(root, real_top)
	var w := _spawn_panda(root, real_top + 1.5, 0.5)  # ground_y 1.5 m above real surface
	for i in range(60):
		await get_tree().physics_frame
	var feet: float = _visible_feet_y(w.get("_body"))
	assert_almost_eq(feet, real_top, _CONTACT_TOL,
		"panda feet (%.3f) must land on the real collision surface (%.1f), not the high estimate"
			% [feet, real_top])
