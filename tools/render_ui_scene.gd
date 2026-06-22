# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# render_ui_scene.gd — Render a UI .tscn under a forced locale to a PNG.
#
# Instances any Control/UI scene, forces the TranslationServer locale BEFORE the
# scene is loaded (so auto-translated Control.text resolves in the target language),
# sizes the root window so overflow/clipping reproduces, lets layout + translation
# settle, then screenshots the root viewport to a PNG. Built so the AI can self-verify
# localisation/layout UATs (e.g. the Phase 9 avatar-creator screen: English labels,
# dead preview, content running off the bottom).
#
# Godot --headless has NO rendering, so run this WITH a rendering display:
#   godot -s tools/render_ui_scene.gd -- <scene_res_path> <out_png> [locale] [WxH]
#
#   <scene_res_path>  required, e.g. res://src/ui/avatar_creator.tscn
#   <out_png>         required, absolute output path
#   [locale]          optional, default "nl"
#   [WxH]             optional, default "1280x720" (e.g. 1920x1080)
#
# Running --headless yields a blank buffer, so always run with a real display.

extends SceneTree

var _scene_res_path := ""
var _out := ""
var _locale := "nl"
var _size := Vector2i(1280, 720)


func _init() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() >= 1:
		_scene_res_path = ua[0]
	if ua.size() >= 2:
		_out = ua[1]
	if ua.size() >= 3:
		_locale = ua[2]
	if ua.size() >= 4:
		_size = _parse_size(ua[3])

	if _scene_res_path.is_empty() or _out.is_empty():
		push_error("[render_ui_scene] usage: -- <scene_res_path> <out_png> [locale] [WxH]")
		quit(1)
		return

	# Force the locale BEFORE loading/instancing so auto-translated Control.text
	# resolves in the target language at layout time.
	TranslationServer.set_locale(_locale)

	# Size the root window so Control scenes lay out against the real resolution —
	# overflow/clipping (e.g. content running off the bottom) reproduces faithfully.
	get_root().set_size(_size)

	var scene: PackedScene = load(_scene_res_path) as PackedScene
	if scene == null:
		push_error("[render_ui_scene] failed to load: %s" % _scene_res_path)
		quit(1)
		return
	var inst: Node = scene.instantiate()
	get_root().add_child(inst)

	# Give layout + translation a moment to settle before screenshotting.
	create_timer(0.4).timeout.connect(_save)


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


func _save() -> void:
	var img: Image = get_root().get_texture().get_image()
	var err := img.save_png(_out)
	if err != OK:
		push_error("[render_ui_scene] save_png failed (%d) -> %s" % [err, _out])
		quit(1)
		return
	print("[render_ui_scene] saved -> %s" % _out)
	quit(0)
