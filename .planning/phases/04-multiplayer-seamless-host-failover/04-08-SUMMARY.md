---
phase: 04-multiplayer-seamless-host-failover
plan: "08"
subsystem: ui-multiplayer
tags: [chat, profanity-filter, network-hud, nameplates, surface-7, surface-8, surface-10]
dependency_graph:
  requires: [04-05, 04-06, 04-07]
  provides: [chat_overlay, profanity_filter, network_hud, remote_builder_nameplate]
  affects: [04-09, 04-11]
tech_stack:
  added:
    - ProfanityFilter static utility (GDScript, RegEx-based word-boundary matching)
    - ChatOverlay CanvasLayer 5 (GDScript + .tscn, rate-limited ephemeral chat)
    - NetworkHud VBoxContainer (1 Hz Timer RTT display with signal icons)
    - RemoteBuilderNameplate Node3D (Label3D billboard, 20 m fade)
  patterns:
    - Timer-driven refresh at 1 Hz (not _process) for network HUD
    - Signal-driven chat history updates via NetworkManager.chat_message_received
    - Static regex cache in ProfanityFilter for performance
    - Group-based nameplate toggle ("remote_nameplate")
key_files:
  created:
    - src/networking/profanity_filter.gd
    - src/ui/chat_overlay.gd
    - src/ui/chat_overlay.tscn
    - src/ui/network_hud.gd
    - src/ui/network_hud.tscn
    - src/world/remote_builder_nameplate.gd
  modified:
    - src/autoload/network_manager.gd
    - src/ui/settings_menu.gd
    - tests/unit/test_chat_rate_limit.gd
decisions:
  - "ProfanityFilter uses static compiled regex (cached, recompiled only on set_word_list) for performance on mobile"
  - "Chat RPCs use reliable transport (_deliver_chat, _send_chat_to_host) rather than unreliable to prevent message loss"
  - "Host-side rate tracking uses rolling window via per-peer reset timestamp (not a Timer per peer, avoiding N timers)"
  - "Label3D created programmatically in _ready() so RemoteBuilderNameplate attaches as a plain Node3D without a .tscn dep"
  - "NetworkHud rows built programmatically (no .tscn template) to allow runtime peer-count variation"
metrics:
  duration_s: 315
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 6
  files_modified: 3
---

# Phase 04 Plan 08: Chat overlay, Network HUD, Nameplates, Profanity filter — Summary

**One-liner:** Ephemeral chat overlay with 5/10s rate limit + client-and-host profanity filtering, 1 Hz RTT signal-icon HUD with relay badge, and billboard Label3D nameplates with 20 m distance fade and settings.cfg toggle.

## Tasks Completed

| # | Name | Commit | Key Files |
|---|------|--------|-----------|
| 1 | ProfanityFilter utility + Chat overlay (Surface 7) | `63fba34` | profanity_filter.gd, chat_overlay.gd/.tscn, network_manager.gd |
| 2 | Network HUD (Surface 10) + Player nameplates (Surface 8) | `6710a95` | network_hud.gd/.tscn, remote_builder_nameplate.gd, settings_menu.gd |

## What Was Built

### Task 1: ProfanityFilter + ChatOverlay

**`src/networking/profanity_filter.gd`**
- `class_name ProfanityFilter extends RefCounted`
- 20-word ASCII stub blocklist (`_WORD_LIST`) for Phase 4 testing
- `static func filter(text) -> String`: case-insensitive `(?i)\b(word1|word2|...)\b` regex, replaces matches with `[filtered]`
- `static var _custom_list: Array[String]` + `set_word_list(words)` Phase 5 extension point
- Static compiled regex cache (`_regex`); recompiled only when `_custom_list` changes

**`src/ui/chat_overlay.gd` + `chat_overlay.tscn`**
- CanvasLayer layer=5; visible gate via `NetworkManager.is_multiplayer_active()`
- `ui_chat_toggle` action handled in `_unhandled_input` to toggle HistoryPanel + focus InputField
- Rate limit: `RATE_LIMIT_MESSAGES=5`, `RATE_LIMIT_WINDOW_S=10.0`; 6th message dropped silently; `LineEdit.editable=false` + countdown label with `ui.chat.rate_limit_wait` tr() string
- History: `MAX_HISTORY=40`; oldest child `queue_freed` at cap; `ScrollContainer` auto-scrolls to bottom
- Auto-show: `_auto_hide_timer` (5 s one-shot) hides HistoryPanel when chat not active
- Per-player mute: `_muted_peers: Dictionary`; `toggle_mute(peer_id)` / `is_muted(peer_id)`; local-only
- Sender sees original unfiltered message; all peers receive host-filtered copy via `_deliver_chat` RPC

