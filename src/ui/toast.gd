# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# toast.gd — Toast notification renderer.
#
# Per UI-SPEC.md §Toast Notification Pattern:
#   - Connects to Toasts.toast_requested signal in _ready().
#   - show_toast(key, severity) translates the key, sets label text, animates in/out.
#   - Severity "info" → yellow left border; "error" → red left border.
#   - 4s hold, 250ms fade-in / 250ms fade-out via Tween (ease-out cubic).
#   - Tappable to dismiss early.
#   - Max one toast on screen: newer replaces older with crossfade.
#
# The scene structure:
#   Toast (PanelContainer, script=this)
#     └── Panel (PanelContainer, StyleBoxFlat with left border)
#           └── Label

extends PanelContainer

# ─── Constants ────────────────────────────────────────────────────────────────

const FADE_DURATION: float = 0.25
const HOLD_DURATION: float = 4.0

const COLOR_BORDER_INFO: Color = Color(0.961, 0.765, 0.051, 1.0)
const COLOR_BORDER_ERROR: Color = Color(0.839, 0.220, 0.157, 1.0)
const COLOR_BG: Color = Color(0.106, 0.173, 0.337, 0.92)

# ─── Node refs ────────────────────────────────────────────────────────────────

@onready var _panel: PanelContainer = $Panel
@onready var _label: Label = $Panel/Label

# ─── Internal state ───────────────────────────────────────────────────────────

var _tween: Tween = null
var _dismiss_timer: float = 0.0
var _animating: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	visible = false
	modulate.a = 0.0
	# Connect to Toasts autoload signal
	Toasts.toast_requested.connect(_on_toast_requested)
	# Tap to dismiss
	gui_input.connect(_on_gui_input)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_toast_requested(key: String, severity: String) -> void:
	show_toast(key, severity)


## Public method for direct calls in tests.
func show_toast(key: String, severity: String = "info") -> void:
	var text := tr(key)
	_label.text = text

	# Update border colour based on severity
	var border_color := COLOR_BORDER_INFO if severity == "info" else COLOR_BORDER_ERROR
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_width_left = 4
	style.border_color = border_color
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 24.0
	style.content_margin_top = 16.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 16.0
	_panel.add_theme_stylebox_override("panel", style)

	# Cancel any active tween
	if _tween != null and _tween.is_running():
		_tween.kill()

	# Animate in
	visible = true
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_interval(HOLD_DURATION)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_callback(func(): visible = false)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_dismiss_early()


func _dismiss_early() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_callback(func(): visible = false)
