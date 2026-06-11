---
phase: 01-foundation-mobile-spike
plan: 02
subsystem: bootstrap-autoloads-ci-gates
tags: [features, iap, translations, toasts, thermal, ci, gut, glossary, i18n]
dependency_graph:
  requires:
    - 01-01 (project.godot, folder tree, locale stubs)
  provides:
    - Features singleton with 18 §9 deferred flags (all false)
    - Iap stub with typed empty registry (DOC-00)
    - Translations.t() wrapper with prefix assertion (DOC-10)
    - Toasts.show() signal API for Plan 06 renderer
    - ThermalProbe CSV sampler with Plan 07 provider hook
    - scripts/glossary-check.sh DOC-10 CI gate
    - scripts/verify-feature-flags.sh DOC-09 CI gate
    - scripts/extract-pot.sh i18n extraction (idempotent)
    - scripts/analyse-benchmark.sh §7.2 worst-window min-FPS gate
    - GUT v9.4.0 installed; 4 unit tests all passing
    - locale/en.po seed keys (toast, IAP, about, device, common)
  affects:
    - Plans 04-07 (consume Features.is_enabled, Iap, Translations, Toasts, ThermalProbe)
    - Plan 03 (CI matrix uses glossary-check + verify-feature-flags)
    - Plan 06 (wires Toasts scene renderer to toast_requested signal)
    - Plan 07 (calls ThermalProbe.set_thermal_provider() with Kotlin plugin)
tech_stack:
  added:
    - GUT v9.4.0 (bitwes/Gut, MIT) — GDScript unit test framework
  patterns:
    - Pattern 1 — Feature-Flag Singleton on ProjectSettings (RESEARCH.md)
    - IAP stub typed empty registry (RESEARCH.md Code Examples)
    - tr() explicit wrapper over auto_translate (Pitfall 7 avoidance)
    - Toast signal API decoupled from scene renderer (Plan 06 dependency injection)
    - Worst-30s-window sliding min-FPS for sustained benchmark (Pitfall 9 / D-02)
key_files:
  created:
    - src/autoload/features.gd (Features singleton — 18 §9 flags, is_enabled())
    - src/autoload/iap_stub.gd (Iap stub — is_available/purchase/get_products)
    - src/autoload/translations.gd (Translations.t() with prefix assertion)
    - src/autoload/toasts.gd (Toasts.show() + toast_requested signal)
    - src/autoload/thermal_probe.gd (ThermalProbe CSV sampler + provider hook)
    - scripts/glossary-check.sh (DOC-10 CI grep with Cyrillic homoglyph defense)
    - scripts/glossary-allowlist.txt (README.md + locale/en.po + script self-entries)
    - scripts/verify-feature-flags.sh (DOC-09 invariant; also checks override.cfg)
    - scripts/extract-pot.sh (xgettext-based, strips POT-Creation-Date, idempotent)
    - scripts/analyse-benchmark.sh (sliding window min-FPS per Pitfall 9 / D-02)
    - tests/gut_config.cfg (GUT config — tests/unit + tests/integration)
    - tests/conftest_helpers.gd (find_tscn_files, read_text_file, get_project_name)
    - tests/unit/test_naming.gd (DOC-00 — project name lock, 3 tests)
    - tests/unit/test_feature_flags.gd (DOC-09 — all 18 flags false, 7 tests)
    - tests/unit/test_iap_stub.gd (DOC-00 — IAP stub contracts, 5 tests)
    - tests/unit/test_no_hardcoded_strings.gd (DOC-10 — i18n hygiene, 2 tests)
    - addons/gut/ (GUT v9.4.0 — 80+ files from bitwes/Gut at tag v9.4.0)
    - addons/gut/.gut-installed.marker (CI sentinel for GUT install verification)
  modified:
    - project.godot ([autoload] section with 5 autoloads + [cubicraftia] block with 18 flags)
    - locale/en.po (seed keys: toast.*, ui.settings.iap.*, ui.about.*, ui.device.*, ui.common.*)
    - locale/messages.pot (empty — no tr() call sites yet; idempotent extraction confirmed)
    - .gitignore (added *.uid — Godot 4.x generated resource UID files)
    - scripts/glossary-check.sh (bugfix iteration — see Deviations)
    - scripts/glossary-allowlist.txt (comment lines removed to prevent false-positive matching)
