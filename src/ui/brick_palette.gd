# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# brick_palette.gd — Brick palette controller (desktop sidebar + mobile bottom sheet).
#
# Per UI-SPEC.md §3.5 + §"Brick Palette Layout Specification" (DOCS.md §3.5).
# Two scenes share this controller: brick_palette_sidebar.tscn (desktop) and
# brick_palette_bottomsheet.tscn (mobile). Layout is set via @export var layout.
#
# Filter order (per PLAN 02-12 must_haves): search → category → colour.
# Selecting a tile equips into the player's active hotbar slot via Hotbar.set_slot_brick().
#
# Adaptive-quality hook: set_previews_mode("3d_realtime"|"on_tap") dispatched by
# Plan 14's _apply_live_settings when the graphics preset changes.
# "3d_realtime" = SubViewport.UPDATE_WHEN_VISIBLE (default, D-12)
# "on_tap"      = SubViewport.UPDATE_DISABLED + one-frame flip on hover/tap (Tier-3)
#
# Mobile bottom-sheet gesture handling:
#   InputEventScreenTouch + InputEventScreenDrag + Tween 0.22s ease-out cubic
#   (per UI-SPEC.md §"Mobile Bottom Sheet" interaction contract)
#
# Crosshair integration (Plan 02-09):
#   open() calls MobileOverlay._set_palette_open(true)
#   close() calls MobileOverlay._set_palette_open(false)
#   so the crosshair hides/shows correctly on mobile.
#
# References:
#   UI-SPEC.md §Brick Palette Layout Specification
#   CONTEXT.md D-12 — 3D tile previews decision
#   02-PATTERNS.md §"src/ui/brick_palette.gd" — settings_menu.gd analog
#   02-PLAN 02-12 — Task 1 + Task 2 implementation spec

class_name BrickPaletteUI
extends PanelContainer

# ─── Constants ────────────────────────────────────────────────────────────────

const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 0.92)   # #1B2C56 at 0.92α
const COLOR_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)   # #F1F0EA
const COLOR_ACCENT: Color = Color(0.961, 0.765, 0.051, 1.0)  # #F5C30D

## Category ID → localisation key mapping (10 categories + All)
const CATEGORY_KEYS: Array = [
	{"id": -1,                             "key": "ui.palette.category.all"},
	{"id": BrickDefinition.Category.RECTANGULAR, "key": "ui.palette.category.rectangular"},
	{"id": BrickDefinition.Category.PLATE,       "key": "ui.palette.category.plates"},
	{"id": BrickDefinition.Category.SLOPE,       "key": "ui.palette.category.slopes"},
	{"id": BrickDefinition.Category.TILE,        "key": "ui.palette.category.tiles"},
	{"id": BrickDefinition.Category.ROUND,       "key": "ui.palette.category.round"},
	{"id": BrickDefinition.Category.FUNCTIONAL,  "key": "ui.palette.category.functional"},
	{"id": BrickDefinition.Category.DECORATIVE,  "key": "ui.palette.category.decorative"},
	{"id": BrickDefinition.Category.MATERIAL_ORE,"key": "ui.palette.category.materials"},
	{"id": BrickDefinition.Category.ACCESSORY,   "key": "ui.palette.category.accessories"},
	{"id": BrickDefinition.Category.MOB_DROP,    "key": "ui.palette.category.mob_drops"},
]

## Tween duration for bottom-sheet animation (UI-SPEC.md "0.22s ease-out cubic")
const TWEEN_DURATION_S: float = 0.22

# ─── Exported properties ──────────────────────────────────────────────────────

## Layout mode: "sidebar" (desktop) or "bottomsheet" (mobile).
@export var layout: String = "sidebar"

# ─── Private node refs (set in _ready from scene tree) ────────────────────────

var _search: LineEdit = null
var _category_chips_container: HBoxContainer = null
var _colour_swatches_container: GridContainer = null
var _equipped_preview_container: SubViewportContainer = null
var _palette_grid: GridContainer = null
var _drag_handle: Control = null

# ─── Private filter state ─────────────────────────────────────────────────────

var _filter_search: String = ""
var _filter_category: int = -1   # -1 = all categories
var _filter_colour: int = -1     # -1 = all colours

## Currently equipped tile's (def_id, colour_index) for selected-state rendering
var _equipped_def_id: String = ""
var _equipped_colour_index: int = -1

## Active chip buttons for category filter
var _category_chip_buttons: Array = []

## Palette tile nodes currently in the grid
var _palette_tiles: Array = []

