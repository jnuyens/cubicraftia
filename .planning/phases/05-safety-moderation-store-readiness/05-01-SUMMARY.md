---
phase: 05-safety-moderation-store-readiness
plan: "01"
subsystem: test-scaffold
tags: [gut, i18n, theme, assets, phase5-scaffold]
dependency_graph:
  requires: []
  provides:
    - tests/conftest_phase5.gd
    - tests/unit/test_block_unblock.gd
    - tests/unit/test_report_submission.gd
    - tests/unit/test_dob_parser.gd
    - tests/unit/test_parental_consent_token.gd
    - tests/unit/test_profanity_multilang.gd
    - tests/unit/test_username_validator.gd
    - tests/unit/test_eula_hash_recompute.gd
    - tests/integration/test_blocks_check_on_join.gd
    - tests/integration/test_parental_consent_e2e.gd
    - 96 new locale/en.po msgid keys across 12 namespaces
    - StyleBox_legal_summary, StyleBox_warning_banner, StyleBox_context_menu_panel in cubicraftia.tres
    - icon_warning.png, icon_email.png, icon_check.png stubs
  affects:
    - All Phase 5 plans (depend on conftest_phase5.gd and test file presence)
    - Wave 3 UI plans (reference the new StyleBoxes and icon assets)
tech_stack:
  added: []
  patterns:
    - GUT pending() stubs (Phase4Fixtures structural pattern)
    - gettext PO format msgid/msgstr pairs
    - StyleBoxFlat additive extension pattern (Phase 1-4 entries unchanged)
    - Minimal valid 1x1 transparent PNG (stub asset pattern)
key_files:
  created:
    - tests/conftest_phase5.gd
    - tests/unit/test_block_unblock.gd
    - tests/unit/test_report_submission.gd
    - tests/unit/test_dob_parser.gd
    - tests/unit/test_parental_consent_token.gd
    - tests/unit/test_profanity_multilang.gd
    - tests/unit/test_username_validator.gd
    - tests/unit/test_eula_hash_recompute.gd
    - tests/integration/test_blocks_check_on_join.gd
    - tests/integration/test_parental_consent_e2e.gd
    - assets/textures/icons/icon_warning.png
    - assets/textures/icons/icon_email.png
    - assets/textures/icons/icon_check.png
  modified:
    - locale/en.po
    - assets/themes/cubicraftia.tres
decisions:
  - "Added 96 i18n keys (vs 53 stated in UI-SPEC summary) because the consolidated key list in 05-UI-SPEC.md contains 96 unique keys — the 53 figure was an earlier draft count; the authoritative key list is the explicit consolidated section"
  - "PNG stubs are 1x1 transparent (68 bytes valid PNG) not 32x32 as mentioned in plan header — plan body specifies only that files must be valid PNGs; Wave 3 will replace with real artwork"
  - "Phase5Fixtures.open_temp_world delegates to the same WorldSave.open_world pattern as Phase4Fixtures (exact structural mirror)"
metrics:
  duration: "319 seconds (~5 min)"
  completed: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 13
  files_modified: 2
---

# Phase 05 Plan 01: GUT Scaffold + i18n + Theme + Asset Stubs Summary

Wave 0 scaffold: 10 GUT test files with pending() stubs (conftest + 7 unit + 2 integration), 96 new i18n keys across 12 namespaces in locale/en.po, 3 new StyleBoxFlat entries in cubicraftia.tres, and 3 valid PNG placeholder icons.

## Objective Achieved

All Phase 5 GUT test stubs exist and are structurally ready for activation in 05-12. No later plan is blocked on missing test infrastructure. The i18n keys, StyleBoxes, and icon stubs are all in place for the Wave 3 UI implementation plans.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | conftest_phase5.gd + 7 unit test stubs | 956ad73 | tests/conftest_phase5.gd, tests/unit/test_block_unblock.gd, test_report_submission.gd, test_dob_parser.gd, test_parental_consent_token.gd, test_profanity_multilang.gd, test_username_validator.gd, test_eula_hash_recompute.gd |
| 2 | Integration stubs + i18n + StyleBoxes + icons | 945f248 | tests/integration/test_blocks_check_on_join.gd, test_parental_consent_e2e.gd, locale/en.po, assets/themes/cubicraftia.tres, assets/textures/icons/icon_{warning,email,check}.png |

## Artifacts Delivered

### Test Files (10 total)

**conftest_phase5.gd:** `class_name Phase5Fixtures extends RefCounted` with static helpers:
- `open_temp_world(mode)` — delegates to WorldSave.open_world, mirrors Phase4Fixtures pattern
- `cleanup_temp_world(world_id)` — removes temp world directory
- `make_mock_block_row(blocker, blocked)` — Dictionary matching 004_blocks.sql schema (blocker_uid, blocked_uid, created_at)
- `make_mock_report_row(reporter, reported, surface, category)` — Dictionary matching 005_reports.sql schema
- `make_mock_consent_row(child_uid, parent_email)` — Dictionary matching 006_parental_consents.sql schema

