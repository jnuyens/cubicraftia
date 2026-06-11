# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# context_menu.gd — Singleton context menu for Block/Report/Unfriend/Mute entry points.
#
# Registered as autoload "ContextMenu" in project.godot.
# Sits at CanvasLayer layer=25 (above modals at 20, always tappable on mobile).
#
# API:
#   ContextMenu.show(items: Array[Dictionary], screen_pos: Vector2)
#   items: Array of {label: String, action: Callable}
#
# Dismissal: any InputEventMouseButton or InputEventScreenTouch outside the panel,
# or Escape key.
#
# References:
#   05-UI-SPEC.md ContextMenu singleton recommendation
#   05-08-PLAN.md Task 2

extends CanvasLayer

# ─── Colors ──────────────────────────────────────────────────────────────────

## StyleBox_context_menu_panel: dominant navy at 0.96α, rounded 8px.
const COLOR_PANEL: Color = Color(0.106, 0.173, 0.337, 0.96)
const COLOR_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)

# ─── Node refs ───────────────────────────────────────────────────────────────

var _panel: PanelContainer = null
var _btn_vbox: VBoxContainer = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 25
	_build_ui()
	visible = false


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ContextMenuPanel"
	_panel.custom_minimum_size = Vector2(160, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)

	add_child(_panel)

	_btn_vbox = VBoxContainer.new()
	_btn_vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(_btn_vbox)


# ─── Public API ──────────────────────────────────────────────────────────────

## Show the context menu at screen_pos with the given items.
## @param items      Array of {label: String, action: Callable}.
## @param screen_pos 2D viewport-space position to anchor the menu.
func show_menu(items: Array, screen_pos: Vector2) -> void:
	# Clear previous buttons.
	for child in _btn_vbox.get_children():
		child.queue_free()

	# Build buttons from items array.
	for item in items:
		if not item is Dictionary:
			continue
		var d := item as Dictionary
		var lbl: String = d.get("label", "")
		var action: Callable = d.get("action", Callable())

		if lbl == "---":
			# Divider.
			var sep := HSeparator.new()
			sep.add_theme_color_override("color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.20))
			_btn_vbox.add_child(sep)
			continue

		var btn := Button.new()
		btn.text = lbl
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color", COLOR_WHITE)
		btn.add_theme_font_size_override("font_size", 14)
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0, 0, 0, 0)
		btn_style.content_margin_left = 4.0
		btn_style.content_margin_right = 4.0
		btn_style.content_margin_top = 4.0
		btn_style.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override("normal", btn_style)
		var btn_hover := StyleBoxFlat.new()
		btn_hover.bg_color = Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.10)
		btn_hover.content_margin_left = 4.0
		btn_hover.content_margin_right = 4.0
		btn_hover.content_margin_top = 4.0
		btn_hover.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override("hover", btn_hover)

		if action.is_valid():
			btn.pressed.connect(_on_item_pressed.bind(action))

		_btn_vbox.add_child(btn)

	visible = true
	# Position panel, awaiting layout for correct size.
	_panel.position = screen_pos
	await get_tree().process_frame
	_clamp_to_viewport()


## Hide the context menu.
func hide_menu() -> void:
	visible = false


# ─── Input handling ──────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		visible = false
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			# Check if click is outside the panel.
			if not _panel.get_global_rect().has_point(mb.global_position):
				visible = false
				get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if not _panel.get_global_rect().has_point(touch.position):
				visible = false
				get_viewport().set_input_as_handled()


# ─── Private helpers ──────────────────────────────────────────────────────────

func _on_item_pressed(action: Callable) -> void:
	visible = false
	if action.is_valid():
		action.call()


func _clamp_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	var panel_size := _panel.size
	var pos := _panel.position
	pos.x = clampf(pos.x, 0.0, vp_size.x - panel_size.x)
	pos.y = clampf(pos.y, 0.0, vp_size.y - panel_size.y)
	_panel.position = pos
