---
phase: 06-first-five-minutes
verified: 2026-05-30T12:00:00Z
status: human_needed
score: 4/4 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Run the full FTUE flow end-to-end on a real device or emulator"
    expected: "Tap install → sign up → avatar creator appears → select/customise → New World → survival world loads → FTUE overlay appears with 4 steps → open chest → mine tree → place plank → overlay completes with 'That's it. The world is yours.' → bed is beside chest"
    why_human: "ftue_overlay.gd instantiates only at runtime with scene tree, WorldClock, StudGrid and ChestEntity present. GUT headless tests exercise the data layer but cannot simulate the live 4-step step-machine traversal with GPU rendering."
  - test: "Verify invite-link joiner flow end-to-end on at least one platform"
    expected: "Tap cubicraftia://invite/TOKEN link → abbreviated sign-in or bypass (if signed in) → redeems token → mutual friendship created → player spawns next to host with 'This is [Friend]'s world. They have what you need to get started.' tip → no FTUE overlay appears"
    why_human: "Deep-link URI handling relies on OS-level URL scheme registration. The _parse_args() unit tests verify parsing, but the full mobile Universal Links / Android App Links flow (server-side .well-known config, OS-level link interception) cannot be verified programmatically without a device."
  - test: "Verify avatar 3D SubViewport preview rotates and applies colour to all parts"
    expected: "SubViewport 256x256 shows builder preview rotating at 0.4 rad/s; selecting skin colour updates head albedo; body colour updates torso; leg colour updates legs; hand accessory meshes toggle visible/hidden"
    why_human: "SubViewport rendering and MeshInstance3D material overrides require an active GPU context. avatar_creator.gd is substantive but _apply_config_to_preview requires a live scene tree to produce visible output."
  - test: "Verify NL locale is active and displays correct translations in-game"
    expected: "Switch language to 'Nederlands' in settings; all UI labels (title, world select, FTUE narration, avatar creator) show Dutch text; no raw msgid key-strings visible"
    why_human: "Translations.get_locale() + TranslationServer.set_locale() requires a running Godot instance with the nl.po file loaded. The 477/479 msgid translation coverage is verified by code inspection, but rendering the locale live cannot be confirmed headlessly."
---

# Phase 6: First Five Minutes Verification Report

**Phase Goal:** A first-time player taps install, signs up, customises a builder, taps "New world", walks the first 60 seconds of guided play (open chest → mine a tree → place a plank → optional first-night sleep), and decides to come back tomorrow — and an invite-link joiner skips all of that and appears next to their friend in the host's world.

