---
phase: 06-first-five-minutes
plan: 10
subsystem: localisation
tags: [i18n, nl, locale, settings-ui, translations]
dependency_graph:
  requires: [06-03, 06-04, 06-05, 06-06, 06-08]
  provides: [full-nl-translations, locale-runtime-switcher]
  affects: [src/ui/settings_menu.gd, locale/en.po, locale/nl.po, project.godot, src/autoload/translations.gd]
tech_stack:
  added: []
  patterns: [PO localisation, TranslationServer runtime locale switch, ConfigFile locale persistence]
key_files:
  created:
    - locale/nl.po
  modified:
    - locale/en.po
    - project.godot
    - src/autoload/translations.gd
    - src/ui/settings_menu.gd
    - scripts/glossary-allowlist.txt
decisions:
  - "locale/nl.po allowlisted in glossary-allowlist.txt: disclaimer msgstrs mirror en.po allowlisted content (LEGO Group, Mojang Studios are legally required disclaimers, not gameplay terminology)"
  - "ui.username.inline_valid left empty in nl.po — intentionally empty in en.po too (used as placeholder for a non-visible validation state)"
  - "ui.signin.age_checkbox left empty in nl.po per 06-UI-SPEC.md Localisation Contract note 5 (transitional key)"
  - "Translations.gd loads both en.po and nl.po via _load_po() helper; locale priority: user pref > OS language code > default en"
  - "T-06-L1 mitigation applied in both translations.gd and settings_menu.gd: locale codes validated as 'en'|'nl' before use"
metrics:
  duration: "~30 minutes"
  completed: "2026-05-30"
  tasks_completed: 2
  files_modified: 6
---

# Phase 06 Plan 10: Dutch (NL) Localisation + Locale Runtime Switcher Summary

Full Dutch translation for all 478 msgids (Phase 1-6) + Language section in settings with EN/NL buttons for runtime locale switching.

## What Was Built

**Task 1 — locale/en.po + locale/nl.po + project.godot registration:**

- `locale/en.po`: filled all 44 Phase 6 empty msgstr stubs with canonical EN copy per 06-UI-SPEC.md Copywriting Contract. ui.ftue.step_3 uses the longer Recommendation 5 variant.
- `locale/nl.po`: replaced 17-line stub with 478 complete Dutch translations:
  - Informal 2nd person singular ("je", not "u") throughout
  - Terminology: brick = "brick" (brand term kept), stud → "nop", builder → "bouwer", chest → "kist", workbench → "werkbank", pickaxe → "houweel", shovel → "schop"
  - Phase 6 canonical NL strings from 06-CONTEXT.md Copywriting Contract used verbatim
  - Parental consent copy uses formal Dutch appropriate for legal context
  - 2 intentionally empty msgstrs: ui.signin.age_checkbox (per plan spec) and ui.username.inline_valid (mirrors en.po)
- `project.godot`: added `internationalization/locale/translations=PackedStringArray("res://locale/nl.po")`
- `src/autoload/translations.gd`: refactored to load both en.po and nl.po via `_load_po()` helper; locale priority chain (user pref → OS language code → "en" default); T-06-L1 locale code validation
- `scripts/glossary-allowlist.txt`: added `locale/nl.po:` to allowlist (disclaimer msgstrs are legally required trademark notices, same content as the already-allowlisted en.po entries)

Also added 3 new locale keys to both files: `ui.settings.language_label`, `ui.settings.locale_en`, `ui.settings.locale_nl`

**Task 2 — settings_menu.gd Language section:**

- `_setup_language_section()`: adds Language heading + English/Nederlands button row before the Legal section
- `_on_locale_btn_pressed()`: calls `_on_locale_changed()` + `_save_locale_pref()`
- `_on_locale_changed()`: `TranslationServer.set_locale()` + `get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)` for immediate in-place update
- `_save_locale_pref()`: persists to `user://settings.cfg [settings] locale`; T-06-L1: validates locale code as "en" or "nl" only
- `_load_locale_pref()`: called in `_ready()`; reads saved pref and syncs button accent highlight
- Active locale indicated by 2px accent-yellow border on button (same COLOR_ACCENT pattern as existing tab buttons)

## Commits

- `b5c8adb`: feat(06-10): fill en.po Phase 6 stubs + full NL translation (478 msgids)
- `426cb40`: feat(06-10): settings_menu Language section with EN/NL locale picker

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Security] T-06-L1 locale_code injection mitigation applied in both files**
- **Found during:** Task 1 + Task 2
- **Issue:** Threat model required locale_code from settings.cfg to be validated; plan described it for settings_menu only, but translations.gd also reads the same value
- **Fix:** Added `_ALLOWED_LOCALES: PackedStringArray = ["en", "nl"]` check in translations.gd `_determine_locale()`, and explicit `locale_code != "en" and locale_code != "nl"` guard in settings_menu `_save_locale_pref()`
- **Files modified:** src/autoload/translations.gd, src/ui/settings_menu.gd

**2. [Rule 2 - Missing functionality] glossary-allowlist.txt: nl.po disclaimer msgstrs**
- **Found during:** Task 1 verification (glossary-check.sh)
- **Issue:** nl.po disclaimer msgstrs contain "LEGO Groep" and "Mojang Studios" — legally required trademark disclaimers, same content as en.po (already allowlisted). The glossary check was failing on these lines.
- **Fix:** Added `locale/nl.po:` to glossary-allowlist.txt (same pattern as `locale/en.po:`)
- **Files modified:** scripts/glossary-allowlist.txt

### Pre-existing Failures (Out of Scope)

The following glossary-check.sh failures existed before this plan and are not caused by any changes here. Logged to deferred-items:

- `src/crafting/recipes/recipe_stick.tres:8` — "Minecraft" in a code comment
- `src/autoload/inventory.gd:1203` — "Minecraft" in a code comment
- `src/ui/hp_bar.gd:50` — "Minecraft-style" in a code comment
- `docs/EULA.md:23`, `docs/store-readiness/*.md` — legal/store docs with trademark mentions

These are deferred for a future housekeeping plan.

## Verification Results

1. `grep -c "^msgid" locale/nl.po` → 478 (all Phase 1-6 msgids present)
2. `grep -c "^msgstr \"\"" locale/nl.po` → 3 (header + ui.signin.age_checkbox + ui.username.inline_valid — 2 intentional, 1 PO header)
3. `grep "nl\.po" project.godot` → `internationalization/locale/translations=PackedStringArray("res://locale/nl.po")`
4. `grep "set_locale" src/ui/settings_menu.gd` → present (line 527)
5. `grep "NOTIFICATION_TRANSLATION_CHANGED" src/ui/settings_menu.gd` → present (line 531)
6. `grep -A1 "ui.ftue.step_3" locale/nl.po` → non-empty NL translation present
7. Glossary check: nl.po lines pass; pre-existing failures are out of scope

## Threat Flags

None — no new network endpoints, auth paths, or file access patterns beyond those in the plan's threat model.

## Self-Check: PASSED

- locale/nl.po exists with 478 msgids
- locale/en.po Phase 6 stubs filled
- project.godot contains nl.po registration
- src/ui/settings_menu.gd contains set_locale and NOTIFICATION_TRANSLATION_CHANGED
- Commits b5c8adb and 426cb40 exist in git log
