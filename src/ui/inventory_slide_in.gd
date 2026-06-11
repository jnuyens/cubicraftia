# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# inventory_slide_in.gd — Inventory slide-in controller.
#
# Phase 3 hero UI: right-side slide-in (desktop) / bottom-sheet (mobile) hosting the
# 48-slot inventory grid + 2×2 inline crafting + tab header (Inventory / Recipes).
#
# Slide-in chrome is a verbatim port from brick_palette.gd (UI-SPEC §"Identical chrome"
# at L332 + L410). Two scenes share this controller:
#   - inventory_slide_in_sidebar.tscn  (desktop, layout="sidebar")
#   - inventory_slide_in_bottomsheet.tscn (mobile, layout="bottomsheet")
#
# Mutually exclusive with the brick palette (closes palette on open, vice versa).
# Per CONTEXT.md <specifics>: "only one panel open at a time".
#
# Mode-swap stubs:
#   open_chest_mode(chest_id, tier, locked)   — Plan 03-06 implements body
#   open_workbench_mode(workbench_id)          — Plan 03-07b implements body
#
# References:
#   03-PLAN-05 Task 2
#   03-UI-SPEC.md §"Inventory + Chest + Workbench Slide-In Layout Specification" L286-453
#   DOCS.md §4.1 — 6×8 grid, hotbar = bottom 8 slots (indices 40-47)
#   03-CONTEXT.md D-01 (slide-in as primary inventory surface)
#   brick_palette.gd — chrome verbatim reference

class_name InventorySlideIn
extends Control

# ─── Constants ────────────────────────────────────────────────────────────────

## Panel background: #1B2C56 at 0.92α — verbatim from brick_palette.gd.
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 0.92)
## Accent yellow: #F5C30D — tab underline + selected ring.
const COLOR_ACCENT: Color = Color(0.96, 0.76, 0.05, 1.0)
## Brick white: #F1F0EA — secondary text.
const COLOR_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)
## Bottom-sheet ease-out cubic animation duration (UI-SPEC L451 "0.22 s").
const TWEEN_DURATION_S: float = 0.22
## Inventory grid: 8 columns × 6 rows = 48 slots (DOCS §4.1).
## Grid is now 6 cols × 8 rows = 48 slots (was 8 cols × 6 rows). The 8-wide
## variant overflowed the 360 px sidebar and pushed the crafting cluster off
## screen (UAT test 9). 6 wide fits cleanly and stacks crafting cluster below.
const GRID_COLUMNS: int = 6
const GRID_ROWS: int = 8
## Inline 2×2 crafting cluster.
const CRAFTING_GRID_SIZE: int = 2
## Desktop inventory cell size in pixels (UI-SPEC §Spacing).
const CELL_SIZE_DESKTOP: int = 64
## Mobile inventory cell size in pixels.
const CELL_SIZE_MOBILE: int = 56
## 2×2 crafting cluster cell size (same desktop + mobile per UI-SPEC L69).
const CRAFTING_CELL_SIZE: int = 56
## Gap between cells (UI-SPEC §Spacing token "sm" = 8px).
const CELL_GAP: int = 8
## Sidebar width (desktop — UI-SPEC L447 "360 px wide").
const SIDEBAR_WIDTH: int = 360
## Bottom-sheet collapsed peek height in pixels (UI-SPEC §Spacing "2xl" = 48px).
const PEEK_HEIGHT: int = 48

# ─── Exported properties ──────────────────────────────────────────────────────

## Layout mode: "sidebar" (desktop) or "bottomsheet" (mobile).
@export var layout: String = "sidebar"

# ─── Preload ─────────────────────────────────────────────────────────────────

const _InventorySlotScene := preload("res://src/ui/inventory_slot.tscn")

# ─── Node refs (resolved in _ready from scene tree) ──────────────────────────

