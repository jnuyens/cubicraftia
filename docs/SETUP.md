<!--
SPDX-FileCopyrightText: 2026 Cubicraftia contributors
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Cubicraftia — Development Setup

This guide covers the Phase 1 developer setup on macOS (M4 MacBook Air) and Ubuntu/Debian.

## Quick start

```bash
# macOS
bash scripts/install-deps.sh

# Check what is installed (no side effects)
bash scripts/install-deps.sh --check
```

---

## Prerequisites

### macOS (Homebrew)

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Godot 4.6.3
brew install --cask godot

# Install CI tooling
brew install ripgrep gettext jq

# Install pipx (for reuse)
brew install pipx && pipx ensurepath

# Install reuse (SPDX header lint)
pipx install reuse
```

### Ubuntu / Debian

```bash
# Install Godot 4.6.3 — download from https://godotengine.org/download
# or use the official Flatpak:
flatpak install flathub org.godotengine.Godot

# Install CI tooling
sudo apt-get update && sudo apt-get install -y ripgrep gettext jq pipx
pipx install reuse
```

---

## Pinned versions

| Component | Version | Notes |
|-----------|---------|-------|
| **Godot Engine** | **4.6.3** | `godot --version` must output `4.6.3.stable.official.*` |
| **godot_voxel** | master @ commit **4a9d311** (2026-05-14) | Verify with `git -C addons/godot_voxel rev-parse HEAD` |
| **Gut** (GDScript Unit Testing) | **v9.4.0** | `ls addons/gut/gut_cmdln.gd` must exist |
| ripgrep | 14.x+ | `rg --version` |
| gettext / xgettext | any recent | `xgettext --version` |
| reuse | 6.x+ | `reuse --version` |

> **Phase 1 has no Rust.** The decision to add a Rust GDExtension hot-path was explicitly
> deferred to a future phase (CONTEXT.md D-12). No `cargo`, `rustup`, `rust-toolchain`, or
> `Cargo.toml` files are part of the Phase 1 setup. If you see Rust-related errors, you may
> be on the wrong branch or reading stale documentation.

---

## Addon installation

Addons are not committed as full clones — only `.gitkeep` stubs are in the repo.
`scripts/install-deps.sh` installs them at the pinned versions.

### godot_voxel (manual)

```bash
# Remove the stub and clone at the pinned commit
rm addons/godot_voxel/.gitkeep
git clone https://github.com/Zylann/godot_voxel.git addons/godot_voxel
git -C addons/godot_voxel checkout 4a9d311
```

### Gut (manual)

```bash
rm -f addons/gut/.gitkeep
git clone --branch v9.4.0 --depth 1 https://github.com/bitwes/Gut.git /tmp/gut-clone
cp -r /tmp/gut-clone/addons/gut/. addons/gut/
```

---

## Opening the project

1. Launch Godot 4.6.3.
2. Choose **Import** → navigate to this repo root → select `project.godot`.
3. Click **Import & Edit**.

The project uses the **Mobile renderer** (`rendering/renderer/rendering_method.mobile = "mobile"`).
Do NOT switch to Forward+ — it will break performance on the Android Tier-3 target.

---

## Verifying the install

Run these commands after `scripts/install-deps.sh` to confirm everything is in order:

```bash
# Godot version
godot --version | grep -E "^4\.6\.3"

# godot_voxel pinned commit
git -C addons/godot_voxel rev-parse HEAD   # should start with 4a9d311

# Gut addon
ls addons/gut/gut_cmdln.gd

# ripgrep
rg --version | head -1

# reuse (SPDX lint)
reuse lint
```

---

## Running the REUSE lint

```bash
reuse lint
```

All source files must carry `SPDX-FileCopyrightText` and `SPDX-License-Identifier` headers
(or be covered by `.reuse/dep5`). The CI `scope-checks` job enforces this on every PR.

---

## Phase 1 has no Rust

Per CONTEXT.md D-12, Rust GDExtension (godot-rust / gdext) is **out of scope for Phase 1**.
The hot path for voxel meshing runs in the C++ `godot_voxel` module; gameplay code is GDScript.

Rust enters the project only if a future phase identifies a specific measured hot path that
GDScript + godot_voxel cannot sustain on the Tier-3 Android target.

---

## Motorola One Macro — Phase 1 perf spike

The Phase 1 mobile performance spike runs on a **Motorola One Macro (XT2016-1)**:
- SoC: MediaTek Helio P70
- GPU: Mali-G72 MP3
- RAM: 4 GB
- Android: 9 (API 28) / OTA'd to Android 10 (API 29)

This device is NOT needed for Plans 01–06. It is required for Plan 07 (30-minute benchmark).
See `.planning/phases/01-foundation-mobile-spike/01-01-PLAN.md` `user_setup` section for
acquisition notes.
