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
var _satchel: Node3D = null      # Explorer signature
var _bandolier: Node3D = null    # Pathfinder signature
var _mustache: MeshInstance3D = null   # Pathfinder face
var _goatee: Node3D = null             # Explorer face
var _scarf: MeshInstance3D = null      # Forester neck scarf
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

## Build a wide open-gap C-claw hand from chunky voxels (gap at the top, where a
## tool would sit). Reads as a minifig C-hand rather than a closed ring.
func _build_claw(nm: String, center: Vector3, colour: Color) -> void:
	var r := 0.16
	var seg := 10
	for i in seg:
		var a := TAU * float(i) / float(seg)
		var deg := rad_to_deg(a)
		# Open gap at the BOTTOM (claw opening downward); the arm meets the closed top.
		if deg > 205.0 and deg < 335.0:
			continue
		var px := center.x + cos(a) * r
		var py := center.y + sin(a) * r
		var b := _box(self, "%s_%d" % [nm, i], Vector3(0.11, 0.11, 0.20), Vector3(px, py, center.z), colour)
		_skin_parts.append(b)

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
	# Leg detail: lighter knee panels + a centre seam between the legs.
	_box(self, "KneeL", Vector3(0.20, 0.12, 0.02), Vector3(-0.145, 0.34, 0.16), LEG_COLOUR.lightened(0.12))
	_box(self, "KneeR", Vector3(0.20, 0.12, 0.02), Vector3(0.145, 0.34, 0.16), LEG_COLOUR.lightened(0.12))
	_box(self, "LegGap", Vector3(0.03, 0.58, 0.30), Vector3(0.0, 0.31, 0.0), Color("#15151A"))
	# Shoe toe caps + soles.
	_box(self, "ToeL", Vector3(0.27, 0.07, 0.10), Vector3(-0.145, 0.06, 0.21), Color("#0F0F14"))
	_box(self, "ToeR", Vector3(0.27, 0.07, 0.10), Vector3(0.145, 0.06, 0.21), Color("#0F0F14"))
	_box(self, "SoleL", Vector3(0.28, 0.03, 0.36), Vector3(-0.145, 0.005, 0.02), Color("#444"))
	_box(self, "SoleR", Vector3(0.28, 0.03, 0.36), Vector3(0.145, 0.005, 0.02), Color("#444"))

	# ── Torso (trapezoid: narrow chest box + wider waist box) ─────────────────
	var chest := _box(self, "Chest", Vector3(0.58, 0.40, 0.34), Vector3(0.0, 1.18, 0.0), outfit)
	var waist := _box(self, "Waist", Vector3(0.64, 0.26, 0.345), Vector3(0.0, 0.93, 0.0), outfit)
	_outfit_parts.append(chest)
	_outfit_parts.append(waist)
	# Collar (V-neck) + chest seam + belt + gold buckle (fixed trim).
	_box(self, "Collar", Vector3(0.26, 0.08, 0.36), Vector3(0.0, 1.39, 0.01), Color("#FFFFFF").lerp(outfit, 0.35))
	_box(self, "Belt", Vector3(0.66, 0.07, 0.355), Vector3(0.0, 0.84, 0.0), BELT_COLOUR)
	_box(self, "Buckle", Vector3(0.10, 0.07, 0.02), Vector3(0.0, 0.84, 0.18), BUCKLE_COLOUR)
	_box(self, "Seam", Vector3(0.02, 0.45, 0.02), Vector3(0.0, 1.16, 0.175), BELT_COLOUR)
	# Chest detail: two flap pockets, a row of gold buttons, collar lapels.
	_box(self, "PocketL", Vector3(0.15, 0.12, 0.02), Vector3(-0.16, 1.02, 0.175), BELT_COLOUR)
	_box(self, "PocketR", Vector3(0.15, 0.12, 0.02), Vector3(0.16, 1.02, 0.175), BELT_COLOUR)
	_box(self, "BtnA", Vector3(0.035, 0.035, 0.02), Vector3(0.0, 1.30, 0.18), BUCKLE_COLOUR)
	_box(self, "BtnB", Vector3(0.035, 0.035, 0.02), Vector3(0.0, 1.18, 0.18), BUCKLE_COLOUR)
	_box(self, "BtnC", Vector3(0.035, 0.035, 0.02), Vector3(0.0, 1.06, 0.18), BUCKLE_COLOUR)
	_box(self, "LapelL", Vector3(0.08, 0.17, 0.02), Vector3(-0.10, 1.29, 0.175), Color("#FFFFFF").lerp(outfit, 0.5), Vector3(0, 0, deg_to_rad(-16)))
	_box(self, "LapelR", Vector3(0.08, 0.17, 0.02), Vector3(0.10, 1.29, 0.175), Color("#FFFFFF").lerp(outfit, 0.5), Vector3(0, 0, deg_to_rad(16)))

	# ── Shoulders + arms (angled) + C-claw hands ──────────────────────────────
	var sh_l := _box(self, "ShoulderL", Vector3(0.20, 0.22, 0.28), Vector3(-0.37, 1.30, 0.0), outfit)
	var sh_r := _box(self, "ShoulderR", Vector3(0.20, 0.22, 0.28), Vector3(0.37, 1.30, 0.0), outfit)
	var arm_l := _box(self, "ArmL", Vector3(0.18, 0.46, 0.22), Vector3(-0.42, 1.02, 0.04), outfit, Vector3(0, 0, deg_to_rad(8)))
	var arm_r := _box(self, "ArmR", Vector3(0.18, 0.46, 0.22), Vector3(0.42, 1.02, 0.04), outfit, Vector3(0, 0, deg_to_rad(-8)))
	_outfit_parts.append_array([sh_l, sh_r, arm_l, arm_r])
	# Sleeve cuffs (slightly darker outfit) then wide open-gap C-claw hands.
	var cuff_l := _box(self, "CuffL", Vector3(0.20, 0.08, 0.24), Vector3(-0.42, 0.86, 0.04), outfit.darkened(0.18), Vector3(0, 0, deg_to_rad(8)))
	var cuff_r := _box(self, "CuffR", Vector3(0.20, 0.08, 0.24), Vector3(0.42, 0.86, 0.04), outfit.darkened(0.18), Vector3(0, 0, deg_to_rad(-8)))
	_outfit_parts.append_array([cuff_l, cuff_r])
	_build_claw("HandL", Vector3(-0.45, 0.74, 0.10), skin)
	_build_claw("HandR", Vector3(0.45, 0.74, 0.10), skin)

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
	# Brows: nearly flat with inner ends slightly RAISED (friendly, not angry).
	_box(self, "BrowL", Vector3(0.16, 0.05, 0.025), Vector3(-0.12, 1.935, fz + 0.005), HAIR_SHADE, Vector3(0, 0, deg_to_rad(7)))
	_box(self, "BrowR", Vector3(0.16, 0.05, 0.025), Vector3(0.12, 1.935, fz + 0.005), HAIR_SHADE, Vector3(0, 0, deg_to_rad(-7)))
	# Happy open smile: a thin red mouth + white teeth above a dark smile curve whose
	# corners turn up. No tongue (keeps it clean and cheerful).
	_box(self, "Teeth", Vector3(0.18, 0.045, 0.02), Vector3(0.0, 1.675, fz + 0.014), EYE_WHITE)
	_box(self, "MouthRed", Vector3(0.16, 0.035, 0.02), Vector3(0.0, 1.642, fz + 0.008), MOUTH_RED)
	_box(self, "LipC", Vector3(0.16, 0.04, 0.022), Vector3(0.0, 1.615, fz), MOUTH_DARK)
	_box(self, "SmileL", Vector3(0.10, 0.042, 0.022), Vector3(-0.115, 1.645, fz), MOUTH_DARK, Vector3(0, 0, deg_to_rad(38)))
	_box(self, "SmileR", Vector3(0.10, 0.042, 0.022), Vector3(0.115, 1.645, fz), MOUTH_DARK, Vector3(0, 0, deg_to_rad(-38)))
	# Rosy cheeks for a warmer, happier read.
	_box(self, "CheekL", Vector3(0.07, 0.05, 0.02), Vector3(-0.20, 1.70, fz - 0.005), Color("#F0A24A"))
	_box(self, "CheekR", Vector3(0.07, 0.05, 0.02), Vector3(0.20, 1.70, fz - 0.005), Color("#F0A24A"))

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

	# ── Per-builder signature gear (toggled by character) ─────────────────────
	# Explorer: a single satchel strap across the chest + a hip pouch.
	_satchel = Node3D.new()
	_satchel.name = "Satchel"
	add_child(_satchel)
	_box(_satchel, "Strap", Vector3(0.07, 0.78, 0.03), Vector3(0.0, 1.08, 0.185), STRAP_COLOUR, Vector3(0, 0, deg_to_rad(33)))
	_box(_satchel, "Pouch", Vector3(0.20, 0.18, 0.12), Vector3(0.26, 0.86, 0.16), Color("#6B4A28"))
	_satchel.visible = false
	# Pathfinder: a crossed X bandolier.
	_bandolier = Node3D.new()
	_bandolier.name = "Bandolier"
	add_child(_bandolier)
	_box(_bandolier, "StrapA", Vector3(0.07, 0.80, 0.03), Vector3(0.0, 1.08, 0.185), STRAP_COLOUR, Vector3(0, 0, deg_to_rad(33)))
	_box(_bandolier, "StrapB", Vector3(0.07, 0.80, 0.03), Vector3(0.0, 1.08, 0.185), STRAP_COLOUR, Vector3(0, 0, deg_to_rad(-33)))
	_box(_bandolier, "BuckleX", Vector3(0.09, 0.09, 0.03), Vector3(0.0, 1.08, 0.2), BUCKLE_COLOUR)
	_bandolier.visible = false

	# ── Ears (skin) peeking past the sideburns ────────────────────────────────
	var ear_l := _box(self, "EarL", Vector3(0.055, 0.13, 0.11), Vector3(-0.278, 1.74, 0.03), skin)
	var ear_r := _box(self, "EarR", Vector3(0.055, 0.13, 0.11), Vector3(0.278, 1.74, 0.03), skin)
	_skin_parts.append_array([ear_l, ear_r])

	# ── Jacket zipper pull (gold) below the collar ────────────────────────────
	_box(self, "Zipper", Vector3(0.03, 0.07, 0.02), Vector3(0.0, 1.33, 0.185), BUCKLE_COLOUR)

	# ── Per-character face details (toggled by _apply_face) ───────────────────
	var fz2 := 0.255
	_mustache = _box(self, "Mustache", Vector3(0.20, 0.05, 0.03), Vector3(0.0, 1.71, fz2), HAIR_SHADE)
	_mustache.visible = false
	_goatee = Node3D.new()
	_goatee.name = "Goatee"
	add_child(_goatee)
	_box(_goatee, "Chin", Vector3(0.14, 0.09, 0.04), Vector3(0.0, 1.55, fz2 - 0.005), HAIR_SHADE)
	_box(_goatee, "Jaw", Vector3(0.30, 0.06, 0.30), Vector3(0.0, 1.56, 0.0), HAIR_SHADE)
	_goatee.visible = false
	# Forester neck scarf (wraps the neck).
	_scarf = _box(self, "Scarf", Vector3(0.40, 0.12, 0.40), Vector3(0.0, 1.46, 0.0), Color("#C9483A"))
	_scarf.visible = false


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
	# Density: angled fringe tufts + layered side locks on every style.
	_box(h, "TuftFL", Vector3(0.14, 0.13, 0.12), Vector3(-0.16, 2.13, 0.11), HAIR_COLOUR, Vector3(deg_to_rad(-24), 0, deg_to_rad(-10)))
	_box(h, "TuftFR", Vector3(0.14, 0.13, 0.12), Vector3(0.16, 2.13, 0.11), HAIR_COLOUR, Vector3(deg_to_rad(-24), 0, deg_to_rad(10)))
	_box(h, "LockL", Vector3(0.09, 0.12, 0.30), Vector3(-0.30, 1.98, -0.04), HAIR_SHADE, Vector3(0, 0, deg_to_rad(16)))
	_box(h, "LockR", Vector3(0.09, 0.12, 0.30), Vector3(0.30, 1.98, -0.04), HAIR_SHADE, Vector3(0, 0, deg_to_rad(-16)))
	_box(h, "Nape", Vector3(0.44, 0.14, 0.08), Vector3(0.0, 1.66, -0.255), HAIR_SHADE)
	_box(h, "CrownL", Vector3(0.13, 0.15, 0.18), Vector3(-0.13, 2.15, -0.03), HAIR_COLOUR, Vector3(deg_to_rad(-10), 0, deg_to_rad(-7)))
	_box(h, "CrownR", Vector3(0.13, 0.15, 0.18), Vector3(0.13, 2.15, -0.03), HAIR_COLOUR, Vector3(deg_to_rad(-10), 0, deg_to_rad(7)))
	_box(h, "CrownM", Vector3(0.12, 0.14, 0.18), Vector3(0.0, 2.16, -0.10), HAIR_SHADE, Vector3(deg_to_rad(-6), 0, 0))
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

	var character: String = str(cfg.get("character", ""))
	_apply_signature(character)
	_apply_face(character)


## Show the chosen builder's signature gear (Explorer satchel / Pathfinder bandolier;
## Forester wears neither). Makes the three cards visibly distinct beyond jacket colour.
func _apply_signature(character: String) -> void:
	if _satchel != null:
		_satchel.visible = (character == "builder1")
	if _bandolier != null:
		_bandolier.visible = (character == "red")


## Give each builder a distinct face: Pathfinder a moustache, Explorer a stubbled
## jaw/goatee, Forester a clean face + red neck scarf.
func _apply_face(character: String) -> void:
	if _mustache != null:
		_mustache.visible = (character == "red")
	if _goatee != null:
		_goatee.visible = (character == "builder1")
	if _scarf != null:
		_scarf.visible = (character == "fem")


func _recolour(mi: MeshInstance3D, colour: Color) -> void:
	if mi == null:
		return
	var m: StandardMaterial3D = mi.get_active_material(0) as StandardMaterial3D
	if m != null:
		m.albedo_color = colour
