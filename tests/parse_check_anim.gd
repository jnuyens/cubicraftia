# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# parse_check_anim.gd — Headless load()-based parse check for Phase 8 anim files.
#
# Usage:
#   godot --headless --script tests/parse_check_anim.gd
#
# Verifies every Phase 8 modified/new script loads (parses) without error.
# Exits 0 on success, 1 on any failure.

extends SceneTree

func _init() -> void:
	var files: Array[String] = [
		"res://src/builder/procedural_creature_animator.gd",
		"res://src/builder/minifigure_animator.gd",
		"res://src/builder/quadruped_animator.gd",
		"res://src/builder/shader_wobble_animator.gd",
		"res://src/builder/builder.gd",
		"res://src/world/wildlife.gd",
		"res://src/combat/hostile_mob.gd",
		"res://src/combat/vampire.gd",
		"res://src/combat/ghost.gd",
		"res://src/combat/cube_slime.gd",
		"res://src/combat/bat.gd",
		"res://src/combat/laser_penguin.gd",
	]
	var ok: bool = true
	for path: String in files:
		var res: Resource = load(path)
		if res == null:
			push_error("PARSE FAIL: %s" % path)
			ok = false
		else:
			print("PARSE OK: %s" % path)
	if ok:
		print("All Phase 8 anim scripts parsed successfully.")
		quit(0)
	else:
		push_error("One or more Phase 8 anim scripts failed to parse.")
		quit(1)
