---
phase: 08-creature-builder-animation
recorded: 2026-06-09
godot_version: 4.6.3.stable.official.7d41c59c4
gut_version: 9.4.0
result: PASS
---

# Phase 8 — Animation Test Results

Run date: 2026-06-09
Godot version: 4.6.3.stable.official.7d41c59c4 (from `godot --version`)
GUT version: 9.4.0
Run host: headless (no display, no GPU)


## Requirement-to-Test Mapping

| Requirement | Test File | Tests Passing | Tests Pending | Tests Failing | Notes |
|-------------|-----------|:---:|:---:|:---:|-------|
| ANIM-01 (shader wobble / soft-body animator) | tests/unit/test_anim_shader_wobble.gd | 4 | 1 | 0 | 1 display/GPU-gated wiring test |
| ANIM-02 (quadruped / panda animator) | tests/unit/test_anim_quadruped.gd | 4 | 1 | 0 | 1 display-gated rig-build test |
| ANIM-03 (minifigure rigid-piece rig) | tests/unit/test_anim_minifigure.gd | 7 | 1 | 0 | 1 display-gated rig-build test |
| ANIM-04 (builder speed→gait mapping) | tests/unit/test_anim_minifigure.gd | 7 | 1 | 0 | Same file as ANIM-03; gait logic tests all pass |
| ANIM-05 (all 5 hostile animator wiring) | tests/unit/test_anim_hostiles.gd | 10 | 0 | 0 | All pass; no display-gated tests |

Animation subset totals (4 files, prefix test_anim_): 28 tests — 25 passing, 3 pending, 0 failing.


## Full Unit Suite Totals

Run command: godot --headless --script addons/gut/gut_cmdln.gd -- -gdir=res://tests/unit -gexit

Scripts: 65
Tests: 331
  Passing: 312
  Risky/Pending: 19
  Failing: 0
Asserts: 1697
Time: ~25 seconds

The full unit suite shows zero failing assertions. This matches the planner baseline captured on 2026-06-09 (312 passing / 19 risky-pending / 0 failing). No animation-introduced regression was found.


## Pending Tests — Rationale

The 3 animation-specific pending tests are by-design display-gated wiring tests per the headless strategy documented in 08-VALIDATION.md ("Headless test strategy"). Each is guarded with:

    if DisplayServer.get_name() == "headless":
        pending("requires display for rig .glb load")
        return

These tests verify that the animators' `_ready()` method adds child pivot nodes after loading the rig `.glb` — an operation that requires a GPU and display context. They are not failures. A pending test is not a red test.

Affected tests:
- test_anim_minifigure.gd: test_in_tree_ready_builds_rig
- test_anim_quadruped.gd: test_in_tree_ready_builds_rig
- test_anim_shader_wobble.gd: test_in_tree_ready_attaches_visual


## ANIM-06 — Out of Scope for This Plan

Visual in-world confirmation (creatures actually wobbling/walking on screen) and the frame-budget check are owned by the ANIM-06 plan (08-02), not by headless CI. ANIM-06 requires a real GPU and reference Tier-3 device. This result file evidences ANIM-01 through ANIM-05 only.
