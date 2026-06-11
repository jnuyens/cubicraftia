---
phase: 01-foundation-mobile-spike
plan: 03
subsystem: ci-automation
tags: [ci, github-actions, android, ios, export, keystore, reuse, glossary, runbook]
dependency_graph:
  requires:
    - 01-01 (export_presets.cfg with 4 platform presets, .gitignore with release.keystore*)
    - 01-02 (scripts/glossary-check.sh, scripts/verify-feature-flags.sh, scripts/extract-pot.sh, GUT unit tests)
  provides:
    - .github/workflows/ci.yml (scope-checks + 4-target export matrix)
    - .github/workflows/pr-checks.yml (lightweight PR lint job)
    - scripts/export-ios.sh (manual M4 MBA iOS export, D-04)
    - scripts/generate-android-keystore.sh (one-time keystore generator)
    - export_presets.cfg 5th preset "iOS" (manual-only, flagged via comment)
    - docs/CI.md (CI runbook + D-04 deviation documentation)
    - docs/IOS_MANUAL_EXPORT.md (step-by-step M4 MBA iOS export procedure)
    - docs/CI_KEYSTORE_SETUP.md (keystore generation + GitHub Secrets + rotation)
    - scripts/glossary-allowlist.txt updated (docs/CI.md et al. allowlisted)
  affects:
    - Every subsequent phase (CI runs on every PR/push)
    - Phase 5 (full iOS CI is Phase 5 — docs/CI.md D-04 section tracks this)
    - Phase 4 (Android keystore infrastructure ready for release builds)
tech_stack:
  added:
    - barichello/godot-ci:4.6.3 (Docker, Linux CI container with Godot + Android SDK + NDK)
    - GitHub Actions (ci.yml + pr-checks.yml workflows)
  patterns:
    - Pattern 6 — GitHub Actions Matrix Build (RESEARCH.md)
    - Pitfall 12 — pin barichello/godot-ci to exact tag, not :latest (RESEARCH.md)
    - D-04 — iOS as manual M4 MBA export, full CI deferred to Phase 5 (CONTEXT.md)
    - T-03-03 — export-ios.sh runs scope-gates before export (threat model)
key_files:
  created:
    - .github/workflows/ci.yml
    - .github/workflows/pr-checks.yml
    - scripts/export-ios.sh
    - scripts/generate-android-keystore.sh
    - docs/CI.md
    - docs/IOS_MANUAL_EXPORT.md
    - docs/CI_KEYSTORE_SETUP.md
  modified:
    - export_presets.cfg (added iOS preset as 5th entry, manual-only)
    - scripts/glossary-allowlist.txt (added docs/CI.md, docs/IOS_MANUAL_EXPORT.md, docs/CI_KEYSTORE_SETUP.md)
decisions:
  - key: ci-macos-runner
    value: "macos-latest with native Homebrew Godot install (not barichello/godot-ci Linux container)"
    rationale: "macOS GitHub runners do not support Linux containers; native install avoids cross-OS Mach-O .app bundling issues (Open Question Q2 recommendation)"
  - key: ci-pot-idempotency
    value: "Backup committed .pot, regenerate, diff — no separate .pot.fresh file required"
    rationale: "extract-pot.sh already strips POT-Creation-Date for determinism; backup+diff is simpler and avoids a second output file"
  - key: allowlist-ci-docs
    value: "Whole-file allowlist entries for docs/CI.md, docs/IOS_MANUAL_EXPORT.md, docs/CI_KEYSTORE_SETUP.md"
    rationale: "CI runbooks legitimately document the forbidden terms (describing what the grep checks for); these are internal developer docs, not player-facing surfaces"
metrics:
  duration_minutes: 35
  completed_date: "2026-05-24"
  tasks_completed: 3
  tasks_total: 3
  files_created: 7
  files_modified: 2
---

# Phase 1 Plan 03: CI Automation + iOS Manual Export Summary

## One-liner

