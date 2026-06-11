# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# palette_tile.gd — One brick palette tile with 3D rotating preview.
#
# Per UI-SPEC.md §PaletteTile spec (lines 345-361) and CONTEXT.md D-12:
#   - SubViewportContainer fills the tile (anchors_preset = full_rect)
#   - SubViewport(update_mode = WHEN_VISIBLE) gives scroll-aware culling for free
#     (D-12: "only on-screen tiles render")
#   - MeshInstance3D rotates at 0.5 rad/s when visible
#   - On tap/click, emits tile_selected(def_id, colour_index)
#   - Selected state: 2px #F5C30D outline via StyleBoxFlat.border_color
#   - Hover state (desktop): 0.10α #1B2C56 overlay ColorRect on mouse_entered
#
# Per 02-PATTERNS.md §"src/ui/palette_tile.gd": analog is preset_chip.gd.
# The active/inactive style toggle follows preset_chip.gd lines 57-99 pattern.
#
# Adaptive-quality hook: set_update_mode(SubViewport.UPDATE_DISABLED) for Tier-3
# "on_tap" mode dispatched by BrickPalette.set_previews_mode("on_tap").
#
# References:
#   UI-SPEC.md §PaletteTile spec
#   CONTEXT.md D-12 — 3D tile previews decision
#   02-PATTERNS.md §"src/ui/palette_tile.gd" — preset_chip.gd analog

class_name PaletteTile
extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

const COLOR_ACCENT: Color = Color(0.961, 0.765, 0.051, 1.0)  # #F5C30D
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 1.0)    # #1B2C56
const ROTATION_SPEED_RAD: float = 0.5  # rad/s per UI-SPEC.md

# ─── Exported properties ──────────────────────────────────────────────────────

## Brick definition ID from BrickRegistry.
@export var def_id: String = ""

## Palette colour index (-1 = material/natural colour).
@export var colour_index: int = -1

## Optional 2D icon path (BrickDefinition.icon_path). When set + loadable, the tile shows this
## 2D icon instead of the flat untextured 3D mesh preview (real art + no per-tile Camera3D cost).
@export var icon_path: String = ""

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when this tile is tapped/clicked. Parent BrickPalette connects to this.
signal tile_selected(def_id: String, colour_index: int)

# ─── State ────────────────────────────────────────────────────────────────────

var _is_selected: bool = false
var _hover_overlay: ColorRect = null
var _mesh_instance: MeshInstance3D = null
var _sub_viewport: SubViewport = null
## Mesh requested via set_mesh() before _ready built _mesh_instance. Applied in
## _build_viewport_tree so the call order (BrickPalette sets the mesh before the tile
## enters the tree) no longer drops the preview — the cause of all-blank tiles.
var _pending_mesh: Mesh = null

# ─── Internal node references (built programmatically in _ready) ──────────────

var _tap_button: Button = null
var _colour_dot: ColorRect = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_viewport_tree()
	_build_colour_dot()
	_build_tap_button()
	_update_style()


