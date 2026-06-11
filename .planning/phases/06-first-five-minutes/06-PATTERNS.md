# Phase 6 — Patterns Map

> Every new file introduced in Phase 6 and its closest analog from Phases 1–5.
> Executors: use these analogs to understand expected structure before writing new files.

---

## New Autoloads

| New File | Closest Analog | Key Differences |
|----------|---------------|-----------------|
| `src/autoload/deep_link_handler.gd` | `src/autoload/features.gd` | Reads OS.get_command_line_args() instead of ProjectSettings; emits a signal; has a `_handled` guard |
| `src/autoload/onboarding_telemetry.gd` | `src/autoload/world_save.gd` (ConfigFile pattern) | Append-only write pattern; 60s flush timer; 10k-event cap rotation |

---

## New UI Scenes

| New File | Closest Analog | Key Differences |
|----------|---------------|-----------------|
| `src/ui/title_scene.gd` | `src/ui/boot.gd` | Full signal-based routing; deep-link intercept; session restore; UV-pan shader |
| `src/ui/title_scene.tscn` | `src/ui/settings_menu.tscn` | CanvasLayer(0) root; TextureRect background with ShaderMaterial; VBoxContainer button stack |
| `src/ui/avatar_creator.gd` | `src/ui/inventory_slide_in.gd` | Full-screen panel with HBoxContainer (customiser + SubViewport preview); 8 presets + Randomise |
| `src/ui/avatar_creator.tscn` | `src/ui/inventory_slide_in_sidebar.tscn` | CanvasLayer(10) root; SubViewportContainer instead of TabBar |
| `src/ui/world_select_screen.gd` | `src/ui/friends_panel.gd` | CanvasLayer(0) root; dynamic world card list from ConfigFile; inline modal (new world) |
| `src/ui/world_select_screen.tscn` | `src/ui/friends_panel.tscn` | PanelContainer centred with ScrollContainer for world cards |
| `src/ui/ftue_overlay.gd` | `src/ui/network_hud.gd` | CanvasLayer(20) non-blocking overlay; 4-step state machine; Tween-based arrow bounce; queue_free on completion |
| `src/ui/ftue_overlay.tscn` | `src/ui/hp_bar.tscn` | CanvasLayer(20) with mouse_filter=IGNORE on root; ProgressBar + Label + arrow TextureRect |

---

## New Shader

| New File | Closest Analog | Key Differences |
|----------|---------------|-----------------|
| `src/shaders/title_bg_pan.gdshader` | Phase 2 sky shader (if exists) | canvas_item type; single UV offset uniform; updated from GDScript _process() |

---

## Modified Existing Files

| Modified File | Plan | Change Type | Change Summary |
|--------------|------|-------------|----------------|
| `src/world/chest_entity.gd` | 06-01 | Signal addition | `signal opened()` + `opened.emit()` in _open_panel() |
| `src/autoload/inventory.gd` | 06-01 | Signal addition | `signal item_added(builder_id, def_id, count)` + emit in _apply_add() |
| `src/world/main_scene.gd` | 06-03, 06-06 | Dev-path removal + FTUE hook | Remove auto-open "dev_world_001"; add _maybe_start_ftue() after world_ready |
| `project.godot` | 06-02, 06-03 | run/main_scene + autoloads | title_scene.tscn as main_scene; DeepLinkHandler + OnboardingTelemetry in autoloads |
| `src/autoload/friends_client.gd` | 06-04 | Method addition | `save_avatar(cfg: Dictionary)` fire-and-forget PATCH to profiles.avatar_json |
| `src/autoload/world_save.gd` | 06-05 | Method addition | `capture_thumbnail(world_id)` — deferred JPEG screenshot |
| `src/ui/sign_in_panel.gd` | 06-03, 06-08 | Property + method additions | `show_back_button: bool`, `back_to_title_requested` signal, `set_abbreviated_mode(bool)` |
| `src/ui/friends_panel.gd` | 06-05 | Property addition | `standalone_mode: bool` — hides in-session admin controls |
| `src/ui/brick_palette.gd` | 06-06 | Method addition | `_set_ftue_highlight(def_id, enabled)` — pulsing border on palette slot |
| `src/builder/builder.gd` | 06-07 | Method + node setup | `apply_avatar_config(cfg)`, `load_avatar_from_file()`, `_setup_avatar_mesh_nodes()` |
| `src/builder/builder.tscn` | 06-07 | Child nodes | AvatarMesh Node3D with Head/Body/Legs/HandItem MeshInstance3D children |
| `assets/themes/cubicraftia.tres` | 06-03, 06-05 | StyleBox additions | StyleBox_button_continue, StyleBox_world_card, StyleBox_mode_badge_creative, StyleBox_mode_badge_survival |
| `src/ui/settings_menu.gd` | 06-10 | Section addition | Language picker: EN/NL buttons, TranslationServer.set_locale(), locale pref in user://settings.cfg |
| `locale/en.po` | 06-01, 06-10 | 44 new msgid entries | Phase 6 keys as empty stubs (06-01), filled with EN copy (06-10) |
| `locale/nl.po` | 06-10 | Full Dutch translation | All ~669 msgids translated (previously 0 translations) |
| `.planning/DOCS.md` | 06-11 | §1 DDD sync | §1.1-§1.4 updated to be a true description of shipped implementation |
| `docs/PRIVACY.md` | 06-11 | Telemetry enumeration | Local telemetry event log section added |
| `.planning/ROADMAP.md` | — | Phase 6 plan list | Updated from "Plans: TBD" to "Plans: 11 plans across 5 waves" |

---

## New Database Migration

