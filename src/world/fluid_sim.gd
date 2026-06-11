# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# fluid_sim.gd — Finite-volume, volume-conserving discrete water simulation.
#
# This is the WATER overhaul module. It sits beside the VoxelTerrain and runs a
# bounded cellular fluid tick that:
#   1. Settles water roughly flat (no vertical "walls of water") — water spreads
#      horizontally to lower terrain before it stacks vertically.
#   2. Flows when terrain is mined: mining a damming block seeds the bordering
#      water into the active set; the water floods the newly-opened space and the
#      original level drops because total volume is conserved.
#   3. Animates the spread: only a capped number of cells are processed per tick
#      and ticks fire on a fixed cadence, so the flood visibly creeps over time.
#
# ── Discrete-level model (the simplification that makes a voxel fluid tractable) ──
# The terrain mesher only knows two water states per voxel: WATER (id 7) or AIR (0).
# It has no per-cell "fill fraction" channel. So this sim keeps its OWN integer
# water level per cell in `_levels` (0..LEVEL_MAX). A cell renders as a full WATER
# voxel when its level is >= 1 and as AIR when it drains to 0. Conservation is
# tracked on the integer levels, not on the voxel grid. The voxel grid is purely
# the render target — we push level>0 -> WATER, level==0 -> AIR.
#
# Because the renderer is binary, "discrete rounded levels" manifests as: water
# fills a cell fully or not at all, and the simulation equalises horizontally first
# so a body of water reads as a flat sheet (a shoreline) rather than a sheer cliff.
# A partially-full cell (level between 1 and LEVEL_MAX-1) still renders as a full
# water voxel but will keep trying to spread/level until it is either full or empty,
# which is what gives the "settles flat" look.
#
# ── Performance (mobile budget) ──
# We NEVER scan the world. The only cells that ever tick are in `_active` (a Set of
# Vector3i packed into a Dictionary). Cells leave the active set when they reach a
# stable state and have no unstable neighbours. Each tick processes at most
# MAX_CELLS_PER_TICK cells; the remainder carry to the next tick. Settling provably
# terminates because every transfer moves volume strictly downward or strictly
# towards lower total potential, and the active set empties when no cell can move.
#
# ── Thread safety ──
# Everything here runs on the MAIN thread (driven by _physics_process via an
# accumulator). VoxelTool.get_voxel/set_voxel are main-thread calls. No worker
# threads touch this module.
#
# ── Integration ──
# main_scene instantiates one FluidSim, gives it the VoxelTerrain node, and calls
# notify_block_mined(cell) from the builder's mine path (one-line hook). The sim
# does the rest. See main_scene.gd `_fluid_sim` wiring and builder.gd `_try_break`.
#
# References:
#   src/world/multipass_generator.gd — WATER_ID=7, AIR_ID=0, sea_level=12
#   src/world/terrain.tscn           — water VoxelBlockyModelCube (transparency)
#   src/builder/builder.gd           — _try_break mine hook

class_name FluidSim
extends Node

# ─── Voxel id constants (must match terrain.tscn / multipass_generator.gd) ─────

## AIR voxel id (empty cell).
const AIR_ID: int = 0

## WATER voxel id (the single water model in the VoxelBlockyLibrary).
const WATER_ID: int = 7

## Channel used by VoxelMesherBlocky for type ids.
const CHANNEL_TYPE: int = 0  # VoxelBuffer.CHANNEL_TYPE

# ─── Discrete level model ──────────────────────────────────────────────────────

## Maximum integer water level a single cell can hold. A "full" cell is LEVEL_MAX.
## Higher values give finer settling at the cost of more transfer steps. 8 keeps
## settling quick while still reading as smoothly graded shorelines.
const LEVEL_MAX: int = 8

## A cell renders as a WATER voxel when its level is at or above this threshold.
## 1 means any non-empty cell shows water (so a thin sheet is still visible).
const RENDER_THRESHOLD: int = 1

# ─── Tick cadence + work cap (mobile budget) ───────────────────────────────────

## Seconds between fluid ticks. ~12 ticks/sec gives a visible flood crawl without
## hammering the main thread. The flood "animates" because the active set is only
## advanced once per interval.
const TICK_INTERVAL_S: float = 0.08

## Hard cap on the number of active cells processed per tick. Bounds worst-case
## per-tick cost regardless of how large the active set grows (a burst flood queues
## thousands of cells; they drain over many ticks instead of one frame spike).
const MAX_CELLS_PER_TICK: int = 256

## Safety cap on the total active-set size. If a runaway flood somehow exceeds this,
## we stop seeding new cells (existing ones still settle) so memory stays bounded.
const MAX_ACTIVE_CELLS: int = 20000

