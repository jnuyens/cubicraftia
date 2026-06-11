# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# tool_durability_bar.gd — 4px-tall durability bar overlay on a hotbar slot (survival mode only).
#
# Per UI-SPEC.md §"Tool Durability Bar (survival mode only)":
#   - 4px tall StyleBoxFlat progress bar at the bottom edge of the 64×64px hotbar slot.
#   - Visible only in survival mode (hidden in sandbox via Features.is_survival_mode()).
#   - Full bar = green #5DBB46. Bar < 30% = red #D63828. Transitions are instant (no animation).
#   - Screen-reader label: ui.tool.durability_sr = "Durability: {pct}%".
#   - Does NOT need to be a touch target — display-only overlay.
#
# Pattern: closest analog is preset_chip.gd _update_style() (StyleBoxFlat overlay;
# preset_chip.gd lines 57-99). Visibility gating follows settings_menu.gd lines 96-97.
# See 02-PATTERNS.md §"src/ui/tool_durability_bar.gd".
#
# Wiring:
#   - Instantiated per hotbar slot by hotbar.gd in _build_slots().
#   - Positioned at the bottom edge of the slot via anchor overrides.
#   - ToolWear.durability_changed signal connected in _ready().
#   - Slot index set by hotbar on instantiation via _slot_index property.
#
# References:
#   UI-SPEC.md §"Tool Durability Bar (survival mode only)" lines 237-249
#   02-PATTERNS.md §"src/ui/tool_durability_bar.gd"
#   DOCS.md §3.4

class_name ToolDurabilityBar
extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

## Bar height in pixels per UI-SPEC.md (4px track + 4px margin = 8px total; track is 4px).
const BAR_HEIGHT: int = 4

## Colour when durability >= 30% (green #5DBB46 per UI-SPEC.md).
const COLOR_OK: Color = Color(0.365, 0.733, 0.275, 1.0)

## Colour when durability < 30% (red #D63828 per UI-SPEC.md).
const COLOR_LOW: Color = Color(0.839, 0.220, 0.157, 1.0)

## Track background colour (navy #1B2C56 per UI-SPEC.md — dominant chrome colour).
const COLOR_TRACK: Color = Color(0.106, 0.173, 0.337, 1.0)

## Threshold below which the bar turns red (30% per UI-SPEC.md).
const LOW_THRESHOLD: float = 0.3

# ─── State ────────────────────────────────────────────────────────────────────

## Current durability fraction [0.0 .. 1.0].
var _pct: float = 1.0

## Hotbar slot index (0-based). Set by hotbar.gd immediately after instantiation.
## Used to filter durability_changed events to the correct slot.
var _slot_index: int = -1

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Survival mode visibility gate per UI-SPEC.md §"Tool Durability Bar".
	# Sandbox mode: bar is hidden entirely; no durability logic runs per DOCS §3.4.
	visible = Features.is_survival_mode()

	# Anchor to bottom edge of parent slot.
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	offset_top = -BAR_HEIGHT
	offset_bottom = 0

	# Connect to ToolWear signal to receive live updates.
	if ToolWear.durability_changed.is_connected(_on_durability_changed):
		pass  # Already connected (should not happen on fresh instance).
	else:
		ToolWear.durability_changed.connect(_on_durability_changed)

	# Screen-reader tooltip.
	tooltip_text = tr("ui.tool.durability_sr").format({"pct": "100"})


func _exit_tree() -> void:
	# Disconnect to avoid dangling signal connections.
	if ToolWear.durability_changed.is_connected(_on_durability_changed):
		ToolWear.durability_changed.disconnect(_on_durability_changed)


func _draw() -> void:
	# Draw the track (full-width navy background).
	draw_rect(Rect2(0, 0, size.x, BAR_HEIGHT), COLOR_TRACK)

	# Draw the fill (proportional to _pct, colour by threshold).
	var fill_w: float = size.x * _pct
	if fill_w > 0.0:
		var fill_color: Color = COLOR_OK if _pct >= LOW_THRESHOLD else COLOR_LOW
		draw_rect(Rect2(0, 0, fill_w, BAR_HEIGHT), fill_color)


# ─── Public API ───────────────────────────────────────────────────────────────

## Directly set the durability percentage (0.0..1.0). Used for testing and initial sync.
## @param pct  New durability fraction [0.0..1.0].
func set_durability_pct(pct: float) -> void:
	_pct = clampf(pct, 0.0, 1.0)
	# Update screen-reader label.
	tooltip_text = tr("ui.tool.durability_sr").format({"pct": str(int(_pct * 100.0))})
	queue_redraw()


# ─── Signal handler ───────────────────────────────────────────────────────────

## Called by ToolWear.durability_changed for ANY tool instance.
## Filters to this slot's instance_id ("slot_{_slot_index}").
func _on_durability_changed(_tool_id: String, instance_id: String, new_pct: float) -> void:
	if _slot_index < 0:
		return
	if instance_id != ("slot_%d" % _slot_index):
		return
	set_durability_pct(new_pct)
