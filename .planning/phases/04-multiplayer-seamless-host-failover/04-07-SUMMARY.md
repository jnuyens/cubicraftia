---
phase: 04-multiplayer-seamless-host-failover
plan: "07"
subsystem: ui
tags: [invite, join, players-tab, host-admin, freeze-build, rollback, session-age-gate, surface-4, surface-5, surface-6]
dependency_graph:
  requires:
    - 04-01  # locale/en.po Phase 4 keys (ui.invite.*, ui.join.*, ui.players.*)
    - 04-04  # FriendsClient.create_invite, get_session_published_at, is_email_verified
    - 04-05  # NetworkManager: session_state_changed, kick_peer, set_freeze_build, freeze_build_changed
  provides:
    - InviteModal (invite_modal.gd/.tscn) — Surface 4 invite-link generation modal
    - JoinScreen (join_screen.gd/.tscn) — Surface 5 WebRTC handshake overlay (CanvasLayer 20)
    - PlayersTab (players_tab.gd) — Surface 6 host admin + peer-list panel
    - settings_menu extended with Players/Settings tab row
  affects:
    - 04-08  # chat_overlay uses settings_menu chrome
    - 04-10  # WorldSave.load_latest_snapshot called from roll-back confirm
tech_stack:
  added: []
  patterns:
    - PanelContainer modal pattern (navy bg, corner_radius=16, StyleBoxFlat) — no AcceptDialog
    - Timer one_shot + wait_time=2.0 for copy-revert (invite_modal.gd)
    - published_at > 0 cache-miss guard for session-age gate (join_screen.gd)
    - inline-expansion kick confirm (row height 56 → 112 px)
    - freeze_build_changed signal flow: UI → NetworkManager.set_freeze_build → broadcast_event → freeze_build_changed signal → PlayersTab._on_freeze_build_changed
    - _set_active_tab / _apply_tab_style with accent-yellow 2px bottom border (settings_menu.gd)
key_files:
  created:
    - src/ui/invite_modal.gd
    - src/ui/invite_modal.tscn
    - src/ui/join_screen.gd
    - src/ui/join_screen.tscn
    - src/ui/players_tab.gd
  modified:
    - src/ui/settings_menu.gd
    - src/ui/settings_menu.tscn
    - src/autoload/network_manager.gd
decisions:
  - Used `published_at > 0` guard in join_screen.gd so cache-miss sessions (published_at == 0) are never blocked by the session-age gate (CONTEXT Area 3)
  - Players tab uses direct VBoxContainer (not TabContainer built-in) to match the existing tab-row injection pattern from inventory_slide_in.gd
  - freeze_build_changed signal added to NetworkManager so non-host peers can update their UI on freeze events without polling
  - Roll-back confirmation uses PanelContainer overlay (not AcceptDialog) per PATTERNS.md line 484
  - kick_peer uses @rpc("authority") on _receive_kicked_notice to prevent peer impersonation (T-04-07-T)
metrics:
  duration: "~20 minutes"
  completed: "2026-05-29T16:51:22Z"
  tasks_completed: 2
  files_created: 5
  files_modified: 3
---

# Phase 04 Plan 07: Invite Modal, Join Screen, Players Tab Summary

**One-liner:** Invite link modal (Surface 4) with TTL countdown + join screen (Surface 5) with session-age gate + host-admin Players tab (Surface 6) injected into the pause menu.

## What Was Built

### Task 1: InviteModal + JoinScreen

**`src/ui/invite_modal.gd` + `.tscn`** (Surface 4):
- PanelContainer modal (400px, centred) over navy 60% alpha ColorRect overlay
- `open(session_id)` calls `FriendsClient.create_invite()` and waits for `invite_created` signal
- 1-second TTL countdown timer (`_expires_at - now` formatted as HH:MM:SS)
- `DisplayServer.clipboard_set()` on copy; 2-second "Copied!" revert via one-shot Timer
- Share button falls back to copy + Toasts on all platforms (OS share sheet stub for mobile)
- Error label for `invite_creation_failed` (unverified account, friends limit, network error)

