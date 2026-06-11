# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# remote_builder_nameplate.gd — Label3D nameplate for remote builders (Surface 8).
#
# Attached dynamically to each remote Builder node at spawn time. NOT on the
# local player's builder.
#
# Nameplate spec (04-UI-SPEC.md Surface 8):
#   - Label3D at +2.2 m Y above the builder root.
#   - Username truncated to 16 chars.
#   - Builder's primary colour tint applied to the label.
#   - Billboard mode: always faces the camera.
#   - Distance fade: 16-20 m (visibility_range_end=20m, margin=4m).
#   - Toggled via Settings "Show player names" checkbox (user://settings.cfg).
#
# Usage (spawn controller adds nameplate to a remote builder):
#   var nameplate := RemoteBuilderNameplate.new()
#   remote_builder_node.add_child(nameplate)
#   nameplate.setup("Alice", Color(0.2, 0.5, 0.9))
#
# References:
#   04-UI-SPEC.md Surface 8 — player nameplates
#   04-08-PLAN.md Task 2 — nameplate behaviour spec
#   04-PATTERNS.md lines 680-695 — Label3D settings template

class_name RemoteBuilderNameplate
extends Node3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Y offset above the builder root (metres) per UI-SPEC Surface 8.
const NAMEPLATE_Y_OFFSET: float = 2.2

## Maximum username characters displayed.
const USERNAME_MAX_CHARS: int = 16

## Label3D pixel_size (world units per pixel).
const LABEL_PIXEL_SIZE: float = 0.004

## Label3D font size.
const LABEL_FONT_SIZE: int = 14

## Distance at which the nameplate fully fades (metres).
const VISIBILITY_RANGE_END: float = 20.0

## Distance before VISIBILITY_RANGE_END at which fade begins (metres).
const VISIBILITY_RANGE_MARGIN: float = 4.0

## Outline size for readability.
const OUTLINE_SIZE: int = 1

## ConfigFile section for multiplayer settings.
const SETTINGS_SECTION: String = "multiplayer"

## ConfigFile key for nameplate visibility preference.
const SETTINGS_KEY: String = "show_nameplates"

## Settings file path.
const SETTINGS_PATH: String = "user://settings.cfg"

# ─── Exports ──────────────────────────────────────────────────────────────────

## Builder username (max USERNAME_MAX_CHARS displayed).
@export var username: String = ""

## Builder's primary colour (used to tint the nameplate label).
@export var builder_colour: Color = Color.WHITE

# ─── Private state ────────────────────────────────────────────────────────────

## Reference to the Label3D child (created in _ready if not already present).
var _label: Label3D = null

## Phase 5: UID of the remote builder (for Block/Report context menu, Surface J).
var _uid: String = ""

## Phase 5: long-press timer for context menu (500ms, one-shot).
var _long_press_timer: Timer = null

## Half-width of the nameplate touch target in screen pixels.
const NAMEPLATE_HIT_HALF_W: float = 24.0
## Half-height of the nameplate touch target in screen pixels.
const NAMEPLATE_HIT_HALF_H: float = 16.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("remote_nameplate")

	# Create Label3D child programmatically so this script can be attached as a
	# plain Node3D without a .tscn scene resource.
	if not has_node("Label3D"):
		var lbl := Label3D.new()
		lbl.name = "Label3D"
		lbl.position = Vector3(0.0, NAMEPLATE_Y_OFFSET, 0.0)
		add_child(lbl)
	_label = $Label3D
	_apply_label3d_settings()

	# Apply initial username + colour (in case setup() was called before _ready).
	if not username.is_empty() and is_instance_valid(_label):
		_label.text = username.left(USERNAME_MAX_CHARS)
		_label.modulate = builder_colour

	# Load nameplate preference from settings.
	_load_nameplate_pref()

	# Wire session state changes (hide nameplate if session ends).
	if is_instance_valid(NetworkManager):
		NetworkManager.session_state_changed.connect(_on_session_state_changed)

	# Phase 5: long-press timer for Block/Report context menu (Surface J).
	_long_press_timer = Timer.new()
	_long_press_timer.name = "_LongPressTimer"
	_long_press_timer.wait_time = 0.5
	_long_press_timer.one_shot = true
	_long_press_timer.timeout.connect(_on_nameplate_long_press)
	add_child(_long_press_timer)


# ─── Public API ───────────────────────────────────────────────────────────────

