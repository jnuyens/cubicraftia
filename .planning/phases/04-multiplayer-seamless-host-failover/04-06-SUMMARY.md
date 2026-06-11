---
phase: 04-multiplayer-seamless-host-failover
plan: "06"
subsystem: ui
tags: [sign-in, friends, social, slide-in, mobile-overlay, webrtc, mutual-exclusion]
dependency_graph:
  requires:
    - 04-01  # locale/en.po Phase 4 keys (ui.signin.*, ui.friends.*)
    - 04-04  # FriendsClient autoload (sign_in, sign_up, get_friends, etc.)
    - 04-05  # NetworkManager (join_session_requested consumer in Wave 4)
  provides:
    - SignInPanel (sign_in_panel.gd/.tscn) — full-screen Surface 1 auth gate
    - FriendsPanel (friends_panel.gd/.tscn) — slide-in Surface 2 + embedded Surface 3
    - mobile_overlay notify_friends_open() — mutual exclusion with inventory + palette
    - ui_chat_toggle / ui_friends_open input actions in project.godot
  affects:
    - 04-07  # invite_modal.gd uses friends_panel to show friend list context
    - 04-08  # chat_overlay.gd uses ui_chat_toggle action added here
    - 04-10  # join_screen.gd receives join_session_requested signal from FriendsPanel
tech_stack:
  added: []
  patterns:
    - _apply_tab_style verbatim from inventory_slide_in.gd (2px accent underline)
    - _animate_to / _snap_to_nearest verbatim from inventory_slide_in.gd (TWEEN_DURATION_S=0.22)
    - _setup_panel_style verbatim from inventory_slide_in.gd (sidebar vs bottomsheet corners)
    - notify_friends_open mirroring notify_inventory_open in mobile_overlay.gd
    - get_node_or_null tree traversal for all cross-scene references
    - tr() for all visible strings — no hardcoded English
key_files:
  created:
    - src/ui/sign_in_panel.gd
    - src/ui/sign_in_panel.tscn
    - src/ui/friends_panel.gd
    - src/ui/friends_panel.tscn
  modified:
    - src/ui/mobile_overlay.gd
    - src/ui/mobile_overlay.tscn
    - project.godot
decisions:
  - "sign_in_panel.gd extends Control (not PanelContainer) — root is CanvasLayer child; UI built programmatically in _ready() to avoid hard scene node name dependencies"
  - "OAuth buttons (Apple/Google) are stubs emitting sign_in_failed until Phase 5/6 per T-04-06-T threat accept disposition"
  - "friends_panel.gd uses sidebar position:x animation for desktop (mirrors inventory_slide_in _animate_sidebar_to pattern)"
  - "join_session_requested signal emitted from FriendsPanel rather than calling NetworkManager directly — decoupled for Wave 4 wiring"
  - "notify_friends_open closes inventory on friends open (mutual exclusion) — FriendsPanel.open() also closes both palette + inventory via group lookup for belt-and-suspenders coverage"
metrics:
  duration_minutes: 45
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 3
---

# Phase 04 Plan 06: Sign-in Panel + Friends Panel Summary

**One-liner:** Full-screen sign-in / create-account Surface 1 gate wired to FriendsClient, plus slide-in friends list Surface 2 (online/offline, sessions, search) with verbatim inventory_slide_in.gd chrome and mutual-exclusion extension in mobile_overlay.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Sign-in panel (Surface 1) | 3bba372 | src/ui/sign_in_panel.gd, src/ui/sign_in_panel.tscn |
| 2 | Friends panel (Surfaces 2+3) + mobile overlay extension | 3e40a6c | src/ui/friends_panel.gd, src/ui/friends_panel.tscn, src/ui/mobile_overlay.gd, src/ui/mobile_overlay.tscn, project.godot |

## What Was Built

### Task 1: sign_in_panel.gd + sign_in_panel.tscn

- CanvasLayer layer=10 root, `visible = false` by default, child Control extends SignInPanel
- UI built fully programmatically in `_ready()` — no hard node-name dependencies
- Two tabs ("Sign in" / "Create account") using `_apply_tab_style` verbatim from `inventory_slide_in.gd`
- Email LineEdit, password LineEdit (`secret = true`), age CheckBox (Create tab only)
- Error label uses only `tr()` user-facing strings — T-04-06-I mitigate: HTTP codes never surfaced
- Connects to FriendsClient signals: `signed_in`, `sign_in_failed`, `sign_up_ok`, `sign_up_failed`
- `_on_signed_in`: hides panel, emits `sign_in_complete`
- `_on_sign_up_ok`: shows verification notice, hides after 2s via one-shot Timer
- OAuth buttons (`_on_apple_sign_in`, `_on_google_sign_in`) stub: emit `sign_in_failed` with error_network — T-04-06-T accept (no false auth possible)
- All strings via `tr("ui.signin.*")` — zero hardcoded English in GDScript

### Task 2: friends_panel.gd + friends_panel.tscn + mobile_overlay extension

