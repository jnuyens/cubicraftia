# Phase 4: Multiplayer & seamless host failover - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — 4/4 grey areas accepted as proposed

<domain>
## Phase Boundary

Cubicraftia becomes social and multiplayer. A signed-in builder can add friends, generate single-use invite links that turn non-friends into mutual friends on accept, and host 1–4-player sessions over WebRTC P2P with text chat, host admin tools, and a seamless 2–4-second host failover when the host's connection dies. Discovery and signaling happen via a Go service over WebSocket; STUN/TURN via coturn; auth + friends graph via self-hosted Supabase. This phase ships the full pipe from "anonymous solo build" → "signed-in social session that keeps running through host disconnects." Voice chat, open lobbies, server-side chat persistence, and multi-region signaling are explicitly out of scope (see `<deferred>`).

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Host failover policy

- **Failover trigger:** A peer marks the host failed when its WebRTC data channel closes OR no keepalive has arrived in 6 seconds. The 6-second window balances false positives (transient mobile-cell drops) against handover budget — the DOCS §6.5 promise is "2–4 second handover", and the 6 s detection window plus ~1 s election plus ~1 s WebRTC reconnect lands inside the 4 s upper bound from the moment peers stop receiving state.
- **"Best-connection" metric:** Rolling average of host→peer RTT over the last 30 s of session time, lower = better. Tiebreaker is the peer-join index (older peer wins) so the answer is deterministic across all peers without negotiation.
- **Election protocol:** Each surviving peer computes the same election locally from the same shared view (RTT table + join-order). No vote, no signaling-server round-trip. This makes the election sub-second and works even if the signaling server is temporarily unreachable.
- **Reconciliation when the old host returns:** Latest-snapshot-wins, scoped per chunk. The old host's session ends at disconnect; their next session-open re-syncs from the new host's authoritative state. No operational transform, no chunk-level merge in v1 — the cost would be disproportionate for 2–4 player sessions and the failure mode is rare.

### Area 2 — Signaling server & sessions

- **Message envelope:** JSON over WebSocket. All messages carry `{"v":1,"type":...}` so we can roll forward the schema without breaking older clients. Binary formats (MessagePack, Protobuf) considered but rejected for v1: too small a wire-savings to justify the debugging cost, especially during the bring-up period.
- **Session idle timeout:** 15 minutes after the last peer activity → discovery server unpublishes the session. Host can re-publish on demand without restarting the world. Keeps the session listing fresh without forcing players to restart after a snack break.
- **Operator topology:** A single Cubicraftia-operated coturn + Go signaling instance on one Linux VPS for v1 public users. The Go signaling source ships open so power-users / dedicated communities can run their own instance. Federated multi-instance discovery is a v2 problem.
- **Capacity policy:** 200 concurrent sessions soft cap per signaling instance. Hitting it triggers an operator alert + manual horizontal-scale checklist. No auto-scale infra for v1 — Kubernetes is too much yak-shave for a 1-binary Go service at this scale.

### Area 3 — Accounts, auth, friends graph

- **Auth providers:** Email + password via Supabase GoTrue (default); Sign-in-with-Apple (required for App Store submission); Sign-in-with-Google. Discord SSO deferred — nice for the modder-adjacent audience but not store-critical.
- **Email verification gate:** Sign-up gives immediate play. The verification link is mailed in the background. Unverified accounts can play but cannot (a) send friend invites or (b) join sessions that are >24 hours old. Hard block at 7 days unverified. This keeps the funnel open while curbing spam-account abuse.
- **Friends graph schema (Postgres via Supabase):** `friendships(user_a UUID, user_b UUID, created_at, status)` with `CHECK (user_a < user_b)` for canonical ordering. One row per friendship, indexed both ways via expression index. Row-Level Security: a user can `SELECT` a row only if they're a member. Adjacency lists per user rejected as write-heavy and ugly to keep consistent.
- **Invite link tokens:** Random 128-bit token, base32-encoded (26 ASCII chars), single-use, 24-hour TTL per DOCS §6.3. Stored in `invites(token, host_uid, session_id, expires_at, redeemed_by)` and indexed on `token`. UUIDs would also work but base32 gives shorter URLs.

### Area 4 — State replication, chat, host admin