## Configure the nameplate with a username and colour.
## Safe to call before or after _ready().
## @param uname   Player username (truncated to USERNAME_MAX_CHARS in display).
## @param colour  Builder's primary colour tint.
## @param uid     (Phase 5) Supabase UID for Block/Report context menu. Optional.
func setup(uname: String, colour: Color, uid: String = "") -> void:
	username = uname
	builder_colour = colour
	_uid = uid
	if is_instance_valid(_label):
		_label.text = uname.left(USERNAME_MAX_CHARS)
		_label.modulate = colour


# ─── Private ─────────────────────────────────────────────────────────────────

## Apply Label3D display settings (billboard, fade, font).
func _apply_label3d_settings() -> void:
	if not is_instance_valid(_label):
		return
	_label.pixel_size             = LABEL_PIXEL_SIZE
	_label.font_size              = LABEL_FONT_SIZE
	_label.billboard              = BaseMaterial3D.BILLBOARD_ENABLED
	_label.visibility_range_end   = VISIBILITY_RANGE_END
	_label.visibility_range_end_margin = VISIBILITY_RANGE_MARGIN
	_label.outline_size           = OUTLINE_SIZE
	_label.no_depth_test          = true   # Always render on top of geometry.


## Load the "show_nameplates" preference from settings.cfg.
## Defaults to true when the key is absent (first launch).
func _load_nameplate_pref() -> void:
	var cfg := ConfigFile.new()
	var show: bool = true
	if cfg.load(SETTINGS_PATH) == OK:
		show = cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, true)
	visible = show


## Respond to session state changes — hide nameplate if session ends.
func _on_session_state_changed(state: String) -> void:
	if state in ["DISCONNECTED", "IDLE"]:
		visible = false


# ─── Phase 5: long-press context menu (Surface J) ─────────────────────────────

## Detect input within the nameplate's 2D screen-space bounding box.
## Mobile: InputEventScreenTouch; Desktop: InputEventMouseButton.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	var screen_center := _get_nameplate_screen_pos()
	if screen_center == Vector2.ZERO:
		return

	var hit_rect := Rect2(
		screen_center - Vector2(NAMEPLATE_HIT_HALF_W, NAMEPLATE_HIT_HALF_H),
		Vector2(NAMEPLATE_HIT_HALF_W * 2.0, NAMEPLATE_HIT_HALF_H * 2.0)
	)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and hit_rect.has_point(mb.global_position):
				_long_press_timer.start()
				get_viewport().set_input_as_handled()
			else:
				_long_press_timer.stop()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if hit_rect.has_point(mb.global_position):
				_show_context_menu(mb.global_position)
				get_viewport().set_input_as_handled()

	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and hit_rect.has_point(touch.position):
			_long_press_timer.start()
			get_viewport().set_input_as_handled()
		else:
			_long_press_timer.stop()


func _on_nameplate_long_press() -> void:
	var screen_pos := _get_nameplate_screen_pos()
	_show_context_menu(screen_pos)


## Compute the 2D screen-space position of this nameplate.
## Returns Vector2.ZERO if the camera or viewport is unavailable.
func _get_nameplate_screen_pos() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2.ZERO
	var camera: Camera3D = vp.get_camera_3d()
	if camera == null:
		return Vector2.ZERO
	# Nameplate is at +NAMEPLATE_Y_OFFSET above the builder root.
	var world_pos := global_position + Vector3(0.0, NAMEPLATE_Y_OFFSET, 0.0)
	return camera.unproject_position(world_pos)


func _show_context_menu(screen_pos: Vector2) -> void:
	var display_name := username.left(USERNAME_MAX_CHARS)
	var items: Array = [
		{
			"label": tr("ui.nameplate.report_action").format({"username": display_name}),
			"action": func():
				var rm: Node = get_node_or_null("/root/ReportModal")
				if rm != null and rm.has_method("open"):
					rm.call("open", _uid, display_name, "player"),
		},
		{
			"label": tr("ui.nameplate.block_action").format({"username": display_name}),
			"action": func():
				var bm: Node = get_node_or_null("/root/BlockModal")
				if bm != null and bm.has_method("open"):
					bm.call("open", _uid, display_name),
		},
	]

	var ctx_menu: Node = get_node_or_null("/root/ContextMenu")
	if ctx_menu != null and ctx_menu.has_method("show_menu"):
		ctx_menu.call("show_menu", items, screen_pos)
