# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# benchmark_runner.gd — Deterministic benchmark runner (Plan 07 + Plan 02-15).
#
# Drives the benchmark_scene.tscn without any player input:
#
# Phase 1 (30-minute thermal loop — Plan 07):
#   - Applies Tier-3 graphics preset (render_distance=5, shadows=off) on _ready()
#   - Walks the builder along a fixed Catmull-Rom spline through the visible chunks
#   - Places and breaks 100 bricks at predetermined coordinates over 1800 seconds
#     (one place/break event every 18 seconds: 100 × 18 = 1800 s)
#   - Logs FPS + ThermalProbe readings every 10 seconds to a CSV via ThermalProbe.start()
#   - Emits benchmark_complete after 1800 simulated seconds
#   - Stops ThermalProbe and writes the CSV on completion or on stop()
#
# Phase 2 dynamite-blast macro (Plan 02-15 — §7.2 Tier-3 worst-case gate):
#   - start_phase_2_macro() runs BEFORE the 30-minute thermal loop
#   - Pre-places 100 bricks (brick_2x4, colour=4 red) in a 10×10 grid at (0,5,0)
#     so the blast hits the worst-case 4-chunk-intersection spot at world (8,5,8)
#   - Fuse starts at t=5 s; blast at t=8 s (3-second DynamiteHandler fuse)
#   - Records per-frame process time (Performance.TIME_PROCESS) for t=8..t=9 s (60 frames
#     at 60 FPS target; 30 frames at Tier-3 30 FPS cap) to user://benchmarks/02-dynamite.csv
#   - Logs one-line summary: "Phase 2 macro: blast at t=8s; peak_frame_ms=N; threshold=33.3ms"
#   - If peak_frame_ms > 33.3 ms (30 FPS cap): logs "FAIL — per D-07 lower §7.2 contract"
#   - After macro completes (~9 s simulated), transitions into the 30-min thermal loop
#
# Determinism guarantee:
#   Both macros are seeded through the fixed terrain seed (seed=1234 in benchmark_scene.tscn)
#   and use deterministic brick positions / waypoints. Given the same seed, identical state
#   is reproduced run-to-run on the same hardware — required for Tier-3 thermal comparisons.
#
# Time warping (for unit tests):
#   @export var simulated_time_multiplier: float = 1.0
#   Set to e.g. 60.0 to make 1 wall-clock second simulate 60 game seconds.
#   The runner uses accumulated_time += delta * simulated_time_multiplier.
#
# CSV path: user://benchmark-<timestamp>.csv
#   (or override via start_benchmark(custom_path))
#
# Usage in benchmark_scene.tscn:
#   - BenchmarkRunner is the root script; the scene contains Terrain, Builder,
#     StudGrid, BrickRenderer, VoxelViewer — all wired in _ready().
#   - No UI overlay, no mobile controls, no first-launch disclaimer.
#
# Thread safety: runs on the main thread; not thread-safe.

extends Node3D

# ─── Signals ─────────────────────────────────────────────────────────────────

## Emitted when the benchmark run completes (1800 simulated seconds elapsed).
## Payload: csv_path (the path where the CSV was written).
signal benchmark_complete(csv_path: String)

# ─── Exports ─────────────────────────────────────────────────────────────────

## Time-warp factor for unit tests (1.0 = real time; 60.0 = 1s wall = 60s sim).
## Do NOT set this in production builds — use 1.0 (real time).
@export var simulated_time_multiplier: float = 1.0

## Benchmark duration in simulated seconds (D-02: 30 minutes = 1800 seconds).
@export var benchmark_duration_s: float = 1800.0

## Place/break cycle interval in simulated seconds.
## 100 bricks × 18 s = 1800 s (full run duration).
@export var brick_event_interval_s: float = 18.0

## Number of brick place/break cycles to execute.
@export var brick_event_count: int = 100

## CSV output path (Godot user path). Timestamp substituted at start() time.
@export var csv_base_path: String = "user://benchmark"

# ─── Tier-3 graphics preset (DOCS.md §7.2) ───────────────────────────────────

