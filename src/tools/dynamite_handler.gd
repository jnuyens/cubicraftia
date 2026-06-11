# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# dynamite_handler.gd — DynamiteHandler: 3 s fuse + bulk-edit blast + dropped-item spawn.
#
# Headline VFX moment of Phase 2 (CONTEXT.md D-11): bright orange/yellow flash +
# screen shake + every affected brick/voxel "pops" outward as a DroppedItem entity.
#
# BULK-EDIT CONTRACT (RESEARCH.md Pattern 5 + Pitfalls TECH-1/2/3):
#   detonate() issues EXACTLY ONE VoxelTool.do_sphere() call (not 524+ set_voxel).
#   detonate() issues EXACTLY ONE StudGrid.remove_bulk() call (not 100+ remove).
#   The voxel mesher schedules one re-mesh per affected chunk (1-4 chunks at radius 5)
#   because do_sphere triggers batch chunk updates internally.
#   voxel/threads/main/time_budget_ms = 6 is set in project.godot to spread mesh
#   swaps across frames and avoid a single-frame main-thread stall (TECH-3 mitigation).
#
# PHYSICS CAP (RESEARCH.md Pitfall 7):
#   Up to 30 active RigidBody3D dropped items; remainder settle directly into
#   the MultiMesh pool via main_scene.spawn_dropped_item(…, active_physics=false).
#
# SCREEN SHAKE (02-UI-SPEC.md §"Dynamite VFX sequence" step 4):
#   Camera3D.h_offset / v_offset random oscillation, 0.3 s, max 8 px, ease-out cubic.
#   Matches toast.gd Tween precedent (Tween.EASE_OUT / Tween.TRANS_CUBIC).
#
# TERRAIN→DROP MAPPING:
#   DroppedItem.TERRAIN_TO_BRICK_DROP is the single source of truth.
#   DynamiteHandler reads that const — no duplicate mapping here.
#
# References:
#   DOCS.md §3.4 — dynamite ~5 m radius
#   02-RESEARCH.md §"Pattern 5: Dynamite blast as one bulk VoxelTool.do_sphere"
#   02-RESEARCH.md §"Pitfall 2" — chunk-mesh batching (bulk edit = 1 remesh/chunk)
#   02-RESEARCH.md §"Pitfall 7" — dropped-item physics cap
#   02-CONTEXT.md D-11 — brick-shatter VFX
#   02-PATTERNS.md §"src/tools/dynamite_handler.gd" — Timer + Tween + GPUParticles3D
#   02-UI-SPEC.md §"Dynamite VFX sequence" — step-by-step sequence
#   02-UI-SPEC.md §"Dynamite (VFX + feedback)" — toast copywriting

class_name DynamiteHandler
extends Node3D

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted after a blast completes.
## @param centre       World-space blast centre.
## @param removed_count Total number of stud-grid cells removed + voxels cleared.
signal blast_completed(centre: Vector3, removed_count: int)

# ─── Constants ────────────────────────────────────────────────────────────────

## Fuse duration in seconds (DOCS.md §3.4).
const FUSE_DURATION_S: float = 3.0

## Screen-shake amplitude in world units (maps to Camera3D h_offset/v_offset px).
## 02-UI-SPEC.md: max 8 px amplitude.
const SHAKE_AMPLITUDE: float = 0.08

## Screen-shake duration in seconds.
const SHAKE_DURATION_S: float = 0.3

# ─── Node children ────────────────────────────────────────────────────────────

@onready var _fuse_timer: Timer = $FuseTimer
@onready var _flash_particles: GPUParticles3D = $FlashParticles
@onready var _fuse_sparks: GPUParticles3D = $FuseSparks

# ─── Private state ────────────────────────────────────────────────────────────

## The radius of the dynamite blast in metres (from ToolDefinition.dynamite_radius_m).
var _radius: float = 5.0

## Cached StudGrid reference from the scene tree.
var _stud_grid: StudGrid = null

## Cached main_scene reference for spawn_dropped_item calls.
var _main_scene: Node = null

