<!-- GSD:project-start source:PROJECT.md -->
## Project

**Cubicraftia**

Cubicraftia is een 3D game waarin de hele wereld gemaakt is van **bricks** (Lego-stijl onderdelen): terrein, **builders** (de poppetjes, spelers én vijanden), en alles wat je bouwt. Het combineert de procedureel oneindige wereld van Minecraft met echte brick-bouwmechaniek — onderdelen zoals bricks, plates, slopes, tiles en accessoires die op studs aansluiten, in plaats van enkel 1×1 kubussen. Je speelt alleen of samen met 2-4 vrienden over internet, met een creatieve modus en een survival-modus, op Mac, PC en mobiel.

> **Naam:** "Cubicraftia" is de **definitieve naam**, onder voorbehoud van trademark-clearance voor publieke release. Player-facing terminologie: brick / stud / builder. "Lego" of "Minecraft" verschijnen nooit in UI of docs.

**Core Value:** **Het Lego-bouwgevoel in een Minecraft-achtige sandbox — alleen of met je vrienden.** De rijkere vormtaal van echte Lego (geen 1×1 cubes) maakt bouwen expressiever. Je begint solo, en wanneer een vriend joint groeit dezelfde sessie naar multiplayer — geen aparte modi.

### Constraints

- **Tech stack:** Cross-platform vereist een engine met goede mobile-prestaties en open-source-compatibel ecosysteem (research-fase: Godot vs. Unity vs. eigen / Bevy etc.)
- **Multiplayer-architectuur:** P2P met variabele connecties betekent zorgvuldig netwerk-protocol; host-failover moet game-state synchroon overdragen zonder merkbare onderbreking
- **Performance:** Mobile performance is bottleneck — voxel + Lego-detail moet werken op gemiddelde telefoons
- **Open source licensing:** Alle dependencies moeten compatibel zijn met de gekozen licentie
- **Handelsmerk-risico:** Werknaam "LegoMinecraft" en visuele stijl moeten genoeg afwijken van LEGO/Minecraft om geen juridische problemen te krijgen vóór release
- **Hosting:** Discovery-server draait op één Linux-machine (in eerste instantie); architectuur moet horizontaal schaalbaar zijn voor latere groei
- **Doel-sessie-grootte:** 2-4 spelers per wereld, dus we hoeven geen massive-multiplayer-architectuur te bouwen
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## TL;DR — Recommended Stack
| Layer | Choice | Why (one-liner) |
|---|---|---|
| Game engine (client) | **Godot 4.6** (stable, MIT) | Only fully-open-source engine with a mature, ship-tested cross-platform export to Mac/Win/Linux/iOS/Android in 2026. |
| Voxel terrain | **Zylann/godot_voxel** (MIT) | The de-facto Minecraft-style voxel module for Godot; greedy/blocky meshing, LOD, chunked storage. |
| Lego-brick "studs" layer | **Custom system on top of glTF 2.0 parts** with stud-anchor metadata in glTF `extras` | glTF is the standard for Godot 4; stud grid metadata travels with the asset. *(Implementation note: Phase 1 ships glTF `extras` rather than the `EXT_structural_metadata` extension, because Godot 4.6 does not import `EXT_structural_metadata` natively. The functional outcome — stud-anchor metadata travelling with the asset — is identical. `.blend` files in `src/bricks/` are source-only; if a sibling `.glb` file exists, it does not need to be reimported during CLI exports.)* |
| Procedural generation | **Godot's built-in `FastNoiseLite`** + custom biome/structure logic in GDScript or Rust GDExtension | Already in-engine, performant, no extra dep. |
| Scripting | **GDScript** for gameplay + **Rust via godot-rust (gdext)** for hot voxel/meshing paths | GDScript for iteration speed, Rust for the perf-critical chunk work. |
| Networking transport | **Godot's WebRTCMultiplayerPeer** (libdatachannel under the hood for native) with **ENetMultiplayerPeer** as LAN/dev fallback | Single API works on desktop *and* mobile, handles NAT traversal through ICE/STUN/TURN, fits friends-only P2P model. |
| Discovery / signaling server | **Go service** on Linux (single binary, WebSocket signaling + STUN-assisted ICE coordination) | Tiny memory footprint, easy single-binary deploy, scales horizontally if needed; reference implementations exist for Godot WebRTC. |
| STUN/TURN | **coturn** (BSD-3) on the same Linux host | Open-source standard, drop-in on Debian/Ubuntu, handles symmetric-NAT relay fallback. |
| Account + friends + invites | **Supabase** (Apache-2.0, self-hostable) — Postgres + GoTrue auth + Row-Level Security | Friends graph is relational; SQL with RLS is the right model; can self-host on the same Linux box to avoid vendor lock-in. |
| World persistence (P2P, on-host) | **SQLite via Godot's built-in support / `godot-sqlite` GDExtension** for chunk + structure storage | Single-file world DB matches Minecraft's mental model; trivial to ship/restore on host migration. |
| Build / CI | **GitHub Actions** matrix building Godot export templates per platform | Free for open source; covers all 5 targets. |
| License | **MIT** (engine + most deps) or **Apache-2.0** (matches Supabase, libdatachannel) | All recommended deps are permissively licensed. |
## Per-Component Rationale
### 1. Game Engine — Godot 4.6 (HIGH confidence)
- **Genuinely cross-platform with mobile that works today.** Godot exports to Linux/macOS/Windows/Android/iOS/Web from a single project. The Foundation has a dedicated mobile team since 2025, with crash rates from shipped 4.x titles down from ~4% to <1% after the [April 2026 mobile push](https://godotengine.org/article/godot-mobile-update-apr-2026/).
- **MIT license, no royalties, no per-seat fees.** Compatible with Cubicraftia's open-source-from-day-1 principle. The only required external costs are the Apple Developer Program ($99/yr) and Google Play Console ($25 once) if you want to publish to those stores; sideloading and itch.io are free.
- **Active voxel ecosystem.** [`Zylann/godot_voxel`](https://github.com/Zylann/godot_voxel) is the longest-running open-source Minecraft-style voxel module, written in C++ with GDExtension support for Godot 4.4+. It bundles a `VoxelMesherBlocky` (model-based blocks, ideal for Lego parts) plus `VoxelMesherCubes` (greedy meshing for terrain), LOD, chunked streaming, and physics.
- **Built-in networking primitives.** `ENetMultiplayerPeer`, `WebRTCMultiplayerPeer`, scene replication, RPCs — all in core, all work across platforms.
- **Tooling is approachable for an open-source contributor base.** GDScript reads like Python; the editor runs everywhere, including on iPad ([Xogot](https://xogot.com/)).
- The Godot 4 `Forward+` renderer is desktop-optimised — do not enable it for the mobile target.
- Voxel performance on low-end Android (e.g. 3-year-old mid-range phones) needs early prototyping. Plan an explicit "mobile perf spike" in the roadmap.
- GDExtension export templates for some niche mobile architectures occasionally need to be self-built; plan for a CI build step.
### 2. Voxel Terrain — Zylann/godot_voxel (HIGH confidence)
- **Two meshers, both relevant to Cubicraftia:**
- **Chunked storage + streaming + LOD already implemented**, which is exactly what an infinite procedural world needs.
- **C++ performance** (not GDScript), so heavy meshing doesn't stall the main thread on mobile.
- Author actively maintains it (last release within months), and there's a [working voxel demo for Godot 4.4](https://github.com/Zylann/voxelgame) you can fork.
- The Blocky mesher does **face-culling but not greedy meshing**; for the chunky terrain layer use `VoxelMesherCubes` or roll a greedy pass on top of Blocky for high-density brick fields.
- Mobile builds of the GDExtension may need recompilation for less-common ABIs. Document this clearly in CONTRIBUTING.md.
### 3. Lego "Stud" Layer — Custom on top of glTF 2.0 (MEDIUM confidence)
- **glTF is the open, royalty-free Khronos standard** and the native 3D format for Godot, Blender, and most modern tooling. Asset authors can use any DCC tool.
- `EXT_structural_metadata` is a real, published extension specifically for "structured metadata travelling with the asset" — exactly the snap-point use-case.
- **Implementation reality (Phase 1+):** Godot 4.6 does not import `EXT_structural_metadata` natively. Phase 1 implemented stud-anchor metadata using glTF `extras` instead — the functional outcome is identical (metadata travels with the `.glb`), and the asset pipeline (Blender → `.glb` with extras → `BrickRegistry`) is proven and in use. Future contributors: author stud-anchor metadata as `extras.stud_anchors` in your `.glb`; see `src/bricks/brick_1x1.glb` as the reference asset. `.blend` source files in `src/bricks/` are source-only — if a sibling `.glb` exists, it does not need to be reimported during CLI exports.
- Avoid inventing a binary format; reuse the entire glTF ecosystem (validators, viewers, blender exporters).
- LOW confidence that the v1 stud grid can run smoothly on low-end Android with thousands of placed bricks; this needs an explicit performance prototype phase. Mitigations: per-chunk static mesh baking after N seconds of no edits; LOD that swaps stud detail for flat textures past ~10 meters.
### 4. Procedural Generation — `FastNoiseLite` (HIGH confidence)
- Already bundled — no extra dependency.
- Supports Perlin, Simplex, OpenSimplex2, Cellular noise + fractal layering (FBM, ridged) — the standard kit for Minecraft-style biomes.
- C++ implementation; performant enough on mobile.
- Well-documented for Minecraft-style terrain ([example: 75-line procedural world](https://github.com/alpapaydin/Godot4-3D-Procedural-World-Generation)).
### 5. Networking Transport — Godot WebRTCMultiplayerPeer (+ ENet fallback) (MEDIUM-HIGH confidence)
- **Primary (online P2P with friends):** `WebRTCMultiplayerPeer` using Godot's `webrtc-native` GDExtension (which wraps **libdatachannel** for desktop+mobile native builds).
- **Fallback (LAN, same-network, dev):** `ENetMultiplayerPeer` — works zero-config when peers can directly see each other (e.g. LAN parties).
- **Discovery/signaling:** Custom Go service over WebSocket exchanging WebRTC offer/answer/ICE candidates (see component 6).
- **NAT traversal:** Public STUN servers (Google's free pool) + self-hosted **coturn** TURN relay for symmetric-NAT cases.
- **WebRTC is the only protocol that natively reaches mobile (iOS/Android) browsers and apps** with consistent NAT-traversal results.
- Godot already ships a WebRTC multiplayer peer that drops straight into the High-Level Multiplayer API — your RPCs and `MultiplayerSpawner` / `MultiplayerSynchronizer` code stay unchanged whether you're on ENet, WebRTC, or future SteamSockets.
- **libdatachannel** (the underlying C++ lib) is permissively-licensed (MPL-2.0), small, cross-platform native — confirmed working on iOS/Android/macOS/Linux/Windows.
- GNS is excellent and Valve-tested, but its ICE NAT traversal still leans on Google's WebRTC reference implementation; you'd be adding complexity vs. just using WebRTC directly.
### 6. Discovery / Signaling Server — Go on Linux (HIGH confidence)
- WebSocket endpoint for WebRTC offer/answer/ICE relay (signaling only — never game state).
- Lobby/session registry: which sessions exist, who's invited, who's the host.
- Friend graph lookups (delegated to Supabase Postgres via PostgREST or direct SQL).
- Invite-link issuance and redemption.
- **Single static binary**, deploys with `scp + systemd unit` — minimal ops.
- **Coroutines (goroutines)** map naturally to "thousands of long-lived WebSocket connections" — perfect signaling profile.
- **Faster than Node** at the WebSocket level, **simpler than Rust** for contributors. The project is open source; lower contributor barrier matters.
- **[Nakama](https://github.com/heroiclabs/nakama)** is written in Go and proves the pattern at scale, but Nakama itself is overkill — it's an authoritative game server with matchmaking, leaderboards, presence, chat. Cubicraftia doesn't need any of that on the server (game state is P2P, friends/chat go to Supabase). Build a **slim Go signaling service** instead; if it later outgrows itself, the upgrade path to Nakama is clear.
- [Godot WebRTC signaling demo (Node.js)](https://github.com/godotengine/godot-demo-projects/tree/master/networking/webrtc_signaling) — port the protocol to Go.
- [V-Sekai signaling sample](https://github.com/V-Sekai/sample-webrtc-signaling) — variant with lobbies.
### 7. STUN/TURN — coturn (HIGH confidence)
### 8. Account / Auth / Friends Backend — Supabase (Self-Hosted) (HIGH confidence)
- **Open source from day 1** — matches Cubicraftia's principle. Firebase is closed source and locks you into Google Cloud pricing.
- **Postgres for the friends graph.** Friends, invites, mutual-friend rules, "invite-by-link makes mutual friends until unfriended" — this is *exactly* the kind of relational logic that's painful in Firestore (no joins, denormalized reads) and natural in Postgres (a single `friendships(user_a, user_b, status, created_at)` table with `CHECK (user_a < user_b)`, foreign keys to `auth.users`, plus an `invites(token, sender, session_id, expires_at)` table).
- **Row-Level Security (RLS)** gives you per-row authz declaratively — "a user can only see invites sent to or by them" is a single policy.
- **Email/password + OAuth** (Google, Apple, Discord) come out of the box via GoTrue.
- **Self-hostable** — single `docker compose` deployment.
- Firebase: closed source, vendor lock-in, weak SQL story for the friends graph.
- Raw Postgres + handwritten auth: reinvents the wheel — Supabase's GoTrue handles email verification, password reset, OAuth, sessions, JWT issuance for you, all open-source.
### 9. World Storage — SQLite via godot-sqlite (HIGH confidence)
- **A single file == a world** is the Minecraft mental model players already understand. Easy to back up, share, transfer to a new host.
- SQLite handles chunk blobs, structure metadata, inventories, and player state in one transactional store.
- Trivial to serialise/deserialise during host migration: the new host can request the world file (or a delta) from the old host before the failover completes.
- On mobile the file lives in the app's sandbox, so iOS/Android sandboxing is automatic.
### 10. Scripting — GDScript + Rust (godot-rust / gdext) (MEDIUM confidence)
- **GDScript** for 80% of gameplay logic (UI, inventory, mobs AI, crafting, sessions).
- **Rust via [godot-rust (`gdext`)](https://github.com/godot-rust/gdext)** for the hot loop: chunk meshing extensions, custom noise compositing, stud-grid spatial index, networking serialisation.
- GDScript: Python-like, deeply integrated, no FFI overhead, fast iteration. Best for designers + new contributors.
- Rust: zero-cost abstractions, memory safety, mature ecosystem for voxel maths (e.g. `block-mesh-rs`, `ilattice`, `ndshape`). Where milliseconds matter on mobile, Rust pays for itself.
### 11. License (HIGH confidence)
- Permissive: encourages forks, mods, and embedded use without legal anxiety.
- Matches Godot itself, godot_voxel, FastNoiseLite — no relicensing friction.
- A passion project doesn't need GPL's copyleft protections; openness is enforced by community goodwill + the public repo, not by license.
## Installation Sketch
# --- Client (developer machine) ---
# Install Godot 4.6 via official binary (or asdf-vm / mise)
# Add Zylann/godot_voxel as a project submodule and compile a custom export template
# (or use the GDExtension build for desktop iteration)
# --- Server (single Linux VPS, Debian 12 / Ubuntu 24.04) ---
## Alternatives Considered (and Rejected)
| Component | Alternative | Why Rejected |
|---|---|---|
| Engine | **Unity** | Closed-source runtime, paid for any non-trivial mobile project, 2023 install-fee fiasco eroded trust, license incompatible with "free + OSS forever" goal. |
| Engine | **Unreal Engine 5** | Source-available but not OSS (custom license), 5% royalty over $1M (not a blocker, but principled mismatch); huge binary size hostile to mobile downloads; Lumen/Nanite are wasted on a Lego-style game; mobile export is heavy. |
| Engine | **Bevy 0.18** | Excellent Rust engine and stable on desktop, but mobile (especially Android) is still "possible but not easy" as of 2026 — app lifecycle bugs, weaker Android Studio integration, no editor. For a project that *must* ship on iOS+Android, this is a deal-breaker. Reconsider in 2027. |
| Engine | **O3DE (Open 3D Engine)** | Mobile got a 4× perf boost in 24.09 and is improving, but the project is still mostly aimed at AAA-style robotics/simulation use; voxel ecosystem is thin; contributor base is small relative to Godot; build complexity is high. |
| Engine | **raylib** | Beautiful for prototyping, but no editor, no scene tree, no mobile-grade renderer abstractions — too low-level for a multi-platform sandbox with the scope of Cubicraftia. |
| Engine | **Three.js / WebGL** | Browser-based works for web export but a PWA on iOS still has gesture/audio/save-data hassles; native app polish is hard. Performance ceiling on mobile is lower than native Godot. |
| Engine | **Luanti (ex-Minetest)** | Open-source voxel platform but it *is* the game engine — would mean shipping a Minetest fork. Too restrictive on Lego mechanics, art direction, and the hybrid stud/voxel concept. Useful as a **reference codebase to study**, not a base to build on. |
| Networking | **GameNetworkingSockets (GNS)** | Excellent, but pulls in Google WebRTC for NAT traversal anyway, doesn't integrate as cleanly with Godot's High-Level Multiplayer, and adds complexity without unique benefit at the 2-4 player scale. |
| Networking | **LiteNetLib** | .NET / C# focused, no first-class Godot integration. |
| Networking | **Steam Sockets via GodotSteam** | Battle-tested but Steam-only; Cubicraftia must ship to iOS+Android where Steam doesn't exist. Would require a parallel networking stack. Reconsider as a Steam-platform-only optimisation post-v1. |
| Discovery | **Node.js signaling server** | Works (Godot's reference uses it), but Go gives a single static binary, better concurrency primitives for thousands of WebSocket sessions, lower memory footprint. |
| Discovery | **Nakama (Heroic Labs)** | Open-source, Go-based, has all the features (matchmaking, friends, chat, leaderboards) — but is overkill: it's designed as an *authoritative* game server. Cubicraftia explicitly chose P2P, so 90% of Nakama is unused weight. Keep it as the v2 upgrade path. |
| Auth | **Firebase** | Closed source, vendor lock-in, weak friends-graph modelling, ties you to Google billing. |
| Auth | **Auth0 / Clerk** | Proprietary SaaS, not self-hostable in OSS form, monthly fees scale with users. |
| Auth | **Hand-rolled JWT + bcrypt** | Avoid: email verification, password reset, OAuth flows, session rotation are all foot-guns. Supabase's GoTrue handles them. |
| World storage | **JSON files / flatbuffers** | Loses transactional guarantees; chunk corruption on a crash is much harder to recover. SQLite gives ACID for free. |
| Asset format | **Custom binary brick format** | Reinvents glTF poorly; loses access to Blender/Substance/all viewers/validators. |
## Confidence Assessment
| Recommendation | Confidence | Reasoning |
|---|---|---|
| Godot 4.6 as engine | HIGH | MIT, mature, only OSS engine with shipped mobile titles in 2026. |
| Zylann/godot_voxel | HIGH | De-facto Godot voxel module; meshers + chunking solved problems. |
| WebRTC + libdatachannel transport | HIGH | Only path that covers mobile + NAT + native + browser uniformly. |
| Custom Go discovery server | HIGH | Simple problem, proven pattern, low cost. |
| Supabase self-hosted | HIGH | Friends graph is relational; OSS + self-host meets project ethos. |
| coturn + STUN/TURN | HIGH | Industry standard. |
| FastNoiseLite | HIGH | In-engine; performant; well-documented. |
| glTF + custom stud-metadata for Lego parts | MEDIUM | The format choice is solid; the **runtime stud-snap performance on mobile** is the unknown. Needs prototype validation. |
| Rust GDExtension for hot paths | MEDIUM | Excellent in principle, but adds toolchain complexity for contributors. Worth it for the meshing loop; not worth it elsewhere. |
| **Host-migration approach** | **MEDIUM-LOW** | The primitives exist (`set_multiplayer_authority`), the policy is custom and non-trivial. **Single biggest tech risk in v1; flag as a dedicated phase.** |
| Mobile voxel + stud-grid performance ceiling | MEDIUM | Godot mobile renderer is good, godot_voxel is fast, but the combo with a fine stud grid on low-end Android needs early prototyping. Plan a "mobile perf spike" phase. |
## Open Questions for Later Phase Research
## Sources
- [Godot Engine 4.6 release notes](https://godotengine.org/releases/4.6/)
- [Godot Mobile Update, April 2026](https://godotengine.org/article/godot-mobile-update-apr-2026/)
- [Godot Renderers (Forward+, Mobile, Compatibility)](https://docs.godotengine.org/en/4.4/tutorials/rendering/renderers.html)
- [Zylann/godot_voxel](https://github.com/Zylann/godot_voxel) — voxel module, MIT
- [Zylann voxel game demo for Godot 4.4](https://github.com/Zylann/voxelgame)
- [Voxel Tools docs](https://voxel-tools.readthedocs.io/en/latest/getting_the_module/)
- [Godot WebRTC tutorial](https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html)
- [Godot WebRTC signaling demo](https://github.com/godotengine/godot-demo-projects/tree/master/networking/webrtc_signaling)
- [libdatachannel — C/C++ WebRTC](https://github.com/paullouisageneau/libdatachannel) — MPL-2.0
- [Godot host-migration proposal #7912](https://github.com/godotengine/godot-proposals/issues/7912)
- [Making P2P multiplayer seamless with Godot — Rafael Epplée](https://www.rafa.ee/articles/godot-peer-to-peer-multiplayer/)
- [GameNetworkingSockets P2P README](https://github.com/ValveSoftware/GameNetworkingSockets/blob/master/README_P2P.md)
- [Nakama (Heroic Labs)](https://github.com/heroiclabs/nakama)
- [coturn TURN/STUN server](https://github.com/coturn/coturn)
- [Supabase vs Firebase 2026 (Bytebase)](https://www.bytebase.com/blog/supabase-vs-firebase/)
- [Supabase open-source repo](https://github.com/supabase/supabase)
- [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
- [EXT_structural_metadata glTF extension](https://github.com/CesiumGS/glTF/tree/3d-tiles-next/extensions/2.0/Vendor/EXT_structural_metadata)
- [Lego studs rendering techniques (simonschreibt.de)](https://simonschreibt.de/gat/lego-studs/)
- [FastNoiseLite — Godot docs](https://docs.godotengine.org/en/stable/classes/class_fastnoiselite.html)
- [godot-rust (gdext) book](https://godot-rust.github.io/book/)
- [Bevy mobile platforms overview](https://bevy-cheatbook.github.io/platforms.html)
- [Bevy 0.18 release notes](https://bevy.org/news/bevy-0-18/)
- [O3DE 25.05 release notes](https://www.docs.o3de.org/docs/release-notes/2505-release-notes/)
- [Luanti (Minetest) GitHub](https://github.com/luanti-org/luanti)
- [Game engine comparison 2025 — Wayline](https://www.wayline.io/blog/unity-unreal-godot-engine-comparison-2025)
- [Game Server Showdown 2025 (medevel)](https://medevel.com/game-server-2025/)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

### Desktop control scheme (WoW-style — see DOCS §7.5)

Cubicraftia does **not** use Minecraft FPV mouse-look. Mouse motion alone never rotates the builder or camera. Active bindings — keep these in sync with `project.godot` `[input]` and the i18n prompts in `locale/en.po`:

**Chase camera implementation note (feat(07) — Direct Orbit):** The chase camera uses a manual `RayCast3D` (`CameraRay`, child of `CameraPivot`) instead of `SpringArm3D`. Each physics frame `camera_ray.force_raycast_update()` is called and `camera_chase.position.z` is set directly — NO `Tween`, NO `lerp`, NO interpolation of any kind. This gives instant (zero-latency) wall retraction, eliminating motion-sickness artefacts. RMB-steer behavior (yaw on the Builder body, pitch on `camera_pivot.rotation.x`) is unchanged.

| Action                  | Binding          | Notes                                           |
|-------------------------|------------------|-------------------------------------------------|
| `move_forward` / back / left / right | WSAD + arrow keys | camera-relative strafing                |
| `jump`                  | Space            |                                                 |
| `turn_left`             | Q                | smooth yaw via `Builder.TURN_RATE_RAD_PER_S`    |
| `turn_right`            | E                | (same)                                          |
| `ui_inventory_toggle`   | I                | opens / closes the InventorySlideIn             |
| `interact`              | Left Shift       | walk-up: chest, workbench (event-based, see below) |
| `sleep_interact`        | Left Shift       | bed-interact at night → `Builder.start_sleep_lapse` |
| `ui_release_mouse`      | Tab              | toggle `Input.MOUSE_MODE_CAPTURED`              |
| Esc                     | hardcoded        | `main_scene._unhandled_key_input` opens Settings + releases mouse |
| Right mouse button (hold) + mouse | hardcoded | steer with the mouse — X rotates the builder (yaw, walking direction follows), Y is camera pitch. Mouse motion alone (no RMB) is ignored so the cursor stays free for UI. |
| `break` (mine) / `attack` | **LMB** | Minecraft-standard: left-click mines terrain bricks & attacks. (Swapped from RMB in feat(07) — break was on RMB, which conflicted with RMB camera-look and broke the "mine a tree" FTUE.) |
| `place` | **RMB** | Right-click places a brick. RMB-drag still steers the camera (click vs drag). |

Walk-up entities (chest, workbench) handle their key in `_unhandled_key_input` and call `get_viewport().set_input_as_handled()` so Builder's `_unhandled_input` (which also listens for `ui_inventory_toggle`) doesn't fire twice on the same frame. **Do not poll input via `Input.is_action_just_pressed` in `_process` for these — `set_input_as_handled` is a no-op against `Input` singleton polling and the inventory will open on top of the chest panel.**

`Hold SHIFT to open chest / workbench / sleep` is the canonical walk-up prompt phrasing. If you add a new walk-up entity, add a `ui.<entity>.<prompt>` key to `locale/en.po` and use the same "Hold SHIFT to ..." phrasing.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
use the /browse skill from gstack for all web browsing, never use mcp__claude-in-chrome__* tools, and lists the available skills: /office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review, /design-consultation, /design-shotgun, /design-html, /review, /ship, /land-and-deploy, /canary, /benchmark, /browse, /connect-chrome, /qa, /qa-only, /design-review, /setup-browser-cookies, /setup-deploy, /setup-gbrain, /retro, /investigate, /document-release, /document-generate, /codex, /cso, /autoplan, /plan-devex-review, /devex-review, /careful, /freeze, /guard, /unfreeze, /gstack-upgrade, /learn. Then ask the user if they also want to add gstack to the current project so teammates get it.
