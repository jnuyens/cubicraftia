# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# compass.gd — top-centre heading compass for the in-world HUD.
#
# Reads the local builder's yaw each frame and renders a horizontal N/E/S/W
# strip that scrolls with the heading, with a fixed centre tick marking the
# direction the builder currently faces. Brick-styled with the project palette
# (parchment text on a navy framed panel), matched to crosshair.gd's colours.
#
# Design choices (per the HUD task brief):
#   - Cheap: a single _draw() pass, no per-frame node allocations. We only
#     queue_redraw() when the heading changes by more than a degree, and the
#     draw itself just paints text + lines (like crosshair.gd).
#   - Graceful when there is no local builder yet: the widget hides itself and
#     keeps polling cheaply until a node in group "builder" appears.
#
# Heading convention:
#   The builder's forward vector is -transform.basis.z. We map world -Z to North,
#   +X to East, +Z to South, -X to West (a standard top-down map convention).
#   Heading is the clockwise angle from North in degrees [0, 360).
#
# References:
#   crosshair.gd — sibling pure-rendering HUD Control (palette + _draw pattern)
#   CLAUDE.md §Conventions — builder lives in group "builder"; yaw is rotation.y

extends Control

# ─── Colour constants (match crosshair.gd / UI-SPEC palette) ──────────────────

## Cardinal/text colour — warm white #F1F0EA (BrickPalette index 0).
const COLOR_TEXT: Color = Color(0.945, 0.941, 0.918, 1.0)

## Intercardinal tick colour — same parchment at reduced alpha.
const COLOR_TICK: Color = Color(0.945, 0.941, 0.918, 0.55)

## Drop-shadow / frame colour — navy #1B2C56.
const COLOR_SHADOW: Color = Color(0.106, 0.173, 0.337, 1.0)

## Panel background — navy at 55% alpha.
const COLOR_PANEL: Color = Color(0.106, 0.173, 0.337, 0.55)

## Centre heading-marker colour — destructive red #D63828 (reads as "you face here").
const COLOR_MARKER: Color = Color(0.839, 0.220, 0.157, 1.0)

# ─── Layout constants ─────────────────────────────────────────────────────────

## Widget size in pixels (a wide, short strip).
const STRIP_WIDTH: int = 220
const STRIP_HEIGHT: int = 30

## Horizontal pixels per degree of heading. STRIP_WIDTH / DEGREES_VISIBLE.
## We show a 180° window so half the compass rose is visible at once.
const DEGREES_VISIBLE: float = 180.0

## Minimum heading change (degrees) before we bother repainting.
const REDRAW_EPSILON_DEG: float = 1.0

# ─── State ────────────────────────────────────────────────────────────────────

## Cached builder node (re-acquired if it disappears).
var _builder: Node3D = null

## Current heading in degrees [0, 360); -1 means "unknown / no builder".
var _heading_deg: float = -1.0

## Last heading we painted, to gate queue_redraw().
var _last_drawn_deg: float = -999.0

## Cardinal marks: (degrees, label). Empty label = an intercardinal tick.
const _MARKS: Array = [
	[0.0, "N"], [45.0, ""], [90.0, "E"], [135.0, ""],
	[180.0, "S"], [225.0, ""], [270.0, "W"], [315.0, ""],
]

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(STRIP_WIDTH, STRIP_HEIGHT)
	size = Vector2(STRIP_WIDTH, STRIP_HEIGHT)
	# Purely informational — never eat input meant for the world/UI beneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Hidden until we have a builder + a heading to show.
	visible = false


func _process(_delta: float) -> void:
	if not _ensure_builder():
		if visible:
			visible = false
		return

	var heading: float = _compute_heading_deg(_builder)
	_heading_deg = heading
	if not visible:
		visible = true

	# Only repaint when the heading actually moved enough to matter.
	if absf(_short_angle_diff(heading, _last_drawn_deg)) >= REDRAW_EPSILON_DEG:
		_last_drawn_deg = heading
		queue_redraw()


# ─── Builder acquisition ──────────────────────────────────────────────────────

## Ensure _builder points at a live node in group "builder". Returns false if
## none is available (e.g. before spawn or in menu scenes).
func _ensure_builder() -> bool:
	if _builder != null and is_instance_valid(_builder):
		return true
	var b: Node = get_tree().get_first_node_in_group("builder")
	if b is Node3D:
		_builder = b as Node3D
		return true
	_builder = null
	return false


## Compute the builder's compass heading in degrees [0, 360).
## Forward is -basis.z; world -Z is North, +X is East.
func _compute_heading_deg(builder: Node3D) -> float:
	var fwd: Vector3 = -builder.global_transform.basis.z
	# atan2(east, north) gives the clockwise angle from North.
	var rad: float = atan2(fwd.x, -fwd.z)
	var deg: float = rad_to_deg(rad)
	return fposmod(deg, 360.0)


## Shortest signed difference a-b wrapped to [-180, 180].
func _short_angle_diff(a: float, b: float) -> float:
	return wrapf(a - b, -180.0, 180.0)


# ─── Rendering ────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _heading_deg < 0.0:
		return

	var w: float = float(STRIP_WIDTH)
	var h: float = float(STRIP_HEIGHT)
	var px_per_deg: float = w / DEGREES_VISIBLE
	var center_x: float = w * 0.5

	# Framed panel background with a 1px navy border.
	var panel := Rect2(0.0, 0.0, w, h)
	draw_rect(panel, COLOR_PANEL, true)
	draw_rect(panel, COLOR_SHADOW, false, 1.0)

	var font: Font = get_theme_default_font()
	var font_size: int = 14

	# Draw each cardinal/intercardinal mark at its scrolled x position.
	for mark: Array in _MARKS:
		var mark_deg: float = mark[0]
		var label: String = mark[1]
		# Offset of this mark from the centre heading, wrapped to [-180,180].
		var off: float = _short_angle_diff(mark_deg, _heading_deg)
		var x: float = center_x + off * px_per_deg
		if x < -8.0 or x > w + 8.0:
			continue
		if label.is_empty():
			# Intercardinal: a short tick.
			draw_line(Vector2(x, h - 8.0), Vector2(x, h - 3.0), COLOR_TICK, 1.0)
		else:
			# Cardinal letter, centred on x, with a 1px navy drop-shadow.
			var text_size: Vector2 = font.get_string_size(
				label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
			)
			var tx: float = x - text_size.x * 0.5
			var ty: float = (h + text_size.y) * 0.5 - 3.0
			draw_string(
				font, Vector2(tx + 1.0, ty + 1.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, COLOR_SHADOW
			)
			draw_string(
				font, Vector2(tx, ty), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, COLOR_TEXT
			)

	# Fixed centre marker (a small downward red triangle) = "you face here".
	var tri := PackedVector2Array([
		Vector2(center_x - 4.0, 1.0),
		Vector2(center_x + 4.0, 1.0),
		Vector2(center_x, 7.0),
	])
	draw_colored_polygon(tri, COLOR_MARKER)
