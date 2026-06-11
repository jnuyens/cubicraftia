# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# hotbar.gd — 8-slot hotbar HUD
#
# Phase 1: slot 1 holds the 1×1 brick (brick_1x1.tres), slots 2-8 empty.
# Selected slot has a 2px #F5C30D accent ring.
# Tap-to-select on mobile; keyboard 1-8 keys on desktop (via Input actions hotbar_1..8).
#
# Phase 2 (Plan 02-10) additions:
#   - ToolDurabilityBar overlay on each slot (survival mode only; hidden in sandbox).
#   - Mode badge Label (Survival / Sandbox) shown above/beside hotbar frame.
#   - set_slot_tool_id(slot, tool_id) for Plan 12's palette-to-hotbar equip wiring.
#   - Lantern detection: when active slot tool_id == "lantern_handheld", enables
#     Builder.set_handheld_lantern(true) and disables it when switching away.
#
# Per UI-SPEC.md §Mobile Control Overlay:
#   Slot size: 64×64px (56×56 on screens <600px wide)
#   Gap: 8px between slots
#   Total: 8 slots × 64 + 7 × 8 = 568px
#   Selected: 2px #F5C30D outline
#
# References:
#   UI-SPEC.md §"Tool Durability Bar (survival mode only)"
#   02-PATTERNS.md §"src/ui/hotbar.tscn / hotbar.gd (EXTEND IN PLACE)"

class_name Hotbar
extends HBoxContainer

# ─── Constants ────────────────────────────────────────────────────────────────

const SLOT_SIZE: int = 64
const SLOT_SIZE_SMALL: int = 56
const SLOT_GAP: int = 8
const ACCENT_COLOR: Color = Color(0.961, 0.765, 0.051, 1.0)
const SLOT_COUNT: int = 8

# ─── State ────────────────────────────────────────────────────────────────────

## Currently selected slot index (0-based).
var selected_slot: int = 0

## Slot Panel nodes.
var _slots: Array = []

## Per-slot tool_id strings (empty = no tool; set by set_slot_tool_id).
var _slot_tool_ids: Array = []

## Per-slot brick def_id strings (empty = no brick; set by set_slot_brick).
var _slot_def_ids: Array = []

## Per-slot brick colour indices (-1 = not set; set by set_slot_brick).
var _slot_colour_indices: Array = []

## Mode badge Label (Survival / Sandbox).
var _mode_badge: Label = null

## Preloaded ToolDurabilityBar script.
const _DurabilityBarScript := preload("res://src/ui/tool_durability_bar.gd")

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Group so the Builder (place) and BrickPalette (equip) can find us without a path.
	add_to_group("hotbar")
	add_theme_constant_override("separation", SLOT_GAP)
	_build_slots()
	_update_selection()
	_build_mode_badge()


## The brick currently equipped in the active hotbar slot, for Builder._try_place.
## Returns {"def_id": String (empty if none), "colour_index": int (-1 if unset)}.
func get_active_brick() -> Dictionary:
	var has_slot: bool = selected_slot >= 0 and selected_slot < _slot_def_ids.size()
	return {
		"def_id": str(_slot_def_ids[selected_slot]) if has_slot else "",
		"colour_index": int(_slot_colour_indices[selected_slot]) if has_slot else -1,
	}


func _build_slots() -> void:
	# Initialise per-slot tool_id, def_id, and colour_index arrays.
	_slot_tool_ids.resize(SLOT_COUNT)
	_slot_def_ids.resize(SLOT_COUNT)
	_slot_colour_indices.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		_slot_tool_ids[i] = ""
		_slot_def_ids[i] = ""
		_slot_colour_indices[i] = -1

	for i in range(SLOT_COUNT):
		var panel := Panel.new()
		panel.name = "Slot%d" % (i + 1)
		panel.add_to_group("hotbar_slot")
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		# Clip children to the slot rect so a scaled icon can never spill a sliver past
		# the slot border into the neighbouring slot (v1.1 QA #1).
		panel.clip_contents = true

		# Create inner TextureRect for the icon
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		# Clamp to edge (no wrap) so the scaled icon's linear-filtered border doesn't
		# sample the opposite texture edge and bleed a thin sliver into the slot edge
		# (v1.1 QA #1: hotbar slots showed an adjacent-icon edge sliver). DISABLED ==
		# clamp-to-edge, independent of per-asset import flags.
		icon.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		# Load icon texture if available (may not be imported in headless/CI mode)
		var icon_path := "res://assets/textures/icons/hotbar_slot_empty.png"
		if ResourceLoader.exists(icon_path, "Texture2D"):
			var icon_tex: Texture2D = load(icon_path)
			if icon_tex != null:
				icon.texture = icon_tex

		# Tooltip for screen-reader (slot n - empty)
		panel.tooltip_text = tr("ui.hotbar.slot_empty").format({"n": str(i + 1)})

		panel.add_child(icon)
		add_child(panel)
		_slots.append(panel)

		# Connect tap on mobile
		var btn := Button.new()
		btn.name = "TapArea"
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		var slot_index := i
		btn.pressed.connect(func(): _select_slot(slot_index))
		panel.add_child(btn)

		# ── Plan 02-10: ToolDurabilityBar overlay at slot bottom ──────────────
		# Instantiate one bar per slot; survival-mode visibility is gated inside the bar.
		var dur_bar: Control = Control.new()
		dur_bar.set_script(_DurabilityBarScript)
		dur_bar.name = "DurabilityBar"
		panel.add_child(dur_bar)
		# Set slot index so the bar filters ToolWear.durability_changed correctly.
		# _slot_index is set after _ready() via direct field access.
		dur_bar.set("_slot_index", i)


