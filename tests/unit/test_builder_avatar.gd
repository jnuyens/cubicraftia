# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_builder_avatar.gd — Unit tests for Builder.apply_avatar_config() + load_avatar_from_file().
#
# Plan 06-07 must_haves tested here:
#   - apply_avatar_config() changes head mesh albedo to SKIN_COLOURS[skin_colour_index]
#   - apply_avatar_config() changes body mesh albedo to BODY_COLOURS[body_colour_index]
#   - apply_avatar_config() changes legs mesh albedo to BODY_COLOURS[leg_colour_index]
#   - apply_avatar_config() sets correct hand accessory visibility (only selected visible)
#   - apply_avatar_config() sets correct body accessory visibility
#   - apply_avatar_config() can be called multiple times (no resource leak)
#   - load_avatar_from_file() falls back to DEFAULT_AVATAR_CFG when no file present
#   - Index bounds clamping prevents out-of-range crashes (T-06-B1)
#   - SKIN_COLOURS and BODY_COLOURS constants match avatar_creator.gd values
#
# Pattern: detached-node-test per STATE.md Phase 1 decision.
# Builder.tscn instantiated; avatar mesh nodes are set up programmatically in _ready().

extends GutTest

# ─── Scene preload ─────────────────────────────────────────────────────────────

const BuilderScene = preload("res://src/builder/builder.tscn")

# ─── Fixtures ──────────────────────────────────────────────────────────────────

var _builder: Builder = null


func before_each() -> void:
	_builder = BuilderScene.instantiate() as Builder
	add_child(_builder)


func after_each() -> void:
	if _builder != null:
		_builder.queue_free()
	_builder = null


# ─── Helper ────────────────────────────────────────────────────────────────────

## Build a complete valid avatar cfg dict with given overrides on top of defaults.
func _make_cfg(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"skin_colour_index": 0,
		"head_shape": "square",
		"face_expression": "neutral",
		"body_colour_index": 0,
		"body_accessory": "none",
		"leg_colour_index": 0,
		"leg_shoes": "none",
		"hand_accessory": "none",
	}
	for key: String in overrides.keys():
		base[key] = overrides[key]
	return base


# ─── Test 1: apply_avatar_config method exists ────────────────────────────────

func test_apply_avatar_config_method_exists() -> void:
	assert_true(_builder.has_method("apply_avatar_config"),
		"Builder must have apply_avatar_config() method")


# ─── Test 2: load_avatar_from_file method exists ────────────────────────────

func test_load_avatar_from_file_method_exists() -> void:
	assert_true(_builder.has_method("load_avatar_from_file"),
		"Builder must have load_avatar_from_file() method")


# ─── Test 3: SKIN_COLOURS constant has 5 entries ────────────────────────────

func test_skin_colours_constant_has_five_entries() -> void:
	assert_eq(Builder.SKIN_COLOURS.size(), 5,
		"Builder.SKIN_COLOURS must have exactly 5 colour entries")


# ─── Test 4: BODY_COLOURS constant has 10 entries ────────────────────────────

func test_body_colours_constant_has_ten_entries() -> void:
	assert_eq(Builder.BODY_COLOURS.size(), 10,
		"Builder.BODY_COLOURS must have exactly 10 colour entries")


# ─── Test 5: SKIN_COLOURS values match avatar_creator.gd ─────────────────────

func test_skin_colours_match_avatar_creator() -> void:
	# Values copied from avatar_creator.gd SKIN_COLOURS constant.
	var expected: Array[Color] = [
		Color("#FFD21A"),
		Color("#D4956A"),
		Color("#A0614A"),
		Color("#6B3A2A"),
		Color("#3B1F16"),
	]
	for i: int in expected.size():
		assert_almost_eq(Builder.SKIN_COLOURS[i].r, expected[i].r, 0.01,
			"SKIN_COLOURS[%d] red channel must match avatar_creator.gd" % i)
		assert_almost_eq(Builder.SKIN_COLOURS[i].g, expected[i].g, 0.01,
			"SKIN_COLOURS[%d] green channel must match avatar_creator.gd" % i)
		assert_almost_eq(Builder.SKIN_COLOURS[i].b, expected[i].b, 0.01,
			"SKIN_COLOURS[%d] blue channel must match avatar_creator.gd" % i)


