# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# crosshair.gd — Centre-of-screen 12×12 crosshair reticle (Plan 02-09).
#
# Paints a + cross in _draw(). Per UI-SPEC.md §Crosshair:
#   - 12×12 px, 1px stroke.
#   - Colour: #F1F0EA (warm white, per BrickPalette index 0).
#   - 1px navy drop-shadow (#1B2C56) for legibility over light terrain.
#   - No alpha. Always centred via anchors_preset = CENTER in the scene.
#   - Hidden on mobile when the brick palette bottom sheet is expanded (mobile_overlay.gd).
#
# Signals:
#   (none — a pure rendering control)
#
# Public API:
#   set_invalid_state(invalid: bool) — toggle red tint for invalid placement feedback.
#
# References:
#   UI-SPEC.md §Crosshair (desktop/mobile — Phase 2 makes it active)
#   DOCS.md §3.2 — "placement is point-and-click with the centre-of-screen crosshair"

extends Control

# ─── Colour constants ─────────────────────────────────────────────────────────

## Primary crosshair colour — warm white from BrickPalette index 0.
const COLOR_PRIMARY: Color = Color(0.945, 0.941, 0.918, 1.0)  # #F1F0EA

## Drop-shadow colour — navy per UI-SPEC.md §Crosshair.
const COLOR_SHADOW: Color = Color(0.106, 0.173, 0.337, 1.0)   # #1B2C56

## Invalid-state tint (red) — #D63828 per UI-SPEC.md §Ghost Preview.
const COLOR_INVALID: Color = Color(0.839, 0.220, 0.157, 1.0)  # #D63828

## Crosshair size in pixels.
const CROSSHAIR_SIZE: int = 12

# ─── State ────────────────────────────────────────────────────────────────────

## When true, the crosshair tints red to indicate invalid placement.
var _invalid_state: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(CROSSHAIR_SIZE, CROSSHAIR_SIZE)


# ─── Public API ──────────────────────────────────────────────────────────────

## Toggle the invalid-placement red tint.
## Called by ghost_preview.gd when the predicted placement target is blocked.
func set_invalid_state(invalid: bool) -> void:
	if _invalid_state != invalid:
		_invalid_state = invalid
		queue_redraw()


# ─── Rendering ────────────────────────────────────────────────────────────────

func _draw() -> void:
	var center_x: float = CROSSHAIR_SIZE / 2.0
	var center_y: float = CROSSHAIR_SIZE / 2.0
	var half: float = CROSSHAIR_SIZE / 2.0

	var primary: Color = COLOR_INVALID if _invalid_state else COLOR_PRIMARY

	# ── 1px navy drop-shadow (drawn 1px offset, under the primary lines) ──────
	# Horizontal shadow.
	draw_line(
		Vector2(0, center_y + 1.0),
		Vector2(CROSSHAIR_SIZE, center_y + 1.0),
		COLOR_SHADOW, 1.0
	)
	# Vertical shadow.
	draw_line(
		Vector2(center_x + 1.0, 0),
		Vector2(center_x + 1.0, CROSSHAIR_SIZE),
		COLOR_SHADOW, 1.0
	)

	# ── Primary cross lines ───────────────────────────────────────────────────
	# Horizontal arm.
	draw_line(
		Vector2(0.0, center_y),
		Vector2(float(CROSSHAIR_SIZE), center_y),
		primary, 1.0
	)
	# Vertical arm.
	draw_line(
		Vector2(center_x, 0.0),
		Vector2(center_x, float(CROSSHAIR_SIZE)),
		primary, 1.0
	)
