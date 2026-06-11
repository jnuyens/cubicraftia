# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# stud_grid.gd — Sparse stud-grid data structure (Plan 05, Task 2; extended Plan 02-09).
#
# Maintains a Dictionary[Vector3i, BrickInstance] mapping stud-grid coordinates
# to placed bricks (Pattern 4 from RESEARCH.md). Coordinates are in terrain-anchor
# space: each Vector3i(x, y, z) is the 1 m voxel cell that a brick occupies.
#
# API (Phase 1 preserved):
#   place(anchor_cell, definition) -> bool   — wrapper: calls place_multi with 1-cell footprint
#   remove(anchor_cell)            -> bool   — true if a brick was there; false if empty
#   query(anchor_cell)             -> BrickInstance | null
#   size()                         -> int
#
# API (Phase 2 — Plan 02-09 extensions):
#   place_multi(anchor, footprint, def, colour, rotation) -> bool   — all-or-nothing multi-cell
#   remove_bulk(cells: Array)                             -> void   — batch remove
#   cells_in_sphere(centre, radius)                       -> Array  — cells within radius (dynamite)
#   get_dirty_chunks()                                    -> Array
#   clear_dirty_chunks()                                  -> void
#
# Signals:
#   placed(anchor_cell, definition, colour_index, rotation) — emitted after a successful place
#   removed(anchor_cell)                                    — emitted after a successful remove
#   removed_bulk(cells: Array)                              — emitted once after remove_bulk
#
# Phase 2 semantics:
#   - place_multi: pre-checks every cell in footprint before inserting any.
#     All-or-nothing: if any cell is occupied, returns false without writing.
#     Every cell in the footprint stores the SAME BrickInstance reference
#     (so query(any cell of the footprint) returns the brick).
#   - remove(anchor): looks up the BrickInstance at anchor, then erases ALL cells
#     that share the same instance (multi-cell brick removal).
#   - remove_bulk(cells): erases all cells and emits a single removed_bulk signal.
#   - _dirty_chunks: tracks which 16m×16m×16m chunks have changed for WorldSave.
#   - No persistence; state resets on quit (SQLite persistence is Plan 02-11+).
#   - No gravity: removing a supporting brick leaves the upper brick floating.
#     This is by design (DOCS.md §3.2 + §9, Features.brick_gravity = false).
#
# RESEARCH.md Pattern 4 (multi-cell placement, lines 759-778) — all-or-nothing insert.
# RESEARCH.md Pitfall 4 (partial-write corruption) — pre-check prevents it.
# RESEARCH.md Contradiction 1 (no gravity) — no falling-block algorithm here.
#
# T-09-01 mitigation: pre-check + all-or-nothing in place_multi.
# T-05-04 mitigation: raycast results from builder.gd check bounds before calling here;
# this node does NOT enforce terrain bounds (builder does).

class_name StudGrid
extends Node

# ─── BrickInstance (inner class) ─────────────────────────────────────────────

## A placed brick entry in the stud grid.
## Holds a reference to its BrickDefinition and additional Phase 2 placement data.
## The SAME instance reference is stored in every footprint cell for multi-cell bricks.
class BrickInstance:
	## BrickDefinition resource for this placed brick.
	var definition: BrickDefinition

	## Index into the per-definition MultiMeshInstance3D (Phase 2 batching).
	## Phase 1: always -1 (not yet batched); Phase 2 assigns real indices.
	var multi_mesh_index: int = -1

	## Colour index into BrickPalette.COLOURS (-1 = natural/material colour).
	var colour_index: int = -1

	## Rotation step (0..3 = 0/90/180/270 degrees around Y axis).
	## Derived from builder yaw at place time (DOCS.md §3.2 no-manual-rotation).
	var rotation: int = 0

	## The anchor cell (first cell, where place_multi was called).
	var anchor: Vector3i = Vector3i.ZERO

	func _init(def: BrickDefinition, colour: int = -1, rot: int = 0,
			anchor_cell: Vector3i = Vector3i.ZERO, index: int = -1) -> void:
		definition = def
		colour_index = colour
		rotation = rot
		anchor = anchor_cell
		multi_mesh_index = index

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when a brick is successfully placed.
## Phase 2: extended signature includes colour_index and rotation.
signal placed(anchor_cell: Vector3i, definition: BrickDefinition, colour_index: int, rotation: int)

