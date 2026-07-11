# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# auto_update.gd (AutoUpdate autoload): DIST-05, notify-and-link update check.
#
# On launch, fetches a small JSON manifest and, if the published version differs
# from this build's version.txt, shows a NON-BLOCKING "update available" notice with
# a Download button (opens the download page in the browser). It never downloads or
# replaces anything itself: the player stays in control. Any error (offline, bad
# JSON, timeout) is a silent no-op so it can never block or disrupt play.
#
# Manifest shape (https://cubicraftia.com/updates/latest.json):
#   {"version": "<git-sha date>", "url": "https://cubicraftia.com/downloads/...", "notes": "..."}
#
# Version source: BuildInfo.version_string() (res://version.txt, stamped on export).
# The check is skipped when the local build is unstamped (fallback) so dev/editor runs
# are never nagged.

extends Node

## Default manifest URL. Overridable via ProjectSettings "network/update_manifest_url".
const _DEFAULT_MANIFEST_URL: String = "https://cubicraftia.com/updates/latest.json"

## Emitted when a newer published version is detected. Payload: version, download url, notes.
signal update_available(version: String, url: String, notes: String)

var _http: HTTPRequest = null
var _notice: CanvasLayer = null

func _ready() -> void:
	var local := _local_version()
	# Skip entirely when this build is unstamped (editor / dev) so we never nag.
	if local.is_empty() or local == "unstamped-dev-build":
		return
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_manifest_fetched)
	var url: String = ProjectSettings.get_setting("network/update_manifest_url", _DEFAULT_MANIFEST_URL)
	# Best-effort: an error here is a silent no-op.
	_http.request(url)

## The running build's version identifier (res://version.txt via BuildInfo).
func _local_version() -> String:
	if not is_instance_valid(BuildInfo):
		return ""
	var v: String = BuildInfo.version_string()
	# BuildInfo returns a human "unstamped" fallback when version.txt is missing.
	if v.to_lower().find("unstamped") != -1:
		return "unstamped-dev-build"
	return v.strip_edges()

## Pure decision function (unit-tested): an update is available only when both
## versions are present and they differ. Forward-only publishing means "different"
## == "the server has a newer build".
static func is_update_available(local_version: String, manifest_version: String) -> bool:
	if local_version.is_empty() or manifest_version.is_empty():
		return false
	if local_version == "unstamped-dev-build":
		return false
	return local_version.strip_edges() != manifest_version.strip_edges()

func _on_manifest_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		return
	var manifest := parsed as Dictionary
	var remote_version := String(manifest.get("version", "")).strip_edges()
	var url := String(manifest.get("url", ""))
	var notes := String(manifest.get("notes", ""))
	if not is_update_available(_local_version(), remote_version):
		return
	update_available.emit(remote_version, url, notes)
	_show_notice(remote_version, url)

## Self-contained, non-blocking notice anchored bottom-right. Dismissible.
func _show_notice(version: String, url: String) -> void:
	if is_instance_valid(_notice):
		return
	_notice = CanvasLayer.new()
	_notice.layer = 100
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	# Localized: "Update available (vX)". Falls back to the key if a locale is missing it.
	label.text = tr("ui.update.available").format({"version": version})
	row.add_child(label)
	var dl := Button.new()
	dl.text = tr("ui.update.download")
	dl.pressed.connect(func() -> void:
		if not url.is_empty():
			OS.shell_open(url))
	row.add_child(dl)
	var close := Button.new()
	close.text = "x"
	close.pressed.connect(func() -> void:
		if is_instance_valid(_notice):
			_notice.queue_free()
			_notice = null)
	row.add_child(close)
	panel.add_child(row)
	_notice.add_child(panel)
	add_child(_notice)