**Verified:** 2026-05-30T12:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Implementation matches DOCS.md §1.1 — title screen, sign-in / account creation, avatar customisation with 8 presets, world select with "New world" as default | ✓ VERIFIED | `title_scene.gd` builds full UI programmatically: 2s logo fade (line 152), UV-pan shader driven in `_process` (lines 158-162), Sign in / Create account / Settings buttons (lines 276-315), `ui.title.continue` key used and present in en.po + nl.po (CR-02 fixed). `avatar_creator.gd` declares 8 presets in `PRESETS` array (lines 68-156), 5-part customiser (skin/head/face/body/legs/accessories), `user://avatar.cfg` persistence (`_write_avatar_cfg_silent`), `FriendsClient.save_avatar()` Supabase upload. `world_select_screen.gd` enforces `MAX_WORLDS=5` cap (line 47), world cards with `.jpg` thumbnails (line 717, CR-01 fixed). |
| 2 | Implementation matches DOCS.md §1.2 — 4-step unskippable in-world FTUE; ChestEntity.opened → item_added(wood_log) → StudGrid.placed(wood_plank) signal gates; "That's it. The world is yours." completion; persistence via WorldSave.ftue_complete | ✓ VERIFIED | `ftue_overlay.gd`: `STEP_COUNT=4` (line 41), no "skip" word anywhere (`grep -ic "skip"` → 0), signal handlers `_on_chest_opened` (line 399), `_on_item_added` filtered by "wood_log" (line 406), `_on_stud_placed` filtered by `definition.brick_id=="wood_plank"` (line 413). Completion writes `WorldSave.set_world_meta("ftue_complete", var_to_bytes(true))` (line 441) and emits telemetry. `main_scene._maybe_start_ftue()` correctly gates on `Features.is_survival_mode()` and `get_world_meta("ftue_complete")==null` (lines 549-559). ChestEntity retry loop (`_CHEST_RETRY_MAX=10 × 0.5s`, WR-04 fixed). |
| 3 | Implementation matches DOCS.md §1.3 — invite-link joiner skips FTUE; abbreviated sign-in; `pending_ftue_complete` written before world load; joiner tip toast; mutual friendship via token redemption | ✓ VERIFIED | `deep_link_handler.gd`: parses `--uri=cubicraftia://invite/TOKEN` and `--invite=TOKEN` CLI args (lines 108-119), `MIN_TOKEN_LENGTH=20` client gate (CR-04 trailing-bits fix applied — `_generate_invite_token` in `friends_client.gd` now emits trailing group, line 1263-1264). `title_scene.gd`: connects `invite_creation_failed` (CR-05 fixed, lines 592-593), writes `pending_ftue_complete` marker before world load (line 607), joiner tip shown via `ui.deeplink.joiner_tip` after `world_ready` fires (lines 656-662). `main_scene._apply_pending_ftue_complete_if_set()` pre-sets ftue_complete for joiners (lines 577-589). |
| 4 | Implementation matches DOCS.md §1.4 — email+password auth only (no third-party in v1); 4 avatar slots; UNSKIPPABLE tutorial; EN+NL localisation with every string keyed | ✓ VERIFIED | Auth: sign-in panel is email+password only in Phase 6 (OAuth stubs emit `sign_in_failed`). Avatar schema: exactly 8 keys (skin_colour_index, head_shape, face_expression, body_colour_index, body_accessory, leg_colour_index, leg_shoes, hand_accessory). No "skip" in ftue_overlay.gd. NL locale: 477/479 non-empty msgstr entries (2 intentionally empty: `ui.username.inline_valid` per `ui-username-inline_valid-empty-both` decision). `translations.gd` `_VALID_PREFIXES` includes `chests.` and `items.` (CR-06 fixed, line 29). Locale switcher in `settings_menu.gd` (lines 470-508). |

