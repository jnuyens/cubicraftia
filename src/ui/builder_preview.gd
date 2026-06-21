# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# builder_preview.gd — lightweight, SubViewport-safe builder preview for the
# avatar creator (Surface 2). It is NOT the in-world Builder: no physics, no
# groups, no mouse capture, no ../ sibling lookups. It reuses ONLY the avatar
# mesh + colour logic so the customiser preview re-renders every selection.
#
# Contract (mirrors Builder._setup_avatar_mesh_nodes / Builder.apply_avatar_config):
#   - On _ready() builds three named box MeshInstance3D children — "Head" /
#     "Body" / "Legs" — with StandardMaterial3D override materials.
#   - Optionally loads the selected skin GLB (cosmetic). A missing/failed GLB is
#     non-fatal: the coloured boxes are the contract; the GLB is a bonus.
#   - Exposes apply_avatar_config(cfg) so avatar_creator.gd's delegate path
#     (_apply_config_to_preview) drives it; the named children also keep the
#     fallback recolour path valid.
#
# References:
#   src/builder/builder.gd:2249-2363 (box-mesh build), :2513-2580 (apply_avatar_config)
#   .planning/phases/09-nl-localisation-review/09-04-PLAN.md Task 3 (approach B)

extends Node3D

# ─── Palettes (self-contained copies of avatar_creator's swatches) ────────────

## Skin colour swatches (5), applied to the exposed "Head" mesh.
const SKIN_COLOURS: Array[Color] = [
	Color("#FFD21A"),  # classic builder-figure yellow (default builder head)
	Color("#D4956A"),  # tan
	Color("#A0614A"),  # medium
	Color("#6B3A2A"),  # dark
	Color("#3B1F16"),  # deep
]

## Body / leg colour swatches (10) — a subset of the 18-colour brick palette.
const BODY_COLOURS: Array[Color] = [
	Color("#C91111"),  # red
	Color("#E8890C"),  # orange
	Color("#F5C30D"),  # yellow
	Color("#97C515"),  # lime
	Color("#3DB560"),  # green
	Color("#159195"),  # teal
	Color("#1B72D8"),  # blue
	Color("#7B2DB5"),  # purple
	Color("#D43582"),  # pink
	Color("#F1F0EA"),  # white
]

## Selectable skin GLBs by character id (cosmetic only; matches Builder._AVATAR_SKINS).
const AVATAR_SKINS: Dictionary = {
	"builder1": "res://assets/meshes/builder/skin_builder1.glb",
	"red": "res://assets/meshes/builder/skin_red.glb",
	"fem": "res://assets/meshes/builder/skin_fem.glb",
}
const DEFAULT_CHARACTER: String = "builder1"

const AVATAR_CFG_PATH: String = "user://avatar.cfg"
const AVATAR_SECTION: String = "avatar"

# ─── Node references (built in _ready) ────────────────────────────────────────

var _head_mesh: MeshInstance3D = null
var _body_mesh: MeshInstance3D = null
var _legs_mesh: MeshInstance3D = null
var _skin_root: Node3D = null
var _glb_loaded: bool = false


func _ready() -> void:
	_build_box_figure()
	_try_load_skin_glb()


# ─── Mesh build ───────────────────────────────────────────────────────────────

