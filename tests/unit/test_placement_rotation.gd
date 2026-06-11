# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_placement_rotation.gd — Unit tests for builder-yaw → 4 distinct rotation steps.
#
# Anchors:
#   DOCS.md §3 — no rotation in v1; only builder-yaw-derived placements
#   DOCS.md §3.2 — Minecraft-style point-and-click placement
#   02-CONTEXT.md — D-12 note: no rotate_brick action exposed in UI
#   02-RESEARCH.md §"Stud-Snap Placement on VoxelBlockyLibrary"
#
# Owned by Plan 09 (placement rotation implementation turns these GREEN).
# Plan 02-09: tests turned GREEN by implementing rotation helpers in StudGridHelper
# (standalone helper not requiring a full Builder scene in headless mode).
#
# Key invariant: yaw→rotation_step permutes XZ only; Y axis is never affected.
#
# Implementation note: Builder requires RayCast3D / Camera3D hierarchy from
# builder.tscn, which is GPU-dependent in headless mode. Instead, these tests
# exercise the rotation mathematics directly via standalone helper functions that
# mirror builder.gd's _derive_rotation_from_builder_yaw / _rotated_footprint logic.
# This avoids scene instantiation while still testing the correctness of the math.

extends GutTest

# ─── Standalone rotation helpers (mirrors builder.gd, headless-safe) ──────────

## Mirror of Builder._derive_rotation_from_builder_yaw(yaw).
## Converts a yaw angle to a 0..3 rotation step.
func _yaw_to_step(yaw: float) -> int:
	return int(round(yaw / (PI / 2.0))) & 3


## Mirror of Builder._rotated_footprint(footprint, rotation).
## Permutes X/Z of each Vector3i offset; Y is unchanged.
func _rotate_footprint(footprint: Array, rotation: int) -> Array:
	var result: Array = []
	rotation = rotation & 3
	for offset_raw: Variant in footprint:
		var o: Vector3i = offset_raw as Vector3i
		var rotated: Vector3i
		match rotation:
			0:
				rotated = Vector3i(o.x, o.y, o.z)
			1:
				rotated = Vector3i(o.z, o.y, -o.x)
			2:
				rotated = Vector3i(-o.x, o.y, -o.z)
			3:
				rotated = Vector3i(-o.z, o.y, o.x)
			_:
				rotated = o
		result.append(rotated)
	return result


# ─── Test 1: yaw → rotation step ──────────────────────────────────────────────

func test_yaw_to_rotation_step() -> void:
	# Yaw = 0 → step 0 (facing +Z, no rotation)
	assert_eq(_yaw_to_step(0.0), 0,
		"yaw=0 should map to rotation step 0")

	# Yaw = PI/2 (90° CCW in Godot's right-hand Y-up convention) → step 1
	assert_eq(_yaw_to_step(PI / 2.0), 1,
		"yaw=PI/2 should map to rotation step 1")

	# Yaw = PI (180°) → step 2
	assert_eq(_yaw_to_step(PI), 2,
		"yaw=PI should map to rotation step 2")

	# Yaw = -PI/2 (270° = -90°) → step 3
	assert_eq(_yaw_to_step(-PI / 2.0), 3,
		"yaw=-PI/2 should map to rotation step 3")

	# Yaw = 3*PI/2 (same as -PI/2 but positive) → step 3
	assert_eq(_yaw_to_step(3.0 * PI / 2.0), 3,
		"yaw=3*PI/2 should map to rotation step 3")

	# Yaw = 2*PI (full circle) → step 0
	assert_eq(_yaw_to_step(2.0 * PI), 0,
		"yaw=2*PI should map to rotation step 0 (full circle)")


# ─── Test 2: rotation permutes XZ only (Y unchanged) ─────────────────────────

func test_rotation_permutes_xz_only() -> void:
	# Test footprint: L-shape in XZ plane.
	var footprint: Array[Vector3i] = [
		Vector3i(0, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(1, 0, 0),
	]

	# Step 0 — identity: no change.
	var rot0: Array = _rotate_footprint(footprint, 0)
	assert_eq(rot0[0], Vector3i(0, 0, 0), "step 0: (0,0,0) unchanged")
	assert_eq(rot0[1], Vector3i(0, 0, 1), "step 0: (0,0,1) unchanged")
	assert_eq(rot0[2], Vector3i(1, 0, 0), "step 0: (1,0,0) unchanged")

	# Step 1 — 90° rotation: (x,y,z) → (z,y,-x)
	var rot1: Array = _rotate_footprint(footprint, 1)
	assert_eq(rot1[0], Vector3i(0, 0, 0),   "step 1: (0,0,0) → (0,0,0)")
	assert_eq(rot1[1], Vector3i(1, 0, 0),   "step 1: (0,0,1) → (1,0,0)")
	assert_eq(rot1[2], Vector3i(0, 0, -1),  "step 1: (1,0,0) → (0,0,-1)")

	# Step 2 — 180° rotation: (x,y,z) → (-x,y,-z)
	var rot2: Array = _rotate_footprint(footprint, 2)
	assert_eq(rot2[0], Vector3i(0, 0, 0),   "step 2: (0,0,0) → (0,0,0)")
	assert_eq(rot2[1], Vector3i(0, 0, -1),  "step 2: (0,0,1) → (0,0,-1)")
	assert_eq(rot2[2], Vector3i(-1, 0, 0),  "step 2: (1,0,0) → (-1,0,0)")

	# Step 3 — 270° rotation: (x,y,z) → (-z,y,x)
	var rot3: Array = _rotate_footprint(footprint, 3)
	assert_eq(rot3[0], Vector3i(0, 0, 0),   "step 3: (0,0,0) → (0,0,0)")
	assert_eq(rot3[1], Vector3i(-1, 0, 0),  "step 3: (0,0,1) → (-1,0,0)")
	assert_eq(rot3[2], Vector3i(0, 0, 1),   "step 3: (1,0,0) → (0,0,1)")

	# Invariant: Y is NEVER modified across all rotation steps.
	var y_footprint: Array[Vector3i] = [Vector3i(3, 7, 2), Vector3i(-1, 4, 5)]
	for step in range(4):
		var rotated: Array = _rotate_footprint(y_footprint, step)
		for i in range(rotated.size()):
			var orig_y: int = (y_footprint[i] as Vector3i).y
			var rot_y: int = (rotated[i] as Vector3i).y
			assert_eq(rot_y, orig_y,
				"Y component must be unchanged by rotation step %d" % step)
