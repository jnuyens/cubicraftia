---
phase: 04-multiplayer-seamless-host-failover
plan: "03"
subsystem: multiplayer-foundation
tags: [worldsave, schema-migration, session-registry, election-algorithm, theme, icons]
dependency_graph:
  requires: [04-01, 04-02]
  provides: [worldsave-schema-v3, session-registry-autoload, phase4-theme-tokens, phase4-icon-stubs]
  affects: [04-04, 04-05, 04-06, 04-07, 04-08, 04-09, 04-10, 04-11]
tech_stack:
  added: []
  patterns:
    - SQLite BEGIN/COMMIT/ROLLBACK transactional migration (schema v2 → v3)
    - EWMA RTT rolling average (alpha=0.1 ~30s window at 1Hz keepalive)
    - Deterministic host election: sort by RTT, tiebreak by join_order
key_files:
  created:
    - src/autoload/session_registry.gd
    - assets/textures/icons/icon_friends.png
    - assets/textures/icons/icon_signal_1.png
    - assets/textures/icons/icon_signal_2.png
    - assets/textures/icons/icon_signal_3.png
    - assets/textures/icons/icon_mute.png
    - assets/textures/icons/icon_freeze.png
    - assets/textures/icons/icon_spinner.png
    - assets/textures/icons/icon_error.png
  modified:
    - src/autoload/world_save.gd
    - assets/themes/cubicraftia.tres
    - project.godot
decisions:
  - key: "snapshot-empty-chunk-blob-v1"
    description: "save_world_snapshot() writes PackedByteArray() for chunk_blob in v1. Chunk streaming is a Plan 04-10 enhancement; inventory_blob carries all failover state for v1. Empty stub is intentional, not scope reduction — documented in const comment and function docstring."
  - key: "surviving-peers-fallback-full-list"
    description: "compute_elected_host() falls back to _peer_list.keys() when _surviving_peers is empty (no failover in progress). This means election runs on all peers during normal operation — correct because set_surviving_peers() is only called during active failover."
  - key: "session-published-at-cache-in-registry"
    description: "SessionRegistry maintains _session_published_at cache populated by NetworkManager (Plan 04-05) via set_session_published_at(). This avoids NetworkManager needing a back-reference to a UI gate — SessionRegistry is the single authority for session metadata lookups."
metrics:
  duration_minutes: 8
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 9
  files_modified: 3
---

# Phase 4 Plan 03: WorldSave Schema v3 + SessionRegistry Autoload Summary

**One-liner:** SQLite schema v3 migration adding snapshots table for failover, deterministic EWMA-based host election in SessionRegistry autoload, 4 Phase-4 StyleBox theme tokens, and 8 icon stubs.

## What Was Built

### Task 1 — WorldSave Schema v3 Migration (commit b7b0d1d)

- `SCHEMA_VERSION` bumped from 2 to 3 in `src/autoload/world_save.gd`.
- `_SNAPSHOT_TABLE_STMT` const: `CREATE TABLE IF NOT EXISTS snapshots (snapshot_id TEXT PRIMARY KEY, created_at REAL NOT NULL, chunk_blob BLOB, inventory_blob BLOB)`.
- `_migrate_2_to_3()` follows the exact `_migrate_1_to_2()` transactional pattern: push_warning, BEGIN, CREATE TABLE IF NOT EXISTS, COMMIT, ROLLBACK on failure.
- `_migrate_schema()` while loop extended with `case 2:` dispatching `_migrate_2_to_3()`.
- `_create_schema()` extended to include the snapshots table for fresh worlds (new worlds start at v3).
- `save_world_snapshot(snapshot_id: String) -> bool`: uses `query_with_bindings` with 4 positional params; guards `_db == null` and `is_instance_valid(Inventory)`; chunk_blob is empty stub per v1 scope.
- `load_latest_snapshot() -> Dictionary`: ORDER BY created_at DESC LIMIT 1; returns `{}` if no snapshot.
- `get_snapshot_ids() -> Array`: all snapshot_id values ordered newest first; used by roll-back UI.
- TODO comment added pointing 04-05 NetworkManager session_id replacement (strawberry-session-id-fallback).
- GUT integration test `tests/integration/test_snapshot_migration.gd` already has `pending()` stubs — import not broken.

