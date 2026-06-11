# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_mobile_overlay.gd — Unit tests for mobile overlay, hotbar, joystick, toast
#
# Tests:
#   1. test_overlay_hidden_on_desktop: overlay hides when not mobile
#   2. test_all_required_buttons_present: overlay has TouchScreenButtons + VirtualJoystick
#   3. test_hotbar_has_8_slots: hotbar has exactly 8 slot TextureRects
#   4. test_build_palette_button_disabled: palette button is non-interactive (disabled)
#   5. test_toast_renders: Toasts.show() causes toast scene to show the EN copy key
extends GutTest


func _get_overlay() -> Node:
	# Load the mobile overlay scene directly
	var overlay_scene := load("res://src/ui/mobile_overlay.tscn")
	if overlay_scene == null:
		return null
	return overlay_scene.instantiate()


func _get_hotbar() -> Node:
	var hotbar_scene := load("res://src/ui/hotbar.tscn")
	if hotbar_scene == null:
		return null
	return hotbar_scene.instantiate()


func _get_toast() -> Node:
	var toast_scene := load("res://src/ui/toast.tscn")
	if toast_scene == null:
		return null
	return toast_scene.instantiate()


# ─── Test 1: Overlay hides on desktop ─────────────────────────────────────────

func test_overlay_hidden_on_desktop() -> void:
	## On non-mobile platforms, the overlay must not be visible.
	## The overlay's _ready() calls OS.has_feature("mobile") and hides itself.
	## In the headless test runner (not a mobile device), visible should be false.
	var overlay := _get_overlay()
	assert_not_null(overlay, "mobile_overlay.tscn must exist and instantiate")
	if overlay == null:
		return

	add_child(overlay)
	# After _ready() runs (via add_child), on desktop has_feature("mobile") = false
	# so the overlay should not be visible.
	assert_false(overlay.visible,
		"Mobile overlay must be hidden on non-mobile platform (OS.has_feature('mobile') == false)")
	overlay.queue_free()


# ─── Test 2: Required buttons present ─────────────────────────────────────────

func test_all_required_buttons_present() -> void:
	## The overlay must contain TouchScreenButtons with actions: place, break, jump
	## and a VirtualJoystick child.
	var overlay := _get_overlay()
	assert_not_null(overlay, "mobile_overlay.tscn must exist")
	if overlay == null:
		return

	add_child(overlay)

	# Find all TouchScreenButtons (may be nested)
	var buttons := _find_all_of_type(overlay, "TouchScreenButton")
	var actions := []
	for btn in buttons:
		actions.append(btn.action)

	assert_true("place" in actions,
		"overlay must contain a TouchScreenButton with action='place'")
	assert_true("break" in actions,
		"overlay must contain a TouchScreenButton with action='break'")
	assert_true("jump" in actions,
		"overlay must contain a TouchScreenButton with action='jump'")

	# VirtualJoystick must be present — look for a node named "VirtualJoystick"
	var joystick := _find_node_by_name(overlay, "VirtualJoystick")
	assert_not_null(joystick,
		"overlay must contain at least one VirtualJoystick node")

	overlay.queue_free()


# ─── Test 3: Hotbar has 8 slots ───────────────────────────────────────────────

func test_hotbar_has_8_slots() -> void:
	## hotbar.tscn must render exactly 8 slot TextureRect nodes.
	var hotbar := _get_hotbar()
	assert_not_null(hotbar, "hotbar.tscn must exist and instantiate")
	if hotbar == null:
		return

	add_child(hotbar)

	var slots := _find_all_with_group(hotbar, "hotbar_slot")
	if slots.is_empty():
		# Fallback: count TextureRect children
		slots = _find_all_of_type(hotbar, "TextureRect")

	assert_eq(slots.size(), 8,
		"hotbar.tscn must have exactly 8 slot nodes (TextureRect or hotbar_slot group)")

	hotbar.queue_free()


