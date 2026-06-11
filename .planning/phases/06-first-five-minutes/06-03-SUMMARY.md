---
phase: 06-first-five-minutes
plan: "03"
subsystem: ui
tags: [title-screen, boot, deep-link, shader, sign-in, telemetry]
requires: [06-01, 06-02]
provides: [title_scene.tscn, title_scene.gd, title_bg_pan.gdshader]
affects: [project.godot, main_scene.gd, sign_in_panel.gd, cubicraftia.tres]
tech-stack:
  added: []
  patterns: [CanvasLayer-as-root, programmatic-UI-build, tween-alpha-in, UV-pan-shader]
key-files:
  created:
    - src/ui/title_scene.gd
    - src/ui/title_scene.tscn
    - src/shaders/title_bg_pan.gdshader
  modified:
    - project.godot
    - src/world/main_scene.gd
    - src/ui/sign_in_panel.gd
    - assets/themes/cubicraftia.tres
decisions:
  - "title_scene.gd builds all UI programmatically in _build_ui() — no child nodes in .tscn, consistent with sign_in_panel.gd pattern"
  - "main_scene._ready() returns early when WorldSave not open to prevent undefined survival-HUD behaviour"
  - "StyleBox_button_continue applied via add_theme_stylebox_override in script (not theme lookup) to avoid polluting global Button style"
metrics:
  duration: "25 min"
  completed: "2026-05-30"
  tasks: 2
  files: 7
---

# Phase 06 Plan 03: Title Screen Summary

**One-liner:** Title screen CanvasLayer with UV-pan brick background shader, 2s logo alpha-in tween, five-button stack, deep-link race-fix, and telemetry; replaces main_scene.tscn as run/main_scene.

## What Was Built

### Task 1 — Boot path redirect + main_scene dev auto-open removal

- `project.godot` `run/main_scene` changed from `res://src/world/main_scene.tscn` to `res://src/ui/title_scene.tscn`. This is the single highest-impact change: all Phase 6 flows now land at the title screen.
- `src/world/main_scene.gd`: removed the `WorldSave.open_world("dev_world_001", ...)` dev shortcut (lines 324-335 as found). Replaced with a `push_warning` + `return` guard so main_scene exits cleanly if loaded without a world already open (prevents undefined survival-HUD behaviour).
- Stale dev-comment block (`# Auto-open a default development world…`) removed.

**Commits:** `e4b9225`

### Task 2 — title_scene.gd/.tscn + UV-pan shader + sign_in_panel back button + StyleBox_button_continue

**`src/shaders/title_bg_pan.gdshader`**
- Canvas-item shader with `uniform vec2 uv_offset`. UV pan at 0.002 UV units/s; offset driven per frame by `title_scene._process(delta)`.

**`src/ui/title_scene.gd`** (TitleScene extends CanvasLayer, layer=0)
- `_ready()` sequence: (1) `OnboardingTelemetry.log(TITLE_SHOWN)`, (2) connect `DeepLinkHandler.invite_token_received` then immediately call `consume_pending_token()` to handle the race where the signal fired before `_ready()` connected, (3) session restore — `_continue_button` shown with username when `FriendsClient.is_signed_in()`, (4) 2s logo alpha-in tween (`TRANS_SINE`, `EASE_IN_OUT`) followed by 0.5s button-stack fade.
- `_process(delta)`: increments `uv_offset` by `Vector2(0.002, 0.0) * delta` on the background ShaderMaterial.
- Button wiring: Continue (signed-in CTA → avatar check → world_select), Sign in, Create account (both open sign_in_panel with `show_back_button=true`), Continue offline (world_select in offline mode), Settings (opens settings_menu.tscn).
- Legal footer: EULA + Privacy flat buttons → open `legal_viewer.tscn`.
- Version label anchored bottom-right.
- AudioStreamPlayer: `volume_db=-6.0`, stream=null (no crash); stream loaded at runtime if `assets/audio/title_loop.ogg` exists.
- `_unhandled_key_input`: `ui_cancel` closes open overlay; on desktop with no overlay open, calls `OS.request_quit()`.
- `_handle_invite_deep_link(token)`: hides content column, shows "Joining…" label, calls `_ensure_signed_in_then_redeem(token)`. Full Surface 6 redeem flow deferred to Plan 06-08.