| File | Analogs | Notes |
|------|---------|-------|
| `supabase/migrations/009_avatar.sql` | `supabase/migrations/003_profiles.sql` | ADD COLUMN IF NOT EXISTS avatar_json TEXT to profiles table |

---

## New Test Files

| Test File | Plan | Analogous Phase Test | What It Tests |
|-----------|------|---------------------|---------------|
| `tests/conftest_phase6.gd` | 06-01 | `tests/conftest.gd` (Phase 3) | Shared fixtures: make_avatar_cfg(), make_telemetry_cfg_path(), make_world_index_path() |
| `tests/unit/test_avatar_config_schema.gd` | 06-01, 06-11 | `tests/unit/test_inventory_schema.gd` (Phase 3) | Avatar cfg round-trip, required keys, valid ranges |
| `tests/unit/test_avatar_preset_validity.gd` | 06-01, 06-11 | N/A | 8 presets distinct, all keys present, diversity check |
| `tests/unit/test_ftue_state_machine.gd` | 06-01, 06-11 | `tests/unit/test_failover_state_machine.gd` (Phase 4) | FTUE step 1/2/3/4 signal gating; step 4 persistence |
| `tests/unit/test_deeplink_parser.gd` | 06-01, 06-09 | `tests/unit/test_profanity_filter.gd` (Phase 5) | Token parsing from --invite= and --uri= args |
| `tests/unit/test_telemetry_rotation.gd` | 06-01, 06-09 | `tests/unit/test_world_save.gd` (Phase 2) | Append, cap rotation, no-PII check |
| `tests/unit/test_world_thumbnail_capture.gd` | 06-01, 06-11 | N/A | WorldSave.capture_thumbnail() file creation (partially PENDING) |
| `tests/integration/test_first_time_user_e2e.gd` | 06-01, 06-11 | `tests/integration/test_failover_e2e.gd` (Phase 4) | World create → FTUE steps → ftue_complete written |

---

## New Asset Files

| Asset | Size/Type | Plan | Usage |
|-------|-----------|------|-------|
| `assets/textures/title/title_bg.png` | 1920×1080 tileable PNG (stub) | 06-01 | Title screen background TextureRect; UV-pan shader input |
| `assets/textures/ui/world_thumb_placeholder.png` | 256×144 PNG (stub) | 06-01 | World card fallback thumbnail |
| `assets/textures/icons/ftue_arrow.png` | 24×24 PNG (stub) | 06-01 | FTUE overlay directional arrow TextureRect |
| `assets/textures/icons/icon_plus.png` | 16×16 PNG (stub) | 06-01 | "New world" button icon |
| `assets/textures/icons/icon_arrow_down.png` | 32×32 PNG (stub) | 06-01 | Empty state downward arrow |
| `assets/textures/icons/icon_dice.png` | 16×16 PNG (stub) | 06-01 | Avatar creator "Randomise" button icon |
| `assets/textures/ui/avatar_presets/preset_{1..8}.png` | 64×64 PNG (stubs) | 06-04 | Avatar preset tile images |

All stub PNGs are 1×1 transparent placeholders. Artist replacement assets drop in at the same paths.

---

## CanvasLayer Layering (Cumulative)

| Layer | Scene(s) | Phase Introduced |
|-------|----------|-----------------|
| 0 | title_scene.tscn, world_select_screen.tscn | Phase 6 |
| 5 | chat_overlay.tscn, restricted_account_banner | Phase 4, 5 |
| 10 | sign_in_panel.tscn, avatar_creator.tscn, settings_menu.tscn, friends_panel.tscn, legal_viewer.tscn | Phases 4-6 |
| 15 | legal_viewer (when opened from title) | Phase 5 |
| 20 | ftue_overlay.tscn, block/report modals, parental_gate_panel | Phase 5-6 |
| 25 | context_menu.gd (singleton) | Phase 5 |
| 100 | handover_screen.tscn | Phase 4 |
| 128 | In-world loading overlay | Phase 1 |

---

## Signal Additions (Wave 0 — Plan 06-01)

These two signals are the critical Wave 0 dependencies. Every plan that references FTUE step completion depends on them.

| Signal | File | Emit Location | FTUE Step |
|--------|------|---------------|-----------|
| `ChestEntity.opened()` | `src/world/chest_entity.gd` | `_open_panel()` before panel instantiation | Step 1 |
| `Inventory.item_added(builder_id, def_id, count)` | `src/autoload/inventory.gd` | `_apply_add()` after slot update | Step 2 |

**StudGrid.placed** already existed (verified at stud_grid.gd line 87) but uses BrickDefinition object, not def_id String. FTUE filters by `definition.brick_id == "wood_plank"`.

---

## Critical Implementation Constraints

| Constraint | Source | Consequence if Violated |
|-----------|--------|------------------------|
| No "Skip" button in FTUE | DOCS §1.4 (locked) | Phase fails DDD gate |
| Migration must be 009_avatar.sql (not 006) | RESEARCH.md Pitfall 1 | Silent migration skip; avatar_json column absent |
| main_scene.gd dev auto-open path MUST be removed | CONTEXT.md specifics | App loops back to main_scene on launch instead of showing title |
| StudGrid.placed uses BrickDefinition not def_id String | RESEARCH.md Pitfall 2 | FTUE step 3 never completes |
| FTUE only runs in survival mode | CONTEXT.md Area 3 | sandbox worlds have no starter chest at predictable location |
| DeepLinkHandler: get_pending_token() race-fix needed | 06-UI-SPEC Recommendation 6 | Invite links miss their token if signal fires before title_scene connects |
