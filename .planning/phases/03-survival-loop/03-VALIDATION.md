---
phase: 3
slug: survival-loop
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-27
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from `03-RESEARCH.md` `## Validation Architecture`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | GUT (Godot Unit Test) v9.x — installed in Phase 2 Plan 02-02 |
| **Config file** | `addons/gut/` (GUT plugin), per-project GUT settings from Plan 02-02 |
| **Quick run command** | `godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests -gtest=test_<module>.gd -gexit` |
| **Full suite command** | `godot --headless --script addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` |
| **Estimated runtime** | Quick: ~5–15 s per file. Full: ~60–120 s headless (excluding mobile benchmark). |

---

## Sampling Rate

- **After every task commit:** Run quick command for the touched module's `test_<module>.gd`.
- **After every plan wave:** Run full suite headless + Tier-3 benchmark smoke (~5-minute mobile run with 10 hostiles).
- **Before `/gsd:verify-work`:** Full suite must be green; Motorola 30-minute combat benchmark complete; all manual UAT rows ticked.
- **Max feedback latency:** ~15 s per task commit; ~120 s per wave merge (headless).

---

## Per-Task Verification Map

> Final task IDs assigned during planning. The rows below are derived from `RESEARCH.md` SC#1..SC#5 mapping. Planner fills `Task ID`, `Plan`, `Wave`, `Threat Ref` columns from PLAN.md frontmatter.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-02 | 03-02 | 0 | DOC-04 SC#1 — 6×8 grid, 64/stack, shift-split, single-take, hotbar=row-0 | — | Inventory mutations are event-sourced; no raw global state | unit | `gut_cmdln … -gtest=test_inventory_grid.gd -gexit` | ✅ W0 | ✅ |
| 03-02 | 03-02 | 0 | DOC-04 SC#1 — DroppedItem `picked_up` signal → Inventory ADD | — | N/A | integration | `gut_cmdln … -gtest=test_pickup_integration.gd -gexit` | ✅ W0 | ✅ |
| 03-02 | 03-02 | 0 | DOC-04 SC#1 — 2-Cubicraftia-day despawn tick math | — | Despawn timer reads authoritative WorldClock ticks | unit | `gut_cmdln … -gtest=test_despawn_timer.gd -gexit` | ✅ W0 | ✅ |
| 03-06 | 03-06 | 0 | DOC-04 SC#2 — 5 chest types, slot counts 48/48/54/60/72, 4 key types, persistent-unlock | — | Chest contents queries are parameterised (no SQL concat) | unit | `gut_cmdln … -gtest=test_chest_state.gd -gexit` | ✅ W0 | ✅ |
| 03-06 | 03-06 | 0 | DOC-04 SC#2 — Wrong-tier key rejected | — | Lock validation enforces tier match | unit | `gut_cmdln … -gtest=test_chest_unlock_validation.gd -gexit` | ✅ W0 | ✅ |
| 03-06 | 03-06 | 0 | DOC-04 SC#2 — Double-chest combine + split-on-break | — | N/A | unit | `gut_cmdln … -gtest=test_double_chest.gd -gexit` | ✅ W0 | ✅ |
| 03-07a | 03-07a | 0 | DOC-04 SC#3 — 10 v1 recipes produce expected outputs | — | Recipe def_id references validated at load | unit | `gut_cmdln … -gtest=test_recipes.gd -gexit` | ✅ W0 | ✅ |
| 03-07a | 03-07a | 0 | DOC-04 SC#3 — Recipe-book progressive reveal | — | Corrupted recipes-known blob fails shape check → log + ignore | unit | `gut_cmdln … -gtest=test_recipe_book_reveal.gd -gexit` | ✅ W0 | ✅ |
| 03-03 | 03-03 | 0 | DOC-05 SC#4 — Sandbox suppresses creatures; survival enables; ~10/chunk cap; bed-bubble blocks spawn AND ghost; light-level gate | — | N/A | unit | `gut_cmdln … -gtest=test_spawning_rules.gd -gexit` | ✅ W0 | ✅ |
| 03-10 | 03-10 | 0 | DOC-05 SC#4 — Cube slime tier-split on defeat | — | N/A | integration | `gut_cmdln … -gtest=test_slime_split.gd -gexit` | ✅ W0 | ✅ |
| 03-10 | 03-10 | 0 | DOC-05 SC#4 — Vampire→bat transform at ≤2 HP; HP carries; invuln window | — | N/A | integration | `gut_cmdln … -gtest=test_vampire_transform.gd -gexit` | ✅ W0 | ✅ |
| 03-10 | 03-10 | 0 | DOC-05 SC#4 — Ghost wall-pass + bed-bubble repel | — | N/A | smoke (manual) | Manual: spawn ghost in test world; verify wall-pass AND bubble-repel | ✅ W0 | 🔵 deferred (UAT row 1) |
| 03-04 | 03-04 | 0 | DOC-05 SC#5 — HP=0 → DEATH_DROP; death-pile; 3 s fade-to-respawn; respawn at bed/spawn; void-fall at surface | — | Death state mutations event-sourced (replicable in Phase 4) | unit + integration | `gut_cmdln … -gtest=test_death_respawn.gd -gexit` | ✅ W0 | ✅ |
| 03-11 | 03-11 | 0 | DOC-05 SC#5 — Starter chest + bed at survival world spawn (D-15 verbatim) | — | N/A | unit | `gut_cmdln … -gtest=test_starter_kit.gd -gexit` | ✅ W0 | ✅ |
| 03-09 | 03-09 | 0 | DOC-05 D-13 — Tom Yum fire-breath VFX (~0.3 s flame, no damage) | — | No-damage invariant on cosmetic VFX | smoke (manual) | Manual: eat Tom Yum in test world; verify ~0.3 s flame puff, no HP/light/damage change | ✅ W0 | 🔵 deferred (UAT row 2) |
| 03-01 | 03-01 | 0 | Save state — Schema migration v1→v2 idempotent | T-MIG-01 | Migration wrapped in BEGIN/COMMIT; bak.1/bak.2/bak.3 rolling backup preserved | integration | `gut_cmdln … -gtest=test_schema_migration.gd -gexit` | ✅ W0 | ✅ |
| 03-08a | 03-08a | 0 | Save state — Loot roll determinism (seeded weighted roll) | — | All rolled def_ids validated via BrickRegistry; null defs push_warning + skip | unit | `gut_cmdln … -gtest=test_loot_roll.gd -gexit` | ✅ W0 | ✅ |
| 03-03 | 03-03 | 0 | DOC-05 D-12 — WorldClock 10× multiplier + cancellation conditions | — | N/A | unit | `gut_cmdln … -gtest=test_sleep_lapse.gd -gexit` | ✅ W0 | ✅ |
| 03-02 | 03-02 | 0 | Save state — Inventory persists across force-quit (no clean close) | T-MIG-02 | Atomic-rename writes survive force-quit | manual UAT | UAT row: force-quit during inventory mutation; verify on reload | ✅ W0 | 🔵 deferred (UAT row 3) |
| 03-11 | 03-11 | 0 | Mobile perf — Tier-3 Motorola sustains §7.2 frame budget @ 10 hostiles + death-pile + sleep lapse | — | N/A | manual UAT | `bash scripts/run-benchmark.sh combat_scene` on Motorola XT2016-1 | ✅ W0 | 🔵 deferred (UAT row 4) |
| 03-11 | 03-11 | 0 | DOC-05 D-12 — 10× sleep lapse feel (5-6 s sweep; camera unchanged; HP restores; Tier-3 fade fallback) | — | N/A | smoke (manual) | Manual: right-click bed at night; verify sky sweep, CHASE cam, HP restore, Tier-3 fallback | ✅ W0 | 🔵 deferred (UAT row 5) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Wave 0 of Phase 3 ships the test scaffolding **and** the schema migration + Inventory autoload stub (per RESEARCH.md recommendation). Files to create:

- [x] `tests/test_inventory_grid.gd` — 6×8 grid, stack math, shift-split, single-take
- [x] `tests/test_pickup_integration.gd` — DroppedItem `picked_up` → Inventory ADD
- [x] `tests/test_despawn_timer.gd` — 2-Cubicraftia-day despawn math
- [x] `tests/test_chest_state.gd` — 5 chest types, 4 keys, slot counts, unlock semantics
- [x] `tests/test_chest_unlock_validation.gd` — wrong-tier-key rejection
- [x] `tests/test_double_chest.gd` — double-chest combine + split-on-break
- [x] `tests/test_recipes.gd` — 10 v1 recipes produce expected outputs
- [x] `tests/test_recipe_book_reveal.gd` — has-all-ingredients OR first-craft-unlocks
- [x] `tests/test_spawning_rules.gd` — light gate + 10/chunk cap + bed-bubble
- [x] `tests/test_slime_split.gd` — LARGE → 3 MEDIUM → 2 SMALL each → loot only
- [x] `tests/test_vampire_transform.gd` — transform at ≤2 HP; HP carries; 0.3 s invuln window
- [x] `tests/test_death_respawn.gd` — DEATH_DROP event; death-pile spawn; respawn at bed/spawn; void-fall surface drop
- [x] `tests/test_starter_kit.gd` — survival world opens with chest + bed at origin; contents match D-15
- [x] `tests/test_schema_migration.gd` — v1 DB opens, migrates to v2, all old data intact
- [x] `tests/test_loot_roll.gd` — deterministic weighted roll math
- [x] `tests/test_sleep_lapse.gd` — WorldClock 10× multiplier + cancellation conditions
- [x] `tests/conftest_phase3.gd` — shared fixtures (open_temp_world, populate_inventory, spawn_hostile, etc.)
- [x] `tests/scenes/combat_bench.tscn` — 10-hostile mobile benchmark scene (Motorola perf gate)