## Horizontal Chebyshev radius around a mined cell whose water neighbours get seeded
## into the active set. Small, because flow propagates outward tick-by-tick anyway.
const MINE_SEED_RADIUS: int = 1

# ─── State ─────────────────────────────────────────────────────────────────────

## The VoxelTerrain node. Set via set_terrain(); we pull a VoxelTool from it lazily.
var _terrain: Node = null

## Cached VoxelTool (VoxelToolTerrain). Re-fetched if it goes null.
var _voxel_tool: Object = null

## Per-cell integer water level. Key: Vector3i, Value: int in 1..LEVEL_MAX.
## A cell absent from this dict has level 0 (dry). We only store wet cells.
var _levels: Dictionary = {}

## Active set: cells that still need to be evaluated. Key: Vector3i, Value: true.
## Cells are removed once they reach a stable state with no unstable neighbours.
var _active: Dictionary = {}

## Carry buffer: cells deferred to the next tick because MAX_CELLS_PER_TICK was hit.
var _carry: Array[Vector3i] = []

## Accumulator driving the fixed-cadence tick from _physics_process.
var _accum: float = 0.0

## Master enable. When false, the sim is dormant (ticks early-out). Lets tests and
## headless runs construct the node without it doing any voxel work.
var _enabled: bool = true

# ─── Signals ───────────────────────────────────────────────────────────────────

## Emitted after each tick that changed at least one voxel. Payload: number of
## cells whose rendered voxel changed this tick. Useful for tests + debug HUD.
signal water_changed(changed_cell_count: int)

# ─── Setup ─────────────────────────────────────────────────────────────────────

## Wire the VoxelTerrain this sim edits. Safe to pass null (sim stays dormant).
func set_terrain(terrain: Node) -> void:
	_terrain = terrain
	_voxel_tool = null  # force re-fetch on next use


## Enable/disable ticking. Disabled sims do no voxel work (used by headless tests
## that exercise the pure level math without a live terrain).
func set_enabled(enabled: bool) -> void:
	_enabled = enabled


## Lazily fetch (and cache) the terrain's VoxelTool. Returns null if unavailable.
func _get_tool() -> Object:
	if _voxel_tool != null:
		return _voxel_tool
	if _terrain == null or not _terrain.has_method("get_voxel_tool"):
		return null
	_voxel_tool = _terrain.get_voxel_tool()
	if _voxel_tool != null and "channel" in _voxel_tool:
		_voxel_tool.channel = CHANNEL_TYPE
	return _voxel_tool


# ─── Public API ────────────────────────────────────────────────────────────────

## Notify the sim that a terrain voxel was mined (removed -> AIR) at `cell`.
## This is the one-line hook the builder calls. It seeds any bordering water cells
## into the active set so they flow into the freshly-opened space.
##
## We read the actual voxel grid around the mined cell (the authoritative source of
## where water currently is), import any WATER voxels we don't yet track into
## `_levels` at full level, and mark them + the mined cell active.
func notify_block_mined(cell: Vector3i) -> void:
	if not _enabled:
		return
	# The mined cell is now air; make sure we don't think it holds water.
	_levels.erase(cell)
	# Seed neighbours: any water touching the mined cell (incl. the cell directly
	# above, which will fall in) becomes active so it starts flowing this tick.
	for offset in _NEIGHBOUR_OFFSETS_INCL_UP:
		var n: Vector3i = cell + offset
		_import_voxel_water(n)
		if _levels.has(n):
			_mark_active(n)
	# Also import + activate water within a small XZ radius so a wide dam break
	# doesn't leave far cells stranded for a tick.
	for dx in range(-MINE_SEED_RADIUS, MINE_SEED_RADIUS + 1):
		for dz in range(-MINE_SEED_RADIUS, MINE_SEED_RADIUS + 1):
			var n2: Vector3i = Vector3i(cell.x + dx, cell.y, cell.z + dz)
			_import_voxel_water(n2)
			if _levels.has(n2):
				_mark_active(n2)
	# The mined cell itself is active so water can fall/flow into it.
	_mark_active(cell)


## Seed a water source at `cell` with a given level (clamped 1..LEVEL_MAX). Used by
## generation/tests to register existing ocean water with the sim, or by a future
## "place water" tool. Writes the render voxel immediately.
func add_water(cell: Vector3i, level: int = LEVEL_MAX) -> void:
	if not _enabled:
		return
	var lv: int = clampi(level, 1, LEVEL_MAX)
	_levels[cell] = lv
	_write_voxel(cell, WATER_ID)
	_mark_active(cell)


## Total tracked water volume in level-units. Test/diagnostic aid: conservation
## checks assert this is constant across settling ticks (no source/sink).
func total_volume() -> int:
	var sum: int = 0
	for v in _levels.values():
		sum += int(v)
	return sum


## Number of cells currently queued for processing (active + carried).
func active_count() -> int:
	return _active.size() + _carry.size()