decisions:
  - key: docs-md-18-flags
    what: Used 18 feature flag keys from DOCS.md §9, not 19 from RESEARCH.md Pattern 1
    why: DOCS.md §9 collapses "snow, thunderstorms, lightning" into one row (18); RESEARCH.md's draft had 19 by splitting them. DOCS.md is authoritative per DDD mode.
  - key: gd-uid-gitignored
    what: Added *.uid to .gitignore
    why: Godot 4.x generates .gd.uid files as resource UID cache; they are build artifacts and should not be committed.
  - key: en-po-seed-keys
    what: Added bootstrap translation keys to locale/en.po directly (not via extract-pot.sh)
    why: No tr() call sites exist in src/ at Plan 02 time; seed keys are required for the autoload contracts. extract-pot.sh will populate messages.pot incrementally as Plans 04-07 add tr() call sites.
  - key: allowlist-no-comments
    what: glossary-allowlist.txt contains no comment lines
    why: grep -F -f treats every line as a fixed-string pattern; comment lines (e.g. bare '#') were substrings of violation lines, causing false-negative matches. The allowlist must contain only the exact patterns to permit.
  - key: glossary-check-dot-root
    what: glossary-check.sh uses '.' as the rg search root (not explicit file list)
    why: When --glob flags are combined with explicit path arguments, rg only applies globs to directory arguments, not file arguments. Using '.' ensures globs activate for all subdirectories including locale/.
metrics:
  duration: ~35 minutes
  completed_date: 2026-05-24
  tasks_completed: 3
  files_created: 24
  files_modified: 5
---

# Phase 01 Plan 02: Bootstrap Autoloads + CI Gates Summary

**One-liner:** Five autoloads (Features/Iap/Translations/Toasts/ThermalProbe) registered in project.godot with 18 §9 deferred flags=false, four CI gate scripts, and GUT v9.4.0 with 17 passing unit tests covering DOC-00/DOC-09/DOC-10.

## Tasks Completed

| Task | Description | Commit |
|------|-------------|--------|
| 1 | CI gate scripts: glossary-check, verify-feature-flags, extract-pot, analyse-benchmark + allowlist | d2006dc |
| 2 | Five autoloads + project.godot autoload registrations + 18 feature flags | 41993ce |
| 3 | GUT v9.4.0 install + 4 unit tests (naming/flags/iap/i18n) + gut_config.cfg | e6317c6 |

## Verification Results

- `bash scripts/glossary-check.sh` exits 0: OK
- `bash scripts/verify-feature-flags.sh` exits 0: OK
- `bash scripts/extract-pot.sh` (run twice, sha256sum matches): OK — idempotent
- `grep -c 'features/' project.godot` = 18: OK
- `godot --headless --quit-after 1 --path .` — exits with "no main scene" only (expected): OK
- `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests/unit -gexit`: 4 scripts, 17 tests, 17 passing, 0 failures: OK
- `reuse lint` exits 0 (156 files all compliant): OK
- `bash scripts/analyse-benchmark.sh /tmp/test.csv --target-fps 25` with constant 30fps CSV: exit 0: OK

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] glossary-check.sh grep used explicit file paths instead of '.' as root**
- **Found during:** Task 1 verification — rg with --glob flags requires a directory root to activate globs; explicit file paths in the arg list bypass --glob application.
- **Issue:** `rg ... --glob 'locale/**/*.po' README.md project.godot` did not scan locale/ because --glob only applies to directory roots. Violation detection missed en.po entries.
- **Fix:** Changed the search command to use `rg ... --glob 'locale/**/*.po' --glob 'README.md' --glob 'project.godot' .` — using `.` as the root so all --glob patterns activate.
- **Files modified:** scripts/glossary-check.sh
- **Commit:** 41993ce (included in Task 2 autoload commit as the corrected version)

