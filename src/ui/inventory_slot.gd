# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# inventory_slot.gd — Per-slot Panel for the 6×8 inventory grid + 2×2 crafting cluster.
#
# Drag-drop uses Godot 4.6 Control built-ins:
#   _get_drag_data  — emits payload + drag preview (set_drag_preview)
#   _can_drop_data  — accept any dict with "source_slot" key
#   _drop_data      — dispatches MOVE / SWAP / SPLIT / ADD event to Inventory.apply_event
#
# Per RESEARCH.md §"Don't Hand-Roll": do NOT track mouse position manually.
# Godot's drag-drop system handles visual + cancellation automatically.
#
# Right-click (desktop) / long-press (mobile): single-take SPLIT event to cursor slot.
#
# References:
#   03-PLAN-05 Task 1
#   03-UI-SPEC.md §"Inventory cell" (sizing, selected ring, count label)
#   03-PATTERNS.md drag-drop new-territory (lines 696-705)
#   DOCS.md §4.1 — 48-slot grid, hotbar = bottom 8 slots (indices 40-47)

class_name InventorySlot
extends Panel

# ─── Constants ────────────────────────────────────────────────────────────────

## Desktop inventory cell size (UI-SPEC §Spacing).
const CELL_SIZE_DESKTOP_PX: int = 64
## Mobile inventory cell size (UI-SPEC §Spacing).
const CELL_SIZE_MOBILE_PX: int = 56
## Selected ring border width (UI-SPEC §"Accent reserved for" item 6).
const SELECTED_BORDER_PX: int = 2
## Accent yellow (#F5C30D) — selected cell ring + active tab underline.
const COLOR_ACCENT: Color = Color(0.96, 0.76, 0.05, 1.0)
## Brick white (#F1F0EA) — empty cell stroke + count label.
const COLOR_BRICK_WHITE: Color = Color(0.945, 0.941, 0.914, 1.0)
## Navy background (#1B2C56) for filled cells.
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 1.0)
## Brick-blue slot palette (matches the inventory reference): a recessed inset fill with a
## brighter blue bevel border + a soft drop-shadow so each cell reads as embossed.
const COLOR_SLOT_INSET: Color = Color(0.086, 0.137, 0.275, 1.0)       # #162346 — darker than panel
const COLOR_SLOT_INSET_FILLED: Color = Color(0.149, 0.224, 0.408, 1.0) # #263968 — lifted when occupied
const COLOR_SLOT_BEVEL: Color = Color(0.298, 0.435, 0.706, 1.0)        # #4c6fb4 — bright blue rim
const SLOT_CORNER_PX: int = 6
## Long-press threshold in seconds (mobile single-take equivalent of right-click).
const LONG_PRESS_DURATION_S: float = 0.5

# ─── Exported properties ──────────────────────────────────────────────────────

## Slot index within the owning grid (0..47 for inventory; 0..3 for crafting 2x2; -1 = output).
@export var slot_index: int = -1
## Which grid this slot belongs to (determines drag-data source_grid field).
@export var source_grid: String = "inventory"
## True if this slot is in the bottom hotbar row (indices 40-47).
@export var is_hotbar_slot: bool = false

## Optional chest_id when this slot belongs to a chest grid. Set by
## ChestPanel during slot construction so drag/drop events carry the
## owning chest's identifier and Inventory._apply_move can read/write
## the chest's slot array rather than the builder's inventory.
@export var chest_id: String = ""

# ─── Node refs ────────────────────────────────────────────────────────────────

## TextureRect for the item icon (full-rect, 4px inner margin).
var _icon: TextureRect = null
## Count label anchored bottom-right (12px semibold; hidden when count ≤ 1).
var _count_label: Label = null
## Selected ring overlay (NinePatchRect or ColorRect border; hidden by default).
var _selected_ring: Control = null

# ─── Slot state ───────────────────────────────────────────────────────────────

var _def_id: String = ""
var _count: int = 0
var _builder_id: String = ""
var _is_selected: bool = false
## Accumulated touch duration for long-press detection (mobile single-take).
var _touch_hold_time: float = 0.0
var _touch_held: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Build child nodes programmatically (avoids .tscn complexity for 48 dynamic slots).
	_build_icon()
	_build_count_label()
	_build_selected_ring()
	_apply_empty_style()

	# Ensure drag-drop receives mouse/touch input.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Group membership for batch queries.
	add_to_group("inventory_slot")


