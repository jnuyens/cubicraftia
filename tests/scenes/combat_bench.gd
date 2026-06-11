# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# combat_bench.gd — Controller script for the 10-hostile combat benchmark scene.
#
# This scene is the empty shell for Plan 03-11's Tier-3 perf gate.
# Plan 03-11 wires the actual hostile classes; this script defines the spawn interface.
#
# Usage (Plan 03-11):
#   var packed := preload("res://tests/scenes/combat_bench.tscn")
#   var bench := packed.instantiate()
#   add_child(bench)
#   bench.spawn_hostiles(10)
#   # Run benchmark for N frames, sample FPS.
#
# Anchors:
#   03-PLAN.md 03-01 Task 2 — combat_bench.tscn shell for Plan 03-11 perf gate
#   03-CONTEXT.md D-09 — up to ~10 active hostiles per chunk on Tier-3 device
#   DOCS.md §7 — Tier-3 performance requirements (Motorola One Macro)

extends Node3D

## Maximum number of hostile mobs to spawn in this benchmark.
const MAX_HOSTILE_COUNT: int = 10

## Array of spawned hostile nodes for cleanup.
var _spawned_hostiles: Array = []

## Reference to the spawn root node (child named "HostileSpawnRoot").
@onready var _spawn_root: Node3D = $HostileSpawnRoot


func _ready() -> void:
	# Plan 03-11 will call spawn_hostiles() after instantiating this scene.
	# For now, the scene is an empty shell.
	pass


## Spawn N hostile mobs at world origin for the benchmark.
## Plan 03-11 replaces the placeholder with real hostile classes.
##
## @param count  Number of hostile mobs to spawn (capped at MAX_HOSTILE_COUNT).
func spawn_hostiles(count: int) -> void:
	var actual_count: int = mini(count, MAX_HOSTILE_COUNT)
	for i: int in range(actual_count):
		# Placeholder: Plan 03-11 replaces this with actual hostile instantiation.
		# e.g. var hostile := preload("res://src/combat/laser_penguin.tscn").instantiate()
		var placeholder := Node3D.new()
		placeholder.name = "HostilePlaceholder_%d" % i
		placeholder.global_position = Vector3(
			randf_range(-5.0, 5.0),
			0.0,
			randf_range(-5.0, 5.0)
		)
		_spawn_root.add_child(placeholder)
		_spawned_hostiles.append(placeholder)
	push_warning("combat_bench: spawned %d placeholder hostiles (Plan 03-11 wires real classes)" % actual_count)


## Return the count of currently spawned hostiles.
func get_hostile_count() -> int:
	return _spawned_hostiles.size()


## Clear all spawned hostiles (for reset between benchmark runs).
func clear_hostiles() -> void:
	for h: Node in _spawned_hostiles:
		if is_instance_valid(h):
			h.queue_free()
	_spawned_hostiles.clear()
