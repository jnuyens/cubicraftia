---
phase: 06-first-five-minutes
plan: 01
subsystem: scaffolding
tags: [signals, test-stubs, i18n, assets, ftue]
dependency_graph:
  requires: []
  provides:
    - ChestEntity.opened signal (for FTUE step 1)
    - Inventory.item_added signal (for FTUE step 2)
    - GUT test stubs for all 7 Phase 6 test files
    - conftest_phase6.gd fixtures
    - 93 EN i18n key stubs (Surfaces 1-8)
    - 14 asset stub PNG files (icons + textures + presets)
  affects:
    - src/world/chest_entity.gd
    - src/autoload/inventory.gd
    - locale/en.po
    - tests/ (7 new files)
    - assets/textures/ (14 new files)
tech_stack:
  added: []
  patterns:
    - GDScript signal declaration + emit (surgical 2-line additions)
    - GUT pending() stubs for TDD wave 2 implementation
    - Minimal 1x1 transparent PNG for scene-load-safe asset stubs
key_files:
  created:
    - tests/conftest_phase6.gd
    - tests/unit/test_avatar_config_schema.gd
    - tests/unit/test_avatar_preset_validity.gd
    - tests/unit/test_ftue_state_machine.gd
    - tests/unit/test_deeplink_parser.gd
    - tests/unit/test_telemetry_rotation.gd
    - tests/unit/test_world_thumbnail_capture.gd
    - tests/integration/test_first_time_user_e2e.gd
    - assets/textures/title/title_bg.png
    - assets/textures/ui/world_thumb_placeholder.png
    - assets/textures/ui/avatar_presets/preset_1.png through preset_8.png
    - assets/textures/icons/ftue_arrow.png
    - assets/textures/icons/icon_plus.png
    - assets/textures/icons/icon_arrow_down.png
    - assets/textures/icons/icon_dice.png
  modified:
    - src/world/chest_entity.gd
    - src/autoload/inventory.gd
    - locale/en.po
decisions:
  - "item_added.emit() fires at BOTH success paths in _apply_add(): the slot-hint early-return path AND the normal two-pass path; original requested count is captured before count is mutated by slot filling"
  - "item_added does NOT fire for chest ADD events (_apply_add_to_chest) or for REMOVE/MOVE/SPLIT/SWAP events — only for builder inventory ADD"
  - "opened.emit() fires in _open_panel() immediately before slide_in.open_chest_mode() call — guaranteed to precede panel instantiation"
  - "93 EN locale keys added (vs. spec's stated 44) because the UI-SPEC's count excluded Surface 3 world_select (21 keys) and Surface 4 new_world (14 keys) from its tally; all keys from the consolidated key list in 06-UI-SPEC.md Localisation Contract were added"
  - "Avatar preset thumbnails (assets/textures/ui/avatar_presets/preset_1..8.png) added as bonus stubs not in the original 6-file plan list — the plan text references them and they prevent scene load crashes"
metrics:
  duration_minutes: 15
  completed: "2026-05-30"
  tasks_completed: 2
  tasks_total: 2
  files_created: 23
  files_modified: 3
---

# Phase 6 Plan 01: Signal Gap Fixes + Test Stubs + i18n Keys + Asset Stubs Summary

Wave 0 scaffolding: two surgical signal additions to production files, 7 GUT test stub files (all pending), conftest_phase6 fixtures, 93 EN i18n key stubs across 8 surfaces, and 14 asset stub PNGs.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Add ChestEntity.opened + Inventory.item_added signals | 94aeb6d | src/world/chest_entity.gd, src/autoload/inventory.gd |
| 2 | GUT test stubs + conftest_phase6 + 93 EN i18n keys + asset stubs | d25ec77 | tests/ (8 files), locale/en.po, assets/textures/ (14 files) |

## What Was Built

**ChestEntity.opened signal** (`src/world/chest_entity.gd`):
- `signal opened()` declared in the signal block after the existing `unlocked` and `broken` signals (line 125)
- `opened.emit()` fires in `_open_panel()` (line 234) immediately before `slide_in.open_chest_mode(...)` is called — guaranteed to precede panel instantiation

**Inventory.item_added signal** (`src/autoload/inventory.gd`):
- `signal item_added(builder_id: String, def_id: String, count: int)` declared after `inventory_changed` (line 97)
- `item_added.emit()` fires in `_apply_add()` at both success exit points (lines 866 and 897), before `inventory_changed.emit()`, so listeners can act on the new state
- Does NOT fire for chest ADD events, REMOVE, MOVE, SPLIT, SWAP, CRAFT, or any other event kind