**Score:** 4/4 truths verified

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/ui/title_scene.gd` | Title screen with 2s fade, UV-pan shader, deep-link intercept, signed-in shortcut | ✓ VERIFIED | 778 lines; full implementation; `class_name TitleScene`; UV-pan driven in `_process`; CR-02 and CR-05 fixes confirmed |
| `src/ui/avatar_creator.gd` | 5-part avatar, 8 presets, Randomise, SubViewport preview, user://avatar.cfg, Supabase save | ✓ VERIFIED | 526 lines; 8 PRESETS defined; all customisation handlers wired; `_write_avatar_cfg_silent` + `FriendsClient.save_avatar()` |
| `src/ui/world_select_screen.gd` | 5-world cap, world cards, thumbnails (.jpg), long-press context menu | ✓ VERIFIED | 1166 lines; `MAX_WORLDS=5`; `thumbnail.jpg` in `_load_thumbnail()`; context menu with rename/duplicate/export/delete; WR-05 (empty name guard) and WR-06 (open_world return check) fixes visible |
| `src/ui/ftue_overlay.gd` | 4-step FTUE, signal gates, no-skip, night hint, persistence | ✓ VERIFIED | 636 lines; `STEP_COUNT=4`; `grep -ic "skip"` returns 0; all 3 signal handlers wired; WR-04 chest retry loop (10×0.5s) |
| `src/autoload/deep_link_handler.gd` | Parses cubicraftia:// URI + --invite= CLI; 20-char minimum; consume_pending_token() API | ✓ VERIFIED | 136 lines; `MIN_TOKEN_LENGTH=20`; `_parse_args(PackedStringArray)` extracted for testability; `get_cmdline_args()` (not deprecated `get_command_line_args()`) |
| `src/autoload/onboarding_telemetry.gd` | 15 event constants; user://telemetry.cfg; 10000-event FIFO cap; rotation renumbers retained events | ✓ VERIFIED | 197 lines; 15 constants defined; `MAX_EVENTS=10000`; `_rotate_oldest()` renumbers retained sections and updates `[meta] event_count` (CR-03 fixed) |
| `src/builder/builder.gd` (apply_avatar_config) | Multi-part mesh: Head/Body/Legs + accessories | ✓ VERIFIED | `apply_avatar_config()` at line 1471; applies skin→Head, body→Body, leg→Legs colours; hand/body accessory node visibility toggling |
| `supabase/migrations/009_avatar.sql` | `ALTER TABLE profiles ADD COLUMN IF NOT EXISTS avatar_json TEXT` | ✓ VERIFIED | 14-line migration; idempotent; covered by existing "Users update own profile" RLS policy |
| `locale/nl.po` | 478 msgids translated; brand terminology: brick/nop/bouwer/kist | ✓ VERIFIED | 479 actual msgid entries; 477 non-empty msgstr (2 intentionally empty per `ui-username-inline_valid-empty-both` decision); brand terms verified: "brick" in msgstrs; "LEGO Groep" appears only in disclaimer context (allowlisted) |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `title_scene.gd` | `DeepLinkHandler` | `invite_token_received.connect` + `consume_pending_token()` | ✓ WIRED | Lines 118-123: race-safe pattern — connect first then consume |
| `title_scene.gd` | `FriendsClient.invite_creation_failed` | `fc.invite_creation_failed.connect(_on_invite_creation_failed)` | ✓ WIRED | Line 593 (CR-05 fixed); `_on_invite_creation_failed` handler at line 666 |
| `ftue_overlay.gd` | `ChestEntity.opened` | `chest.opened.connect(_on_chest_opened)` in `_connect_chest_signals()` | ✓ WIRED | Lines 281-299; timer-backed retry loop capped at 10×0.5s (WR-04 fixed) |
| `ftue_overlay.gd` | `Inventory.item_added` | `Inventory.item_added.connect(_on_item_added)` | ✓ WIRED | Line 253; `Inventory` autoload; filters `def_id == "wood_log"` |
| `ftue_overlay.gd` | `StudGrid.placed` | `stud_grid.placed.connect(_on_stud_placed)` | ✓ WIRED | Lines 255-263; filters `definition.brick_id == "wood_plank"` |
| `ftue_overlay.gd` | `WorldSave.set_world_meta` | Direct call on step completion and on `_show_completion()` | ✓ WIRED | Line 441: `WorldSave.set_world_meta("ftue_complete", var_to_bytes(true))` |
| `main_scene.gd` | `ftue_overlay.tscn` | `world_ready.connect(_maybe_start_ftue, CONNECT_ONE_SHOT)` | ✓ WIRED | Line 482; `_maybe_start_ftue()` checks survival mode + `ftue_complete` null |
| `avatar_creator.gd` | `builder.apply_avatar_config()` | `_preview_builder.apply_avatar_config(cfg)` if method available | ✓ WIRED | Line 416: `apply_avatar_config` method check before calling |
| `avatar_creator.gd` | `FriendsClient.save_avatar()` | Direct call on Done pressed | ✓ WIRED | Line 351 in `_on_done_pressed()` |
| `world_select_screen.gd` | `WorldSave.create_world()` | `_on_create_world_pressed()` → `WorldSave.create_world(world_name, world_seed, _selected_mode)` | ✓ WIRED | Lines 936-944; return value checked (WR-06 fixed) |
| `translations.gd` | `chests.*/items.*` prefix validation | `_VALID_PREFIXES` includes `"chests."` and `"items."` | ✓ WIRED | Line 29 (CR-06 fixed) |
| `onboarding_telemetry.gd` | Autoload registry | `project.godot [autoload] OnboardingTelemetry` | ✓ WIRED | Line 56 in project.godot |
| `deep_link_handler.gd` | Autoload registry | `project.godot [autoload] DeepLinkHandler` | ✓ WIRED | Line 52 in project.godot |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| `title_scene.gd._continue_button` | `username` from `FriendsClient.get_username()` | JWT-validated cached username | Yes (JWT-backed, not static) | ✓ FLOWING |
| `avatar_creator.gd._cfg` | `PRESETS[idx]` or user input | `PRESETS` const array + UI swatch presses | Yes (8 real presets, real UI event handlers) | ✓ FLOWING |
| `world_select_screen._worlds` | `ConfigFile.load(_INDEX_PATH)` | `user://worlds/index.cfg` on disk | Yes (real file reads + index rebuild) | ✓ FLOWING |
| `ftue_overlay._current_step` | Signal callbacks from `ChestEntity.opened`, `Inventory.item_added`, `StudGrid.placed` | Game event signals | Yes (real game signals, not hardcoded) | ✓ FLOWING |
| `onboarding_telemetry._queue` | `log(event_name)` calls from multiple sites | 15 call sites across 4 source files | Yes (all 15 events confirmed wired) | ✓ FLOWING |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase 6 autoloads registered | `grep "DeepLinkHandler\|OnboardingTelemetry" project.godot` | Both present on lines 52, 56 | ✓ PASS |
| Main scene is title_scene.tscn | `grep "run/main_scene" project.godot` | `res://src/ui/title_scene.tscn` | ✓ PASS |
| FTUE no-skip gate | `grep -ic "skip" src/ui/ftue_overlay.gd` | 0 | ✓ PASS |
| Telemetry: 15 events wired | Grep across src/ for `OnboardingTelemetry.log(Onboarding` | All 15 event constants called in source | ✓ PASS |
| NL locale coverage | Python count: non-empty msgstr | 477/479 (2 intentionally empty per decision) | ✓ PASS |
| CR-01 thumbnail .jpg | `grep "thumbnail.jpg" world_select_screen.gd world_save.gd` | `.jpg` in both; stale `.png` comment only in docstring | ✓ PASS |
| CR-02 ui.title.continue key | `grep "ui.title.continue" locale/en.po locale/nl.po` | Present in both (lines 1263 en.po, 1191 nl.po) | ✓ PASS |
| CR-03 rotation renumbers | Grep `_rotate_oldest` impl in `onboarding_telemetry.gd` | Renumbers retained sections + updates `[meta] event_count` | ✓ PASS |
| CR-04 token trailing bits | `_generate_invite_token()` in friends_client.gd | `if bit_count > 0: token += ALPHABET[...]` at line 1263 | ✓ PASS |
| CR-05 invite_creation_failed | `grep "invite_creation_failed" title_scene.gd` | Lines 592-593 and handler at 666 | ✓ PASS |
| CR-06 prefix gate | `grep "_VALID_PREFIXES" translations.gd` | `["ui.", "bricks.", "device.", "toast.", "chests.", "items."]` at line 29 | ✓ PASS |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DOC-01 | 06-01 through 06-11 | DOCS.md §1: First five minutes — title, account, avatar, FTUE, invite-link skip, EN+NL | ✓ SATISFIED | All 4 ROADMAP success criteria verified; DOCS.md §1 updated to "IMPLEMENTED" status; implementation matches spec |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `src/autoload/world_save.gd` | 374 | Stale docstring comment says `thumbnail.png`; actual code uses `.jpg` | ℹ INFO | Documentation only; no functional impact (CR-01 fix correctly applied in executable code) |
| `src/ui/settings_menu.gd` | multiple | `return null` / `return {}` in some helper paths | ℹ INFO | Standard guard returns; verified not rendered as user-visible data |

