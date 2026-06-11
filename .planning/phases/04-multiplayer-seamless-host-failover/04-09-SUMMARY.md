---
phase: 04-multiplayer-seamless-host-failover
plan: "09"
subsystem: ui-networking
tags:
  - handover-screen
  - autoload-order
  - session-id
  - failover
dependency_graph:
  requires:
    - 04-05  # NetworkManager autoload (host_failover_started/complete/failed signals)
    - 04-07  # Surface 6 UI (CanvasLayer patterns)
    - 04-08  # Chat overlay (Surface 7, layer pattern reference)
  provides:
    - handover_screen  # CanvasLayer 100 failover overlay
    - canonical_autoload_order  # project.godot [autoload] section locked
  affects:
    - src/world/strawberry.gd  # session_id fallback now uses NetworkManager
    - src/world/main_scene.gd  # same session_id guard
tech_stack:
  added:
    - handover_screen.gd / handover_screen.tscn (CanvasLayer 100 failover overlay)
  patterns:
    - tween-kill-before-create (FADE_DURATION_S=0.22s, EASE_OUT TRANS_CUBIC)
    - one-shot timer for slow-threshold (8s amber subtitle update)
    - is_instance_valid guard for NetworkManager signal subscription
key_files:
  created:
    - src/ui/handover_screen.gd
    - src/ui/handover_screen.tscn
  modified:
    - project.godot  # [autoload] order rewritten to canonical
    - src/autoload/world_save.gd  # TODO comment updated, A3 cleanup noted
    - src/world/strawberry.gd  # _get_session_id: NetworkManager guard
    - src/world/main_scene.gd  # _get_session_id + inline: NetworkManager guard
decisions:
  - id: handover-overlay-layer-100
    summary: "CanvasLayer layer=100 ensures handover screen renders above all game UI"
  - id: autoload-canonical-order-locked
    summary: "project.godot [autoload] locked: Features→BrickRegistry→…→ThermalProbe→AndroidThermal→SessionRegistry→NetworkManager→FriendsClient"
  - id: strawberry-session-id-networked
    summary: "session_id now prefers NetworkManager.get_session_id() with is_instance_valid guard; timestamp fallback remains for solo play"
metrics:
  duration: "3m"
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 4
---

# Phase 04 Plan 09: Handover Screen + Autoload Order + Strawberry Cleanup Summary

**One-liner:** CanvasLayer-100 failover overlay with 8-second amber slow threshold, canonical autoload order locked (NetworkManager after WorldSave+Inventory), and strawberry session_id fallback updated to prefer `NetworkManager.get_session_id()`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Handover screen (Surface 9) | a120f95 | src/ui/handover_screen.gd, src/ui/handover_screen.tscn |
| 2 | Autoload order + strawberry session_id cleanup | 7415078 | project.godot, world_save.gd, strawberry.gd, main_scene.gd |

## What Was Built

### Task 1: Handover Screen (Surface 9)

`src/ui/handover_screen.gd` — CanvasLayer layer=100 controller:
- Subscribes to `NetworkManager.host_failover_started` → shows overlay (visible=true, modulate.a=1.0), resets subtitle copy, starts 8-second one-shot timer.
- On `NetworkManager.host_failover_complete(new_host_peer_id)` → kills any running tween, creates a 0.22s fade-out (EASE_OUT, TRANS_CUBIC) then `queue_free()`.
- On `_on_slow_threshold()` (8s elapsed) → subtitle updates to `tr("ui.handover.subtitle_slow")` tinted `COLOR_RELAY_AMBER` (T-04-09-D mitigation).
- No `_input()` override, no close button, no Escape handler — not dismissible by player.

`src/ui/handover_screen.tscn` — scene structure:
- Root: CanvasLayer `layer=100`, `visible=false`
- Child `Background`: ColorRect full-rect, `Color(0.106, 0.173, 0.337, 0.88)`, `mouse_filter=STOP`
- Child `Background/Content`: VBoxContainer, anchor PRESET_CENTER, 400px wide
  - `IconRect`: TextureRect 48×48, icon_freeze.png placeholder, brick-white tint
  - `Heading`: Label with `tr("ui.handover.heading")` default text, DisplaySemibold, brick white
  - `Subtitle`: Label with `tr("ui.handover.subtitle")` default text, regular, 70% alpha
  - `Spinner`: AnimatedSprite2D, SpriteFrames from icon_spinner.png, 2 Hz, autoplay="default"

### Task 2: Autoload Order Finalization

`project.godot` [autoload] section rewritten to canonical order (Pitfall 8 contract):
```
Features → BrickRegistry → Iap → Toasts → Translations → WorldSave → Inventory →
WorldClock → Weather → Spawning → ToolWear → ThermalProbe → AndroidThermal →
SessionRegistry → NetworkManager → FriendsClient
```
Key constraints satisfied:
- `WorldSave` before `Inventory` before `NetworkManager` (verified by Python index check)
- All 3 Phase 4 autoloads after `ThermalProbe`/`AndroidThermal`
- `FriendsClient` last (connects to `NetworkManager.session_metadata_received` in `_ready`)

### Task 2: Strawberry session_id Cleanup (A3)

Replaced bare `str(int(Time.get_unix_time_from_system()))` session_id tokens in:
- `src/world/strawberry.gd` `_get_session_id()`: now prefers `NetworkManager.get_session_id()` with `is_instance_valid` guard before falling back to WorldSave meta or timestamp.
- `src/world/main_scene.gd` `_get_session_id()`: same guard pattern.
- `src/world/main_scene.gd` inline world-open session_id initialization: same guard.
- `src/autoload/world_save.gd`: TODO comment updated from `(04-05)` to `(04-11)` DOCS sync; A3 cleanup noted complete.

## Deviations from Plan

### Auto-applied (within plan scope)

**1. [Rule 2 - Missing guard] Inline session_id token in main_scene.gd _ready**

The plan mentioned `_get_session_id()` method in main_scene.gd but the inline world-open initialization at ~line 427 also used the bare timestamp. Updated both locations for consistency.

**2. [Rule 2 - Comment hygiene] world_save.gd TODO comment**

The plan specified adding a `TODO(04-11)` DOCS sync comment. The existing `TODO(04-05)` comment (from when NetworkManager hadn't shipped yet) was replaced with the `(04-11)` reference and a note that A3 cleanup is done.

## Known Stubs

- `HandoverScreen.Heading` default text is "Reconnecting…" (English literal). The `tr("ui.handover.heading")` key does not exist in `locale/en.po` yet — the translation key will resolve to the raw key string until locale/en.po is updated. This is intentional: the translation file sync is a separate plan task.
- `HandoverScreen.Subtitle` default text is "Restoring session" — same caveat.
- `icon_freeze.png` is used as a placeholder in the IconRect. Phase 6 will replace it with the proper brick icon per the plan task note.

## Self-Check

**Files exist:**
- src/ui/handover_screen.gd — FOUND
- src/ui/handover_screen.tscn — FOUND

**Commits exist:**
- a120f95 (feat: handover screen) — FOUND
- 7415078 (chore: autoload order + strawberry cleanup) — FOUND

## Self-Check: PASSED