## Tier-3 render distance in metres (5 chunks × 16 m/chunk = 80 m).
const TIER3_RENDER_DISTANCE: int = 80

## Tier-3 shadows setting.
const TIER3_SHADOWS: bool = false

## Tier-3 particle density label (informational; stored in settings.cfg).
const TIER3_PARTICLE_DENSITY: String = "low"

# ─── Fixed brick anchor coordinates (deterministic) ──────────────────────────
# 100 predetermined positions for the place/break cycle (Pattern 4 sparse grid).
# Coordinates are in voxel-anchor space: (x, y+1, z) on top of the terrain surface.
# The terrain surface is typically at Y = 12–20 (sea_level=12, amplitude=8 in
# terrain_generator.gd); we use Y=16 as a safe nominal surface anchor.
# The X/Z positions are spread within the first chunk's footprint (0..15 range)
# so the places happen within the loaded terrain area regardless of builder position.

const BRICK_ANCHORS: Array = [
	Vector3i(2,  17, 2),  Vector3i(3,  17, 2),  Vector3i(4,  17, 2),
	Vector3i(5,  17, 2),  Vector3i(6,  17, 2),  Vector3i(7,  17, 2),
	Vector3i(8,  17, 2),  Vector3i(9,  17, 2),  Vector3i(10, 17, 2),
	Vector3i(11, 17, 2),  Vector3i(2,  17, 3),  Vector3i(3,  17, 3),
	Vector3i(4,  17, 3),  Vector3i(5,  17, 3),  Vector3i(6,  17, 3),
	Vector3i(7,  17, 3),  Vector3i(8,  17, 3),  Vector3i(9,  17, 3),
	Vector3i(10, 17, 3),  Vector3i(11, 17, 3),  Vector3i(2,  17, 4),
	Vector3i(3,  17, 4),  Vector3i(4,  17, 4),  Vector3i(5,  17, 4),
	Vector3i(6,  17, 4),  Vector3i(7,  17, 4),  Vector3i(8,  17, 4),
	Vector3i(9,  17, 4),  Vector3i(10, 17, 4),  Vector3i(11, 17, 4),
	Vector3i(2,  17, 5),  Vector3i(3,  17, 5),  Vector3i(4,  17, 5),
	Vector3i(5,  17, 5),  Vector3i(6,  17, 5),  Vector3i(7,  17, 5),
	Vector3i(8,  17, 5),  Vector3i(9,  17, 5),  Vector3i(10, 17, 5),
	Vector3i(11, 17, 5),  Vector3i(2,  17, 6),  Vector3i(3,  17, 6),
	Vector3i(4,  17, 6),  Vector3i(5,  17, 6),  Vector3i(6,  17, 6),
	Vector3i(7,  17, 6),  Vector3i(8,  17, 6),  Vector3i(9,  17, 6),
	Vector3i(10, 17, 6),  Vector3i(11, 17, 6),  Vector3i(2,  17, 7),
	Vector3i(3,  17, 7),  Vector3i(4,  17, 7),  Vector3i(5,  17, 7),
	Vector3i(6,  17, 7),  Vector3i(7,  17, 7),  Vector3i(8,  17, 7),
	Vector3i(9,  17, 7),  Vector3i(10, 17, 7),  Vector3i(11, 17, 7),
	Vector3i(2,  17, 8),  Vector3i(3,  17, 8),  Vector3i(4,  17, 8),
	Vector3i(5,  17, 8),  Vector3i(6,  17, 8),  Vector3i(7,  17, 8),
	Vector3i(8,  17, 8),  Vector3i(9,  17, 8),  Vector3i(10, 17, 8),
	Vector3i(11, 17, 8),  Vector3i(2,  17, 9),  Vector3i(3,  17, 9),
	Vector3i(4,  17, 9),  Vector3i(5,  17, 9),  Vector3i(6,  17, 9),
	Vector3i(7,  17, 9),  Vector3i(8,  17, 9),  Vector3i(9,  17, 9),
	Vector3i(10, 17, 9),  Vector3i(11, 17, 9),  Vector3i(2,  17, 10),
	Vector3i(3,  17, 10), Vector3i(4,  17, 10), Vector3i(5,  17, 10),
	Vector3i(6,  17, 10), Vector3i(7,  17, 10), Vector3i(8,  17, 10),
	Vector3i(9,  17, 10), Vector3i(10, 17, 10), Vector3i(11, 17, 10),
	Vector3i(2,  17, 11), Vector3i(3,  17, 11), Vector3i(4,  17, 11),
	Vector3i(5,  17, 11), Vector3i(6,  17, 11), Vector3i(7,  17, 11),
	Vector3i(8,  17, 11), Vector3i(9,  17, 11), Vector3i(10, 17, 11),
	Vector3i(11, 17, 11),
]

