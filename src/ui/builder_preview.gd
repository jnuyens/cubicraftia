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
const LEG_COLOUR := Color("#1B2747")     # navy trousers (matches the hero art)
const HAIR_COLOUR := Color("#6E4326")    # default brown hair
const HAIR_SHADE := Color("#5A3520")     # darker hair (depth)

## Hair colour swatches (index-identical to avatar_creator.HAIR_COLOURS).
const HAIR_COLOURS: Array[Color] = [
	Color("#6E4326"),  # brown
	Color("#2B2118"),  # black
	Color("#C9A24B"),  # blonde
	Color("#8E3B1E"),  # auburn
	Color("#9A9A9A"),  # grey
	Color("#E8E2D0"),  # white/platinum
]
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
## Current hair colour + the non-hair-root parts that follow it (brows, facial hair).
var _hair_colour: Color = HAIR_COLOURS[0]
var _hair_shade_parts: Array[MeshInstance3D] = []

## Animation pivots (legs/arms swing from these) + procedural-animation state.
var _leg_l_pivot: Node3D = null
var _leg_r_pivot: Node3D = null
var _arm_l_pivot: Node3D = null
var _arm_r_pivot: Node3D = null
var _anim_phase: float = 0.0
var _walk_blend: float = 0.0
var _grounded: bool = true
## Off in the creator (clean idle stand); the in-world Builder turns it on + drives it.
var _animate: bool = false


func _ready() -> void:
	_build()


## Drive the procedural walk/idle/jump from the in-world Builder each frame.
##   h_speed : horizontal speed (m/s); 0 = idle.
##   grounded: false → jump/airborne pose.
func set_locomotion(h_speed: float, grounded: bool) -> void:
	_animate = true
	_walk_blend = clampf(h_speed / 2.5, 0.0, 1.0)
	_grounded = grounded


func _process(delta: float) -> void:
	if not _animate:
		return
	if not _grounded:
		# Airborne: legs split, arms raised.
		_set_pivot(_leg_l_pivot, 0.5)
		_set_pivot(_leg_r_pivot, -0.3)
		_set_pivot(_arm_l_pivot, -0.9)
		_set_pivot(_arm_r_pivot, -0.9)
		return
	_anim_phase += delta * (5.0 + _walk_blend * 8.0)
	var swing: float = sin(_anim_phase) * (0.04 + _walk_blend * 0.55)
	_set_pivot(_leg_l_pivot, swing)
	_set_pivot(_leg_r_pivot, -swing)
	_set_pivot(_arm_l_pivot, -swing * 0.85)
	_set_pivot(_arm_r_pivot, swing * 0.85)


func _set_pivot(p: Node3D, x_rot: float) -> void:
	if p != null:
		p.rotation.x = x_rot


# ─── Primitive helpers ────────────────────────────────────────────────────────

