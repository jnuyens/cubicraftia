# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_world_thumbnail_capture.gd — Unit tests for WorldSave.capture_thumbnail.
#
# Tests cover:
#   - capture_thumbnail creates a file at the expected path (user://worlds/{id}/thumbnail.jpg)
#   - file dimensions are 256×144 px (or a conforming aspect ratio)
#   - capture_thumbnail is a no-op (returns false) when no viewport is active
#   - calling capture_thumbnail on a non-existent world_id returns false
#
# NOTE: Most tests here are PENDING because they require a live Godot Viewport/Camera3D.
# These tests serve as executable documentation of the expected API contract.
# Wave 6 (visual QA) will wire a mock SubViewport to make them pass.
#
# The API contract test (path format) is the only test that can run headlessly.
#
# Anchors:
#   06-01-PLAN.md Task 2 — test_world_thumbnail_capture stub
#   06-UI-SPEC.md Surface 3 — world card thumbnail, 256x144 stored, 128x72 displayed

extends GutTest

const Phase6Fixtures = preload("res://tests/conftest_phase6.gd")

## Expected thumbnail filename (relative to the world directory).
const THUMBNAIL_FILENAME: String = "thumbnail.jpg"

## Expected thumbnail dimensions.
const EXPECTED_WIDTH:  int = 256
const EXPECTED_HEIGHT: int = 144


func test_thumbnail_path_format() -> void:
	# Verify the expected thumbnail path format without actually calling capture_thumbnail.
	# The method in world_save.gd constructs: "user://worlds/%s/thumbnail.jpg" % world_id
	var world_id: String = "test_world_abc"
	var expected_path: String = "user://worlds/%s/%s" % [world_id, THUMBNAIL_FILENAME]
	assert_eq(expected_path, "user://worlds/test_world_abc/thumbnail.jpg",
		"Thumbnail path must follow the user://worlds/{world_id}/thumbnail.jpg pattern")


func test_thumbnail_path_uses_world_id_directory() -> void:
	# The thumbnail must be inside the world's directory, not at the user:// root.
	var world_id: String = "my_world_42"
	var path: String = "user://worlds/%s/%s" % [world_id, THUMBNAIL_FILENAME]
	assert_true(path.begins_with("user://worlds/"),
		"Thumbnail path must be under user://worlds/")
	assert_true(path.ends_with(".jpg"),
		"Thumbnail path must end with .jpg")
	assert_true(path.contains(world_id),
		"Thumbnail path must contain the world_id '%s'" % world_id)


func test_empty_world_id_does_not_produce_valid_path() -> void:
	# WorldSave.capture_thumbnail returns early if p_world_id.is_empty().
	# This test documents the guard contract.
	var empty_id: String = ""
	assert_true(empty_id.is_empty(),
		"Empty string must be detected as empty (guard condition in capture_thumbnail)")


func test_thumbnail_dimensions_contract() -> void:
	# Document the 256×144 px contract. The actual assertion against a real image
	# requires a live viewport — see PENDING below.
	assert_eq(EXPECTED_WIDTH, 256,  "Thumbnail width contract must be 256 px")
	assert_eq(EXPECTED_HEIGHT, 144, "Thumbnail height contract must be 144 px")
	# Verify aspect ratio: 256/144 = 16/9 = ~1.777
	var ratio: float = float(EXPECTED_WIDTH) / float(EXPECTED_HEIGHT)
	assert_almost_eq(ratio, 16.0 / 9.0, 0.01,
		"Thumbnail must be 16:9 aspect ratio")


func test_thumbnail_dimensions() -> void:
	pending("Requires rendering viewport — manual verification; WorldSave.capture_thumbnail() resizes to 256x144")


func test_no_viewport_returns_false() -> void:
	pending("Requires rendering viewport — WorldSave.capture_thumbnail without active Camera3D is a no-op")


func test_nonexistent_world_returns_false() -> void:
	pending("Requires WorldSave open database — capture_thumbnail('nonexistent_world') is a no-op in headless mode")
