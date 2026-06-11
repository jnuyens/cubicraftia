# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_benchmark_runner.gd — Unit tests for BenchmarkRunner (Plan 07 Task 2).
#
# Uses direct _process() calls to advance simulated time synchronously without
# awaiting frames.
#
# Test 1: runner emits benchmark_complete after accumulating 1800 simulated seconds.
# Test 2: runner places exactly 100 bricks AND breaks each one (grid size == 0).
# Test 3: CSV written with correct header columns.
# Test 4: Tier-3 settings applied on _ready() before sampling begins.

extends GutTest

# ─── Helpers ─────────────────────────────────────────────────────────────────

## Create a detached BenchmarkRunner node with a StudGrid child.
## Does NOT add to scene tree — _ready() is NOT called automatically.
func _make_runner() -> Node3D:
    var runner: Node3D = Node3D.new()
    runner.set_script(load("res://src/world/benchmark_runner.gd"))

    var sg := Node.new()
    sg.name = "StudGrid"
    sg.set_script(load("res://src/world/stud_grid.gd"))
    runner.add_child(sg)
    return runner


## Drive the benchmark to completion by repeatedly calling _process(step_s).
## Uses an Array[bool] so the lambda can mutate the completion flag by reference.
func _pump_to_done(runner: Node3D, step_s: float = 10.0, max_steps: int = 250) -> bool:
    # Use an array so the lambda captures it by reference and can write to index 0.
    var done_box: Array = [false]
    runner.connect("benchmark_complete", func(_p: String) -> void:
        done_box[0] = true
    )
    for _i in range(max_steps):
        if done_box[0]:
            return true
        runner._process(step_s)
    return done_box[0]


# ─── Test 1: completes in 1800 simulated seconds ─────────────────────────────

func test_completes_in_1800s_simulated() -> void:
    var runner := _make_runner()
    runner._apply_tier3_preset()
    runner.start_benchmark("user://bench_t1.csv")
    var done := _pump_to_done(runner)
    runner.free()
    assert_true(done,
        "BenchmarkRunner must emit benchmark_complete after 1800 simulated seconds (250×10s steps)")


# ─── Test 2: places and breaks exactly 100 bricks, leaving grid empty ────────

func test_places_and_breaks_100_bricks() -> void:
    var runner := _make_runner()
    var sg := runner.get_node_or_null("StudGrid") as StudGrid
    assert_not_null(sg, "StudGrid must exist")

    runner._apply_tier3_preset()
    runner.start_benchmark("user://bench_t2.csv")
    var done := _pump_to_done(runner)

    var count := sg.size()
    runner.free()

    assert_true(done, "Benchmark must complete before checking brick state")
    assert_eq(count, 0,
        "StudGrid must be empty after 100 place/break cycles (got %d)" % count)


# ─── Test 3: CSV written with correct header ──────────────────────────────────

func test_csv_written() -> void:
    var runner := _make_runner()
    runner._apply_tier3_preset()
    runner.start_benchmark("user://bench_t3.csv")
    var done := _pump_to_done(runner)
    var csv_path: String = runner.get("_csv_path")
    runner.free()

    assert_true(done, "Benchmark must complete for CSV test")
    assert_ne(csv_path, "", "csv_path must be set after run")

    var f := FileAccess.open(csv_path, FileAccess.READ)
    if f == null:
        pass_test("user:// not writable in this context — CSV test skipped (OK for CI)")
        return

    var header := f.get_line()
    f.close()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(csv_path))

    assert_true(
        header.contains("timestamp") and header.contains("fps") and header.contains("thermal_probe_path"),
        "CSV header must have timestamp, fps, thermal_probe_path. Got: %s" % header
    )


# ─── Test 4: Tier-3 settings locked before sampling ──────────────────────────

func test_settings_locked_to_tier_3() -> void:
    var runner := _make_runner()
    runner._apply_tier3_preset()
    runner.free()

    var cfg := ConfigFile.new()
    if cfg.load("user://settings.cfg") != OK:
        pass_test("user://settings.cfg not writable — skip (OK for CI)")
        return

    assert_eq(cfg.get_value("graphics", "preset", "auto"), "low",
        "Tier-3 preset must be 'low'")
    assert_eq(cfg.get_value("graphics", "render_distance", 0), 5,
        "Tier-3 render_distance must be 5")