func _mat(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.85
	return m

## Target voxel edge length: every part is rebuilt from a grid of cubes this size
## (≈100× the old single-box count) for a fine voxel look. Cached by size so identical
## parts (legs L/R, etc.) share one mesh.
const _VOXEL_CUBE: float = 0.085
var _voxel_cache: Dictionary = {}
var _vox_placeholder: StandardMaterial3D = null


## A part is ONE MeshInstance3D (material + pivots unchanged) whose mesh is a voxel
## grid of small cubes, so recolouring and animation keep working as before.
func _box(p: Node, nm: String, size: Vector3, pos: Vector3, colour: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = _voxel_mesh(size)
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation = rot
	mi.set_surface_override_material(0, _mat(colour))
	p.add_child(mi)
	return mi


## Build (and cache) a voxelised box: a shell of small cubes filling `size`, with small
## gaps between them (SSAO settles into the seams) and the 8 corners shaved for a rounded,
## less-blocky silhouette. Tiny parts (≤1 cube) fall back to a plain BoxMesh.
func _voxel_mesh(size: Vector3) -> Mesh:
	var key: String = "%0.3f_%0.3f_%0.3f" % [size.x, size.y, size.z]
	if _voxel_cache.has(key):
		return _voxel_cache[key]
	var nx: int = maxi(1, int(round(size.x / _VOXEL_CUBE)))
	var ny: int = maxi(1, int(round(size.y / _VOXEL_CUBE)))
	var nz: int = maxi(1, int(round(size.z / _VOXEL_CUBE)))
	# Small detail parts (eyes, mouth, brows, buttons) stay crisp solid boxes; only
	# parts big enough to read as voxels (≥3 cubes on an axis) get the grid.
	if maxi(maxi(nx, ny), nz) < 3:
		var bm := BoxMesh.new()
		bm.size = size
		_voxel_cache[key] = bm
		return bm
	var sx: float = size.x / nx
	var sy: float = size.y / ny
	var sz: float = size.z / nz
	var h: Vector3 = Vector3(sx, sy, sz) * (0.91 * 0.5)  # cube half-extents (small gaps)
	var rounded: bool = nx >= 3 and ny >= 3 and nz >= 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nx:
		for j in ny:
			for k in nz:
				if not (i == 0 or i == nx - 1 or j == 0 or j == ny - 1 or k == 0 or k == nz - 1):
					continue  # shell only — interior cubes are never seen
				if rounded and (i == 0 or i == nx - 1) and (j == 0 or j == ny - 1) and (k == 0 or k == nz - 1):
					continue  # shave the 8 corners
				var c := Vector3(
					-size.x * 0.5 + (float(i) + 0.5) * sx,
					-size.y * 0.5 + (float(j) + 0.5) * sy,
					-size.z * 0.5 + (float(k) + 0.5) * sz)
				_add_cube(st, c, h)
	# A shared fallback surface material avoids "material is null" render warnings
	# (the per-instance colour comes from the MeshInstance3D's surface override).
	if _vox_placeholder == null:
		_vox_placeholder = StandardMaterial3D.new()
	st.set_material(_vox_placeholder)
	st.generate_normals()
	var am: ArrayMesh = st.commit()
	_voxel_cache[key] = am
	return am


## Emit one cube (6 quads, CCW-out) centred at `c` with half-extents `h`.
func _add_cube(st: SurfaceTool, c: Vector3, h: Vector3) -> void:
	var v := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
		c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z),
		c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	# faces as CCW-outward vertex-index quads
	var faces := [
		[4, 5, 6, 7],  # +Z
		[1, 0, 3, 2],  # -Z
		[5, 1, 2, 6],  # +X
		[0, 4, 7, 3],  # -X
		[7, 6, 2, 3],  # +Y
		[0, 1, 5, 4]]  # -Y
	for f in faces:
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[1]]); st.add_vertex(v[f[2]])
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[2]]); st.add_vertex(v[f[3]])

