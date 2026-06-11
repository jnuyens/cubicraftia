<!--
SPDX-FileCopyrightText: 2026 Cubicraftia contributors
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Installing Cubicraftia

This guide takes you from a clean machine to a running build of Cubicraftia and a green
test suite. For a deeper developer setup (CI tooling, REUSE lint, pinned addon commits,
mobile perf-spike notes), see [docs/SETUP.md](docs/SETUP.md).

## 1. Prerequisites

| Tool | Version | Check |
|---|---|---|
| **Godot Engine** | **4.6.3** | `godot --version` → `4.6.3.stable.official.*` |
| **git** | any recent | `git --version` |
| **git-lfs** | 3.x+ | `git lfs version` |

Install them:

```bash
# macOS (Homebrew)
brew install --cask godot      # Godot 4.6.3
brew install git git-lfs

# Ubuntu / Debian
sudo apt-get update && sudo apt-get install -y git git-lfs
# Godot 4.6.3: download from https://godotengine.org/download
# or: flatpak install flathub org.godotengine.Godot
```

The project targets the **Mobile renderer** (`GL Compatibility` features). Do **not**
switch it to Forward+ — that will break performance on the Android target.

## 2. Clone the repository

```bash
git clone https://github.com/jnuyens/cubicraftia.git
cd cubicraftia
```

## 3. Set up Git LFS

Cubicraftia stores its binary assets — art (`.png`, `.jpg`, `.glb`), audio, and the
committed native addon binaries (see below) — in **Git LFS**. This repo uses a
**self-hosted LFS server**, configured by the committed `.lfsconfig`:

```ini
[lfs]
	url = https://lfs.cubicraftia.com/api/cubicraftia/cubicraftia
```

The LFS server is protected by HTTP Basic auth. **Collaborators must request the LFS
credential from the maintainer** — it is not stored in the repository. Once you have it,
configure it once (it will be saved to your git credential store on first use), then pull
the LFS objects:

```bash
# Initialise the LFS hooks (one-time per machine)
git lfs install

# Pull all LFS-tracked objects from the self-hosted server.
# You will be prompted for the Basic-auth username and password
# (ask the maintainer for these — do NOT commit them anywhere).
git lfs pull
```

If `git lfs pull` succeeds, your working tree now contains the real binaries instead of
small text pointer files. You can confirm with:

```bash
git lfs ls-files | head        # lists tracked LFS files
file addons/zylann.voxel/bin/libvoxel.linux.editor.x86_64.so  # a real binary, NOT an "ASCII text" pointer
```

> **Native addon binaries are committed via LFS — no compilation needed for desktop.**
> The `Zylann/godot_voxel` GDExtension binaries (`addons/zylann.voxel/bin/**`) are
> committed as LFS objects, so a desktop developer does **not** need to compile the C++
> voxel module. Just `git lfs pull` and open the project. (Mobile export to less-common
> ABIs may still require recompiling the GDExtension — see `docs/SETUP.md`.)

## 4. Open the project in Godot and run

1. Launch **Godot 4.6.3**.
2. Click **Import**, navigate to the repo root, and select `project.godot`.
3. Click **Import & Edit**. Godot will reimport assets on first open (this can take a
   few minutes the first time).
4. Press **F5** (or the ▶ Play button) to run. The main scene is the title screen
   (`res://src/ui/title_scene.tscn`).

To trigger asset import headlessly (useful for CI or a first-pass sanity check):

```bash
godot --headless --import
```

## 5. Running the test suite

Tests use **GUT** (GDScript Unit Testing, committed under `addons/gut/`). Run the unit
suite headlessly from the repo root:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/unit -gexit
```

To include integration tests as well:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -- -gdir=tests/unit,tests/integration -gexit
```

A non-zero exit code means a test failed. CI runs the same command on every pull request
(see [docs/CI.md](docs/CI.md)).

## 6. Contribution workflow

Cubicraftia uses the **GSD workflow** for all repository changes so planning artifacts and
execution context stay in sync with the code (see `CLAUDE.md`).

1. **Branch** off `main`:

   ```bash
   git switch -c your-feature-branch
   ```

2. **Make changes through a GSD command** — do not make direct edits outside the workflow
   unless explicitly bypassing it:
   - `/gsd-quick` — small fixes, doc updates, ad-hoc tasks
   - `/gsd-debug` — investigation and bug fixing
   - `/gsd-execute-phase` — planned phase work

3. **Run the test suite** (Section 5) and confirm it is green.

4. **Open a pull request** against `main`. CI will run the GUT suite and the REUSE/SPDX
   lint. Every new source file must carry an SPDX header (`reuse lint` enforces this —
   see [docs/SETUP.md](docs/SETUP.md)).

Project status, the roadmap, and requirements live in `.planning/` (`ROADMAP.md`,
`PROJECT.md`, `STATE.md`).