## Preview mode: "3d_realtime" or "on_tap"
var _previews_mode: String = "3d_realtime"

# ─── Bottom-sheet gesture state ───────────────────────────────────────────────

var _drag_start_y: float = -1.0
var _collapsed_y: float = 0.0   # position.y when collapsed (only drag-handle visible)
var _expanded_y: float = 0.0    # position.y when fully expanded (50% viewport visible)
var _is_expanded: bool = false
var _tween: Tween = null

# ─── Tile scene preload ───────────────────────────────────────────────────────

const _PaletteTileScene := preload("res://src/ui/palette_tile.tscn")
const _PaletteTileScript := preload("res://src/ui/palette_tile.gd")

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_setup_panel_style()
	_resolve_node_refs()
	_build_category_chips()
	_build_colour_swatches()
	_refresh_palette_grid()
	if layout == "bottomsheet":
		_setup_bottomsheet_positions()
		if _drag_handle != null:
			_drag_handle.gui_input.connect(_on_drag_handle_input)


## Set up the panel StyleBoxFlat per UI-SPEC.md §"Chrome colours".
func _setup_panel_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.106, 0.173, 0.337, 0.92)  # #1B2C56 at 0.92α
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
	add_theme_stylebox_override("panel", style)


## Resolve @onready references from the scene tree (set by .tscn scene).
## Gracefully handles missing nodes (sidebar vs bottomsheet have different structures).
func _resolve_node_refs() -> void:
	_search = get_node_or_null("VBox/Search") as LineEdit
	if _search == null:
		_search = get_node_or_null("VBox/Header/Search") as LineEdit
	if _search != null:
		_search.placeholder_text = tr("ui.palette.search_placeholder")
		_search.text_changed.connect(_on_search_text_changed)

	_category_chips_container = get_node_or_null("VBox/CategoryChips") as HBoxContainer
	_colour_swatches_container = get_node_or_null("VBox/ColourSwatches") as GridContainer
	_equipped_preview_container = get_node_or_null("VBox/EquippedPreview") as SubViewportContainer
	if _equipped_preview_container == null:
		_equipped_preview_container = get_node_or_null("VBox/Header/EquippedPreview") as SubViewportContainer

	_palette_grid = get_node_or_null("VBox/PaletteScroll/PaletteGrid") as GridContainer
	_drag_handle = get_node_or_null("VBox/DragHandle") as Control


## Calculate bottom-sheet expanded/collapsed Y positions.
func _setup_bottomsheet_positions() -> void:
	var vp_height := get_viewport_rect().size.y
	_expanded_y = vp_height * 0.5      # 50% of viewport = expanded bottom edge of sheet
	_collapsed_y = vp_height - 64.0    # Only drag-handle peek visible


# ─── Chip builders ────────────────────────────────────────────────────────────

func _build_category_chips() -> void:
	if _category_chips_container == null:
		return
	# Clear existing chips
	for child in _category_chips_container.get_children():
		child.queue_free()
	_category_chip_buttons.clear()

	for entry in CATEGORY_KEYS:
		var btn := Button.new()
		btn.text = tr(entry["key"])
		btn.flat = false
		# Touch target: 80px min width, 40px height per UI-SPEC.md
		btn.custom_minimum_size = Vector2(80.0, 40.0)
		_apply_chip_style(btn, entry["id"] == _filter_category)
		var cat_id: int = entry["id"]
		btn.pressed.connect(func(): _on_category_pressed(cat_id))
		_category_chips_container.add_child(btn)
		_category_chip_buttons.append({"button": btn, "id": cat_id})


func _apply_chip_style(btn: Button, active: bool) -> void:
	if active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.106, 0.173, 0.337, 1.0)
		style.border_width_bottom = 2
		style.border_color = COLOR_ACCENT
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		style.content_margin_left = 12.0
		style.content_margin_top = 8.0
		style.content_margin_right = 12.0
		style.content_margin_bottom = 6.0
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_color_override("font_color", COLOR_WHITE)
		btn.add_theme_font_size_override("font_size", 14)
	else:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.4)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.content_margin_left = 12.0
		style.content_margin_top = 8.0
		style.content_margin_right = 12.0
		style.content_margin_bottom = 8.0
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.7))
		btn.add_theme_font_size_override("font_size", 14)


func _build_colour_swatches() -> void:
	if _colour_swatches_container == null:
		return
	for child in _colour_swatches_container.get_children():
		child.queue_free()

	# "All colours" swatch
	_add_colour_swatch(-1, tr("ui.palette.colour.all"), Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.3))

	# 18 palette colours
	for i in range(BrickPalette.COLOURS.size()):
		_add_colour_swatch(i, BrickPalette.NAMES[i], BrickPalette.COLOURS[i])