**`src/autoload/network_manager.gd` extensions:**
- `const _ProfanityFilter := preload(...)` at file top
- `send_chat(message)`: applies `_ProfanityFilter.filter()` client-side; if host relays via `_deliver_chat.rpc()`; if peer sends via `_send_chat_to_host.rpc_id(1, ...)`
- `@rpc("any_peer", "call_remote", "reliable") _send_chat_to_host(message)`: host-side rate limit (`_chat_rate_counts` + `_chat_rate_reset_time` dicts, 5/10s rolling window); host re-filters (T-04-08-T defense in depth); broadcasts via `_deliver_chat.rpc(sender_id, filtered, ts)`; emits `chat_message_received` locally
- `@rpc("authority", "call_remote", "reliable") _deliver_chat(sender_id, message, ts)`: peers emit `chat_message_received` on receipt

### Task 2: Network HUD + Nameplates

**`src/ui/network_hud.gd` + `network_hud.tscn`**
- `class_name NetworkHud extends VBoxContainer`; anchored top-right; `visible=false` until session active
- `_cache_signal_icons()`: loads `icon_signal_{1,2,3}.png` in `_ready()`; null fallback if not yet authored
- `_update_timer` (1 Hz, one_shot=false) → `_refresh_rtt_indicators()`: RTT buckets <50ms=3-bar green, 50-150ms=2-bar amber, >150ms=1-bar red
- Per-peer rows built in `_build_peer_row(peer_id)`: HBoxContainer + TextureRect "SignalIcon" + Label "UsernameLabel" (10-char max) + Label "RelayBadge" (hidden default)
- `show_relay_badge(peer_id, show)`: toggles RelayBadge visibility (amber text `ui.netstatus.relay_badge`)
- `_on_peer_laggy(peer_id, is_laggy)`: tints SignalIcon amber when laggy, white on recovery
- `peer_connected` / `peer_disconnected` / `session_state_changed` signal wiring

**`src/world/remote_builder_nameplate.gd`**
- `class_name RemoteBuilderNameplate extends Node3D`
- Label3D created programmatically in `_ready()` at `Vector3(0, 2.2, 0)` if not present
- `_apply_label3d_settings()`: `pixel_size=0.004`, `font_size=14`, `billboard=BILLBOARD_ENABLED`, `visibility_range_end=20.0`, `visibility_range_end_margin=4.0`, `outline_size=1`, `no_depth_test=true`
- `setup(uname, colour)`: sets `_label.text = uname.left(16)`, `_label.modulate = colour`
- `add_to_group("remote_nameplate")` for group-based toggle
- `_load_nameplate_pref()`: reads `user://settings.cfg [multiplayer] show_nameplates` (default true)
- `_on_session_state_changed()`: hides nameplate on DISCONNECTED/IDLE

**`src/ui/settings_menu.gd` extension:**
- `_add_nameplate_toggle()`: appends CheckBox "ShowNameplatesCheck" to `_settings_content`
- Text via `tr("ui.settings.show_nameplates")`; loads and saves `user://settings.cfg [multiplayer] show_nameplates`
- `_on_nameplate_toggle(show)`: saves setting; propagates via `get_tree().get_nodes_in_group("remote_nameplate")`

## Deviations from Plan

**1. [Rule 1 - Bug] Changed _receive_chat RPC to _deliver_chat with proper parameters**
- **Found during:** Task 1 implementation
- **Issue:** The existing `_receive_chat` RPC used `@rpc("authority", "unreliable")` but didn't carry `sender_id` or timestamp; chat messages would be anonymous on peers
- **Fix:** Replaced with `_deliver_chat(sender_id, message, ts)` using `"reliable"` transport to prevent message loss and carry sender context
- **Files modified:** `src/autoload/network_manager.gd`
- **Note:** The old `_receive_chat` stub is fully superseded — `send_chat()` no longer calls it

**2. [Rule 2 - Missing critical functionality] Added host-side rate tracking state**
- **Found during:** Task 1 threat model review (T-04-08-D)
- **Issue:** Plan described host-side rate enforcement in `_receive_chat_from_peer` but the existing code had no per-peer rate state
- **Fix:** Added `_chat_rate_counts: Dictionary`, `_chat_rate_reset_time: Dictionary`, and `CHAT_RATE_LIMIT`/`CHAT_RATE_WINDOW_S` constants; implemented rolling-window rate check in `_send_chat_to_host` before relay

## Known Stubs

| File | Stub | Reason |
|------|------|--------|
| `src/networking/profanity_filter.gd` | `_WORD_LIST` 20-word stub | Real community-maintained list deferred to Phase 5 per 04-RESEARCH.md Q4 |
| `src/ui/network_hud.gd` | Signal icon textures null fallback | `icon_signal_{1,2,3}.png` not yet authored; HUD row still renders without icon |

## Threat Surface Scan

No new unplanned network endpoints, auth paths, or schema changes introduced. All surfaces stay within the threat model declared in the plan (T-04-08-T, T-04-08-D accepted).

## Self-Check: PASSED

- `src/networking/profanity_filter.gd` — exists
- `src/ui/chat_overlay.gd` — exists
- `src/ui/chat_overlay.tscn` — exists
- `src/ui/network_hud.gd` — exists
- `src/ui/network_hud.tscn` — exists
- `src/world/remote_builder_nameplate.gd` — exists
- Commit `63fba34` — verified (Task 1)
- Commit `6710a95` — verified (Task 2)