## Build the Survival/Sandbox mode badge Label (Plan 02-10).
## Positioned above the hotbar at the top-right of the HBoxContainer frame.
func _build_mode_badge() -> void:
	_mode_badge = Label.new()
	_mode_badge.name = "ModeBadge"
	# Mode badge text: "Survival" in survival, "Sandbox" in sandbox.
	if Features.is_survival_mode():
		_mode_badge.text = tr("ui.hud.mode.survival")
	else:
		_mode_badge.text = tr("ui.hud.mode.sandbox")
	# Style: 14px semibold, brick-white on navy background (UI-SPEC.md §Typography).
	_mode_badge.add_theme_font_size_override("font_size", 14)
	# Position badge above the hotbar frame (outside the HBoxContainer).
	# Use a separate CanvasLayer-level anchor via get_parent().add_child if needed;
	# for Phase 2 simplicity, add as a sibling via the parent container.
	var parent_node: Node = get_parent()
	if parent_node is Control:
		# Defer the add_child — parent is busy setting up its children when our
		# _ready fires, calling add_child directly throws "Parent is busy".
		(parent_node as Control).add_child.call_deferred(_mode_badge)
		# Anchoring/positioning must also defer until after the node is in the tree.
		_mode_badge.tree_entered.connect(func() -> void:
			_mode_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			_mode_badge.position = Vector2(-120.0, 4.0)
		, CONNECT_ONE_SHOT)
	else:
		# Fallback: add as child of this HBoxContainer.
		add_child(_mode_badge)


func _process(_delta: float) -> void:
	# Keyboard 1-8 hotbar selection (desktop)
	for i in range(SLOT_COUNT):
		if Input.is_action_just_pressed("hotbar_%d" % (i + 1)):
			_select_slot(i)


