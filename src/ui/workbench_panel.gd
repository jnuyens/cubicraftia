# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# workbench_panel.gd — WorkbenchPanel sub-controller for the inventory slide-in workbench mode.
#
# Renders two stacked grids inside the slide-in (03-CONTEXT.md D-06 + UI-SPEC §"Workbench panel"):
#   1. Workbench 3×3 crafting grid — 9 input slots, each 64×64 px.
#   2. Craft arrow (right-pointing) + output slot — shows the recipe result.
#   3. Separator.
#   4. Builder inventory grid — the standard 6×8 below.
#
# Grid state is read from Inventory._floating_crafting_grid["crafting_3x3"] on every
# inventory_changed signal (T-03-07b-UI-02: no local writes to _grid_state without prior
# apply_event dispatch).
#
# Recipe matching uses Inventory.match_recipe(_grid_state, false) — shaped lookup first,
# then shapeless — delegating to the RecipeRegistry loaded in Plan 03-07a.
#
# Lifecycle:
#   - Instantiated once by InventorySlideIn.open_workbench_mode(); reused on subsequent opens
#     (hidden/shown per T-03-07b-UI-03).
#   - open_for_workbench() configures + subscribes.
#   - close() hides; slide-in calls queue_free only when itself is freed.
#
# References:
#   03-CONTEXT.md D-06 — 3×3 grid layout + craft arrow + output slot
#   03-UI-SPEC.md L70 — workbench cell size 64 px
#   03-PATTERNS.md L932 — ChestPanel as structural analog
#   DOCS.md §4.5 — workbench enables 3×3 crafting recipes

class_name WorkbenchPanel
extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

## 3×3 grid dimensions.
const GRID_SIZE: int = 3

## Workbench crafting cell size in pixels (UI-SPEC L70 "the workbench is the 'real' crafting surface").
const CELL_SIZE: int = 64

## Gap between cells in pixels (UI-SPEC §Spacing token "sm" = 8 px).
const CELL_GAP: int = 8

## Builder inventory row/col counts.
const BUILDER_ROWS: int = 6
const BUILDER_COLS: int = 8

# ─── Preloads ─────────────────────────────────────────────────────────────────

const _InventorySlotScene := preload("res://src/ui/inventory_slot.tscn")

# ─── Node refs (built programmatically in _build_layout) ─────────────────────

## 3×3 crafting grid container.
var _workbench_grid: GridContainer = null

## Output slot (shows the recipe result).
var _output_slot: InventorySlot = null

## Builder inventory grid.
var _builder_grid: GridContainer = null

## Craft arrow label/icon between grid and output.
var _craft_arrow: Label = null

# ─── State ────────────────────────────────────────────────────────────────────

var _workbench_id: String = ""
var _builder_id: String = ""

## 9-entry array of {def_id: String, count: int} dicts (crafting_3x3 grid state).
var _grid_state: Array = []

## InventorySlot nodes for the 3×3 grid.
var _crafting_slots: Array = []

## InventorySlot nodes for the builder grid.
var _builder_slots_nodes: Array = []

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_layout()
	add_to_group("workbench_panel")


## Build the full panel layout programmatically (mirrors ChestPanel._build_layout).
func _build_layout() -> void:
	# Root VBoxContainer.
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", CELL_GAP)
	add_child(vbox)

	# ── 3×3 workbench crafting grid ──────────────────────────────────────────
	_workbench_grid = GridContainer.new()
	_workbench_grid.name = "WorkbenchGrid"
	_workbench_grid.columns = GRID_SIZE
	_workbench_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_workbench_grid.add_theme_constant_override("v_separation", CELL_GAP)
	vbox.add_child(_workbench_grid)

	# ── Craft row: arrow + output slot ───────────────────────────────────────
	var craft_row := HBoxContainer.new()
	craft_row.name = "CraftRow"
	craft_row.alignment = BoxContainer.ALIGNMENT_CENTER
	craft_row.add_theme_constant_override("separation", CELL_GAP)
	vbox.add_child(craft_row)

	_craft_arrow = Label.new()
	_craft_arrow.name = "CraftArrow"
	_craft_arrow.text = "→"
	_craft_arrow.add_theme_font_size_override("font_size", 24)
	craft_row.add_child(_craft_arrow)

	_output_slot = _InventorySlotScene.instantiate() as InventorySlot
	_output_slot.name = "OutputSlot"
	_output_slot.slot_index = -1
	_output_slot.source_grid = "crafting_3x3_output"
	_output_slot.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	craft_row.add_child(_output_slot)

	# ── Separator ────────────────────────────────────────────────────────────
	var sep := HSeparator.new()
	sep.name = "Separator"
	vbox.add_child(sep)

	# ── Builder inventory grid ────────────────────────────────────────────────
	_builder_grid = GridContainer.new()
	_builder_grid.name = "BuilderGrid"
	_builder_grid.columns = BUILDER_COLS
	_builder_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_builder_grid.add_theme_constant_override("v_separation", CELL_GAP)
	vbox.add_child(_builder_grid)

# ─── Public API ───────────────────────────────────────────────────────────────

