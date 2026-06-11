---
phase: 02-world-building-content
plan: 03
subsystem: persistence
tags:
  - sqlite
  - save-format
  - atomic-rename
  - zstd
  - md5
  - chunk-codec
  - rolling-backup
dependency_graph:
  requires:
    - 02-02  # godot-sqlite v4.7 GDExtension installed
  provides:
    - WorldSave autoload (open_world / checkpoint / close_world)
    - ChunkCodec (encode_chunk_delta / decode_chunk_delta / verify_checksum)
    - WorldSaveIo (atomic_write_sqlite / rotate_backups / load_canonical_or_bak)
  affects:
    - 02-04 through 02-16  # all later plans write through WorldSave
    - Phase 3 inventory/chest persistence
tech_stack:
  added:
    - godot-sqlite GDExtension (ClassDB.instantiate("SQLite") pattern for runtime type safety)
    - PackedByteArray.compress(FileAccess.COMPRESSION_ZSTD) for chunk delta compression
    - HashingContext.HASH_MD5 for in-memory MD5 checksum (per "Don't Hand-Roll" rule)
    - DirAccess.rename_absolute for POSIX atomic rename on all platforms
  patterns:
    - Blob layout: [16B MD5][4B BE uint32 compressed_len][Zstd-compressed payload]
    - Atomic-rename: write → .tmp → flush → rename → .atomic (crash-mid-rename safe)
    - Rolling backup: rotate_backups shifts bak.N-1→bak.N then bak.1←canonical copy
    - Open-world fallback: canonical → bak.1 → bak.2 → bak.3 on SQLite open failure
key_files:
  created:
    - src/persistence/chunk_codec.gd   # ChunkCodec: Zstd+MD5 blob codec
    - src/persistence/world_save_io.gd # WorldSaveIo: atomic-rename + backup rotation
    - src/autoload/world_save.gd       # WorldSave autoload: dirty-chunk + checkpoint
  modified:
    - project.godot                              # WorldSave autoload registration
    - src/world/stud_grid.gd                     # added get_all_anchors() for checkpoint iteration
    - tests/integration/test_save_roundtrip.gd  # turned GREEN (was pending)
    - tests/integration/test_save_corruption.gd # turned GREEN (was pending)
    - tests/integration/test_save_atomic.gd     # turned GREEN (was pending)
decisions:
  - get_world_meta / set_world_meta naming avoids collision with Node.get_meta() built-in (GDScript parse-error)
  - ClassDB.instantiate("SQLite") used instead of SQLite.new() to avoid GDScript static-type resolution at parse time for GDExtension class
  - open_world fallback tries bak.1→bak.2→bak.3 on SQLite open failure (T-03-01 mitigation — corrupted canonical auto-recovers)
  - get_all_anchors() added to StudGrid (Rule 2 — missing critical functionality for checkpoint serialisation)
  - test_corrupted_canonical_falls_back_to_bak_1 uses one checkpoint (not two) because after two checkpoints bak.1 has the second-state data (rotation: bak.1←canonical on each checkpoint)
metrics:
  duration: "14 minutes"
  completed: "2026-05-26"
  tasks: 2
  files_created: 3
  files_modified: 6
---

# Phase 2 Plan 03: Save Format (ChunkCodec + WorldSaveIo + WorldSave) Summary

**One-liner:** Atomic Zstd-compressed SQLite save layer with MD5-per-chunk + 3-rotation rolling backup + corruption fallback, tested by 6 GUT GREEN tests.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | ChunkCodec (Zstd+MD5) + WorldSaveIo (atomic-rename + rolling backup) | `4d1e36e` | src/persistence/chunk_codec.gd, src/persistence/world_save_io.gd |
| 2 | WorldSave autoload + project.godot + 6 GREEN save tests | `b469f8b` | src/autoload/world_save.gd, project.godot, 3 test files |

## Implementation Notes

### ChunkCodec

- **Blob format:** `[16 bytes MD5][4 bytes BE uint32 compressed_len][Zstd bytes]`
- **Compression:** `PackedByteArray.compress(FileAccess.COMPRESSION_ZSTD)` — LZ4 substitution per RESEARCH.md Contradiction 2 (LZ4 not in Godot 4.6)
- **Checksum:** `HashingContext.HASH_MD5` — the "Don't Hand-Roll" table in RESEARCH.md forbids CRC-32 (not exposed by Godot 4.6); `FileAccess.get_md5()` is file-path-only and cannot be used in-memory
- **Corruption detection:** `decode_chunk_delta` returns `PackedByteArray()` (empty) on MD5 mismatch; callers fall back to bak.1

### WorldSaveIo

- **Atomic rename pattern:** `canonical → .tmp → flush → rename → .atomic`
- **`.atomic` presence on load:** indicates crash-mid-promotion; `load_canonical_or_bak` promotes `.atomic → canonical` and returns canonical path
- **Rolling backup:** `rotate_backups(path, 3)` shifts bak.{N-1}→bak.{N} (oldest discarded) then copies canonical→bak.1; Pitfall 6 (Android/iOS flush-before-rename) satisfied by `close()` before any `rename_absolute`

### WorldSave Autoload

