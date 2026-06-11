# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_naming.gd — DOC-00: project name lock assertion
#
# Verifies that project.godot's application/config/name is exactly "Cubicraftia"
# and that the forbidden string "Lego" does not appear in the project name.
#
# Referenced DOC: DOC-00 — "name = Cubicraftia only"
# See: DOCS.md §0, RESEARCH.md Validation Architecture → Test Map
extends GutTest

const Helpers = preload("res://tests/conftest_helpers.gd")


func test_project_name_is_cubicraftia() -> void:
	## The application/config/name in project.godot must be exactly "Cubicraftia".
	## This is the DOC-00 name-lock assertion — no other product name is permitted.
	var project_name := Helpers.get_project_name()
	assert_eq(
		project_name,
		"Cubicraftia",
		"project.godot config/name must be exactly 'Cubicraftia' (DOC-00)"
	)


func test_project_name_does_not_contain_lego() -> void:
	## The project name must not contain "Lego" in any capitalisation.
	## This guards against accidental use of the working title "LegoMinecraft".
	var project_name := Helpers.get_project_name()
	assert_false(
		"Lego" in project_name or "LEGO" in project_name or "lego" in project_name,
		"project.godot config/name must not contain 'Lego' / 'LEGO' (DOC-00, DOC-10)"
	)


func test_project_name_does_not_contain_minecraft() -> void:
	## The project name must not contain "Minecraft".
	var project_name := Helpers.get_project_name()
	assert_false(
		"Minecraft" in project_name or "minecraft" in project_name,
		"project.godot config/name must not contain 'Minecraft' (DOC-00, DOC-10)"
	)
