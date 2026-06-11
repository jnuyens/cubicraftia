# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# thermal_probe.gd — FPS + thermal CSV sampler
#
# Registered as autoload "ThermalProbe" in project.godot.
#
# Records FPS and thermal readings to a CSV file for the Motorola 30-min
# benchmark (D-02 / §7.2 contract). Sampling cadence is 10 seconds per
# RESEARCH.md Pitfall 3 (Android's getThermalHeadroom API requires ≤ 1 call/10s).
#
# CSV columns: timestamp,fps,thermal_headroom,thermal_status,thermal_probe_path
#
# Phase 1: the Android JNI hook is injected via set_thermal_provider().
# Plan 07 calls this setter with the Kotlin ThermalPlugin instance.
# Until then, the stub provider returns NaN / -1 (safe no-op values).
#
# Usage:
#   ThermalProbe.start("user://benchmark.csv")
#   # ... run game for 30 min ...
#   ThermalProbe.stop()
extends Node

## Sampling interval in seconds (Android thermal API: ≤ 1 call per 10s).
const SAMPLE_INTERVAL_S: float = 10.0

## CSV header row (must match scripts/analyse-benchmark.sh column expectations).
const CSV_HEADER: String = "timestamp,fps,thermal_headroom,thermal_status,thermal_probe_path"

## Current thermal provider. Set via set_thermal_provider() from Plan 07.
## The provider object must expose:
##   func get_thermal_headroom() -> float   (returns NaN if unavailable)
##   func get_thermal_status() -> int       (returns -1 if unavailable)
var _thermal_provider: Object = null

## Internal state
var _csv_file: FileAccess = null
var _timer: Timer = null
var _start_timestamp: float = 0.0
var _frame_accumulator: float = 0.0
var _frame_count: int = 0
var _probe_path_label: String = "unavailable"
var _running: bool = false


## Begin recording to the given CSV path.
## Creates the file and writes the header row.
## @param csv_path  A Godot path, e.g. "user://benchmark.csv"
func start(csv_path: String) -> void:
	if _running:
		push_warning("ThermalProbe.start() called while already running. Call stop() first.")
		return

	_csv_file = FileAccess.open(csv_path, FileAccess.WRITE)
	if _csv_file == null:
		push_error("ThermalProbe: could not open CSV file: %s (error %d)" % [
			csv_path, FileAccess.get_open_error()])
		return

	_csv_file.store_line(CSV_HEADER)
	_start_timestamp = Time.get_unix_time_from_system()
	_frame_accumulator = 0.0
	_frame_count = 0
	_running = true

	# Detect which thermal probe path is active
	_probe_path_label = _detect_probe_path()

	# Start the 10-second sampling timer
	_timer = Timer.new()
	_timer.wait_time = SAMPLE_INTERVAL_S
	_timer.autostart = true
	_timer.timeout.connect(_on_sample_timer_timeout)
	add_child(_timer)


## Stop recording and close the CSV file.
func stop() -> void:
	if not _running:
		return

	if _timer != null:
		_timer.stop()
		_timer.queue_free()
		_timer = null

	if _csv_file != null:
		_csv_file.close()
		_csv_file = null

	_running = false


## Inject the Android thermal provider (called by Plan 07 with the Kotlin plugin).
## Until Plan 07 runs, the provider is null and readings return NaN / -1.
## @param provider  An Object exposing get_thermal_headroom() and get_thermal_status()
func set_thermal_provider(provider: Object) -> void:
	_thermal_provider = provider
	_probe_path_label = _detect_probe_path()


## Per-frame FPS accumulation (main thread; cheap).
func _process(_delta: float) -> void:
	if not _running:
		return
	_frame_accumulator += Engine.get_frames_per_second()
	_frame_count += 1


## Called every 10 seconds by the Timer to write a CSV row.
func _on_sample_timer_timeout() -> void:
	if not _running or _csv_file == null:
		return

	var now := Time.get_unix_time_from_system()
	var elapsed := now - _start_timestamp

	# Compute average FPS over the interval
	var fps := 0.0
	if _frame_count > 0:
		fps = _frame_accumulator / float(_frame_count)
	_frame_accumulator = 0.0
	_frame_count = 0

	# Read thermal data from provider (stub returns NaN / -1)
	var headroom: float = NAN
	var status: int = -1
	if _thermal_provider != null:
		if _thermal_provider.has_method("get_thermal_headroom"):
			headroom = _thermal_provider.get_thermal_headroom()
		if _thermal_provider.has_method("get_thermal_status"):
			status = _thermal_provider.get_thermal_status()

	# Format CSV row: timestamp,fps,thermal_headroom,thermal_status,thermal_probe_path
	var headroom_str := "NaN" if is_nan(headroom) else "%.4f" % headroom
	var row := "%s,%.2f,%s,%d,%s" % [
		"%.3f" % elapsed,
		fps,
		headroom_str,
		status,
		_probe_path_label,
	]
	_csv_file.store_line(row)


## Plan 07: on Android builds, wire the AndroidThermal provider automatically.
## Called from _ready() so the provider is available as soon as the autoload tree is ready.
func _ready() -> void:
	if OS.has_feature("android"):
		# AndroidThermal autoload is registered in project.godot for Android builds.
		# It performs its own layered probe detection in its _ready().
		var at := get_node_or_null("/root/AndroidThermal")
		if at != null:
			set_thermal_provider(at)


## Determine which thermal probe path is active for the CSV metadata.
func _detect_probe_path() -> String:
	if _thermal_provider != null:
		# Prefer the explicit get_probe_path() method exposed by android_thermal.gd.
		if _thermal_provider.has_method("get_probe_path"):
			return _thermal_provider.get_probe_path()
		# Fallback: infer from available methods (for custom mock providers in tests).
		if _thermal_provider.has_method("get_thermal_headroom"):
			return "getThermalHeadroom"
		elif _thermal_provider.has_method("get_thermal_status"):
			return "currentThermalStatus"
	return "unavailable"
