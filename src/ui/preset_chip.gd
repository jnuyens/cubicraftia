# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# preset_chip.gd - Graphics preset chip button.
#
# Reusable chip for Auto/Low/Medium/High graphics presets.
# Per UI-SPEC.md §Settings Screen:
#   - Size: 96x40px (touch target, grouped)
#   - Active: filled #F5C30D with #1B2C56 16px semibold label
#   - Inactive: outlined #F1F0EA 1px stroke with #F1F0EA label

class_name PresetChip
extends Button

# ─── Constants ────────────────────────────────────────────────────────────────

const COLOR_ACCENT: Color = Color(0.961, 0.765, 0.051, 1.0)
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 1.0)
const COLOR_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)

# ─── Exported properties ──────────────────────────────────────────────────────

## Preset identifier: "auto", "low", "medium", or "high".
@export var preset_id: StringName = &"auto"

# ─── State ────────────────────────────────────────────────────────────────────

var _is_active: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	custom_minimum_size = Vector2(96, 40)
	_update_style()
	# Connect press to apply preset
	pressed.connect(_on_pressed)


func _update_label() -> void:
	var key := "ui.settings.graphics.preset.%s" % preset_id
	text = tr(key)


# ─── Public API ──────────────────────────────────────────────────────────────

## Returns the preset_id of this chip.
func get_preset_id() -> StringName:
	return preset_id


## Set active/inactive visual state.
func set_active(active: bool) -> void:
	_is_active = active
	_update_style()


func _update_style() -> void:
	_update_label()
	if _is_active:
		# Filled yellow, navy text
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_ACCENT
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 12.0
		style.content_margin_top = 8.0
		style.content_margin_right = 12.0
		style.content_margin_bottom = 8.0
		add_theme_stylebox_override("normal", style)
		add_theme_stylebox_override("hover", style)
		add_theme_stylebox_override("pressed", style)
		add_theme_color_override("font_color", COLOR_NAVY)
		add_theme_color_override("font_pressed_color", COLOR_NAVY)
		add_theme_color_override("font_hover_color", COLOR_NAVY)
		add_theme_font_size_override("font_size", 16)
	else:
		# Outlined brick-white
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = COLOR_WHITE
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 12.0
		style.content_margin_top = 8.0
		style.content_margin_right = 12.0
		style.content_margin_bottom = 8.0
		add_theme_stylebox_override("normal", style)
		add_theme_color_override("font_color", COLOR_WHITE)
		add_theme_color_override("font_pressed_color", COLOR_ACCENT)
		add_theme_font_size_override("font_size", 14)


func _on_pressed() -> void:
	# Notify parent settings menu that this preset was selected
	var parent := get_parent()
	if parent != null and parent.has_method("_on_preset_chip_pressed"):
		parent._on_preset_chip_pressed(preset_id)
