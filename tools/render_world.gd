# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# render_world.gd — boot the in-world scene (main_scene) with a seeded world and
# screenshot the spawn view to a PNG, so the in-world builder + spawn surroundings
# can be verified/iterated without a human at the keyboard.
#
# Runs as a MAIN SCENE (autoloads live), NOT via `-s`:
#   godot --path . res://tools/render_world.tscn -- <out_png> [seconds] [seed] [WxH]
#
# It opens a throwaway WorldSave, instances main_scene as a child (so the chase
# camera renders to the root viewport), waits `seconds` for terrain to stream +
# the builder to spawn, then captures. Run WITH a display (not --headless).

extends Node


func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var out: String = ua[0] if ua.size() >= 1 else "/tmp/world.png"
	var secs: float = float(ua[1]) if ua.size() >= 2 else 10.0
	var seed_i: int = int(ua[2]) if ua.size() >= 3 else 1234
	var size := Vector2i(1280, 720)
	if ua.size() >= 4:
		var p := ua[3].split("x", false)
		if p.size() >= 2 and p[0].is_valid_int() and p[1].is_valid_int():
			size = Vector2i(maxi(1, int(p[0])), maxi(1, int(p[1])))
	get_window().size = size

	# Open a throwaway sandbox world so main_scene streams seeded terrain.
	if WorldSave.is_open():
		WorldSave.close_world()
	if not WorldSave.open_world("render_tmp", seed_i, "sandbox"):
		push_error("[render_world] could not open world")
		get_tree().quit(1)
		return

	var packed: PackedScene = load("res://src/world/main_scene.tscn") as PackedScene
	if packed == null:
		push_error("[render_world] main_scene load failed")
		get_tree().quit(1)
		return
	get_tree().root.add_child.call_deferred(packed.instantiate())

	await get_tree().create_timer(secs).timeout

	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("[render_world] empty viewport (needs a display, not --headless)")
		get_tree().quit(1)
		return
	var err := img.save_png(out)
	if err != OK:
		push_error("[render_world] save_png failed (%d)" % err)
		get_tree().quit(1)
		return
	print("[render_world] saved -> %s" % out)
	get_tree().quit(0)