var _body: PanelContainer = null
var _grid_container: GridContainer = null
var _crafting_container: GridContainer = null
var _crafting_output: InventorySlot = null
var _title_label: Label = null
var _tab_header: HBoxContainer = null
var _tab_inventory: Button = null
var _tab_recipes: Button = null
var _recipes_pane: Control = null
var _drag_handle: Control = null

# ─── Slot arrays ──────────────────────────────────────────────────────────────

## 48 InventorySlot nodes for the main 6×8 grid.
var _inventory_slots: Array = []
## 4 InventorySlot nodes for the 2×2 crafting cluster inputs.
var _crafting_slots: Array = []

# ─── State ────────────────────────────────────────────────────────────────────

var _builder_id: String = ""
var _is_open: bool = false
var _is_expanded: bool = false  # bottom-sheet expanded state
var _expanded_y: float = 0.0
var _collapsed_y: float = 0.0
var _tween: Tween = null
var _drag_start_y: float = -1.0
## Current panel mode: "inventory" | "chest" | "workbench"
var _mode: String = "inventory"
## Active tab: "inventory" | "recipes"
var _active_tab: String = "inventory"
## Crafting grid state (4-slot input buffer; kept in slide-in since crafting is session-local).
var _crafting_grid_state: Array = []
## Active ChestPanel sub-controller instance (null when not in chest mode).
## Duck-typed as Control to avoid class-name resolution ordering issues (headless-preload-pattern).
var _chest_panel_instance: Control = null
## Active WorkbenchPanel sub-controller instance (null when not in workbench mode).
## Reused across opens (T-03-07b-UI-03: constructed once, hidden/shown).
var _workbench_panel_instance: Control = null

# ─── Signals ─────────────────────────────────────────────────────────────────

signal opened()
signal closed()
signal mode_changed(mode: String)

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Resolve scene-tree nodes.
	_resolve_node_refs()

	# Apply panel chrome (verbatim from brick_palette.gd _setup_panel_style).
	_setup_panel_style()

	# Build 48 inventory slots + 4 crafting slots.
	_build_grid()
	_build_crafting()

	# Initialise crafting state buffer.
	_crafting_grid_state.resize(CRAFTING_GRID_SIZE * CRAFTING_GRID_SIZE)
	for i in range(_crafting_grid_state.size()):
		_crafting_grid_state[i] = {"def_id": "", "count": 0}

	# Connect to Builder toggle signal.
	var builder := get_tree().get_first_node_in_group("builder") if is_inside_tree() else null
	if builder != null:
		if "get_stable_builder_id" in builder:
			_builder_id = builder.call("get_stable_builder_id")
		if builder.has_signal("inventory_toggle_requested"):
			builder.inventory_toggle_requested.connect(_on_toggle)

	# Connect to Inventory.inventory_changed.
	if Inventory != null and Inventory.has_signal("inventory_changed"):
		Inventory.inventory_changed.connect(_on_inventory_changed)

	# Tab buttons.
	if _tab_inventory != null:
		_tab_inventory.pressed.connect(_set_active_tab.bind("inventory"))
	if _tab_recipes != null:
		_tab_recipes.pressed.connect(_set_active_tab.bind("recipes"))

	# Bottom-sheet setup.
	if layout == "bottomsheet":
		_setup_bottomsheet_positions()
		if _drag_handle != null:
			_drag_handle.gui_input.connect(_on_drag_handle_input)
		# Start collapsed off-screen.
		position.y = _collapsed_y
		visible = true
	else:
		# Sidebar: start off-screen right.
		visible = false

	# Group for chest/workbench sub-controllers to locate this node.
	add_to_group("inventory_slide_in")

	# Apply initial tab state.
	_set_active_tab("inventory")


