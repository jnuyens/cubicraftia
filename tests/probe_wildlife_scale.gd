# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# probe_wildlife_scale.gd — measures the actual RENDERED height of wildlife creatures
# in IDLE and WALKING states, and asserts it equals _TARGET_HEIGHT within ~10%.
#
# Run as a SCENE (so the project autoloads — BrickRegistry / Inventory — boot):
#   godot --headless tests/probe_wildlife_scale.tscn
#
# Instantiates each probed kind, lets the one-frame-deferred posed-skeleton scale+ground
# run, measures the visible-mesh world-AABB Y span while idle, then forces the walk visual
# and re-measures. Reports ratio rendered/target for both states.

extends Node

const WildlifeScript := preload("res://src/world/wildlife.gd")

const _PROBE_KINDS: Array[String] = [
	"polar_bear", "husky_dog", "penguin", "dog", "arctic_wolf", "arctic_fox",
	"sheep", "giraffe", "camel", "caribou", "reindeer", "pig", "monkey",
	"gnu", "elephant", "snow_rabbit", "meerkat", "vulture", "toucan",
	"flamingo", "seagull", "snowy_owl", "scorpion", "rattlesnake",
	"desert_lizard", "desert_mouse", "fennec_fox",
	"orca", "panda",
]

# Kinds driven by self-sizing animators (QuadrupedAnimator panda / ShaderWobble fish) that do
# NOT use _TARGET_HEIGHT for their visual scale — reported for info, never asserted.
const _SELF_SIZED: Array[String] = ["panda", "fish_blue", "fish_orange", "fish_yellow"]

func _ready() -> void:
	_run.call_deferred()

func _await_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _visible_mesh_aabb_y(node: Node3D) -> float:
	# World-space Y span of every VISIBLE MeshInstance3D / posed Skeleton3D under node.
	var lo := INF
	var hi := -INF
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is Skeleton3D:
			var sk := n as Skeleton3D
			if sk.get_bone_count() > 0:
				for i in range(sk.get_bone_count()):
					var bw: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
					lo = minf(lo, bw.y)
					hi = maxf(hi, bw.y)
				continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			lo = minf(lo, box.position.y)
			hi = maxf(hi, box.position.y + box.size.y)
		for c in n.get_children():
			stack.append(c)
	if lo == INF:
		return -1.0
	return hi - lo

func _run() -> void:
	var targets: Dictionary = WildlifeScript._TARGET_HEIGHT
	var fails: int = 0
	print("PROBE_BEGIN")
	print("kind                 target   idle    ratioI   walk    ratioW")
	print("-------------------- ------ ------- -------- ------- --------")
	for kind in _PROBE_KINDS:
		var w = WildlifeScript.new()
		w.kind = kind
		add_child(w)
		# Let _ready + call_deferred(_ground_to_collision / _ground_skinned_to_target) run.
		await _await_frames(4)

		var target: float = float(targets.get(kind, 1.4))
		var host: Node3D = w._body if w._body != null else w

		# IDLE measure: ensure idle visual is the one shown.
		if w._skinned_anim != null:
			if w._anim != null:
				(w._anim as Node3D).visible = false
			if w._mesh_root != null:
				w._mesh_root.visible = true
		await _await_frames(1)
		var idle_h: float = _visible_mesh_aabb_y(host)

		# WALK measure: force the rigged walk visual (skinned) or quadruped walk gait.
		if w._skinned_anim != null:
			if w._anim != null:
				(w._anim as Node3D).visible = true
			if w._mesh_root != null:
				w._mesh_root.visible = false
			if w._skinned_walk_name != "":
				w._skinned_anim.play(w._skinned_walk_name)
				w._skinned_anim.seek(0.0, true)
		await _await_frames(2)
		var walk_h: float = _visible_mesh_aabb_y(host)

		var ri: float = idle_h / target if target > 0.0 and idle_h > 0.0 else -1.0
		var rw: float = walk_h / target if target > 0.0 and walk_h > 0.0 else -1.0
		var note: String = "  (self-sized)" if kind in _SELF_SIZED else ""
		print("%-20s %5.2f  %6.2f  %6.2f   %6.2f  %6.2f%s" % [kind, target, idle_h, ri, walk_h, rw, note])

		# Assert both within 10% of target (self-sized animators excluded; -1 = not measured).
		if kind not in _SELF_SIZED:
			if ri > 0.0 and (ri < 0.9 or ri > 1.1):
				fails += 1
			if rw > 0.0 and (rw < 0.9 or rw > 1.1):
				fails += 1

		w.queue_free()
		await _await_frames(1)

	print("-------------------- ------ ------- -------- ------- --------")
	if fails == 0:
		print("ALL PASS (every measured idle & walk height within 10pct of target)")
	else:
		print("FAILURES: %d height(s) outside 10pct of target" % fails)
	print("PROBE_END")
	get_tree().quit(0 if fails == 0 else 1)
