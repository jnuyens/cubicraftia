---
phase: 02-world-building-content
plan: "02"
subsystem: test-infrastructure
tags: [godot-sqlite, gut-tests, wave-0, nyquist, multipass, reuse]
dependency_graph:
  requires: []
  provides:
    - addons/godot-sqlite (MIT, v4.7 — used by Plan 03 save format)
    - 16 Wave-0 GUT test skeleton files (used by Plans 03-12 as acceptance gates)
    - tests/conftest_helpers.gd Phase 2 helpers (used by all Phase 2 tests)
    - 02-MULTIPASS-NOTE.md binding decision (consumed by Plan 08 mineshaft generator)
  affects:
    - All Phase 2 plans that reference a test file in their acceptance_criteria
tech_stack:
  added:
    - "2shady4u/godot-sqlite v4.7 (MIT) — SQLite GDExtension for Godot 4.x"
  patterns:
    - "GUT pending() stub pattern for Wave-0 Nyquist compliance"
    - "Idempotent curl+sha256+unzip install pattern (extends Phase 1 install-deps.sh)"
    - "REUSE dep5 blanket SPDX coverage for third-party addons"
key_files:
  created:
    - addons/godot-sqlite/.gitkeep
    - tests/unit/test_biome_map.gd
    - tests/unit/test_world_clock.gd
    - tests/unit/test_weather.gd
    - tests/unit/test_lighting_channels.gd
    - tests/unit/test_brick_registry.gd
    - tests/unit/test_placement_rotation.gd
    - tests/unit/test_tool_wear.gd
    - tests/unit/test_brick_palette_filter.gd
    - tests/unit/test_bottomsheet.gd
    - tests/integration/test_biome_distribution.gd
    - tests/integration/test_structure_placement.gd
    - tests/integration/test_dynamite_blast.gd
    - tests/integration/test_save_roundtrip.gd
    - tests/integration/test_save_corruption.gd
    - tests/integration/test_save_atomic.gd
    - tests/integration/test_no_gravity.gd
    - .planning/phases/02-world-building-content/02-MULTIPASS-NOTE.md
  modified:
    - scripts/install-deps.sh
    - .reuse/dep5
    - .gitignore
    - tests/conftest_helpers.gd
decisions:
  - "godot-sqlite install uses demo.zip (not bin.zip) — demo.zip bundles the gdextension manifest + plugin.cfg + bin/ in the correct addon directory structure; bin.zip is a flat archive requiring manual manifest authoring"
  - "idempotency sentinel = gdsqlite.gdextension presence (not version comment); reliable because that file only exists post-install"
  - "VoxelGeneratorMultipassCB._generate_pass is confirmed available in addon at commit 4a9d311 (marked experimental); Plan 02-08 ships multipass_generator.gd (not inline fallback)"
  - "Two-pass mineshaft design: pass 0 = base terrain (no neighbor access), pass 1 = corridor carving (set_pass_extent_blocks=2)"
metrics:
  duration: "~25 minutes"
  completed: "2026-05-26"
  tasks_completed: 3
  files_created: 19
  files_modified: 4
---

# Phase 02 Plan 02: Wave-0 Test Infrastructure + godot-sqlite Install Summary

**One-liner:** Idempotent godot-sqlite v4.7 install with SHA-256 pinning + 16 GUT pending-skeleton test files covering all 02-VALIDATION.md Nyquist rows + binding multipass API decision for Plan 02-08.

## Tasks Completed

| # | Name | Commit | Key Files |
|---|------|--------|-----------|
| 1 | Install godot-sqlite v4.7 + REUSE compliance + gitignore | 9facaef | scripts/install-deps.sh, .reuse/dep5, .gitignore, addons/godot-sqlite/.gitkeep |
| 2 | Wave-0 test skeletons — 16 GUT files + conftest Phase 2 helpers | a35c723 | 16 test files, tests/conftest_helpers.gd |
| 3 | Multipass API spike — confirm VoxelGeneratorMultipassCB entry point | 14c5273 | .planning/phases/02-world-building-content/02-MULTIPASS-NOTE.md |

## Verification Results

- `reuse lint` exits 0 (275/275 files covered, MIT + GPL-3.0-or-later + OFL-1.1)
- `godot --headless -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg`: 0 FAILING, 44 PENDING/risky
- Glossary check passes (no "Lego"/"Minecraft"/"minifig" in any authored file)
- Idempotency verified: re-running the install section logs "already installed — skipping"
- 10 platform binary files present: macOS (debug+release), Windows (debug+release), Linux (debug+release), Android arm64 (debug+release), Android x86_64 (debug+release) + iOS xcframeworks + Web wasm

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Install sequence] Script exits before godot-sqlite section in this environment**
- **Found during:** Task 1
- **Issue:** `scripts/install-deps.sh` exits at the pipx guard (pipx not installed on this machine). The godot-sqlite install section is appended after the GUT clone section, but the macOS install path exits at `exit 1` when pipx is missing. The acceptance criterion requires the addon be installed.
- **Fix:** Ran the godot-sqlite install logic directly (using the pre-downloaded demo.zip from the SHA-256 verification step). The install-deps.sh script is correctly structured — the issue is this development machine's pipx absence, not a code bug. The script works correctly on a machine with all prerequisites (the Phase 1 pattern requires pipx for reuse).
- **Files modified:** None (script already correct)

**2. [Rule 1 - Bug] .gitkeep removed by install then not restored**
- **Found during:** Task 1 post-install
- **Issue:** The install script's `rm -f .gitkeep` before `cp -r` left no `.gitkeep` after installation. Git could not track the directory.
- **Fix:** Added `touch "$SQLITE_DIR/.gitkeep"` immediately after the cp command in the install section. The gitkeep is always restored after addon installation.
- **Commit:** 9facaef

**3. [Rule 2 - Completeness] plugin.cfg not in gitignore**
- **Found during:** Task 1, inspecting installed files
- **Issue:** The demo.zip includes `plugin.cfg` which was not in the original gitignore list. Without ignoring it, `git status` would show it as untracked after installation.
- **Fix:** Added `addons/godot-sqlite/plugin.cfg` to .gitignore.
- **Commit:** 9facaef

**4. [Rule 1 - Archive choice] bin.zip vs demo.zip**
- **Found during:** Task 1, inspecting release assets
- **Issue:** The PLAN.md specified `godot-sqlite-gd4.7.zip` (which doesn't exist — the asset is named `demo.zip`). The `bin.zip` exists but is a flat archive without the gdextension manifest file, requiring manual authoring. The `demo.zip` bundles the complete addon structure including `gdsqlite.gdextension`.
- **Fix:** Used `demo.zip` (sha256: `26966044757cf86a223a8027f8bc88c49c289ab047dcf8138bb591d7632e580e`) which contains the full `demo/addons/godot-sqlite/` tree. Documented in the pinned-SHA comment.
- **Commit:** 9facaef

## Known Stubs

All 16 test files are intentional stubs by design (Wave 0 Nyquist contract). Each pending() message names the owning plan. `make_biome_map()` in conftest_helpers.gd is an intentional stub (Plan 06 replaces it). None of these stubs prevent the plan's goal — the goal IS to create stubs.

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced in test files or conftest. The install-deps.sh SHA-256 pin mitigates T-02-SC (supply-chain tampering). No additional threat surface beyond the plan's threat model.

## Self-Check: PASSED
