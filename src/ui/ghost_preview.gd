# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ghost_preview.gd — Transparent placement-feedback MeshInstance3D (Plan 02-09).
#
# Lives in the 3D viewport scene tree as a sibling of the Builder. Every _process
# frame it queries builder.predict_placement_target() to position a transparent
# ghost mesh at the predicted brick placement location.
#
# Per UI-SPEC.md §Ghost Preview (placement feedback, D-10):
#   - Valid state: white at 0.35α.
#   - Invalid state: red #D63828 at 0.35α.
#   - Tier-3 adaptive-quality fallback: set_mode("outline_only") hides the ghost mesh.
#     A future outline-shader pass (Plan 14) replaces this placeholder. The setter is
#     non-no-op so Plan 14's Tier-3 switch is a real code path.
#   - cast_shadow = false (no performance cost from shadow maps).
#   - The ghost mesh is NOT a UI Control; it lives in the 3D world scene tree.
#
# Public methods:
#   show_valid()         — display white 0.35α ghost
#   show_invalid()       — display red 0.35α ghost
#   hide()               — make ghost invisible
#   update_target()      — called from _process; repositions + tints ghost
#   set_mode(mode: String) — "full" (default) or "outline_only" (Tier-3 fallback)
#
# References:
#   UI-SPEC.md §Ghost Preview lines 251-258
#   02-PATTERNS.md §"src/ui/ghost_preview.gd" — builder.gd raycast analog
#   02-RESEARCH.md §"Pattern 4" lines 759-778 — predict_placement_target usage
#   CONTEXT.md D-10 — placement feedback is real-time semi-transparent brick mesh

class_name GhostPreview
extends MeshInstance3D

# ─── Colour constants (UI-SPEC.md §Ghost Preview) ─────────────────────────────

## Valid placement tint: white at 0.35α.
const COLOR_VALID: Color = Color(1.0, 1.0, 1.0, 0.35)

## Invalid placement tint: red #D63828 at 0.35α.
const COLOR_INVALID: Color = Color(0.839, 0.220, 0.157, 0.35)

# ─── Private state ────────────────────────────────────────────────────────────

## Current quality mode. "full" = transparent mesh; "outline_only" = mesh hidden.
var _mode: String = "full"

## The ShaderMaterial driving the ghost colour uniform.
var _ghost_material: StandardMaterial3D = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Start hidden; _process will make it visible once a builder is found.
	visible = false

	# Set up a StandardMaterial3D with transparency for the ghost mesh.
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = COLOR_VALID
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# The actual brick mesh is set in update_target() from the active definition.
	# Phase 2: uses brick_1x1 mesh as placeholder until Hotbar (Plan 12) wires the active def.
	material_override = _ghost_material


# ─── Per-frame update ─────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _mode == "outline_only":
		# Tier-3 fallback: ghost mesh is hidden; the crosshair alone shows target.
		visible = false
		return

	var builder := get_tree().get_first_node_in_group("builder")
	if builder == null:
		visible = false
		return

	update_target()


# ─── Public API ──────────────────────────────────────────────────────────────

## Show the ghost mesh in the valid (white 0.35α) state.
func show_valid() -> void:
	if _mode == "outline_only":
		return
	if _ghost_material != null:
		_ghost_material.albedo_color = COLOR_VALID
	visible = true


## Show the ghost mesh in the invalid (red 0.35α) state.
func show_invalid() -> void:
	if _mode == "outline_only":
		return
	if _ghost_material != null:
		_ghost_material.albedo_color = COLOR_INVALID
	visible = true


## Update the ghost mesh position and tint based on the builder's predicted placement.
## Called from _process. Safe to call if no builder is in the scene.
func update_target() -> void:
	var builder := get_tree().get_first_node_in_group("builder") as Builder
	if builder == null:
		visible = false
		return

	# predict_placement_target() is the shared raycast extracted from _try_place.
	if not builder.has_method("predict_placement_target"):
		visible = false
		return

	var prediction: Dictionary = builder.predict_placement_target()
	var is_valid: bool = prediction.get("valid", false)
	var target_cell: Vector3i = prediction.get("target_cell", Vector3i.ZERO)

	if not is_valid and not prediction.get("target_cell", Vector3i.ZERO) != Vector3i.ZERO:
		# No target found at all.
		visible = false
		return

	# Position the ghost at the centre of the target cell.
	# Each stud-grid cell is 1m³; centre = cell + Vector3(0.5, 0.5, 0.5).
	var world_pos := Vector3(
		float(target_cell.x) + 0.5,
		float(target_cell.y) + 0.5,
		float(target_cell.z) + 0.5
	)
	global_position = world_pos

	# Wire the brick mesh if the builder's active def has one.
	# Phase 2 fallback: use the builder's BRICK_1X1 until Plan 12 Hotbar wires active_def.
	if builder.has_method("get") and builder.get("BRICK_1X1") != null:
		var def: BrickDefinition = builder.get("BRICK_1X1") as BrickDefinition
		if def != null and def.mesh != null and mesh != def.mesh:
			mesh = def.mesh

	# Tint based on validity.
	if is_valid:
		show_valid()
	else:
		show_invalid()


## Switch the ghost preview quality mode.
##
## "full" (default): transparent mesh ghost as per UI-SPEC.md §Ghost Preview.
## "outline_only": Tier-3 adaptive-quality fallback (Plan 14). The ghost mesh is
##   hidden; a future outline-shader stencil pass will replace this. In v1 the
##   fallback is "mesh hidden" — the player still sees the crosshair to aim.
##   This setter is intentionally non-no-op so Plan 14's dispatch is a real switch.
##
## Called by settings_menu.gd _apply_live_settings() (§7.6 adaptive-quality hook).
func set_mode(mode_str: String) -> void:
	_mode = mode_str
	# In outline_only mode, hide immediately so _process skips the raycast.
	if _mode == "outline_only":
		visible = false
