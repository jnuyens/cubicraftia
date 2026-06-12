# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# compass.gd — top-centre heading compass for the in-world HUD.
#
# Shows the authored compass-rose art (compass_rose.png, the MINIMAP_COMPASS_N rose
# cropped label-free from art-hud.png) as a TextureRect and rotates it by the local
# builder's heading so the rose's N always points to world-north relative to the way
# the player faces. When the builder faces north the rose sits upright; turning the
# builder clockwise rotates the rose counter-clockwise so N keeps indicating north.
#
# Design choices (per the HUD task brief):
#   - Cheap: a single rotating TextureRect, no _draw() and no per-frame allocations.
#     We only re-apply the rotation when the heading changes by more than a degree.
#   - Graceful when there is no local builder yet: the widget hides itself and keeps
#     polling cheaply until a node in group "builder" appears. It also hides if the
#     rose art is unavailable so nothing broken is shown.
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

## On-screen size of the rose in pixels (square). The cropped rose is taller than
## wide; the TextureRect keeps the aspect, so this is the bounding box.
const ROSE_SIZE_PX: int = 56

## Path to the compass-rose sprite (label-free, cropped from art-hud.png).
const ICON_ROSE: String = "res://assets/textures/icons/compass_rose.png"

## Minimum heading change (degrees) before we bother re-rotating the rose.
const REDRAW_EPSILON_DEG: float = 1.0

# ─── State ────────────────────────────────────────────────────────────────────

## Cached builder node (re-acquired if it disappears).
var _builder: Node3D = null

## The rotating rose sprite (null until built; absent if the art is unavailable).
var _rose: TextureRect = null

## Current heading in degrees [0, 360); -1 means "unknown / no builder".
var _heading_deg: float = -1.0

## Last heading we applied to the rose rotation, to gate re-rotation.
var _last_applied_deg: float = -999.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(ROSE_SIZE_PX, ROSE_SIZE_PX)
	size = Vector2(ROSE_SIZE_PX, ROSE_SIZE_PX)
	# Purely informational — never eat input meant for the world/UI beneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_rose()

	# Hidden until we have a builder + a heading to show (and valid art).
	visible = false


## Build the rotating rose TextureRect. If the art is unavailable, leaves _rose null
## so _process keeps the widget hidden gracefully.
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
	# Fill our box and rotate about the centre.
	tr_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr_node.pivot_offset = Vector2(ROSE_SIZE_PX, ROSE_SIZE_PX) * 0.5
	add_child(tr_node)
	_rose = tr_node


func _process(_delta: float) -> void:
	if _rose == null or not _ensure_builder():
		if visible:
			visible = false
		return

	var heading: float = _compute_heading_deg(_builder)
	_heading_deg = heading
	if not visible:
		visible = true

	# Only re-rotate when the heading actually moved enough to matter.
	if absf(_short_angle_diff(heading, _last_applied_deg)) >= REDRAW_EPSILON_DEG:
		_last_applied_deg = heading
		# Rotate the rose opposite to the builder's clockwise heading so that N keeps
		# pointing to world-north on screen (rose upright when facing north).
		_rose.rotation = deg_to_rad(-heading)


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
