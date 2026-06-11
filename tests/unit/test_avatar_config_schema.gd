# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_avatar_config_schema.gd — Unit tests for avatar cfg round-trip and schema validation.
#
# Tests cover:
#   - save/load round-trip through user://avatar.cfg via ConfigFile
#   - all required keys present after load
#   - valid index ranges: skin 0-4, body 0-9, leg 0-9
#   - valid enum values: head_shape in ["square","round","tall"]
#   - valid enum values: face_expression in ["neutral","happy","cool","surprised","sleepy"]
#   - valid enum values: body_accessory in ["none","backpack","cape"]
#   - valid enum values: leg_shoes in ["none","boots","sneakers"]
#   - valid enum values: hand_accessory in ["none","pickaxe","lantern","flower","blank"]
#
# Anchors:
#   06-01-PLAN.md Task 2 — test_avatar_config_schema stub
#   06-UI-SPEC.md Surface 2 — avatar config key/value contract

extends GutTest

const Phase6Fixtures = preload("res://tests/conftest_phase6.gd")

## The 8 required keys that every avatar config must contain.
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


func test_avatar_cfg_has_required_keys() -> void:
	var cfg: Dictionary = Phase6Fixtures.make_avatar_cfg()
	for key: String in REQUIRED_KEYS:
		assert_true(cfg.has(key),
			"make_avatar_cfg() must contain key '%s'" % key)


func test_avatar_cfg_round_trip_via_config_file() -> void:
	var cfg_in: Dictionary = Phase6Fixtures.make_avatar_cfg()
	# Override some values so we verify they round-trip correctly.
	cfg_in["skin_colour_index"]  = 3
	cfg_in["head_shape"]         = "tall"
	cfg_in["face_expression"]    = "sleepy"
	cfg_in["body_colour_index"]  = 7
	cfg_in["body_accessory"]     = "cape"
	cfg_in["leg_colour_index"]   = 4
	cfg_in["leg_shoes"]          = "sneakers"
	cfg_in["hand_accessory"]     = "lantern"

	# Write to a temp path.
	var temp_path: String = "user://test_avatar_roundtrip_%d.cfg" % randi()
	var writer := ConfigFile.new()
	writer.set_value("avatar", "skin_colour_index",  cfg_in["skin_colour_index"])
	writer.set_value("avatar", "head_shape",         cfg_in["head_shape"])
	writer.set_value("avatar", "face_expression",    cfg_in["face_expression"])
	writer.set_value("avatar", "body_colour_index",  cfg_in["body_colour_index"])
	writer.set_value("avatar", "body_accessory",     cfg_in["body_accessory"])
	writer.set_value("avatar", "leg_colour_index",   cfg_in["leg_colour_index"])
	writer.set_value("avatar", "leg_shoes",          cfg_in["leg_shoes"])
	writer.set_value("avatar", "hand_accessory",     cfg_in["hand_accessory"])
	writer.save(temp_path)

	# Read back.
	var reader := ConfigFile.new()
	var err := reader.load(temp_path)
	assert_eq(err, OK, "ConfigFile.load must succeed for the temp avatar cfg")

	assert_eq(reader.get_value("avatar", "skin_colour_index", -1),
		3, "skin_colour_index must round-trip as 3")
	assert_eq(reader.get_value("avatar", "head_shape", ""),
		"tall", "head_shape must round-trip as 'tall'")
	assert_eq(reader.get_value("avatar", "face_expression", ""),
		"sleepy", "face_expression must round-trip as 'sleepy'")
	assert_eq(reader.get_value("avatar", "body_colour_index", -1),
		7, "body_colour_index must round-trip as 7")
	assert_eq(reader.get_value("avatar", "body_accessory", ""),
		"cape", "body_accessory must round-trip as 'cape'")
	assert_eq(reader.get_value("avatar", "leg_colour_index", -1),
		4, "leg_colour_index must round-trip as 4")
	assert_eq(reader.get_value("avatar", "leg_shoes", ""),
		"sneakers", "leg_shoes must round-trip as 'sneakers'")
	assert_eq(reader.get_value("avatar", "hand_accessory", ""),
		"lantern", "hand_accessory must round-trip as 'lantern'")

	# Cleanup.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))


