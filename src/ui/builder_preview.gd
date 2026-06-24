# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# builder_preview.gd — detailed recolourable box-minifig preview for the avatar creator.
#
# A blocky voxel-LEGO minifig assembled from primitives, tuned to read like the
# painted card art: printed face (white eyes + pupils, angled brows, open grin),
# spiky brown hair with a fringe, a trapezoidal jacket torso (collar, belt + gold
# buckle), angled sleeved arms with C-claw hands, and dark legs. Every customiser
# swatch drives it live:
#   skin tone  → head + hands (+ neck)
#   outfit col → jacket torso + sleeves + shoulders
#   hairstyle  → hair silhouette (3 Kapsel options)
#   accessory  → backpack / cape
# Legs, hair, face and trim are fixed accents (the art's customiser only exposes
# Skin / Outfit / Hairstyle / Accessory). One fixed size → all builders preview
# at the same scale. apply_avatar_config(cfg) is the drive point.

extends Node3D

# ─── Palettes (index-identical to avatar_creator's swatches) ──────────────────

const SKIN_COLOURS: Array[Color] = [
	Color("#FFD21A"), Color("#D4956A"), Color("#A0614A"), Color("#6B3A2A"), Color("#3B1F16"),
]
const BODY_COLOURS: Array[Color] = [
	Color("#C91111"), Color("#E8890C"), Color("#F5C30D"), Color("#97C515"), Color("#3DB560"),
	Color("#159195"), Color("#1B72D8"), Color("#7B2DB5"), Color("#D43582"), Color("#F1F0EA"),
]

# Fixed accents.
const LEG_COLOUR := Color("#2B2B33")     # dark trousers
const HAIR_COLOUR := Color("#6E4326")    # brown hair
const HAIR_SHADE := Color("#5A3520")     # darker hair (depth)
const BELT_COLOUR := Color("#3A2A1C")
const BUCKLE_COLOUR := Color("#E8B23A")
const STRAP_COLOUR := Color("#4A3420")  # brown strap
const CAPE_COLOUR := Color("#C0202C")
const EYE_WHITE := Color("#F7F7F2")
const EYE_DARK := Color("#241A12")
const MOUTH_DARK := Color("#3A1410")
const MOUTH_RED := Color("#C44233")

# ─── Part groups (recoloured in apply_avatar_config) ──────────────────────────

var _skin_parts: Array[MeshInstance3D] = []
var _outfit_parts: Array[MeshInstance3D] = []
var _hair_root: Node3D = null
var _backpack: Node3D = null
var _cape: MeshInstance3D = null
var _cur_hair := ""


func _ready() -> void:
	_build()


# ─── Primitive helpers ────────────────────────────────────────────────────────

func _mat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.85
	return m