**2. [Rule 1 - Bug] glossary-allowlist.txt comment lines caused false-negative filtering**
- **Found during:** Task 1 verification — testing violation detection with a temporary src/*.gd file showed glossary-check.sh passed when it should have failed.
- **Issue:** The allowlist file contained comment lines starting with `#`. grep -v -F -f treats every line as a fixed-string pattern, so the bare `#` line matched any violation line containing `#` (e.g. a GDScript comment). This silently suppressed real violations.
- **Fix:** Removed all comment lines from scripts/glossary-allowlist.txt, keeping only the exact match patterns.
- **Files modified:** scripts/glossary-allowlist.txt
- **Commit:** 41993ce

**3. [Rule 1 - Bug] GDScript parse error in translations.gd multi-line push_error() call**
- **Found during:** Task 3 verification — GUT test run reported "Parse Error: Expected closing ')'" at translations.gd:49.
- **Issue:** GDScript 4 does not support implicit string concatenation across lines (without `\` or temp variable) inside function call arguments. The `push_error("..." % x + "...")` pattern across three lines caused a parse error.
- **Fix:** Moved the concatenation to a `var err_msg` assignment before the `push_error()` call.
- **Files modified:** src/autoload/translations.gd
- **Commit:** e6317c6

**4. [Rule 1 - Bug] Same multi-line concatenation parse error in test_no_hardcoded_strings.gd**
- **Found during:** Task 3 verification — GUT reported the same parse error pattern in the test file.
- **Issue:** Same as above — multi-line string concatenation inside `fail_test()` arguments.
- **Fix:** Extracted the message into a `var fail_msg` variable.
- **Files modified:** tests/unit/test_no_hardcoded_strings.gd
- **Commit:** e6317c6

**5. [Rule 2 - Missing] *.uid added to .gitignore**
- **Found during:** Task 3 commit — git status showed `?? src/autoload/features.gd.uid` etc. (5 Godot-generated UID files).
- **Issue:** Godot 4.x generates `.gd.uid` resource UID cache files that are build artifacts and should not be committed. They were not in .gitignore.
- **Fix:** Added `*.uid` to .gitignore.
- **Files modified:** .gitignore
- **Commit:** e6317c6

### Architecture Notes

**RESEARCH.md Pattern 1 vs DOCS.md §9 flag count:** RESEARCH.md listed 19 feature flag keys by splitting "snow_weather" and "thunderstorms" into separate entries. DOCS.md §9 row 576 combines them into "Snow, thunderstorms, lightning" (one row). Per DDD mode, DOCS.md is authoritative. The features.gd implementation uses 18 keys and documents this deviation in a comment header.

**locale/messages.pot is empty at Plan 02:** The `extract-pot.sh` script produces an empty .pot file because no `tr()` call sites exist in src/ yet (the autoloads define the API but don't call it). The en.po seed keys were added directly as bootstrap strings. This is correct Wave 0 behaviour; Plans 04-07 will add tr() call sites and the .pot will populate.

**locale/en.po contains LEGO Group in the disclaimer msgstr:** The `ui.about.disclaimer` key's English translation contains "LEGO Group" — the only permitted player-facing use. This is allowlisted in `scripts/glossary-allowlist.txt` via `locale/en.po:` prefix matching (any line in en.po is permitted). This is correct per UI-SPEC.md Copywriting Contract.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| ThermalProbe._thermal_provider = null | src/autoload/thermal_probe.gd | Plan 07 injects the Android JNI provider via set_thermal_provider(). Until then, readings return NaN/-1. |
| ThermalProbe._detect_probe_path() returns "unavailable" | src/autoload/thermal_probe.gd | sysfs fallback path detection deferred to Plan 07 per comment. |
| features.gd has no build_palette_enabled in ProjectSettings | src/autoload/features.gd | build_palette_enabled is exposed as a const bool, not as a ProjectSettings key. This is intentional — it's not a §9 row. Phase 2 flips it. |
| locale/messages.pot is empty | locale/messages.pot | No tr() call sites in src/ yet. Populate incrementally as Plans 04-07 add UI scenes. |

All stubs are intentional and do not prevent this plan's goal (bootstrap scaffolding). The ThermalProbe and feature-flag stubs are the explicit Phase 1 contracts that later plans extend.

## Threat Flags

None. This plan creates no network endpoints, auth paths, file access patterns, or schema changes at trust boundaries. CI scripts are read-only repo greps. Autoloads read-only from ProjectSettings at boot.

## Self-Check: PASSED

Files exist:
- scripts/glossary-check.sh: FOUND
- scripts/glossary-allowlist.txt: FOUND
- scripts/verify-feature-flags.sh: FOUND
- scripts/extract-pot.sh: FOUND
- scripts/analyse-benchmark.sh: FOUND
- src/autoload/features.gd: FOUND
- src/autoload/iap_stub.gd: FOUND
- src/autoload/translations.gd: FOUND
- src/autoload/toasts.gd: FOUND
- src/autoload/thermal_probe.gd: FOUND
- tests/gut_config.cfg: FOUND
- tests/conftest_helpers.gd: FOUND
- tests/unit/test_naming.gd: FOUND
- tests/unit/test_feature_flags.gd: FOUND
- tests/unit/test_iap_stub.gd: FOUND
- tests/unit/test_no_hardcoded_strings.gd: FOUND
- addons/gut/gut_cmdln.gd: FOUND
- addons/gut/.gut-installed.marker: FOUND

Commits exist:
- d2006dc: FOUND (Task 1 — CI gate scripts)
- 41993ce: FOUND (Task 2 — autoloads)
- e6317c6: FOUND (Task 3 — GUT tests)