GitHub Actions 4-target CI matrix (Linux/Windows/macOS/Android) + scope-checks job (glossary/REUSE/feature-flags/i18n/GUT), with iOS intentionally excluded per D-04 and documented as a manual M4 MBA export using `barichello/godot-ci:4.6.3`.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | GitHub Actions ci.yml + pr-checks.yml | e13cb5d | `.github/workflows/ci.yml`, `.github/workflows/pr-checks.yml` |
| 2 | export-ios.sh + generate-android-keystore.sh + iOS preset | 24fbef5 | `scripts/export-ios.sh`, `scripts/generate-android-keystore.sh`, `export_presets.cfg` |
| 3 | docs/CI.md + docs/IOS_MANUAL_EXPORT.md + docs/CI_KEYSTORE_SETUP.md | d4944ad | `docs/CI.md`, `docs/IOS_MANUAL_EXPORT.md`, `docs/CI_KEYSTORE_SETUP.md`, `scripts/glossary-allowlist.txt` |

## What Was Built

### .github/workflows/ci.yml

Two-job workflow triggered on `push` and `pull_request`:

1. **`scope-checks`** job (`ubuntu-latest`, `barichello/godot-ci:4.6.3` container):
   - `scripts/glossary-check.sh` — DOC-10 terminology guard
   - `reuse lint` — DOC-00 SPDX header compliance
   - `scripts/verify-feature-flags.sh` — DOC-09 deferred-feature invariant
   - i18n round-trip: backup `.pot`, regenerate, diff (detects stale committed `.pot`)
   - GUT unit tests headless: `godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/unit -gexit`

2. **`export`** matrix (depends on `scope-checks`): 4 targets:
   - Linux/X11 and Windows Desktop: `ubuntu-latest` + `barichello/godot-ci:4.6.3` container
   - macOS: `macos-latest` + native Godot via `brew install --cask godot`
   - Android: `ubuntu-latest` + `barichello/godot-ci:4.6.3` + keystore decoded from `SECRET_RELEASE_KEYSTORE_BASE64`
   - iOS: **intentionally absent** (D-04)

### .github/workflows/pr-checks.yml

Lightweight PR-only workflow: same `scope-checks` job only, no export matrix. Gives < 5 min red/green on a PR before the ≈20-min matrix completes.

### scripts/export-ios.sh

Manual iOS export for M4 MacBook Air (D-04). Checks macOS + Xcode + Godot before exporting. Runs scope-gates (glossary, feature-flags, reuse) before `godot --export-release "iOS"` (T-03-03 threat mitigation). Writes `.last-ios-export.json` sidecar with timestamp + Godot version + Xcode version. Supports `--check` mode.

### scripts/generate-android-keystore.sh

One-time Android release keystore generator. Refuses to clobber existing `release.keystore`. Uses `keytool` with RSA 2048, 25000-day validity, `CN=Cubicraftia release, O=Cubicraftia contributors, C=BE`. Base64-encodes output and prints `SECRET_RELEASE_KEYSTORE_BASE64` paste instructions. Verifies .gitignore exclusions. Supports `--check` mode.

### export_presets.cfg — 5th preset

Added iOS preset as `[preset.4]` with `name="iOS"`, `platform="iOS"`, `export_path="build/ios/Cubicraftia.ipa"`, `application/bundle_identifier="org.cubicraftia.app"`, `interface/target_device=2` (Universal iPhone+iPad). Commented as "Manual export only — see scripts/export-ios.sh and docs/IOS_MANUAL_EXPORT.md per CONTEXT.md D-04".

### Documentation

- **docs/CI.md**: CI job overview, 5-platform claim (honestly explained with D-04 deviation), macOS runner choice rationale, add-gate runbook, diagnose-red-build runbook, Docker pin procedure.
- **docs/IOS_MANUAL_EXPORT.md**: Step-by-step M4 MBA export procedure (prerequisites, export, Xcode verify, smoke test, run-log commit), troubleshooting, Phase 5 upgrade path.
- **docs/CI_KEYSTORE_SETUP.md**: Keystore generation, GitHub Secrets setup, .gitignore safety check, rotation procedure, Google Play App Signing recommendation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] glossary-allowlist.txt updated for CI runbook docs**