## Build a wide open-gap C-claw hand from chunky voxels (gap at the top, where a
## tool would sit). Reads as a minifig C-hand rather than a closed ring.
func _build_claw(parent: Node, nm: String, center: Vector3, colour: Color) -> void:
	var r := 0.16
	var seg := 10
	for i in seg:
		var a := TAU * float(i) / float(seg)
		var deg := rad_to_deg(a)
		# Small open gap at the BOTTOM (claw opening downward); the arm meets the closed top.
		if deg > 244.0 and deg < 296.0:
			continue
		var px := center.x + cos(a) * r
		var py := center.y + sin(a) * r
		var b := _box(parent, "%s_%d" % [nm, i], Vector3(0.11, 0.11, 0.20), Vector3(px, py, center.z), colour)
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

	# ── Legs on hip pivots (animation) ────────────────────────────────────────
	# Each leg hangs from a pivot at the hip joint (y≈0.70) so rotating the pivot.x
	# swings the whole leg for a walk cycle. Parts are positioned relative to it.
	_leg_l_pivot = Node3D.new()
	_leg_l_pivot.name = "HipPivotL"
	_leg_l_pivot.position = Vector3(-0.145, 0.70, 0.0)
	add_child(_leg_l_pivot)
	_leg_r_pivot = Node3D.new()
	_leg_r_pivot.name = "HipPivotR"
	_leg_r_pivot.position = Vector3(0.145, 0.70, 0.0)
	add_child(_leg_r_pivot)
	for side in [["L", _leg_l_pivot], ["R", _leg_r_pivot]]:
		var s: String = side[0]
		var p: Node3D = side[1]
		_box(p, "Leg" + s, Vector3(0.26, 0.62, 0.30), Vector3(0.0, -0.39, 0.0), LEG_COLOUR)
		_box(p, "Foot" + s, Vector3(0.27, 0.10, 0.34), Vector3(0.0, -0.65, 0.02), Color("#1C1C22"))
		_box(p, "Knee" + s, Vector3(0.20, 0.12, 0.02), Vector3(0.0, -0.36, 0.16), LEG_COLOUR.lightened(0.12))
		_box(p, "Toe" + s, Vector3(0.27, 0.07, 0.10), Vector3(0.0, -0.64, 0.21), Color("#0F0F14"))
		_box(p, "Sole" + s, Vector3(0.28, 0.03, 0.36), Vector3(0.0, -0.695, 0.02), Color("#444"))
	_box(self, "Hips", Vector3(0.56, 0.20, 0.32), Vector3(0.0, 0.72, 0.0), LEG_COLOUR)
	_box(self, "LegGap", Vector3(0.03, 0.40, 0.30), Vector3(0.0, 0.50, 0.0), Color("#15151A"))

	# ── Torso (trapezoid: narrow chest box + wider waist box) ─────────────────
	var chest := _box(self, "Chest", Vector3(0.58, 0.40, 0.34), Vector3(0.0, 1.18, 0.0), outfit)
	var waist := _box(self, "Waist", Vector3(0.64, 0.26, 0.345), Vector3(0.0, 0.93, 0.0), outfit)
	_outfit_parts.append(chest)
	_outfit_parts.append(waist)
	# Collar (V-neck) + chest seam + belt + gold buckle (fixed trim).
	_box(self, "Collar", Vector3(0.30, 0.09, 0.37), Vector3(0.0, 1.40, 0.0), outfit.lightened(0.18))
	_box(self, "Belt", Vector3(0.66, 0.07, 0.355), Vector3(0.0, 0.84, 0.0), BELT_COLOUR)
	_box(self, "Buckle", Vector3(0.10, 0.07, 0.02), Vector3(0.0, 0.84, 0.18), BUCKLE_COLOUR)
	_box(self, "Seam", Vector3(0.02, 0.45, 0.02), Vector3(0.0, 1.16, 0.175), BELT_COLOUR)
	# Chest detail: two flap pockets, a row of gold buttons, collar lapels.
	_box(self, "PocketL", Vector3(0.15, 0.12, 0.02), Vector3(-0.16, 1.02, 0.175), BELT_COLOUR)
	_box(self, "PocketR", Vector3(0.15, 0.12, 0.02), Vector3(0.16, 1.02, 0.175), BELT_COLOUR)
	_box(self, "BtnA", Vector3(0.035, 0.035, 0.02), Vector3(0.0, 1.30, 0.18), BUCKLE_COLOUR)
	_box(self, "BtnB", Vector3(0.035, 0.035, 0.02), Vector3(0.0, 1.18, 0.18), BUCKLE_COLOUR)
	_box(self, "BtnC", Vector3(0.035, 0.035, 0.02), Vector3(0.0, 1.06, 0.18), BUCKLE_COLOUR)
	# Thin cream undershirt placket peeking at the collar (small, not a big white V).
	_box(self, "Placket", Vector3(0.06, 0.18, 0.02), Vector3(0.0, 1.30, 0.178), Color("#EDE7D2"))
	_box(self, "LapelL", Vector3(0.09, 0.16, 0.02), Vector3(-0.10, 1.30, 0.176), outfit.lightened(0.12), Vector3(0, 0, deg_to_rad(-16)))
	_box(self, "LapelR", Vector3(0.09, 0.16, 0.02), Vector3(0.10, 1.30, 0.176), outfit.lightened(0.12), Vector3(0, 0, deg_to_rad(16)))

	# ── Shoulders (static) + arms on shoulder pivots + C-claw hands ───────────
	var sh_l := _box(self, "ShoulderL", Vector3(0.20, 0.22, 0.28), Vector3(-0.37, 1.30, 0.0), outfit)
	var sh_r := _box(self, "ShoulderR", Vector3(0.20, 0.22, 0.28), Vector3(0.37, 1.30, 0.0), outfit)
	_outfit_parts.append_array([sh_l, sh_r])
	_arm_l_pivot = Node3D.new()
	_arm_l_pivot.name = "ShoulderPivotL"
	_arm_l_pivot.position = Vector3(-0.40, 1.38, 0.04)
	add_child(_arm_l_pivot)
	_arm_r_pivot = Node3D.new()
	_arm_r_pivot.name = "ShoulderPivotR"
	_arm_r_pivot.position = Vector3(0.40, 1.38, 0.04)
	add_child(_arm_r_pivot)
	for side in [["L", _arm_l_pivot], ["R", _arm_r_pivot]]:
		var s: String = side[0]
		var p: Node3D = side[1]
		_outfit_parts.append(_box(p, "Arm" + s, Vector3(0.18, 0.46, 0.22), Vector3(0.0, -0.36, 0.0), outfit))
		_outfit_parts.append(_box(p, "Cuff" + s, Vector3(0.20, 0.08, 0.24), Vector3(0.0, -0.52, 0.0), outfit.darkened(0.18)))
		_build_claw(p, "Hand" + s, Vector3(0.0, -0.64, 0.06), skin)

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
	# Brows: BOLD black, thick and slightly angled — the strong dark brows of the hero art.
	var brow_col := Color("#181210")
	_box(self, "BrowL", Vector3(0.18, 0.07, 0.03), Vector3(-0.115, 1.93, fz + 0.008), brow_col, Vector3(0, 0, deg_to_rad(9)))
	_box(self, "BrowR", Vector3(0.18, 0.07, 0.03), Vector3(0.115, 1.93, fz + 0.008), brow_col, Vector3(0, 0, deg_to_rad(-9)))
	# Clean happy open smile: white teeth + red mouth + a thin lower lip whose ENDS sit
	# slightly higher (an up-turn). No rotated side-corners — those read as a moustache
	# and made every builder look the same. Facial hair is per-character only.
	_box(self, "Teeth", Vector3(0.20, 0.05, 0.02), Vector3(0.0, 1.675, fz + 0.014), EYE_WHITE)
	_box(self, "MouthRed", Vector3(0.18, 0.04, 0.02), Vector3(0.0, 1.64, fz + 0.008), MOUTH_RED)
	_box(self, "Lip", Vector3(0.14, 0.03, 0.022), Vector3(0.0, 1.612, fz), MOUTH_DARK)
	_box(self, "LipTipL", Vector3(0.045, 0.03, 0.022), Vector3(-0.10, 1.626, fz), MOUTH_DARK)
	_box(self, "LipTipR", Vector3(0.045, 0.03, 0.022), Vector3(0.10, 1.626, fz), MOUTH_DARK)
	# Rosy cheeks, kept low/outboard so they read as cheeks (not a moustache).
	_box(self, "CheekL", Vector3(0.06, 0.045, 0.02), Vector3(-0.205, 1.72, fz - 0.005), Color("#F0A24A"))
	_box(self, "CheekR", Vector3(0.06, 0.045, 0.02), Vector3(0.205, 1.72, fz - 0.005), Color("#F0A24A"))

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
	_hair_shade_parts.append(_mustache)
	_goatee = Node3D.new()
	_goatee.name = "Goatee"
	add_child(_goatee)
	_hair_shade_parts.append(_box(_goatee, "Chin", Vector3(0.14, 0.09, 0.04), Vector3(0.0, 1.55, fz2 - 0.005), HAIR_SHADE))
	_hair_shade_parts.append(_box(_goatee, "Jaw", Vector3(0.30, 0.06, 0.30), Vector3(0.0, 1.56, 0.0), HAIR_SHADE))
	_goatee.visible = false
	# Forester neck scarf (wraps the neck).
	_scarf = _box(self, "Scarf", Vector3(0.40, 0.12, 0.40), Vector3(0.0, 1.46, 0.0), Color("#C9483A"))
	_scarf.visible = false

	_polish_materials()


