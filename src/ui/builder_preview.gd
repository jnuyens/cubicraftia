# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# builder_preview.gd — recolourable box-minifig preview for the avatar creator.
#
# NOT the in-world Builder: no physics, groups, mouse capture, or sibling lookups.
# It builds a minifig-proportioned figure from BoxMeshes (head, hair, torso, arms,
# hands, legs, accessories) so EVERY customiser swatch visibly changes the preview:
#   skin tone   → head + hands albedo
#   outfit col  → torso + arms (sleeves) albedo
#   hairstyle   → hair silhouette (head_shape token reused as the 3 Kapsel options)
#   accessory   → backpack / cape visibility
# Legs + hair colour are fixed (dark trousers, brown hair) to match the art, whose
# customiser exposes only Skin / Outfit / Hairstyle / Accessory.
#
# The figure is a single fixed size, so all three builder cards preview at the same
# scale (no per-skin size drift). apply_avatar_config(cfg) is the drive point used by
# avatar_creator.gd::_apply_config_to_preview.

extends Node3D

# ─── Palettes (self-contained copies of avatar_creator's swatches) ────────────

## Skin colour swatches (5) — applied to head + hands.
## MUST stay index-identical to avatar_creator.SKIN_COLOURS (swatch ↔ preview mapping).
const SKIN_COLOURS: Array[Color] = [
	Color("#FFD21A"),  # classic builder-figure yellow
	Color("#D4956A"),  # tan
	Color("#A0614A"),  # medium
	Color("#6B3A2A"),  # dark
	Color("#3B1F16"),  # deep
]

## Outfit colour swatches (10) — applied to torso + arms.
## MUST stay index-identical to avatar_creator.BODY_COLOURS.
const BODY_COLOURS: Array[Color] = [
	Color("#C91111"),  # 0 red
	Color("#E8890C"),  # 1 orange
	Color("#F5C30D"),  # 2 yellow
	Color("#97C515"),  # 3 lime
	Color("#3DB560"),  # 4 green
	Color("#159195"),  # 5 teal
	Color("#1B72D8"),  # 6 blue
	Color("#7B2DB5"),  # 7 purple
	Color("#D43582"),  # 8 pink
	Color("#F1F0EA"),  # 9 white
]

## Fixed accents (not swatch-driven; match the painted minifigs).
const LEG_COLOUR: Color = Color("#3A2A1C")   # dark trousers
const HAIR_COLOUR: Color = Color("#6B3F22")  # brown hair
const CAPE_COLOUR: Color = Color("#C0202C")  # red cape

# ─── Part references ──────────────────────────────────────────────────────────

var _head: MeshInstance3D = null
var _hair: MeshInstance3D = null
var _torso: MeshInstance3D = null
var _arm_l: MeshInstance3D = null
var _arm_r: MeshInstance3D = null
var _hand_l: MeshInstance3D = null
var _hand_r: MeshInstance3D = null
var _legs: MeshInstance3D = null   # named "Legs" for the controller's fallback recolour path
var _leg_l: MeshInstance3D = null
var _leg_r: MeshInstance3D = null
var _hips: MeshInstance3D = null
var _backpack: MeshInstance3D = null
var _cape: MeshInstance3D = null

# Aliases the avatar_creator fallback path looks up by name.
var _body_mesh: MeshInstance3D = null  # == _torso
var _head_mesh: MeshInstance3D = null  # == _head
var _legs_mesh: MeshInstance3D = null  # == _hips


func _ready() -> void:
	_build_figure()


# ─── Build ────────────────────────────────────────────────────────────────────