## Emitted when a brick is successfully removed (single-cell or anchor of multi-cell).
signal removed(anchor_cell: Vector3i)

## Emitted once after remove_bulk completes (bulk removal for dynamite etc.).
signal removed_bulk(cells: Array)

## Emitted once after a bulk placement (begin_bulk/end_bulk) completes. Listeners that
## react per-brick to `placed` (e.g. the BrickRenderer multimesh) should connect to this
## and do ONE full resync instead, so a 200k-brick pre-stamp doesn't fire 200k handlers.
signal bulk_changed

# ─── Private state ────────────────────────────────────────────────────────────

## Sparse hash map keyed on stud-grid terrain anchor (Pattern 4).
## O(1) insert, remove, lookup.
var _entries: Dictionary = {}   # Dictionary[Vector3i, BrickInstance]

## Dirty-chunk tracker: keys are chunk-grid Vector3i (16m chunks), values = true.
## Cleared by WorldSave after every checkpoint (Plan 02-11).
var _dirty_chunks: Dictionary = {}  # Dictionary[Vector3i, bool]

## When true, place_multi() does NOT emit the per-brick `placed` signal. Set by
## begin_bulk()/end_bulk() around large deterministic placements (the spawn-area
## structure pre-stamp). Without this, each of ~200k pre-stamped bricks fired the
## BrickRenderer's per-brick handler, which grew the MultiMesh by one instance —
## an O(n²) buffer realloc that froze the main thread for minutes and starved the
## VoxelTerrain of mesh time (symptom: empty sky / no terrain at spawn).
var _bulk_active: bool = false

# ─── Chunk helper ─────────────────────────────────────────────────────────────

## Map a stud-grid cell to the 16m chunk it belongs to.
## Chunk grid uses right-shift by 4 (= integer divide by 16).
func _chunk_of(cell: Vector3i) -> Vector3i:
	# Arithmetic right-shift for negative numbers in GDScript uses >> on int.
	# This is equivalent to floor(cell.x / 16) but faster.
	return Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)

# ─── Public API ──────────────────────────────────────────────────────────────

## Place a brick at the given anchor cell (Phase 1 single-cell wrapper).
## Preserves Phase 1 call-site compatibility: place(anchor, def) -> bool.
## Internally calls place_multi with a 1-cell footprint.
## Returns true on success; false if the cell is already occupied.
func place(anchor_cell: Vector3i, definition: BrickDefinition) -> bool:
	return place_multi(anchor_cell, [Vector3i(0, 0, 0)], definition, -1, 0)


## Begin a bulk placement: subsequent place()/place_multi() calls still insert into the
## grid but suppress the per-brick `placed` signal. Pair with end_bulk(). Use around
## large deterministic placements (e.g. the spawn-area structure pre-stamp) to avoid
## firing per-brick listeners hundreds of thousands of times.
func begin_bulk() -> void:
	_bulk_active = true


## End a bulk placement and emit a single `bulk_changed` so listeners (BrickRenderer)
## do ONE full resync instead of per-brick work.
func end_bulk() -> void:
	if not _bulk_active:
		return
	_bulk_active = false
	bulk_changed.emit()


## Place a multi-cell brick atomically.
##
## Pre-checks every cell in the footprint. If any cell is occupied, returns false
## without writing anything (all-or-nothing: RESEARCH.md Pattern 4, Pitfall 4).
##
## Stores the SAME BrickInstance reference in every footprint cell so that
## query(any_cell_of_footprint) returns the brick.
##
## @param anchor       The cell at which placement was targeted (origin of footprint).
## @param footprint    Array[Vector3i] of offsets from anchor (e.g. [Vector3i(0,0,0)]).
## @param def          BrickDefinition resource for this brick type.
## @param colour_index Palette colour index (-1 = natural/material colour).
## @param rotation     0..3 rotation step (0/90/180/270° around Y). Clamped to 0..3.
## @return             true on success; false if any footprint cell is occupied.
func place_multi(anchor: Vector3i, footprint: Array, def: BrickDefinition,
		colour_index: int, rotation: int) -> bool:
	# Clamp rotation to valid range (T-09-02 mitigation).
	rotation = rotation & 3  # equivalent to rotation % 4, works for positive values

	# Pre-check: every footprint cell must be free.
	for offset: Variant in footprint:
		var cell: Vector3i = anchor + (offset as Vector3i)
		if _entries.has(cell):
			return false

	# All-or-nothing insert: create one instance, store in every cell.
	var instance := BrickInstance.new(def, colour_index, rotation, anchor)
	for offset: Variant in footprint:
		var cell: Vector3i = anchor + (offset as Vector3i)
		_entries[cell] = instance
		_dirty_chunks[_chunk_of(cell)] = true

	if not _bulk_active:
		placed.emit(anchor, def, colour_index, rotation)
	return true


