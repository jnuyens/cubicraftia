<!-- SPDX-FileCopyrightText: 2026 Cubicraftia contributors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# iOS Manual Export — M4 MacBook Air (D-04)

## Context

iOS export is intentionally **not automated in CI** during Phase 1. See [docs/CI.md — The 5-platform claim, honestly](CI.md#the-5-platform-claim-honestly) and CONTEXT.md D-04 for the full rationale.

The M4 MacBook Air can run iOS apps via the "Designed-for-iPad" path (Apple Silicon Macs can run iOS/iPadOS apps natively). This validates that the Godot project **builds correctly for iOS** and that the resulting app **boots and runs input** — without requiring a physical iPhone or Apple Developer Program enrollment.

Full iOS CI + TestFlight + App Store distribution is a **Phase 5 deliverable**.

---

## Prerequisites

| Requirement | Install command | Verify |
|-------------|----------------|--------|
| macOS 15+ (Sequoia) | System update | `sw_vers -productVersion` |
| Xcode latest (≥ 16) | Mac App Store | `xcodebuild -version` |
| Xcode command-line tools | `xcode-select --install` | `xcode-select -p` |
| Godot 4.6.3 | `brew install --cask godot` | `godot --version` |
| `scripts/export-ios.sh` | (in repo) | `test -x scripts/export-ios.sh` |

> **Note:** You do NOT need an Apple Developer Program account for "Designed-for-iPad" / local Mac testing. The export produces an unsigned `.ipa` that installs on your own Mac only.

---

## Step-by-step export procedure

### Step 1: Check prerequisites

```bash
bash scripts/export-ios.sh --check
```

Expected output:
```
[OK]  Running on macOS (Darwin).
[OK]  Xcode found at /Applications/Xcode.app/Contents/Developer (Xcode 16.x).
[OK]  Godot found: 4.6.3.stable.official.xxxxxxxx
[OK]  iOS preset found in export_presets.cfg.

=== --check mode: all prerequisites satisfied. No export performed. ===
```

If any `[ERROR]` lines appear, follow the instructions to install missing tools, then re-run.

### Step 2: Run the export

```bash
bash scripts/export-ios.sh
```

The script will:
1. Re-run the prerequisite checks.
2. Execute the scope-gates (glossary, feature-flags, REUSE) — identical to CI (T-03-03 threat mitigation).
3. Invoke `godot --headless --export-release "iOS" build/ios/Cubicraftia.ipa`.
4. Write `.last-ios-export.json` with the timestamp, Godot version, and Xcode version.

Expected output ends with:
```
=== Export complete ===
  Output: build/ios/Cubicraftia.ipa

Run log written to .last-ios-export.json
```

> If the export fails with an error about missing export templates, open the Godot editor once and let it download templates, or install them via: Editor → Export → Manage Export Templates → Download.

### Step 3: Verify the .ipa in Xcode

1. Open **Xcode**.
2. Go to **Window → Devices and Simulators** (⇧⌘2).
3. In the left sidebar, select **My Mac** under "My Devices" (not a simulator — the physical Mac entry).
4. Drag `build/ios/Cubicraftia.ipa` to the **"Installed Apps"** section.
5. Click **Install** if prompted.
6. The Cubicraftia app should appear in the list and launch from the My Mac device entry.

### Step 4: Functional smoke test

Verify the following in the running app:

- [ ] The Cubicraftia title / loading screen appears (no crash on launch).
- [ ] The disclaimer dialog ("not affiliated with…") is present on first launch.
- [ ] Mouse/click input responds (camera movement, button presses).
- [ ] The game world loads (terrain visible, builder character present).
- [ ] No obvious graphical corruption (black screen, Z-fighting, missing UI).

Record pass/fail for each item above in the run log (see Step 5).

### Step 5: Record the run

Commit the `.last-ios-export.json` sidecar to record this validation:

```bash
git add .last-ios-export.json
git commit -m "chore: record iOS export $(date +%Y-%m-%d)"
```

The JSON file captures:
- `exported_at`: ISO-8601 timestamp
- `godot_version`: exact Godot build string
- `xcode_version`: Xcode version used
- `host`: machine hostname
- `output`: path to the .ipa
- `note`: D-04 deviation reminder

---

## Troubleshooting

### "No export template found"

```
ERROR: No export templates found. Download them in Godot's Editor → Export → Manage Export Templates.
```

Open the Godot editor, go to **Editor → Export → Manage Export Templates**, and click **Download**. The template for iOS requires Xcode to be installed.

### "Xcode not found"

```
ERROR: Xcode command-line tools not found.
```

Install Xcode from the Mac App Store, then:
```bash
xcode-select --install
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### "Godot not found"

```
ERROR: Godot not found on PATH.
```

```bash
brew install --cask godot
# Or add to PATH manually:
export PATH="/Applications/Godot.app/Contents/MacOS:$PATH"
```

### App doesn't appear in Xcode "My Mac" devices

This can happen if the app's Info.plist is missing `UIRequiresFullScreen` or the minimum OS version is set too high. Verify the export preset settings in Godot's export dialog or in `export_presets.cfg` (the `interface/target_device` setting; `2` = Universal iPhone+iPad).

---

## Phase 5 upgrade path

When Phase 5 begins (store-readiness):
1. Enroll in Apple Developer Program ($99/yr at developer.apple.com).
2. Generate a Distribution certificate and a provisioning profile.
3. Configure the iOS export preset in Godot with the signing identity and profile.
4. Add the GitHub Actions `macos-latest` iOS export step to `.github/workflows/ci.yml`.
5. Set up TestFlight upload via Fastlane or the App Store Connect API.

Until then, this manual procedure is the canonical iOS validation path.

---

## Run log

| Date | Godot | Xcode | Smoke test | Notes |
|------|-------|-------|------------|-------|
| (first run — record after executing Step 5) | | | | |
