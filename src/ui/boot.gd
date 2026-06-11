# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# boot.gd — Splash-screen + threaded world load.
#
# Set as run/main_scene in project.godot. Workflow:
#   1. Engine boot_splash flashes (Godot built-in, milliseconds).
#   2. This scene shows the Cubicraftia splash image + a progress bar.
#   3. ResourceLoader.load_threaded_request(main_scene.tscn) starts the heavy
#      file load on a worker thread. Bar fills 0 → 100% from real loader
#      progress.
#   4. Once the scene resource is fully loaded AND a minimum splash time has
#      elapsed (so the splash doesn't flash by on a cache-warm load),
#      change_scene_to_packed swaps to main_scene. Standard Godot transition,
#      no dual-scene-tree shenanigans.
#
# If the loader fails (file missing, parse error, etc.) the label surfaces the
# error and the scene stays up so the user can read the console.

extends CanvasLayer

const _MAIN_SCENE_PATH: String = "res://src/world/main_scene.tscn"

## Minimum time the splash stays visible even on a cache-warm load.
const _MIN_SPLASH_S: float = 1.5

@onready var _bar: ProgressBar = $Layout/BottomPanel/BarCenter/Bar
@onready var _label: Label = $Layout/BottomPanel/Label

var _boot_started_msec: int = 0
var _swapped: bool = false


func _ready() -> void:
	_boot_started_msec = Time.get_ticks_msec()
	_bar.value = 0.0
	_label.text = "Loading world…"
	var err: int = ResourceLoader.load_threaded_request(_MAIN_SCENE_PATH)
	if err != OK:
		_label.text = "Load request failed (err=%d) — see console" % err
		push_error("boot.gd: load_threaded_request failed for %s (err=%d)" % [_MAIN_SCENE_PATH, err])


func _process(_delta: float) -> void:
	if _swapped:
		return
	var progress: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(_MAIN_SCENE_PATH, progress)
	if progress.size() > 0:
		_bar.value = float(progress[0]) * 100.0
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			var elapsed_s: float = float(Time.get_ticks_msec() - _boot_started_msec) / 1000.0
			if elapsed_s >= _MIN_SPLASH_S:
				_swap_to_main_scene()
		ResourceLoader.THREAD_LOAD_FAILED:
			_label.text = "World load failed — see console"
			push_error("boot.gd: ResourceLoader.THREAD_LOAD_FAILED for %s" % _MAIN_SCENE_PATH)
			_swapped = true
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_label.text = "World scene missing — see console"
			push_error("boot.gd: ResourceLoader.THREAD_LOAD_INVALID_RESOURCE for %s" % _MAIN_SCENE_PATH)
			_swapped = true


func _swap_to_main_scene() -> void:
	_swapped = true
	_bar.value = 100.0
	_label.text = "Welcome to Cubicraftia"
	var packed: Resource = ResourceLoader.load_threaded_get(_MAIN_SCENE_PATH)
	if packed == null or not (packed is PackedScene):
		_label.text = "World scene corrupt — see console"
		push_error("boot.gd: load_threaded_get returned non-PackedScene for %s" % _MAIN_SCENE_PATH)
		return
	# One-frame delay so the user sees the 100% / "Welcome" state briefly.
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		get_tree().change_scene_to_packed(packed as PackedScene)
	)
