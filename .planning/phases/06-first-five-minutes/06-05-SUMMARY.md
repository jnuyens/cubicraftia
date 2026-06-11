---
phase: 06-first-five-minutes
plan: "05"
subsystem: ui
tags: [world-select, world-cards, thumbnail, new-world-modal, context-menu, friends-panel]
dependency_graph:
  requires: [06-01, 06-02]
  provides: [world_select_screen, WorldSave.capture_thumbnail, WorldSave.save_world]
  affects: [title_scene, friends_panel, world_save, onboarding_telemetry]
tech_stack:
  added: []
  patterns:
    - "world index persistence via user://worlds/index.cfg ConfigFile"
    - "soft-delete world dirs to user://worlds/_deleted/"
    - "deferred thumbnail capture via call_deferred after checkpoint"
    - "long-press (500ms) + right-click context menu on world cards"
    - "inline new-world modal (Surface 4) embedded in world_select_screen"
key_files:
  created:
    - src/ui/world_select_screen.gd
    - src/ui/world_select_screen.tscn
  modified:
    - src/autoload/world_save.gd
    - assets/themes/cubicraftia.tres
    - src/ui/friends_panel.gd
decisions:
  - "save_world() wrapper added to world_save.gd — callers use save_world() for periodic saves so thumbnails stay current; raw checkpoint() remains for internal use"
  - "capture_thumbnail() uses call_deferred to ensure viewport image is from a fully rendered frame"
  - "world index is a ConfigFile at user://worlds/index.cfg; each section is a world_id with name/seed/mode/created_unix/last_played_unix"
  - "Delete is a soft-delete: world dir moved to user://worlds/_deleted/{world_id} — recoverable manually"
  - "friends_panel opened with standalone_mode=true from world_select so admin controls (kick/freeze/rollback) are hidden outside a session"
  - "ContextMenu autoload fallback: if /root/ContextMenu is not wired, _show_fallback_context_menu() is called (confirms delete inline)"
metrics:
  duration: "~25 minutes"
  completed: "2026-05-30"
  tasks_completed: 2
  files_changed: 5
---

# Phase 6 Plan 05: World Select Screen + New World Modal + Thumbnail Capture Summary

WorldSelectScreen (Surface 3 + 4) with scrollable world cards, new-world modal, context menu, friends integration, and deferred thumbnail capture added to WorldSave.

## What Was Built

### Task 1: WorldSave.capture_thumbnail() + 3 StyleBoxes (commit 76906cd)

- `save_world()` wrapper added to `world_save.gd`: calls `checkpoint()`, then `call_deferred("capture_thumbnail", world_id)` so thumbnails are always current.
- `capture_thumbnail(world_id)`: `RenderingServer.force_draw(false)` → `get_viewport().get_texture().get_image()` → `resize(256, 144)` → `img.save_jpg(...)` at 0.85 quality. Gracefully no-ops in headless/unit-test environments (null/empty image check).
- 3 new StyleBoxes added to `assets/themes/cubicraftia.tres`:
  - `StyleBox_world_card`: navy 85% alpha, 1px subtle brick-white rim, 12px corners
  - `StyleBox_mode_badge_creative`: online green #3DB560, 12px corners, compact margin
  - `StyleBox_mode_badge_survival`: relay amber #E8890C, 12px corners, compact margin

### Task 2: world_select_screen.gd / .tscn + friends_panel standalone_mode (commit 06d440f)

**WorldSelectScreen (CanvasLayer layer=0):**
- Background: same title_bg shader as title_scene for visual continuity
- Header: "Your Worlds" title + Friends button (hidden offline) + Settings button
- "New World" CTA button: disabled with `worlds_cap_error` tooltip at 5-world cap
- ScrollContainer with VBoxContainer for up to 5 world cards
- Empty state: heading + body + visible when no worlds directory or index.cfg is empty

