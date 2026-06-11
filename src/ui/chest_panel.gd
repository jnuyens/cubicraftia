# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# chest_panel.gd — ChestPanel sub-controller for the inventory slide-in chest mode.
#
# Renders two stacked grids inside the slide-in (03-CONTEXT.md D-02 + UI-SPEC §"Chest panel"):
#   1. Key slot (optional, visible only when chest is locked) — a single 64×64 slot above
#      the chest grid that accepts only matching-tier keys. Drop dispatches UNLOCK event.
#   2. Chest grid — sized per tier (regular/bronze=6×8, silver=6×9, gold=6×10, diamond=6×12).
#      For double-chest: columns doubled (e.g. double regular = 6×16).
#   3. Builder grid — the standard 6×8 below; shift-drag moves items between the two grids.
#
# Lifecycle:
#   - Instantiated by InventorySlideIn.open_chest_mode(); open_for_chest() configures it.
#   - Subscribes to Inventory.inventory_changed + Inventory.chest_unlocked.
#   - Destroyed by close() (queue_free).
#
# Key slot drop logic:
#   The key slot is a special-purpose InventorySlot with source_grid="key_slot". When a drag
#   from "inventory" with a def_id starting "key_" is dropped onto it, ChestPanel intercepts
#   the _drop_data and dispatches UNLOCK rather than MOVE/SWAP.
#
# References:
#   03-CONTEXT.md D-02 — chest UI two stacked grids + key slot
#   03-UI-SPEC.md L71 — chest grid cell sizing per tier
#   03-UI-SPEC.md L75 — key slot 64×64 centred above chest grid + lock-plate 32×32
#   03-UI-SPEC.md L267-270 — key drop is the commit moment; no confirmation dialog
#   03-PATTERNS.md L932 — ChestPanel sub-controller analog: brick_palette.gd layout
#   DOCS.md §4.4 — slot counts per tier; double-chest combined slot count

class_name ChestPanel
extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

## Slot counts per tier (DOCS §4.4).
const SLOT_COUNTS: Dictionary = {
	"regular": 48,
	"bronze":  48,
	"silver":  54,
	"gold":    60,
	"diamond": 72,
}

## Grid columns per tier per UI-SPEC L71.
## regular/bronze = 8 cols × 6 rows = 48; silver = 9×6 = 54; gold = 10×6 = 60; diamond = 12×6 = 72.
const GRID_COLUMNS: Dictionary = {
	"regular": 8,
	"bronze":  8,
	"silver":  9,
	"gold":    10,
	"diamond": 12,
}

## Desktop cell size in pixels (UI-SPEC §Spacing).
const CELL_SIZE_DESKTOP: int = 64

## Mobile cell size in pixels (UI-SPEC L71).
const CELL_SIZE_MOBILE: int = 56

## Gap between cells.
const CELL_GAP: int = 8

## Key slot size in pixels (UI-SPEC L75).
const KEY_SLOT_SIZE: int = 64

## Builder inventory row count (standard 6×8 = 48 slots).
const BUILDER_ROWS: int = 6
const BUILDER_COLS: int = 8

# ─── Preloads ─────────────────────────────────────────────────────────────────

const _InventorySlotScene := preload("res://src/ui/inventory_slot.tscn")

# ─── Node refs ────────────────────────────────────────────────────────────────

## Container wrapping the key slot (HBox with LockPlateIcon + KeySlot).
var _chest_title: Label = null
var _key_slot_container: HBoxContainer = null

## The actual key slot (InventorySlot with source_grid="key_slot").
var _key_slot: InventorySlot = null

## Chest contents grid (GridContainer — top half).
var _chest_grid: GridContainer = null

## Builder inventory grid (GridContainer — bottom half).
var _builder_grid: GridContainer = null

# ─── State ────────────────────────────────────────────────────────────────────

var _chest_id: String = ""
var _tier: String = "regular"
var _locked: bool = false
var _double_partner_chunk: Vector3i = Vector3i.ZERO
var _has_partner: bool = false
var _builder_id: String = ""
var _chest_slots: Array = []
var _builder_slots_nodes: Array = []

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# The ChestPanel is added to the slide-in's MainContent programmatically
	# (chest_panel_script.new() returns a 0×0 Control). Anchor it to fill its
	# parent so the VBox + grids inside actually have space to lay out —
	# without this, _build_layout populates children inside a 0×0 box and
	# nothing renders, which made the chest panel invisible during UAT.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_layout()
	add_to_group("chest_panel")


