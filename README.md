<!--
SPDX-FileCopyrightText: 2026 Cubicraftia contributors
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Cubicraftia

**An open-source 3D building-and-survival sandbox where the entire world is made of bricks.**

Cubicraftia blends an infinite, procedurally generated world with real brick-build
mechanics. The terrain, the creatures, and everything you make are assembled from
**bricks** — not just 1×1 cubes, but a whole vocabulary of bricks, plates, slopes,
tiles, and accessories that snap together on **studs**. You play a customisable
**builder** and explore the world solo or with up to three friends over the internet.

Sessions are friends-only — you start alone, and the moment a friend joins, the same
session seamlessly becomes multiplayer. No separate modes. Cubicraftia runs on macOS,
Windows, Linux, iOS, and Android with full cross-play.

> Cubicraftia is not affiliated with, endorsed by, or sponsored by any toy or game
> company. All brick shapes, names, and game terms are original. Player-facing
> terminology is **brick / stud / builder**.

## Features

- **Two-grid world** — chunky procedural terrain for the landscape plus a finer stud
  grid for expressive brick-by-brick building, in one seamless world.
- **A real brick vocabulary** — bricks, plates, slopes, and tiles in an 18-colour
  palette, placed one part per action and snapped onto studs. The richer shape language
  makes building far more expressive than cubes alone.
- **Sandbox and survival in the same session** — build freely with no danger in sandbox
  mode, or mine terrain for bricks, craft tools, and fend off hostile creatures in
  survival. Both modes coexist.
- **Solo or 2–4 friends** — friends-only peer-to-peer sessions with seamless host
  failover, so the game continues if the host drops.
- **Infinite procedural terrain** — biomes, structures, a soft day/night cycle, and
  weather, all generated as you explore.
- **Cross-platform, cross-play** — macOS, Windows, Linux, iOS, and Android from a single
  codebase.

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Game engine | **Godot 4.6** (MIT) | Mature, fully open-source, ship-tested cross-platform export to all five targets. |
| Voxel terrain | **Zylann/godot_voxel** (MIT) | De-facto open-source voxel module: chunked streaming, LOD, blocky + cubes meshers. |
| Brick / stud layer | **Custom system on glTF 2.0** with stud-anchor metadata in glTF `extras` | Stud-grid metadata travels with each asset; reuses the entire glTF tooling ecosystem. |
| Procedural generation | **FastNoiseLite** (in-engine) | Built-in, performant noise for biomes and structures — no extra dependency. |
| Scripting | **GDScript** (gameplay) + **Rust via gdext** for future hot paths | Fast iteration in GDScript; Rust reserved for measured perf-critical work. |
| Networking transport | **WebRTCMultiplayerPeer** (libdatachannel) + **ENet** LAN fallback | One API for desktop and mobile, with ICE/STUN/TURN NAT traversal for friends-only P2P. |
| Discovery / signaling | **Go service** (single binary) | Tiny WebSocket signaling server for session discovery and ICE relay — never game state. |
| STUN / TURN | **coturn** (BSD-3) | Open-source standard relay for symmetric-NAT fallback. |
| Accounts / friends | **Supabase** (self-hosted: Postgres + GoTrue + RLS) | Relational friends graph with declarative row-level authorization. |
| World persistence | **SQLite** via godot-sqlite | One file per world: transactional chunk + structure storage, easy to back up and migrate. |
| License | **GPL-3.0-or-later** | All derivatives stay open; prevents proprietary forks. |

## Build & run

Cubicraftia is a Godot 4.6 project. See **[INSTALL.md](INSTALL.md)** for the full
step-by-step guide: prerequisites, cloning, Git LFS setup, opening the project in Godot,
running the test suite, and the contribution workflow.

```bash
git clone https://github.com/jnuyens/cubicraftia.git
cd cubicraftia
git lfs pull          # native addon binaries + art assets (see INSTALL.md)
godot --headless --import
```

## Contributing

This project uses the **GSD workflow** for all repository changes — planning artifacts and
execution context stay in sync with the code. Before making edits, start work through a GSD
command (see `CLAUDE.md` for the full convention):

- `/gsd-quick` — small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` — investigation and bug fixing
- `/gsd-execute-phase` — planned phase work

The typical flow: branch off `main`, make your changes through the appropriate GSD command,
run the test suite (see [INSTALL.md](INSTALL.md)), and open a pull request. Project status,
roadmap, and requirements live in `.planning/`.

## Licence

Cubicraftia's effective license is **GPL-3.0-or-later WITH the App Store Distribution Exception**:
the **GNU General Public License v3.0 or later** (`GPL-3.0-or-later`, see [LICENSE](LICENSE) for
the full text), plus a narrow additional permission under GPLv3 section 7 that allows official
signed binaries to be distributed through the Apple App Store. See
**[LICENSING.md](LICENSING.md)** for the full explanation of what the exception does and does not
change.

Third-party component licences are listed in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)
and [NOTICE](NOTICE). The project follows the [REUSE](https://reuse.software/) specification:
every source file carries an SPDX header.