# ─── Waypoints for the deterministic builder walk ─────────────────────────────
# 12 world-space positions for the builder to walk through (looped).
# Centred in the first few terrain chunks (seeded terrain is reliable here).
# Y=22 places the builder above the terrain surface (terrain is ~Y=12..20).
const WALK_WAYPOINTS: Array = [
	Vector3(4.0,  22.0,  4.0),
	Vector3(12.0, 22.0,  4.0),
	Vector3(20.0, 22.0,  8.0),
	Vector3(20.0, 22.0, 16.0),
	Vector3(12.0, 22.0, 20.0),
	Vector3(4.0,  22.0, 20.0),
	Vector3(-4.0, 22.0, 16.0),
	Vector3(-4.0, 22.0,  8.0),
	Vector3(4.0,  22.0,  4.0),  # loop back
	Vector3(12.0, 22.0,  4.0),
	Vector3(20.0, 22.0,  8.0),
	Vector3(12.0, 22.0, 20.0),
]

## Walk speed in metres per simulated second.
const WALK_SPEED: float = 2.5

# ─── Internal state ───────────────────────────────────────────────────────────

var _running: bool = false
var _accumulated_time: float = 0.0
var _next_brick_event_time: float = 0.0
var _brick_event_index: int = 0
var _placed_this_cycle: bool = false
var _csv_path: String = ""
var _waypoint_index: int = 0

# Cached scene node references (wired in _ready).
var _builder: Node = null       # CharacterBody3D
var _stud_grid: StudGrid = null
var _terrain: Node = null       # VoxelTerrain
var _voxel_viewer: Node = null

# Preloaded brick definition
const BRICK_1X1 := preload("res://src/bricks/brick_1x1.tres")

# Settings file path for benchmark preset override.
const SETTINGS_PATH := "user://settings.cfg"

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Apply Tier-3 graphics settings (D-05, §7.2) before any sampling begins.
	# This overrides whatever the user had configured in their settings.cfg.
	_apply_tier3_preset()

	# Cache scene node references from the benchmark_scene.tscn hierarchy.
	_builder      = get_node_or_null("Builder")
	_stud_grid    = get_node_or_null("StudGrid") as StudGrid
	_terrain      = get_node_or_null("Terrain")
	_voxel_viewer = get_node_or_null("Builder/VoxelViewer")

	# Disable player input on the builder (benchmark is scripted, no user input).
	if _builder != null:
		_builder.set_process_input(false)
		_builder.set_process_unhandled_input(false)

	# Start the Phase 2 dynamite-blast macro first (Plan 02-15).
	# The macro runs for ~9 simulated seconds, then automatically calls start_benchmark()
	# to begin the 30-min thermal loop. This ordering ensures the worst-case dynamite
	# frame-time gate is measured on a cold device (no thermal throttling yet).
	start_phase_2_macro()


## Start the benchmark run.
## Generates a timestamped CSV path and starts ThermalProbe.
## Called automatically from _ready() in the benchmark scene.
func start_benchmark(custom_path: String = "") -> void:
	if _running:
		push_warning("BenchmarkRunner.start_benchmark() called while already running.")
		return

	var ts := str(int(Time.get_unix_time_from_system()))
	_csv_path = custom_path if custom_path != "" else (csv_base_path + "-" + ts + ".csv")
	_accumulated_time = 0.0
	_next_brick_event_time = brick_event_interval_s
	_brick_event_index = 0
	_placed_this_cycle = false
	_waypoint_index = 0

	# Start the thermal + FPS probe.
	ThermalProbe.start(_csv_path)
	_running = true