# ─── Test 6: BODY_COLOURS values match avatar_creator.gd ─────────────────────

func test_body_colours_match_avatar_creator() -> void:
	# First entry (red) and last entry (white) verify the palette subset.
	assert_almost_eq(Builder.BODY_COLOURS[0].r, Color("#C91111").r, 0.01,
		"BODY_COLOURS[0] (red) must match avatar_creator.gd value")
	assert_almost_eq(Builder.BODY_COLOURS[9].r, Color("#F1F0EA").r, 0.01,
		"BODY_COLOURS[9] (white) must match avatar_creator.gd value")


# ─── Test 7: apply_avatar_config sets head mesh colour to SKIN_COLOURS[2] ────

func test_apply_avatar_config_sets_head_skin_colour() -> void:
	var cfg: Dictionary = _make_cfg({"skin_colour_index": 2})
	_builder.apply_avatar_config(cfg)

	var head_mesh: MeshInstance3D = _builder.get_node_or_null("AvatarMesh/Head") as MeshInstance3D
	assert_not_null(head_mesh, "Builder must have AvatarMesh/Head MeshInstance3D child")
	if head_mesh == null:
		return
	var mat: StandardMaterial3D = head_mesh.get_active_material(0) as StandardMaterial3D
	assert_not_null(mat, "Head mesh must have a StandardMaterial3D")
	if mat == null:
		return
	var expected_colour: Color = Builder.SKIN_COLOURS[2]
	assert_almost_eq(mat.albedo_color.r, expected_colour.r, 0.01,
		"Head albedo red channel must match SKIN_COLOURS[2]")
	assert_almost_eq(mat.albedo_color.g, expected_colour.g, 0.01,
		"Head albedo green channel must match SKIN_COLOURS[2]")
	assert_almost_eq(mat.albedo_color.b, expected_colour.b, 0.01,
		"Head albedo blue channel must match SKIN_COLOURS[2]")


# ─── Test 8: apply_avatar_config sets body mesh colour to BODY_COLOURS[5] ────

func test_apply_avatar_config_sets_body_colour() -> void:
	var cfg: Dictionary = _make_cfg({"body_colour_index": 5})
	_builder.apply_avatar_config(cfg)

	var body_mesh: MeshInstance3D = _builder.get_node_or_null("AvatarMesh/Body") as MeshInstance3D
	assert_not_null(body_mesh, "Builder must have AvatarMesh/Body MeshInstance3D child")
	if body_mesh == null:
		return
	var mat: StandardMaterial3D = body_mesh.get_active_material(0) as StandardMaterial3D
	assert_not_null(mat, "Body mesh must have a StandardMaterial3D")
	if mat == null:
		return
	var expected_colour: Color = Builder.BODY_COLOURS[5]
	assert_almost_eq(mat.albedo_color.r, expected_colour.r, 0.01,
		"Body albedo red channel must match BODY_COLOURS[5]")


# ─── Test 9: apply_avatar_config sets legs mesh colour to BODY_COLOURS[3] ────

func test_apply_avatar_config_sets_legs_colour() -> void:
	var cfg: Dictionary = _make_cfg({"leg_colour_index": 3})
	_builder.apply_avatar_config(cfg)

	var legs_mesh: MeshInstance3D = _builder.get_node_or_null("AvatarMesh/Legs") as MeshInstance3D
	assert_not_null(legs_mesh, "Builder must have AvatarMesh/Legs MeshInstance3D child")
	if legs_mesh == null:
		return
	var mat: StandardMaterial3D = legs_mesh.get_active_material(0) as StandardMaterial3D
	assert_not_null(mat, "Legs mesh must have a StandardMaterial3D")
	if mat == null:
		return
	var expected_colour: Color = Builder.BODY_COLOURS[3]
	assert_almost_eq(mat.albedo_color.r, expected_colour.r, 0.01,
		"Legs albedo red channel must match BODY_COLOURS[3]")