## Build the full panel layout programmatically.
func _build_layout() -> void:
	# Root VBoxContainer.
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", CELL_GAP)
	add_child(vbox)

	# ── Chest title (UAT feedback: chest grid was visually indistinguishable
	# from inventory grid; explicit "Chest (tier)" label makes the mode obvious).
	_chest_title = Label.new()
	_chest_title.name = "ChestTitle"
	_chest_title.text = tr("ui.chest.title")  # populated with tier in open_for_chest
	_chest_title.add_theme_font_size_override("font_size", 18)
	_chest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_chest_title)

	# ── Key slot row (hidden until chest is locked) ──────────────────────────
	_key_slot_container = HBoxContainer.new()
	_key_slot_container.name = "KeySlotContainer"
	_key_slot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_key_slot_container.visible = false
	vbox.add_child(_key_slot_container)

	# Lock plate icon label (text key "ui.chest.key_slot_label").
	var label := Label.new()
	label.name = "KeySlotLabel"
	label.text = tr("ui.chest.key_slot_label")
	label.add_theme_font_size_override("font_size", 12)
	_key_slot_container.add_child(label)

	# Actual key slot.
	_key_slot = _InventorySlotScene.instantiate() as InventorySlot
	_key_slot.name = "KeySlot"
	_key_slot.slot_index = -2  # Sentinel index for key slot.
	_key_slot.source_grid = "key_slot"
	_key_slot.custom_minimum_size = Vector2(KEY_SLOT_SIZE, KEY_SLOT_SIZE)
	_key_slot_container.add_child(_key_slot)

	# ── Chest grid ───────────────────────────────────────────────────────────
	_chest_grid = GridContainer.new()
	_chest_grid.name = "ChestGrid"
	_chest_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_chest_grid.add_theme_constant_override("v_separation", CELL_GAP)
	vbox.add_child(_chest_grid)

	# ── Divider label + separator (UAT feedback: the HSeparator alone was
	# invisible against the slide-in's dark background, so users couldn't tell
	# where the chest grid ended and their own inventory began).
	var divider_label := Label.new()
	divider_label.name = "DividerLabel"
	divider_label.text = tr("ui.chest.your_inventory")
	divider_label.add_theme_font_size_override("font_size", 13)
	divider_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 0.9))
	divider_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(divider_label)
	var sep := HSeparator.new()
	sep.name = "Separator"
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# ── Builder grid ─────────────────────────────────────────────────────────
	_builder_grid = GridContainer.new()
	_builder_grid.name = "BuilderGrid"
	_builder_grid.columns = BUILDER_COLS
	_builder_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_builder_grid.add_theme_constant_override("v_separation", CELL_GAP)
	vbox.add_child(_builder_grid)


# ─── Public API ───────────────────────────────────────────────────────────────

## Configure and populate this panel for the given chest.
## Called by InventorySlideIn.open_chest_mode after instantiating ChestPanel.
##
## @param chest_id      Stable chest identifier.
## @param tier          Chest tier string.
## @param locked        Whether the chest is currently locked.
## @param partner_chunk Vector3i.ZERO for a single chest; partner coord for double-chest.
## @param builder_id    Builder UUID owning this inventory.
func open_for_chest(chest_id: String, tier: String, locked: bool,
					partner_chunk: Vector3i, builder_id: String = "") -> void:
	_chest_id = chest_id
	_tier = tier
	_locked = locked
	_double_partner_chunk = partner_chunk
	_has_partner = partner_chunk != Vector3i.ZERO
	_builder_id = builder_id

	# Update the chest title with the tier name (UAT feedback: visual distinction
	# between chest grid and inventory grid). Falls back to tier-cased string if
	# the localized key is missing.
	if _chest_title != null:
		var tier_key: String = "ui.chest.tier." + tier
		var tier_display: String = tr(tier_key)
		if tier_display == tier_key:
			tier_display = tier.capitalize()
		_chest_title.text = tier_display + " " + tr("ui.chest.title_suffix")

	# Configure chest grid dimensions.
	var base_cols: int = GRID_COLUMNS.get(tier, 8)
	var base_slots: int = SLOT_COUNTS.get(tier, 48)
	var total_cols: int = base_cols * 2 if _has_partner else base_cols
	var total_slots: int = base_slots * 2 if _has_partner else base_slots

	_chest_grid.columns = total_cols

	# Populate chest slots.
	_chest_slots.clear()
	for child in _chest_grid.get_children():
		child.queue_free()

	for i: int in range(total_slots):
		var slot: InventorySlot = _InventorySlotScene.instantiate() as InventorySlot
		slot.slot_index = i
		slot.source_grid = "chest"
		slot.chest_id = _chest_id
		slot.custom_minimum_size = Vector2(CELL_SIZE_DESKTOP, CELL_SIZE_DESKTOP)
		_chest_grid.add_child(slot)
		_chest_slots.append(slot)

	# Populate builder slots.
	_builder_slots_nodes.clear()
	for child in _builder_grid.get_children():
		child.queue_free()

	for i: int in range(BUILDER_ROWS * BUILDER_COLS):
		var slot: InventorySlot = _InventorySlotScene.instantiate() as InventorySlot
		slot.slot_index = i
		slot.source_grid = "inventory"
		slot.is_hotbar_slot = (i >= 40)
		slot.custom_minimum_size = Vector2(CELL_SIZE_DESKTOP, CELL_SIZE_DESKTOP)
		_builder_grid.add_child(slot)
		_builder_slots_nodes.append(slot)

	# Show/hide key slot.
	_key_slot_container.visible = locked
	if locked:
		_key_slot.set_content("", 0, _builder_id)

	# Populate slot contents.
	_refresh_slots()

	# Subscribe to Inventory signals.
	if not Inventory.inventory_changed.is_connected(_on_inventory_changed):
		Inventory.inventory_changed.connect(_on_inventory_changed)
	if not Inventory.chest_unlocked.is_connected(_on_chest_unlocked):
		Inventory.chest_unlocked.connect(_on_chest_unlocked)