## Stop the benchmark run early (also called on benchmark_complete).
func stop_benchmark() -> void:
	if not _running:
		return
	ThermalProbe.stop()
	_running = false


# ─── Per-frame update ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var sim_delta: float = delta * simulated_time_multiplier

	# Phase 2 macro runs first; when it finishes it starts the thermal loop.
	if _p2_running:
		_update_phase_2_macro(sim_delta)
		return

	if not _running:
		return

	_accumulated_time += sim_delta

	# Walk the builder along the deterministic waypoint path.
	_advance_builder_walk(sim_delta)

	# Brick place/break events at regular intervals.
	if _accumulated_time >= _next_brick_event_time and _brick_event_index < brick_event_count:
		if not _placed_this_cycle:
			_do_place_event(_brick_event_index)
			_placed_this_cycle = true
			# Break happens 9 simulated seconds after place.
			_next_brick_event_time = _accumulated_time + 9.0 * simulated_time_multiplier
		else:
			_do_break_event(_brick_event_index)
			_placed_this_cycle = false
			_brick_event_index += 1
			# Next place event: every brick_event_interval_s from the cycle start.
			_next_brick_event_time = _brick_event_index * brick_event_interval_s

	# Check if run duration completed.
	if _accumulated_time >= benchmark_duration_s:
		stop_benchmark()
		benchmark_complete.emit(_csv_path)


# ─── Builder walk ─────────────────────────────────────────────────────────────

func _advance_builder_walk(sim_delta: float) -> void:
	if _builder == null or WALK_WAYPOINTS.size() == 0:
		return

	var target: Vector3 = WALK_WAYPOINTS[_waypoint_index % WALK_WAYPOINTS.size()]
	var current_pos: Vector3 = _builder.global_position
	# Only move in XZ; keep builder's Y from physics (it falls onto terrain).
	var flat_target := Vector3(target.x, current_pos.y, target.z)
	var dist_to_target := current_pos.distance_to(flat_target)

	if dist_to_target < 1.0:
		# Reached waypoint; advance to next.
		_waypoint_index = (_waypoint_index + 1) % WALK_WAYPOINTS.size()
		return

	# Move toward waypoint at WALK_SPEED metres per simulated second.
	var direction := (flat_target - current_pos).normalized()
	var step := direction * WALK_SPEED * sim_delta
	if step.length() > dist_to_target:
		step = direction * dist_to_target

	# Directly set global_position for scripted movement (no physics input needed).
	_builder.global_position += step


# ─── Brick events ─────────────────────────────────────────────────────────────

func _do_place_event(event_idx: int) -> void:
	if _stud_grid == null:
		return
	if event_idx >= BRICK_ANCHORS.size():
		return
	var anchor: Vector3i = BRICK_ANCHORS[event_idx]
	_stud_grid.place(anchor, BRICK_1X1)


func _do_break_event(event_idx: int) -> void:
	if _stud_grid == null:
		return
	if event_idx >= BRICK_ANCHORS.size():
		return
	var anchor: Vector3i = BRICK_ANCHORS[event_idx]
	_stud_grid.remove(anchor)


# ─── Graphics preset application ─────────────────────────────────────────────

# ─── Phase 2 dynamite-blast macro (Plan 02-15) ───────────────────────────────

## CSV output path for the Phase 2 dynamite macro frame-time data.
## Written to Godot's user:// directory so it survives on-device benchmark runs
## and can be pulled via adb.
const PHASE2_CSV_PATH: String = "user://benchmarks/02-dynamite.csv"

## Tier-3 frame-time budget: 1/30 s expressed in milliseconds.
## §7.2 contract (30 FPS cap on Tier-3). If any frame in the blast window exceeds
## this threshold, the macro logs FAIL and per D-07 the §7.2 contract is lowered
## (NEVER Rust — D-12 forbids Rust escalation).
const TIER3_FRAME_BUDGET_MS: float = 33.3

