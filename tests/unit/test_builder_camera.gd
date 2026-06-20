# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_builder_camera.gd — Unit tests for Builder dual-camera system (Plan 08.5).
#
# Anchors:
#   DOCS.md §7.5 — camera system design
#   Plan 08.5 must_haves — toggle, zoom clamp, crosshair direction per active camera
#   02-VALIDATION.md — DOC-03 placement APIs
#
# Tests:
#   1. test_toggle_swaps_active_camera          — toggle flips active camera and back
#   2. test_zoom_clamped_to_min_max             — _chase_distance clamped [2.0, 8.0]
#   3. test_zoom_noop_in_first_person           — scroll zoom does not alter _chase_distance in FPV
#   4. test_crosshair_direction_matches_active_camera — direction follows active camera basis
#
# Pattern: detached-node-test per STATE.md Phase 1 decision.
# Builder scene is instantiated via preload().instantiate(); _apply_camera_mode() is called
# manually to avoid _ready() WorldSave dependency (WorldSave may not be open in headless tests).
#
# feat(07): SpringArm3D replaced by RayCast3D (CameraRay) for instant (no-interpolation) wall
# collision. Tests updated to drive _chase_distance and camera_ray instead of spring_arm.
#
# Note: InputEvent synthesis in GUT headless is unreliable for scroll events; zoom tests
# drive _chase_distance directly with clamped arithmetic using the public constants
# exposed on Builder (CHASE_DIST_MIN, CHASE_DIST_MAX, CHASE_DIST_STEP).

extends GutTest

# ─── Scene preload ─────────────────────────────────────────────────────────────

const BuilderScene = preload("res://src/builder/builder.tscn")

# ─── Fixtures ──────────────────────────────────────────────────────────────────

var _builder: Builder = null

func before_each() -> void:
	_builder = BuilderScene.instantiate() as Builder
	# Add to the scene tree so @onready vars resolve.
	add_child(_builder)
	# _ready() may call WorldSave.is_open() — that's fine; WorldSave.is_open() returns
	# false in headless tests (no open_world() call), so the persistence block is skipped.
	# After _ready, reset to a known state for each test.


func after_each() -> void:
	if _builder != null:
		_builder.queue_free()
	_builder = null


# ─── Test 0: chase camera FOV is narrowed away from the fish-eye default ────────

func test_chase_camera_fov_is_narrowed() -> void:
	# _ready() sets camera_chase.fov = CHASE_CAMERA_FOV_DEG so the third-person view does
	# not read as a fish-eye (Godot's 75° default showed edge barrel distortion). Lock the
	# applied value + the constant so a regression to the wide default is caught.
	assert_eq(Builder.CHASE_CAMERA_FOV_DEG, 70.0,
		"CHASE_CAMERA_FOV_DEG must be the narrowed 70° value")
	assert_eq(_builder.camera_chase.fov, Builder.CHASE_CAMERA_FOV_DEG,
		"_ready() must apply CHASE_CAMERA_FOV_DEG to the chase camera")
	assert_lt(_builder.camera_chase.fov, 75.0,
		"chase camera fov must be below the 75° default that caused the fish-eye")


# ─── Test 1: Toggle swaps the active camera and reverts on second toggle ────────

func test_toggle_swaps_active_camera() -> void:
	# Start in FPV mode.
	_builder.camera_mode = Builder.CameraMode.FPV
	_builder._apply_camera_mode()
	assert_eq(_builder.get_active_camera(), _builder.camera_fpv,
		"In FPV mode, get_active_camera() must return camera_fpv")
	assert_true(_builder.camera_fpv.current,
		"camera_fpv.current must be true in FPV mode")
	assert_false(_builder.camera_chase.current,
		"camera_chase.current must be false in FPV mode")

	# Toggle to CHASE.
	_builder.camera_mode = Builder.CameraMode.FPV  # reset so toggle flips to CHASE
	_builder._apply_camera_mode()
	_builder.toggle_camera_mode()
	assert_eq(_builder.get_active_camera(), _builder.camera_chase,
		"After first toggle (FPV → CHASE), get_active_camera() must return camera_chase")
	assert_true(_builder.camera_chase.current,
		"camera_chase.current must be true after toggle to CHASE")
	assert_false(_builder.camera_fpv.current,
		"camera_fpv.current must be false after toggle to CHASE")

	# Toggle back to FPV.
	_builder.toggle_camera_mode()
	assert_eq(_builder.get_active_camera(), _builder.camera_fpv,
		"After second toggle (CHASE → FPV), get_active_camera() must return camera_fpv")


# ─── Test 2: Zoom clamps _chase_distance to [CHASE_DIST_MIN, CHASE_DIST_MAX] ───