func _select_slot(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	var prev_slot := selected_slot
	selected_slot = index
	_update_selection()
	# Lantern wiring: toggle handheld lantern light when switching slots (Plan 02-10).
	_update_lantern_light(prev_slot, selected_slot)


## Plan 02-10: Set a tool_id string for a specific hotbar slot.
## Called by Plan 12's palette UI when the player equips a tool from the palette.
## @param slot    Slot index (0-based).
## @param tool_id Tool definition ID (e.g. "lantern_handheld") or "" to clear.
func set_slot_tool_id(slot: int, tool_id: String) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	var prev_tool: String = _slot_tool_ids[slot]
	_slot_tool_ids[slot] = tool_id
	_update_slot_icon(slot)
	# If the active slot changed its lantern state, update the light.
	if slot == selected_slot:
		_update_lantern_light(slot if prev_tool == "lantern_handheld" else -1,
		                      slot if tool_id == "lantern_handheld" else -1)


## Plan 03-05: Set a non-brick item_id + count for a specific hotbar slot.
## Called by InventorySlideIn when inventory state changes for hotbar slots (40-47).
## Handles keys (key_bronze/silver/gold/diamond), food, strawberry, and generic items.
## Icon assets ship in Plans 03-06 (keys) and 03-09 (food/strawberry); falls back to null.
## @param slot_index   Slot index (0-based, clamped to [0, SLOT_COUNT-1]).
## @param item_id      Item definition ID string, or "" to clear.
## @param count        Stack count (0 clears the slot).
func set_slot_item(slot_index: int, item_id: String, count: int) -> void:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return
	var panel: Panel = _slots[slot_index] as Panel
	if panel == null:
		return

	# Resolve icon from assets/textures/icons/ (item-specific paths per naming convention).
	var icon: TextureRect = panel.get_node_or_null("Icon") as TextureRect
	if icon != null:
		var icon_tex: Texture2D = _resolve_item_icon(item_id)
		icon.texture = _center_cropped(icon_tex) if icon_tex != null else null

	# Update or create the count label for non-brick items.
	var count_label: Label = panel.get_node_or_null("CountLabel") as Label
	if count_label == null and count > 1:
		count_label = Label.new()
		count_label.name = "CountLabel"
		count_label.add_theme_font_size_override("font_size", 12)
		count_label.add_theme_color_override("font_color", Color(0.945, 0.941, 0.918, 1.0))
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		count_label.offset_left = 2.0
		count_label.offset_top = 2.0
		count_label.offset_right = -2.0
		count_label.offset_bottom = -2.0
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(count_label)
	if count_label != null:
		count_label.text = str(count) if count > 1 else ""

	# Update tooltip.
	var item_name: String = _resolve_item_name_for_hotbar(item_id)
	if item_id == "" or count == 0:
		panel.tooltip_text = tr("ui.hotbar.slot_empty").format({"n": str(slot_index + 1)})
	else:
		panel.tooltip_text = tr("ui.hotbar.slot_filled").format({
			"n": str(slot_index + 1), "brick_name": item_name})


## Set a slot's Icon TextureRect from the equipped tool/brick definition's icon_path
## (art-sheet slices in res://assets/textures/icons/). Falls back to the empty-slot art.
func _update_slot_icon(slot: int) -> void:
	if slot < 0 or slot >= _slots.size():
		return
	var panel: Panel = _slots[slot] as Panel
	if panel == null:
		return
	var icon: TextureRect = panel.get_node_or_null("Icon") as TextureRect
	if icon == null:
		return
	var ip: String = _slot_icon_path(slot)
	if ip != "" and ResourceLoader.exists(ip, "Texture2D"):
		icon.texture = _center_cropped(load(ip) as Texture2D)
		return
	var empty: String = "res://assets/textures/icons/hotbar_slot_empty.png"
	# Empty-slot art is a full-bleed frame, NOT a tool sprite — show it un-cropped.
	icon.texture = (load(empty) as Texture2D) if ResourceLoader.exists(empty, "Texture2D") else null


## Fraction of each edge to crop off a tool/brick icon before display.
## The art sheet was sliced with bleed: several icon PNGs (e.g. pickaxe_bronze.png,
## shovel_iron.png) carry a partial neighbouring tool in the ~12-30 px band from each
## 256 px edge. With STRETCH_KEEP_ASPECT_CENTERED on a square icon in a square slot the
## sprite fills the slot edge-to-edge, so that bleed renders as a thin sliver on the slot
## border (pickaxe showed it on the LEFT, shovel on BOTH sides). texture_repeat=DISABLED +
## clip_contents did not help because the sliver is real image content, not a wrap/filter
## artefact. Cropping the outer 15 % on every side drops the bleed entirely; the actual
## tools occupy only the central ~[60..200]/256 columns, so nothing meaningful is lost.
const _ICON_CROP_FRAC: float = 0.15
## Cache of center-cropped AtlasTextures keyed by source Texture2D so we build each region once.
var _icon_crop_cache: Dictionary = {}

## Return a center-cropped view of a tool/brick icon that excludes the edge-bleed slivers
## baked into the source art sheet. Wraps the source in an AtlasTexture whose region is the
## central (1 - 2*_ICON_CROP_FRAC) box. Returns the texture unchanged when it is null or has
## no size (headless/CI). Cached per source so repeated slot updates don't re-allocate.
func _center_cropped(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _icon_crop_cache.has(tex):
		return _icon_crop_cache[tex]
	var w: float = float(tex.get_width())
	var h: float = float(tex.get_height())
	if w <= 0.0 or h <= 0.0:
		return tex
	var inset_x: float = w * _ICON_CROP_FRAC
	var inset_y: float = h * _ICON_CROP_FRAC
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(inset_x, inset_y, w - 2.0 * inset_x, h - 2.0 * inset_y)
	# filter_clip keeps the crop edges crisp (no neighbour sampling outside the region).
	atlas.filter_clip = true
	_icon_crop_cache[tex] = atlas
	return atlas


## Resolve the icon_path for a slot: tool definition first (src/tools/<id>.tres), then
## brick definition (BrickRegistry). "" when neither has an icon.
func _slot_icon_path(slot: int) -> String:
	var tool_id: String = str(_slot_tool_ids[slot]) if slot < _slot_tool_ids.size() else ""
	if tool_id != "":
		var tp: String = "res://src/tools/%s.tres" % tool_id
		if ResourceLoader.exists(tp):
			var td: Resource = load(tp)
			if td != null:
				var p: Variant = td.get("icon_path")
				if p is String and (p as String) != "":
					return p
	var def_id: String = str(_slot_def_ids[slot]) if slot < _slot_def_ids.size() else ""
	if def_id != "" and BrickRegistry != null:
		var bd: Resource = BrickRegistry.get_definition(def_id)
		if bd != null:
			var p2: Variant = bd.get("icon_path")
			if p2 is String and (p2 as String) != "":
				return p2
	return ""


## Resolve an icon Texture2D for a non-brick item_id.
## Returns null when the asset does not yet exist (ships in Plans 03-06 / 03-09).
func _resolve_item_icon(item_id: String) -> Texture2D:
	if item_id == "":
		return null
	var base: String = "res://assets/textures/icons/"
	var paths: Array = [
		base + item_id + ".png",
		base + "hotbar_slot_empty.png",
	]
	for path: String in paths:
		if ResourceLoader.exists(path, "Texture2D"):
			var tex: Texture2D = load(path) as Texture2D
			if tex != null:
				return tex
	return null


## Resolve a localised display name for the hotbar tooltip.
func _resolve_item_name_for_hotbar(item_id: String) -> String:
	if item_id == "":
		return ""
	# Try items.{item_id}.name i18n key.
	var i18n_key: String = "items." + item_id + ".name"
	var translated: String = tr(i18n_key)
	if translated != i18n_key:
		return translated
	# Try BrickRegistry.
	var def: Resource = BrickRegistry.get_definition(item_id) if BrickRegistry != null else null
	if def != null and def.get("display_name_key") != null:
		return tr(def.get("display_name_key") as String)
	return item_id


## Plan 02-12: Set a brick def_id + colour_index for a specific hotbar slot.
## Called by BrickPaletteUI when the player equips a brick from the palette.
## @param slot         Slot index (0-based, clamped to valid range).
## @param def_id       BrickDefinition ID from BrickRegistry, or "" to clear.
## @param colour_index Palette colour index (0..17) or -1 for natural/no colour.
func set_slot_brick(slot: int, def_id: String, colour_index: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	# T-12-04 mitigation: validate def_id exists in BrickRegistry before setting slot
	if def_id != "" and BrickRegistry.get_definition(def_id) == null:
		push_warning("Hotbar.set_slot_brick: unknown def_id '%s' — slot not updated." % def_id)
		return
	_slot_def_ids[slot] = def_id
	_slot_colour_indices[slot] = colour_index
	_update_slot_icon(slot)
	# Update slot tooltip for screen-reader
	if slot < _slots.size():
		var def: BrickDefinition = BrickRegistry.get_definition(def_id) if def_id != "" else null
		if def != null:
			var brick_name: String = tr(def.display_name_key)
			(_slots[slot] as Panel).tooltip_text = tr("ui.hotbar.slot_filled").format({
				"n": str(slot + 1), "brick_name": brick_name})
		else:
			(_slots[slot] as Panel).tooltip_text = tr("ui.hotbar.slot_empty").format(
				{"n": str(slot + 1)})


## Return the brick def_id equipped in the currently active slot.
var active_def_id: String:
	get:
		if selected_slot < _slot_def_ids.size():
			return _slot_def_ids[selected_slot]
		return ""

## Return the colour index equipped in the currently active slot.
var active_colour_index: int:
	get:
		if selected_slot < _slot_colour_indices.size():
			return _slot_colour_indices[selected_slot]
		return -1

## Return the currently active slot index (alias for selected_slot, for API consistency).
var active_slot: int:
	get:
		return selected_slot


## Toggle the handheld lantern OmniLight3D on the builder based on slot transition.
## Called on slot selection change and on tool_id assignment to the active slot.
## @param prev_slot  Previous active slot index (or -1 if n/a).
## @param next_slot  New active slot index (or -1 if n/a).
func _update_lantern_light(prev_slot: int, next_slot: int) -> void:
	var builder: Node = get_tree().get_first_node_in_group("builder") if is_inside_tree() else null
	if builder == null or not builder.has_method("set_handheld_lantern"):
		return
	# Was previous slot lantern?
	var was_lantern: bool = (prev_slot >= 0 and prev_slot < SLOT_COUNT
		and _slot_tool_ids[prev_slot] == "lantern_handheld")
	# Is new slot lantern?
	var is_lantern: bool = (next_slot >= 0 and next_slot < SLOT_COUNT
		and _slot_tool_ids[next_slot] == "lantern_handheld")
	if was_lantern != is_lantern:
		builder.call("set_handheld_lantern", is_lantern)


func _update_selection() -> void:
	for i in range(_slots.size()):
		var panel: Panel = _slots[i]
		if i == selected_slot:
			# Apply yellow accent outline via StyleBoxFlat
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.106, 0.173, 0.337, 0.6)
			style.border_width_left = 2
			style.border_width_top = 2
			style.border_width_right = 2
			style.border_width_bottom = 2
			style.border_color = ACCENT_COLOR
			panel.add_theme_stylebox_override("panel", style)
		else:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.106, 0.173, 0.337, 0.4)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.945, 0.941, 0.918, 0.4)
			panel.add_theme_stylebox_override("panel", style)