## True if `cell` currently tracks water (level >= 1). Diagnostic/test aid.
func has_water_at(cell: Vector3i) -> bool:
	return int(_levels.get(cell, 0)) >= 1


## Number of distinct cells currently holding water. Diagnostic/test aid.
func wet_cell_count() -> int:
	return _levels.size()


# ─── Tick loop ─────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _enabled:
		return
	if _active.is_empty() and _carry.is_empty():
		return
	_accum += delta
	if _accum < TICK_INTERVAL_S:
		return
	_accum = 0.0
	_tick()


## Advance the simulation by one step. Processes up to MAX_CELLS_PER_TICK cells from
## the active set (plus anything carried from last tick). Cells that move volume
## re-activate their neighbours; cells that are stable are dropped from the set.
##
## Exposed (not prefixed _step) so headless tests can drive deterministic ticks
## without a real clock.
func step() -> void:
	_tick()


func _tick() -> void:
	# Build this tick's work list: carry-over first, then drain the active set.
	var work: Array[Vector3i] = []
	for c in _carry:
		work.append(c)
	_carry.clear()
	# Snapshot active keys so we can mutate _active while iterating.
	for c in _active.keys():
		work.append(c)
		if work.size() >= MAX_CELLS_PER_TICK:
			break
	# Remove the cells we took from the active set; _process_cell re-adds the
	# unstable ones (and their neighbours). Cells beyond the cap stay in _active.
	for c in work:
		_active.erase(c)

	var changed: int = 0
	var processed: int = 0
	for cell in work:
		if processed >= MAX_CELLS_PER_TICK:
			# Over budget: carry the rest to next tick (keeps the flood animating).
			_carry.append(cell)
			continue
		processed += 1
		changed += _process_cell(cell)

	if changed > 0:
		water_changed.emit(changed)


## Evaluate a single water cell: try to fall, then spread to lower terrain / lower
## neighbours, conserving total volume. Returns the number of render-voxel changes
## this produced (for the water_changed counter). Re-activates any cell it touches.
##
## Order of operations (gravity first, then equalise) is what kills vertical walls:
##   1. FALL: move as much as possible straight down into air / unfilled cells.
##   2. SPREAD: equalise with the 4 horizontal neighbours toward a flat surface,
##      preferring neighbours that have air below them (so water seeks the lowest
##      ground first, forming a shoreline instead of a cliff).
func _process_cell(cell: Vector3i) -> int:
	var level: int = int(_levels.get(cell, 0))
	if level <= 0:
		# Dry cell that lingered in the set: make sure its voxel is air and drop it.
		_clear_if_water(cell)
		return 0
	if _is_solid(cell):
		# Terrain grew under us (or this was never valid water): discard the level.
		_levels.erase(cell)
		_mark_neighbours_active(cell)
		return 0

	var changed: int = 0

	# ── 1. FALL straight down ────────────────────────────────────────────────
	var below: Vector3i = cell + Vector3i(0, -1, 0)
	if not _is_solid(below):
		var below_level: int = int(_levels.get(below, 0))
		var space_below: int = LEVEL_MAX - below_level
		if space_below > 0:
			var move: int = mini(level, space_below)
			if move > 0:
				changed += _set_level(below, below_level + move)
				level -= move
				changed += _set_level(cell, level)
				_mark_active(below)
				_mark_neighbours_active(below)
				if level <= 0:
					# Fully drained downward; neighbours may now want to flow here.
					_mark_neighbours_active(cell)
					return changed

	# ── 2. SPREAD horizontally toward lower ground / lower water ─────────────
	# A neighbour is a valid sink if it is not solid AND either:
	#   (a) it has air directly below it (water should run downhill to it), or
	#   (b) its level is at least 2 below ours (equalise to roughly flat).
	var any_unstable: bool = false
	for offset in _HORIZONTAL_OFFSETS:
		if level <= RENDER_THRESHOLD:
			break  # keep at least a thin film here; don't drain the last unit away
		var n: Vector3i = cell + offset
		if _is_solid(n):
			continue
		var n_level: int = int(_levels.get(n, 0))
		var below_n: Vector3i = n + Vector3i(0, -1, 0)
		var downhill: bool = not _is_solid(below_n) \
			and int(_levels.get(below_n, 0)) < LEVEL_MAX
		if downhill:
			# Push aggressively toward a cell that can drain further down.
			var give: int = level - RENDER_THRESHOLD
			give = mini(give, LEVEL_MAX - n_level)
			if give > 0:
				changed += _set_level(n, n_level + give)
				level -= give
				changed += _set_level(cell, level)
				_mark_active(n)
				any_unstable = true
		elif level - n_level >= 2:
			# Equalise: move half the difference so both approach the mean (flat).
			var diff: int = level - n_level
			var move: int = diff / 2
			move = mini(move, LEVEL_MAX - n_level)
			if move > 0:
				changed += _set_level(n, n_level + move)
				level -= move
				changed += _set_level(cell, level)
				_mark_active(n)
				any_unstable = true

	# Stay active ONLY if this cell is genuinely unstable, so a settled flat ocean
	# drops out of the active set (termination — never re-queue a stable cell).
	# Unstable means: we moved water this call (any_unstable), OR we still have
	# unused headroom to fall into the cell below (below is open AND not full).
	# A full cell resting on full water / solid ground with even neighbours is
	# stable and is NOT re-queued.
	if level > 0 and not _is_solid(cell):
		var below2: Vector3i = cell + Vector3i(0, -1, 0)
		var has_fall_room: bool = not _is_solid(below2) \
			and int(_levels.get(below2, 0)) < LEVEL_MAX
		if any_unstable or has_fall_room:
			_mark_active(cell)
	return changed