func _add_colour_swatch(colour_id: int, label: String, colour: Color) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(32.0, 32.0)
	btn.tooltip_text = label
	btn.flat = true
	# Draw as a circle swatch via StyleBoxFlat
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	if colour_id == _filter_colour:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = COLOR_ACCENT
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	var cid: int = colour_id
	btn.pressed.connect(func(): _on_colour_pressed(cid))
	_colour_swatches_container.add_child(btn)


# ─── Palette grid refresh ─────────────────────────────────────────────────────

## Resolve the local builder's stable id via the "builder" group, or "" if none
## (e.g. the main menu or unit tests, where the palette falls back to show-all).
func _local_builder_id() -> String:
	var b: Node = get_tree().get_first_node_in_group("builder")
	if b != null and b.has_method("get_stable_builder_id"):
		return String(b.call("get_stable_builder_id"))
	return ""


## Set of def_ids the local builder currently holds (count > 0), or null when no local
## builder/inventory can be resolved — callers treat null as "show every brick".
func _owned_def_ids() -> Variant:
	var bid: String = _local_builder_id()
	if bid == "" or Inventory == null or not Inventory.has_method("get_slots"):
		return null
	var slots: Array = Inventory.get_slots(bid)
	if slots == null:
		return null
	var owned: Dictionary = {}
	for slot in slots:
		var sd := slot as Dictionary
		if sd != null and int(sd.get("count", 0)) > 0:
			owned[String(sd.get("def_id", ""))] = true
	return owned


func _refresh_palette_grid() -> void:
	if _palette_grid == null:
		return

	# Clear existing tiles
	for tile in _palette_tiles:
		if tile != null and is_instance_valid(tile):
			tile.queue_free()
	_palette_tiles.clear()

	# Get definitions — apply category filter first
	var defs: Array
	if _filter_category == -1:
		defs = BrickRegistry.get_all()
	else:
		defs = BrickRegistry.get_by_category(_filter_category)

	# Determine if we show an empty state
	var visible_count: int = 0

	# Availability set (QA: pressing B shows only bricks the player actually has). null =
	# no local builder/inventory resolvable (menu, tests) → show everything.
	var owned: Variant = _owned_def_ids()

	for def in defs:
		var brick_def := def as BrickDefinition
		if brick_def == null:
			continue

		# Search filter: substring match on translated display name
		if _filter_search != "" and not _matches_search(brick_def, _filter_search):
			continue

		# Availability filter — skip bricks the player holds none of.
		if owned != null and not (owned as Dictionary).has(brick_def.brick_id):
			continue

		# Colour filter: material bricks (colour_swappable=false) always pass
		# Per UI-SPEC.md spec — material bricks bypass colour filter
		if _filter_colour != -1 and brick_def.colour_swappable:
			# For colour-swappable bricks, show one tile per colour filter selection
			var tile := _instantiate_tile(brick_def.brick_id, _filter_colour)
			_palette_tiles.append(tile)
			_palette_grid.add_child(tile)
			visible_count += 1
		else:
			# Material brick or no colour filter: show the brick with its natural appearance
			var effective_colour: int = -1
			if brick_def.colour_swappable and _filter_colour == -1:
				effective_colour = 0  # default to white for colour-swappable with no filter
			var tile := _instantiate_tile(brick_def.brick_id, effective_colour)
			_palette_tiles.append(tile)
			_palette_grid.add_child(tile)
			visible_count += 1

	# Show empty state if no results
	if visible_count == 0 and _search != null:
		_show_empty_state()


func _instantiate_tile(bid: String, cindex: int) -> Control:
	var tile: Control = _PaletteTileScene.instantiate() as Control
	tile.def_id = bid
	tile.colour_index = cindex
	# Set tile size per layout (64x64 desktop, 56x56 mobile)
	if layout == "bottomsheet":
		tile.custom_minimum_size = Vector2(56.0, 56.0)
	else:
		tile.custom_minimum_size = Vector2(64.0, 64.0)

	tile.tile_selected.connect(_on_tile_selected)

	# Mark selected state
	if bid == _equipped_def_id and cindex == _equipped_colour_index:
		tile.set_selected(true)

	# Apply mesh if the BrickDefinition has one
	var def := BrickRegistry.get_definition(bid)
	if def != null and def.mesh != null:
		tile.set_mesh(def.mesh)

	# Apply current preview mode
	if _previews_mode == "on_tap":
		tile.set_update_mode_from_quality("on_tap")

	return tile