No TBD, FIXME, or XXX markers found in Phase 6 source files.

---

## Test Coverage

| Test File | Type | Assertions | Pending | Status |
|-----------|------|-----------|---------|--------|
| `tests/unit/test_avatar_config_schema.gd` | Unit | 10 real | 0 | ✓ Activated |
| `tests/unit/test_avatar_preset_validity.gd` | Unit | 7 real | 0 | ✓ Activated |
| `tests/unit/test_ftue_state_machine.gd` | Unit | 9 real | 2 (filesystem-conditional) | ✓ Activated |
| `tests/unit/test_world_thumbnail_capture.gd` | Unit | 4 real | 3 (viewport-gated) | ✓ Activated (intentional pending) |
| `tests/unit/test_deeplink_parser.gd` | Unit | 8 real | 0 | ✓ Active |
| `tests/unit/test_telemetry_rotation.gd` | Unit | 5 real | 0 | ✓ Active |
| `tests/integration/test_first_time_user_e2e.gd` | Integration (data layer) | 9 real | 0 | ✓ Activated |

**Total activated real assertions:** 52 across 7 test files
**Intentional pending:** 5 (all viewport-gated or filesystem-conditional; each documented with reason)

---

## Human Verification Required

### 1. Full FTUE End-to-End on Real Device