func _resolve_node_refs() -> void:
	_body = get_node_or_null("Body") as PanelContainer
	if _body == null:
		return
	_title_label = _body.get_node_or_null("VBox/Title") as Label
	_tab_header = _body.get_node_or_null("VBox/TabHeader") as HBoxContainer
	if _tab_header != null:
		_tab_inventory = _tab_header.get_node_or_null("TabInventory") as Button
		_tab_recipes = _tab_header.get_node_or_null("TabRecipes") as Button
	var main_content: Control = _body.get_node_or_null("VBox/MainContent")
	if main_content != null:
		_grid_container = main_content.get_node_or_null("InventoryGrid") as GridContainer
		var cluster: Control = main_content.get_node_or_null("CraftingCluster")
		if cluster != null:
			_crafting_container = cluster.get_node_or_null("CraftingGrid") as GridContainer
			# CraftingOutput in the .tscn is a Panel — the script needs an
			# InventorySlot so set_content() exists. If the scene gave us a
			# Panel, replace it with a freshly instantiated InventorySlot in
			# the same position (UAT: output preview was permanently empty).
			var raw_output: Node = cluster.get_node_or_null("CraftingOutput")
			_crafting_output = raw_output as InventorySlot
			if _crafting_output == null and raw_output != null:
				var parent: Node = raw_output.get_parent()
				var idx: int = raw_output.get_index()
				var min_size: Vector2 = (raw_output as Control).custom_minimum_size if raw_output is Control else Vector2(56, 56)
				raw_output.queue_free()
				_crafting_output = _InventorySlotScene.instantiate() as InventorySlot
				_crafting_output.name = "CraftingOutput"
				_crafting_output.slot_index = -1
				_crafting_output.source_grid = "crafting_2x2_output"
				_crafting_output.custom_minimum_size = min_size
				parent.add_child(_crafting_output)
				parent.move_child(_crafting_output, idx)
	_recipes_pane = _body.get_node_or_null("VBox/RecipesPane") as Control
	_drag_handle = get_node_or_null("DragHandle") as Control


## Calculate bottom-sheet expanded / collapsed Y positions.
func _setup_bottomsheet_positions() -> void:
	var vp_height := get_viewport_rect().size.y
	# Expanded: ~70% of screen height (UI-SPEC L62).
	_expanded_y = vp_height * 0.30
	# Collapsed: only the peek handle is visible.
	_collapsed_y = vp_height - PEEK_HEIGHT


## Apply the panel StyleBoxFlat — verbatim from brick_palette.gd L121-134.
func _setup_panel_style() -> void:
	if _body == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_NAVY
	if layout == "sidebar":
		style.corner_radius_top_left = 16
		style.corner_radius_bottom_left = 16
		style.corner_radius_top_right = 0
		style.corner_radius_bottom_right = 0
	else:
		style.corner_radius_top_left = 16
		style.corner_radius_top_right = 16
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
	# Beveled bright-blue frame + soft drop shadow so the whole panel reads as a chunky
	# Brick-blue chrome border (matches the inventory reference).
	style.set_border_width_all(3)
	style.border_color = Color(0.298, 0.435, 0.706, 1.0)  # #4c6fb4 bright blue rim
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	style.anti_aliasing = true
	_body.add_theme_stylebox_override("panel", style)


## Populate the 48 InventorySlot nodes in the grid container.
func _build_grid() -> void:
	if _grid_container == null:
		return
	_inventory_slots.clear()
	_grid_container.columns = GRID_COLUMNS
	_grid_container.add_theme_constant_override("h_separation", CELL_GAP)
	_grid_container.add_theme_constant_override("v_separation", CELL_GAP)

	var cell_size: int = CELL_SIZE_MOBILE if layout == "bottomsheet" else CELL_SIZE_DESKTOP
	var total_slots: int = GRID_ROWS * GRID_COLUMNS

	for i in range(total_slots):
		var slot: InventorySlot = _InventorySlotScene.instantiate() as InventorySlot
		slot.slot_index = i
		slot.source_grid = "inventory"
		slot.is_hotbar_slot = (i >= 40)
		slot.custom_minimum_size = Vector2(cell_size, cell_size)
		_grid_container.add_child(slot)
		_inventory_slots.append(slot)