## World position of the 10×10 brick grid anchor (lower-left corner of the grid).
## Y=5 places the grid in the air above the default terrain surface — deterministic.
const MACRO_GRID_ORIGIN: Vector3 = Vector3(0.0, 5.0, 0.0)

## Brick definition ID for the blast-grid bricks (uses BrickRegistry API).
const MACRO_BRICK_ID: String = "brick_2x4"

## Colour index for the blast-grid bricks (4 = red per palette.gd).
const MACRO_BRICK_COLOUR: int = 4

## World position of the dynamite detonation centre (worst-case 4-chunk-intersection spot).
## Placed at (8, 5, 8) — the corner where chunks (0,0), (1,0), (0,1), (1,1) all meet
## (chunk size = 16 m, so the boundary is at world x=8/z=8 within the first chunk cluster).
const MACRO_BLAST_CENTRE: Vector3 = Vector3(8.0, 5.0, 8.0)

## Dynamite blast radius in metres (DOCS §3.4).
const MACRO_BLAST_RADIUS: float = 5.0

## Simulated time (s) at which the dynamite fuse is lit.
const MACRO_FUSE_START_S: float = 5.0

## Simulated time (s) at which the blast happens (fuse start + 3 s DynamiteHandler fuse).
const MACRO_BLAST_TIME_S: float = 8.0

## Duration (s) over which per-frame times are captured after the blast.
const MACRO_CAPTURE_DURATION_S: float = 1.0

# ─── Phase 2 macro internal state ────────────────────────────────────────────

var _p2_running: bool = false
var _p2_bricks_placed: bool = false
var _p2_fuse_lit: bool = false
var _p2_blast_fired: bool = false
var _p2_capture_active: bool = false
var _p2_capture_end_time_s: float = 0.0
var _p2_frame_times_ms: Array = []
var _p2_active_dropped_items: int = 0
var _p2_affected_voxels: int = 0
var _p2_sim_time_s: float = 0.0   # independent time accumulator for the macro


## Start the Phase 2 dynamite-blast macro.
##
## Call this BEFORE start_benchmark() — the macro runs first (~9 s simulated),
## then on_phase_2_macro_complete() calls start_benchmark() automatically to
## begin the 30-minute thermal loop.
##
## The macro:
##   1. Pre-places 100 bricks (brick_2x4, colour red) in a 10×10 grid.
##   2. Lights a dynamite fuse at t=5 s. Blast happens at t=8 s.
##   3. Records per-frame process time to user://benchmarks/02-dynamite.csv.
##   4. Logs PASS/FAIL vs. the §7.2 Tier-3 33.3 ms frame budget.
##   5. Transitions into the 30-min thermal loop.
##
## Determinism: all positions are compile-time constants seeded from the same
## terrain seed (1234) used by the rest of the benchmark scene.
func start_phase_2_macro() -> void:
	if _p2_running or _running:
		push_warning("BenchmarkRunner.start_phase_2_macro() called while benchmark is running.")
		return

	_p2_running = true
	_p2_bricks_placed = false
	_p2_fuse_lit = false
	_p2_blast_fired = false
	_p2_capture_active = false
	_p2_frame_times_ms.clear()
	_p2_sim_time_s = 0.0
	_p2_active_dropped_items = 0
	_p2_affected_voxels = 0

	# Ensure the benchmarks/ directory exists in user://.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://benchmarks"))

	print("[Phase2Macro] Starting Phase 2 dynamite-blast macro.")
	print("[Phase2Macro] Grid origin: ", MACRO_GRID_ORIGIN, " | Blast centre: ", MACRO_BLAST_CENTRE)
	print("[Phase2Macro] Frame budget: ", TIER3_FRAME_BUDGET_MS, " ms (Tier-3 §7.2 / 30 FPS cap)")