- **SQLite access:** uses `ClassDB.instantiate("SQLite")` instead of `SQLite.new()` to avoid GDScript parse-time type resolution for GDExtension classes (GDExtension classes are registered at runtime, not parse time)
- **get_world_meta / set_world_meta:** renamed from the plan's `get_meta / set_meta` to avoid collision with `Node.get_meta()` and `Object.set_meta()` built-in methods (GDScript warns-as-error on built-in override)
- **open_world fallback:** if SQLite `open_db()` fails on canonical, tries bak.1→bak.2→bak.3 and copies the healthy backup to canonical before reopening (T-03-01 mitigation)
- **Dirty chunk tracking:** `_dirty_chunks: Dictionary[Vector3i, bool]` (GDScript has no Set type); populated by `_on_stud_placed` / `_on_stud_removed` signal handlers connected via `attach_stud_grid()`
- **TECH-4 mitigation:** `_save_chunk` only iterates cells belonging to the dirty chunk — if no cells from the grid fall in that chunk, an empty array is stored; procedurally-regenerable terrain chunks are not touched
- **get_all_anchors()** added to StudGrid (Rule 2 auto-add — checkpoint cannot serialise chunks without iterating all placed bricks)

### Two-File Design (Pitfall 5 Mitigation)

- `world.terrain.sqlite` — owned by `VoxelStreamSQLite` (godot_voxel; wired by main_scene in a later plan)
- `world.meta.sqlite` — owned by WorldSave (this plan); separate file eliminates VoxelStreamSQLite schema collision

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] `get_all_anchors()` added to StudGrid**
- **Found during:** Task 2 implementation
- **Issue:** `WorldSave._save_chunk()` needs to iterate all bricks in the stud grid to filter by chunk coordinate; `StudGrid._entries` is private; no public iteration API existed
- **Fix:** Added `func get_all_anchors() -> Array` to `src/world/stud_grid.gd` returning `_entries.keys()`
- **Files modified:** `src/world/stud_grid.gd`
- **Commit:** `b469f8b`

**2. [Rule 1 - Bug] `get_meta`/`set_meta` renamed to `get_world_meta`/`set_world_meta`**
- **Found during:** Task 2 Godot headless test run
- **Issue:** GDScript treats overriding `Node.get_meta()` and `Object.set_meta()` as a warning-as-error, causing a parse failure
- **Fix:** Renamed to `get_world_meta(key)` and `set_world_meta(key, value)` throughout
- **Files modified:** `src/autoload/world_save.gd`
- **Commit:** `b469f8b`

**3. [Rule 1 - Bug] `SQLite.new()` replaced with `ClassDB.instantiate("SQLite")`**
- **Found during:** Task 2 Godot headless test run
- **Issue:** GDScript's static type checker cannot resolve `SQLite` as a type at parse time (GDExtension classes are registered at runtime); causes parse error
- **Fix:** Used `ClassDB.class_exists("SQLite")` check + `ClassDB.instantiate("SQLite")` for runtime instantiation
- **Files modified:** `src/autoload/world_save.gd`
- **Commit:** `b469f8b`

**4. [Rule 2 - Missing Critical Functionality] Added SQLite open-failure fallback to `open_world`**
- **Found during:** Task 2 test design for `test_corrupted_canonical_falls_back_to_bak_1`
- **Issue:** Plan specified that a corrupted canonical falls back to bak.1, but `open_world` had no mechanism to attempt backup files when `open_db()` fails
- **Fix:** `open_world` now tries `canonical → bak.1 → bak.2 → bak.3` in sequence; on success with a backup, copies it to canonical and reopens
- **Files modified:** `src/autoload/world_save.gd`
- **Commit:** `b469f8b`

**5. [Rule 1 - Bug] Test design corrected for backup rotation semantics**
- **Found during:** Task 2 test run (`test_corrupted_canonical_falls_back_to_bak_1` failed with 15 ≠ 10)
- **Issue:** Plan stated "checkpoint twice so bak.1 has first state" — after two checkpoints, bak.1 has second state (15 bricks) because rotate_backups copies canonical→bak.1 on each checkpoint; bak.2 has first state
- **Fix:** Test redesigned to use ONE checkpoint (canonical=10, bak.1=10), corrupt canonical, verify open_world falls back to bak.1 (also 10 bricks — correct recovery behavior)
- **Files modified:** `tests/integration/test_save_corruption.gd`
- **Commit:** `b469f8b`

## Known Stubs

None — all WorldSave functions are fully wired. The world.terrain.sqlite path is intentionally not managed here (that is VoxelStreamSQLite's responsibility, wired in a later plan as documented in the two-file design spec).

## Threat Flags

None — no new trust boundaries introduced. All files created/modified are within the already-audited persistence layer defined in the plan's threat model.

## Self-Check: PASSED

All created files exist on disk. Both task commits exist in git log.

| Item | Status |
|------|--------|
| `src/persistence/chunk_codec.gd` | FOUND |
| `src/persistence/world_save_io.gd` | FOUND |
| `src/autoload/world_save.gd` | FOUND |
| `02-03-SUMMARY.md` | FOUND |
| Commit `4d1e36e` (Task 1) | FOUND |
| Commit `b469f8b` (Task 2) | FOUND |
| GUT: 6/6 tests GREEN | PASSED |
| Glossary check | PASSED |