func _box(p: Node, nm: String, size: Vector3, pos: Vector3, colour: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	mi.set_surface_override_material(0, _mat(colour))
	p.add_child(mi)
	return mi

func _torus(p: Node, nm: String, inner: float, outer: float, pos: Vector3, colour: Color, rot: Vector3) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 12
	mesh.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.set_surface_override_material(0, _mat(colour))
	p.add_child(mi)
	return mi


# ─── Build ────────────────────────────────────────────────────────────────────

func _build() -> void:
	var skin := SKIN_COLOURS[0]
	var outfit := BODY_COLOURS[6]

	# ── Legs + hips ───────────────────────────────────────────────────────────
	_box(self, "LegL", Vector3(0.26, 0.62, 0.30), Vector3(-0.145, 0.31, 0.0), LEG_COLOUR)
	_box(self, "LegR", Vector3(0.26, 0.62, 0.30), Vector3(0.145, 0.31, 0.0), LEG_COLOUR)
	_box(self, "FootL", Vector3(0.27, 0.10, 0.34), Vector3(-0.145, 0.05, 0.02), Color("#1C1C22"))
	_box(self, "FootR", Vector3(0.27, 0.10, 0.34), Vector3(0.145, 0.05, 0.02), Color("#1C1C22"))
	_box(self, "Hips", Vector3(0.56, 0.20, 0.32), Vector3(0.0, 0.72, 0.0), LEG_COLOUR)

	# ── Torso (trapezoid: narrow chest box + wider waist box) ─────────────────
	var chest := _box(self, "Chest", Vector3(0.58, 0.40, 0.34), Vector3(0.0, 1.18, 0.0), outfit)
	var waist := _box(self, "Waist", Vector3(0.64, 0.26, 0.345), Vector3(0.0, 0.93, 0.0), outfit)
	_outfit_parts.append(chest)
	_outfit_parts.append(waist)
	# Collar (V-neck) + chest seam + belt + gold buckle (fixed trim).
	_box(self, "Collar", Vector3(0.30, 0.10, 0.36), Vector3(0.0, 1.38, 0.01), Color("#FFFFFF").lerp(outfit, 0.2))
	_box(self, "Belt", Vector3(0.66, 0.07, 0.355), Vector3(0.0, 0.84, 0.0), BELT_COLOUR)
	_box(self, "Buckle", Vector3(0.10, 0.07, 0.02), Vector3(0.0, 0.84, 0.18), BUCKLE_COLOUR)
	_box(self, "Seam", Vector3(0.02, 0.45, 0.02), Vector3(0.0, 1.16, 0.175), BELT_COLOUR)

	# ── Shoulders + arms (angled) + C-claw hands ──────────────────────────────
	var sh_l := _box(self, "ShoulderL", Vector3(0.20, 0.22, 0.28), Vector3(-0.37, 1.30, 0.0), outfit)
	var sh_r := _box(self, "ShoulderR", Vector3(0.20, 0.22, 0.28), Vector3(0.37, 1.30, 0.0), outfit)
	var arm_l := _box(self, "ArmL", Vector3(0.18, 0.46, 0.22), Vector3(-0.42, 1.02, 0.04), outfit, Vector3(0, 0, deg_to_rad(8)))
	var arm_r := _box(self, "ArmR", Vector3(0.18, 0.46, 0.22), Vector3(0.42, 1.02, 0.04), outfit, Vector3(0, 0, deg_to_rad(-8)))
	_outfit_parts.append_array([sh_l, sh_r, arm_l, arm_r])
	var hand_l := _torus(self, "HandL", 0.045, 0.12, Vector3(-0.45, 0.78, 0.08), skin, Vector3(deg_to_rad(90), 0, 0))
	var hand_r := _torus(self, "HandR", 0.045, 0.12, Vector3(0.45, 0.78, 0.08), skin, Vector3(deg_to_rad(90), 0, 0))
	_skin_parts.append_array([hand_l, hand_r])

	# ── Neck + head ───────────────────────────────────────────────────────────
	var neck := _box(self, "Neck", Vector3(0.22, 0.10, 0.22), Vector3(0.0, 1.46, 0.0), skin)
	var head := _box(self, "Head", Vector3(0.52, 0.54, 0.50), Vector3(0.0, 1.78, 0.0), skin)
	_skin_parts.append_array([neck, head])

	# ── Face (printed on +Z, fixed colours) ───────────────────────────────────
	var fz := 0.255
	_box(self, "EyeWL", Vector3(0.12, 0.15, 0.02), Vector3(-0.12, 1.84, fz), EYE_WHITE)
	_box(self, "EyeWR", Vector3(0.12, 0.15, 0.02), Vector3(0.12, 1.84, fz), EYE_WHITE)
	_box(self, "PupL", Vector3(0.06, 0.11, 0.02), Vector3(-0.105, 1.83, fz + 0.012), EYE_DARK)
	_box(self, "PupR", Vector3(0.06, 0.11, 0.02), Vector3(0.105, 1.83, fz + 0.012), EYE_DARK)
	# Brows sit just above the eyes, clear of the fringe, angled for a friendly look.
	_box(self, "BrowL", Vector3(0.16, 0.05, 0.025), Vector3(-0.12, 1.935, fz + 0.005), HAIR_SHADE, Vector3(0, 0, deg_to_rad(-10)))
	_box(self, "BrowR", Vector3(0.16, 0.05, 0.025), Vector3(0.12, 1.935, fz + 0.005), HAIR_SHADE, Vector3(0, 0, deg_to_rad(10)))
	# Open grin: dark mouth, red interior, white teeth.
	_box(self, "Mouth", Vector3(0.21, 0.10, 0.02), Vector3(0.0, 1.66, fz), MOUTH_DARK)
	_box(self, "MouthRed", Vector3(0.15, 0.055, 0.02), Vector3(0.0, 1.648, fz + 0.012), MOUTH_RED)
	_box(self, "Teeth", Vector3(0.15, 0.03, 0.02), Vector3(0.0, 1.69, fz + 0.012), EYE_WHITE)

	# ── Hair (rebuilt per style) ──────────────────────────────────────────────
	_hair_root = Node3D.new()
	_hair_root.name = "Hair"
	add_child(_hair_root)
	_apply_hairstyle("square")

	# ── Accessories ───────────────────────────────────────────────────────────
	_backpack = Node3D.new()
	_backpack.name = "Backpack"
	add_child(_backpack)
	_box(_backpack, "Pack", Vector3(0.42, 0.50, 0.20), Vector3(0.0, 1.12, -0.28), Color("#7A5230"))
	_box(_backpack, "PackLid", Vector3(0.44, 0.14, 0.22), Vector3(0.0, 1.32, -0.28), Color("#62421F"))
	_box(_backpack, "PackStrapL", Vector3(0.05, 0.42, 0.02), Vector3(-0.16, 1.18, 0.18), STRAP_COLOUR)
	_box(_backpack, "PackStrapR", Vector3(0.05, 0.42, 0.02), Vector3(0.16, 1.18, 0.18), STRAP_COLOUR)
	_backpack.visible = false
	_cape = _box(self, "Cape", Vector3(0.60, 0.90, 0.04), Vector3(0.0, 1.05, -0.24), CAPE_COLOUR, Vector3(deg_to_rad(4), 0, 0))
	_cape.visible = false


## Rebuild the hair cluster for the chosen Kapsel option.
func _apply_hairstyle(style: String) -> void:
	if _hair_root == null:
		return
	_cur_hair = style
	for c in _hair_root.get_children():
		c.queue_free()
	var h := _hair_root
	# Common base: cap + fringe + sideburns framing the head (head top ~2.05).
	_box(h, "Cap", Vector3(0.56, 0.16, 0.54), Vector3(0.0, 2.07, 0.0), HAIR_COLOUR)
	_box(h, "Fringe", Vector3(0.54, 0.11, 0.10), Vector3(0.0, 2.03, 0.235), HAIR_COLOUR)
	_box(h, "SideL", Vector3(0.08, 0.34, 0.46), Vector3(-0.27, 1.86, 0.0), HAIR_COLOUR)
	_box(h, "SideR", Vector3(0.08, 0.34, 0.46), Vector3(0.27, 1.86, 0.0), HAIR_COLOUR)
	_box(h, "Back", Vector3(0.50, 0.30, 0.10), Vector3(0.0, 1.86, -0.255), HAIR_COLOUR)
	match style:
		"round":  # fuller, rounded — lower side volume, soft top
			_box(h, "TopR", Vector3(0.48, 0.16, 0.46), Vector3(0.0, 2.16, -0.02), HAIR_SHADE)
			_box(h, "SideLo_L", Vector3(0.10, 0.16, 0.40), Vector3(-0.29, 1.66, 0.0), HAIR_COLOUR)
			_box(h, "SideLo_R", Vector3(0.10, 0.16, 0.40), Vector3(0.29, 1.66, 0.0), HAIR_COLOUR)
		"tall":   # spiky, tall tufts
			for i in 5:
				var x := -0.20 + 0.10 * float(i)
				var hh := 0.22 + 0.06 * float(i % 2)
				_box(h, "Spike%d" % i, Vector3(0.09, hh, 0.10), Vector3(x, 2.14 + hh * 0.4, -0.02 + 0.04 * float(i % 2)), HAIR_COLOUR, Vector3(deg_to_rad(-12 + 6 * i), 0, 0))
		_:        # "square" — short spiky fringe (matches the art's explorer)
			for i in 4:
				var x := -0.18 + 0.12 * float(i)
				_box(h, "Tuft%d" % i, Vector3(0.11, 0.18, 0.12), Vector3(x, 2.12, 0.16), HAIR_COLOUR, Vector3(deg_to_rad(-22), 0, deg_to_rad(-8 + 5 * i)))
			_box(h, "TopFlat", Vector3(0.50, 0.10, 0.40), Vector3(0.0, 2.13, -0.05), HAIR_SHADE)


# ─── Public API ───────────────────────────────────────────────────────────────

func apply_avatar_config(cfg: Dictionary) -> void:
	var skin_idx: int = clampi(int(cfg.get("skin_colour_index", 0)), 0, SKIN_COLOURS.size() - 1)
	var skin: Color = SKIN_COLOURS[skin_idx]
	for mi in _skin_parts:
		_recolour(mi, skin)

	var body_idx: int = clampi(int(cfg.get("body_colour_index", 6)), 0, BODY_COLOURS.size() - 1)
	var outfit: Color = BODY_COLOURS[body_idx]
	for mi in _outfit_parts:
		_recolour(mi, outfit)
	# Keep the collar a tinted-light shade of the new outfit.
	var collar: Node = get_node_or_null("Collar")
	if collar is MeshInstance3D:
		_recolour(collar, Color("#FFFFFF").lerp(outfit, 0.2))

	var style: String = str(cfg.get("head_shape", "square"))
	if style != _cur_hair:
		_apply_hairstyle(style)

	var acc: String = str(cfg.get("body_accessory", "none"))
	if _backpack != null:
		_backpack.visible = (acc == "backpack")
	if _cape != null:
		_cape.visible = (acc == "cape")


func _recolour(mi: MeshInstance3D, colour: Color) -> void:
	if mi == null:
		return
	var m: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
	if m != null:
		m.albedo_color = colour