func _build_icon() -> void:
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 4 px inner margin.
	_icon.offset_left = 4.0
	_icon.offset_top = 4.0
	_icon.offset_right = -4.0
	_icon.offset_bottom = -4.0
	add_child(_icon)


func _build_count_label() -> void:
	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_count_label.offset_left = 2.0
	_count_label.offset_top = 2.0
	_count_label.offset_right = -2.0
	_count_label.offset_bottom = -2.0
	_count_label.text = ""
	add_child(_count_label)


func _build_selected_ring() -> void:
	# ColorRect acting as a border overlay for the selected state.
	# We use a StyleBoxFlat to draw a 2px yellow ring without filling the interior.
	_selected_ring = ColorRect.new()
	_selected_ring.name = "SelectedRing"
	_selected_ring.color = Color(0, 0, 0, 0)  # transparent fill; border via StyleBoxFlat
	_selected_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selected_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_ring.visible = false
	add_child(_selected_ring)


## Beveled blue cell — a recessed inset fill, a 2px bright-blue rim, rounded corners and a
## soft inner shadow so the cell reads as embossed (matches the brick-blue inventory look).
## `filled` lifts the fill colour so occupied cells stand out from empty ones.
func _slot_stylebox(filled: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_SLOT_INSET_FILLED if filled else COLOR_SLOT_INSET
	style.set_border_width_all(2)
	style.border_color = COLOR_SLOT_BEVEL
	style.set_corner_radius_all(SLOT_CORNER_PX)
	style.anti_aliasing = true
	# Soft inset shadow: dark, slightly offset, so the cell looks punched into the panel.
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 1)
	return style


func _apply_empty_style() -> void:
	add_theme_stylebox_override("panel", _slot_stylebox(false))


func _apply_filled_style() -> void:
	add_theme_stylebox_override("panel", _slot_stylebox(true))

# ─── Public API ───────────────────────────────────────────────────────────────

## Set or clear the slot content. Triggers icon + count label update.
## @param def_id      Item/brick definition ID or "" for empty.
## @param count       Stack count (0 = empty).
## @param builder_id  Builder UUID owning this inventory.
func set_content(def_id: String, count: int, builder_id: String) -> void:
	_def_id = def_id
	_count = count
	_builder_id = builder_id

	if def_id == "" or count == 0:
		_icon.texture = null
		_count_label.text = ""
		# Also hide the placeholder text — without this, a slot that previously
		# held an item without an icon (e.g. pickaxe/shovel/lantern) keeps
		# rendering "Picka"/"Shove"/"Lante" after the item is moved out.
		if _placeholder_label != null:
			_placeholder_label.visible = false
		_apply_empty_style()
		tooltip_text = ""
	else:
		# Attempt to resolve an icon from BrickRegistry.
		var icon_tex: Texture2D = _resolve_icon(def_id)
		_icon.texture = icon_tex
		# Always show the count (UAT feedback — without the icon AND without a
		# count of 1, the slot looked empty even when full). Player-facing
		# count is min 1, so '1x' is always meaningful.
		_count_label.text = str(count)
		# Fallback name overlay when no icon resource resolved — surface the
		# first 3 letters of the item name so the slot isn't visually blank.
		# Reuses the icon's own area via _placeholder_label (built lazily).
		_apply_placeholder_label(icon_tex == null, def_id)
		_apply_filled_style()
		# Tooltip for screen-reader / mouse hover.
		var row: int = slot_index / 8 + 1
		var col: int = slot_index % 8 + 1
		var item_name: String = _resolve_item_name(def_id)
		tooltip_text = tr("ui.inventory.cell.filled").format({
			"row": str(row), "col": str(col), "item_name": item_name, "count": str(count)})


## Placeholder label rendered over the icon area when no icon Texture2D was
## resolved for the slot's def_id. Shows the first 3-4 characters of the
## display name so the user sees *something* instead of an empty cell.
## Built lazily on first need.
var _placeholder_label: Label = null