## Remove the brick at the given anchor cell.
## For multi-cell bricks: finds the instance, then erases ALL cells that hold it.
## Returns true if a brick was present and removed; false if the cell was empty.
func remove(anchor_cell: Vector3i) -> bool:
	if not _entries.has(anchor_cell):
		return false

	var instance: BrickInstance = _entries[anchor_cell]

	# For multi-cell bricks, erase every cell that holds this instance.
	# We iterate all keys and erase those whose value matches the instance reference.
	# This is O(n) in the number of placed bricks — acceptable for Phase 2 scale.
	var cells_to_erase: Array[Vector3i] = []
	for cell: Variant in _entries.keys():
		var cell_v3: Vector3i = cell as Vector3i
		if _entries[cell_v3] == instance:
			cells_to_erase.append(cell_v3)

	for cell: Vector3i in cells_to_erase:
		_entries.erase(cell)
		_dirty_chunks[_chunk_of(cell)] = true

	removed.emit(anchor_cell)
	return true


## Remove multiple bricks in bulk (used by dynamite handler, Plan 02-11).
## Emits a single removed_bulk(cells) signal after all erasures are complete.
## Cells that are empty are silently skipped.
func remove_bulk(cells: Array) -> void:
	var actually_removed: Array = []
	# Track instances to avoid double-erasing multi-cell bricks.
	var removed_instances: Array = []

	for cell_raw: Variant in cells:
		var cell: Vector3i = cell_raw as Vector3i
		if not _entries.has(cell):
			continue
		var instance: BrickInstance = _entries[cell]
		if removed_instances.has(instance):
			continue  # already erased this multi-cell brick
		removed_instances.append(instance)

		# Erase all cells belonging to this instance.
		for other_cell: Variant in _entries.keys():
			var other: Vector3i = other_cell as Vector3i
			if _entries[other] == instance:
				_entries.erase(other)
				_dirty_chunks[_chunk_of(other)] = true
				actually_removed.append(other)

	if not actually_removed.is_empty():
		removed_bulk.emit(actually_removed)


## Query the brick at the given anchor cell.
## Returns the BrickInstance if occupied, null if empty.
## Works for any cell of a multi-cell brick (all cells share the same instance).
func query(anchor_cell: Vector3i) -> BrickInstance:
	return _entries.get(anchor_cell, null)


## Return all cells whose brick instance anchor is within the given radius from centre.
## Used by dynamite handler (Plan 02-11) to find bricks in a blast sphere.
## Centre is in world-space metres; each stud-grid cell is 1m.
func cells_in_sphere(centre: Vector3, radius: float) -> Array:
	var result: Array = []
	var radius_sq: float = radius * radius
	for cell_raw: Variant in _entries.keys():
		var cell: Vector3i = cell_raw as Vector3i
		var cell_centre := Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5)
		if cell_centre.distance_squared_to(centre) <= radius_sq:
			result.append(cell)
	return result


## Return the total number of placed brick-cells (includes multi-cell duplicates).
func size() -> int:
	return _entries.size()


## Clear all placed bricks (e.g. on world reset).
func clear() -> void:
	_entries.clear()
	_dirty_chunks.clear()


## Return all occupied anchor cells (for save serialisation).
## Phase 2: used by WorldSave.checkpoint() to iterate bricks per chunk.
func get_all_anchors() -> Array:
	return _entries.keys()


## Return the list of chunk-grid cells that have changed since the last checkpoint.
## Used by WorldSave (Plan 02-11) to determine which chunks need re-serialising.
func get_dirty_chunks() -> Array:
	return _dirty_chunks.keys()


## Clear the dirty-chunk set after a successful checkpoint.
## Called by WorldSave (Plan 02-11) after committing the chunk data to SQLite.
func clear_dirty_chunks() -> void:
	_dirty_chunks.clear()