## Active Tween for screen shake (kept so it can be killed early if needed).
var _shake_tween: Tween = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_fuse_timer.wait_time = FUSE_DURATION_S
	_fuse_timer.one_shot = true
	_fuse_timer.autostart = false
	_fuse_timer.timeout.connect(_on_fuse_complete)

	# Cache scene references.
	_stud_grid = get_tree().get_first_node_in_group("stud_grid") as StudGrid
	if _stud_grid == null:
		# Fallback: walk up to root and look for StudGrid sibling.
		var root := get_tree().get_root()
		if root != null:
			_stud_grid = root.find_child("StudGrid", true, false) as StudGrid

	_main_scene = get_tree().get_first_node_in_group("main_scene")
	if _main_scene == null:
		var root := get_tree().get_root()
		if root != null:
			_main_scene = root.find_child("Main", true, false)
			if _main_scene == null:
				# Try direct root children that have spawn_dropped_item.
				for c in root.get_children():
					if c.has_method("spawn_dropped_item"):
						_main_scene = c
						break


# ─── Public API ───────────────────────────────────────────────────────────────

## Light the dynamite fuse at the given world position.
##
## Places and parents this handler at world_pos, starts the fuse timer,
## begins FuseSparks particles, and shows the "Fuse lit — step back!" toast.
##
## @param world_pos  World position where the dynamite is placed (blast centre).
## @param radius     Blast radius in metres. Defaults to 5.0 (DOCS §3.4).
func light_fuse(world_pos: Vector3, radius: float = 5.0) -> void:
	global_position = world_pos
	_radius = radius
	_fuse_sparks.emitting = true
	_fuse_timer.start()
	Toasts.show("ui.tool.dynamite_fuse_lit", "info")


## Detonate the dynamite at the given centre with the given radius.
##
## Performs the bulk-edit blast in exactly ONE do_sphere + ONE remove_bulk call.
## Spawns dropped items for every removed brick/voxel.
## Returns the total count of entities removed (stud-grid cells + voxels cleared).
##
## This method is called internally by _on_fuse_complete, but is public so tests
## can call it directly with a stub StudGrid (no VoxelTerrain required headlessly).
##
## @param centre  World-space blast centre.
## @param radius  Blast radius in metres.
## @return        Total removed entity count (brick cells + terrain voxels in radius).
func detonate(centre: Vector3, radius: float) -> int:
	var total_removed: int = 0

	# ── Step 1: Flash particles + chunky brick-explosion mesh at blast centre ──
	_flash_particles.emitting = true
	# Parent the VFX to the scene (NOT self — the handler frees itself after the blast,
	# which would take the effect with it before it plays).
	var _fx_parent: Node = _main_scene if _main_scene != null else get_tree().current_scene
	if _fx_parent != null:
		EffectsLibrary.spawn(_fx_parent, "explosion", centre,
			{"size": maxf(radius * 0.7, 2.0), "lifetime": 1.2, "spin": 0.6, "ground": false})

	# ── Step 2: Screen shake — Camera3D h_offset / v_offset Tween ───────────
	_apply_screen_shake()

	# Step 3: BULK terrain edit (TECH-1 mitigation: one call, not per-cell).
	var terrain: Node = get_tree().get_first_node_in_group("voxel_terrain")
	if terrain != null and terrain.has_method("get_voxel_tool"):
		var voxel_tool = terrain.get_voxel_tool()
		if voxel_tool != null:
			var aabb_region := AABB(centre - Vector3.ONE * radius,
				Vector3.ONE * (radius * 2.0))
			var copied_buffer = voxel_tool.copy(aabb_region, 1 << 0)
			voxel_tool.value = 0
			voxel_tool.do_sphere(centre, radius)
			if copied_buffer != null and copied_buffer.has_method("get_size"):
				var buf_size: Vector3i = copied_buffer.get_size()
				for bx in range(buf_size.x):
					for by in range(buf_size.y):
						for bz in range(buf_size.z):
							var voxel_id: int = copied_buffer.get_voxel(bx, by, bz, 0)
							if voxel_id == 0:
								continue
							var voxel_world_pos := Vector3(
								aabb_region.position.x + bx,
								aabb_region.position.y + by,
								aabb_region.position.z + bz
							)
							_spawn_terrain_drop(voxel_id, voxel_world_pos)
							total_removed += 1

	# Step 4: BULK stud-grid remove (TECH-2 mitigation: one call, coalesced dirty chunks).
	var affected_cells: Array = []
	if _stud_grid != null:
		affected_cells = _stud_grid.cells_in_sphere(centre, radius)
		var cell_drop_data: Array = []
		for cell_raw in affected_cells:
			var cell: Vector3i = cell_raw as Vector3i
			var instance: StudGrid.BrickInstance = _stud_grid.query(cell)
			if instance != null:
				cell_drop_data.append({
					"def_id": instance.definition.brick_id if instance.definition != null else "",
					"colour": instance.colour_index,
					"pos": Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5)
				})

		_stud_grid.remove_bulk(affected_cells)

		total_removed += affected_cells.size()

		for drop in cell_drop_data:
			var def_id: String = drop["def_id"]
			var colour: int = drop["colour"]
			var pos: Vector3 = drop["pos"]
			if def_id != "" and _main_scene != null:
				_main_scene.spawn_dropped_item(def_id, colour, pos, true)

	# ── Step 5: Emit completion signal ──────────────────────────────────────
	blast_completed.emit(centre, total_removed)

	# Clean up this handler after a short delay (after particles finish).
	get_tree().create_timer(2.0).timeout.connect(queue_free)

	return total_removed