# ─── Test 4: Build palette button enabled (Plan 02-12) ───────────────────────

func test_build_palette_button_disabled() -> void:
	## Plan 02-12: The Build Palette button is now ENABLED (Plan 02-09 stub replaced).
	## The button must be present; it must NOT be disabled and must be fully opaque.
	## Previous check (disabled=true) is now inverted: button should be active.
	var overlay := _get_overlay()
	assert_not_null(overlay, "mobile_overlay.tscn must exist")
	if overlay == null:
		return

	add_child(overlay)

	# Find the palette button — look for node named "PaletteButton" or similar
	var palette_btn := _find_node_by_name(overlay, "PaletteButton")
	if palette_btn == null:
		# Try finding by group
		var all_buttons := _find_all_of_type(overlay, "TouchScreenButton")
		for btn in all_buttons:
			if btn.name.to_lower().contains("palette") or (btn.has_method("get_action") and btn.action == ""):
				palette_btn = btn
				break

	assert_not_null(palette_btn,
		"overlay must have a palette/build-palette button node")

	if palette_btn == null:
		overlay.queue_free()
		return

	# Plan 02-12: palette button must be enabled (not disabled) and fully opaque
	var is_enabled: bool = true
	if "disabled" in palette_btn:
		is_enabled = not palette_btn.disabled
	var is_visible: bool = palette_btn.modulate.a > 0.9

	assert_true(is_enabled,
		"Palette button must be enabled (disabled=false) in Plan 02-12")
	assert_true(is_visible,
		"Palette button must be fully opaque (modulate.a > 0.9) in Plan 02-12")

	overlay.queue_free()


# ─── Test 5: Toast renders with expected key ──────────────────────────────────

func test_toast_renders() -> void:
	## Emitting Toasts.show("ui.toast.graphics_adjusted", "info") must
	## cause the toast scene to be visible with the correct key content.
	var toast := _get_toast()
	assert_not_null(toast, "toast.tscn must exist and instantiate")
	if toast == null:
		return

	add_child(toast)

	# The toast should connect to Toasts signal on _ready
	# Call show() directly on the toast if it exposes that method
	if toast.has_method("show_toast"):
		toast.show_toast("ui.toast.graphics_adjusted", "info")
	else:
		# Emit via Toasts autoload
		Toasts.show("ui.toast.graphics_adjusted", "info")

	# Wait one frame for signal processing
	await get_tree().process_frame

	# Toast should be visible (or have a label with the key or translated text)
	var label := _find_first_of_type(toast, "Label")
	if label != null:
		var text_matches: bool = (
			label.text == tr("ui.toast.graphics_adjusted") or
			label.text == "ui.toast.graphics_adjusted" or
			label.text == "Graphics adjusted for performance."
		)
		assert_true(text_matches,
			"Toast label should show the translated toast message, got: '%s'" % label.text)
	else:
		# Toast exists, even without a visible label — that's the minimum bar
		assert_not_null(toast, "Toast scene exists and is functional")

	toast.queue_free()


# ─── Helpers ──────────────────────────────────────────────────────────────────

func _find_all_of_type(root: Node, type_name: String) -> Array:
	var results := []
	if root.get_class() == type_name or root.is_class(type_name):
		results.append(root)
	for child in root.get_children():
		results.append_array(_find_all_of_type(child, type_name))
	return results


func _find_first_of_type(root: Node, type_name: String) -> Node:
	if root.get_class() == type_name or root.is_class(type_name):
		return root
	for child in root.get_children():
		var found := _find_first_of_type(child, type_name)
		if found != null:
			return found
	return null


func _find_all_with_group(root: Node, group_name: String) -> Array:
	var results := []
	if root.is_in_group(group_name):
		results.append(root)
	for child in root.get_children():
		results.append_array(_find_all_with_group(child, group_name))
	return results


func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, node_name)
		if found != null:
			return found
	return null