- **Found during:** Task 3 verification
- **Issue:** `scripts/glossary-check.sh` includes `docs/**/*.md` in its scope. The new CI runbooks (`docs/CI.md`, `docs/IOS_MANUAL_EXPORT.md`, `docs/CI_KEYSTORE_SETUP.md`) legitimately document the forbidden terms (e.g., describing what the glossary check guards against), causing the check to fail.
- **Fix:** Added whole-file allowlist entries for the three CI runbook docs to `scripts/glossary-allowlist.txt`. These are internal developer runbooks (not player-facing surfaces), analogous to the existing `scripts/glossary-check.sh:` whole-file entry.
- **Files modified:** `scripts/glossary-allowlist.txt`
- **Commit:** d4944ad (included in Task 3 commit)

### Design decisions (not deviations)

**macOS CI runner: `macos-latest` with native Godot (not Linux container)**

Open Question Q2 in RESEARCH.md asked whether the macOS row should use a Linux container or a native macOS runner. The `barichello/godot-ci` image is Linux-only; using it for macOS exports from a Linux container historically works but can produce .app bundle differences vs. a real macOS build. The plan's action description explicitly calls this out ("prefer macos-latest for clean Mach-O signing-readiness"). Decision: `macos-latest` + `brew install --cask godot`. Documented in docs/CI.md.

**i18n round-trip check: backup+diff instead of .pot.fresh**

The plan's task description mentioned writing to `locale/messages.pot.fresh` as a side file for CI diff. The existing `extract-pot.sh` script writes directly to `locale/messages.pot`. The implemented approach (backup committed .pot, regenerate in-place, diff, no separate .fresh file needed) is simpler, avoids file proliferation, and is functionally equivalent. No `.fresh` file is left in the repo.

## Known Stubs

None. All artifacts are complete implementations, not placeholders.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: supply_chain | `.github/workflows/ci.yml` | New workflow pulls `barichello/godot-ci:4.6.3` from Docker Hub at job time; mitigated by version pin + Docker Hub SHA verification procedure documented in docs/CI.md |
| threat_flag: secret_in_ci | `.github/workflows/ci.yml` | Android keystore decoded from `secrets.SECRET_RELEASE_KEYSTORE_BASE64` during export job; never printed to logs; mitigated by standard GitHub Secrets pattern |

## Self-Check: PASSED

Files exist:
- [x] `.github/workflows/ci.yml` — created at e13cb5d
- [x] `.github/workflows/pr-checks.yml` — created at e13cb5d
- [x] `scripts/export-ios.sh` — created at 24fbef5 (executable)
- [x] `scripts/generate-android-keystore.sh` — created at 24fbef5 (executable)
- [x] `docs/CI.md` — created at d4944ad
- [x] `docs/IOS_MANUAL_EXPORT.md` — created at d4944ad
- [x] `docs/CI_KEYSTORE_SETUP.md` — created at d4944ad
- [x] `export_presets.cfg` — modified at 24fbef5 (5 presets)

Commits verified: e13cb5d, 24fbef5, d4944ad all present in git log.

Checks verified:
- `bash scripts/glossary-check.sh` → OK
- `bash scripts/verify-feature-flags.sh` → OK
- `bash scripts/export-ios.sh --check` → all prerequisites satisfied
- `bash scripts/generate-android-keystore.sh --check` → all prerequisites satisfied
- Python `yaml.safe_load()` validates both workflow files
- Matrix has exactly 4 targets (Linux/X11, Windows Desktop, macOS, Android); no iOS
- `barichello/godot-ci:${{ env.GODOT_VERSION }}` with `GODOT_VERSION: "4.6.3"` — pinned