## Populate the 2×2 crafting cluster nodes.
func _build_crafting() -> void:
	if _crafting_container == null:
		return
	_crafting_slots.clear()
	_crafting_container.columns = CRAFTING_GRID_SIZE
	_crafting_container.add_theme_constant_override("h_separation", CELL_GAP)
	_crafting_container.add_theme_constant_override("v_separation", CELL_GAP)

	for i in range(CRAFTING_GRID_SIZE * CRAFTING_GRID_SIZE):
		var slot: InventorySlot = _InventorySlotScene.instantiate() as InventorySlot
		slot.slot_index = i
		slot.source_grid = "crafting_2x2"
		slot.custom_minimum_size = Vector2(CRAFTING_CELL_SIZE, CRAFTING_CELL_SIZE)
		_crafting_container.add_child(slot)
		_crafting_slots.append(slot)

	# The output slot (Plan 03-02 recipe preview).
	if _crafting_output != null:
		_crafting_output.slot_index = -1
		_crafting_output.source_grid = "crafting_2x2_output"
		_crafting_output.custom_minimum_size = Vector2(CRAFTING_CELL_SIZE, CRAFTING_CELL_SIZE)
		# Click / tap the output to CRAFT. Without this the preview was never wired to
		# anything — dragging the output sent an unhandled "crafting_2x2_output" grid and
		# silently failed, so the inline 2×2 grid produced nothing (the plank-craft bug).
		if not _crafting_output.gui_input.is_connected(_on_crafting_output_input):
			_crafting_output.gui_input.connect(_on_crafting_output_input)


## Click/tap the 2×2 output slot to craft the matched recipe (shaped or shapeless).
## Mirrors workbench_panel._on_output_slot_taken. Inventory.inventory_changed then
## refreshes the grid and output preview, and consumes the grid buffer.
func _on_crafting_output_input(event: InputEvent) -> void:
	var is_click: bool = event is InputEventMouseButton \
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
		and (event as InputEventMouseButton).pressed
	var is_tap: bool = event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not (is_click or is_tap):
		return
	if _builder_id.is_empty() or Inventory == null or not Inventory.has_method("match_recipe"):
		return
	var grid: Array = _crafting_grid_state
	if Inventory.has_method("get_crafting_grid"):
		grid = Inventory.get_crafting_grid("crafting_2x2")
	var recipe: Resource = Inventory.match_recipe(grid, false)
	if recipe == null:
		recipe = Inventory.match_recipe(grid, true)
	if recipe == null:
		return
	Inventory.apply_event({
		"kind":        "CRAFT",
		"builder_id":  _builder_id,
		"recipe_id":   recipe.get("recipe_id") as String,
		"grid_inputs": grid,
		"grid_size":   2,
	})
	if is_inside_tree():
		get_viewport().set_input_as_handled()

# ─── Public API ───────────────────────────────────────────────────────────────

## Open the inventory panel. Closes the brick palette first (mutual exclusion).
## Stores the mouse_mode that was active before open() ran, so close() can
## restore it. Auto-release on open + auto-recapture on close avoids the
## user having to Tab manually to free the cursor for slot drag/click.
var _mouse_mode_before_open: int = Input.MOUSE_MODE_CAPTURED


