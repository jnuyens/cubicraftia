---
phase: 07-asset-integration
plan: "01"
subsystem: testing
tags: [gdscript, gut, file-audit, asset-pipeline, godot]

requires:
  - phase: 06-title-avatar-ftue
    provides: "Shipped UI scenes with res://...png references including known stubs"

provides:
  - "Wave 0 headless GUT audit test asserting no PNG reference in shipped scenes is < 200 B"
  - "Exclusion list covering animation POC demo scenes, addons/, and tests/"
  - "RED state enumeration of all known stub/path-gap failures for Phase 7 follow-on plans"

affects:
  - "07-asset-integration/07-02-PLAN.md (hp_bar heart path fix must turn these GREEN)"
  - "07-asset-integration/07-03-PLAN.md (stub replacements must turn those GREEN)"
  - "07-asset-integration/07-04-PLAN.md (final integration; full suite must be GREEN)"

tech-stack:
  added: []
  patterns:
    - "ASSET-07 audit: FileAccess.get_size(res://path) > MIN_BYTES headless check"
    - "Exclusion: begins_with() for res:// prefixes, contains() for mid-path demo-scene fragments"
    - "Red/Green wave contract: audit test added first (Wave 0), goes GREEN after asset work (Waves 1-2)"

key-files:
  created:
    - tests/unit/test_asset_stub_audit.gd
  modified: []

key-decisions:
  - "wave-0-stub-audit-red-by-design: test_asset_stub_audit.gd is intentionally RED on commit; failure output is the specification for subsequent Phase 7 plans"
  - "exclude-demo-contains-not-prefix: demo scene fragments (minifigure_animator_demo etc.) matched via String.contains() not begins_with() because they appear mid-path, not at path start"
  - "200-byte-threshold: 68 B stubs are well below 200 B; real art is always several KB; threshold provides ample margin without requiring exact size knowledge"

patterns-established:
  - "Pattern: Wave 0 RED harness — add GUT audit test before asset work so the test enforces constraints from day one of integration work"
  - "Pattern: _is_excluded() helper separates res:// begins_with from mid-path contains checks for readable exclusion logic"

requirements-completed:
  - ASSET-07

duration: 1min
completed: "2026-06-01"
---

# Phase 7 Plan 01: Asset Stub Audit Harness Summary

**Headless GUT stub-detection harness scanning all shipped .tscn/.gd under res://src for sub-200 B PNG references, correctly red on Wave 0 with 14 failures mapping to all known Phase 7 gaps**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-06-01T19:47:22Z
- **Completed:** 2026-06-01T19:48:55Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Created `tests/unit/test_asset_stub_audit.gd` (133 lines) — Wave 0 RED harness for ASSET-07
- Test runs headlessly via GUT, finds no parse errors, and reports exactly the expected failures
- Correctly excludes animation POC demo scenes (`minifigure_animator_demo`, `shader_wobble_animator`, `quadruped_poc`) and test/addons paths
- Enumerated 14 stub/path-gap failures covering all known Phase 7 work: ftue_arrow wrong path (-1 B), hp_bar heart icons wrong names (-1 B each), world_thumb_placeholder (68 B), avatar presets (68 B each), title_bg_bricks dead path (-1 B), missing icon paths (-1 B each)

## Task Commits

1. **Task 1: Write test_asset_stub_audit.gd** — `788586b` (test)

## Files Created/Modified

- `tests/unit/test_asset_stub_audit.gd` — Headless GUT audit test; scans res://src .tscn/.gd for PNG references and asserts FileAccess.get_size() > 200 B

## Decisions Made

- `wave-0-stub-audit-red-by-design`: test is intentionally RED on commit — the failure report is the specification driving Plans 02-04
- `exclude-demo-contains-not-prefix`: demo scene names appear mid-path; used `String.contains()` rather than `begins_with()` for those fragments
- `200-byte-threshold`: 68 B stubs are well below 200 B; real committed art is always several KB; no exact size knowledge needed

## Deviations from Plan

None — plan executed exactly as written.

The test was run and confirmed to be in RED state with exactly the expected stub failures. This is correct Wave 0 behaviour per plan spec.

## Issues Encountered

GUT printed `"Could not find script: test_asset_stub_audit.gd"` at the very start of the run (before script discovery completes). This is a known GUT 9.x startup log artifact — the script is discovered and executed correctly moments later. No impact on test results.

## Stub Scan

No stubs in the implementation. The word "stub" in `test_asset_stub_audit.gd` appears only in comments documenting the known stubs in other files that this test is designed to catch.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced. The test only reads file sizes from `res://` using `FileAccess.get_size()` (read-only, dev-only, no PII or secrets).

## Next Phase Readiness

- `tests/unit/test_asset_stub_audit.gd` is the gate for all subsequent Phase 7 plans
- Plan 02 must fix the hp_bar heart icon path constants and the ftue_arrow path gap to turn those 5 failures GREEN
- Plans 03-04 replace the 68 B stub PNG files with real art to turn the remaining failures GREEN
- Phase 7 gate: full GUT suite must be GREEN before `/gsd:verify-work`

## Self-Check: PASSED

- File `tests/unit/test_asset_stub_audit.gd` — FOUND
- Commit `788586b` — FOUND (`git log --oneline | grep 788586b`)

---
*Phase: 07-asset-integration*
*Completed: 2026-06-01*