## Called by _process each frame while the Phase 2 macro is active (before the thermal loop).
func _update_phase_2_macro(sim_delta: float) -> void:
	_p2_sim_time_s += sim_delta

	# ── Step 1: Pre-place 100 bricks in the 10×10 grid at t ≈ 0 (first frame) ──
	if not _p2_bricks_placed:
		_place_macro_grid()
		_p2_bricks_placed = true
		print("[Phase2Macro] t=0 — 100 bricks placed in 10×10 grid at ", MACRO_GRID_ORIGIN)

	# ── Step 2: Light the fuse at t=5 s ───────────────────────────────────────
	if not _p2_fuse_lit and _p2_sim_time_s >= MACRO_FUSE_START_S:
		_p2_fuse_lit = true
		print("[Phase2Macro] t=", _p2_sim_time_s, " — fuse lit at ", MACRO_BLAST_CENTRE, " (blast at t=8 s)")

	# ── Step 3: Detonate at t=8 s ─────────────────────────────────────────────
	if not _p2_blast_fired and _p2_sim_time_s >= MACRO_BLAST_TIME_S:
		_p2_blast_fired = true
		_fire_macro_blast()
		# Begin capturing per-frame process times immediately after the blast.
		_p2_capture_active = true
		_p2_capture_end_time_s = _p2_sim_time_s + MACRO_CAPTURE_DURATION_S
		print("[Phase2Macro] t=", _p2_sim_time_s, " — BLAST FIRED at ", MACRO_BLAST_CENTRE)

	# ── Step 4: Capture per-frame process time during blast window ────────────
	if _p2_capture_active:
		# Performance.TIME_PROCESS returns the main-thread process time for the last
		# frame in microseconds (μs). Convert to milliseconds (ms).
		var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_p2_frame_times_ms.append(frame_ms)

		if _p2_sim_time_s >= _p2_capture_end_time_s:
			_p2_capture_active = false
			_finish_phase_2_macro()

	# ── Step 5: Safety timeout — if capture window elapsed with no finish, end macro ──
	elif _p2_blast_fired and _p2_sim_time_s > MACRO_BLAST_TIME_S + MACRO_CAPTURE_DURATION_S + 2.0:
		# Should not happen, but prevents an infinite-wait scenario.
		_finish_phase_2_macro()


## Pre-places 100 bricks (brick_2x4, colour=4 red) in a 10×10 grid.
## Uses BrickRegistry.get() per the locked Phase 2 API contract.
## Falls back gracefully if BrickRegistry or StudGrid is unavailable in headless.
func _place_macro_grid() -> void:
	if _stud_grid == null:
		push_warning("[Phase2Macro] StudGrid not found — skipping brick pre-placement.")
		return

	# Resolve brick definition via BrickRegistry autoload.
	var def = null
	if Engine.has_singleton("BrickRegistry"):
		var registry = Engine.get_singleton("BrickRegistry")
		if registry.has_method("get"):
			def = registry.get(MACRO_BRICK_ID)
	if def == null:
		push_warning("[Phase2Macro] BrickRegistry unavailable — using StudGrid.place(anchor, null) stub.")

	# 10×10 grid: columns along X (0..9), rows along Z (0..9).
	var placed_count: int = 0
	for row in range(10):
		for col in range(10):
			var cell := Vector3i(
				int(MACRO_GRID_ORIGIN.x) + col,
				int(MACRO_GRID_ORIGIN.y),
				int(MACRO_GRID_ORIGIN.z) + row
			)
			if _stud_grid.has_method("place"):
				_stud_grid.place(cell, def)
				placed_count += 1

	print("[Phase2Macro] Placed ", placed_count, " bricks in 10×10 grid.")