func _apply_placeholder_label(needs_label: bool, def_id_for_label: String) -> void:
	if not needs_label:
		if _placeholder_label != null:
			_placeholder_label.visible = false
		return
	if _placeholder_label == null:
		_placeholder_label = Label.new()
		_placeholder_label.name = "PlaceholderLabel"
		_placeholder_label.add_theme_font_size_override("font_size", 11)
		_placeholder_label.add_theme_color_override("font_color", COLOR_BRICK_WHITE)
		_placeholder_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		_placeholder_label.add_theme_constant_override("outline_size", 2)
		_placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_placeholder_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_placeholder_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_placeholder_label)
	# Pull the localized display name if available; fall back to the raw id.
	var name_key: String = "bricks." + def_id_for_label + ".name"
	var resolved: String = tr(name_key)
	var label_text: String = def_id_for_label if resolved == name_key else resolved
	# 5 chars max to fit the cell without overflowing the count label.
	if label_text.length() > 5:
		label_text = label_text.substr(0, 5)
	_placeholder_label.text = label_text
	_placeholder_label.visible = true


## Show or hide the yellow selected ring.
func set_selected(selected: bool) -> void:
	_is_selected = selected
	_selected_ring.visible = selected
	if selected:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_width_left = SELECTED_BORDER_PX
		style.border_width_top = SELECTED_BORDER_PX
		style.border_width_right = SELECTED_BORDER_PX
		style.border_width_bottom = SELECTED_BORDER_PX
		style.border_color = COLOR_ACCENT
		add_theme_stylebox_override("panel", style)
	else:
		if _count > 0:
			_apply_filled_style()
		else:
			_apply_empty_style()


## Return a snapshot of this slot's content (used by drag-data builder and tests).
func get_content() -> Dictionary:
	return {"def_id": _def_id, "count": _count, "slot_index": slot_index, "source_grid": source_grid}

# ─── Drag-drop (Godot 4.6 Control built-ins — NOT hand-rolled) ───────────────

## Called by Godot when a drag begins on this Control.
## Returns the drag payload dict, or null to cancel.
func _get_drag_data(_at_position: Vector2) -> Variant:
	if _count == 0 or _def_id == "":
		return null

	# Build canonical DragData payload (shape fixed in 03-05 for forward-compat).
	var payload: Dictionary = {
		"source_slot": slot_index,
		"source_grid": source_grid,
		"source_chest_id": chest_id,
		"def_id": _def_id,
		"count": _count,
		"builder_id": _builder_id,
	}

	# Visual drag preview: a semi-transparent icon scaled to 85%.
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	preview.custom_minimum_size = Vector2(
		custom_minimum_size.x * 0.85 if custom_minimum_size.x > 0 else CELL_SIZE_DESKTOP_PX * 0.85,
		custom_minimum_size.y * 0.85 if custom_minimum_size.y > 0 else CELL_SIZE_DESKTOP_PX * 0.85
	)
	preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.7)
	set_drag_preview(preview)

	return payload


## Called by Godot to query whether this slot can accept a drop.
## Accepts any Dictionary containing "source_slot" — Inventory.apply_event validates further.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if not data.has("source_slot"):
		return false
	return true


## Called by Godot when a drag payload is dropped onto this slot.
## Determines MOVE / SWAP / SPLIT / ADD kind and dispatches to Inventory.apply_event.
func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary or not data.has("source_slot"):
		return

	var kind: String
	# CTRL (not SHIFT) is the SPLIT modifier — Shift is now the chest/workbench
	# interact key, and players naturally hold it while dragging, so every drop
	# was being interpreted as SPLIT instead of MOVE.
	if Input.is_key_pressed(KEY_CTRL):
		kind = "SPLIT"
	elif _count > 0 and _def_id == data.get("def_id", ""):
		# Same def_id in target: merge stacks.
		kind = "ADD"
	elif _count > 0:
		# Different item in target: swap.
		kind = "SWAP"
	else:
		# Empty target: move.
		kind = "MOVE"

	var event: Dictionary = {
		"kind": kind,
		"builder_id": data.get("builder_id", _builder_id),
		"from_slot": data.get("source_slot", -1),
		"to_slot": slot_index,
		"from_grid": data.get("source_grid", "inventory"),
		"to_grid": source_grid,
		"from_chest_id": data.get("source_chest_id", ""),
		"to_chest_id": chest_id,
	}

	Inventory.apply_event(event)

# ─── Right-click / long-press single-take ─────────────────────────────────────

## Handle right-click (desktop single-take) and initiate long-press tracking (mobile).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _count > 0:
			# Right-click: take exactly 1 item (SPLIT with single_take=true).
			_emit_single_take()

	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _count > 0:
			_touch_held = true
			_touch_hold_time = 0.0
		else:
			_touch_held = false
			_touch_hold_time = 0.0