## Configure and populate this panel for the given workbench.
## Called by InventorySlideIn.open_workbench_mode after creating this panel.
##
## @param workbench_id  Stable workbench identifier (UI-routing token).
## @param builder_id    Builder UUID owning this inventory.
func open_for_workbench(workbench_id: String, builder_id: String = "") -> void:
	_workbench_id = workbench_id
	_builder_id = builder_id

	# Initialise or reuse the 3×3 crafting slots.
	_crafting_slots.clear()
	for child in _workbench_grid.get_children():
		child.queue_free()

	for i: int in range(GRID_SIZE * GRID_SIZE):
		var slot: InventorySlot = _InventorySlotScene.instantiate() as InventorySlot
		slot.slot_index = i
		slot.source_grid = "crafting_3x3"
		slot.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		_workbench_grid.add_child(slot)
		_crafting_slots.append(slot)

	# Populate builder slots.
	_builder_slots_nodes.clear()
	for child in _builder_grid.get_children():
		child.queue_free()

	for i: int in range(BUILDER_ROWS * BUILDER_COLS):
		var slot: InventorySlot = _InventorySlotScene.instantiate() as InventorySlot
		slot.slot_index = i
		slot.source_grid = "inventory"
		slot.is_hotbar_slot = (i >= 40)
		slot.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		_builder_grid.add_child(slot)
		_builder_slots_nodes.append(slot)

	# Sync grid state from Inventory.
	_sync_grid_state()
	_refresh_slots()
	_refresh_output()

	# Subscribe to Inventory signals (guard against double-connect on reuse).
	if not Inventory.inventory_changed.is_connected(_on_inventory_changed):
		Inventory.inventory_changed.connect(_on_inventory_changed)


## Refresh all slots from the current Inventory state.
func _refresh_slots() -> void:
	# Update crafting grid slots from _floating_crafting_grid.
	for i: int in range(_crafting_slots.size()):
		var slot: InventorySlot = _crafting_slots[i] as InventorySlot
		if i < _grid_state.size():
			var entry: Dictionary = _grid_state[i]
			slot.set_content(entry.get("def_id", ""), entry.get("count", 0), _builder_id)
		else:
			slot.set_content("", 0, _builder_id)

	# Update builder inventory slots.
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


## Refresh the output slot by matching the current 3×3 grid against recipes.
## T-03-07b-UI-02: grid state is read from Inventory, never written locally.
func _refresh_output() -> void:
	if _output_slot == null:
		return
	if Inventory == null or not Inventory.has_method("match_recipe"):
		_output_slot.set_content("", 0, _builder_id)
		return

	# Try shaped match first, then shapeless.
	var recipe: Resource = Inventory.match_recipe(_grid_state, false)
	if recipe == null:
		recipe = Inventory.match_recipe(_grid_state, true)

	if recipe != null and recipe.get("output_def_id") != null:
		_output_slot.set_content(
			recipe.get("output_def_id") as String,
			recipe.get("output_count") as int,
			_builder_id
		)
	else:
		_output_slot.set_content("", 0, _builder_id)


## Sync _grid_state from Inventory._floating_crafting_grid["crafting_3x3"].
func _sync_grid_state() -> void:
	if Inventory == null:
		# Initialise to empty 9-slot array.
		_grid_state.resize(GRID_SIZE * GRID_SIZE)
		for i: int in range(_grid_state.size()):
			_grid_state[i] = {"def_id": "", "count": 0}
		return

	var floating: Dictionary = {}
	if "_floating_crafting_grid" in Inventory:
		floating = Inventory._floating_crafting_grid
	var grid_buf: Array = floating.get("crafting_3x3", [])

	if grid_buf.size() == GRID_SIZE * GRID_SIZE:
		_grid_state = grid_buf.duplicate(true)
	else:
		# Buffer not yet populated — use empty grid.
		_grid_state.resize(GRID_SIZE * GRID_SIZE)
		for i: int in range(_grid_state.size()):
			_grid_state[i] = {"def_id": "", "count": 0}


## Called when the builder takes the output slot item (clicks it to craft).
## Submits a CRAFT event for the matched recipe (grid_size=3).
func _on_output_slot_taken() -> void:
	if _builder_id.is_empty() or Inventory == null:
		return
	var recipe: Resource = Inventory.match_recipe(_grid_state, false)
	if recipe == null:
		recipe = Inventory.match_recipe(_grid_state, true)
	if recipe == null:
		return
	Inventory.apply_event({
		"kind":       "CRAFT",
		"builder_id": _builder_id,
		"recipe_id":  recipe.get("recipe_id") as String,
		"grid_inputs": _grid_state,
		"grid_size":  3,
	})


## Close this panel (hide; do not free — reused for T-03-07b-UI-03).
func close() -> void:
	if Inventory != null and Inventory.inventory_changed.is_connected(_on_inventory_changed):
		Inventory.inventory_changed.disconnect(_on_inventory_changed)
	visible = false

# ─── Signal handlers ──────────────────────────────────────────────────────────

## Redraws all slots and output whenever Inventory state changes.
func _on_inventory_changed(builder_id: String) -> void:
	if builder_id != _builder_id and not builder_id.is_empty():
		return  # Phase 4 multi-builder readiness: ignore other builders' changes.
	_sync_grid_state()
	_refresh_slots()
	_refresh_output()