**Test:** Launch fresh install (or clear user:// data). Sign up with email+password. Complete avatar creation (select a preset, tap Done). Create a new survival world. Verify the FTUE overlay appears with step 1 ("Open the chest…"). Open the starter chest. Verify step 2 activates ("Try mining the tree…"). Mine a tree voxel. Verify step 3 activates ("Try placing a wooden plank…"). Place a wood_plank from hotbar. Verify completion message "That's it. The world is yours." fades in and overlay dismisses after 3 seconds. Verify the bed is present next to the starter chest.

**Expected:** All 4 FTUE steps advance in order. Arrow indicator updates direction. Night hint appears if WorldClock transitions to DUSK before step 4. No dismiss button visible anywhere.

**Why human:** FtueOverlay requires a live scene tree with WorldClock (DUSK polling in `_process`), ChestEntity in the `chest_entity` group, Inventory autoload with `item_added` signal, and StudGrid with `placed` signal. GUT headless tests exercise the data and logic layer only.

### 2. Invite-Link Joiner Flow on Mobile or Desktop

**Test:** Host creates a session. Host sends invite link (`cubicraftia://invite/TOKEN`). Non-friend clicks the link on a device. If signed out: abbreviated sign-in appears; sign in; redemption proceeds. If signed in: directly redeems. Verify: mutual friendship created, player spawns in host's world next to host, joiner tip toast "This is [Friend]'s world. They have what you need to get started." appears, NO FTUE overlay appears.

**Expected:** Deep-link token parsed, redeemed, friendship created, pending_ftue_complete applied, FTUE skipped.

**Why human:** iOS Universal Links / Android App Links require server-side `.well-known` config and OS-level URL scheme registration. Desktop `--invite=TOKEN` CLI arg requires process launch from a link handler. `_parse_args()` is unit-tested but the OS handoff cannot be simulated headlessly.

### 3. Avatar SubViewport 3D Preview

**Test:** Open avatar creator. Verify the 3D builder preview rotates continuously. Select different skin colour swatches — verify head colour changes. Select body colours — verify body/legs update. Select a hand accessory — verify the correct accessory becomes visible on the builder.

**Expected:** Smooth 0.4 rad/s rotation. All colour and accessory changes reflected in the SubViewport preview.

**Why human:** SubViewport rendering and `MeshInstance3D.material_override` require GPU context. `_apply_config_to_preview` and `apply_avatar_config` are substantive but visual output cannot be confirmed headlessly.

### 4. Dutch Locale In-Game

**Test:** Launch game, go to Settings, switch Language to "Nederlands". Navigate through: title screen, world select, avatar creator, FTUE narration text (if available). Verify all labels display Dutch text, no raw msgid key-strings visible.

**Expected:** 477 translated strings display correctly. Brand terminology: "brick" (not "lego"), "bouwer" (builder), "kist" (chest).

**Why human:** `TranslationServer.set_locale("nl")` requires a running Godot instance with nl.po loaded. Coverage is confirmed by code inspection (477/479 entries non-empty) but live rendering requires a device.

---

## Gaps Summary

No blocking gaps found. All 4 ROADMAP Success Criteria are VERIFIED in the codebase with substantive, wired, data-flowing implementations. All 6 code-review critical fixes (CR-01 through CR-06) confirmed applied. The 4 human verification items are runtime/visual/OS-level checks that cannot be automated headlessly — they do not indicate implementation defects but require physical validation before release.

**Deferred hardware debt from prior phases (not Phase 6 responsibility):**
- Phase 1: Motorola 30-min benchmark CSV
- Phase 2: 4-row UAT (dynamite benchmark, touch gesture, force-quit, cross-platform export)
- Phase 3: 5-row UAT (ghost wall-pass, Tom Yum VFX, force-quit, Motorola combat, sleep lapse feel)

---

_Verified: 2026-05-30T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