## Accumulate long-press time on mobile (LONG_PRESS_DURATION_S threshold).
func _process(delta: float) -> void:
	if _touch_held and _count > 0:
		_touch_hold_time += delta
		if _touch_hold_time >= LONG_PRESS_DURATION_S:
			_touch_held = false
			_touch_hold_time = 0.0
			_emit_single_take()


## Dispatch SPLIT event with single_take=true.
## Plan 03-02's _apply_split handler treats single_take=true as "take 1, leave count-1".
## When to=-1 the receiver is the cursor-floating slot in Inventory state.
## NOTE: If Plan 03-02 did not ship a _floating_slot, items fall back to source slot.
func _emit_single_take() -> void:
	Inventory.apply_event({
		"kind": "SINGLE_TAKE",
		"builder_id": _builder_id,
		"from": slot_index,
		"to": -1,
		"from_grid": source_grid,
		"from_chest_id": chest_id,
		"single_take": true,
	})

# ─── Tooltip ─────────────────────────────────────────────────────────────────

## Override tooltip for screen-reader accessibility.
func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COLOR_BRICK_WHITE)

	if _count == 0 or _def_id == "":
		var row: int = slot_index / 8 + 1 if slot_index >= 0 else 0
		var col: int = slot_index % 8 + 1 if slot_index >= 0 else 0
		label.text = tr("ui.inventory.cell.empty").format({"row": str(row), "col": str(col)})
	else:
		var row: int = slot_index / 8 + 1 if slot_index >= 0 else 0
		var col: int = slot_index % 8 + 1 if slot_index >= 0 else 0
		var item_name: String = _resolve_item_name(_def_id)
		label.text = tr("ui.inventory.cell.filled").format({
			"row": str(row), "col": str(col),
			"item_name": item_name,
			"count": str(_count),
		})

	panel.add_child(label)
	return panel

# ─── Private helpers ──────────────────────────────────────────────────────────

## Resolve a Texture2D for a given def_id.
## Tries BrickRegistry first; falls back to a placeholder ColorRect-style null.
func _resolve_icon(def_id: String) -> Texture2D:
	var def: Resource = BrickRegistry.get_definition(def_id) if BrickRegistry != null else null
	# Primary path: the def's own icon_path field (BrickDefinition / ToolDefinition). This was
	# the missing piece — the old code looked for a non-existent "icon_texture" property and
	# never read icon_path, so every brick/tool slot rendered blank (only the hardcoded
	# food/key/strawberry fallback below showed). Now any item with a valid icon_path resolves.
	if def != null:
		var ip_v: Variant = def.get("icon_path")
		var ip: String = str(ip_v) if ip_v != null else ""
		if not ip.is_empty() and ResourceLoader.exists(ip, "Texture2D"):
			return load(ip) as Texture2D

	# Fallback for items whose def lacks an icon_path (legacy keys/food/strawberry map).
	var fallback_path: String = _item_id_to_icon_path(def_id)
	if ResourceLoader.exists(fallback_path, "Texture2D"):
		return load(fallback_path) as Texture2D

	return null


## Map a non-brick item_id to an icon path in assets/textures/icons/.
## Plans 03-06 (keys) and 03-09 (food/strawberry) will ship the actual .png assets.
func _item_id_to_icon_path(item_id: String) -> String:
	var base: String = "res://assets/textures/icons/"
	if item_id.begins_with("key_"):
		return base + item_id + ".png"
	if item_id.begins_with("food_"):
		return base + item_id + ".png"
	if item_id == "strawberry":
		return base + "strawberry.png"
	# Generic fallback path (may not exist yet).
	return base + item_id + ".png"


## Resolve a localised item name for display in tooltips and count labels.
func _resolve_item_name(def_id: String) -> String:
	# Try brick display name key first.
	var def: Resource = BrickRegistry.get_definition(def_id) if BrickRegistry != null else null
	if def != null and def.get("display_name_key") != null:
		return tr(def.get("display_name_key") as String)
	# Try items.{def_id}.name i18n key.
	var i18n_key: String = "items." + def_id + ".name"
	var translated: String = tr(i18n_key)
	if translated != i18n_key:
		return translated
	# Last resort: return the raw def_id.
	return def_id