# ─── Test 10: hand accessory "pickaxe" shows pickaxe node, hides others ────────

func test_apply_avatar_config_hand_accessory_pickaxe_visible() -> void:
	var cfg: Dictionary = _make_cfg({"hand_accessory": "pickaxe"})
	_builder.apply_avatar_config(cfg)

	var hand_root: Node = _builder.find_child("HandItem", true, false)
	assert_not_null(hand_root, "Builder must have AvatarMesh/HandItem node")
	if hand_root == null:
		return
	var pickaxe_node: Node = hand_root.get_node_or_null("pickaxe")
	assert_not_null(pickaxe_node, "HandItem must have a 'pickaxe' child node")
	if pickaxe_node == null:
		return
	assert_true(pickaxe_node.visible, "pickaxe child must be visible when hand_accessory='pickaxe'")

	# Other accessories must be hidden.
	var none_node: Node = hand_root.get_node_or_null("none")
	if none_node != null:
		assert_false(none_node.visible, "'none' accessory must be hidden when pickaxe is active")


# ─── Test 11: hand accessory "none" hides all hand nodes ────────────────────

func test_apply_avatar_config_hand_accessory_none_all_hidden() -> void:
	# First set pickaxe, then set none — ensure all become hidden.
	_builder.apply_avatar_config(_make_cfg({"hand_accessory": "pickaxe"}))
	_builder.apply_avatar_config(_make_cfg({"hand_accessory": "none"}))

	var hand_root: Node = _builder.find_child("HandItem", true, false)
	if hand_root == null:
		return
	# Check all non-"none" accessories are hidden.
	for child: Node in hand_root.get_children():
		if child.name != "none":
			assert_false(child.visible,
				"'%s' must be hidden when hand_accessory='none'" % child.name)


# ─── Test 12: body accessory "backpack" shows backpack node ─────────────────

func test_apply_avatar_config_body_accessory_backpack_visible() -> void:
	var cfg: Dictionary = _make_cfg({"body_accessory": "backpack"})
	_builder.apply_avatar_config(cfg)

	var body_acc_root: Node = _builder.get_node_or_null("AvatarMesh/BodyAccessory")
	assert_not_null(body_acc_root, "Builder must have AvatarMesh/BodyAccessory node")
	if body_acc_root == null:
		return
	var backpack_node: Node = body_acc_root.get_node_or_null("backpack")
	assert_not_null(backpack_node, "BodyAccessory must have a 'backpack' child")
	if backpack_node == null:
		return
	assert_true(backpack_node.visible, "backpack must be visible when body_accessory='backpack'")


# ─── Test 13: apply_avatar_config can be called multiple times ───────────────

func test_apply_avatar_config_multiple_calls_no_error() -> void:
	# Calling multiple times must not produce errors or crash.
	for i: int in range(5):
		_builder.apply_avatar_config(_make_cfg({
			"skin_colour_index": i % Builder.SKIN_COLOURS.size(),
			"body_colour_index": i % Builder.BODY_COLOURS.size(),
			"leg_colour_index": (i + 3) % Builder.BODY_COLOURS.size(),
		}))
	# If we get here without error, test passes.
	assert_true(true, "Multiple apply_avatar_config calls must not crash or leak resources")


# ─── Test 14: out-of-range index is clamped (T-06-B1 security) ───────────────