**`src/ui/title_scene.tscn`**
- Minimal root `CanvasLayer` (layer=0) with script attached. All child nodes built in `_build_ui()`.

**`src/ui/sign_in_panel.gd`** (additive changes only)
- Added `signal back_to_title_requested()`.
- Added `@export var show_back_button: bool = false` — when true, `_ready()` calls `_add_back_button()` which appends a flat "Back to title" button at the bottom of `_vbox`.
- Added `set_create_account_mode(active: bool)` — calls `_on_tab_pressed("create")` to pre-select the create-account tab.

**`assets/themes/cubicraftia.tres`** (additive)
- Added `StyleBox_button_continue`: accent yellow `#F5C30D` fill, no border, rounded 8px, standard content margins. Applied programmatically in `title_scene.gd` for the Continue button.

**Commits:** `89b20d9`

## Deviations from Plan

### Auto-additions (not deviations — improvements)

**1. [Rule 1 - Bug] main_scene early return on WorldSave.is_open() == false**
- **Found during:** Task 1
- **Issue:** The original plan said to replace the dev auto-open with `push_warning`. Without a `return`, main_scene would proceed to initialise survival HUD, hostile spawns, and ThermalProbe wiring with no world open — causing undefined behaviour in every function that touches WorldSave state.
- **Fix:** Added `return` immediately after the `push_warning`. The surrounding `_ready()` structure is unchanged.
- **Files modified:** `src/world/main_scene.gd`
- **Commit:** `e4b9225`

**2. [Rule 2 - Missing critical functionality] Semi-transparent overlay above background TextureRect**
- **Found during:** Task 2 — without a darkening overlay, the brick texture would make the logo and buttons unreadable.
- **Fix:** Added a `ColorRect` (navy 0.72 alpha) between `_bg_rect` and `_content_column` to ensure WCAG-compliant contrast. No behaviour change; purely a readability requirement.
- **Files modified:** `src/ui/title_scene.gd`
- **Commit:** `89b20d9`

**3. [Rule 2 - Missing critical functionality] Background TextureRect fallback**
- The plan specified a brick texture that does not exist yet (`assets/textures/title_bg_bricks.png`). The shader is attached unconditionally; texture load is guarded with `ResourceLoader.exists()` so the scene starts with a plain navy overlay (readable) rather than crashing on a missing resource.

## Known Stubs

| Stub | File | Line (approx) | Reason |
|------|------|----------------|--------|
| `assets/audio/title_loop.ogg` — not present | `title_scene.gd` | _build_ui | Placeholder music deferred post-launch; stream=null guard prevents crash |
| `assets/textures/title_bg_bricks.png` — not present | `title_scene.gd` | _build_ui | Brick texture deferred to art pass; ResourceLoader.exists() guard prevents crash |
| `_ensure_signed_in_then_redeem` — full deep-link redeem flow | `title_scene.gd` | ~291 | Plan 06-08 Surface 6 implements the compact inline sign-in + redeem flow |
| `world_select_screen.tscn` — scene not yet created | `title_scene.gd` | _show_world_select | Plan 06-04 creates this scene; push_warning + stay-on-title fallback in place |
| `avatar_creator.tscn` — scene not yet created | `title_scene.gd` | _show_avatar_creator | Plan 06-05; push_warning + world_select fallback in place |

## Threat Surface Scan

No new network endpoints or auth paths introduced beyond what the plan's threat model already covers. `title_scene.gd` only calls existing autoloads (`FriendsClient`, `DeepLinkHandler`, `OnboardingTelemetry`) at trust boundaries already defined in the plan's STRIDE register.

## Self-Check: PASSED

- `src/ui/title_scene.gd` — FOUND
- `src/ui/title_scene.tscn` — FOUND
- `src/shaders/title_bg_pan.gdshader` — FOUND
- `project.godot` contains `title_scene.tscn` — FOUND
- `e4b9225` (Task 1 commit) — FOUND
- `89b20d9` (Task 2 commit) — FOUND