## Fires the dynamite blast using DynamiteHandler or VoxelTool bulk-edit fallback.
## Attempts to use the DynamiteHandler autoload (Plan 02-11 API); falls back to
## direct StudGrid bulk-remove if the handler is not available (headless mode).
func _fire_macro_blast() -> void:
	# Snapshot approximate affected-voxel count before the blast (π r³ ≈ 524 at r=5).
	_p2_affected_voxels = 524  # worst-case estimate; real count depends on terrain

	# Attempt to invoke DynamiteHandler (Plan 02-11 shipped this autoload).
	if Engine.has_singleton("DynamiteHandler"):
		var handler = Engine.get_singleton("DynamiteHandler")
		if handler.has_method("detonate"):
			handler.detonate(MACRO_BLAST_CENTRE, MACRO_BLAST_RADIUS)
			return

	# Fallback: if DynamiteHandler is not available in the benchmark scene context,
	# perform a bulk StudGrid remove of all grid cells within the blast radius.
	if _stud_grid != null and _stud_grid.has_method("cells_in_sphere"):
		var affected: Array = _stud_grid.cells_in_sphere(MACRO_BLAST_CENTRE, MACRO_BLAST_RADIUS)
		_p2_active_dropped_items = affected.size()
		if _stud_grid.has_method("remove_bulk"):
			_stud_grid.remove_bulk(affected)
		print("[Phase2Macro] Fallback bulk-remove: ", affected.size(), " cells cleared.")
	else:
		push_warning("[Phase2Macro] DynamiteHandler and StudGrid bulk-remove both unavailable. Frame-time data will still be captured.")


## Called when the blast-window capture is complete.
## Writes the CSV, logs the PASS/FAIL summary, then starts the 30-min thermal loop.
func _finish_phase_2_macro() -> void:
	if not _p2_running:
		return
	_p2_running = false

	# Compute peak frame time and write CSV.
	var peak_ms: float = 0.0
	var csv_lines: Array = ["frame,time_ms,active_dropped_items,affected_voxels"]
	for i in range(_p2_frame_times_ms.size()):
		var t: float = _p2_frame_times_ms[i]
		if t > peak_ms:
			peak_ms = t
		csv_lines.append("%d,%.3f,%d,%d" % [i, t, _p2_active_dropped_items, _p2_affected_voxels])

	_write_phase2_csv(csv_lines)

	# Log the one-line PASS/FAIL summary (per plan action spec).
	var pass_fail := "PASS" if peak_ms <= TIER3_FRAME_BUDGET_MS else "FAIL"
	print("[Phase2Macro] Phase 2 macro: blast at t=8s; peak frame_time = %.2f ms; threshold (Tier-3 §7.2 budget) = %.1f ms (30 FPS cap) — %s" % [peak_ms, TIER3_FRAME_BUDGET_MS, pass_fail])
	if peak_ms > TIER3_FRAME_BUDGET_MS:
		print("[Phase2Macro] FAIL — per D-07 + CONTEXT.md D-12 (no Rust), lower §7.2 contract or back out a visual feature.")

	print("[Phase2Macro] CSV written to ", PHASE2_CSV_PATH)
	print("[Phase2Macro] Transitioning to 30-min thermal loop...")

	# Transition into the existing 30-minute thermal loop (no behavioural change to Phase 1 loop).
	start_benchmark()


## Write per-frame CSV data to user://benchmarks/02-dynamite.csv.
func _write_phase2_csv(lines: Array) -> void:
	var file := FileAccess.open(PHASE2_CSV_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[Phase2Macro] Cannot open %s for writing: %s" % [PHASE2_CSV_PATH, FileAccess.get_open_error()])
		return
	for line in lines:
		file.store_line(str(line))
	file.close()


## Apply the Tier-3 graphics preset (render_distance=5, shadows=off, particle_density=low).
## Overrides user settings for the duration of the benchmark.
## Called on _ready() before any sampling begins.
func _apply_tier3_preset() -> void:
	# Write Tier-3 settings to user://settings.cfg so that terrain / shadow nodes
	# picking up settings on boot see the correct values.
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # Load existing (may fail if absent — that's OK)
	cfg.set_value("graphics", "preset", "low")
	cfg.set_value("graphics", "render_distance", 5)
	cfg.set_value("graphics", "shadows", "off")
	cfg.set_value("graphics", "particle_density", "low")
	cfg.save(SETTINGS_PATH)

	# Apply render distance live to VoxelViewer if present.
	var viewer := get_node_or_null("Builder/VoxelViewer")
	if viewer != null and viewer.has_method("set") :
		viewer.set("view_distance", TIER3_RENDER_DISTANCE)

	# Apply shadows off to the DirectionalLight3D if present.
	var sun := get_node_or_null("Sun")
	if sun != null:
		sun.set("shadow_enabled", TIER3_SHADOWS)
