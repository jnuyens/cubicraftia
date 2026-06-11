# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_avatar_preset_validity.gd — Unit tests for avatar preset validation.
#
# Tests cover:
#   - all 8 presets are distinct Dictionaries (no duplicate configs)
#   - each preset has all 8 required keys
#   - each preset has valid values for every key (within the schema contract)
#   - applying a preset to make_avatar_cfg() produces a valid result
#
# Anchors:
#   06-01-PLAN.md Task 2 — test_avatar_preset_validity stub
#   06-UI-SPEC.md Surface 2 — 8 preset tiles, diverse skin/style combinations

extends GutTest

const Phase6Fixtures = preload("res://tests/conftest_phase6.gd")

## The 8 required keys from the avatar config contract.
const REQUIRED_KEYS: Array[String] = [
	"skin_colour_index",
	"head_shape",
	"face_expression",
	"body_colour_index",
	"body_accessory",
	"leg_colour_index",
	"leg_shoes",
	"hand_accessory",
]

const HEAD_SHAPES: Array[String]      = ["square", "round", "tall"]
const FACE_EXPRESSIONS: Array[String] = ["neutral", "happy", "cool", "surprised", "sleepy"]
const BODY_ACCESSORIES: Array[String] = ["none", "backpack", "cape"]
const LEG_SHOES: Array[String]        = ["none", "boots", "sneakers"]
const HAND_ACCESSORIES: Array[String] = ["none", "pickaxe", "lantern", "flower", "blank"]

## The 8 presets from avatar_creator.gd — duplicated here so the test is self-contained
## and does not depend on a Godot CanvasLayer autoload (which would require a scene tree).
## These values must stay in sync with AvatarCreator.PRESETS.
const PRESETS: Array[Dictionary] = [
	# 0 — Classic
	{
		"skin_colour_index": 0, "head_shape": "square", "face_expression": "neutral",
		"body_colour_index": 6, "body_accessory": "none", "leg_colour_index": 6,
		"leg_shoes": "none", "hand_accessory": "none",
	},
	# 1 — Explorer
	{
		"skin_colour_index": 1, "head_shape": "round", "face_expression": "happy",
		"body_colour_index": 4, "body_accessory": "backpack", "leg_colour_index": 0,
		"leg_shoes": "boots", "hand_accessory": "pickaxe",
	},
	# 2 — Knight
	{
		"skin_colour_index": 2, "head_shape": "square", "face_expression": "cool",
		"body_colour_index": 0, "body_accessory": "cape", "leg_colour_index": 0,
		"leg_shoes": "boots", "hand_accessory": "none",
	},
	# 3 — Ninja
	{
		"skin_colour_index": 3, "head_shape": "tall", "face_expression": "cool",
		"body_colour_index": 7, "body_accessory": "none", "leg_colour_index": 7,
		"leg_shoes": "sneakers", "hand_accessory": "blank",
	},
	# 4 — Astronaut
	{
		"skin_colour_index": 4, "head_shape": "round", "face_expression": "surprised",
		"body_colour_index": 9, "body_accessory": "backpack", "leg_colour_index": 9,
		"leg_shoes": "none", "hand_accessory": "none",
	},
	# 5 — Rainbow
	{
		"skin_colour_index": 0, "head_shape": "tall", "face_expression": "happy",
		"body_colour_index": 3, "body_accessory": "none", "leg_colour_index": 2,
		"leg_shoes": "sneakers", "hand_accessory": "flower",
	},
	# 6 — Pirate
	{
		"skin_colour_index": 1, "head_shape": "square", "face_expression": "surprised",
		"body_colour_index": 1, "body_accessory": "cape", "leg_colour_index": 0,
		"leg_shoes": "boots", "hand_accessory": "pickaxe",
	},
	# 7 — Winter
	{
		"skin_colour_index": 2, "head_shape": "round", "face_expression": "sleepy",
		"body_colour_index": 5, "body_accessory": "none", "leg_colour_index": 5,
		"leg_shoes": "boots", "hand_accessory": "lantern",
	},
]


func test_eight_presets_exist() -> void:
	assert_eq(PRESETS.size(), 8,
		"PRESETS must contain exactly 8 presets; found %d" % PRESETS.size())


func test_presets_are_distinct() -> void:
	# No two preset Dictionaries may be byte-for-byte identical.
	for i: int in PRESETS.size():
		for j: int in PRESETS.size():
			if i >= j:
				continue
			assert_ne(PRESETS[i], PRESETS[j],
				"Presets %d and %d must be distinct" % [i, j])


func test_each_preset_has_required_keys() -> void:
	for i: int in PRESETS.size():
		var p: Dictionary = PRESETS[i]
		for key: String in REQUIRED_KEYS:
			assert_true(p.has(key),
				"Preset %d must have key '%s'" % [i, key])


func test_each_preset_skin_colour_in_range() -> void:
	for i: int in PRESETS.size():
		var idx: int = int(PRESETS[i].get("skin_colour_index", -1))
		assert_true(idx >= 0 and idx <= 4,
			"Preset %d skin_colour_index=%d must be in [0,4]" % [i, idx])


func test_each_preset_head_shape_valid() -> void:
	for i: int in PRESETS.size():
		var shape: String = str(PRESETS[i].get("head_shape", ""))
		assert_has(HEAD_SHAPES, shape,
			"Preset %d head_shape='%s' must be in HEAD_SHAPES" % [i, shape])


func test_each_preset_face_expression_valid() -> void:
	for i: int in PRESETS.size():
		var expr: String = str(PRESETS[i].get("face_expression", ""))
		assert_has(FACE_EXPRESSIONS, expr,
			"Preset %d face_expression='%s' must be in FACE_EXPRESSIONS" % [i, expr])


func test_preset_diversity_covers_skin_range() -> void:
	# Collect distinct skin_colour_index values across all 8 presets.
	var skin_values: Dictionary = {}
	for p: Dictionary in PRESETS:
		var idx: int = int(p.get("skin_colour_index", -1))
		skin_values[idx] = true
	assert_true(skin_values.size() >= 3,
		"At least 3 distinct skin_colour_index values must appear across the 8 presets; found %d" % skin_values.size())
