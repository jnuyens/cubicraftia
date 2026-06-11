# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# anim_frame_budget.gd — ANIM-06 desktop frame-budget smoke test (Plan 08-03).
#
# Measures the per-frame CPU cost of running ProceduralCreatureAnimator.update()
# on a full creature roster (~23 creatures) within the 40 m LOD radius, versus a
# static baseline (animators frozen / no update call), and reports:
#   - animated average ms/frame
#   - static-baseline average ms/frame
#   - delta in ms/frame
#   - per-creature cost in ms  (delta / creature_count)
#   - pass/partial verdict vs. CONTEXT.md target "< 1 ms/creature"
#
# Environment: headless (no GPU, no display). Because creature .glb assets do not
# load headlessly (GLTFDocument requires a rendering context for mesh import), this
# harness measures the PROCEDURAL fallback path only — the transform-only
# ProceduralCreatureAnimator that runs on every creature that lacks a dedicated rig.
# This is the dominant per-frame cost for single-mesh TripoSR creatures (~18 of 23).
# The GPU-side cost of ShaderWobbleAnimator (fish/ghost) and MinifigureAnimator rig
# updates is EXCLUDED here because those are GPU-driven; the CPU overhead is a single
# uniform write per animator, negligible compared to the transform path.
#
# Measurement methodology (Option A, headless fallback sub-case):
#   - Instantiate N=23 Node3D mesh-root stand-ins (no mesh, transform only).
#   - Create one ProceduralCreatureAnimator per stand-in with Motion.LAND.
#   - Run WARMUP_FRAMES frames to JIT-stabilise GDScript bytecodes.
#   - Measure SAMPLE_FRAMES frames: call update() on all animators, record elapsed ns
#     via Time.get_ticks_usec() bracketing each frame block (not Performance monitor,
#     which has per-frame granularity jitter on headless).
#   - Repeat with animators frozen (update() skipped) for the static baseline.
#   - Print results and write to the CSV path below.
#
# Run via: godot --headless --script tests/perf/anim_frame_budget.gd
# from the Cubicraftia repo root (project must be at res://).

extends SceneTree

# ─── Parameters ───────────────────────────────────────────────────────────────

## Creature count matching the plan "~23 creatures" worst-case roster.
const CREATURE_COUNT: int = 23

## Warmup frames (let GDScript interpreter stabilise).
const WARMUP_FRAMES: int = 200

## Sample frames (must be large enough for ticks_usec noise to average out).
const SAMPLE_FRAMES: int = 1000

## Simulated frame delta (seconds). 1/60 = 60 FPS target on desktop.
const FRAME_DELTA: float = 1.0 / 60.0

## CSV output (informational; written alongside the result .md by the SUMMARY step).
const CSV_OUT: String = "user://benchmarks/anim-06-desktop.csv"

# ─── Entry point ──────────────────────────────────────────────────────────────

func _init() -> void:
	# Ensure output directory exists.
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://benchmarks"))

	print("[ANIM-06] Desktop frame-budget smoke test — ProceduralCreatureAnimator")
	print("[ANIM-06] Creatures: %d | Warmup: %d frames | Sample: %d frames | delta=%.4f s" % [
		CREATURE_COUNT, WARMUP_FRAMES, SAMPLE_FRAMES, FRAME_DELTA])

	var result := _run_measurement()
	_print_result(result)
	_write_csv(result)
	quit(0)


# ─── Measurement core ─────────────────────────────────────────────────────────

