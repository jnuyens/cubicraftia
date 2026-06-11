# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# hp_bar.gd — 10-heart HP bar HUD (survival mode only).
#
# Shown in survival worlds; hidden in sandbox via Features.is_survival_mode() gate
# (mirrors tool_durability_bar.gd L62 pattern).
#
# Heart icons:
#   health_heart_full.png / health_heart_half.png / health_heart_empty.png from assets/textures/icons/.
#   If icons not yet authored (Plan 03-09 ships them), each heart degrades gracefully
#   to a 24×24 ColorRect (#D63828 full, #888888 empty) so the bar is still usable.
#
# Screen-reader: the overall bar Label accessibility string uses tr("ui.hp.bar_sr")
# (owned by Plan 03-05 locale/en.po).
#
# References:
#   03-UI-SPEC.md L72 — top-left anchor, 16px from edge + safe-area inset
#   03-UI-SPEC.md L73 — full/empty hearts only (half-heart is v1.1 polish)
#   03-UI-SPEC.md L111 — #D63828 for full hearts
#   03-CONTEXT.md D-08 — HP bar as primary survival HUD element
#   03-PATTERNS.md L695-757 — HP bar analog: hotbar.gd _build_slots

class_name HpBar
extends HBoxContainer

# ─── Constants ────────────────────────────────────────────────────────────────

## Total number of hearts in the bar (MAX_HP = 10).
const HEART_COUNT: int = 10

## Heart icon size in pixels per UI-SPEC L73.
const HEART_SIZE_PX: int = 24

## Gap between hearts in pixels per UI-SPEC L73.
const HEART_GAP_PX: int = 4

## Path to the full-heart icon.
const ICON_FULL: String = "res://assets/textures/icons/health_heart_full.png"

## Path to the half-heart icon (v1 ships but unused — half-hearts are v1.1 polish).
const ICON_HALF: String = "res://assets/textures/icons/health_heart_half.png"

## Path to the empty-heart icon.
const ICON_EMPTY: String = "res://assets/textures/icons/health_heart_empty.png"

## Fallback colour for filled hearts at full HP. Hearts are tinted by HP%:
## green at full → yellow at one-third → red at low, matching the universal
## "green = healthy, red = danger" convention (UAT feedback — the original
## always-red classic-style was unintuitive on a square ColorRect bar).
const COLOR_FULL: Color = Color(0.314, 0.741, 0.298, 1.0)   # #50BD4C healthy green
const COLOR_MID:  Color = Color(0.953, 0.749, 0.196, 1.0)   # #F3BF32 caution yellow
const COLOR_LOW:  Color = Color(0.839, 0.220, 0.157, 1.0)   # #D63828 destructive red

## Fallback colour for empty hearts when PNG icons are not yet authored.
const COLOR_EMPTY: Color = Color(0.533, 0.533, 0.533, 0.5)  # mid-grey at 50%

# ─── State ────────────────────────────────────────────────────────────────────

## Array of heart display nodes (TextureRect when PNG available, ColorRect fallback).
var _hearts: Array = []

## Cached reference to the builder node (wired in _ready).
var _builder: Builder = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Survival-mode visibility gate (mirrors tool_durability_bar.gd L62).
	visible = Features.is_survival_mode()

	# Inter-heart gap.
	add_theme_constant_override("separation", HEART_GAP_PX)

	# Build the 10-heart row.
	_build_hearts()

	# Wire to the Builder hp_changed signal.
	var b: Node = get_tree().get_first_node_in_group("builder")
	if b != null and b.has_signal("hp_changed"):
		b.hp_changed.connect(_on_hp_changed)
		_builder = b as Builder
		# Sync current HP immediately.
		_on_hp_changed(b.get("hp") if b.get("hp") != null else Builder.MAX_HP)


## Build the heart display nodes. Uses TextureRect with PNG icons if available,
## else a 24×24 ColorRect as a graceful fallback (icons authored in Plan 03-09).
func _build_hearts() -> void:
	_hearts.clear()
	# Remove any old children (in case _build_hearts is called again).
	for child in get_children():
		child.queue_free()

	for i: int in range(HEART_COUNT):
		if ResourceLoader.exists(ICON_FULL, "Texture2D"):
			# PNG icons available — use TextureRect.
			var tr_node := TextureRect.new()
			tr_node.name = "Heart%d" % (i + 1)
			tr_node.custom_minimum_size = Vector2(HEART_SIZE_PX, HEART_SIZE_PX)
			tr_node.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tr_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var tex: Texture2D = load(ICON_FULL)
			if tex != null:
				tr_node.texture = tex
			add_child(tr_node)
			_hearts.append(tr_node)
		else:
			# Fallback: coloured ColorRect (no PNG yet).
			var cr_node := ColorRect.new()
			cr_node.name = "Heart%d" % (i + 1)
			cr_node.custom_minimum_size = Vector2(HEART_SIZE_PX, HEART_SIZE_PX)
			cr_node.color = COLOR_FULL
			add_child(cr_node)
			_hearts.append(cr_node)


# ─── Signal handler ───────────────────────────────────────────────────────────

## Update the heart display when builder HP changes.
## All filled hearts share a single colour tinted by the HP% so the player
## reads bar health at a glance: green (>66%) → yellow (33-66%) → red (<33%).
## v1 ships full/empty only (half-heart is v1.1 polish per UI-SPEC L73).
## @param new_hp  New HP value [0..MAX_HP].
func _on_hp_changed(new_hp: int) -> void:
	var hp_ratio: float = float(new_hp) / float(HEART_COUNT)
	var fill_color: Color = COLOR_LOW
	if hp_ratio > 0.66:
		fill_color = COLOR_FULL
	elif hp_ratio > 0.33:
		fill_color = COLOR_MID
	for i: int in range(HEART_COUNT):
		var filled: bool = i < new_hp
		var heart: Node = _hearts[i]
		if heart is TextureRect:
			var tr_heart: TextureRect = heart as TextureRect
			var icon_path: String = ICON_FULL if filled else ICON_EMPTY
			if ResourceLoader.exists(icon_path, "Texture2D"):
				tr_heart.texture = load(icon_path)
				tr_heart.modulate = fill_color if filled else Color(1, 1, 1, 0.3)
			elif tr_heart.texture != null:
				tr_heart.modulate = fill_color if filled else Color(1, 1, 1, 0.3)
		elif heart is ColorRect:
			var cr_heart: ColorRect = heart as ColorRect
			cr_heart.color = fill_color if filled else COLOR_EMPTY
