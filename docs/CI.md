<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Cubicraftia CI Runbook

## Overview

Two GitHub Actions workflows gate every commit and pull request:

| Workflow | File | Triggers | Purpose |
|----------|------|----------|---------|
| `ci` | `.github/workflows/ci.yml` | `push` (any branch), `pull_request` | Scope-checks + 4-platform export matrix |
| `pr-checks` | `.github/workflows/pr-checks.yml` | `pull_request` | Fast-path scope-checks only (no exports) |

PRs trigger both workflows in parallel — `pr-checks` gives fast red/green signal (< 5 min) while `ci` runs the full export matrix (≈ 20 min) concurrently.

---

## What runs on every PR / push

### Job 1: `scope-checks`

Runs on `ubuntu-latest` inside the `barichello/godot-ci:4.6.3` container.

| Step | Script / Command | What it gates |
|------|-----------------|---------------|
| Glossary check | `bash scripts/glossary-check.sh` | DOC-10 — "Lego", "LEGO", "minifig", "Minecraft" must not appear in player-facing surfaces |
| REUSE / SPDX lint | `reuse lint` | DOC-00 — every source file must carry a GPL-3.0-or-later SPDX header |
| Feature-flag invariant | `bash scripts/verify-feature-flags.sh` | DOC-09 — every `cubicraftia/features/*` flag must be `false` in `project.godot` |
| i18n round-trip | `bash scripts/extract-pot.sh` + diff | The committed `locale/messages.pot` is not stale; running the extractor again produces an identical file |
| GUT unit tests | `godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/unit -gexit` | All GDScript unit tests pass |

### Job 2: `export` (matrix)

Depends on `scope-checks`. Runs the 4 CI platform exports:

| Platform | Runner | Method |
|----------|--------|--------|
| Linux/X11 | `ubuntu-latest` | `barichello/godot-ci:4.6.3` container |
| Windows Desktop | `ubuntu-latest` | `barichello/godot-ci:4.6.3` container |
| macOS | `macos-latest` | Native Godot install via `brew install --cask godot` |
| Android | `ubuntu-latest` | `barichello/godot-ci:4.6.3` container; keystore decoded from `SECRET_RELEASE_KEYSTORE_BASE64` |

Each export uploads a build artifact (`build-<platform>/`).

---

## The 5-platform claim, honestly

The project's ROADMAP.md Phase 1 success criterion 1 reads:
> "Build exports to all 5 platforms (Mac, Windows, Linux, Android, iOS)"

**CONTEXT.md D-04 creates a deliberate deviation from this wording:**

iOS export is NOT automated in CI during Phase 1. The reasons are documented in CONTEXT.md D-04:

1. **No Apple Developer Program enrollment yet.** iOS ad-hoc distribution and TestFlight require an Apple Developer account ($99/yr). This is a Phase 5 prerequisite alongside store-readiness work.
2. **Code-signing infrastructure.** iOS builds require a provisioning profile, signing certificates, and an entitlements file — all of which depend on the Apple Developer Program.
3. **macOS-only Xcode toolchain.** The iOS Godot export template requires Xcode, which only runs on macOS. GitHub-hosted `macos-latest` runners could in principle run an Xcode-based export, but without a valid signing identity the resulting `.ipa` would fail to install on a real device.
4. **What Phase 1 DOES deliver for iOS:** A manual export via `bash scripts/export-ios.sh` on the developer's M4 MacBook Air validates that the Godot project builds successfully for the iOS target ("Designed-for-iPad" path). This proves the **build pipeline** is correct even though **CI automation** is absent.

**Resolution:** Full iOS CI parity — with real code-signing, provisioning profiles, and TestFlight upload — is a **Phase 5 deliverable** tracked in `STATE.md` todos. This is not a gap; it is a deliberate, documented deferral. The Phase 1 iOS validation (M4 MBA manual export + smoke test on "My Mac" iOS apps view) satisfies the spirit of the ROADMAP criterion.

---

## How to add a new CI gate

1. Add your check script to `scripts/` with an SPDX header and `set -euo pipefail`.
2. Add a step to the `scope-checks` job in `.github/workflows/ci.yml` **and** `.github/workflows/pr-checks.yml`.
3. Run `bash scripts/glossary-check.sh` locally to confirm your script doesn't violate DOC-10.
4. Run `reuse lint` locally to confirm the SPDX header is correct.
5. Open a PR; both `ci` and `pr-checks` must go green before merging.

**Security note (T-03-04):** GitHub Actions workflow files added by forked PRs run in an isolated environment with read-only repo access and no access to repository secrets. To prevent secret exfiltration via a malicious workflow, configure your repo: Settings → Actions → General → "Require approval for first-time contributors". All maintainers should enable this setting.

---

## How to diagnose a red build

### Glossary check fails

```
FAIL: forbidden terminology found outside the allowlist.
```

A file under `src/`, `docs/`, `locale/`, or `README.md` contains a forbidden term ("Lego", "LEGO", "minifig", "Minecraft"). Check the output for the file:line reference. If the mention is a legitimate exception (e.g., a README disclaimer line), add the exact path to `scripts/glossary-allowlist.txt`.

### REUSE lint fails

```
* Missing SPDX information in ...
```

A source file is missing its SPDX header. Add:
```
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
```
Use the comment syntax appropriate for the file type (e.g., `<!--` for HTML/XML, `//` for GDShader).

### Feature-flag invariant fails

```
FAIL: a §9 deferred-feature flag is set to true in project.godot.
```

A `cubicraftia/features/*` setting is `true` in `project.godot`. If this is intentional (the feature is ready for v1), update DOCS.md §9 to move the feature from the deferred list. If it's accidental, revert the `project.godot` change.

### i18n round-trip fails

```
FAIL: locale/messages.pot is stale — run scripts/extract-pot.sh and commit the result.
```

A `.gd` file was added or modified with new `tr("...")` calls without re-running `scripts/extract-pot.sh`. Run the script locally and commit the updated `locale/messages.pot`.

### GUT unit tests fail

Check the test output for the specific test name and failure message. Run locally:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/unit -gexit
```

### Export fails (Linux/Windows/Android)

The `barichello/godot-ci:4.6.3` container includes Godot export templates for Linux, Windows, and Android. Common failures:
- Missing export template for the platform — ensure the Docker image tag matches `GODOT_VERSION` in the workflow.
- Android keystore not set up — see [CI_KEYSTORE_SETUP.md](CI_KEYSTORE_SETUP.md).

### Export fails (macOS)

The macOS export uses `macos-latest` with a native Homebrew Godot install. Common failures:
- `brew install --cask godot` timeout — retry the run.
- macOS export template missing — Godot downloads templates on first launch; verify the Godot version matches `GODOT_VERSION`.

---

## Docker image pin

The `barichello/godot-ci` Docker image is pinned to `:4.6.3` (not `:latest`) per **Pitfall 12**. This prevents silent Godot version drift. When the project intentionally upgrades Godot:

1. Update `env.GODOT_VERSION` in both workflow files.
2. Verify the new tag exists on Docker Hub: `docker pull barichello/godot-ci:<new-version>`.
3. Update this doc and the STACK.md entry.

To verify the image has not been tampered with, compare the published SHA256 on Docker Hub against `docker inspect barichello/godot-ci:4.6.3 --format='{{.Id}}'` after pulling.