func open() -> void:
	# Close brick palette (T-03-05-UI-04 mitigate — mutual exclusion).
	if is_inside_tree():
		var palette := get_tree().get_first_node_in_group("brick_palette") if get_tree().has_group("brick_palette") else null
		if palette == null:
			# Fallback: search by class name.
			palette = get_tree().get_root().find_child("BrickPaletteSidebar", true, false)
		if palette != null and palette.has_method("close"):
			palette.call("close")

	# Auto-release the mouse cursor so the player can click/drag slots without
	# pressing Tab first. close() restores whichever mode was active before
	# (typically MOUSE_MODE_CAPTURED for FPV gameplay).
	if not _is_open:
		_mouse_mode_before_open = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	visible = true
	if layout == "bottomsheet":
		_animate_to(_expanded_y)
		_is_expanded = true
		_notify_mobile_overlay(true)
	else:
		# Animate sidebar in from the right edge.
		var vp_width: float = get_viewport_rect().size.x
		position.x = vp_width  # Start off-screen right.
		_animate_sidebar_to(vp_width - SIDEBAR_WIDTH)
		_notify_mobile_overlay(true)

	_is_open = true
	_refresh_all_slots()
	emit_signal("opened")


## Close the inventory panel. If in chest/workbench mode, tears down the sub-panel first.
func close() -> void:
	if _mode == "chest" or _mode == "workbench":
		_return_to_inventory_mode()

	if layout == "bottomsheet":
		_animate_to(_collapsed_y)
		_is_expanded = false
		_notify_mobile_overlay(false)
	else:
		# Animate sidebar off-screen right, then hide.
		var vp_width: float = get_viewport_rect().size.x
		_animate_sidebar_to(vp_width, true)
		_notify_mobile_overlay(false)

	_is_open = false
	# Restore the mouse_mode that was active before this open() call —
	# typically MOUSE_MODE_CAPTURED so FPV gameplay resumes immediately.
	Input.mouse_mode = _mouse_mode_before_open
	emit_signal("closed")


## Tear down chest/workbench mode and restore the standard inventory / crafting view.
## Called automatically by close() when _mode == "chest" or "workbench".
func _return_to_inventory_mode() -> void:
	_mode = "inventory"
	if _chest_panel_instance != null:
		if _chest_panel_instance.has_method("close"):
			_chest_panel_instance.call("close")
		else:
			_chest_panel_instance.queue_free()
		_chest_panel_instance = null
	if _workbench_panel_instance != null:
		_workbench_panel_instance.visible = false
		# Note: WorkbenchPanel is reused (T-03-07b-UI-03); we hide rather than free.
	# Restore the slide-in title + tab header that chest/workbench mode hid
	# (UAT feedback — "Inventory" header was redundant alongside the
	# ChestPanel's own "<Tier> Chest" title).
	if _title_label != null:
		_title_label.visible = true
	if _tab_header != null:
		_tab_header.visible = true
	if _grid_container != null:
		_grid_container.visible = (_active_tab == "inventory")
	if _crafting_container != null:
		var cluster_node: Node = _crafting_container.get_parent()
		if cluster_node != null:
			cluster_node.visible = (_active_tab == "inventory")


## Toggle open/close. In chest/workbench mode, toggle only closes when mode is "inventory".
func _on_toggle() -> void:
	if _is_open and _mode == "inventory":
		close()
	else:
		# Tear down any active chest/workbench panel before switching to inventory mode
		# so their signal connections don't leak into the newly-opened inventory (WR-03).
		if _mode != "inventory":
			_return_to_inventory_mode()
		open()