func _show_empty_state() -> void:
	# Add a label showing the empty search state
	var lbl := Label.new()
	lbl.text = tr("ui.palette.search_empty_heading") + "\n" + tr("ui.palette.search_empty_body")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", COLOR_WHITE)
	_palette_grid.add_child(lbl)
	_palette_tiles.append(lbl)


# ─── Filter helpers ───────────────────────────────────────────────────────────

## Substring match on the translated display name (Claude's discretion per CONTEXT.md).
func _matches_search(def: BrickDefinition, query: String) -> bool:
	var translated_name: String = tr(def.display_name_key)
	return translated_name.to_lower().contains(query.to_lower())


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_search_text_changed(text: String) -> void:
	_filter_search = text
	_refresh_palette_grid()


func _on_category_pressed(cat_id: int) -> void:
	_filter_category = cat_id
	# Update chip active styles
	for entry in _category_chip_buttons:
		_apply_chip_style(entry["button"], entry["id"] == cat_id)
	_refresh_palette_grid()


func _on_colour_pressed(colour_id: int) -> void:
	_filter_colour = colour_id
	# Rebuild swatches to update selection ring
	_build_colour_swatches()
	_refresh_palette_grid()


func _on_tile_selected(bid: String, cindex: int) -> void:
	_equipped_def_id = bid
	_equipped_colour_index = cindex

	# Update selected state on all tiles
	for tile in _palette_tiles:
		if tile.get_script() == _PaletteTileScript:
			tile.set_selected(
				tile.def_id == bid and tile.colour_index == cindex
			)

	# Equip into the hotbar active slot (T-12-04 mitigation: validate def exists first)
	var def := BrickRegistry.get_definition(bid)
	if def == null:
		push_warning("BrickPalette._on_tile_selected: unknown def_id '%s' — hotbar not updated." % bid)
		return

	# Hotbar.set_slot_brick is the Phase 2 Plan 12 Task 2 addition.
	# Use get_first_node_in_group to locate the Hotbar without a hard scene path.
	if is_inside_tree():
		var hotbar_nodes := get_tree().get_nodes_in_group("hotbar_slot")
		# The Hotbar itself is not in "hotbar_slot" group — find it via parent
		var hotbar_node := get_tree().get_first_node_in_group("hotbar") if get_tree().has_group("hotbar") else null
		if hotbar_node == null:
			# Try parent-traversal: find Hotbar class node
			hotbar_node = _find_hotbar_node()
		if hotbar_node != null and hotbar_node.has_method("set_slot_brick"):
			hotbar_node.set_slot_brick(hotbar_node.selected_slot if "selected_slot" in hotbar_node else 0, bid, cindex)


## Traverse the scene tree to find the Hotbar node.
func _find_hotbar_node() -> Node:
	if not is_inside_tree():
		return null
	var root := get_tree().get_root()
	return _find_node_with_method(root, "set_slot_brick")


func _find_node_with_method(node: Node, method_name: String) -> Node:
	if node.has_method(method_name) and node.get_script() != null:
		return node
	for child in node.get_children():
		var found := _find_node_with_method(child, method_name)
		if found != null:
			return found
	return null


# ─── Public API ───────────────────────────────────────────────────────────────

## Set all three filters at once (used by tests and external callers).
## @param search    Substring query (empty = no filter)
## @param category  Category int (-1 = all; use BrickDefinition.Category enum values)
## @param colour    Colour index (-1 = all; 0..17 = BrickPalette.COLOURS index)
func set_filter(search: String, category: int, colour: int) -> void:
	_filter_search = search
	_filter_category = category
	_filter_colour = colour
	_refresh_palette_grid()


## Return all tiles currently visible in the palette grid.
## Used by tests to inspect filter results.
func get_visible_tiles() -> Array:
	var result: Array = []
	for tile in _palette_tiles:
		if tile.get_script() == _PaletteTileScript:
			result.append(tile)
	return result


## Show the palette panel. On mobile (bottomsheet), animates to expanded position.
func open() -> void:
	visible = true
	if layout == "bottomsheet":
		_animate_to(_expanded_y)
		_is_expanded = true
		_notify_mobile_overlay(true)


## Hide the palette panel. On mobile (bottomsheet), animates to collapsed position.
func close() -> void:
	if layout == "bottomsheet":
		_animate_to(_collapsed_y)
		_is_expanded = false
		_notify_mobile_overlay(false)
	else:
		visible = false
		_notify_mobile_overlay(false)