*Framework install: none — GUT already in repo from Plan 02-02.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Ghost wall-pass + bed-bubble repel | DOC-05 SC#4 | Requires visible voxel collision behaviour; physics-state assertions are brittle vs visual confirmation | Open test world; spawn ghost; verify it passes through a wall; place a bed; verify ghost bounces off the 8 m bubble with shimmer + chime |
| Tom Yum fire-breath VFX | DOC-05 D-13 | Cosmetic VFX (~0.3 s) is feel/timing, not state | Open test world; eat Tom Yum from inventory; verify ~0.3 s flame puff at builder mouth; verify no HP change beyond standard cooked-food heal, no light source, no damage applied |
| Inventory persists across force-quit | DOC-04 SC#1 (save robustness) | Cannot force-quit reliably from headless GUT | Open world; mutate inventory; force-quit Godot (kill -9); reopen world; verify inventory state matches last commit-point |
| Tier-3 Motorola perf @ 10 hostiles + death-pile + sleep lapse | DOC-05 §7.2 | Real-device frame timings — emulator skews are too high | `bash scripts/run-benchmark.sh combat_scene` on Motorola XT2016-1; verify §7.2 frame budget held during combat + death-pile spawn + 10× sleep lapse |
| 10× sleep lapse feel | DOC-05 D-12 | Visual feel (~5-6 s sweep of stars/dawn) is judgement-call, not a number | Open survival test world at night; right-click bed; verify world-clock + sky simulation accelerate ~10× for ~5-6 s; verify ambient sound shifts; verify CHASE camera stays put |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 15 s per task / < 120 s per wave
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved (2026-05-27)

---

## Approval

Approved by: jnuyens@gmail.com
Date: 2026-05-27
Status: all GUT tests green; 5 manual UAT rows deferred per Phase 2 precedent; nyquist_compliant flag flipped to true.
