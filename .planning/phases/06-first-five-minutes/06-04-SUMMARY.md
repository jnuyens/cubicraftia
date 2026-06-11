---
phase: 06
plan: 04
subsystem: ui
tags: [avatar, customiser, subviewport, presets, friends-client]
dependency_graph:
  requires: [06-01, 06-02]
  provides: [avatar_creator, FriendsClient.save_avatar]
  affects: [title_scene (avatar_complete wiring), builder (06-07 will add apply_avatar_config)]
tech_stack:
  added: []
  patterns: [CanvasLayer layer=10, SubViewport UPDATE_WHEN_VISIBLE, ConfigFile user:// persistence, HTTPRequest fire-and-forget]
key_files:
  created:
    - src/ui/avatar_creator.gd
    - src/ui/avatar_creator.tscn
  modified:
    - src/autoload/friends_client.gd
decisions:
  - "Pre-06-07 compat: preview builder manipulates MeshInstance3D albedo_color directly; Plan 06-07 upgrades to Builder.apply_avatar_config()"
  - "Avatar config uses 8-key dict matching 06-CONTEXT.md Area 2 schema"
  - "Preset tile buttons in GridContainer 4-col layout; no dynamic instantiation per UI-SPEC perf constraint"
  - "FriendsClient._avatar_req uses _authed_headers_minimal() (no row returned needed for fire-and-forget)"
metrics:
  duration: ~20 minutes
  completed: "2026-05-30"
  tasks: 2
  files: 3
---

# Phase 06 Plan 04: Avatar Creator Summary

**One-liner:** 5-part avatar customiser with 8 diverse presets, Randomise, 256×256 SubViewport 3D preview, ConfigFile + Supabase persistence via FriendsClient.save_avatar().

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | FriendsClient.save_avatar() + _avatar_req | 33f71ee | src/autoload/friends_client.gd |
| 2 | avatar_creator.gd/.tscn + 8 preset configs | 54ba1f2 | src/ui/avatar_creator.gd, src/ui/avatar_creator.tscn |

## What Was Built

### Task 1 — FriendsClient.save_avatar()

Added to `src/autoload/friends_client.gd`:
- `var _avatar_req: HTTPRequest = null` — declared alongside existing per-concern nodes
- `_avatar_req` instantiated and `add_child()`'d in `_ready()` (no response handler connected — fire-and-forget)
- `func save_avatar(cfg: Dictionary) -> void` — guards on `is_signed_in()` and `_is_req_ready(_avatar_req)`, builds JSON body, PATCHes `/rest/v1/profiles?id=eq.<uid>` with `{"avatar_json": JSON.stringify(cfg)}` using `_authed_headers_minimal()`

### Task 2 — avatar_creator.gd / .tscn

`src/ui/avatar_creator.gd` (extends CanvasLayer):
- **Signals:** `avatar_complete`, `avatar_cancelled`
- **Constants:** `SKIN_COLOURS` (5), `BODY_COLOURS` (10), `HEAD_SHAPES` (3), `FACE_EXPRESSIONS` (5), `BODY_ACCESSORIES` (3), `LEG_SHOES` (3), `HAND_ACCESSORIES` (5), `PRESETS` (8 diverse configs)
- **8 presets:** Classic, Explorer, Knight, Ninja, Astronaut, Rainbow, Pirate, Winter — skin tones 0/1/2/3/4/0/1/2 (all 5 tones covered)
- **_ready():** loads `user://avatar.cfg` if present; wires all swatch/button signals; refreshes UI + preview
- **_process(delta):** rotates SubViewport builder at 0.4 rad/s
- **_on_done_pressed():** writes all 8 keys to `user://avatar.cfg`, calls `FriendsClient.save_avatar(_cfg)`, logs `AVATAR_COMPLETE` telemetry, emits `avatar_complete`
- **_on_back_pressed():** emits `avatar_cancelled` (no save)
- **_on_preset_pressed(idx):** duplicates preset dict, updates UI + preview, writes cfg to disk immediately
- **_on_randomise_pressed():** generates random valid cfg from all enum ranges
- **_apply_config_to_preview():** uses `Builder.apply_avatar_config()` if available (06-07+), else sets albedo_color on named MeshInstance3D children "Body", "Legs", "Head"
- **Telemetry:** `AVATAR_PICKER_SHOWN` on `_ready()`, `AVATAR_COMPLETE` on Done

`src/ui/avatar_creator.tscn` (CanvasLayer layer=10):
- PanelContainer 560px wide (16px content margins)
- HBoxMain: left VBoxParts (all 5 sections) + right VBoxPreview (SubViewportContainer 256×256)
- PresetGrid (GridContainer 4 cols, 8 Button tiles 72×72px) + RandomiseButton
- All section labels use `tr("ui.avatar.*")` i18n keys
- SubViewport: `update_mode = 1` (UPDATE_WHEN_VISIBLE), contains WorldEnvironment + DirectionalLight3D + Camera3D + BuilderPreview MeshInstance3D (CapsuleMesh stub)
- Footer: DoneButton (expand fill) + BackButton (120px)

## Deviations from Plan

### Auto-applied — Pre-existing preset PNGs

The 8 preset stub PNGs in `assets/textures/ui/avatar_presets/` already existed from a prior plan execution. No action needed — the files were present and valid.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| CapsuleMesh builder preview | avatar_creator.tscn (BuilderPreview) | Plan 06-07 will add `Builder.apply_avatar_config()` and wire the real `builder.tscn` mesh; the capsule is a geometric stand-in |
| Swatch button colours via `modulate` | avatar_creator.tscn | Colour buttons use `modulate` tint on default Button style rather than a custom ColorRect; functional for v1, visual polish deferred |

## Threat Surface Scan

No new network endpoints introduced (FriendsClient._avatar_req uses the existing Supabase REST pattern). Avatar config keys are integer indices and fixed string enum values — no PII (T-06-I1 mitigated as designed). No new trust boundaries.

## Self-Check: PASSED

- [x] `src/ui/avatar_creator.gd` exists
- [x] `src/ui/avatar_creator.tscn` exists
- [x] `src/autoload/friends_client.gd` modified
- [x] Commit 33f71ee exists (FriendsClient.save_avatar)
- [x] Commit 54ba1f2 exists (avatar_creator.gd/.tscn)
- [x] `signal avatar_complete` present in avatar_creator.gd
- [x] `signal avatar_cancelled` present in avatar_creator.gd
- [x] `PRESETS` constant with 8 entries present
- [x] `FriendsClient.save_avatar` called in `_on_done_pressed`
- [x] `OnboardingTelemetry.log(AVATAR_PICKER_SHOWN)` in `_ready()`
- [x] `OnboardingTelemetry.log(AVATAR_COMPLETE)` in `_on_done_pressed()`
- [x] All 8 preset PNG stubs present at `assets/textures/ui/avatar_presets/preset_{1..8}.png`
- [x] All UI strings use `tr("ui.avatar.*")` key format
