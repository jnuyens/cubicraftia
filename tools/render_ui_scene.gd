# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# render_ui_scene.gd — Render a UI .tscn under a forced locale to a PNG.
#
# Instances any Control/UI scene, forces the TranslationServer locale, sizes the
# root window so overflow/clipping reproduces, lets layout + translation settle,
# then screenshots the root viewport to a PNG. Built so the AI can self-verify
# localisation/layout UATs (e.g. the Phase 9 avatar-creator screen: English labels,
# dead preview, content running off the bottom).
#
# IMPORTANT — runs as a MAIN SCENE, not via `-s`:
#   godot --path . res://tools/render_ui_scene.tscn -- <scene_res_path> <out_png> [locale] [WxH]
#
#   <scene_res_path>  required, e.g. res://src/ui/avatar_creator.tscn
#   <out_png>         required, absolute output path
#   [locale]          optional, default "nl"
#   [WxH]             optional, default "1280x720" (e.g. 1920x1080)
#
# Why a main scene and NOT `godot -s render_ui_scene.gd`: the `-s` form replaces the
# main loop, so the project's autoloads (the custom `Translations` registrar, plus
# singletons UI scripts reference like `OnboardingTelemetry`) never initialise — the
# scene then shows raw `ui.*` locale keys and runtime-built sections fail to compile.
# Booting this as the main scene keeps every autoload and the registered translations
# live, so the captured PNG matches what a player actually sees.
#
# Godot --headless has NO rendering and yields a blank buffer — always run WITH a
# real display.

extends Node


func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var scene_res_path := ua[0] if ua.size() >= 1 else ""
	var out := ua[1] if ua.size() >= 2 else ""
	var locale := ua[2] if ua.size() >= 3 else "nl"
	var size := _parse_size(ua[3]) if ua.size() >= 4 else Vector2i(1280, 720)

	if scene_res_path.is_empty() or out.is_empty():
		push_error("[render_ui_scene] usage: -- <scene_res_path> <out_png> [locale] [WxH]")
		get_tree().quit(1)
		return

	# Force the locale; autoloads + registered translations are already live because
	# this runs as the main scene, so auto-translated Control.text resolves to nl.
	TranslationServer.set_locale(locale)

	# Size the root window so Control scenes lay out against the real resolution —
	# overflow/clipping (e.g. content running off the bottom) reproduces faithfully.
	var win := get_window()
	win.size = size

	var scene: PackedScene = load(scene_res_path) as PackedScene
	if scene == null:
		push_error("[render_ui_scene] failed to load: %s" % scene_res_path)
		get_tree().quit(1)
		return
	var inst: Node = scene.instantiate()
	# Deferred: the root is still busy setting up children during the runner's _ready,
	# so a direct add_child() is rejected.
	get_tree().root.add_child.call_deferred(inst)

	# Give layout + translation a couple of frames, then a short settle for any
	# deferred SubViewport/preview rendering, before screenshotting.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout

	var img: Image = get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	if err != OK:
		push_error("[render_ui_scene] save_png failed (%d) -> %s" % [err, out])
		get_tree().quit(1)
		return
	print("[render_ui_scene] saved -> %s" % out)
	get_tree().quit(0)


## Parse a "WxH" command-line size token into a Vector2i (defaults each malformed
## component to the 1280x720 fallback so a bad arg can never collapse the window).
func _parse_size(token: String) -> Vector2i:
	var parts := token.split("x", false)
	var v := Vector2i(1280, 720)
	if parts.size() >= 1 and parts[0].is_valid_int():
		v.x = int(parts[0])
	if parts.size() >= 2 and parts[1].is_valid_int():
		v.y = int(parts[1])
	# Guard against zero/negative dimensions that would collapse the viewport.
	v.x = maxi(v.x, 1)
	v.y = maxi(v.y, 1)
	return v
