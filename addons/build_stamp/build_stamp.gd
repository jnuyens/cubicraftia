# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build_stamp.gd — EditorPlugin that wires the version-stamp export plugin and also stamps
# res://version.txt before play-in-editor (F5), so the in-game "build <sha> <date>" label is
# always current automatically — no one has to run scripts/stamp-version.sh.
@tool
extends EditorPlugin

const VersionExportPlugin := preload("res://addons/build_stamp/version_export_plugin.gd")

var _export_plugin: EditorExportPlugin = null


func _enter_tree() -> void:
	_export_plugin = VersionExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null


## Godot calls this before a play-in-editor run; refresh the build id then too.
func _build() -> bool:
	VersionExportPlugin.stamp_to_disk()
	return true