## Build the SubViewportContainer + SubViewport + Camera3D + lights + MeshInstance3D tree.
## This is the D-12 3D preview structure per UI-SPEC.md §PaletteTile spec.
func _build_viewport_tree() -> void:
	# Prefer a 2D icon when the brick provides one (real art + no per-tile Camera3D cost). The
	# flat untextured 3D preview made every brick read as the same pale silhouette (v1.1 QA #3).
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex := load(icon_path) as Texture2D
		if tex != null:
			_build_icon_tile(tex)
			return
	# SubViewportContainer (full_rect)
	var svc := SubViewportContainer.new()
	svc.name = "SubViewportContainer"
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	add_child(svc)

	# SubViewport. In Godot 4.6 the property is render_target_update_mode (NOT update_mode);
	# the old name silently errored, leaving every tile rendering EVERY frame. With ~116
	# tiles each running a Camera3D + 2 lights, that pegged the GPU and hung the game on B.
	# UPDATE_ONCE renders each preview a single frame then idles (re-triggered in set_mesh);
	# the previews are static (no per-frame rotation) so the palette costs ~nothing to keep open.
	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "SubViewport"
	_sub_viewport.transparent_bg = true
	_sub_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	svc.add_child(_sub_viewport)

	# Camera3D — FoV 30°, positioned looking at origin
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 30.0
	cam.position = Vector3(0.0, 1.5, 3.5)
	cam.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
	_sub_viewport.add_child(cam)

	# Key directional light
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-45.0, 45.0, 0.0)
	key_light.light_energy = 1.2
	_sub_viewport.add_child(key_light)

	# Rim/fill directional light
	var rim_light := DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.rotation_degrees = Vector3(30.0, -135.0, 0.0)
	rim_light.light_energy = 0.5
	_sub_viewport.add_child(rim_light)

	# MeshInstance3D — mesh requested via set_mesh() (possibly before this node existed).
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "MeshInstance3D"
	_mesh_instance.position = Vector3.ZERO
	# Use the requested mesh, or a default cube so mesh-null bricks still show a preview.
	if _pending_mesh != null:
		_mesh_instance.mesh = _pending_mesh
	else:
		var cube := BoxMesh.new()
		cube.size = Vector3(1.1, 1.1, 1.1)
		_mesh_instance.mesh = cube
	# Apply colour tint: palette colour if set, else a neutral brick tan so it reads.
	var mat := StandardMaterial3D.new()
	if colour_index >= 0 and colour_index < BrickPalette.COLOURS.size():
		mat.albedo_color = BrickPalette.COLOURS[colour_index]
	else:
		mat.albedo_color = Color(0.82, 0.7, 0.45)
	mat.roughness = 0.9
	_mesh_instance.material_override = mat
	# Static 3/4 view (no per-frame rotation — see render_target_update_mode note above).
	_mesh_instance.rotation.y = 0.6
	_sub_viewport.add_child(_mesh_instance)

	# Name label across the bottom so bricks are identifiable even if the 3D preview is
	# featureless (most v1 bricks share the default cube until the art pass).
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = _display_name()
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.92))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)

	# Hover overlay (desktop) — 10% navy tint on mouse_entered
	_hover_overlay = ColorRect.new()
	_hover_overlay.name = "HoverOverlay"
	_hover_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hover_overlay.color = Color(COLOR_NAVY.r, COLOR_NAVY.g, COLOR_NAVY.b, 0.0)
	_hover_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hover_overlay)

	# Render the preview exactly once now that camera/lights/mesh are in place.
	_request_preview_render()


## Build a 2D-icon tile (TextureRect + name label + hover overlay) used instead of the 3D viewport
## preview when the brick supplies an icon_path. Renders the real art and skips the Camera3D cost.
func _build_icon_tile(tex: Texture2D) -> void:
	var icon := TextureRect.new()
	icon.name = "Icon2D"
	icon.texture = tex
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = _display_name()
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.92))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)
	_hover_overlay = ColorRect.new()
	_hover_overlay.name = "HoverOverlay"
	_hover_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hover_overlay.color = Color(COLOR_NAVY.r, COLOR_NAVY.g, COLOR_NAVY.b, 0.0)
	_hover_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hover_overlay)


## Render the 3D preview a single frame (UPDATE_ONCE), then it idles again. Called after
## build and whenever the mesh changes — keeps the palette static and cheap.
func _request_preview_render() -> void:
	if _sub_viewport != null:
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Build the colour swatch dot (12×12 px, bottom-right corner per UI-SPEC.md).
func _build_colour_dot() -> void:
	_colour_dot = ColorRect.new()
	_colour_dot.name = "ColourDot"
	_colour_dot.custom_minimum_size = Vector2(12.0, 12.0)
	_colour_dot.size = Vector2(12.0, 12.0)
	# Anchor to bottom-right corner
	_colour_dot.anchor_left = 1.0
	_colour_dot.anchor_top = 1.0
	_colour_dot.anchor_right = 1.0
	_colour_dot.anchor_bottom = 1.0
	_colour_dot.offset_left = -14.0
	_colour_dot.offset_top = -14.0
	_colour_dot.offset_right = -2.0
	_colour_dot.offset_bottom = -2.0
	_colour_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if colour_index >= 0 and colour_index < BrickPalette.COLOURS.size():
		_colour_dot.color = BrickPalette.COLOURS[colour_index]
	else:
		_colour_dot.color = Color(0.945, 0.941, 0.918, 0.7)  # white fallback
	add_child(_colour_dot)