**friends_panel.gd (Surface 2 + embedded Surface 3):**
- Chrome verbatim from `inventory_slide_in.gd`: `COLOR_NAVY`, `COLOR_ACCENT`, `COLOR_WHITE`, `TWEEN_DURATION_S=0.22`, `SIDEBAR_WIDTH=360`, `PEEK_HEIGHT=48`
- `_setup_panel_style()`, `_animate_to()`, `_snap_to_nearest()` — verbatim copy
- `@export var layout: String = "sidebar"` — sidebar (desktop) or bottomsheet (mobile)
- `open()` closes brick palette + inventory slide-in via group lookup (mutual exclusion)
- `open()` calls `FriendsClient.get_friends()` on every open to refresh list
- Friend rows: 10×10 online dot (COLOR_ONLINE `#3DB560` / COLOR_OFFLINE `#6B7280`), name, status line, "Join" button (80px) when `current_session_id != null`
- "Join" emits `join_session_requested(session_id)` signal for NetworkManager (Wave 4)
- Search: `text_changed` → `FriendsClient.search_friend(text)` when >= 2 chars; restores cached list otherwise
- Pending invites: Accept/Decline rows with `FriendsClient.create_friendship / delete_friendship`
- Empty state: "No friends yet" heading + "Share an invite link" body
- `_notify_friends_open(is_open)`: finds mobile_overlay via group, calls `notify_friends_open()`
- T-04-06-S: friend UIDs never displayed in UI; only `username` (display_name) shown

**mobile_overlay.gd extensions:**
- `_friends_panel_open: bool = false` — tracks friends panel state
- `notify_friends_open(is_open: bool)`: closes palette + inventory on friends open; updates crosshair visibility (crosshair hidden when `_palette_open or _inventory_panel_open or _friends_panel_open`)
- `_on_chat_pressed()`: `Input.action_press("ui_chat_toggle")` + release (same pattern as `_on_inventory_pressed`)
- `_on_friends_pressed()`: group lookup for "friends_panel", calls `open()`
- `_ready()`: wires ChatButton and FriendsButton via `get_node_or_null` + `has_signal("pressed")` guard

**mobile_overlay.tscn additions:**
- `FriendsButton` (top-right, offset_top=88, 64×64) — action `ui_friends_open`
- `ChatButton` (bottom-left, offset_top=-240, 64×64) — action `ui_chat_toggle`

**project.godot:**
- `ui_chat_toggle`: Enter key (physical_keycode=4194309)
- `ui_friends_open`: no keyboard default, triggered via TouchScreenButton action

## Deviations from Plan

**None — plan executed exactly as written.**

Minor implementation notes (not deviations):
- `sign_in_panel.gd` builds its UI tree fully in `_ready()` (programmatic) rather than using `@onready` refs to a pre-built scene tree. This matches the `must_haves.truths` requirement for CanvasLayer layer=10 as root and avoids hard-coding scene paths for child nodes.
- `friends_panel.gd` uses a `_animate_sidebar_to()` helper (mirroring `inventory_slide_in.gd` line 696) for the desktop sidebar animation alongside `_animate_to()` for the bottomsheet — both share the same `_tween` kill-before-create guard.

## Threat Model Coverage

| Threat ID | Category | Disposition | Implementation |
|-----------|----------|-------------|----------------|
| T-04-06-I | Information Disclosure | mitigate | `_show_error()` only calls `tr()` user-facing strings; raw HTTP codes/server messages are never surfaced |
| T-04-06-T | Tampering | accept | `_on_apple_sign_in()` and `_on_google_sign_in()` call `_show_error(tr("ui.signin.error_network"))` — no false authentication possible |
| T-04-06-S | Spoofing | accept | Friend rows display only `username` field; `uid` from Supabase dictionary is never rendered in UI |

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| Apple sign-in | `sign_in_panel.gd` `_on_apple_sign_in()` | Phase 5/6 SIWA integration — emits error_network for now (T-04-06-T accept) |
| Google sign-in | `sign_in_panel.gd` `_on_google_sign_in()` | Phase 5/6 OAuth integration — emits error_network for now (T-04-06-T accept) |
| `join_session_requested` consumer | `friends_panel.gd` | NetworkManager wave 4 (04-10) will connect to this signal |

These stubs do not prevent the plan's goal (sign-in panel gates access, friends list shows friends and sessions) — they are intentional Phase 5/6 deferred items.

## Self-Check: PASSED

- [x] `src/ui/sign_in_panel.gd` exists
- [x] `src/ui/sign_in_panel.tscn` exists
- [x] `src/ui/friends_panel.gd` exists
- [x] `src/ui/friends_panel.tscn` exists
- [x] `src/ui/mobile_overlay.gd` has `notify_friends_open` method
- [x] `project.godot` has `ui_chat_toggle` input action
- [x] Commit 3bba372 (Task 1) exists in git log
- [x] Commit 3e40a6c (Task 2) exists in git log
- [x] All strings via `tr()` — zero raw English in GDScript files
- [x] FriendsClient.sign_in called on submit (8 FriendsClient references in sign_in_panel.gd)
- [x] FriendsClient.get_friends called in friends_panel.open()
- [x] TWEEN_DURATION_S=0.22 (verbatim from inventory_slide_in.gd)