# ─── Level <-> voxel bridge ────────────────────────────────────────────────────

## Set a cell's tracked level (0 erases it) and sync its render voxel. Returns 1 if
## the rendered voxel state (water vs air) flipped, else 0.
func _set_level(cell: Vector3i, level: int) -> int:
	var lv: int = clampi(level, 0, LEVEL_MAX)
	var was_water: bool = int(_levels.get(cell, 0)) >= RENDER_THRESHOLD
	if lv <= 0:
		_levels.erase(cell)
	else:
		_levels[cell] = lv
	var is_water: bool = lv >= RENDER_THRESHOLD
	if was_water == is_water:
		return 0
	_write_voxel(cell, WATER_ID if is_water else AIR_ID)
	return 1


## Read the live voxel grid; if `cell` holds a WATER voxel we don't yet track,
## import it into `_levels` at full level. Lets the sim pick up ocean water that
## was generated by the terrain generator (which writes WATER voxels directly).
func _import_voxel_water(cell: Vector3i) -> void:
	if _levels.has(cell):
		return
	var tool: Object = _get_tool()
	if tool == null:
		return
	if tool.get_voxel(cell) == WATER_ID:
		_levels[cell] = LEVEL_MAX


## True if the voxel at `cell` is solid terrain (anything that isn't air or water).
func _is_solid(cell: Vector3i) -> bool:
	# Our own tracked water is never "solid".
	if _levels.has(cell):
		return false
	var tool: Object = _get_tool()
	if tool == null:
		# No terrain access: treat unknown cells as open so pure-math tests still run.
		return false
	var v: int = tool.get_voxel(cell)
	return v != AIR_ID and v != WATER_ID


## If the cell currently renders water but we no longer track it, clear it to air.
func _clear_if_water(cell: Vector3i) -> void:
	var tool: Object = _get_tool()
	if tool == null:
		return
	if tool.get_voxel(cell) == WATER_ID and not _levels.has(cell):
		_write_voxel(cell, AIR_ID)


## Write a voxel id at `cell` through the VoxelTool (no-op if no terrain).
func _write_voxel(cell: Vector3i, voxel_id: int) -> void:
	var tool: Object = _get_tool()
	if tool == null:
		return
	tool.set_voxel(cell, voxel_id)


# ─── Active-set bookkeeping ─────────────────────────────────────────────────────

## Add a cell to the active set (bounded by MAX_ACTIVE_CELLS).
func _mark_active(cell: Vector3i) -> void:
	if _active.size() >= MAX_ACTIVE_CELLS:
		return
	_active[cell] = true


## Re-activate the 6 axis neighbours of a cell (used after a transfer so adjacent
## water re-evaluates and the flood front keeps moving).
##
## Crucially this also IMPORTS any neighbour that is an untracked WATER voxel in the
## live grid (the rest of a generated ocean body) into `_levels` before activating it.
## That is how a dam break draws on the whole ocean: the active front crawls outward
## through existing water voxels, converting them to tracked cells tick by tick, so the
## SOURCE level genuinely lowers as volume conserves into the flooded basin.
func _mark_neighbours_active(cell: Vector3i) -> void:
	for offset in _NEIGHBOUR_OFFSETS_INCL_UP:
		var n: Vector3i = cell + offset
		if not _levels.has(n):
			_import_voxel_water(n)  # pull in adjacent ocean water if present
		if _levels.has(n):
			_mark_active(n)


# ─── Static neighbour-offset tables ─────────────────────────────────────────────

## The 4 horizontal (XZ) neighbour offsets.
const _HORIZONTAL_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## The 4 horizontal offsets plus up and down (6-neighbourhood). Used when seeding /
## re-activating so the cell directly above (which falls in) is always included.
const _NEIGHBOUR_OFFSETS_INCL_UP: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
]
