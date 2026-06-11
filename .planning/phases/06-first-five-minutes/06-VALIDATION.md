# Phase 6 — Validation Map

> Per-Task Verification Map: how to prove each task is complete, before and after execution.
> Run the automated commands column to verify. Human-verify column indicates manual review steps.

---

## Wave 1 — Foundation

### Plan 06-01: GUT stubs + signal additions + i18n stubs + asset stubs

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-01 T1: ChestEntity.opened + Inventory.item_added signals | `grep -n "signal opened" src/world/chest_entity.gd` — must return result. `grep -n "opened\.emit" src/world/chest_entity.gd` — must return result. `grep -n "signal item_added" src/autoload/inventory.gd` — must return result. `grep -n "item_added\.emit" src/autoload/inventory.gd` — must return result. | Open a chest in-game and verify no errors in Godot debug console. | Both signals declared AND emitted; no other logic changed in either file. |
| 06-01 T2: Test stubs + 44 EN i18n keys + asset stubs | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gprefix=test_avatar -gsuffix=.gd -gexit 2>&1 \| grep -v PENDING` — should return nothing (all PENDING, no ERROR). `grep -c "msgid \"ui\.title\." locale/en.po` — should be >= 6. `ls assets/textures/title/title_bg.png assets/textures/ui/world_thumb_placeholder.png assets/textures/icons/ftue_arrow.png` — all exist. | Verify GUT runs without GDScript parse errors in debug output. | 7 test stub files exist, run without errors, report PENDING; 44 EN keys in locale/en.po; 6 asset stub PNGs exist. |

### Plan 06-02: Supabase migration + DeepLinkHandler + OnboardingTelemetry autoloads

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-02 T1: 009_avatar.sql | `ls supabase/migrations/009_avatar.sql` — exists. `grep "ADD COLUMN IF NOT EXISTS avatar_json TEXT" supabase/migrations/009_avatar.sql` — statement present. `grep -rl "avatar_json" supabase/migrations/ \| grep -v "009" \| wc -l \| grep "^0$"` — no prior migration adds avatar_json. | Apply migration to local Supabase and verify `\d profiles` shows avatar_json column. | Migration file exists; idempotent ADD COLUMN IF NOT EXISTS; no prior migration conflict. |
| 06-02 T2: DeepLinkHandler + OnboardingTelemetry + project.godot | `grep "DeepLinkHandler" project.godot` — registered. `grep "OnboardingTelemetry" project.godot` — registered. `grep -n "get_pending_token" src/autoload/deep_link_handler.gd` — method exists. `grep -n "MAX_EVENTS.*10" src/autoload/onboarding_telemetry.gd` — cap constant. | Open project in Godot editor; verify both autoloads appear in AutoLoad list in correct order (DeepLinkHandler after FriendsClient, OnboardingTelemetry last). | Both autoloads created; registered in correct order; no GDScript parse errors. |

---

## Wave 2 — Core Systems

### Plan 06-03: Title Screen

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-03 T1: main_scene dev-path removal + project.godot run/main_scene | `grep "dev_world_001" src/world/main_scene.gd \| wc -l \| grep "^0$" && echo OK` — must print OK. `grep "run/main_scene" project.godot \| grep "title_scene"` — must match. | Launch the game; verify it opens to title screen (not main_scene directly). | "dev_world_001" absent; push_warning defensive guard in place; project.godot points to title_scene. |
| 06-03 T2: title_scene.gd/.tscn + UV-pan shader + sign_in_panel back button | `ls src/ui/title_scene.gd src/ui/title_scene.tscn src/shaders/title_bg_pan.gdshader` — all exist. `grep "consume_pending_token\|get_pending_token" src/ui/title_scene.gd` — race-fix present. `grep "show_back_button" src/ui/sign_in_panel.gd` — property exists. `grep "OnboardingTelemetry.log.*title_shown" src/ui/title_scene.gd` — telemetry call. | Launch game: verify 2-second logo fade-in; verify all 5 buttons visible; tap "Settings" — opens settings menu; tap "Terms of Use" — opens legal viewer; verify UV-pan background animates. | title_scene.tscn is run/main_scene; logo fades in 2s; all buttons wired; deep-link race-fix present; UV-pan shader active. |

### Plan 06-04: Avatar Creator

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-04 T1: FriendsClient.save_avatar() | `grep -n "save_avatar" src/autoload/friends_client.gd` — method exists. `grep -n "_avatar_req" src/autoload/friends_client.gd` — node declared and added. | Sign in, go through avatar creator, tap Done, verify no network errors in Godot debug output. | save_avatar() exists; _avatar_req added in _ready(); fire-and-forget guard (drops if in-flight). |
| 06-04 T2: avatar_creator.gd/.tscn + 8 presets | `ls src/ui/avatar_creator.gd src/ui/avatar_creator.tscn` — both exist. `grep -c "signal avatar_complete" src/ui/avatar_creator.gd` — exactly 1. `grep "FriendsClient.save_avatar" src/ui/avatar_creator.gd` — called in _on_done_pressed. `ls assets/textures/ui/avatar_presets/preset_8.png` — exists. | Navigate to avatar creator: verify 5 part sections visible; tap each preset tile — all 8 apply changes; tap Randomise — combination changes; tap Done — returns to title/world-select; open user://avatar.cfg — contains [avatar] section with 8 keys. | avatar_creator.gd/.tscn created; 8 presets defined; Done writes avatar.cfg and calls save_avatar(); SubViewport preview rotates. |

### Plan 06-05: World Select Screen

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-05 T1: WorldSave.capture_thumbnail() + StyleBoxes | `grep -n "capture_thumbnail" src/autoload/world_save.gd` — method exists. `grep -n "call_deferred.*capture_thumbnail" src/autoload/world_save.gd` — deferred call. `grep -c "StyleBox_world_card\|StyleBox_mode_badge" assets/themes/cubicraftia.tres` — count > 0. | Save a world, then check user://worlds/{world_id}/thumbnail.png exists and is a valid JPEG. | capture_thumbnail() method; deferred call from save_world(); 3 StyleBoxes in theme. |
| 06-05 T2: world_select_screen.gd/.tscn | `ls src/ui/world_select_screen.gd src/ui/world_select_screen.tscn` — both exist. `grep "dir_exists_absolute.*worlds" src/ui/world_select_screen.gd` — null-guard. `grep "filter_reject" src/ui/world_select_screen.gd` — profanity check. `grep "standalone_mode" src/ui/friends_panel.gd` — property added. | Navigate to world select: verify empty state shown on first launch; create a world — card appears; right-click card — context menu with 4 items; tap Delete — confirmation modal; tap Friends — opens friends panel. | world_select_screen created; empty state handled; new world modal validates; context menu wired; 5-world cap enforced; Friends panel opens in standalone_mode. |

---

## Wave 3 — FTUE + Avatar In-World

### Plan 06-06: FTUE Overlay

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-06 T1: brick_palette._set_ftue_highlight() + main_scene FTUE hook | `grep -n "_set_ftue_highlight" src/ui/brick_palette.gd` — method exists. `grep -n "ftue_overlay\|_maybe_start_ftue" src/world/main_scene.gd` — FTUE instantiation present. | Create a new survival world; verify FTUE overlay appears (not on creative world). | brick_palette method exists; main_scene instantiates FTUE after world_ready in survival mode only. |
| 06-06 T2: ftue_overlay.gd/.tscn — 4-step state machine | `ls src/ui/ftue_overlay.gd src/ui/ftue_overlay.tscn` — both exist. `grep "STEP_COUNT.*4" src/ui/ftue_overlay.gd`. `grep "definition.brick_id.*wood_plank\|wood_plank.*brick_id" src/ui/ftue_overlay.gd` — step 3 filter correct. `grep -ic "skip" src/ui/ftue_overlay.gd \| grep "^0$" && echo "No skip"` — no skip button. `grep "set_world_meta.*ftue_complete" src/ui/ftue_overlay.gd` — completion written. | New survival world: verify step 1 text visible; open chest — step advances; mine a tree (get wood_log) — step advances; place wood_plank — step advances; "That's it" message appears for 3s then overlay fades out. Check WorldSave ftue_complete is written. | 4-step FTUE; steps advance on correct signals; no skip button; completion persisted; OnboardingTelemetry events fired. |

### Plan 06-07: Builder Avatar Rendering

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-07 T1: Builder.apply_avatar_config + mesh nodes | `grep -n "func apply_avatar_config" src/builder/builder.gd` — method exists. `grep -n "func load_avatar_from_file" src/builder/builder.gd` — method exists. `grep -n "SKIN_COLOURS\|BODY_COLOURS" src/builder/builder.gd` — constants present. `grep "clampi\|clamp" src/builder/builder.gd` — bounds checking. | Set avatar body colour to orange in creator; enter a world; verify builder has orange body colour. Set different preset; verify builder in SubViewport preview reflects the change. | apply_avatar_config() exists; multi-part mesh nodes (Head/Body/Legs/HandItem); load_avatar_from_file() in _ready(); index bounds clamped. |

---

## Wave 4 — Invite Flow + Telemetry

### Plan 06-08: Deep-Link Handler + Telemetry Wiring

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-08 T1: _handle_invite_deep_link + set_abbreviated_mode + ftue.cfg marker | `grep -n "_handle_invite_deep_link\|_redeem_invite_and_join" src/ui/title_scene.gd` — both methods. `grep -n "joined_via_invite\|pending_ftue_complete" src/ui/title_scene.gd` — both markers. `grep -n "set_abbreviated_mode" src/ui/sign_in_panel.gd` — method exists. | Test invite flow on desktop: launch with `--invite=VALIDTOKEN00000000000`; verify title UI hidden; verify compact sign-in prompt appears (if not signed in). | _handle_invite_deep_link() fully implemented; ftue_complete pre-set; user://ftue.cfg marker written; abbreviated mode hides tab bar in sign_in_panel. |
| 06-08 T2: All 15 telemetry event log points | `grep -rn "OnboardingTelemetry.log" src/ui/ src/world/main_scene.gd \| grep -oP '"[^"]+"' \| sort \| uniq` — list all unique event names. Cross-check against the 15-event list in 06-CONTEXT.md Area 6. | Play through the full first-time flow; check user://telemetry.cfg after each step; verify events appear in order. | All 15 event names from 06-CONTEXT.md Area 6 present in code; no duplicate firing on a single user path; telemetry.cfg written after 60s or on app close. |

### Plan 06-09: Telemetry Implementation + Test Activation

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-09 T1: Full telemetry implementation + tests | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gprefix=test_telemetry -gsuffix=.gd -gexit 2>&1 \| grep -E "(PASS|FAIL)"` — only PASS. `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gprefix=test_deeplink -gsuffix=.gd -gexit 2>&1 \| grep -E "(PASS|FAIL)"` — only PASS. `grep "_parse_args" src/autoload/deep_link_handler.gd` — testable helper. | Manually verify user://telemetry.cfg is written with correct schema after 60s of gameplay. | test_telemetry_rotation.gd PASS; test_deeplink_parser.gd PASS; _flush_to_disk() + _rotate_oldest() fully implemented; _parse_args() extracted. |

