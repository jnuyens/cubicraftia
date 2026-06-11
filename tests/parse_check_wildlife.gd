# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# parse_check_wildlife.gd — Headless load()-based parse check for wildlife files.
#
# Usage:
#   godot --headless --script tests/parse_check_wildlife.gd
#
# Verifies that all three wildlife-related scripts load without parse errors.
# Exits 0 on success, 1 on any failure.

extends SceneTree

func _init() -> void:
	var files: Array[String] = [
		"res://src/world/wildlife.gd",
		"res://src/world/wildlife_spawner.gd",
		"res://src/world/main_scene.gd",
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
		print("All wildlife scripts parsed successfully.")
		quit(0)
	else:
		push_error("One or more wildlife scripts failed to parse.")
		quit(1)