## Open the slide-in in chest mode: chest grid stacked above the builder grid.
## Plan 03-05 shipped this as a stub. Plan 03-06 implements the full body per D-02.
##
## @param chest_id       Stable chest identifier (e.g. "chest_0_0_0").
## @param tier           Chest tier string (regular/bronze/silver/gold/diamond).
## @param locked         Whether the chest is currently locked (shows key slot if true).
## @param partner_chunk  Vector3i.ZERO for single chest; partner coord for double-chest.
func open_chest_mode(chest_id: String, tier: String, locked: bool,
					 partner_chunk: Vector3i = Vector3i.ZERO) -> void:
	_mode = "chest"

	# Hide the standard inventory grid + crafting cluster while in chest mode.
	if _grid_container != null:
		_grid_container.visible = false
	if _crafting_container != null:
		var cluster_node: Node = _crafting_container.get_parent()
		if cluster_node != null:
			cluster_node.visible = false

	# Hide the slide-in's "Inventory" title label AND the Inventory/Recipes
	# tab header in chest mode — neither is meaningful while a chest is open.
	# The ChestPanel renders its own "<Tier> Chest" title at the top.
	# _return_to_inventory_mode restores both.
	if _title_label != null:
		_title_label.visible = false
	if _tab_header != null:
		_tab_header.visible = false

	# Create or reuse the ChestPanel sub-controller (duck-typed per headless-preload-pattern).
	if _chest_panel_instance == null:
		var chest_panel_script: GDScript = preload("res://src/ui/chest_panel.gd")
		_chest_panel_instance = chest_panel_script.new() as Control
		var main_content: Control = null
		if _body != null:
			main_content = _body.get_node_or_null("VBox/MainContent") as Control
		if main_content != null:
			main_content.add_child(_chest_panel_instance)
		else:
			add_child(_chest_panel_instance)

	_chest_panel_instance.visible = true
	if _chest_panel_instance.has_method("open_for_chest"):
		_chest_panel_instance.call("open_for_chest", chest_id, tier, locked, partner_chunk, _builder_id)

	# Ensure the slide-in itself is visible and animated in.
	open()
	emit_signal("mode_changed", _mode)


## Open the slide-in in workbench mode: 3×3 crafting grid replaces the 2×2 inline cluster.
## Plan 03-05 shipped this as a stub. Plan 03-07b implements the full body per D-06.
##
## @param workbench_id  Stable workbench identifier (e.g. "workbench_0_0_0").
##                      This is a UI-routing token only; the crafting grid state lives in
##                      Inventory._floating_crafting_grid (not keyed by workbench_id).
func open_workbench_mode(workbench_id: String) -> void:
	_mode = "workbench"

	# Tear down any active chest panel (single open-thing mental model).
	if _chest_panel_instance != null:
		if _chest_panel_instance.has_method("close"):
			_chest_panel_instance.call("close")
		else:
			_chest_panel_instance.queue_free()
		_chest_panel_instance = null

	# Create or reuse the WorkbenchPanel (T-03-07b-UI-03: construct once, hide/show).
	if _workbench_panel_instance == null:
		var workbench_panel_script: GDScript = preload("res://src/ui/workbench_panel.gd")
		_workbench_panel_instance = workbench_panel_script.new() as Control
		var main_content: Control = null
		if _body != null:
			main_content = _body.get_node_or_null("VBox/MainContent") as Control
		if main_content != null:
			main_content.add_child(_workbench_panel_instance)
		else:
			add_child(_workbench_panel_instance)

	# Hide standard 2×2 crafting cluster — workbench provides the 3×3 grid instead.
	if _grid_container != null:
		_grid_container.visible = false
	if _crafting_container != null:
		var cluster_node: Node = _crafting_container.get_parent()
		if cluster_node != null:
			cluster_node.visible = false

	_workbench_panel_instance.visible = true
	if _workbench_panel_instance.has_method("open_for_workbench"):
		_workbench_panel_instance.call("open_for_workbench", workbench_id, _builder_id)

	# Build the recipes pane if not yet built (lazy init per _set_active_tab pattern).
	_build_recipes_pane()

	# Ensure the slide-in itself is visible and animated in.
	open()
	emit_signal("mode_changed", _mode)


