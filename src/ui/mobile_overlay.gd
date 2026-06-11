# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# mobile_overlay.gd — Mobile control overlay logic.
#
# Plan 02-09 additions:
#   - Hides the crosshair (in the parent CanvasLayer) when the palette bottom sheet
#     expands on mobile. Crosshair is restored when the sheet collapses.
#   - _crosshair: cached reference to the Crosshair node in the parent CanvasLayer.
#
# Plan 02-12 additions:
#   - _on_palette_pressed: instantiates + expands BrickPaletteBottomsheet (replaces stub).
#   - _palette_bottom_sheet: lazy-loaded instance of brick_palette_bottomsheet.tscn.
#   - PaletteButton enabled (modulate.a=1.0, disabled=false, tooltip_text localised).
#   - _set_palette_open(bool): hook for BrickPaletteUI to hide/show crosshair.
#   - Added to group "mobile_overlay" for BrickPaletteUI to locate this node.
#
# Plan 03-05 additions:
#   - notify_inventory_open(bool): tracks inventory slide-in state; hides on-screen
#     controls when the inventory is open (mutual exclusion with brick palette).
#   - notify_palette_open(bool): replaces the older _set_palette_open hook with a public
#     method for symmetry; closes inventory if open (mutual exclusion).
#   - InventoryButton (TouchScreenButton, top-right): visible on mobile only; emits the
#     ui_inventory_toggle Input action so Builder._unhandled_input picks it up via E key path.
#
# Plan 04-06 additions:
#   - notify_friends_open(bool): tracks friends panel state; closes inventory + palette
#     when friends panel opens (mutual exclusion). Updates crosshair visibility.
#   - _on_chat_pressed(): emits ui_chat_toggle Input action (chat overlay trigger).
#   - _on_friends_pressed(): finds friends_panel via group, calls open().
#   - ChatButton / FriendsButton wired in _ready via get_node_or_null pattern.
#
# Per UI-SPEC.md Mobile Control Overlay section:
#   - Entire overlay hides when OS.has_feature("mobile") is false (desktop).
#   - Left half: VirtualJoystick anchored bottom-left.
#   - Right half: Jump / Place / Break TouchScreenButtons anchored bottom-right.
#   - Bottom centre: Hotbar.
#   - Bottom right: Palette button (enabled in Plan 02-12, DOC-09 fulfilled).
#   - Top right: Inventory button (added Plan 03-05).
#   - Bottom left above joystick: Chat button (added Plan 04-06).
#   - Top right below inventory: Friends button (added Plan 04-06).
#   - Crosshair hidden when palette bottom sheet is fully expanded (UI-SPEC §Crosshair).

extends Control

# ─── Preloads ─────────────────────────────────────────────────────────────────

const _BottomSheetScene := preload("res://src/ui/brick_palette_bottomsheet.tscn")

# ─── State ────────────────────────────────────────────────────────────────────

## Cached reference to the Crosshair node in the parent CanvasLayer (UI).
## Populated in _ready if the node exists; null-safe if absent (e.g. in headless tests).
var _crosshair: Control = null

## Whether the palette bottom sheet is currently expanded.
var _palette_open: bool = false

## Whether the inventory slide-in is currently open (Plan 03-05).
var _inventory_panel_open: bool = false

## Whether the friends panel is currently open (Plan 04-06).
var _friends_panel_open: bool = false

## Lazy-loaded palette bottom sheet instance.
var _palette_bottom_sheet: Control = null

