# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# compass.gd — top-centre heading compass for the in-world HUD.
#
# The compass FACE is FIXED: the authored compass-rose art (compass_rose.png) is shown
# upright as a static backdrop so N always reads at the top, S at the bottom. Only a
# separate NEEDLE rotates on top of it to indicate the player's heading.
#
# Needle convention (reads correctly):
#   The needle points to world-NORTH relative to the way the player faces. When the
#   builder faces north the needle points straight UP (towards the static "N"). Turn
#   the builder clockwise and the needle rotates counter-clockwise, so the red tip keeps
#   pointing at true north on the fixed face — exactly how a real magnetic compass reads.
#
# Design choices (per the HUD task brief):
#   - Cheap: the backdrop is a static TextureRect that never moves; the needle is drawn
#     with a couple of polygons in _draw(). We only request a redraw when the heading
#     changes by more than ~1 degree, so a stationary or slowly-turning builder costs
#     nothing per frame beyond the heading read.
#   - Graceful when there is no local builder yet: the widget hides itself and keeps
#     polling cheaply until a node in group "builder" appears. The needle still draws
#     even if the rose art is unavailable, so the heading is always readable.
#
# Heading convention:
#   The builder's forward vector is -transform.basis.z. We map world -Z to North,
#   +X to East, +Z to South, -X to West (a standard top-down map convention).
#   Heading is the clockwise angle from North in degrees [0, 360).
#
# References:
#   crosshair.gd — sibling pure-rendering HUD Control (palette pattern)
#   CLAUDE.md §Conventions — builder lives in group "builder"; yaw is rotation.y

extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

## On-screen size of the compass in pixels (square). The rose art keeps its aspect
## inside this bounding box; the needle is drawn relative to the box centre.
const SIZE_PX: int = 56

## Path to the static compass-rose backdrop (label-free, cropped from art-hud.png).
const ICON_ROSE: String = "res://assets/textures/icons/compass_rose.png"

## Minimum heading change (degrees) before we bother re-drawing the needle.
const REDRAW_EPSILON_DEG: float = 1.0

## Needle geometry, as fractions of the half-size (so it scales with SIZE_PX).
const NEEDLE_LEN_FRAC: float = 0.78      # tip distance from centre, fraction of half-size
const NEEDLE_HALF_W_FRAC: float = 0.16   # half-width of the needle base, fraction of half-size
const HUB_RADIUS_FRAC: float = 0.12      # centre hub radius, fraction of half-size

## Needle colours: red north tip (points to north), pale south tail, dark hub + outline.
const COL_NORTH: Color = Color(0.839, 0.220, 0.157, 1.0)   # red  #D63828 (palette red)
const COL_SOUTH: Color = Color(0.945, 0.941, 0.918, 1.0)   # white #F1F0EA (palette white)
const COL_HUB: Color = Color(0.110, 0.110, 0.120, 1.0)     # near-black hub
const COL_OUTLINE: Color = Color(0.0, 0.0, 0.0, 0.55)      # soft dark outline

# ─── State ────────────────────────────────────────────────────────────────────

## Cached builder node (re-acquired if it disappears).
var _builder: Node3D = null

## The static rose backdrop (null until built; absent if the art is unavailable).
var _rose: TextureRect = null

## The needle layer — a child Control whose _draw() paints the rotating needle.
## It is added AFTER the rose so it always renders ON TOP of the static backdrop.
var _needle: Control = null

## Current heading in degrees [0, 360); -1 means "unknown / no builder".
var _heading_deg: float = -1.0

## Last heading we drew the needle at, to gate redraws.
var _last_drawn_deg: float = -999.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	size = Vector2(SIZE_PX, SIZE_PX)
	# Purely informational — never eat input meant for the world/UI beneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_rose()
	_build_needle()

	# Hidden until we have a builder + a heading to show.
	visible = false


## Build the STATIC rose backdrop TextureRect. It never rotates — N stays at the top.
## If the art is unavailable, leaves _rose null; the needle still draws on a bare box.
func _build_rose() -> void:
	if not ResourceLoader.exists(ICON_ROSE, "Texture2D"):
		return
	var tr_node := TextureRect.new()
	tr_node.name = "Rose"
	tr_node.texture = load(ICON_ROSE)
	tr_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(tr_node)
	_rose = tr_node


## Build the needle layer as a child Control on top of the rose. Its _draw() renders
## the rotating needle; redirecting the paint here (rather than this Control's own
## _draw) guarantees the needle sits ABOVE the static rose backdrop.
func _build_needle() -> void:
	var n := Control.new()
	n.name = "Needle"
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.draw.connect(_draw_needle)
	add_child(n)
	_needle = n


func _process(_delta: float) -> void:
	if not _ensure_builder():
		if visible:
			visible = false
		return

	var heading: float = _compute_heading_deg(_builder)
	_heading_deg = heading
	if not visible:
		visible = true

	# Only redraw the needle when the heading actually moved enough to matter.
	if absf(_short_angle_diff(heading, _last_drawn_deg)) >= REDRAW_EPSILON_DEG:
		_last_drawn_deg = heading
		if _needle != null:
			_needle.queue_redraw()


## Draw the rotating needle on top of the static rose. Bound to the needle child's
## `draw` signal, so all draw_* calls target the needle layer (above the rose).
## Called only on heading change.
func _draw_needle() -> void:
	if _heading_deg < 0.0 or _needle == null:
		return

	var centre := Vector2(SIZE_PX, SIZE_PX) * 0.5
	var half := float(SIZE_PX) * 0.5
	var needle_len := half * NEEDLE_LEN_FRAC
	var base_half := half * NEEDLE_HALF_W_FRAC
	var hub_r := half * HUB_RADIUS_FRAC

	# Screen up is -Y. "Points to north" means: when heading == 0 (facing north) the tip
	# is straight up. Rotating the builder clockwise (+heading) rotates the needle
	# counter-clockwise on screen so the red tip keeps indicating true north.
	var ang := deg_to_rad(-_heading_deg)
	var up := Vector2(sin(ang), -cos(ang))          # unit vector towards the needle tip
	var right := Vector2(up.y, -up.x)                # 90deg clockwise from up, for width

	var tip := centre + up * needle_len
	var tail := centre - up * needle_len
	var base_l := centre + right * base_half
	var base_r := centre - right * base_half

	# North half (red): tip -> base_l -> base_r triangle.
	var north_tri := PackedVector2Array([tip, base_l, base_r])
	# South half (pale): tail -> base_r -> base_l triangle.
	var south_tri := PackedVector2Array([tail, base_r, base_l])

	# All draw_* calls target the needle child node (the signal source), so they paint
	# onto the needle layer that sits above the static rose backdrop.
	_needle.draw_colored_polygon(south_tri, COL_SOUTH)
	_needle.draw_colored_polygon(north_tri, COL_NORTH)

	# Thin dark outline around the full diamond so it reads against any rose colour.
	var outline := PackedVector2Array([tip, base_l, tail, base_r, tip])
	_needle.draw_polyline(outline, COL_OUTLINE, 1.0, true)

	# Centre hub disc.
	_needle.draw_circle(centre, hub_r, COL_HUB)


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