func _box(name: String, size: Vector3, pos: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	mi.set_surface_override_material(0, mat)
	add_child(mi)
	return mi


## Build the minifig. Origin at the feet; the figure is ~2.0 units tall.
func _build_figure() -> void:
	var skin: Color = SKIN_COLOURS[0]
	var body: Color = BODY_COLOURS[6]  # default blue

	# Legs (two trousers) + hips.
	_leg_l = _box("LegL", Vector3(0.26, 0.55, 0.30), Vector3(-0.14, 0.28, 0.0), LEG_COLOUR)
	_leg_r = _box("LegR", Vector3(0.26, 0.55, 0.30), Vector3(0.14, 0.28, 0.0), LEG_COLOUR)
	_hips = _box("Legs", Vector3(0.56, 0.22, 0.32), Vector3(0.0, 0.66, 0.0), LEG_COLOUR)

	# Torso + arms (outfit colour) and yellow/skin hands.
	_torso = _box("Body", Vector3(0.62, 0.62, 0.34), Vector3(0.0, 1.08, 0.0), body)
	_arm_l = _box("ArmL", Vector3(0.18, 0.56, 0.22), Vector3(-0.40, 1.10, 0.02), body)
	_arm_r = _box("ArmR", Vector3(0.18, 0.56, 0.22), Vector3(0.40, 1.10, 0.02), body)
	_hand_l = _box("HandL", Vector3(0.17, 0.17, 0.17), Vector3(-0.40, 0.80, 0.06), skin)
	_hand_r = _box("HandR", Vector3(0.17, 0.17, 0.17), Vector3(0.40, 0.80, 0.06), skin)

	# Head + hair (hair = top cap + front fringe).
	_head = _box("Head", Vector3(0.52, 0.52, 0.52), Vector3(0.0, 1.66, 0.0), skin)
	_hair = _box("Hair", Vector3(0.60, 0.22, 0.60), Vector3(0.0, 1.96, 0.0), HAIR_COLOUR)
	var fringe := _box("HairFringe", Vector3(0.54, 0.16, 0.10), Vector3(0.0, 1.84, 0.23), HAIR_COLOUR)
	fringe.set_meta("hair", true)

	# Face on the +Z front (defines the front and gives the figure character).
	var eye := Color("#241A12")
	_box("EyeL", Vector3(0.08, 0.10, 0.03), Vector3(-0.12, 1.71, 0.27), eye)
	_box("EyeR", Vector3(0.08, 0.10, 0.03), Vector3(0.12, 1.71, 0.27), eye)
	_box("Mouth", Vector3(0.18, 0.04, 0.03), Vector3(0.0, 1.57, 0.27), Color("#7A2A1E"))

	# Accessories (hidden by default).
	_backpack = _box("Backpack", Vector3(0.42, 0.48, 0.18), Vector3(0.0, 1.06, -0.26), Color("#7A5230"))
	_backpack.visible = false
	_cape = _box("Cape", Vector3(0.58, 0.82, 0.05), Vector3(0.0, 0.98, -0.22), CAPE_COLOUR)
	_cape.visible = false

	# Name aliases for the controller fallback path.
	_body_mesh = _torso
	_head_mesh = _head
	_legs_mesh = _hips


# ─── Public API ───────────────────────────────────────────────────────────────

## Apply avatar config to the preview. Null-safe; unknown indices are clamped.
func apply_avatar_config(cfg: Dictionary) -> void:
	# Skin → head + hands.
	var skin_idx: int = clampi(int(cfg.get("skin_colour_index", 0)), 0, SKIN_COLOURS.size() - 1)
	var skin: Color = SKIN_COLOURS[skin_idx]
	_set_colour(_head, skin)
	_set_colour(_hand_l, skin)
	_set_colour(_hand_r, skin)

	# Outfit → torso + arms.
	var body_idx: int = clampi(int(cfg.get("body_colour_index", 4)), 0, BODY_COLOURS.size() - 1)
	var body: Color = BODY_COLOURS[body_idx]
	_set_colour(_torso, body)
	_set_colour(_arm_l, body)
	_set_colour(_arm_r, body)

	# Hairstyle (reuses the head_shape token for the 3 Kapsel options).
	_apply_hairstyle(str(cfg.get("head_shape", "square")))

	# Accessory.
	var acc: String = str(cfg.get("body_accessory", "none"))
	if _backpack != null:
		_backpack.visible = (acc == "backpack")
	if _cape != null:
		_cape.visible = (acc == "cape")


## Set a mesh's override-material albedo (null-safe).
func _set_colour(mi: MeshInstance3D, colour: Color) -> void:
	if mi == null:
		return
	var mat: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
	if mat != null:
		mat.albedo_color = colour


## Reshape the hair block for the three Kapsel options.
func _apply_hairstyle(style: String) -> void:
	if _hair == null:
		return
	var mesh: BoxMesh = _hair.mesh as BoxMesh
	if mesh == null:
		return
	match style:
		"round":  # rounded / fuller bob — wider, lower
			mesh.size = Vector3(0.64, 0.30, 0.64)
			_hair.position.y = 1.92
		"tall":   # spiky / tall — taller, narrower
			mesh.size = Vector3(0.56, 0.40, 0.56)
			_hair.position.y = 2.02
		_:        # "square" — short flat cap
			mesh.size = Vector3(0.60, 0.20, 0.60)
			_hair.position.y = 1.96