## Refresh all chest + builder slot contents from Inventory state.
func _refresh_slots() -> void:
	# Chest contents.
	var chest_coord: Vector3i = _chunk_from_id(_chest_id)
	var chest_contents: Array = Inventory.get_chest_contents(chest_coord)

	if _has_partner:
		var partner_contents: Array = Inventory.get_chest_contents(_double_partner_chunk)
		chest_contents = chest_contents + partner_contents

	for i: int in range(_chest_slots.size()):
		var slot: InventorySlot = _chest_slots[i] as InventorySlot
		if i < chest_contents.size():
			var entry: Dictionary = chest_contents[i]
			slot.set_content(entry.get("def_id", ""), entry.get("count", 0), _builder_id)
		else:
			slot.set_content("", 0, _builder_id)

	# Builder contents.
	if _builder_id.is_empty():
		return

	var builder_slots: Array = Inventory.get_slots(_builder_id)
	for i: int in range(_builder_slots_nodes.size()):
		var slot: InventorySlot = _builder_slots_nodes[i] as InventorySlot
		if i < builder_slots.size():
			var entry: Dictionary = builder_slots[i]
			slot.set_content(entry.get("def_id", ""), entry.get("count", 0), _builder_id)
		else:
			slot.set_content("", 0, _builder_id)


## Close and destroy this panel. Disconnects Inventory signals.
func close() -> void:
	if Inventory.inventory_changed.is_connected(_on_inventory_changed):
		Inventory.inventory_changed.disconnect(_on_inventory_changed)
	if Inventory.chest_unlocked.is_connected(_on_chest_unlocked):
		Inventory.chest_unlocked.disconnect(_on_chest_unlocked)
	queue_free()

# ─── Private helpers ──────────────────────────────────────────────────────────

## Parse chest_id string "chest_x_y_z" back into a Vector3i chunk coordinate.
func _chunk_from_id(chest_id: String) -> Vector3i:
	# Format: "chest_%d_%d_%d"
	if not chest_id.begins_with("chest_"):
		return Vector3i.ZERO
	var parts: PackedStringArray = chest_id.trim_prefix("chest_").split("_")
	if parts.size() >= 3:
		return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	return Vector3i.ZERO

# ─── Signal handlers ──────────────────────────────────────────────────────────

## Refresh slot content whenever any inventory mutation fires.
func _on_inventory_changed(builder_id: String) -> void:
	# Refresh on any builder change (Phase 4 will scope this more tightly).
	if builder_id == _builder_id or builder_id.is_empty():
		_refresh_slots()


## Hide the key slot when this chest is unlocked.
func _on_chest_unlocked(chunk_coord: Vector3i) -> void:
	var my_coord: Vector3i = _chunk_from_id(_chest_id)
	if chunk_coord == my_coord:
		_locked = false
		_key_slot_container.visible = false
		_refresh_slots()
