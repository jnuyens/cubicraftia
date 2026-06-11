# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_world_select_list.gd — Regression guard for the "world-select hangs / dead-ends" bug.
#
# THE BUG (observed twice): the world-card ScrollContainer was created with only
# size_flags_vertical = EXPAND_FILL and NO minimum height. The panel sizes to its
# content, so the scroll collapsed to 0 px and EVERY world card was invisible. The
# player could only ever click "New world"; once the MAX_WORLDS cap disabled that
# button there was no visible card to select or delete — the screen was a dead-end.
#
# These tests fail if either guarantee regresses:
#   1. The world list has a positive minimum height (cards can render visibly).
#   2. _rebuild_world_list() produces exactly one card per world in index.cfg
#      (so a player at the cap can always see/select/delete a world to proceed).
#
# Pattern: instantiate the real screen scene; seed a temporary index.cfg and
# restore it in after_each so user state is never clobbered.

extends GutTest

const WorldSelectScene := preload("res://src/ui/world_select_screen.tscn")
const _INDEX := "user://worlds/index.cfg"
const _WORLDS_DIR := "user://worlds"

var _backup: String = ""
var _had_backup: bool = false


func before_each() -> void:
	if FileAccess.file_exists(_INDEX):
		_backup = FileAccess.get_file_as_string(_INDEX)
		_had_backup = true
	else:
		_had_backup = false


func after_each() -> void:
	if _had_backup:
		var f := FileAccess.open(_INDEX, FileAccess.WRITE)
		if f != null:
			f.store_string(_backup)
			f.close()
	elif FileAccess.file_exists(_INDEX):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_INDEX))


func _make_screen() -> Node:
	var screen: Node = WorldSelectScene.instantiate()
	add_child_autofree(screen)
	return screen


func _seed_index(count: int) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_WORLDS_DIR))
	var cfg := ConfigFile.new()
	for i in count:
		var wid := "selftest_world_%d" % i
		cfg.set_value(wid, "name", "Selftest %d" % i)
		cfg.set_value(wid, "seed", 100 + i)
		cfg.set_value(wid, "mode", "creative")
		cfg.set_value(wid, "created_unix", 1000 + i)
		cfg.set_value(wid, "last_played_unix", 1000 + i)
	cfg.save(_INDEX)


# Regression 1: the world-card list must have a positive minimum height so cards
# are never collapsed to 0 px (the root cause of the dead-end hang).
func test_world_list_has_visible_height() -> void:
	var screen := _make_screen()
	await get_tree().process_frame
	var scroll: Control = screen._scroll_container
	assert_not_null(scroll, "world-select must build a scroll container for the card list")
	assert_gt(scroll.custom_minimum_size.y, 0.0,
		"World-card list must have a positive min height — otherwise all world cards are invisible and the MAX_WORLDS cap becomes a dead-end.")


# Regression 2: every world in index.cfg renders as a selectable/deletable card.
func test_one_card_per_world() -> void:
	_seed_index(3)
	# _ready() runs _rebuild_world_list() against the seeded index when added to the tree.
	var screen := _make_screen()
	await get_tree().process_frame
	assert_eq(screen._world_list_container.get_child_count(), 3,
		"world-select must render exactly one card per world so a capped player can still pick/delete one")


# Regression 3: even at the MAX_WORLDS cap (New world disabled), the player still
# sees every world card — so they can delete one and escape the cap.
func test_cards_present_when_at_cap() -> void:
	_seed_index(screen_cap())
	var screen := _make_screen()
	await get_tree().process_frame
	assert_true(screen._new_world_button.disabled,
		"New world should be disabled at the cap (expected)")
	assert_eq(screen._world_list_container.get_child_count(), screen_cap(),
		"at the cap, all world cards must still render so the screen is never a dead-end")


func screen_cap() -> int:
	return load("res://src/ui/world_select_screen.gd").MAX_WORLDS