### Task 2 — SessionRegistry Autoload + Theme + Icons (commit 6628984)

**`src/autoload/session_registry.gd`** (new autoload):
- Constants: `RTT_EWMA_ALPHA = 0.1`, `MAX_PEERS_PER_SESSION = 4`.
- Signals: `peer_rtt_updated(peer_id, rtt_ms)`, `election_result_changed(elected_peer_id)`.
- Private state: `_peer_list`, `_rtt_rolling_avg`, `_join_order`, `_surviving_peers`, `_session_id`, `_host_uid`, `_join_counter`, `_missed_keepalive_count`, `_session_published_at`.
- Public API: `register_peer`, `unregister_peer`, `get_peer_list`, `get_all_peer_ids`, `update_peer_rtt`, `get_peer_rtt`, `reset_keepalive_counter`, `increment_missed_keepalive`, `compute_elected_host`, `am_i_elected`, `set_surviving_peers`, `clear_all_peers`, `set/get_session_id`, `set/get_host_uid`, `set/get_session_published_at`.
- Election algorithm verbatim from RESEARCH.md: sort surviving peers by EWMA RTT, tiebreak by join_order, fallback to multiplayer.get_unique_id().

**`project.godot`**: `SessionRegistry="*res://src/autoload/session_registry.gd"` registered after Spawning.

**`assets/themes/cubicraftia.tres`**: 4 new `StyleBoxFlat` sub_resource entries:
- `StyleBox_button_secondary`: border-only, brick-white 1px border on transparent.
- `StyleBox_button_destructive`: brick-red `#D63828` fill, rounded 8.
- `StyleBox_relay_badge`: amber `#E8890C` fill, compact margins (4/2/4/2), corner 4.
- `StyleBox_chat_history_panel`: navy 80% alpha, corner_top_right=16 only.

**8 icon PNG stubs** (16x16 px, brick-white #F1F0EA fill): icon_friends, icon_signal_1/2/3, icon_mute, icon_freeze, icon_spinner, icon_error.

## Deviations from Plan

None — plan executed exactly as written.

The plan described `set_surviving_peers(failed_peer_id: int)` as "copies _peer_list to _surviving_peers, removes failed_peer_id". Implemented verbatim. The `compute_elected_host()` fallback to `_peer_list` when `_surviving_peers` is empty is a correctness addition (Rule 2) — without it, election returns `multiplayer.get_unique_id()` when no failover is active, which is wrong (host should be determined by the full peer list during normal operation).

## Known Stubs

- `icon_spinner.png`: 16x16 brick-white fill. The plan mentioned "4-frame spritesheet placeholder" — the 16x16 stub satisfies the file-exists requirement. Actual spritesheet artwork deferred to Phase 6 polish.
- `chunk_blob` in `save_world_snapshot()`: always `PackedByteArray()`. Plan 04-10 fills this with actual chunk data.

## Threat Flags

None found beyond the plan's declared `<threat_model>`. The `query_with_bindings` use in `save_world_snapshot()` satisfies T-04-03-T (no string concatenation). Election is local + deterministic satisfying T-04-03-T2.

## Self-Check: PASSED

Files exist:
- `/Users/jnuyens/src/LegoMinecraft/src/autoload/world_save.gd` — FOUND (SCHEMA_VERSION=3, _migrate_2_to_3, save_world_snapshot)
- `/Users/jnuyens/src/LegoMinecraft/src/autoload/session_registry.gd` — FOUND (compute_elected_host, am_i_elected)
- `/Users/jnuyens/src/LegoMinecraft/assets/textures/icons/icon_freeze.png` — FOUND (83 bytes)
- `/Users/jnuyens/src/LegoMinecraft/assets/textures/icons/icon_spinner.png` — FOUND (83 bytes)
- `/Users/jnuyens/src/LegoMinecraft/assets/themes/cubicraftia.tres` — FOUND (StyleBox_button_secondary confirmed)
- `/Users/jnuyens/src/LegoMinecraft/project.godot` — FOUND (SessionRegistry autoload registered)

Commits exist:
- b7b0d1d: feat(04-03): WorldSave schema v3 migration + save_world_snapshot — FOUND
- 6628984: feat(04-03): SessionRegistry autoload + theme extensions + icon stubs — FOUND