## Refresh all 48 inventory slots from the Inventory autoload.
func _refresh_all_slots() -> void:
	if _builder_id == "":
		return
	var slots: Array = Inventory.get_slots(_builder_id)
	if slots == null or slots.size() < 48:
		return
	for i in range(48):
		if i < _inventory_slots.size():
			var slot_data: Dictionary = slots[i] as Dictionary
			(_inventory_slots[i] as InventorySlot).set_content(
				slot_data.get("def_id", ""),
				slot_data.get("count", 0),
				_builder_id
			)
	# Refresh the 4 crafting slots from the floating buffer — without this,
	# dragging a wood plank INTO the crafting grid succeeds at the data layer
	# but the slot keeps rendering empty (the buffer is separate from the
	# builder inventory array).
	if Inventory.has_method("get_crafting_grid") and _crafting_slots.size() == 4:
		var grid: Array = Inventory.get_crafting_grid("crafting_2x2")
		for ci: int in range(4):
			var cs: Dictionary = grid[ci] as Dictionary
			(_crafting_slots[ci] as InventorySlot).set_content(
				cs.get("def_id", ""),
				cs.get("count", 0),
				_builder_id
			)
	# Update crafting output preview.
	_refresh_crafting_output()


## Update the crafting output slot based on the current 2×2 grid state.
func _refresh_crafting_output() -> void:
	if _crafting_output == null:
		return
	if Inventory == null or not Inventory.has_method("match_recipe"):
		return
	# Read the LIVE crafting buffer from Inventory rather than the stale local
	# _crafting_grid_state Array (which was initialised empty in _ready and
	# never written back to). Without this, match_recipe always saw an empty
	# grid and never showed an output preview even with full stacks dropped in.
	var live_grid: Array = _crafting_grid_state
	if Inventory.has_method("get_crafting_grid"):
		live_grid = Inventory.get_crafting_grid("crafting_2x2")
	# Try shaped first, then shapeless. The 2×2 inline grid is the SHAPELESS grid
	# (plank, stick, etc.) — the old shaped-only lookup meant those never previewed.
	var recipe: Resource = Inventory.match_recipe(live_grid, false)
	if recipe == null:
		recipe = Inventory.match_recipe(live_grid, true)
	if recipe != null and recipe.get("output_def_id") != null:
		_crafting_output.set_content(
			recipe.get("output_def_id") as String,
			recipe.get("output_count") as int,
			_builder_id
		)
	else:
		_crafting_output.set_content("", 0, _builder_id)

# ─── Tab handling ─────────────────────────────────────────────────────────────

## Switch the active tab (Inventory or Recipes) with accent underline animation.
func _set_active_tab(tab_name: String) -> void:
	_active_tab = tab_name

	# Build recipes pane lazily on first switch to "recipes" tab.
	if tab_name == "recipes":
		_build_recipes_pane()

	# Update tab button styles.
	if _tab_inventory != null:
		_apply_tab_style(_tab_inventory, tab_name == "inventory")
	if _tab_recipes != null:
		_apply_tab_style(_tab_recipes, tab_name == "recipes")

	# Show / hide content panes.
	if _grid_container != null:
		_grid_container.visible = (tab_name == "inventory")
	if _crafting_container != null:
		var cluster_node: Node = _crafting_container.get_parent()
		if cluster_node != null:
			cluster_node.visible = (tab_name == "inventory")
	if _recipes_pane != null:
		_recipes_pane.visible = (tab_name == "recipes")


## Apply active/inactive style to a tab button (2px accent underline when active).
func _apply_tab_style(btn: Button, active: bool) -> void:
	if active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.106, 0.173, 0.337, 1.0)
		style.border_width_bottom = 2
		style.border_color = COLOR_ACCENT
		style.content_margin_left = 12.0
		style.content_margin_top = 8.0
		style.content_margin_right = 12.0
		style.content_margin_bottom = 6.0
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		style.content_margin_left = 12.0
		style.content_margin_top = 8.0
		style.content_margin_right = 12.0
		style.content_margin_bottom = 8.0
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.7))

# ─── Signal handlers ──────────────────────────────────────────────────────────

## Redraws all slots whenever the Inventory state changes.
func _on_inventory_changed(builder_id: String) -> void:
	if builder_id != _builder_id:
		return  # Phase 4 multi-builder readiness: ignore other builders' changes.
	_refresh_all_slots()
	if _active_tab == "recipes":
		_refresh_recipes_tab()


