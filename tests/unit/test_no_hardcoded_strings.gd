# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_no_hardcoded_strings.gd — DOC-10 + Phase 6 prep: i18n hygiene
#
# Scans every .tscn under src/ui/ for `text = "..."` lines that contain
# raw English text not wrapped in tr(). Fails if any non-whitelisted raw
# string is found.
#
# Phase 1 / Wave 0 behaviour: src/ui/ is empty (no .tscn files yet).
# The test passes trivially — it becomes load-bearing when Plan 06 lands.
# This is intentional: the guard must exist BEFORE the UI scenes are authored
# so that Plan 06's scenes are validated from the moment they are committed.
#
# Allowlisted raw strings (permitted because they are non-translatable):
#   - Empty strings: text = ""
#   - Pure numeric strings: text = "1", text = "8", etc.
#   - Version strings with a placeholder: text = "Version {version}" → must use tr()
#
# Referenced DOC: DOC-10 — "every UI string uses locked terminology"
# Referenced: RESEARCH.md Pitfall 6, Pitfall 7, UI-SPEC.md Copywriting Contract
extends GutTest

const Helpers = preload("res://tests/conftest_helpers.gd")

## Raw English text in .tscn `text = "..."` lines that is explicitly permitted
## without tr() wrapping (non-user-facing strings).
## All other non-empty, non-numeric strings are violations.
const ALLOWED_RAW_STRINGS: PackedStringArray = [
	"",         # empty text = ""
	".",        # separator
	"/",        # separator
	":",        # separator
	"→",        # language-neutral navigation arrow (tab switcher)
]


## A translation KEY (e.g. "ui.avatar.title") set as a Control's text is the project's
## auto-translate i18n pattern — TranslationServer resolves it at display time, so it is
## NOT raw English. Keys are lowercase dotted identifiers with no spaces.
static func _is_translation_key(s: String) -> bool:
	if not s.contains("."):
		return false
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")
	return re.search(s) != null

## Pattern for `text = "some value"` lines in .tscn files.
## Captures the string between the quotes.
const TEXT_PROPERTY_PREFIX: String = 'text = "'
const TEXT_PROPERTY_SUFFIX: String = '"'


func test_no_hardcoded_english_in_ui_tscn_files() -> void:
	## Scan all .tscn files under src/ui/ for raw English text properties.
	## At Plan 02 time src/ui/ is empty so this passes trivially.
	## This becomes the load-bearing gate when Plan 06 lands.
	var tscn_files := Helpers.find_tscn_files("res://src/ui")

	if tscn_files.is_empty():
		gut.p("src/ui/ contains no .tscn files yet (Plan 02 Wave 0 — passes trivially)")
		pass_test("No .tscn files in src/ui/ at this stage")
		return

	var violations: Array[String] = []

	for tscn_path: String in tscn_files:
		var content := Helpers.read_text_file(tscn_path)
		if content.is_empty():
			continue
		var line_number := 0
		for line: String in content.split("\n"):
			line_number += 1
			line = line.strip_edges()

			# Look for `text = "some value"` properties
			if not line.begins_with(TEXT_PROPERTY_PREFIX):
				continue

			# Extract the string value between the quotes
			var value_start := len(TEXT_PROPERTY_PREFIX)
			var value_end := line.rfind(TEXT_PROPERTY_SUFFIX)
			if value_end <= value_start:
				continue
			var raw_value := line.substr(value_start, value_end - value_start)

			# Skip whitelisted values
			if raw_value in ALLOWED_RAW_STRINGS:
				continue

			# Skip translation keys (the auto-translate pattern, e.g. text = "ui.x.y").
			# These are resolved by TranslationServer at display time — not raw English.
			if _is_translation_key(raw_value):
				continue

			# Skip pure numeric strings (hotbar slot counts, etc.)
			if raw_value.is_valid_int() or raw_value.is_valid_float():
				continue

			# Skip anything that already uses tr() — scene editor writes these as
			# TRANS("key") or TranslationServer.translate("key") in .tscn files
			if "TRANS(" in line or "tr(" in line or "TranslationServer" in line:
				continue

			# Remaining non-empty, non-numeric, non-translated strings are violations
			violations.append(
				"%s:%d: raw text '%s' (must use tr('ui.namespace.key'))" % [
					tscn_path, line_number, raw_value
				]
			)

	if violations.is_empty():
		pass_test("All .tscn text properties are i18n-clean")
	else:
		for v: String in violations:
			gut.p("VIOLATION: %s" % v)
		var fail_msg := ("%d hardcoded string(s) found in src/ui/ .tscn files. " % violations.size()
			+ "Use tr('ui.namespace.key') instead of raw English. "
			+ "(DOC-10, RESEARCH.md Pitfall 6)")
		fail_test(fail_msg)


func test_autoload_strings_use_valid_prefix() -> void:
	## Verify that any string in the autoload source files that looks like
	## a translation key follows the ui./bricks./device./toast. prefix convention.
	## (Supplementary check — the Translations.t() assertion is the primary gate.)
	var gd_files := Helpers.find_gd_files("res://src/autoload")
	var violations: Array[String] = []
	var valid_prefixes := ["ui.", "bricks.", "device.", "toast."]

	for gd_path: String in gd_files:
		var content := Helpers.read_text_file(gd_path)
		if content.is_empty():
			continue
		var line_number := 0
		for line: String in content.split("\n"):
			line_number += 1
			# Look for Translations.t("...") calls
			if 'Translations.t("' not in line:
				continue
			# Extract the key argument
			var key_start := line.find('Translations.t("') + len('Translations.t("')
			var key_end := line.find('"', key_start)
			if key_end <= key_start:
				continue
			var key := line.substr(key_start, key_end - key_start)

			var prefix_ok := false
			for prefix: String in valid_prefixes:
				if key.begins_with(prefix):
					prefix_ok = true
					break
			if not prefix_ok:
				violations.append(
					"%s:%d: key '%s' has invalid prefix (must be ui./bricks./device./toast.)"
					% [gd_path, line_number, key]
				)

	if violations.is_empty():
		pass_test("All Translations.t() keys in autoloads use valid prefixes")
	else:
		for v: String in violations:
			gut.p("VIOLATION: %s" % v)
		fail_test(
			"%d invalid key prefix(es) found in src/autoload/ files." % violations.size()
		)