**`src/ui/join_screen.gd` + `.tscn`** (Surface 5):
- `CanvasLayer` at `layer=20`, group `"join_screen"`
- Subscribes to `NetworkManager.session_state_changed` in `_ready()`
- Session-age gate: `if published_at > 0 and not FriendsClient.is_email_verified() and (now - published_at) > 86400` — cache miss (`published_at == 0`) never blocks
- On `CONNECTED_AS_PEER` success: `Toasts.show(ui.join.new_friends_toast)` then `queue_free()`
- Error state: hides Content, shows ErrorContent with ErrorBody + BackButton
- Emits `verification_required_for_old_session` signal on age-gate trigger

### Task 2: PlayersTab + settings_menu extension

**`src/ui/players_tab.gd`** (Surface 6):
- `class_name PlayersTab extends VBoxContainer`
- `_build_player_list()`: InviteButton (if < 4 peers), peer rows, RollBack section (host only)
- `_build_player_row()`: colour swatch, username label, (Host) badge, RTT label, Laggy label, admin buttons (host only, not for self)
- Kick: inline expand (56 → 112px row) → "Kick {username}? They can rejoin via invite." → Confirm kick / Cancel
- Freeze: toggle `NetworkManager.set_freeze_build(peer_id, !current)`, accent-yellow border on frozen row
- Roll-back: `_show_rollback_confirm_modal()` → PanelContainer overlay (not AcceptDialog), 2-button confirm → `push_warning()` audit trail → `NetworkManager.broadcast_event({"kind": "SNAPSHOT_RESET", ...})`
- `freeze_build_changed` signal from NetworkManager updates button text and row border
- `EVENT_FREEZE_BUILD` constant for readability

**`src/ui/settings_menu.gd` + `.tscn`** extended:
- `TabRow` HBoxContainer with `PlayersTabBtn` + `SettingsTabBtn` at top of VBox
- `_setup_tab_row()`: shows PlayersTabBtn only when `NetworkManager.is_in_session()`; defaults to Players tab in-session, Settings tab in solo
- `_set_active_tab(tab)`: shows/hides `PlayersContent` / `SettingsContent`; applies accent-yellow 2px underline to active tab via `_apply_tab_style()`
- `_inject_players_tab()`: loads `players_tab.gd` script, creates VBoxContainer, adds to PlayersContent
- Existing Graphics/BrickPacks/About sections moved inside `SettingsContent` wrapper
- @onready paths updated to reflect new nesting

**`src/autoload/network_manager.gd`** extended:
- `_frozen_peers: Dictionary` — peer freeze state store
- `freeze_build_changed(peer_id, frozen)` signal
- `is_in_session()` — alias for `is_multiplayer_active()`
- `kick_peer(peer_id)` — host-only; sends `_receive_kicked_notice` RPC then disconnects
- `set_freeze_build(peer_id, frozen)` — host-only; sets `_frozen_peers`, emits signal, broadcasts event
- `is_peer_frozen(peer_id)` — reads `_frozen_peers`
- `_receive_kicked_notice()` — @rpc("authority"), closes connection on the kicked peer

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new network endpoints or auth paths introduced beyond those in the plan's threat model.
- `kick_peer` / `set_freeze_build` are host-gated (`multiplayer.is_server()`) client-side AND protected by `@rpc("authority")` server-side (T-04-07-T mitigation: complete).
- Roll-back requires explicit 2-tap confirmation with `push_warning()` audit trail (T-04-07-R mitigation: complete).
- Clipboard is populated only on deliberate "Copy" button press (T-04-07-I accepted).

## Self-Check

Files exist check:
- src/ui/invite_modal.gd ✓
- src/ui/invite_modal.tscn ✓
- src/ui/join_screen.gd ✓
- src/ui/join_screen.tscn ✓
- src/ui/players_tab.gd ✓

Commits exist check:
- 5080ac3 feat(04-07): InviteModal (Surface 4) + JoinScreen (Surface 5)
- 6814286 feat(04-07): Players tab (Surface 6) + settings_menu tab row + NetworkManager admin RPCs

## Self-Check: PASSED