## Build (or rebuild) the RecipeBookTab and add it to the recipes pane.
## Called lazily on first tab switch to "recipes" or on open_workbench_mode.
func _build_recipes_pane() -> void:
	if _recipes_pane == null:
		return
	if _recipes_pane.get_child_count() > 0:
		return  # Already built.
	var recipe_book_tab_script: GDScript = preload("res://src/ui/recipe_book_tab.gd")
	var tab: Control = recipe_book_tab_script.new() as Control
	tab.size_flags_horizontal = SIZE_EXPAND_FILL
	tab.size_flags_vertical = SIZE_EXPAND_FILL
	_recipes_pane.add_child(tab)


## Refresh the recipe book tab when Inventory state changes.
## Delegates to the RecipeBookTab instance if it exists.
func _refresh_recipes_tab() -> void:
	if _recipes_pane == null:
		return
	for child in _recipes_pane.get_children():
		if child.has_method("_refresh_book"):
			child.call("_refresh_book")

# ─── Tap-outside-panel close ──────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not get_global_rect().has_point((event as InputEventMouseButton).position):
			close()

# ─── Bottom-sheet gesture — verbatim from brick_palette.gd L495-541 ──────────

func _on_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_drag_start_y = touch.position.y
		else:
			_snap_to_nearest()

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var new_y: float = clampf(position.y + drag.relative.y, _expanded_y, _collapsed_y)
		position.y = new_y

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_snap_to_nearest()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var new_y: float = clampf(position.y + mm.relative.y, _expanded_y, _collapsed_y)
			position.y = new_y


func _snap_to_nearest() -> void:
	var mid: float = (_expanded_y + _collapsed_y) * 0.5
	if position.y <= mid:
		_animate_to(_expanded_y)
		_is_expanded = true
		_notify_mobile_overlay(true)
	else:
		_animate_to(_collapsed_y)
		_is_expanded = false
		_notify_mobile_overlay(false)


## Animate the bottom-sheet to a target Y — verbatim from brick_palette.gd L535-541.
## Also used for sidebar open animation via _animate_sidebar_to.
func _animate_to(target_y: float) -> void:
	# T-03-05-UI-03 mitigate: kill any running tween before starting a new one.
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", target_y, TWEEN_DURATION_S)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_CUBIC)


## Animate the desktop sidebar to a target X position.
## @param hide  If true, hides the node after the tween completes.
func _animate_sidebar_to(target_x: float, hide: bool = false) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	var tw = _tween.tween_property(self, "position:x", target_x, TWEEN_DURATION_S)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_CUBIC)
	if hide:
		_tween.tween_callback(func(): visible = false)

# ─── Mobile-overlay notification ─────────────────────────────────────────────

## Notify MobileOverlay of inventory open/close state — mirrors brick_palette.gd L544-553.
func _notify_mobile_overlay(is_open: bool) -> void:
	if not is_inside_tree():
		return
	var overlay: Node = null
	if get_tree().has_group("mobile_overlay"):
		overlay = get_tree().get_first_node_in_group("mobile_overlay")
	if overlay == null:
		overlay = get_tree().get_root().find_child("MobileOverlay", true, false)
	if overlay != null:
		if overlay.has_method("notify_inventory_open"):
			overlay.call("notify_inventory_open", is_open)
		elif overlay.has_method("_set_palette_open"):
			# Fallback for older overlay version.
			overlay.call("_set_palette_open", is_open)


## Test hook: simulate a drag gesture for bottom-sheet headless GUT tests.
## Mirrors brick_palette.gd _handle_test_drag (per STATE.md palette-test-logic-only decision).
func _handle_test_drag(start_y: float, end_y: float, release_at: float) -> void:
	_drag_start_y = start_y
	position.y = clampf(release_at, _expanded_y, _collapsed_y)
	_snap_to_nearest()
	if _tween != null and _tween.is_running():
		_tween.custom_step(TWEEN_DURATION_S + 0.1)