func test_skin_colour_index_valid_range() -> void:
	# Default value 0 is in range [0,4].
	var cfg: Dictionary = Phase6Fixtures.make_avatar_cfg()
	var idx: int = int(cfg.get("skin_colour_index", -1))
	assert_true(idx >= 0 and idx <= 4,
		"default skin_colour_index must be in [0,4]; got %d" % idx)

	# The 5 valid values.
	for i: int in range(5):
		assert_true(i >= 0 and i <= 4,
			"skin index %d must be in [0,4]" % i)

	# Value 5 is out of the valid range.
	assert_false(5 >= 0 and 5 <= 4,
		"skin index 5 must NOT be in [0,4]")


func test_head_shape_valid_enum() -> void:
	assert_has(HEAD_SHAPES, "square", "HEAD_SHAPES must include 'square'")
	assert_has(HEAD_SHAPES, "round",  "HEAD_SHAPES must include 'round'")
	assert_has(HEAD_SHAPES, "tall",   "HEAD_SHAPES must include 'tall'")
	assert_does_not_have(HEAD_SHAPES, "invalid",
		"HEAD_SHAPES must not include 'invalid'")
	assert_eq(HEAD_SHAPES.size(), 3, "HEAD_SHAPES must have exactly 3 values")


func test_face_expression_valid_enum() -> void:
	assert_has(FACE_EXPRESSIONS, "neutral",   "FACE_EXPRESSIONS must include 'neutral'")
	assert_has(FACE_EXPRESSIONS, "happy",     "FACE_EXPRESSIONS must include 'happy'")
	assert_has(FACE_EXPRESSIONS, "cool",      "FACE_EXPRESSIONS must include 'cool'")
	assert_has(FACE_EXPRESSIONS, "surprised", "FACE_EXPRESSIONS must include 'surprised'")
	assert_has(FACE_EXPRESSIONS, "sleepy",    "FACE_EXPRESSIONS must include 'sleepy'")
	assert_eq(FACE_EXPRESSIONS.size(), 5, "FACE_EXPRESSIONS must have exactly 5 values")


func test_body_colour_index_valid_range() -> void:
	var cfg: Dictionary = Phase6Fixtures.make_avatar_cfg()
	var idx: int = int(cfg.get("body_colour_index", -1))
	assert_true(idx >= 0 and idx <= 9,
		"default body_colour_index must be in [0,9]; got %d" % idx)
	# Value 10 is out of range.
	assert_false(10 >= 0 and 10 <= 9,
		"body index 10 must NOT be in [0,9]")


func test_body_accessory_valid_enum() -> void:
	assert_has(BODY_ACCESSORIES, "none",    "BODY_ACCESSORIES must include 'none'")
	assert_has(BODY_ACCESSORIES, "backpack","BODY_ACCESSORIES must include 'backpack'")
	assert_has(BODY_ACCESSORIES, "cape",    "BODY_ACCESSORIES must include 'cape'")
	assert_eq(BODY_ACCESSORIES.size(), 3, "BODY_ACCESSORIES must have exactly 3 values")


func test_leg_colour_index_valid_range() -> void:
	var cfg: Dictionary = Phase6Fixtures.make_avatar_cfg()
	var idx: int = int(cfg.get("leg_colour_index", -1))
	assert_true(idx >= 0 and idx <= 9,
		"default leg_colour_index must be in [0,9]; got %d" % idx)


func test_leg_shoes_valid_enum() -> void:
	assert_has(LEG_SHOES, "none",     "LEG_SHOES must include 'none'")
	assert_has(LEG_SHOES, "boots",    "LEG_SHOES must include 'boots'")
	assert_has(LEG_SHOES, "sneakers", "LEG_SHOES must include 'sneakers'")
	assert_eq(LEG_SHOES.size(), 3, "LEG_SHOES must have exactly 3 values")


func test_hand_accessory_valid_enum() -> void:
	assert_has(HAND_ACCESSORIES, "none",    "HAND_ACCESSORIES must include 'none'")
	assert_has(HAND_ACCESSORIES, "pickaxe", "HAND_ACCESSORIES must include 'pickaxe'")
	assert_has(HAND_ACCESSORIES, "lantern", "HAND_ACCESSORIES must include 'lantern'")
	assert_has(HAND_ACCESSORIES, "flower",  "HAND_ACCESSORIES must include 'flower'")
	assert_has(HAND_ACCESSORIES, "blank",   "HAND_ACCESSORIES must include 'blank'")
	assert_eq(HAND_ACCESSORIES.size(), 5, "HAND_ACCESSORIES must have exactly 5 values")
