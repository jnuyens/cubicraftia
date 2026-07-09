# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build_info.gd — exposes the per-build identifier so the player always knows
# exactly which build they are testing (prevents stale-build confusion).
#
# Registered as autoload "BuildInfo" in project.godot.
#
# The identifier is written to res://version.txt by scripts/stamp-version.sh
# (short commit hash + optional "+" dirty suffix + short date, one line). That
# file is a build artifact (git-ignored) and is force-included in every export
# preset's include_filter so it ships with packaged builds. Re-run
# `bash scripts/stamp-version.sh` before every playtest or export.
#
# Usage:
#   BuildInfo.version_string()       -> "a1b2c3d 2026-06-20" (or fallback)
#   BuildInfo.IS_MAJOR_RELEASE       -> when true, UI build labels stay hidden
extends Node

## Flip to true for a major/public release so the in-game build label is hidden
## (the console line still prints). Subtle build labels are for test builds only.
const IS_MAJOR_RELEASE: bool = false

## Coarse, hand-bumped P2P build-compatibility integer (D-07, VER-01).
## This is DELIBERATELY separate from two other version-shaped fields that live
## at different layers, do not conflate them:
##   - version_string()'s per-commit git-sha stamp (above) is too fine-grained for a
##     compatibility gate: it changes on every commit, but most commits do not break
##     the P2P RPC/serialization contract.
##   - The Go signaling server's own wire-protocol field ("v":1 in
##     signaling-server/internal/hub/hub.go) governs client <-> signaling-server
##     framing only; it says nothing about whether two game builds can safely
##     interoperate over the resulting P2P connection.
## Bump PROTOCOL_VERSION only when the P2P RPC/serialization contract in
## network_manager.gd actually changes, never on every commit.
const PROTOCOL_VERSION: int = 1

## Path to the stamped build identifier (res:// so it resolves in exports too).
const _VERSION_PATH: String = "res://version.txt"

## Shown when version.txt is missing (e.g. someone forgot to stamp the build).
const _FALLBACK: String = "dev (unstamped)"


func _ready() -> void:
	print("Cubicraftia build: %s" % version_string())


## Return the one-line build identifier, or a clear fallback if unstamped.
func version_string() -> String:
	if not FileAccess.file_exists(_VERSION_PATH):
		return _FALLBACK
	var f := FileAccess.open(_VERSION_PATH, FileAccess.READ)
	if f == null:
		return _FALLBACK
	var line := f.get_line().strip_edges()
	f.close()
	if line.is_empty():
		return _FALLBACK
	return line
