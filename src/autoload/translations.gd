# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# translations.gd — tr() wrapper with prefix assertion
#
# Registered as autoload "Translations" in project.godot.
#
# Pitfall 7: pick ONE translation pattern and use it everywhere.
# Convention: explicit tr() calls everywhere via this wrapper.
# Phase 6 convention: every key starts with one of the four namespaces below.
#
# Usage:
#   label.text = Translations.t("ui.about.title")
#   label.text = Translations.t("ui.hotbar.slot_filled", {"brick_name": "1×1 brick"})
#
# Key namespace contract (RESEARCH.md Pitfall 6 — namespaced keys, not surface forms):
#   ui.*       — UI chrome (settings, HUD, dialogs, about screen)
#   bricks.*   — brick display names and descriptions
#   device.*   — device-tier names and warnings
#   toast.*    — transient notification messages
#   chests.*   — chest type display names (e.g. "chests.regular", "chests.gold")
#   items.*    — inventory item display names and descriptions
#
# In debug builds, an unrecognised key prefix triggers a push_error so typos
# are caught early in development. In release builds, it falls through to tr().
extends Node

## Valid key namespaces as defined in UI-SPEC.md Copywriting Contract.
const _VALID_PREFIXES: PackedStringArray = ["ui.", "bricks.", "device.", "toast.", "chests.", "items."]


## Load locale/en.po and locale/nl.po at startup and register them with TranslationServer.
##
## The .po files in this project are intentionally NOT pre-imported via Godot's
## editor pipeline (no .po.import sidecar exists), because the project is
## developed CLI-first. Without registration, tr() returns the raw key, which
## surfaced during /gsd:verify-work 3 as buttons reading
## "ui.settings.graphics.preset.auto" instead of "Auto".
##
## This _ready parses the PO files at runtime — minimal subset that handles
## msgid "X" / msgstr "Y" pairs, blank-line separated. Multi-line strings
## (msgid_plural, msgctxt, continuation lines) are not currently used in
## locale/en.po so they are not parsed.
##
## Locale selection priority (Plan 06-10):
##   1. User override from user://settings.cfg [settings] locale
##   2. OS locale language code if a matching .po exists ("en" or "nl")
##   3. Default: "en"
const _PO_PATHS: Dictionary = {
	"en": "res://locale/en.po",
	"nl": "res://locale/nl.po",
}
const _DEFAULT_LOCALE: String = "en"
const _SETTINGS_PATH: String = "user://settings.cfg"

## Valid locale codes accepted by the runtime switcher (T-06-L1 mitigation).
const _ALLOWED_LOCALES: PackedStringArray = ["en", "nl"]


func _ready() -> void:
	# Load and register all available .po translations.
	for locale_code: String in _PO_PATHS:
		var po_path: String = _PO_PATHS[locale_code]
		var loaded_count: int = _load_po(po_path, locale_code)
		if loaded_count == 0:
			push_warning("Translations: %s contained 0 messages." % po_path)

	# Determine the active locale using the priority chain.
	var active_locale: String = _determine_locale()
	TranslationServer.set_locale(active_locale)


## Load a single .po file and register it with TranslationServer.
## Returns the number of messages loaded (0 on failure).
func _load_po(po_path: String, locale_code: String) -> int:
	var file: FileAccess = FileAccess.open(po_path, FileAccess.READ)
	if file == null:
		push_error("Translations: cannot open %s (err %d). UI will show raw translation keys." % [po_path, FileAccess.get_open_error()])
		return 0
	var translation: Translation = Translation.new()
	translation.locale = locale_code
	var current_msgid: String = ""
	var pending_msgstr: bool = false
	var loaded_count: int = 0
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			# Blank line resets the msgid/msgstr pair; comments are ignored.
			current_msgid = ""
			pending_msgstr = false
			continue
		if line.begins_with("msgid \"") and line.ends_with("\""):
			# Strip leading 'msgid "' (7 chars) and trailing '"' (1 char).
			current_msgid = line.substr(7, line.length() - 8)
			pending_msgstr = true
			continue
		if line.begins_with("msgstr \"") and line.ends_with("\""):
			# Strip leading 'msgstr "' (8 chars) and trailing '"' (1 char).
			var msgstr: String = line.substr(8, line.length() - 9)
			# Empty msgid is the .po header (Project-Id-Version, etc.) — skip.
			# Empty msgstr is intentional for transitional keys — skip those too.
			if current_msgid != "" and pending_msgstr and msgstr != "":
				translation.add_message(current_msgid, msgstr)
				loaded_count += 1
			current_msgid = ""
			pending_msgstr = false
	file.close()
	TranslationServer.add_translation(translation)
	return loaded_count


## Determine the active locale using priority chain:
##   1. User override in user://settings.cfg [settings] locale (T-06-L1: validated)
##   2. OS locale language code (if "en" or "nl")
##   3. Default "en"
func _determine_locale() -> String:
	# Priority 1: user-saved preference.
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) == OK:
		var saved: String = cfg.get_value("settings", "locale", "")
		if saved in _ALLOWED_LOCALES:
			return saved

	# Priority 2: OS locale language code.
	var os_locale: String = OS.get_locale_language()
	if os_locale in _ALLOWED_LOCALES:
		return os_locale

	# Priority 3: default.
	return _DEFAULT_LOCALE


## Translate a key, optionally substituting named placeholders.
##
## @param key    A dotted translation key, e.g. "ui.about.title".
##               Must start with one of: ui., bricks., device., toast., chests., items.
## @param ctx    Optional Dictionary of named substitutions, e.g. {"n": "3"}.
##               Applied via String.format(ctx) after tr() lookup.
## @return       The translated (and substituted) string.
func t(key: String, ctx: Dictionary = {}) -> String:
	# Validate key prefix in debug builds (cheap string operation, not hot-path)
	var prefix_ok := false
	for prefix: String in _VALID_PREFIXES:
		if key.begins_with(prefix):
			prefix_ok = true
			break

	if not prefix_ok and OS.is_debug_build():
		var err_msg := ("Translations.t(): key '%s' does not start with a valid namespace. " % key
			+ "Valid prefixes: ui., bricks., device., toast., chests., items. "
			+ "(RESEARCH.md Pitfall 6 — use namespaced keys, not surface-form strings)")
		push_error(err_msg)

	var translated := tr(key)
	if ctx.is_empty():
		return translated
	return translated.format(ctx)