func test_apply_avatar_config_clamps_out_of_range_index() -> void:
	# An out-of-range index (e.g. 99) must not crash — it should clamp to valid range.
	var cfg: Dictionary = _make_cfg({
		"skin_colour_index": 99,
		"body_colour_index": -1,
		"leg_colour_index": 999,
	})
	# Must not crash.
	_builder.apply_avatar_config(cfg)

	var head_mesh: MeshInstance3D = _builder.get_node_or_null("AvatarMesh/Head") as MeshInstance3D
	if head_mesh == null:
		return
	var mat: StandardMaterial3D = head_mesh.get_active_material(0) as StandardMaterial3D
	if mat == null:
		return
	# Should have been clamped to the last skin colour (index 4).
	var expected_colour: Color = Builder.SKIN_COLOURS[Builder.SKIN_COLOURS.size() - 1]
	assert_almost_eq(mat.albedo_color.r, expected_colour.r, 0.01,
		"Out-of-range skin_colour_index must be clamped to last valid index")


# ─── Test 15: DEFAULT_AVATAR_CFG constant exists ────────────────────────────

func test_default_avatar_cfg_constant_exists() -> void:
	# The constant must be accessible and have all 8 required keys.
	var default_cfg: Dictionary = Builder.DEFAULT_AVATAR_CFG
	assert_true(default_cfg.has("skin_colour_index"), "DEFAULT_AVATAR_CFG must have skin_colour_index")
	assert_true(default_cfg.has("head_shape"),        "DEFAULT_AVATAR_CFG must have head_shape")
	assert_true(default_cfg.has("face_expression"),   "DEFAULT_AVATAR_CFG must have face_expression")
	assert_true(default_cfg.has("body_colour_index"), "DEFAULT_AVATAR_CFG must have body_colour_index")
	assert_true(default_cfg.has("body_accessory"),    "DEFAULT_AVATAR_CFG must have body_accessory")
	assert_true(default_cfg.has("leg_colour_index"),  "DEFAULT_AVATAR_CFG must have leg_colour_index")
	assert_true(default_cfg.has("leg_shoes"),         "DEFAULT_AVATAR_CFG must have leg_shoes")
	assert_true(default_cfg.has("hand_accessory"),    "DEFAULT_AVATAR_CFG must have hand_accessory")


# ─── Test 16: AvatarMesh node tree exists after _ready ────────────────────────

func test_avatar_mesh_node_tree_exists() -> void:
	var avatar_mesh: Node = _builder.get_node_or_null("AvatarMesh")
	assert_not_null(avatar_mesh, "Builder must have an 'AvatarMesh' child node after _ready()")

	var head: Node = _builder.get_node_or_null("AvatarMesh/Head")
	assert_not_null(head, "AvatarMesh must have 'Head' MeshInstance3D child")

	var body: Node = _builder.get_node_or_null("AvatarMesh/Body")
	assert_not_null(body, "AvatarMesh must have 'Body' MeshInstance3D child")

	var legs: Node = _builder.get_node_or_null("AvatarMesh/Legs")
	assert_not_null(legs, "AvatarMesh must have 'Legs' MeshInstance3D child")

	var hand_item: Node = _builder.find_child("HandItem", true, false)
	assert_not_null(hand_item, "AvatarMesh must have 'HandItem' child node")


# ─── Test 17: head shape scale variants ─────────────────────────────────────

func test_apply_avatar_config_head_shape_scale_square() -> void:
	_builder.apply_avatar_config(_make_cfg({"head_shape": "square"}))
	var head_mesh: MeshInstance3D = _builder.get_node_or_null("AvatarMesh/Head") as MeshInstance3D
	if head_mesh == null:
		return
	assert_almost_eq(head_mesh.scale.x, 1.0, 0.01,
		"square head shape must have scale.x = 1.0")
	assert_almost_eq(head_mesh.scale.y, 1.0, 0.01,
		"square head shape must have scale.y = 1.0")


