# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_asset_stub_audit.gd — ASSET-07: Wave 0 stub-detection harness
#
# Scans every shipped .tscn and .gd file under res://src for res://...png
# references and asserts that each referenced PNG is > MIN_BYTES in size.
# A 1×1 transparent placeholder stub is 68 B — well below the 200 B threshold.
#
# Wave 0 RED state: This test is EXPECTED to fail on the first run because the
# following known stubs are still in place and referenced by shipped code:
#   - assets/textures/ui/world_thumb_placeholder.png   (68 B stub)
#   - assets/textures/ui/avatar_presets/preset_1..8.png (68 B stubs each)
#   - src/ui/hp_bar.gd references heart_full.png / heart_empty.png which do
#     not exist at those paths (FileAccess.get_size returns -1)
#
# Each subsequent plan in Phase 7 turns more assertions GREEN by:
#   - replacing stub PNGs with real art (Plans 02-04)
#   - fixing code path constants to match committed asset filenames (Plan 02)
#
# When all stubs and path gaps are resolved, this test goes GREEN (Plan 04+).
#
# Exclusion list: animation POC demo scenes and test scenes are excluded so
# that their internal references to test-only or provisional assets do not
# produce false positives.
#
# Related: tests/conftest_helpers.gd (find_tscn_files, find_gd_files, read_text_file)
# Related: .planning/phases/07-asset-integration/07-RESEARCH.md Pattern 5 (ASSET-07)
extends GutTest

const Helpers = preload("res://tests/conftest_helpers.gd")

## Regex pattern that matches any res://...png path reference in .tscn or .gd
## source text. Stops at whitespace, single-quote, double-quote, or closing
## parenthesis to avoid over-matching.
const _RES_PNG_REGEX: String = 'res://[^\\s\'"\\)]+\\.png'

## Minimum number of bytes for a PNG to not be a 1×1 transparent stub.
## Known stubs are exactly 68 B. Real art is always several KB or larger.
## The 200 B threshold gives ample margin while excluding any 1×1 generated stub.
const MIN_BYTES: int = 200

## Directories and path fragments to skip during the audit.
## Entries that begin with "res://" are checked via String.begins_with().
## Entries without "res://" are checked via String.contains() to catch
## mid-path occurrences (e.g. "demo_scene" anywhere in the path).
const _EXCLUDE_DIRS: Array[String] = [
	"res://tests/",
	"res://addons/",
	"minifigure_animator_demo",
	"shader_wobble_animator",
	"quadruped_poc",
	"animation_demo",
	"demo_scene",
]


## Primary audit test.
##
## Collects all shipped .tscn and .gd files under res://src, extracts every
## res://...png reference from their text, and checks that each referenced
## PNG exists and is larger than MIN_BYTES. Any file smaller than MIN_BYTES
## (or absent, size = -1) is appended to the failures list.
##
## This test is RED in Wave 0 and turns GREEN after Plans 02-04 resolve all
## known stub references.
func test_no_stub_textures_in_shipped_scenes() -> void:
	var tscn_files := Helpers.find_tscn_files("res://src")
	var gd_files   := Helpers.find_gd_files("res://src")

	var all_files: Array[String] = []
	all_files.append_array(tscn_files)
	all_files.append_array(gd_files)

	if all_files.is_empty():
		gut.p("No .tscn or .gd files found under res://src — passes trivially")
		pass_test("No source files found")
		return

	var regex := RegEx.new()
	var compile_err := regex.compile(_RES_PNG_REGEX)
	if compile_err != OK:
		fail_test("Failed to compile _RES_PNG_REGEX: %s" % _RES_PNG_REGEX)
		return

	var failures: Array[String] = []

	for file_path: String in all_files:
		if _is_excluded(file_path):
			continue

		var content := Helpers.read_text_file(file_path)
		if content.is_empty():
			continue

		# Scan line-by-line so we can skip GDScript comment lines: example/doc
		# paths inside '#' comments are not live scene references (e.g. an
		# icon_path usage example in a docstring). .tscn files use ';' for
		# comments, so '#'-prefix skipping never drops a real .tscn resource ref.
		for line: String in content.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue

			var matches: Array[RegExMatch] = regex.search_all(line)
			for m: RegExMatch in matches:
				var tex_path: String = m.get_string(0)

				# Skip self-referential entries (e.g. the regex constant itself in this file)
				if tex_path == _RES_PNG_REGEX:
					continue

				var size: int = FileAccess.get_size(tex_path)
				if size < MIN_BYTES:
					failures.append(
						"%s: references %s (%d B)" % [file_path, tex_path, size]
					)

	assert_eq(
		failures.size(),
		0,
		"Stub textures found (size < %d B, or missing size = -1):\n%s" % [
			MIN_BYTES,
			"\n".join(failures),
		]
	)


## Returns true if `path` should be excluded from the audit.
##
## Paths that begin with an "res://" entry are matched via begins_with().
## Paths that contain a non-res:// fragment (e.g. a demo scene name that
## appears mid-path) are matched via contains().
func _is_excluded(path: String) -> bool:
	for excl: String in _EXCLUDE_DIRS:
		if excl.begins_with("res://"):
			if path.begins_with(excl):
				return true
		else:
			if path.contains(excl):
				return true
	return false