**World cards:**
- Thumbnail: 128×72px display (loaded from `user://worlds/{id}/thumbnail.png`, falls back to `assets/textures/ui/world_thumb_placeholder.png`)
- World name: 16px semibold, truncated at 24 chars with ellipsis
- Last-played relative time: "Today" / "Yesterday" / "{n} days ago" via Time.get_unix_time_from_system()
- Mode badge: Creative (green) or Survival (amber) with correct StyleBoxFlat
- Play button (80×40px) → WorldSave.open_world() → change_scene_to_file main_scene.tscn
- Hover effect: 0.22s background colour tween on mouse_entered/mouse_exited
- Long-press (500ms) / right-click: shows context menu with Rename / Duplicate / Export / Delete

**Context menu actions:**
- Rename: AcceptDialog with LineEdit, profanity-validated via WorldSave.rename_world()
- Duplicate: copies world directory file-by-file, creates new index entry with "(copy)" suffix
- Export: opens world directory in system file manager via OS.shell_open()
- Delete: shows confirmation modal (destructive red button), then soft-deletes to `user://worlds/_deleted/{id}`

**New World modal (Surface 4):**
- LineEdit with 24-char max, counter label, profanity error label (never echoes rejected name — T-06-S2)
- Seed field (random if empty)
- Survival/Creative toggle with accent-yellow active border
- Create button: loading state during WorldSave.create_world(), returns to ready on rejection
- Cancel / tap-overlay-to-dismiss

**Telemetry:** `WORLD_SELECT_SHOWN` in `_ready()`, `WORLD_CREATED` + `WORLD_LOADED` on world creation, `WORLD_LOADED` on card Play.

**friends_panel.gd:** `@export var standalone_mode: bool = false` added. `_apply_standalone_mode()` hides the `AdminControlsSection` node if present (hook for Phase 4+ admin UI).

## World Index Schema

```
user://worlds/index.cfg
[world_id]
name = "My World"
seed = 12345
mode = "survival"
created_unix = 1748588400
last_played_unix = 1748588400
```

Index is read in `_rebuild_world_list()` and written in `_write_index_entry()`. Rebuilt from existing entries on every open — consistent with plan spec.

## Deviations from Plan

### Auto-fixed Issues

None. Plan executed as specified.

### Scope Note

The plan mentions `new_world_modal.gd` as a separate file; the modal was implemented inline within `world_select_screen.gd` as a set of overlay nodes built programmatically in `_build_new_world_modal()`. This matches the PLAN.md note "show new world modal (set visible = true on the embedded _new_world_modal PanelContainer)" and the 06-UI-SPEC.md performance constraint "Static scene; no dynamic content — Instantiated once per world_select_screen _ready; shown/hidden". No separate .gd/.tscn file for the modal was needed or created.

### ContextMenu Fallback

The plan references `/root/ContextMenu` autoload (Phase 5 singleton). A `_show_fallback_context_menu()` method was added as a fallback when the autoload is not wired, to ensure the screen degrades gracefully rather than silently doing nothing on right-click.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes at trust boundaries were introduced beyond what was declared in the plan's `<threat_model>`. The world index ConfigFile access is local-only. `OS.shell_open()` opens the world directory in the system file manager, not an arbitrary URL (T-06-SC: accepted).

## Known Stubs

None. All plan deliverables are fully wired:
- World card thumbnails load from disk or fall back to placeholder
- Mode badges wire to the actual `mode` field from the index
- Telemetry events are fired at the correct lifecycle points

## Self-Check

Files created/modified:
- `/Users/jnuyens/src/LegoMinecraft/src/ui/world_select_screen.gd` — FOUND
- `/Users/jnuyens/src/LegoMinecraft/src/ui/world_select_screen.tscn` — FOUND
- `/Users/jnuyens/src/LegoMinecraft/src/autoload/world_save.gd` — FOUND (capture_thumbnail + save_world)
- `/Users/jnuyens/src/LegoMinecraft/assets/themes/cubicraftia.tres` — FOUND (3 new StyleBoxes)
- `/Users/jnuyens/src/LegoMinecraft/src/ui/friends_panel.gd` — FOUND (standalone_mode)

Commits:
- `76906cd` feat(06-05): WorldSave.capture_thumbnail() + 3 world card StyleBoxes
- `06d440f` feat(06-05): world_select_screen + standalone_mode in friends_panel

## Self-Check: PASSED