---

## Wave 5 — Localisation + Final Gate

### Plan 06-10: Dutch Localisation + Locale Switcher

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-10 T1: locale/nl.po + locale/en.po stubs filled + project.godot | `grep -c "^msgid" locale/nl.po` — should be >= 625. `grep "^msgstr \"\"" locale/nl.po \| wc -l \| awk '{if ($1 <= 1) print "OK"; else print "FAIL: " $1 " empty strings"}'`. `grep "nl\.po" project.godot` — registered. `grep "ui\.ftue\.step_3" locale/nl.po` — NL translation present (non-empty). | Switch to Dutch in settings; verify all Phase 6 screens show Dutch text; verify no visible tr() keys leaking through (strings showing "ui.ftue.step_1" instead of translated text). | nl.po: all ~669 msgids have NL translations (max 1 empty); en.po Phase 6 stubs filled; nl.po registered in project.godot. |
| 06-10 T2: settings_menu locale picker | `grep -n "set_locale\|_save_locale_pref\|NOTIFICATION_TRANSLATION_CHANGED" src/ui/settings_menu.gd` — all 3 present. `grep "ui.settings.language_label" locale/en.po locale/nl.po` — key in both files. | Open settings; verify Language section appears before Legal; tap "Nederlands" — all visible strings immediately switch to Dutch; relaunch app — Dutch persists. | Language section in settings; EN/NL buttons wired; locale pref saved to user://settings.cfg; NOTIFICATION_TRANSLATION_CHANGED propagated for immediate update. |