## Switch all tile previews between "3d_realtime" and "on_tap" quality modes.
## Dispatched by Plan 14's _apply_live_settings from the adaptive-quality system.
## "3d_realtime" -> SubViewport.UPDATE_WHEN_VISIBLE (default)
## "on_tap"      -> SubViewport.UPDATE_DISABLED + render-once on hover/tap (Tier-3)
func set_previews_mode(mode: String) -> void:
	_previews_mode = mode
	for tile in _palette_tiles:
		if tile.get_script() == _PaletteTileScript:
			tile.set_update_mode_from_quality(mode)


# ─── Mobile bottom-sheet gesture ──────────────────────────────────────────────

func _on_drag_handle_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_drag_start_y = touch.position.y
		else:
			# Release — snap to nearest of expanded/collapsed
			_snap_to_nearest()

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		# Move the panel with the drag, clamped between expanded and collapsed
		var new_y: float = clampf(position.y + drag.relative.y, _expanded_y, _collapsed_y)
		position.y = new_y

	elif event is InputEventMouseButton:
		# Desktop drag-handle click for test/preview
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


func _animate_to(target_y: float) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", target_y, TWEEN_DURATION_S)\
		.set_ease(Tween.EASE_OUT)\
		.set_trans(Tween.TRANS_CUBIC)


## Notify MobileOverlay of palette open/close state for crosshair hide/show (Plan 02-09).
func _notify_mobile_overlay(is_open: bool) -> void:
	if not is_inside_tree():
		return
	var overlay := get_tree().get_first_node_in_group("mobile_overlay") if get_tree().has_group("mobile_overlay") else null
	if overlay == null:
		# Search by node name
		overlay = get_tree().get_root().find_child("MobileOverlay", true, false)
	if overlay != null and overlay.has_method("_set_palette_open"):
		overlay._set_palette_open(is_open)


## FTUE hook: pulse-highlight the palette tile for a specific def_id.
## Called by ftue_overlay.gd at step 3 (wood_plank placement tutorial).
##
## When enabled=true: adds a 2px accent-yellow pulsing border overlay to the tile.
## When enabled=false: removes the overlay and stops the tween.
##
## If the def_id is not currently visible in the palette (wrong category or search
## filter active), this is a silent no-op — the tile may not be present yet.
##
## @param def_id   The brick def_id to highlight (e.g. "wood_plank").
## @param enabled  true = start highlight; false = remove highlight.
func _set_ftue_highlight(def_id: String, enabled: bool) -> void:
	for tile in _palette_tiles:
		if tile.get_script() != _PaletteTileScript:
			continue
		if (tile as PaletteTile).def_id != def_id:
			continue

		# Find or create the FTUE overlay ColorRect on this tile.
		var overlay: ColorRect = tile.get_node_or_null("_ftue_highlight_overlay")

		if not enabled:
			if overlay != null:
				overlay.queue_free()
			return

		if overlay == null:
			overlay = ColorRect.new()
			overlay.name = "_ftue_highlight_overlay"
			# Full-tile anchored; drawn on top of SubViewportContainer content.
			overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			overlay.color = Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.0)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(overlay)

		# Pulsing alpha tween: 0.3 → 0.7 → 0.3, looping (TRANS_SINE ease-in-out, 0.8s).
		var tween: Tween = overlay.get_meta("_ftue_tween", null)
		if tween != null and tween.is_running():
			tween.kill()
		tween = create_tween()
		tween.set_loops()
		tween.tween_property(overlay, "color:a", 0.7, 0.4)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(overlay, "color:a", 0.3, 0.4)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		overlay.set_meta("_ftue_tween", tween)
		return


## Test hook: simulate a drag gesture for bottom-sheet tests.
## Bypasses InputEvent layer to test math directly in headless GUT environment.
## @param start_y    Starting Y position of the drag
## @param end_y      Ending Y position of the drag
## @param release_at Y position at which to "release" the drag handle
func _handle_test_drag(start_y: float, end_y: float, release_at: float) -> void:
	_drag_start_y = start_y
	# Apply drag movement (clamp to valid range)
	position.y = clampf(release_at, _expanded_y, _collapsed_y)
	# Snap to nearest based on release position
	_snap_to_nearest()
	# For test assertions: immediately complete any running tween
	if _tween != null and _tween.is_running():
		_tween.custom_step(TWEEN_DURATION_S + 0.1)
