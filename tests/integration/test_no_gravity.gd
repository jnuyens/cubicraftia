# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_no_gravity.gd — Integration tests for the no-gravity brick invariant.
#
# Anchors:
#   DOCS.md §3.2 — bricks float when supports removed; no gravity on placed bricks in v1
#   DOCS.md §9 — brick gravity is deferred post-v1
#   02-CONTEXT.md — brick_gravity: false in Features.gd (Phase 1 invariant carried forward)
#   02-RESEARCH.md §"Contradiction 1 — Brick gravity"
#
# Plan 02-09: tests turned GREEN.
# Contradiction 1 mitigation: no falling-block algorithm exists in StudGrid.
#
# Headless note: StudGrid operations do not require a GPU. No headless guard needed.

extends GutTest

const BRICK_1X1_PATH := "res://src/bricks/brick_1x1.tres"

var _grid: StudGrid = null
var _brick_def: BrickDefinition = null

func before_each() -> void:
	_grid = StudGrid.new()
	add_child_autofree(_grid)
	_brick_def = load(BRICK_1X1_PATH) as BrickDefinition
	assert_not_null(_brick_def, "brick_1x1.tres must exist")

# ─── Test 1 ────────────────────────────────────────────────────────────────────

func test_removing_support_leaves_brick_floating() -> void:
	# Stack two bricks vertically: one at (0,0,0) as the "support", one at (0,1,0) above.
	var support_anchor := Vector3i(0, 0, 0)
	var upper_anchor := Vector3i(0, 1, 0)

	var placed_support := _grid.place(support_anchor, _brick_def)
	var placed_upper := _grid.place(upper_anchor, _brick_def)
	assert_true(placed_support, "support brick should place successfully")
	assert_true(placed_upper, "upper brick should place successfully")
	assert_eq(_grid.size(), 2, "grid should have 2 bricks before remove")

	# Remove the supporting brick.
	var removed := _grid.remove(support_anchor)
	assert_true(removed, "remove of support brick should return true")

	# The upper brick should STILL be there — no gravity algorithm moves it.
	# This is the DOCS.md §3.2 + §9 floating-brick invariant.
	var upper_instance := _grid.query(upper_anchor)
	assert_not_null(upper_instance,
		"upper brick at (0,1,0) should still exist after removing support (no-gravity invariant)")
	assert_eq(_grid.size(), 1, "grid should have 1 brick remaining (the floating upper brick)")

# ─── Test 2 ────────────────────────────────────────────────────────────────────

func test_features_brick_gravity_is_false() -> void:
	# Verify the Feature flag is false — this is the Phase 1 invariant carried
	# through Phase 2 per DOCS.md §9 and RESEARCH.md Contradiction 1.
	# The flag must remain false in project.godot; CI script verify-feature-flags.sh
	# enforces this. This test provides runtime confirmation.
	var brick_gravity_enabled: bool = Features.is_enabled("brick_gravity")
	assert_false(brick_gravity_enabled,
		"Features.brick_gravity must be false in v1 — DOCS.md §9, RESEARCH.md Contradiction 1")