- **Replication protocol:** Host-authoritative event journal. Inventory autoload is already event-sourced from Phase 3 (this was an explicit Phase 3 promise — `apply_event`). Builder actions, brick place/break, hostile spawns, chest opens all become events the host applies, then broadcasts to peers. Peers apply received events; their state converges through the journal. Snapshots emit every 30 s for host-failover catch-up. Voxel chunks and StudGrid pages ship lazily on player proximity rather than per-frame.
- **Chat:** Ephemeral. No server-side persistence — chat lives in RAM on the host, dies when the session ends. Rate limit 5 messages per 10 s per player; over-limit messages dropped silently with a toast to the sender. Per-player mute is a local-only display filter. The harder Block from DOCS §6.2 is a separate hard-disjoin operation that also blocks cross-session discovery.
- **Host admin (DOCS §6.7 locks the three powers — these are the implementation choices):**
  - **Kick** — removes the player from the session, session-scoped only, kicked player can rejoin via fresh invite link.
  - **Freeze build** — per-player boolean flag in session state, replicated to all peers (so the visual lock applies on every screen), undoable from the same UI.
  - **Roll back** — host loads the last 30 min snapshot from world SQLite, confirmation modal required, broadcasts the new authoritative state to peers as a snapshot reset event.
- **Peer connection failure handling:** Adaptive thresholds. 3 consecutive lost keepalives surfaces a soft UI warning ("[Player] is laggy"). 6 lost drops the peer and the session continues. Disconnected peer can rejoin via the existing session if within a 5-minute reconnect window — otherwise they need a fresh invite path.

### Claude's Discretion

Implementation details below the architectural decisions above are at Claude's discretion: signaling-message field names, Go module layout, Supabase RLS policy syntax, specific WebRTC peer-config (ICE servers, bundle policy), Godot scene structure for the network manager, and choice of Profanity-filter library are all unconstrained beyond the principles above.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`src/autoload/inventory.gd`** is already event-sourced — `apply_event(event)` returns success/failure, every mutation goes through it. This is the foundational pattern for host-authoritative replication: events flowing between peers go through the same `apply_event` entry point.
- **`src/autoload/world_save.gd`** persists chunks + chest CRUD to SQLite with Zstd-compressed deltas. Snapshot creation for host failover reuses this — `save_world_snapshot()` is the obvious extension.
- **`src/autoload/features.gd`** has the feature-flag scaffolding (Phase 1). Multiplayer-only features can gate behind `Features.is_multiplayer_enabled()`.
- **`src/autoload/thermal_probe.gd`** + adaptive-quality dispatcher provides the hook for "downgrade network update rate on Tier-3 mobile."

### Established Patterns
- Autoloads live in `src/autoload/`. New autoloads (e.g., `NetworkManager`, `SessionRegistry`, `FriendsClient`) follow the same single-file `extends Node` pattern.
- Signals + connect-on-_ready is the canonical decoupling pattern (see WorldClock + Spawning).
- GUT tests live in `tests/unit/` and `tests/integration/`; conftest_phase3.gd is the model for a Phase-4-specific fixtures file.
- DOCS-driven naming: every UI string uses `tr("ui.<surface>.<key>")` and is added to `locale/en.po`.

### Integration Points
- `main_scene.gd` currently opens a default `dev_world_001` in survival mode on _ready (post-03 polish). Phase 4 replaces this with a title → sign-in → world-pick flow (some of which is Phase 6's job — Phase 4 only needs the API surface, not the UI).
- The `Builder` group + `inventory_toggle_requested` signal pattern (Phase 3) extends to remote builders: each remote builder is a `Builder` instance with `multiplayer_authority` set to its peer ID.
- `ChestEntity` registers via `Inventory.register_chest(chunk, tier, locked, contents)`. For multiplayer, the host writes; peers receive via event replication and call the same register API locally.

</code_context>

<specifics>
## Specific Ideas

- DOCS §6.5: the 2–4-second handover is a v1 *promise*. The 6 s keepalive trigger from Area 1 sits right at the upper bound of the promise — leaves no slack for slow election + WebRTC reconnect on bad mobile networks. Worth measuring at execution time and tuning down to 4 s if real-world handover is closer to 6 s than 4 s.
- DOCS §6.7 freeze-build wording explicitly says "Undoable." Implementation must surface the undo state in the admin UI, not just store the flag.
- The Phase 3 `WorldSave.save_chest()` already emits to SQLite. Snapshot creation for host-failover should reuse the same write path with a session-scoped `snapshot_id`.
- The single-VPS topology from Area 2 means the operator's coturn instance is the public TURN relay too — make sure the deployment recipe locks coturn to `restricted` mode (not open relay) per `DOCS §6` privacy stance.

</specifics>

<deferred>
## Deferred Ideas

- **Voice chat** — explicitly §9 deferred; v1.x at earliest.
- **Open lobbies / public discovery** — §9 deferred; v1 is friends-only by design.
- **Server-side chat persistence + moderation pipeline** — Phase 5 (safety/store readiness) territory, not Phase 4.
- **Federated multi-region signaling** — v2.
- **Discord SSO** — deferred until Phase 6 / store-ready phase.
- **Kubernetes auto-scale for signaling** — explicitly rejected for v1; revisit when concurrent-session count crosses 100 in production.
- **Operational transform / per-chunk merge** for old-host return reconciliation — rejected in Area 1 Q4; revisit only if "I came back and lost work" becomes a real user complaint.

</deferred>