### Plan 06-11: Test Activation + DOCS Sync

| Task | Automated Verification | Human Verify | Done Criteria |
|------|----------------------|--------------|---------------|
| 06-11 T1: Activate remaining test stubs | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gprefix=test_ -gsuffix=.gd -gexit 2>&1 \| grep -E "FAIL\|ERROR"` — must return nothing (no failures). `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -ginclude_subdirs -gexit 2>&1 \| grep -E "FAIL\|ERROR"` — full suite green. | Review GUT output summary; confirm all test files show PASS or PENDING (viewport-only tests are acceptable PENDING). | All unit tests PASS; integration data-layer PASS; no FAIL or ERROR; test_world_thumbnail_capture may be PENDING. |
| 06-11 T2: DOCS.md §1 sync + PRIVACY.md | `grep "That's it. The world is yours" .planning/DOCS.md` — completion text present. `grep "telemetry\|event log" docs/PRIVACY.md` — telemetry section added. `grep "11 plans\|06-11-PLAN" .planning/ROADMAP.md` — ROADMAP updated. `grep -ic "skip" src/ui/ftue_overlay.gd \| grep "^0$" && echo "No skip button"` — final FTUE integrity check. | Read DOCS.md §1.1-§1.4 end-to-end; verify every sentence describes what was actually built. Spot-check 3-4 statements against the code. | DOCS.md §1 = true description of shipped code; PRIVACY.md has telemetry enumeration; ROADMAP.md shows 11 plans; no skip button in FTUE (final check). |

---

## Phase-Level Success Criteria Checklist

```
[ ] project.godot run/main_scene = "res://src/ui/title_scene.tscn"
[ ] "dev_world_001" absent from src/world/main_scene.gd
[ ] supabase/migrations/009_avatar.sql exists with ADD COLUMN IF NOT EXISTS avatar_json TEXT
[ ] DeepLinkHandler registered in project.godot after FriendsClient
[ ] OnboardingTelemetry registered in project.godot last
[ ] title_scene: logo alpha-in 2s; all 5 buttons; legal footer; session restore
[ ] avatar_creator: 5 parts; 8 presets; Done writes user://avatar.cfg + calls save_avatar()
[ ] world_select_screen: world cards; new world modal; 5-world cap; context menu; friends overlay
[ ] ftue_overlay: 4 steps; no skip button; step 3 filters definition.brick_id; ftue_complete persisted
[ ] builder.gd: apply_avatar_config() + load_avatar_from_file()
[ ] deep-link flow: signed-in fast-path + unsigned compact sign-in; ftue_complete pre-set; toast
[ ] locale/nl.po: all ~669 msgids translated; registered in project.godot
[ ] All 15 telemetry events present at correct call sites
[ ] All Phase 6 GUT unit tests PASS (test_world_thumbnail_capture may be PENDING)
[ ] Full GUT suite green (no Phase 1-5 regressions)
[ ] DOCS.md §1.1-§1.4 = true description of shipped implementation
[ ] docs/PRIVACY.md has local telemetry event log enumeration
[ ] ROADMAP.md Phase 6: "11 plans across 5 waves" with plan list
```

---

## Regression Risk Map

| Change | Files Affected | Regression Risk | Mitigation |
|--------|---------------|-----------------|------------|
| project.godot run/main_scene changed | All tests that rely on main_scene auto-opening | HIGH | Any test that called WorldSave.open_world("dev_world_001") internally must now call open_world() explicitly — update any affected tests in Plan 06-11 |
| main_scene.gd dev-path removed | Any test importing main_scene.tscn that expected auto-open | MEDIUM | Tests that instantiate main_scene must call WorldSave.open_world() first |
| Inventory.item_added signal added | All tests that mock Inventory.inventory_changed | LOW | New signal is additive; existing signal still fires; no existing test breaks |
| ChestEntity.opened signal added | All tests that mock ChestEntity | LOW | New signal is additive; existing signals (unlocked, broken) still fire |
| friends_panel.gd standalone_mode property | Phase 4 tests that open friends_panel | LOW | Default is false; existing tests unaffected |
| sign_in_panel.gd show_back_button + set_abbreviated_mode | Phase 5 tests that open sign_in_panel | LOW | Both default to false/off; existing sign_in_panel tests unaffected |
