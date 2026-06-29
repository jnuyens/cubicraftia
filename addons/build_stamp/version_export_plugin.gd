# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# version_export_plugin.gd — EditorExportPlugin that refreshes res://version.txt with the
# current git build id at the START of every export (editor GUI or `--export-release` CLI).
# The export presets force-include version.txt, so the freshly-written file is packed into
# the build and BuildInfo.version_string() reads the correct "<sha>[+] <date>" at runtime.
# This is what makes the in-game build label automatic — no manual stamp-version.sh needed.
@tool
extends EditorExportPlugin


func _get_name() -> String:
	return "BuildStamp"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	stamp_to_disk()


## Write "<short-sha>[+] <YYYY-MM-DD>" to res://version.txt. Shared with the EditorPlugin's
## _build() hook (play-in-editor). Mirrors scripts/stamp-version.sh.
static func stamp_to_disk() -> void:
	var f := FileAccess.open("res://version.txt", FileAccess.WRITE)
	if f != null:
		f.store_line(compute_version())
		f.close()


static func compute_version() -> String:
	var out: Array = []
	OS.execute("git", ["rev-parse", "--short", "HEAD"], out)
	var sha: String = str(out[0]).strip_edges() if out.size() > 0 else ""
	if sha == "":
		sha = "unknown"
	# "+" only for TRACKED CODE changes. Ignore untracked build artifacts (downloaded addon
	# binaries, version.txt) AND the .planning/ GSD docs, which are intentionally left
	# uncommitted (commit_docs=false) and don't represent a different build.
	var dirty_out: Array = []
	OS.execute("git", ["status", "--porcelain", "--untracked-files=no"], dirty_out)
	var is_dirty: bool = false
	if dirty_out.size() > 0:
		for line in str(dirty_out[0]).split("\n", false):
			var path: String = line.strip_edges().substr(2).strip_edges()  # drop the 2-char status code
			if path == "" or path.begins_with(".planning/"):
				continue
			is_dirty = true
			break
	var suffix: String = "+" if is_dirty else ""
	var date: String = Time.get_date_string_from_system()
	return "%s%s %s" % [sha, suffix, date]
