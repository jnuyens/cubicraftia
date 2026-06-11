# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# virtual_joystick.gd — Custom ~150-LoC virtual joystick Control node.
#
# Per UI-SPEC.md §Mobile Control Overlay:
#   - Anchored bottom-left; 128px active radius from initial touch point.
#   - Base: 96×96px navy 0.6α circle, always visible.
#   - Knob: 48×48px brick-white circle, appears at touch point.
#   - Maps (dx, dz) → Input actions: move_forward/back/left/right.
#   - Emits joystick_moved(direction: Vector2) in [-1..1]².
#   - Emits joystick_released().
#
# Design: custom node (not a plugin) per UI-SPEC.md Registry Safety §"Don't Hand-Roll"
# bias toward custom for Phase 1 to minimise external dependencies.
#
# Thread safety: all touch handling is on the main thread.

class_name VirtualJoystick
extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

## Active radius in pixels (UI-SPEC §Mobile Control Overlay).
const ACTIVE_RADIUS: float = 128.0

## Base circle size in pixels (UI-SPEC §Mobile Control Overlay).
const BASE_SIZE: float = 96.0

## Knob circle size in pixels.
const KNOB_SIZE: float = 48.0

## Minimum deflection fraction to trigger a directional action.
const DEADZONE: float = 0.15

## Navy colour for the joystick base (0.6α per UI-SPEC).
const COLOR_BASE: Color = Color(0.106, 0.173, 0.337, 0.6)

## Brick white for the knob.
const COLOR_KNOB: Color = Color(0.945, 0.941, 0.918, 0.9)

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted every frame the finger is held, with normalised direction in [-1..1]².
signal joystick_moved(direction: Vector2)

## Emitted when the finger lifts (joystick returns to centre).
signal joystick_released()

# ─── Internal state ───────────────────────────────────────────────────────────

## True when a finger is actively held on this joystick.
var _active: bool = false

## Touch index tracking this joystick (to ignore other fingers).
var _touch_index: int = -1

## World-space centre of the touch (where the finger first pressed).
var _touch_origin: Vector2 = Vector2.ZERO

## Current knob offset from origin, clamped to ACTIVE_RADIUS.
var _knob_offset: Vector2 = Vector2.ZERO

## Last computed normalised direction.
var _direction: Vector2 = Vector2.ZERO

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Accept all touch input events.
	set_process_input(true)
	custom_minimum_size = Vector2(BASE_SIZE, BASE_SIZE)
	queue_redraw()


# ─── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not _active:
			# Begin tracking this touch if it is within the control's rect.
			var local_pos := get_local_mouse_position()
			# For touch events, convert global position to local.
			local_pos = (event as InputEventScreenTouch).position - global_position
			if Rect2(Vector2.ZERO, size).has_point(local_pos) or size == Vector2.ZERO:
				_active = true
				_touch_index = event.index
				_touch_origin = (event as InputEventScreenTouch).position
				_knob_offset = Vector2.ZERO
				_direction = Vector2.ZERO
				queue_redraw()
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_index:
			_release()
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag and event.index == _touch_index:
		var raw_offset: Vector2 = (event as InputEventScreenDrag).position - _touch_origin
		_knob_offset = raw_offset.limit_length(ACTIVE_RADIUS)
		_direction = _knob_offset / ACTIVE_RADIUS

		# Apply directional input actions
		_apply_actions(_direction)
		emit_signal("joystick_moved", _direction)
		queue_redraw()
		get_viewport().set_input_as_handled()


# ─── Drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var centre := size / 2.0

	# Base circle (always visible)
	draw_circle(centre, BASE_SIZE / 2.0, COLOR_BASE)

	# Knob (visible when active, otherwise at centre)
	var knob_pos := centre + _knob_offset
	draw_circle(knob_pos, KNOB_SIZE / 2.0, COLOR_KNOB)


# ─── Internal helpers ─────────────────────────────────────────────────────────

func _release() -> void:
	_active = false
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	_direction = Vector2.ZERO
	_clear_actions()
	emit_signal("joystick_released")
	queue_redraw()


## Map the normalised joystick direction to Godot input actions so existing
## builder.gd code (which reads Input.get_vector("move_left",...)) works unchanged.
func _apply_actions(dir: Vector2) -> void:
	# dir.x = right (+) / left (-)
	# dir.y = down (+) / up (-) in screen space → forward = negative Y
	var threshold: float = DEADZONE

	# Forward / back (Y axis, inverted: up on joystick = move forward)
	if dir.y < -threshold:
		Input.action_press("move_forward", abs(dir.y))
		Input.action_release("move_back")
	elif dir.y > threshold:
		Input.action_press("move_back", abs(dir.y))
		Input.action_release("move_forward")
	else:
		Input.action_release("move_forward")
		Input.action_release("move_back")

	# Left / right (X axis)
	if dir.x < -threshold:
		Input.action_press("move_left", abs(dir.x))
		Input.action_release("move_right")
	elif dir.x > threshold:
		Input.action_press("move_right", abs(dir.x))
		Input.action_release("move_left")
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")


func _clear_actions() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")


## Public getter for current direction.
func get_direction() -> Vector2:
	return _direction