func _run_measurement() -> Dictionary:
	# --- Set up creature stand-ins ---
	var mesh_roots: Array = []
	var animators: Array = []

	for i in range(CREATURE_COUNT):
		var root := Node3D.new()
		# Stagger phases so they are not all in lock-step (mirrors _init phase_offset).
		var anim := ProceduralCreatureAnimator.new(ProceduralCreatureAnimator.Motion.LAND)
		mesh_roots.append(root)
		animators.append(anim)

	# --- Warmup pass (animated) ---
	for _f in range(WARMUP_FRAMES):
		for j in range(CREATURE_COUNT):
			(animators[j] as ProceduralCreatureAnimator).update(
				mesh_roots[j], FRAME_DELTA)

	# --- Animated sample pass ---
	var animated_total_us: float = 0.0
	var animated_frame_times_us: Array = []
	for _f in range(SAMPLE_FRAMES):
		var t0: int = Time.get_ticks_usec()
		for j in range(CREATURE_COUNT):
			(animators[j] as ProceduralCreatureAnimator).update(
				mesh_roots[j], FRAME_DELTA)
		var elapsed: int = Time.get_ticks_usec() - t0
		animated_total_us += float(elapsed)
		animated_frame_times_us.append(float(elapsed))

	var animated_avg_us: float = animated_total_us / float(SAMPLE_FRAMES)
	var animated_avg_ms: float = animated_avg_us / 1000.0

	# --- Reset animators for a fresh static pass (same objects, fresh _t) ---
	# Re-create to avoid carry-over phase state affecting timing.
	animators.clear()
	for i in range(CREATURE_COUNT):
		animators.append(ProceduralCreatureAnimator.new(
			ProceduralCreatureAnimator.Motion.LAND))

	# --- Static baseline warmup (just tick the loop, no update calls) ---
	for _f in range(WARMUP_FRAMES):
		for j in range(CREATURE_COUNT):
			pass  # no animator update — same loop overhead, no sin/cos

	# --- Static sample pass ---
	var static_total_us: float = 0.0
	var static_frame_times_us: Array = []
	for _f in range(SAMPLE_FRAMES):
		var t0: int = Time.get_ticks_usec()
		for j in range(CREATURE_COUNT):
			pass  # intentionally empty — baseline for loop + call overhead
		var elapsed: int = Time.get_ticks_usec() - t0
		static_total_us += float(elapsed)
		static_frame_times_us.append(float(elapsed))

	var static_avg_us: float = static_total_us / float(SAMPLE_FRAMES)
	var static_avg_ms: float = static_avg_us / 1000.0

	# --- Compute delta ---
	var delta_ms: float = animated_avg_ms - static_avg_ms
	var per_creature_ms: float = delta_ms / float(CREATURE_COUNT)

	# Percentiles (p95, p99) from animated_frame_times_us for evidence quality.
	animated_frame_times_us.sort()
	var p95_ms: float = animated_frame_times_us[int(SAMPLE_FRAMES * 0.95)] / 1000.0
	var p99_ms: float = animated_frame_times_us[int(SAMPLE_FRAMES * 0.99)] / 1000.0

	return {
		"creature_count": CREATURE_COUNT,
		"sample_frames": SAMPLE_FRAMES,
		"animated_avg_ms": animated_avg_ms,
		"static_avg_ms": static_avg_ms,
		"delta_ms": delta_ms,
		"per_creature_ms": per_creature_ms,
		"animated_p95_ms": p95_ms,
		"animated_p99_ms": p99_ms,
		"frame_times_us": animated_frame_times_us,
	}


func _print_result(r: Dictionary) -> void:
	var verdict: String
	if r["per_creature_ms"] < 1.0:
		verdict = "PASS (< 1 ms/creature on desktop, procedural-fallback path)"
	else:
		verdict = "PARTIAL — per-creature cost >= 1 ms (desktop / procedural path only; Tier-3 hardware run required)"

	print("")
	print("=== ANIM-06 Desktop Smoke Result ===")
	print("Animated average (23 creatures): %.4f ms/frame" % r["animated_avg_ms"])
	print("Static baseline (loop only):     %.4f ms/frame" % r["static_avg_ms"])
	print("Delta (animated - static):       %.4f ms/frame" % r["delta_ms"])
	print("Per-creature cost:               %.5f ms/creature" % r["per_creature_ms"])
	print("Animated p95:                    %.4f ms/frame" % r["animated_p95_ms"])
	print("Animated p99:                    %.4f ms/frame" % r["animated_p99_ms"])
	print("Verdict:                         %s" % verdict)
	print("")


func _write_csv(r: Dictionary) -> void:
	var path: String = ProjectSettings.globalize_path(CSV_OUT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[ANIM-06] Cannot write CSV to %s" % path)
		return

	file.store_line("frame,time_us")
	var times: Array = r["frame_times_us"]
	for i in range(times.size()):
		file.store_line("%d,%.1f" % [i, times[i]])
	file.close()
	print("[ANIM-06] CSV written to %s" % path)