## Lazy-loaded inventory bottom sheet instance (Plan 03-05).
var _inventory_bottom_sheet: Control = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# DOC-07 / UI-SPEC Mobile Control Overlay:
	# The overlay is only visible on mobile; desktop uses keyboard + mouse.
	if not OS.has_feature("mobile"):
		visible = false
		return
	visible = true
	# On mobile, ensure mouse mode is VISIBLE so touch works.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Add to group so BrickPaletteUI can find this node via get_first_node_in_group.
	add_to_group("mobile_overlay")

	# Cache the Crosshair node from the parent CanvasLayer (UI/Crosshair).
	# The parent of this MobileOverlay is the CanvasLayer "UI" in main_scene.tscn.
	var ui_layer := get_parent()
	if ui_layer != null:
		_crosshair = ui_layer.get_node_or_null("Crosshair") as Control

	# Wire the palette button tap to bottom-sheet expansion (Plan 02-12).
	var palette_btn := get_node_or_null("PaletteButton")
	if palette_btn != null and palette_btn.has_signal("pressed"):
		palette_btn.pressed.connect(_on_palette_pressed)
	# Update tooltip text from localisation key
	if palette_btn != null:
		palette_btn.tooltip_text = tr("ui.palette.open")

	# Instantiate the bottom sheet into the parent CanvasLayer at startup.
	# This avoids first-tap latency and allows pre-positioning.
	_ensure_bottom_sheet()

	# Plan 03-05: Wire the inventory button.
	var inv_btn := get_node_or_null("InventoryButton")
	if inv_btn != null and inv_btn.has_signal("pressed"):
		inv_btn.pressed.connect(_on_inventory_pressed)
	if inv_btn != null:
		inv_btn.tooltip_text = tr("ui.inventory.open")

	# Plan 04-06: Wire the chat button (bottom-left, above VirtualJoystick).
	var chat_btn := get_node_or_null("ChatButton")
	if chat_btn != null and chat_btn.has_signal("pressed"):
		chat_btn.pressed.connect(_on_chat_pressed)

	# Plan 04-06: Wire the friends button (top-right, below InventoryButton).
	var friends_btn := get_node_or_null("FriendsButton")
	if friends_btn != null and friends_btn.has_signal("pressed"):
		friends_btn.pressed.connect(_on_friends_pressed)


## Ensure the bottom sheet is instantiated and added to the parent layer.
func _ensure_bottom_sheet() -> void:
	if _palette_bottom_sheet != null and is_instance_valid(_palette_bottom_sheet):
		return
	var parent_layer := get_parent()
	if parent_layer == null:
		return
	_palette_bottom_sheet = _BottomSheetScene.instantiate() as Control
	parent_layer.add_child(_palette_bottom_sheet)
	# Start collapsed (hidden until first open())
	_palette_bottom_sheet.visible = false


func _on_palette_pressed() -> void:
	# Plan 02-12: open the brick palette bottom sheet.
	_ensure_bottom_sheet()
	if _palette_bottom_sheet != null and _palette_bottom_sheet.has_method("open"):
		_palette_bottom_sheet.call("open")
	else:
		# Fallback: toggle visibility
		if _palette_bottom_sheet != null:
			_palette_bottom_sheet.visible = not _palette_bottom_sheet.visible
		_set_palette_open(not _palette_open)


## Called when the palette bottom sheet expands or collapses.
## Updates the crosshair visibility: hidden when palette is open (per UI-SPEC §Crosshair).
## BrickPaletteUI calls this directly via _notify_mobile_overlay().
func _set_palette_open(open: bool) -> void:
	_palette_open = open
	if _crosshair != null:
		_crosshair.visible = not _palette_open and not _inventory_panel_open

	# Also update the PaletteExpandedMarker node for downstream listeners.
	var marker := get_node_or_null("PaletteExpandedMarker")
	if marker != null:
		marker.visible = _palette_open


# ─── Plan 03-05: Inventory panel coordination ─────────────────────────────────

