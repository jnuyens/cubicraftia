# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# welcome_sign.gd — A purely-decorative brick-styled "Welcome to Cubicraftia" sign.
#
# Built entirely in code (no .tscn dependency) so main_scene can spawn it with one call:
#   add_child(WelcomeSign.new()); sign.global_position = ...
#
# Structure (all assembled in _ready, anchored at this Node3D's origin = ground level):
#   - StaticBody3D post  : wood-brown vertical box (a thin StaticBody so the player can't
#                          walk through it — trivial to add, gives the sign physical heft).
#   - MeshInstance3D board: lighter tan horizontal box mounted atop the post.
#   - Label3D            : "Welcome to Cubicraftia" mounted on the board's front face,
#                          facing outward (-Z local), with an outline for contrast.
#
# Colours reuse the locked 18-brick palette (palette.gd): brown #7A4A23 for the post,
# tan #D7B97A for the board — matching the "wood post + lighter board" brief.
#
# The sign faces -Z in local space. The spawner rotates the node so -Z points back toward
# the spawn point, so a player standing at spawn reads the text head-on.

class_name WelcomeSign
extends Node3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Player-facing game name (intentionally shown to players — see CLAUDE.md).
const SIGN_TEXT: String = "Welcome to Cubicraftia"

## Post (wood-brown #7A4A23, palette index 15).
const POST_COLOR: Color = Color(0.478, 0.290, 0.137, 1.0)

## Board (tan #D7B97A, palette index 16) — lighter than the post.
const BOARD_COLOR: Color = Color(0.843, 0.725, 0.478, 1.0)

## Post dimensions (m): thin square column.
const POST_SIZE: Vector3 = Vector3(0.16, 1.4, 0.16)

## Board dimensions (m): ~1.8 m wide, mounted near the top of the post.
const BOARD_SIZE: Vector3 = Vector3(1.8, 0.6, 0.1)

## Height (m) of the board's centre above the sign's origin (ground level).
const BOARD_CENTER_Y: float = 1.5

## Label font size (point-equivalent for Label3D pixel size). Large + outlined = readable.
const LABEL_FONT_SIZE: int = 64

## Label3D pixel_size: world metres per font pixel. Tuned so the text fits the board width.
const LABEL_PIXEL_SIZE: float = 0.0085

## Outline thickness (px) for contrast against the tan board.
const LABEL_OUTLINE_SIZE: int = 12

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("welcome_sign")
	_build_post()
	_build_board()
	_build_label()


# ─── Builders ─────────────────────────────────────────────────────────────────

## Wood-brown post: a thin StaticBody3D so the player bumps into it instead of
## clipping through. Box mesh + matching box collision.
func _build_post() -> void:
	var post := StaticBody3D.new()
	post.name = "Post"
	post.position = Vector3(0.0, POST_SIZE.y * 0.5, 0.0)

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = POST_SIZE
	mesh_inst.mesh = box
	mesh_inst.material_override = _make_material(POST_COLOR)
	post.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = POST_SIZE
	col.shape = shape
	post.add_child(col)

	add_child(post)


## Lighter tan board mounted near the top of the post (purely visual mesh).
func _build_board() -> void:
	var board := MeshInstance3D.new()
	board.name = "Board"
	var box := BoxMesh.new()
	box.size = BOARD_SIZE
	board.mesh = box
	board.material_override = _make_material(BOARD_COLOR)
	board.position = Vector3(0.0, BOARD_CENTER_Y, 0.0)
	add_child(board)


## "Welcome to Cubicraftia" Label3D mounted on the board's front (-Z) face,
## facing outward with an outline for contrast and legibility.
func _build_label() -> void:
	var label := Label3D.new()
	label.name = "WelcomeLabel"
	label.text = SIGN_TEXT
	label.font_size = LABEL_FONT_SIZE
	label.outline_size = LABEL_OUTLINE_SIZE
	label.pixel_size = LABEL_PIXEL_SIZE
	label.modulate = Color(0.118, 0.090, 0.043, 1.0)        # dark brown text
	label.outline_modulate = Color(0.961, 0.941, 0.890, 1.0)  # cream outline for contrast
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Always render flat on the board face; never billboard.
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	label.double_sided = false
	# Sit just in front of the board's -Z face so the text isn't z-fighting the box.
	label.position = Vector3(0.0, BOARD_CENTER_Y, -(BOARD_SIZE.z * 0.5 + 0.01))
	# Label3D's text faces +Z by default; rotate 180° so it reads on the -Z (outward) face.
	label.rotation = Vector3(0.0, PI, 0.0)
	add_child(label)


# ─── Helpers ──────────────────────────────────────────────────────────────────

## Matte StandardMaterial3D for the brick-styled boxes.
func _make_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mat.metallic = 0.0
	return mat