# ─── Private helpers ──────────────────────────────────────────────────────────

## Apply screen shake via Camera3D h_offset / v_offset Tween.
## Per 02-UI-SPEC.md §"Dynamite VFX sequence" step 4:
##   - Random oscillation 0.3 s duration, max 8 px amplitude, ease-out cubic.
## Per 02-PATTERNS.md §"dynamite_handler.gd" — toast.gd tween precedent.
func _apply_screen_shake() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return

	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()

	var h_shake: float = randf_range(-SHAKE_AMPLITUDE, SHAKE_AMPLITUDE)
	var v_shake: float = randf_range(-SHAKE_AMPLITUDE, SHAKE_AMPLITUDE)

	_shake_tween = create_tween()
	_shake_tween.set_parallel(true)
	# Animate to the random offset, then back to zero — ease-out cubic per spec.
	_shake_tween.tween_property(camera, "h_offset", h_shake, SHAKE_DURATION_S * 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_shake_tween.chain().tween_property(camera, "h_offset", 0.0, SHAKE_DURATION_S * 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# V offset oscillates independently.
	var tween_v := create_tween()
	tween_v.tween_property(camera, "v_offset", v_shake, SHAKE_DURATION_S * 0.5)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween_v.chain().tween_property(camera, "v_offset", 0.0, SHAKE_DURATION_S * 0.5)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Spawn a dropped item for a cleared terrain voxel using TERRAIN_TO_BRICK_DROP.
## Snow voxels (and unknown IDs) drop nothing.
func _spawn_terrain_drop(voxel_id: int, world_pos: Vector3) -> void:
	if _main_scene == null:
		return
	# Use the single-owner mapping in DroppedItem (no duplicate mapping here).
	if not DroppedItem.TERRAIN_TO_BRICK_DROP.has(voxel_id):
		return  # Unknown terrain voxel type — drop nothing.
	var def_id: Variant = DroppedItem.TERRAIN_TO_BRICK_DROP[voxel_id]
	if def_id == null:
		return  # Null mapping = explicit "drop nothing" (e.g. snow, ice, water).
	_main_scene.spawn_dropped_item(def_id as String, -1, world_pos, true)


# ─── Timer signal handler ─────────────────────────────────────────────────────

## Called when the fuse timer expires (after FUSE_DURATION_S seconds).
func _on_fuse_complete() -> void:
	_fuse_sparks.emitting = false
	detonate(global_position, _radius)