**GUT test stubs** (`tests/`):
- `conftest_phase6.gd`: Phase6Fixtures class with `make_avatar_cfg()`, `make_telemetry_cfg_path()`, `make_world_index_path()` static helpers
- `tests/unit/test_avatar_config_schema.gd`: 10 pending() stubs for avatar cfg round-trip and all key/range validations
- `tests/unit/test_avatar_preset_validity.gd`: 7 pending() stubs for 8-preset diversity and validity
- `tests/unit/test_ftue_state_machine.gd`: 8 pending() stubs for FTUE step 1-4 advancement logic
- `tests/unit/test_deeplink_parser.gd`: 7 pending() stubs for DeepLinkHandler token parsing
- `tests/unit/test_telemetry_rotation.gd`: 7 pending() stubs for OnboardingTelemetry 10k-cap rotation
- `tests/unit/test_world_thumbnail_capture.gd`: 4 pending() stubs (require viewport — marked accordingly)
- `tests/integration/test_first_time_user_e2e.gd`: 8 pending() stubs for full first-run e2e flow

**EN locale keys** (`locale/en.po`):
- 93 new Phase 6 msgid stubs added (all msgstr empty), covering Surfaces 1-8 from 06-UI-SPEC.md consolidated key list
- No existing msgid entries modified
- File grew from 1253 to 1548 lines

**Asset stubs** (`assets/textures/`):
- 6 required stubs: title_bg.png, world_thumb_placeholder.png, ftue_arrow.png, icon_plus.png, icon_arrow_down.png, icon_dice.png
- 8 bonus stubs: avatar_presets/preset_1.png through preset_8.png (referenced by 06-UI-SPEC.md Surface 2 but not listed in plan's 6-file list)
- All 14 are valid minimal 1x1 transparent PNGs (will not crash Godot's importer)

## Deviations from Plan

**1. [Rule 2 - Missing critical functionality] Added avatar preset thumbnail stubs**
- **Found during:** Task 2 implementation
- **Issue:** The plan's asset stubs list specified 6 files but the plan text itself says "8 preset thumbnails" (see success criteria) and 06-UI-SPEC.md Surface 2 references `assets/textures/ui/avatar_presets/preset_N.png`. Without these, avatar_creator.tscn would crash on load in Phase 6 Plan 02.
- **Fix:** Created 8 additional stub PNGs at assets/textures/ui/avatar_presets/preset_1.png through preset_8.png
- **Files modified:** assets/textures/ui/avatar_presets/ (8 new files)
- **Commit:** d25ec77

**2. [Deviation - Locale key count] 93 keys added vs spec's stated 44**
- **Found during:** Task 2 implementation
- **Issue:** The 06-UI-SPEC.md states "Total new Phase 6 EN keys: 44" but the consolidated key list contains 93 distinct keys (6+37+21+14+6+7+1+1=93). The discrepancy appears to be a miscalculation in the spec's summary (Surface 2 alone has 37 avatar keys, Surface 3 has 21 world_select keys, Surface 4 has 14 new_world keys).
- **Fix:** Added all keys from the consolidated key list — the correct reference is the key list, not the summary count. The verification criterion ("count must be >= 44 higher than before") is satisfied (93 > 44).
- **Files modified:** locale/en.po

## Known Stubs

All test files contain only `pending()` calls — by design. These stubs exist for wave 2-6 implementation:

| File | Stub reason |
|------|-------------|
| test_avatar_config_schema.gd | AvatarConfig class not yet written (Plan 06-02) |
| test_avatar_preset_validity.gd | AvatarPresets class not yet written (Plan 06-02) |
| test_ftue_state_machine.gd | FtueOverlay class not yet written (Plan 06-04) |
| test_deeplink_parser.gd | DeepLinkHandler class not yet written (Plan 06-05) |
| test_telemetry_rotation.gd | OnboardingTelemetry class not yet written (Plan 06-07) |
| test_world_thumbnail_capture.gd | WorldSave.capture_thumbnail not yet written; requires viewport |
| test_first_time_user_e2e.gd | Full scene graph required; integration flow across Plans 06-02..06-04 |

All locale msgstr values are empty — NL translations are Plan 06-10.

## Threat Flags

None. The two signal additions do not introduce new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries. `item_added` emits only a game item def_id (public data, no PII).

## Self-Check: PASSED

- src/world/chest_entity.gd: FOUND (signal opened at line 125, opened.emit() at line 234)
- src/autoload/inventory.gd: FOUND (signal item_added at line 97, item_added.emit() at lines 866+897)
- tests/conftest_phase6.gd: FOUND
- tests/unit/test_avatar_config_schema.gd: FOUND
- tests/unit/test_avatar_preset_validity.gd: FOUND
- tests/unit/test_ftue_state_machine.gd: FOUND
- tests/unit/test_deeplink_parser.gd: FOUND
- tests/unit/test_telemetry_rotation.gd: FOUND
- tests/unit/test_world_thumbnail_capture.gd: FOUND
- tests/integration/test_first_time_user_e2e.gd: FOUND
- locale/en.po: 93 new Phase 6 keys added (FOUND)
- assets/textures/title/title_bg.png: FOUND
- assets/textures/ui/world_thumb_placeholder.png: FOUND
- assets/textures/icons/ftue_arrow.png + icon_plus.png + icon_arrow_down.png + icon_dice.png: ALL FOUND
- assets/textures/ui/avatar_presets/preset_1..8.png: ALL FOUND
- Commits 94aeb6d and d25ec77: VERIFIED in git log
