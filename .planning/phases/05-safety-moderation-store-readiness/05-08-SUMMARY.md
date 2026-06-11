---
phase: 05-safety-moderation-store-readiness
plan: "08"
subsystem: ui-moderation
tags: [block-modal, report-modal, context-menu, safety, moderation, surface-a, surface-b, surface-h, surface-i, surface-j]
dependency_graph:
  requires: [05-01, 05-05]
  provides: [block-modal, report-modal, context-menu-singleton, friends-panel-context-menu, chat-context-menu, nameplate-context-menu]
  affects: [src/ui/friends_panel.gd, src/ui/chat_overlay.gd, src/world/remote_builder_nameplate.gd, project.godot]
tech_stack:
  added: []
  patterns: [modal-canvas-layer-20, singleton-autoload, long-press-timer-500ms, context-menu-dynamic-buttons, structured-history-buffer]
key_files:
  created:
    - src/ui/block_modal.gd
    - src/ui/block_modal.tscn
    - src/ui/report_modal.gd
    - src/ui/report_modal.tscn
    - src/ui/context_menu.gd
    - src/ui/context_menu.tscn
  modified:
    - project.godot
    - src/ui/friends_panel.gd
    - src/ui/chat_overlay.gd
    - src/world/remote_builder_nameplate.gd
decisions:
  - "ContextMenu method renamed show_menu() (not show()) to avoid shadowing CanvasLayer.show() — Godot 4 treats show() override on CanvasLayer as a parse error"
  - "class_name declarations removed from BlockModal, ReportModal, ContextMenuSingleton — Godot 4 does not allow class_name when the same name is registered as an autoload singleton"
  - "ReportModal auto-mute delegates to ChatOverlay.mute_by_uid(uid) (uid string) rather than toggle_mute(peer_id: int) so the mute persists for the full session even if the peer_id changes"
metrics:
  duration_minutes: 45
  completed: "2026-05-29"
  tasks_completed: 2
  files_changed: 10
---

# Phase 05 Plan 08: Block Modal + Report Flow + ContextMenu Singleton Summary

Block confirmation modal (Surface A), 2-step report flow (Surface B), and a shared singleton ContextMenu (layer 25) wired into friends panel, chat overlay, and remote builder nameplate — fulfilling App Store Guideline 1.2 reporting accessibility from every UGC surface.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | BlockModal + ReportModal + ContextMenu singleton | e2f295e | block_modal.gd/.tscn, report_modal.gd/.tscn, context_menu.gd/.tscn |
| 2 | ContextMenu wired into 3 Phase 4 surfaces; autoloads registered | 0306f47 | project.godot, friends_panel.gd, chat_overlay.gd, remote_builder_nameplate.gd |

## What Was Built

### Block Modal (Surface A) — `src/ui/block_modal.gd`
- CanvasLayer layer=20 with full-screen ColorRect navy 60% overlay (MOUSE_FILTER_STOP — cannot dismiss by tapping outside or Escape).
- `open(uid, username)` public method. Heading and destructive button label both inject `{username}` at runtime.
- Block button calls `FriendsClient.block_user(uid)`, emits `user_blocked`, shows Toasts, closes modal.
- Submit button disabled during in-flight request (T-05-D1 rate limit mitigation).

### Report Modal (Surface B) — `src/ui/report_modal.gd`
- CanvasLayer layer=20. Same chrome as BlockModal.
- Step 1: 5 exclusive `CheckButton` category rows (48px touch targets, `ButtonGroup`). "Next" disabled until selection. "Cancel" flat link-style button.
- Step 2: `TextEdit` with 500-char limit enforced via `text_changed` signal truncation; character counter at 14px right-aligned (turns destructive red when < 50 chars remain); optional read-only context panel for `chat_message` surface showing up to 5 prior messages.
- `open(uid, username, surface, evidence)` public method.
- Submit calls `FriendsClient.submit_report(uid, surface, category, reason, evidence)`.
- Auto-mute after submit: calls `ChatOverlay.mute_by_uid(uid)` (local session display filter, not a block — T-05-I1).
- Shows `Toasts.show("ui.report.toast_submitted", "info")` on confirm.