## Build the invisible tap/click button overlay.
func _build_tap_button() -> void:
	_tap_button = Button.new()
	_tap_button.name = "TapButton"
	_tap_button.flat = true
	_tap_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_button.pressed.connect(_on_pressed)
	_tap_button.mouse_entered.connect(_on_mouse_entered)
	_tap_button.mouse_exited.connect(_on_mouse_exited)
	add_child(_tap_button)

	# Screen-reader tooltip per UI-SPEC.md §PaletteTile spec
	_tap_button.tooltip_text = tr("ui.palette.tile.sr_label")


# ─── Process ──────────────────────────────────────────────────────────────────

# NOTE: per-frame rotation removed — previews are static one-shot renders (UPDATE_ONCE)
# so the palette doesn't re-render ~116 SubViewports every frame (the B-key hang).


# ─── Public API ───────────────────────────────────────────────────────────────

## Set the brick mesh for this tile's 3D preview.
func set_mesh(mesh: Mesh) -> void:
	_pending_mesh = mesh
	if _mesh_instance != null:
		_mesh_instance.mesh = mesh
		_request_preview_render()  # re-render once with the new mesh


## Human-readable brick name for the tile label. Prefers the i18n display key,
## falls back to a title-cased def_id.
func _display_name() -> String:
	var key := "bricks.%s.name" % def_id
	var translated := tr(key)
	if translated != key and not translated.is_empty():
		return translated
	return def_id.capitalize()


## Set whether this tile is the currently selected/equipped tile.
## Updates the yellow outline selection indicator.
func set_selected(selected: bool) -> void:
	_is_selected = selected
	_update_style()


## Set the SubViewport update mode for adaptive quality.
## "3d_realtime" -> UPDATE_WHEN_VISIBLE (default)
## "on_tap"      -> UPDATE_DISABLED (Tier-3: renders only on hover/tap)
func set_update_mode_from_quality(mode: String) -> void:
	if _sub_viewport == null:
		return
	# Both modes now render once and idle (static previews). The "on_tap" path re-renders
	# on hover; the default path renders once on build. Neither renders per-frame.
	if mode == "on_tap":
		if not _tap_button.mouse_entered.is_connected(_on_tier3_hover):
			_tap_button.mouse_entered.connect(_on_tier3_hover)
	else:
		if _tap_button.mouse_entered.is_connected(_on_tier3_hover):
			_tap_button.mouse_entered.disconnect(_on_tier3_hover)


# ─── Private helpers ──────────────────────────────────────────────────────────

func _update_style() -> void:
	var style := StyleBoxFlat.new()
	if _is_selected:
		# 2px #F5C30D outline per UI-SPEC.md §PaletteTile spec line 359
		style.bg_color = Color(0.106, 0.173, 0.337, 0.3)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = COLOR_ACCENT
	else:
		style.bg_color = Color(0.106, 0.173, 0.337, 0.15)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.945, 0.941, 0.918, 0.2)
	add_theme_stylebox_override("panel", style)


func _on_pressed() -> void:
	tile_selected.emit(def_id, colour_index)


func _on_mouse_entered() -> void:
	if _hover_overlay != null:
		_hover_overlay.color = Color(COLOR_NAVY.r, COLOR_NAVY.g, COLOR_NAVY.b, 0.10)


func _on_mouse_exited() -> void:
	if _hover_overlay != null:
		_hover_overlay.color = Color(COLOR_NAVY.r, COLOR_NAVY.g, COLOR_NAVY.b, 0.0)


## Tier-3 on_tap mode: re-render the preview once on hover.
func _on_tier3_hover() -> void:
	_request_preview_render()