## Advanced finish: metallic trim, a subtle skin sheen, and a faint rim so the figure
## reads as a real 3D character rather than flat boxes. Applies in the creator AND in
## the world (materials travel with the meshes).
func _polish_materials() -> void:
	# Gold trim → shiny metal.
	for nm in ["Buckle", "BtnA", "BtnB", "BtnC", "Zipper"]:
		_tune(get_node_or_null(nm), 0.30, 0.85)
	if _bandolier != null:
		_tune(_bandolier.get_node_or_null("BuckleX"), 0.30, 0.85)
	# Skin → very subtle sheen (no rim — the rim was washing the skin toward white).
	for p in _skin_parts:
		_tune(p, 0.7, 0.0)


## Tune a mesh's StandardMaterial3D: roughness, metallic, and an optional rim.
func _tune(n: Node, rough: float, metal: float, rim: float = 0.0) -> void:
	if not (n is MeshInstance3D):
		return
	var m: StandardMaterial3D = (n as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	if m == null:
		return
	m.roughness = rough
	m.metallic = metal
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim


## Rebuild the hair cluster for the chosen Kapsel option.
func _apply_hairstyle(style: String) -> void:
	if _hair_root == null:
		return
	_cur_hair = style
	for c in _hair_root.get_children():
		c.queue_free()
	var h := _hair_root
	var hc: Color = _hair_colour                  # picked hair colour
	var hs: Color = _hair_colour.darkened(0.20)   # derived depth shade
	# Common base: a big chunky cap + fringe + thick sideburns framing the head, sitting
	# high and voluminous like the hero art (head top ~2.05).
	_box(h, "Cap", Vector3(0.62, 0.26, 0.60), Vector3(0.0, 2.12, 0.0), hc)
	_box(h, "CapTop", Vector3(0.54, 0.16, 0.52), Vector3(0.0, 2.28, -0.02), hc)
	_box(h, "Fringe", Vector3(0.58, 0.16, 0.12), Vector3(0.0, 2.04, 0.24), hc)
	_box(h, "SideL", Vector3(0.12, 0.42, 0.52), Vector3(-0.29, 1.88, 0.0), hc)
	_box(h, "SideR", Vector3(0.12, 0.42, 0.52), Vector3(0.29, 1.88, 0.0), hc)
	_box(h, "Back", Vector3(0.56, 0.40, 0.14), Vector3(0.0, 1.90, -0.27), hc)
	# Density: angled fringe tufts + layered side locks on every style.
	_box(h, "TuftFL", Vector3(0.14, 0.13, 0.12), Vector3(-0.16, 2.13, 0.11), hc, Vector3(deg_to_rad(-24), 0, deg_to_rad(-10)))
	_box(h, "TuftFR", Vector3(0.14, 0.13, 0.12), Vector3(0.16, 2.13, 0.11), hc, Vector3(deg_to_rad(-24), 0, deg_to_rad(10)))
	_box(h, "LockL", Vector3(0.09, 0.12, 0.30), Vector3(-0.30, 1.98, -0.04), hs, Vector3(0, 0, deg_to_rad(16)))
	_box(h, "LockR", Vector3(0.09, 0.12, 0.30), Vector3(0.30, 1.98, -0.04), hs, Vector3(0, 0, deg_to_rad(-16)))
	_box(h, "Nape", Vector3(0.44, 0.14, 0.08), Vector3(0.0, 1.66, -0.255), hs)
	_box(h, "CrownL", Vector3(0.13, 0.15, 0.18), Vector3(-0.13, 2.15, -0.03), hc, Vector3(deg_to_rad(-10), 0, deg_to_rad(-7)))
	_box(h, "CrownR", Vector3(0.13, 0.15, 0.18), Vector3(0.13, 2.15, -0.03), hc, Vector3(deg_to_rad(-10), 0, deg_to_rad(7)))
	_box(h, "CrownM", Vector3(0.12, 0.14, 0.18), Vector3(0.0, 2.16, -0.10), hs, Vector3(deg_to_rad(-6), 0, 0))
	match style:
		"round":  # fuller, rounded — lower side volume, soft top
			_box(h, "TopR", Vector3(0.48, 0.16, 0.46), Vector3(0.0, 2.16, -0.02), hs)
			_box(h, "SideLo_L", Vector3(0.10, 0.16, 0.40), Vector3(-0.29, 1.66, 0.0), hc)
			_box(h, "SideLo_R", Vector3(0.10, 0.16, 0.40), Vector3(0.29, 1.66, 0.0), hc)
		"tall":   # spiky, tall tufts
			for i in 5:
				var x := -0.20 + 0.10 * float(i)
				var hh := 0.22 + 0.06 * float(i % 2)
				_box(h, "Spike%d" % i, Vector3(0.09, hh, 0.10), Vector3(x, 2.14 + hh * 0.4, -0.02 + 0.04 * float(i % 2)), hc, Vector3(deg_to_rad(-12 + 6 * i), 0, 0))
		_:        # "square" — short spiky fringe (matches the art's explorer)
			for i in 4:
				var x := -0.18 + 0.12 * float(i)
				_box(h, "Tuft%d" % i, Vector3(0.11, 0.18, 0.12), Vector3(x, 2.12, 0.16), hc, Vector3(deg_to_rad(-22), 0, deg_to_rad(-8 + 5 * i)))
			_box(h, "TopFlat", Vector3(0.50, 0.10, 0.40), Vector3(0.0, 2.13, -0.05), hs)


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
		_recolour(collar, outfit.lightened(0.18))
	for lap in ["LapelL", "LapelR"]:
		_recolour(get_node_or_null(lap) as MeshInstance3D, outfit.lightened(0.12))

	# Hair: pickable colour + style. Rebuild the hair cluster when either changes.
	var style: String = str(cfg.get("head_shape", "square"))
	var hair_idx: int = clampi(int(cfg.get("hair_colour_index", 0)), 0, HAIR_COLOURS.size() - 1)
	var new_hair: Color = HAIR_COLOURS[hair_idx]
	var hair_changed: bool = not new_hair.is_equal_approx(_hair_colour)
	_hair_colour = new_hair
	if style != _cur_hair or hair_changed:
		_apply_hairstyle(style)
	# Brows + facial hair follow the hair colour (a touch darker).
	for p in _hair_shade_parts:
		_recolour(p, _hair_colour.darkened(0.12))

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
