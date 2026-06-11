# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_about_disclaimer.gd - Tests for About screen and first-launch disclaimer
#
# Tests:
#   1. test_about_screen_renders: about.tscn has disclaimer text + version label + license link
#   2. test_first_launch_dialog_records_acknowledgement: first-launch shows once, writes cfg
#   3. test_about_disclaimer_allowlisted: glossary-check.sh exits 0 with allowlisted surfaces
extends GutTest


func _get_about() -> Node:
	var scene := load("res://src/ui/about.tscn")
	if scene == null:
		return null
	return scene.instantiate()


func _get_first_launch() -> Node:
	var scene := load("res://src/ui/first_launch_disclaimer.tscn")
	if scene == null:
		return null
	return scene.instantiate()


# ─── Test 1: About screen renders ────────────────────────────────────────────

func test_about_screen_renders() -> void:
	## about.tscn must contain:
	## - A label rendering tr("ui.about.disclaimer")
	## - A version label with text containing a version string
	## - A "View license" button
	var about := _get_about()
	assert_not_null(about, "about.tscn must exist and instantiate")
	if about == null:
		return

	add_child(about)

	# Disclaimer must be present
	var disclaimer_label := _find_label_containing(about, "not affiliated")
	if disclaimer_label == null:
		disclaimer_label = _find_label_containing(about, tr("ui.about.disclaimer").substr(0, 20))
	assert_not_null(disclaimer_label,
		"about.tscn must contain a label with the disclaimer copy")

	# Version label - must show "Version" or a version number
	var version_label := _find_label_containing(about, "Version")
	if version_label == null:
		version_label = _find_label_containing(about, "0.1")
	assert_not_null(version_label,
		"about.tscn must contain a version label (e.g. 'Version 0.1.0')")

	# License button or label
	var license_btn := _find_node_by_name(about, "LicenseButton")
	if license_btn == null:
		license_btn = _find_button_containing(about, "license")
	if license_btn == null:
		# Could be a label with a link
		license_btn = _find_label_containing(about, "GPL-3.0")
	assert_not_null(license_btn,
		"about.tscn must contain a 'View license' button or license label")

	about.queue_free()


# ─── Test 2: First-launch dialog records acknowledgement ─────────────────────

func test_first_launch_dialog_records_acknowledgement() -> void:
	## First-launch disclaimer must:
	## 1. Show when user://settings.cfg lacks [first_launch] acknowledged=true
	## 2. Write the flag when "Got it" is tapped
	## 3. Not show on second instantiation

	# Clear acknowledgement flag for a clean test
	var cfg := ConfigFile.new()
	var path := "user://settings.cfg"
	cfg.set_value("first_launch", "acknowledged", false)
	cfg.save(path)

	# First instantiation - should show the dialog
	var dlg1 := _get_first_launch()
	assert_not_null(dlg1, "first_launch_disclaimer.tscn must exist")
	if dlg1 == null:
		return

	add_child(dlg1)
	# Dialog should be visible (or at least not immediately freed)
	# The dialog gates on the settings.cfg flag - since we set it to false, it should show
	# We check it's still alive (not freed) after _ready
	assert_true(is_instance_valid(dlg1),
		"First launch dialog should still be alive when acknowledged=false")

	# Simulate acknowledgement by calling the handler directly
	if dlg1.has_method("_on_acknowledge_pressed"):
		dlg1._on_acknowledge_pressed()

	# Verify the flag was written
	var cfg2 := ConfigFile.new()
	var err := cfg2.load(path)
	assert_eq(err, OK, "user://settings.cfg must be writable")
	var acked: bool = cfg2.get_value("first_launch", "acknowledged", false)
	assert_true(acked,
		"first_launch_disclaimer must write acknowledged=true to user://settings.cfg on 'Got it'")

	# Clean up
	if is_instance_valid(dlg1):
		dlg1.queue_free()

	# Second instantiation - dialog should immediately free itself
	var dlg2 := _get_first_launch()
	assert_not_null(dlg2, "first_launch_disclaimer.tscn must still instantiate")
	if dlg2 == null:
		return

	add_child(dlg2)
	# One frame for _ready to run
	await get_tree().process_frame

	# After _ready on a device that has acknowledged, the node should be freed
	# or at least not visible
	var still_active: bool = is_instance_valid(dlg2) and bool(dlg2.visible)
	assert_false(still_active,
		"First launch disclaimer must not be shown when acknowledged=true")

	if is_instance_valid(dlg2):
		dlg2.queue_free()


# ─── Test 3: About disclaimer is allowlisted in glossary check ────────────────

func test_about_disclaimer_allowlisted() -> void:
	## Running scripts/glossary-check.sh must exit 0 even though
	## about.tscn and first_launch_disclaimer.tscn contain "LEGO Group" text.
	## This proves the Task 1 allowlist update works correctly.

	var result := OS.execute("bash", ["scripts/glossary-check.sh"], [])
	assert_eq(result, 0,
		"scripts/glossary-check.sh must exit 0 with the disclaimer surfaces allowlisted")


# ─── Helpers ──────────────────────────────────────────────────────────────────

func _find_all_of_type(root: Node, type_name: String) -> Array:
	var results := []
	if root.get_class() == type_name or root.is_class(type_name):
		results.append(root)
	for child in root.get_children():
		results.append_array(_find_all_of_type(child, type_name))
	return results


func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _find_node_by_name(child, node_name)
		if found != null:
			return found
	return null


func _find_label_containing(root: Node, text_fragment: String) -> Node:
	for label in _find_all_of_type(root, "Label"):
		if text_fragment.to_lower() in label.text.to_lower():
			return label
	return null


func _find_button_containing(root: Node, text_fragment: String) -> Node:
	for btn in _find_all_of_type(root, "Button"):
		if text_fragment.to_lower() in btn.text.to_lower() or text_fragment.to_lower() in btn.name.to_lower():
			return btn
	return null