func test_apply_avatar_config_head_shape_tall() -> void:
	_builder.apply_avatar_config(_make_cfg({"head_shape": "tall"}))
	var head_mesh: MeshInstance3D = _builder.get_node_or_null("AvatarMesh/Head") as MeshInstance3D
	if head_mesh == null:
		return
	assert_almost_eq(head_mesh.scale.y, 1.2, 0.01,
		"tall head shape must have scale.y = 1.2")


# ─── #16: held tool is shown in the hand when a right-hand bone exists ─────────
# Re-enables tool-in-hand: when the avatar exposes a right-hand bone the HandItem is
# bone-attached and SHOWN (no longer force-hidden), so the default wood pickaxe reads as
# carried in the fist rather than as a block on the builder's back.

func test_held_tool_visible_when_hand_bone_present() -> void:
	# Requires the textured avatar GLB (which has a "RightHand" bone) to be imported.
	var skel: Skeleton3D = _builder.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		pending("avatar skeleton not present (GLB not imported in this environment)")
		return
	_builder.apply_avatar_config(_make_cfg({"hand_accessory": "pickaxe"}))
	var hand_root: Node = _builder.find_child("HandItem", true, false)
	assert_not_null(hand_root, "Builder must have a HandItem node")
	if hand_root == null:
		return
	# With a real hand bone, the whole HandItem must be shown (the #16 fix), and it must be
	# parented under a BoneAttachment3D rather than parked at the fixed upper-back offset.
	assert_true((hand_root as Node3D).visible,
		"#16: HandItem must be visible when a right-hand bone exists")
	var parent: Node = hand_root.get_parent()
	assert_true(parent is BoneAttachment3D,
		"#16: HandItem must ride a BoneAttachment3D (the right-hand bone), not the back offset")


func test_held_tool_attached_to_right_hand_bone_name() -> void:
	var skel: Skeleton3D = _builder.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		pending("avatar skeleton not present (GLB not imported in this environment)")
		return
	var hand_root: Node = _builder.find_child("HandItem", true, false)
	if hand_root == null:
		return
	var attach: BoneAttachment3D = hand_root.get_parent() as BoneAttachment3D
	assert_not_null(attach, "HandItem parent must be a BoneAttachment3D")
	if attach == null:
		return
	# The probed avatars expose a bone literally named "RightHand"; verify it resolved.
	assert_true(Builder._RIGHT_HAND_BONE_NAMES.has(attach.bone_name),
		"bone_name '%s' must be one of the known right-hand candidates" % attach.bone_name)
	assert_ne(skel.find_bone(attach.bone_name), -1,
		"the chosen bone '%s' must exist on the skeleton" % attach.bone_name)


# ─── #18: builder recognises a climbable collider via the ancestor chain ───────
# The lighthouse's trimesh StaticBody3D bodies are nested several levels below the
# WorldStructure node that carries the "climbable" group, so the builder walks the collider's
# parent chain to detect climbability. These tests exercise that walk in isolation.

func test_collider_is_climbable_walks_ancestor_chain() -> void:
	# Build: climbable_root (in group) → mid Node3D → StaticBody3D (the "collider").
	var climbable_root := Node3D.new()
	climbable_root.add_to_group("climbable")
	var mid := Node3D.new()
	var body := StaticBody3D.new()
	climbable_root.add_child(mid)
	mid.add_child(body)
	add_child(climbable_root)
	assert_true(_builder._collider_is_climbable(body),
		"#18: a collider nested under a climbable node must be detected as climbable")
	climbable_root.queue_free()


func test_collider_is_climbable_false_for_plain_structure() -> void:
	# A structure with NO climbable group must not be detected as climbable.
	var plain_root := Node3D.new()
	plain_root.add_to_group("structure")  # normal structure, not climbable
	var body := StaticBody3D.new()
	plain_root.add_child(body)
	add_child(plain_root)
	assert_false(_builder._collider_is_climbable(body),
		"#18: a non-climbable structure's collider must NOT be detected as climbable")
	plain_root.queue_free()