## Called by InventorySlideIn._notify_mobile_overlay() when the inventory opens/closes.
## Enforces mutual exclusion with the brick palette (T-03-05-UI-04 mitigate).
func notify_inventory_open(is_open: bool) -> void:
	_inventory_panel_open = is_open

	if is_open:
		# Close brick palette if open (mutual exclusion).
		if _palette_open and _palette_bottom_sheet != null and _palette_bottom_sheet.has_method("close"):
			_palette_bottom_sheet.call("close")
			_set_palette_open(false)
		# Update inventory button tooltip to reflect close state. The Inventory
		# button is a TouchScreenButton, which extends Node2D and does NOT have
		# a tooltip_text property — only Control descendants do. Guard with an
		# `in` check so we don't crash open() on desktop where Inventory is a
		# TouchScreenButton (Plan 03-05). The "tooltip" semantics on mobile are
		# accessibility-only and can be skipped without functional impact.
		var inv_btn := get_node_or_null("InventoryButton")
		if inv_btn != null and "tooltip_text" in inv_btn:
			inv_btn.tooltip_text = tr("ui.inventory.close")
	else:
		var inv_btn := get_node_or_null("InventoryButton")
		if inv_btn != null and "tooltip_text" in inv_btn:
			inv_btn.tooltip_text = tr("ui.inventory.open")

	# Update crosshair visibility.
	if _crosshair != null:
		_crosshair.visible = not _palette_open and not _inventory_panel_open


## Public version of _set_palette_open — symmetric with notify_inventory_open (Plan 03-05).
## Closes inventory if open when palette opens.
func notify_palette_open(is_open: bool) -> void:
	if is_open and _inventory_panel_open:
		# Close inventory first.
		var inv := _find_inventory_slide_in()
		if inv != null and inv.has_method("close"):
			inv.call("close")
		_inventory_panel_open = false
	_set_palette_open(is_open)


## Emit the ui_inventory_toggle action to trigger Builder._unhandled_input (same path as E key).
func _on_inventory_pressed() -> void:
	Input.action_press("ui_inventory_toggle")
	Input.action_release("ui_inventory_toggle")


## Get the position where the inventory button was last tapped (for compatibility).
func get_inventory_button_position() -> Vector2:
	var inv_btn := get_node_or_null("InventoryButton")
	if inv_btn != null:
		return inv_btn.global_position
	return Vector2.ZERO


## Locate the inventory slide-in bottom-sheet in the scene tree.
func _find_inventory_slide_in() -> Node:
	if not is_inside_tree():
		return null
	if get_tree().has_group("inventory_slide_in"):
		return get_tree().get_first_node_in_group("inventory_slide_in")
	return null


# ─── Plan 04-06: Friends panel coordination ───────────────────────────────────

## Called by FriendsPanel._notify_friends_open() when the friends panel opens/closes.
## Enforces mutual exclusion: closes inventory + palette when friends panel opens.
## Mirrors notify_inventory_open() pattern (04-PATTERNS.md lines 727-745).
func notify_friends_open(is_open: bool) -> void:
	_friends_panel_open = is_open

	if is_open:
		# Close brick palette if open (mutual exclusion).
		if _palette_open and _palette_bottom_sheet != null \
				and _palette_bottom_sheet.has_method("close"):
			_palette_bottom_sheet.call("close")
			_set_palette_open(false)

		# Close inventory if open (mutual exclusion).
		if _inventory_panel_open:
			var inv := _find_inventory_slide_in()
			if inv != null and inv.has_method("close"):
				inv.call("close")
			_inventory_panel_open = false

	# Update crosshair visibility.
	if _crosshair != null:
		_crosshair.visible = not _palette_open \
			and not _inventory_panel_open \
			and not _friends_panel_open


## Emit the ui_chat_toggle action to open/close the chat overlay.
## Chat overlay listens for this action via _unhandled_input (same path as Enter key).
func _on_chat_pressed() -> void:
	Input.action_press("ui_chat_toggle")
	Input.action_release("ui_chat_toggle")


## Open the friends panel via group lookup — same pattern as palette/inventory.
func _on_friends_pressed() -> void:
	if not is_inside_tree():
		return
	var friends_panel: Node = null
	if get_tree().has_group("friends_panel"):
		friends_panel = get_tree().get_first_node_in_group("friends_panel")
	if friends_panel != null and friends_panel.has_method("open"):
		friends_panel.call("open")