### ContextMenu Singleton — `src/ui/context_menu.gd`
- CanvasLayer layer=25 (above modals at 20).
- `show_menu(items: Array, screen_pos: Vector2)` builds `Button` nodes dynamically from `{label, action}` dictionaries. Dividers via `"---"` label sentinel.
- Single shared `PanelContainer` instance (160px wide, `StyleBox_context_menu_panel` navy 96% alpha, 8px rounded corners).
- `_unhandled_input`: dismisses on any mouse click / screen touch outside panel bounds; Escape key also dismisses.
- Registered as autoload `ContextMenu` in `project.godot`.

### Friends Panel (Surface H) — `src/ui/friends_panel.gd`
- 500ms `Timer` (`_long_press_timer`) added in `_ready()`.
- Each friend row wired via `gui_input` to `_on_friend_row_input(event, uid, username, row)`.
- Long-press timeout: `ContextMenu.show_menu()` with items: Block (opens BlockModal), Report (opens ReportModal surface="player"), separator, Unfriend (calls `FriendsClient.delete_friendship(uid)`).

### Chat Overlay (Surface I) — `src/ui/chat_overlay.gd`
- Added `_history: Array` — structured buffer `{uid, username, text, timestamp}` capped at `MAX_HISTORY` entries, in sync with `_history_container` children.
- Added `_muted_uids: Dictionary` — uid-keyed local mute filter (complements existing `_muted_peers` peer-id filter).
- Added `mute_by_uid(uid)` public method — called by ReportModal after submission.
- 500ms `_msg_long_press_timer` per message row via `gui_input` closure binding the history index.
- Long-press timeout: `ContextMenu.show_menu()` with items: Mute (calls `mute_by_uid()`), Report (opens ReportModal with `evidence = {messages: <5-msg slice>}`).

### Remote Builder Nameplate (Surface J) — `src/world/remote_builder_nameplate.gd`
- `setup()` extended with optional `uid: String = ""` parameter (non-breaking — default is empty).
- `_unhandled_input` detects long-press (500ms Timer) and right-click within nameplate's screen-space bounding box (±24px horizontal, ±16px vertical of `Camera3D.unproject_position()`).
- `ContextMenu.show_menu()` with items: Report player (ReportModal), Block (BlockModal).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ContextMenu.show() conflicts with CanvasLayer.show() built-in**
- **Found during:** Task 1 syntax check — `SCRIPT ERROR: Parse Error: The method "show()" overrides a method from native class "CanvasLayer"`
- **Fix:** Renamed public method to `show_menu()`. Updated all three call sites in friends_panel, chat_overlay, remote_builder_nameplate.
- **Files modified:** src/ui/context_menu.gd, src/ui/friends_panel.gd, src/ui/chat_overlay.gd, src/world/remote_builder_nameplate.gd

**2. [Rule 1 - Bug] class_name BlockModal/ReportModal/ContextMenuSingleton conflicts with autoload name**
- **Found during:** Task 1 syntax check — `SCRIPT ERROR: Parse Error: Class "BlockModal" hides an autoload singleton`
- **Fix:** Removed `class_name` declarations from all three scripts. As autoloads they are accessed by singleton name, not class_name.
- **Files modified:** src/ui/block_modal.gd, src/ui/report_modal.gd, src/ui/context_menu.gd

## Known Stubs

None — all entry points wire to real `FriendsClient` methods (`block_user`, `submit_report`) added in Plan 05-05.

The `mute_by_uid` path in chat_overlay has a slight limitation: if `SessionRegistry.get_peer_list()` does not expose `uid` for a peer (e.g., the peer hasn't registered their uid), the uid string will be empty and the auto-mute will not apply. This is an acceptable limitation per the plan (peer uid is best-effort from SessionRegistry).

## Threat Flags

No new network endpoints or auth paths introduced. All surfaces use existing `FriendsClient.block_user()` and `FriendsClient.submit_report()` paths from Plan 05-05.

## Self-Check: PASSED

Files created:
- src/ui/block_modal.gd — FOUND
- src/ui/block_modal.tscn — FOUND
- src/ui/report_modal.gd — FOUND
- src/ui/report_modal.tscn — FOUND
- src/ui/context_menu.gd — FOUND
- src/ui/context_menu.tscn — FOUND

Files modified:
- project.godot (ContextMenu, BlockModal, ReportModal autoloads) — FOUND
- src/ui/friends_panel.gd (long-press timer, context menu) — FOUND
- src/ui/chat_overlay.gd (_history buffer, mute_by_uid, long-press) — FOUND
- src/world/remote_builder_nameplate.gd (uid param, _unhandled_input) — FOUND

Commits:
- e2f295e (Task 1) — FOUND
- 0306f47 (Task 2) — FOUND