## Build the coloured box-figure contract: Head / Body / Legs.
## Sizes/positions mirror Builder._setup_avatar_mesh_nodes (builder.gd:2327-2363)
## so the figure is proportioned and centred for the SubViewport camera (z=2.5, y=1.5).
func _build_box_figure() -> void:
	# ── Head — skin colour target ─────────────────────────────────────────────
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.5, 0.5, 0.5)
	_head_mesh = MeshInstance3D.new()
	_head_mesh.name = "Head"
	_head_mesh.mesh = head_box
	_head_mesh.position = Vector3(0.0, 1.4, 0.0)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = SKIN_COLOURS[0]
	_head_mesh.set_surface_override_material(0, head_mat)
	add_child(_head_mesh)

	# ── Body — body colour target ─────────────────────────────────────────────
	var body_box := BoxMesh.new()
	body_box.size = Vector3(0.4, 0.6, 0.3)
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	_body_mesh.mesh = body_box
	_body_mesh.position = Vector3(0.0, 0.9, 0.0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BODY_COLOURS[6]  # default blue
	_body_mesh.set_surface_override_material(0, body_mat)
	add_child(_body_mesh)

	# ── Legs — leg colour target ──────────────────────────────────────────────
	var legs_box := BoxMesh.new()
	legs_box.size = Vector3(0.4, 0.5, 0.3)
	_legs_mesh = MeshInstance3D.new()
	_legs_mesh.name = "Legs"
	_legs_mesh.mesh = legs_box
	_legs_mesh.position = Vector3(0.0, 0.35, 0.0)
	var legs_mat := StandardMaterial3D.new()
	legs_mat.albedo_color = BODY_COLOURS[6]  # default blue
	_legs_mesh.set_surface_override_material(0, legs_mat)
	add_child(_legs_mesh)


## Optionally load the selected character's skin GLB as a cosmetic overlay.
## Non-fatal on any failure — the box figure remains the contract.
func _try_load_skin_glb() -> void:
	var character: String = _read_selected_character()
	var skin_path: String = str(AVATAR_SKINS.get(character, AVATAR_SKINS.get(DEFAULT_CHARACTER, "")))
	if skin_path == "" or not ResourceLoader.exists(skin_path):
		return
	var packed: Resource = load(skin_path)
	if packed == null or not (packed is PackedScene):
		return
	var inst: Node = (packed as PackedScene).instantiate()
	if inst == null:
		return
	if not (inst is Node3D):
		inst.queue_free()
		return
	_skin_root = inst as Node3D
	_skin_root.name = "SkinGLB"
	add_child(_skin_root)
	_glb_loaded = true
	# When the textured model renders, hide the box stand-ins so they do not
	# poke through. The boxes stay as the apply_avatar_config recolour targets.
	_head_mesh.visible = false
	_body_mesh.visible = false
	_legs_mesh.visible = false


## Read the selected character id from user://avatar.cfg, defaulting to builder1.
func _read_selected_character() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(AVATAR_CFG_PATH) != OK:
		return DEFAULT_CHARACTER
	return str(cfg.get_value(AVATAR_SECTION, "character", DEFAULT_CHARACTER))


# ─── Public API (mirrors Builder.apply_avatar_config colour/scale logic) ──────

## Apply avatar config to the preview. Null-safe: a missing mesh child is a no-op.
func apply_avatar_config(cfg: Dictionary) -> void:
	# ── Skin colour → Head ────────────────────────────────────────────────────
	if _head_mesh != null:
		var skin_idx: int = clampi(int(cfg.get("skin_colour_index", 0)), 0, SKIN_COLOURS.size() - 1)
		var head_mat: StandardMaterial3D = _head_mesh.get_active_material(0) as StandardMaterial3D
		if head_mat != null:
			head_mat.albedo_color = SKIN_COLOURS[skin_idx]

		# ── Head shape → Head scale (mirrors builder.gd:2526-2532) ────────────
		var head_shape: String = str(cfg.get("head_shape", "square"))
		match head_shape:
			"round":
				_head_mesh.scale = Vector3(0.9, 1.0, 0.9)
			"tall":
				_head_mesh.scale = Vector3(1.0, 1.2, 1.0)
			_:  # "square" (default)
				_head_mesh.scale = Vector3(1.0, 1.0, 1.0)

	# ── Body colour → Body ────────────────────────────────────────────────────
	if _body_mesh != null:
		var body_idx: int = clampi(int(cfg.get("body_colour_index", 6)), 0, BODY_COLOURS.size() - 1)
		var body_mat: StandardMaterial3D = _body_mesh.get_active_material(0) as StandardMaterial3D
		if body_mat != null:
			body_mat.albedo_color = BODY_COLOURS[body_idx]

	# ── Leg colour → Legs ─────────────────────────────────────────────────────
	if _legs_mesh != null:
		var leg_idx: int = clampi(int(cfg.get("leg_colour_index", 6)), 0, BODY_COLOURS.size() - 1)
		var legs_mat: StandardMaterial3D = _legs_mesh.get_active_material(0) as StandardMaterial3D
		if legs_mat != null:
			legs_mat.albedo_color = BODY_COLOURS[leg_idx]
