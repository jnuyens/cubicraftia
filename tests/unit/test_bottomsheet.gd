# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_bottomsheet.gd — Unit tests for mobile brick palette bottom-sheet swipe animation.
#
# Anchors:
#   DOCS.md §3 — palette UI: mobile bottom sheet
#   02-CONTEXT.md §D-12 — brick palette previews + mobile bottom sheet gesture
#   02-UI-SPEC.md §"Brick Palette Bottom Sheet" — drag handle, tween, snap states
#   02-RESEARCH.md §"Brick Palette UI"
#
# Plan 12 ships the bottom-sheet controller — tests turned GREEN.
#
# Strategy: The BrickPaletteUI (brick_palette.gd) extends PanelContainer and requires
# a full scene tree for SubViewport/GPU nodes. These tests exercise the bottom-sheet
# snap math via the _handle_test_drag() hook which bypasses InputEvent and tests
# the tween target calculation + snap-to-nearest logic in isolation.
#
# Note: Full gesture verification requires a manual checkpoint on a touch device
# (per 02-VALIDATION.md §"Manual-Only Verifications"). These unit tests cover the
# tween target calculation and snap-to-nearest logic in isolation.
#
# Per STATE.md "detached-node-test-pattern": BrickPaletteUI is added via add_child_autofree
# so the engine manages its lifecycle. The _expanded_y/_collapsed_y positions are set
# via public test accessors (or directly since GDScript allows duck-typed field access).

extends GutTest

# ─── Constants (matching UI-SPEC.md §"Mobile Bottom Sheet") ──────────────────

## Simulated viewport height for tests
const TEST_VIEWPORT_H: float = 800.0

## Expanded Y: top of sheet = 50% of viewport height from top
const TEST_EXPANDED_Y: float = TEST_VIEWPORT_H * 0.5  # = 400.0

## Collapsed Y: only drag-handle visible at bottom
const TEST_COLLAPSED_Y: float = TEST_VIEWPORT_H - 64.0  # = 736.0

## Midpoint between expanded and collapsed (snap threshold)
const TEST_MIDPOINT_Y: float = (TEST_EXPANDED_Y + TEST_COLLAPSED_Y) * 0.5  # = 568.0

## Tween duration from UI-SPEC.md ("0.22s ease-out cubic")
const TWEEN_DURATION_S: float = 0.22

# ─── Helpers ──────────────────────────────────────────────────────────────────

## Create a BrickPaletteUI instance configured for bottom-sheet snap testing.
## Sets _expanded_y and _collapsed_y to the test constants so math is deterministic.
func _make_sheet() -> PanelContainer:
	var sheet: PanelContainer = PanelContainer.new()
	sheet.set_script(load("res://src/ui/brick_palette.gd"))
	# Set layout BEFORE add_child so _ready() skips viewport setup
	sheet.set("layout", "bottomsheet")
	add_child_autofree(sheet)
	# Override computed positions with test constants (duck-typed field assignment)
	sheet.set("_expanded_y", TEST_EXPANDED_Y)
	sheet.set("_collapsed_y", TEST_COLLAPSED_Y)
	return sheet


# ─── Test 1 ────────────────────────────────────────────────────────────────────

## Verify that a drag from collapsed toward expanded (crossing the midpoint) snaps
## to the expanded position after release.
##
## Scenario: sheet starts at collapsed_y (736). Drag handle pressed at y=680 (below mid=568),
## released at y=500 (above mid=568 → past the midpoint toward expanded).
## Expected: sheet snaps to expanded_y=400.
func test_drag_handle_tween_targets() -> void:
	var sheet := _make_sheet()

	# Start at collapsed
	sheet.position.y = TEST_COLLAPSED_Y

	# Simulate drag that crosses the midpoint upward (release at y above midpoint)
	# _handle_test_drag(start_y, end_y, release_at) — release_at is the sheet position
	# after drag movement (clamp(release_at, expanded_y, collapsed_y)).
	# Release above midpoint → should snap to expanded
	var release_position: float = TEST_MIDPOINT_Y - 50.0  # 518.0 — above midpoint (closer to expanded)
	sheet._handle_test_drag(TEST_COLLAPSED_Y, TEST_EXPANDED_Y, release_position)

	# After snap, position.y should be expanded_y
	assert_almost_eq(sheet.position.y, TEST_EXPANDED_Y, 2.0,
		"Sheet should snap to expanded_y when released above midpoint")


# ─── Test 2 ────────────────────────────────────────────────────────────────────

## Verify that a short drag from collapsed (below midpoint on release) snaps BACK
## to collapsed position.
##
## Scenario: sheet at collapsed_y (736). Drag starts, releases at collapsed_y-10=726
## (still below the midpoint of 568 → closer to collapsed). Expected: snap-back to 736.
func test_expand_collapse_snaps_to_nearest() -> void:
	var sheet := _make_sheet()

	# Start at collapsed
	sheet.position.y = TEST_COLLAPSED_Y

	# Simulate a short drag that does NOT cross the midpoint (release below midpoint)
	var short_drag_position: float = TEST_COLLAPSED_Y - 10.0  # 726.0 — below midpoint (closer to collapsed)
	# Clamp: collapsed_y - 10 = 726, which is between expanded_y(400) and collapsed_y(736)
	sheet._handle_test_drag(TEST_COLLAPSED_Y, TEST_COLLAPSED_Y - 10.0, short_drag_position)

	# After snap, position.y should return to collapsed_y (short drag < midpoint → collapse)
	assert_almost_eq(sheet.position.y, TEST_COLLAPSED_Y, 2.0,
		"Sheet should snap back to collapsed_y when released below midpoint")