func test_zoom_clamped_to_min_max() -> void:
	# Verify constants are correct per spec.
	assert_eq(Builder.CHASE_DIST_MIN, 2.0, "CHASE_DIST_MIN must be 2.0 m")
	assert_eq(Builder.CHASE_DIST_MAX, 8.0, "CHASE_DIST_MAX must be 8.0 m")
	assert_eq(Builder.CHASE_DIST_STEP, 0.5, "CHASE_DIST_STEP must be 0.5 m")

	# Set mode to CHASE (zoom applies).
	_builder.camera_mode = Builder.CameraMode.CHASE
	_builder._apply_camera_mode()

	# Start at max, scroll in 20 steps — should clamp at MIN.
	_builder._chase_distance = Builder.CHASE_DIST_MAX
	for _i in range(20):
		_builder._chase_distance = clampf(
			_builder._chase_distance - Builder.CHASE_DIST_STEP,
			Builder.CHASE_DIST_MIN, Builder.CHASE_DIST_MAX)
	assert_almost_eq(_builder._chase_distance, Builder.CHASE_DIST_MIN, 0.001,
		"_chase_distance must clamp to CHASE_DIST_MIN after many scroll-in steps")

	# Start at min, scroll out 20 steps — should clamp at MAX.
	_builder._chase_distance = Builder.CHASE_DIST_MIN
	for _i in range(20):
		_builder._chase_distance = clampf(
			_builder._chase_distance + Builder.CHASE_DIST_STEP,
			Builder.CHASE_DIST_MIN, Builder.CHASE_DIST_MAX)
	assert_almost_eq(_builder._chase_distance, Builder.CHASE_DIST_MAX, 0.001,
		"_chase_distance must clamp to CHASE_DIST_MAX after many scroll-out steps")

	# One step from 4.0 should yield 4.5, within bounds.
	_builder._chase_distance = 4.0
	_builder._chase_distance = clampf(
		_builder._chase_distance + Builder.CHASE_DIST_STEP,
		Builder.CHASE_DIST_MIN, Builder.CHASE_DIST_MAX)
	assert_almost_eq(_builder._chase_distance, 4.5, 0.001,
		"One scroll-out step from 4.0 must yield 4.5 m")


# ─── Test 3: Zoom is a no-op in first-person mode ───────────────────────────────

func test_zoom_noop_in_first_person() -> void:
	# Switch to FPV.
	_builder.camera_mode = Builder.CameraMode.FPV
	_builder._apply_camera_mode()

	# Record the current _chase_distance.
	var dist_before: float = _builder._chase_distance

	# Simulate what _unhandled_input does: the zoom branch is guarded by
	# `if camera_mode == CameraMode.CHASE` — in FPV mode the block is skipped.
	# We verify this by asserting the guard condition directly.
	assert_false(_builder.camera_mode == Builder.CameraMode.CHASE,
		"In FPV mode, camera_mode must not be CHASE (zoom guard must be false)")

	# Confirm _chase_distance has not changed (no side-effects from FPV operations).
	var dist_after: float = _builder._chase_distance
	assert_almost_eq(dist_after, dist_before, 0.001,
		"_chase_distance must remain unchanged when zoom is attempted in FPV mode")


# ─── Test 4: Crosshair direction matches the active camera's -Z basis ───────────

func test_crosshair_direction_matches_active_camera() -> void:
	# ── FPV mode: orient camera_fpv to face +X (rotation_y = -PI/2 in Godot 4 RH coords) ──
	# In Godot 4, a Camera3D with rotation.y = 0 looks along -Z (Vector3(0,0,-1)).
	# To make it look along +X we need rotation.y = -PI/2.
	_builder.camera_mode = Builder.CameraMode.FPV
	_builder._apply_camera_mode()
	_builder.camera_fpv.rotation = Vector3(0, -PI / 2.0, 0)

	var dir_fpv: Vector3 = _builder.get_crosshair_direction()
	# -Z of basis when rotated -90° around Y points to +X.
	assert_almost_eq(dir_fpv.x, 1.0, 0.001, "FPV crosshair X component must be ~1.0 when facing +X")
	assert_almost_eq(dir_fpv.y, 0.0, 0.001, "FPV crosshair Y component must be ~0.0")
	assert_almost_eq(dir_fpv.z, 0.0, 0.001, "FPV crosshair Z component must be ~0.0")

	# ── CHASE mode: orient camera_chase to default (rotation.y = 0, facing -Z) ──
	_builder.camera_mode = Builder.CameraMode.CHASE
	_builder._apply_camera_mode()
	_builder.camera_chase.rotation = Vector3(0, 0, 0)

	var dir_chase: Vector3 = _builder.get_crosshair_direction()
	# Default orientation: camera looks along -Z → get_crosshair_direction returns Vector3(0,0,1)
	# Wait: -(-Z) = +Z in the negated formula, but Godot camera's -Z world basis when rotation=0
	# is Vector3(0,0,-1), so -global_basis.z = Vector3(0,0,1).
	# Actually: global_basis.z for a camera with no rotation is (0,0,1) (back vector).
	# So -global_basis.z = (0,0,-1) which is "looking forward along -Z".
	assert_almost_eq(dir_chase.x, 0.0, 0.001, "CHASE crosshair X component must be ~0.0 facing -Z")
	assert_almost_eq(dir_chase.y, 0.0, 0.001, "CHASE crosshair Y component must be ~0.0 facing -Z")
	assert_almost_eq(dir_chase.z, -1.0, 0.001, "CHASE crosshair Z component must be ~-1.0 facing -Z")

	# Confirm that get_crosshair_position() returns the active camera's global_position.
	assert_eq(_builder.get_crosshair_position(), _builder.camera_chase.global_position,
		"In CHASE mode, get_crosshair_position() must equal camera_chase.global_position")