**Unit test stubs (7, each extends GutTest, all pending("Phase 5 — activate in 05-12")):**
- test_block_unblock.gd: 4 stubs (block direction, RLS visibility, unblock, blocked-sees-nothing)
- test_report_submission.gd: 3 stubs (reporter insert, reported cannot see, evidence capture)
- test_dob_parser.gd: 4 stubs (age 12, age 13, boundary today, invalid date)
- test_parental_consent_token.gd: 4 stubs (128-bit base32, single-use, 7-day TTL, revoke distinct)
- test_profanity_multilang.gd: 4 stubs (filter EN, filter_reject true, filter_reject false, NL word)
- test_username_validator.gd: 5 stubs (reserved prefix, valid format, special chars, too short, cooldown)
- test_eula_hash_recompute.gd: 3 stubs (consistent hash, different content, mismatch detection)

**Integration test stubs (2, all pending):**
- test_blocks_check_on_join.gd: 2 stubs (blocked user cannot join, unblocked can join after unblock)
- test_parental_consent_e2e.gd: 3 stubs (restricted before consent, unlock on confirm, revoke blocks)

### i18n Keys (96 new msgid entries)

Added to locale/en.po below the Phase 4 entries. Namespaces:

| Namespace | Keys | English copy |
|-----------|------|-------------|
| ui.block | 5 | Full copy from 05-UI-SPEC.md Copywriting Contract |
| ui.report | 16 | Full copy from 05-UI-SPEC.md Copywriting Contract |
| ui.signin (DOB) | 18 | Full copy (4 placeholders + 12 months + 2 errors) |
| ui.consent | 15 | Full copy from 05-UI-SPEC.md Copywriting Contract |
| ui.legal | 10 | Full copy from 05-UI-SPEC.md Copywriting Contract |
| ui.restricted | 6 | Full copy from 05-UI-SPEC.md Copywriting Contract |
| ui.username | 7 | Full copy from 05-UI-SPEC.md Copywriting Contract |
| ui.friends | 1 | "Report" |
| ui.chat | 1 | "Report this message" |
| ui.nameplate | 2 | "Report {username}", "Block {username}" |
| ui.settings | 15 | Full copy from 05-UI-SPEC.md Copywriting Contract |

### StyleBoxes (3 new entries in cubicraftia.tres)

- **StyleBox_legal_summary:** Transparent bg, 2px accent-yellow left border, 8px padding
- **StyleBox_warning_banner:** Warning amber fill (#E8890C), no border, no rounding, zero margin
- **StyleBox_context_menu_panel:** Navy 0.96 alpha, rounded 8px, 8px content margin

No existing Phase 1-4 StyleBox entries were modified.

### Icon Stubs (3 new PNG files)

- `assets/textures/icons/icon_warning.png` — 68-byte valid 1x1 transparent PNG
- `assets/textures/icons/icon_email.png` — 68-byte valid 1x1 transparent PNG
- `assets/textures/icons/icon_check.png` — 68-byte valid 1x1 transparent PNG

All three pass PNG signature validation. Wave 3 UI plans will replace with real 16x16/48x48 artwork.

## Deviations from Plan

### Auto-noted: i18n Key Count

**Found during:** Task 2

**Issue:** The plan's success criteria states "+53 msgid entries" and the 05-UI-SPEC.md summary says "Total new keys: 53". However, the authoritative consolidated key list in 05-UI-SPEC.md contains 96 unique keys. The "53" figure appears to be a stale count from an earlier draft before the settings account section (15 keys) and full month names (12 keys) were added.

**Fix:** Added all 96 keys from the consolidated list. More keys is correct — omitting keys from the consolidated list would cause translator errors and missing copy in Phase 5 UI plans.

**Impact:** grep -c "^msgid" increases by 96 (not 53) from the Phase 4 baseline. The success criteria check `increases by 53` will show a larger increase, which is acceptable (the hard floor was 53; actual is 96).

### Auto-noted: PNG Stub Dimensions

**Found during:** Task 2

**Issue:** Plan header success criteria lists "32×32 placeholders" but the 05-UI-SPEC.md body says the icons are 16x16 (warning, check) and 48x48 (email) at 1x scale, and the plan action says only that files "MUST be valid PNGs".

**Fix:** Created 1x1 transparent PNG stubs (valid, minimal). Wave 3 UI plans will replace with correct-sized artwork. Using 1x1 avoids hardcoding the wrong dimensions in the placeholder.

## Known Stubs

All test functions contain `pending("Phase 5 — activate in 05-12")` — this is intentional by design. The icon PNG files are 1x1 transparent stubs to be replaced in Wave 3.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced. Test files are test-only (not shipped). The locale/en.po and cubicraftia.tres changes are plain data files with no executable surface (T-05-W0-SC disposition: accept).

## Self-Check: PASSED

All 13 created files verified to exist. Both commits (956ad73, 945f248) confirmed in git log. Three StyleBoxes present in cubicraftia.tres. Three PNG files have valid PNG signatures. 96 new msgid entries confirmed (381 total vs 285 pre-Phase-5 baseline).
