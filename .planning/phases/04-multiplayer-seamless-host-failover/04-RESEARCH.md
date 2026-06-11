---
phase: 4
slug: multiplayer-seamless-host-failover
created: 2026-05-29
domain: P2P networking, WebRTC, Go signaling, Supabase auth, host failover, GDScript replication
confidence: MEDIUM-HIGH
---

# Phase 4: Multiplayer & Seamless Host Failover — Research

**Researched:** 2026-05-29
**Domain:** Godot 4.6 WebRTC P2P multiplayer, Go WebSocket signaling, Supabase GoTrue auth + RLS, host-authoritative event journal, host failover state machine
**Confidence:** MEDIUM-HIGH

---

## Summary

Phase 4 ships the entire social + multiplayer pipe: account creation (email/password, SIWA, Google), friends graph (Supabase Postgres + RLS), invite links, WebRTC P2P sessions for 2-4 players, host-authoritative event journal extending the Phase 3 `apply_event` pattern, and seamless host failover in under 4 seconds. Three new GDScript autoloads (`NetworkManager`, `SessionRegistry`, `FriendsClient`) follow the existing `extends Node` singleton pattern already established in `src/autoload/`. The Go signaling server is a thin WebSocket relay and session registry; it never touches game state.

The most critical technical insight is that Godot 4.6 has **no built-in host-migration API** — [Proposal #7912](https://github.com/godotengine/godot-proposals/issues/7912) is still open. Host failover must be hand-built: detect disconnect via `server_disconnected` / keepalive expiry, run a local deterministic election, tear down the old `WebRTCMultiplayerPeer`, construct a new one with the elected peer as server (peer_id=1), reconnect all surviving peers, and replay the snapshot. This is the single highest-risk implementation area and deserves its own wave in the plan.

The Phase 3 `Inventory.apply_event` architecture is exactly the right foundation: events already carry `seq` numbers, the in-RAM `_journal` is populated, and the Zstd snapshot path in `world_save.gd` is reusable. Phase 4 extends `apply_event` to also broadcast each accepted event to peers via RPC.

**Primary recommendation:** Implement failover as a dedicated state machine in `NetworkManager` (not inline in world or UI code). Keep signaling-server protocol at JSON/v1 envelope throughout v1. Use `WebRTCMultiplayerPeer.create_server()` on the new host post-election and `create_client()` on all remaining peers, exchanging ICE via the Go signaling server which persists the session.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Area 1 — Host failover policy**
- Failover trigger: 6-second keepalive timeout OR data channel close
- Best-connection metric: 30-second rolling RTT average, lower = better
- Election: local deterministic, no signaling round-trip (RTT table + join-order)
- Old-host return: latest-snapshot-wins per chunk, no OT/CRDT

**Area 2 — Signaling server & sessions**
- Message envelope: JSON over WebSocket, `{"v":1,"type":...}` on every message
- Session idle timeout: 15 minutes
- Topology: single Cubicraftia-operated coturn + Go signaling on one Linux VPS
- Capacity: 200 concurrent sessions soft cap, manual horizontal scale

**Area 3 — Accounts, auth, friends graph**
- Auth providers: email+password (GoTrue), SIWA, Sign-in-with-Google
- Email verification gate: soft 7-day; unverified can play but cannot send invites or join sessions >24h old
- Friends schema: `friendships(user_a UUID, user_b UUID, created_at, status)` with `CHECK (user_a < user_b)`
- Invite tokens: random 128-bit, base32-encoded (26 chars), single-use, 24h TTL

**Area 4 — State replication, chat, host admin**
- Replication: host-authoritative event journal; `apply_event` already event-sourced
- Snapshots: every 30 s for failover catch-up; reuse `world_save.gd` Zstd path
- Chat: ephemeral, rate-limited 5/10s, local-only mute
- Kick: session-scoped, rejoin via fresh invite; Freeze build: per-player replicated bool; Roll back: host loads last 30-min snapshot, broadcasts `SNAPSHOT_RESET` event
- Reconnect window: 5 minutes for a disconnected peer to rejoin

### Claude's Discretion

Signaling-message field names, Go module layout, Supabase RLS policy syntax, specific WebRTC peer-config (ICE servers, bundle policy), Godot scene structure for the network manager, and choice of profanity-filter library are all unconstrained.

### Deferred Ideas (OUT OF SCOPE)
- Voice chat
- Open lobbies / public discovery
- Server-side chat persistence
- Federated multi-region signaling
- Discord SSO
- Kubernetes auto-scale
- OT/CRDT chunk merge for old-host return
- Title screen / avatar customisation UI (Phase 6 owns these)
- App Store / Play Store EULA + parental consent (Phase 5)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOC-06 | Full §6 implementation: accounts, friends + blocking, invite-by-link with auto-mutual-friends, sessions 1-4 players, host-authoritative listen-server, seamless host failover ≤4 s, text chat with profanity filter, host admin (kick/freeze/roll-back), nameplates | NetworkManager autoload + GoTrue REST calls + Supabase schema + failover state machine + event journal RPC bridge — all researched below |
</phase_requirements>

---

## Project Constraints (from CLAUDE.md)

- Engine: Godot 4.6, MIT license — locked, do not re-research
- Transport: `WebRTCMultiplayerPeer` via `webrtc-native` GDExtension (libdatachannel); `ENetMultiplayerPeer` for LAN/dev fallback — locked
- Signaling: Go service, WebSocket, single binary — locked
- NAT/TURN: coturn, restricted mode — locked
- Auth + friends: Supabase self-hosted (GoTrue + Postgres + RLS) — locked
- World persistence: godot-sqlite GDExtension — locked (extends Phase 3 schema)
- Scripting: GDScript for gameplay; Rust GDExtension for hot paths — locked
- License: GPL-3.0-or-later (STATE.md confirmed)
- Autoloads: `extends Node`, registered in `project.godot`, single-file pattern
- Tests: GUT in `tests/unit/` and `tests/integration/`; fixture class in `tests/conftest_phase4.gd`
- i18n: every UI string via `tr("ui.<surface>.<key>")` added to `locale/en.po`
- Player-facing terminology: brick / stud / builder — never "Lego"
- Renderer: `mobile` renderer enforced in `project.godot` (not Forward+)

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| WebRTC ICE negotiation | Client (GDScript `NetworkManager`) | Go signaling server (relay only) | Godot WebRTCPeerConnection owns the ICE agent; signaling server is a dumb relay |
| Session state (who is host, peer list, RTT) | Client `NetworkManager` autoload | Go signaling server (session record) | P2P: game state never goes through server; signaling server keeps a thin session record for reconnect |
| Friend graph + invites persistence | Supabase Postgres (backend) | `FriendsClient` autoload (cache) | Relational data (friendships, invites) lives in the DB with RLS; client caches for offline display |
| Auth / JWT issuance | Supabase GoTrue (backend) | `FriendsClient` autoload (stores token) | GoTrue is the authority; client holds access+refresh tokens in `user://auth.cfg` |
| Event replication (bricks, inventory, mobs) | Host `Inventory`/`StudGrid` autoloads + `NetworkManager` RPC | Peer `Inventory`/`StudGrid` apply_event path | Event journal already in RAM; NetworkManager bridges host → RPC → peer apply_event |
| Snapshot creation for failover | `WorldSave.save_world_snapshot()` (new method) | Host `NetworkManager` triggers on 30 s timer | Reuses Zstd + SQLite path already proven in Phase 3 |
| Host election | All peers, locally computed | No server round-trip | Deterministic: RTT table + join-order index; every peer computes the same result |
| Host promotion / multiplayer peer teardown | `NetworkManager` failover state machine | New host re-creates `WebRTCMultiplayerPeer` as server | Godot has no built-in migration; this is custom code |
| Text chat routing | Host routes all chat messages to all peers | Peers send to host via RPC | Host authority prevents A→B direct-chat race conditions; consistent with event journal pattern |
| Profanity filter | Client-side (check before broadcast) | Host re-checks on receive | CONTEXT §6.6: filtered text is `[filtered]` for all peers; sender sees original locally |
| In-world nameplates | Client, per remote builder node | — | `Label3D` parented to remote builder head bone; no network traffic per frame |
| Network status HUD | Client, polling `NetworkManager.get_peer_rtt()` | — | RTT bucket computed locally from keepalive timestamps; HUD queries at 1 Hz |

---

## Standard Stack

### Core (all locked in CLAUDE.md)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Godot 4.6 | 4.6 stable | Game engine | Locked in CLAUDE.md; MIT; cross-platform mobile |
| webrtc-native GDExtension | latest (Godot 4.4+ compat) | `WebRTCPeerConnection` on native platforms | Official Godot plugin, libdatachannel under the hood, all-platform binary |
| ENetMultiplayerPeer | built-in | LAN / dev fallback transport | No extra dep; works when peers are on same network |
| godot-sqlite GDExtension | v4.7 (installed in Phase 3) | SQLite for world + snapshot storage | Already in project (STATE.md `godot-sqlite-demo-zip`) |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Go standard library (`net/http`, `golang.org/x/net/websocket` or `nhooyr.io/websocket`) | Go 1.22+ | Go signaling server WebSocket | Go's stdlib covers WebSocket via an upgrade; use a thin wrapper |
| coturn | latest stable | STUN + TURN relay | On the Linux VPS; handles symmetric-NAT/CGNAT fallback |
| Supabase self-hosted (Docker Compose) | latest | GoTrue auth + Postgres + PostgREST | Friends graph + auth; self-hosted on same VPS |

### No New Client-Side Package Installs

Phase 4 adds no new GDExtension dependencies beyond what is already in the project. All new client-side code is GDScript autoloads + GDScript scene controllers. The Go signaling server and Supabase are server-side services, not client packages.

**Package Legitimacy Audit:** Not applicable — Phase 4 introduces no new GDExtension packages on the Godot client. The webrtc-native GDExtension was already planned from Phase 1. Go and Supabase are server-side only.

---

## Architecture Patterns

### System Architecture Diagram

```
[Godot client — Host]                         [Godot clients — Peers]
  NetworkManager                                 NetworkManager
  |                                              |
  |-- Inventory.apply_event(event)               |-- receives RPC
  |-- StudGrid.place/remove                      |-- Inventory.apply_event(event)
  |-- broadcasts event via RPC ----------------> |
  |-- 30s: WorldSave.save_world_snapshot()       |
  |                                              |
  |<------- keepalive pings (1 Hz) ------------->|
  |
  |== WebRTC data channel (libdatachannel) ======|
  |                                              |
  v                                              v
[Go signaling server — Linux VPS]
  WebSocket endpoint /ws
  session registry (in-memory: session_id → {host_uid, peer_list, published_at})
  invite token store (in-memory + Supabase sync)
  |
  |-- relays WebRTC offer/answer/ICE only
  |-- publishes/unpublishes sessions
  |
  v
[Supabase (GoTrue + Postgres)]
  friendships table (RLS)
  invites table (RLS)
  auth.users (GoTrue JWT)
  |
  [coturn — same VPS]
    STUN: 3478
    TURN: 3478 (relay fallback for CGNAT)
```

**Entry points:**
- Player taps "Join" → `FriendsClient` fetches session → `NetworkManager` starts WebRTC offer via signaling server
- Player generates invite → Go server mints token, stores in `invites` table → link deep-links into app → sign-in → join
- Host closes app → peers detect via keepalive expiry → `NetworkManager` failover state machine fires

### Recommended Project Structure (Phase 4 additions)

```
src/
├── autoload/
│   ├── network_manager.gd       # WebRTC peer + failover state machine + keepalive
│   ├── session_registry.gd      # Local session state: peer list, RTT table, join order
│   └── friends_client.gd        # Supabase REST calls (auth, friends, invites)
├── ui/
│   ├── sign_in_panel.gd/.tscn   # Surface 1: email/password + OAuth (Phase 4 minimal)
│   ├── friends_panel.gd/.tscn   # Surface 2: friends list slide-in (reuses slide-in chrome)
│   ├── invite_modal.gd/.tscn    # Surface 4: invite link generation modal
│   ├── join_screen.gd/.tscn     # Surface 5: full-screen join progress overlay
│   ├── players_tab.gd           # Surface 6: Players tab injected into settings_menu.tscn
│   ├── chat_overlay.gd/.tscn    # Surface 7: chat input + history panel
│   └── handover_screen.gd/.tscn # Surface 9: failover overlay (CanvasLayer 100)
├── networking/
│   └── profanity_filter.gd      # Word-list filter (open list, per DOCS §6.6)
└── tests/
    ├── conftest_phase4.gd        # Phase 4 fixture class (mirrors conftest_phase3.gd)
    └── unit/
        ├── test_election_algorithm.gd
        ├── test_event_replication.gd
        ├── test_keepalive_logic.gd
        ├── test_friends_schema.gd
        ├── test_invite_token.gd
        └── test_chat_rate_limit.gd
```

### Pattern 1: WebRTCMultiplayerPeer — Host Setup

[CITED: docs.godotengine.org/en/stable/classes/class_webrtcmultiplayerpeer.html]

The host calls `create_server()` (which assigns itself peer_id=1). Each joining peer first exchanges offer/answer + ICE with the host via the Go signaling server, then is added to the mesh via `add_peer()`.

```gdscript
# NetworkManager — host path
func _start_as_host() -> void:
    _rtc_mp = WebRTCMultiplayerPeer.new()
    _rtc_mp.create_server()
    multiplayer.multiplayer_peer = _rtc_mp
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_signaling_peer_offer(peer_id: int, sdp: String) -> void:
    var conn := WebRTCPeerConnection.new()
    conn.initialize(_build_ice_config())
    conn.session_description_created.connect(
        func(type, s): _signaling_send_answer(peer_id, type, s))
    conn.ice_candidate_created.connect(
        func(m, i, c): _signaling_send_ice(peer_id, m, i, c))
    _rtc_mp.add_peer(conn, peer_id)
    conn.set_remote_description("offer", sdp)

func _build_ice_config() -> Dictionary:
    # Source: WebRTCPeerConnection.initialize() docs
    return {
        "iceServers": [
            {"urls": ["stun:cubicraftia.com:3478"]},
            {
                "urls": ["turn:cubicraftia.com:3478"],
                "username": _turn_user,
                "credential": _turn_credential,
            }
        ]
    }
```

### Pattern 2: WebRTCMultiplayerPeer — Client/Peer Setup

[CITED: docs.godotengine.org/en/stable/classes/class_webrtcmultiplayerpeer.html]

```gdscript
# NetworkManager — peer path (joining a session)
func _start_as_peer(my_peer_id: int) -> void:
    _rtc_mp = WebRTCMultiplayerPeer.new()
    _rtc_mp.create_client(my_peer_id)
    multiplayer.multiplayer_peer = _rtc_mp
    multiplayer.server_disconnected.connect(_on_host_disconnected)
    # Create connection to host (peer_id=1)
    var conn := WebRTCPeerConnection.new()
    conn.initialize(_build_ice_config())
    conn.session_description_created.connect(
        func(type, s): _signaling_send_offer(1, type, s))
    conn.ice_candidate_created.connect(
        func(m, i, c): _signaling_send_ice(1, m, i, c))
    _rtc_mp.add_peer(conn, 1)
    conn.create_offer()
```

### Pattern 3: RPC Bridge for Event Journal

[VERIFIED: Godot 4 high-level multiplayer docs — CITED: docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html]

The host runs `Inventory.apply_event()` locally, then broadcasts the stamped event to all peers. Peers call the same `apply_event()` locally on receipt. This means the journal-replay logic is identical for solo and multiplayer.

```gdscript
# NetworkManager — host-side event broadcast
# Called by Inventory after a successful apply_event()
func broadcast_event(event: Dictionary) -> void:
    if not multiplayer.is_server():
        return  # Only host broadcasts
    _receive_replicated_event.rpc(event)

# On all peers (including host if call_local used)
@rpc("authority", "call_remote", "reliable")
func _receive_replicated_event(event: Dictionary) -> void:
    # Peers apply the event through the same path as solo play
    Inventory.apply_event(event)
    # StudGrid events (place/break) are dispatched similarly
```

**Critical detail:** `apply_event` already stamps `seq` numbers and appends to `_journal`. Peers replaying a snapshot load the journal from 0 and fast-forward. No gap in seq = clean replay.

### Pattern 4: Keepalive + RTT Measurement

[ASSUMED based on common P2P patterns; no authoritative Godot-specific source found]

```gdscript
# NetworkManager — keepalive loop (host sends; peers respond)
const KEEPALIVE_INTERVAL_S := 1.0
const KEEPALIVE_TIMEOUT_S := 6.0  # 6 lost = disconnect (CONTEXT Area 1)
const KEEPALIVE_WARN_S := 3.0     # 3 lost = "Laggy" label (CONTEXT Area 4)

func _process(delta: float) -> void:
    _keepalive_accum += delta
    if _keepalive_accum >= KEEPALIVE_INTERVAL_S:
        _keepalive_accum = 0.0
        if multiplayer.is_server():
            _send_keepalive_to_all_peers()
        _check_peer_timeouts()

@rpc("authority", "call_remote", "unreliable")
func _keepalive_ping(server_time_us: int) -> void:
    # Peer replies with the server timestamp so host can measure RTT
    _keepalive_pong.rpc_id(1, server_time_us, Time.get_ticks_usec())

@rpc("any_peer", "call_remote", "unreliable")
func _keepalive_pong(sent_us: int, peer_received_us: int) -> void:
    var peer_id := multiplayer.get_remote_sender_id()
    var rtt_us := Time.get_ticks_usec() - sent_us
    SessionRegistry.update_peer_rtt(peer_id, float(rtt_us) / 1000.0)  # ms
    SessionRegistry.reset_keepalive_counter(peer_id)
```

### Anti-Patterns to Avoid

- **Do NOT use `MultiplayerSynchronizer`** for brick/inventory state — it handles primitives only and creates complex property-binding overhead. The event journal RPC is simpler and already proven. [ASSUMED: based on ziva.sh/blogs/godot-multiplayer review showing MultiplayerSynchronizer limitations for complex state]
- **Do NOT rebuild WebRTCMultiplayerPeer on every peer disconnect** — only rebuild on host election (the failover path). Normal peer disconnects are handled by `remove_peer()`.
- **Do NOT re-issue keepalives from the signaling server** — the Go signaling server is not in the hot path after WebRTC is established. All keepalives are peer-to-peer over the data channel.
- **Do NOT store chat history in the journal** — chat is ephemeral per CONTEXT Area 4. Chat messages are fire-and-forget RPCs, not journaled events.
- **Do NOT use `create_mesh()` for the 2-4 player case** — the listen-server model (host=server, peers=clients) is simpler, easier to reason about, and matches the host-authoritative design. Mesh topology requires all-to-all connections; in our model only the host needs a full view.

---

## Go Signaling Server

### WebSocket Message Envelope

All messages carry `{"v":1,"type":"<type>","payload":{...}}`. The `v` field future-proofs the schema.

[CITED: 04-CONTEXT.md Area 2]

```json
// Client → Server: register (on WebSocket connect)
{"v":1,"type":"register","payload":{"uid":"<supabase_user_id>","session_id":"<optional>"}}

// Client → Server: publish session (host publishes when second player joins)
{"v":1,"type":"publish_session","payload":{"session_id":"<uuid>","world_name":"<str>","max_peers":4}}

// Client → Server: unpublish session (host closed world or idle 15 min)
{"v":1,"type":"unpublish_session","payload":{"session_id":"<uuid>"}}

// Client → Server: WebRTC offer (peer sends to host)
{"v":1,"type":"offer","payload":{"to_uid":"<host_uid>","sdp":"<sdp_string>"}}

// Client → Server: WebRTC answer (host sends back to peer)
{"v":1,"type":"answer","payload":{"to_uid":"<peer_uid>","sdp":"<sdp_string>"}}

// Client → Server: ICE candidate (either direction)
{"v":1,"type":"ice","payload":{"to_uid":"<target_uid>","mid":"<str>","index":<int>,"candidate":"<str>"}}

// Client → Server: update host pointer after failover
{"v":1,"type":"update_host","payload":{"session_id":"<uuid>","new_host_uid":"<uid>"}}

// Server → Client: session list (friend has open session)
{"v":1,"type":"session_list","payload":[{"session_id":"<uuid>","host_uid":"<uid>","world_name":"<str>","peer_count":<int>}]}

// Server → Client: peer joined (host receives when someone connects)
{"v":1,"type":"peer_joined","payload":{"peer_uid":"<uid>","peer_id":<int>}}

// Server → Client: error
{"v":1,"type":"error","payload":{"code":"<str>","message":"<str>"}}
```

### Session Lifecycle

```
1. Host opens world → no session published yet
2. Second player joins → host calls publish_session → Go server registers session
3. Go server notifies friends (who are online) via their WebSocket connections
4. Session stays published until: (a) host calls unpublish, (b) 15-min idle timer
5. During failover: surviving peers call update_host with new_host_uid
6. New host re-publishes session with new host identity
```

### Go Module Layout (at discretion)

```
cmd/signaling/main.go       — entry point, flag parsing, shutdown
internal/hub/hub.go         — WebSocket connection hub (goroutine per conn)
internal/hub/session.go     — Session registry (in-memory map, RWMutex)
internal/hub/relay.go       — Offer/answer/ICE forwarding
internal/hub/auth.go        — Supabase JWT verification (validate Bearer token)
internal/config/config.go   — env-var config (PORT, SUPABASE_URL, JWT_SECRET)
```

**JWT verification:** The Go server verifies the Supabase JWT (HS256 shared secret or RS256 public key from Supabase `SUPABASE_JWT_SECRET`) on each WebSocket connection upgrade. Unverified connections are rejected. This prevents anonymous connection abuse.

### Capacity Policy (CONTEXT Area 2)

- 200 concurrent sessions soft cap; operator alert on breach
- Per-session peer limit: 4 (enforced by the server when forwarding `publish_session`)
- WebSocket timeout: 90 s idle (ping/pong at 30 s); dead connections cleaned from hub

### Deployment Recipe

```bash
# Build (single static binary, Linux amd64)
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /usr/local/bin/cubicraftia-signaling ./cmd/signaling

# Systemd unit (single VPS)
[Unit]
Description=Cubicraftia WebRTC Signaling Server
After=network.target

[Service]
ExecStart=/usr/local/bin/cubicraftia-signaling \
  -port=8080 \
  -supabase-url=https://supabase.cubicraftia.com \
  -jwt-secret=${SUPABASE_JWT_SECRET}
Restart=on-failure
EnvironmentFile=/etc/cubicraftia/signaling.env

[Install]
WantedBy=multi-user.target
```

---

## Supabase Schema

### Postgres Tables + RLS Policies

[VERIFIED: supabase.com/docs/guides/database/postgres/row-level-security]

```sql
-- 1. Friendships table
CREATE TABLE public.friendships (
  user_a     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_b     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status     TEXT NOT NULL DEFAULT 'active',  -- 'active' | 'blocked'
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_a, user_b),
  CONSTRAINT canonical_order CHECK (user_a < user_b)
);

-- Index both directions for fast adjacency queries
CREATE INDEX friendships_user_a_idx ON public.friendships (user_a);
CREATE INDEX friendships_user_b_idx ON public.friendships (user_b);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- Users may SELECT their own friendships (either side)
CREATE POLICY "Users view own friendships"
  ON public.friendships FOR SELECT
  TO authenticated
  USING (
    (SELECT auth.uid()) = user_a
    OR (SELECT auth.uid()) = user_b
  );

-- Users may INSERT a friendship if they are one of the members
-- The CHECK (user_a < user_b) constraint enforces canonical ordering
CREATE POLICY "Users create friendships"
  ON public.friendships FOR INSERT
  TO authenticated
  WITH CHECK (
    ((SELECT auth.uid()) = user_a OR (SELECT auth.uid()) = user_b)
    AND user_a < user_b
  );

-- Users may DELETE (unfriend) a friendship they're part of
CREATE POLICY "Users delete own friendships"
  ON public.friendships FOR DELETE
  TO authenticated
  USING (
    (SELECT auth.uid()) = user_a
    OR (SELECT auth.uid()) = user_b
  );


-- 2. Invites table
CREATE TABLE public.invites (
  token        TEXT PRIMARY KEY,         -- 26-char base32 token
  host_uid     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id   TEXT NOT NULL,
  expires_at   TIMESTAMPTZ NOT NULL,
  redeemed_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX invites_token_idx ON public.invites (token);
CREATE INDEX invites_host_idx  ON public.invites (host_uid);

ALTER TABLE public.invites ENABLE ROW LEVEL SECURITY;

-- Hosts can see invites they issued
CREATE POLICY "Hosts view own invites"
  ON public.invites FOR SELECT
  TO authenticated
  USING ( (SELECT auth.uid()) = host_uid );

-- Hosts can create invites
CREATE POLICY "Hosts create invites"
  ON public.invites FOR INSERT
  TO authenticated
  WITH CHECK ( (SELECT auth.uid()) = host_uid );

-- Any authenticated user can redeem a valid, unexpired, unredeemed invite
-- (UPDATE sets redeemed_by to the caller's UID)
CREATE POLICY "Users redeem invites"
  ON public.invites FOR UPDATE
  TO authenticated
  USING ( expires_at > NOW() AND redeemed_by IS NULL )
  WITH CHECK ( redeemed_by = (SELECT auth.uid()) );


-- 3. Profiles (display names, builder color, etc.)
CREATE TABLE public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username    TEXT NOT NULL UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read profiles (for friend search)
CREATE POLICY "Authenticated users read profiles"
  ON public.profiles FOR SELECT
  TO authenticated
  USING ( TRUE );

-- Users update only their own profile
CREATE POLICY "Users update own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING ( (SELECT auth.uid()) = id )
  WITH CHECK ( (SELECT auth.uid()) = id );
```

### GoTrue Auth Providers

[CITED: supabase.com/docs/reference/self-hosting-auth/introduction]

GoTrue REST endpoints used by `FriendsClient`:

```
POST /auth/v1/signup           — email + password registration
POST /auth/v1/token?grant_type=password  — email + password sign-in → {access_token, refresh_token, expires_in, user}
POST /auth/v1/token?grant_type=refresh_token — token refresh
POST /auth/v1/token?grant_type=id_token    — SIWA / Google native token exchange
```

SIWA native flow (iOS):
1. Apple Authentication Services → identity_token (JWT)
2. `FriendsClient` posts to `/auth/v1/token?grant_type=id_token` with `{"provider":"apple","id_token":"<jwt>"}`
3. GoTrue verifies with Apple public keys → issues Supabase access_token

**Token storage:** `user://auth.cfg` [auth] section: `access_token`, `refresh_token`, `expires_at`. FriendsClient auto-refreshes before expiry.

### Email Verification Gate (CONTEXT Area 3)

GoTrue sends verification email on signup automatically. The Godot client reads `user.email_confirmed_at` from the `/auth/v1/user` endpoint:
- `null` or absent → unverified state
- After 7 days unverified → block invite-send + block joining old sessions (enforced client-side; server validates via JWT claim)

GDScript HTTP call pattern (Godot 4): [CITED: docs.godotengine.org/en/stable/tutorials/networking/http_request_class.html]

```gdscript
func _sign_in(email: String, password: String) -> void:
    var body := JSON.stringify({"email": email, "password": password})
    var headers := ["Content-Type: application/json", "apikey: " + _anon_key]
    $HTTPRequest.request(
        _supabase_url + "/auth/v1/token?grant_type=password",
        headers,
        HTTPClient.METHOD_POST,
        body
    )

func _on_request_completed(result, code, _headers, body):
    if result != HTTPRequest.RESULT_SUCCESS or code != 200:
        sign_in_failed.emit(tr("ui.signin.error_network"))
        return
    var json: Variant = JSON.parse_string(body.get_string_from_utf8())
    if json == null:
        sign_in_failed.emit(tr("ui.signin.error_network"))
        return
    _access_token = json.get("access_token", "")
    _refresh_token = json.get("refresh_token", "")
    _user_id = json.get("user", {}).get("id", "")
    _save_tokens()
    signed_in.emit(_user_id)
```

---

## Host Failover State Machine

### States

```
IDLE                  — solo play, no MP session
CONNECTING            — WebRTC handshake in progress
CONNECTED_AS_HOST     — is the server (peer_id=1), owns world state
CONNECTED_AS_PEER     — is a client, receiving replicated events
FAILOVER_DETECTING    — keepalive expired; not yet elected
FAILOVER_ELECTED      — won election; promoting to host
FAILOVER_PROMOTING    — rebuilding WebRTCMultiplayerPeer as server
FAILOVER_COMPLETE     — now host; peers reconnecting
FAILOVER_WAITING      — did not win; waiting for new host to publish
RECONNECTING          — lost connection; retrying (within 5-min window)
DISCONNECTED          — session ended
```

### State Machine Transitions

```
CONNECTED_AS_PEER
  → keepalive timeout (6 s) or server_disconnected signal
  → FAILOVER_DETECTING (start election timer: 200ms to let all peers measure)

FAILOVER_DETECTING
  → election computed (local, deterministic):
      if am_elected:      → FAILOVER_ELECTED
      if not_elected:     → FAILOVER_WAITING

FAILOVER_ELECTED
  → promote local snapshot to authoritative (call WorldSave.save_world_snapshot())
  → FAILOVER_PROMOTING

FAILOVER_PROMOTING
  → tear down old WebRTCMultiplayerPeer
  → create new: _rtc_mp.create_server()
  → multiplayer.multiplayer_peer = _rtc_mp
  → notify Go signaling server: update_host
  → wait for peers to reconnect (signal: peer_connected)
  → FAILOVER_COMPLETE

FAILOVER_WAITING
  → listen on signaling server for update_host notification
  → when new host known: reconnect via signaling (offer → answer → ICE)
  → when WebRTC reconnected: request snapshot from new host
  → apply snapshot (SNAPSHOT_RESET event)
  → CONNECTED_AS_PEER (new host)

FAILOVER_COMPLETE (new host)
  → emit host_failover_complete signal (Surface 9 handover screen listens)
```

### Election Algorithm (GDScript)

[ASSUMED: canonical algorithm per CONTEXT Area 1; deterministic election without signaling round-trip]

```gdscript
# SessionRegistry — computes election result locally
# All surviving peers have the same RTT table + join order
func compute_elected_host() -> int:
    # RTT table: {peer_id: float (ms, 30s rolling average)}
    var candidates: Array = _surviving_peers.keys()  # does not include failed host
    candidates.sort_custom(func(a, b):
        var rtt_a: float = _rtt_rolling_avg.get(a, INF)
        var rtt_b: float = _rtt_rolling_avg.get(b, INF)
        if absf(rtt_a - rtt_b) < 1.0:
            # Tiebreaker: lower join-order index wins (older peer)
            return _join_order.get(a, INF) < _join_order.get(b, INF)
        return rtt_a < rtt_b
    )
    return candidates[0] if candidates.size() > 0 else multiplayer.get_unique_id()

func am_i_elected() -> bool:
    return compute_elected_host() == multiplayer.get_unique_id()
```

### Snapshot Reconciliation (CONTEXT Area 1)

When the old host returns:
1. Old host opens the app → finds the session is now hosted by another peer
2. Old host joins as a regular peer via invite or auto-reconnect
3. New host detects their `peer_connected`
4. New host sends a `SNAPSHOT_RESET` event containing the current authoritative snapshot
5. Old host's local state is overwritten by the snapshot (latest-snapshot-wins)

This is the same flow as a fresh mid-session join — no special old-host path.

---

## Snapshot / Replication

### Event Journal Extension

`Inventory._journal` already exists and is populated with stamped events. Phase 4 adds:

1. **`NetworkManager.broadcast_event(event: Dictionary)`** — called after every successful `apply_event()` on the host.
2. **`NetworkManager._receive_replicated_event(event: Dictionary)`** — RPC on peers that calls `Inventory.apply_event(event)`.
3. **Stud-grid events** — `StudGrid.placed` and `StudGrid.removed` signals are wrapped into events and added to the journal: `{"kind":"PLACE","anchor":...,"def_id":...,"colour_index":...}`, `{"kind":"REMOVE","anchor":...}`.
4. **Creature events** — spawns and deaths from `Spawning` go through the journal as `{"kind":"CREATURE_SPAWN","kind_id":...,"pos":...}` and `{"kind":"CREATURE_DEATH","kind_id":...}`.

### Snapshot Cadence

`WorldSave.save_world_snapshot(snapshot_id)` — new method, 30-second timer on host:

```gdscript
# WorldSave extension (new method)
func save_world_snapshot(snapshot_id: String) -> bool:
    # snapshot_id = "snap_" + str(Time.get_unix_time_from_system())
    # Writes to world.meta.sqlite snapshots table:
    #   snapshots(snapshot_id TEXT PK, created_at REAL, chunk_blob BLOB, inventory_blob BLOB)
    # Reuses Zstd path from _save_chunk + var_to_bytes(Inventory.get_all_state())
    ...
```

On failover, the elected host promotes its most recent local snapshot by:
1. Calling `save_world_snapshot("failover_" + str(Time.get_unix_time_from_system()))`
2. Sending the snapshot blob to reconnecting peers via a large `SNAPSHOT_RESET` RPC (split into ~1400-byte UDP-safe chunks if using unreliable, or send as single reliable message)

### Voxel Chunk Lazy Shipping

Voxel terrain (godot_voxel, `VoxelStreamSQLite`) is NOT replicated event-by-event. On join:
1. The new peer receives the world seed from the session metadata
2. Godot_voxel regenerates terrain procedurally from the seed
3. Only modified chunks (those in `stud_grid_chunks` and modified terrain) are shipped lazily as the peer enters their proximity

[ASSUMED: standard practice for voxel MP games; confirmed by godot_voxel documentation pattern of seed-based generation with delta-only persistence]

---

## Pitfalls

### Pitfall 1: iOS Background App Suspension Kills WebRTC
**What goes wrong:** iOS suspends app after ~1 minute in background (documented in react-native-webrtc issue #942). libdatachannel connections close. When the user returns, peers see a disconnect.
**Why it happens:** iOS OS-level network suspension; no socket keepalive survives.
**How to avoid:**
- Treat iOS background as a graceful disconnect: on `ApplicationFocusChanged` signal (false), call `NetworkManager.begin_graceful_disconnect()` which notifies peers and signals the host to persist a checkpoint.
- On foreground return: trigger the 5-minute reconnect window path, not a failover election.
- Persist world state immediately on background (bypass the 30-second coalesce timer).
**Warning signs:** Peer shows as "disconnected" after user returns from background on iOS.

### Pitfall 2: CGNAT on Cellular — STUN Fails, TURN Required
**What goes wrong:** ~15-30% of connections (higher on cellular) are behind symmetric NAT or CGNAT. STUN cannot traverse these. ICE candidate gathering succeeds but `STATE_CONNECTED` is never reached.
**Why it happens:** Mobile ISPs use CGNAT heavily. ICE falls back to TURN but only if coturn is configured correctly.
**How to avoid:**
- Always include the TURN server in ICE config (not just STUN).
- Use coturn `lt-cred-mech` (long-term credentials), not open relay — CONTEXT Area 2 says "restricted mode."
- Show "Relay" badge (Surface 10) when `NetworkManager` detects the connection type is TURN relay (detectable via ICE candidate type in the selected candidate pair).
**Warning signs:** Two cellular peers can't connect; removing TURN config doesn't help (they never had direct path).

### Pitfall 3: Peer ID Conflict After Failover
**What goes wrong:** The new host is promoted and creates `WebRTCMultiplayerPeer.create_server()` — it takes peer_id=1. But surviving peers still have the old host registered with peer_id=1 in their local tables.
**Why it happens:** Godot's High-Level Multiplayer hardcodes server=1. After failover, the elected peer must discard all old peer state and rebuild.
**How to avoid:**
- On election win: `_rtc_mp.close()` then `_rtc_mp = WebRTCMultiplayerPeer.new()` + `create_server()`.
- Signal `SessionRegistry.clear_all_peers()` before rebuilding.
- Peers that were NOT the old host must also discard old `_rtc_mp` and create a fresh `create_client(my_peer_id)`, then re-do the ICE negotiation with the new host via signaling server.
**Warning signs:** RPCs reach the wrong peer; `multiplayer.get_remote_sender_id()` returns unexpected values.

### Pitfall 4: Signaling Server Not Reachable During Failover
**What goes wrong:** Election is local and deterministic — but the winning peer needs to notify the signaling server (`update_host`) so other peers know where to reconnect. If the signaling server is temporarily down, reconnecting peers have no rendezvous.
**Why it happens:** Network partition or VPS blip during the exact moment of failover.
**How to avoid:**
- Surviving peers have each other's ICE connection data from the original handshake. If the signaling server is unreachable, peers attempt direct-reconnect using the existing ICE candidates cached from the initial connection.
- 5-minute reconnect window gives time for the signaling server to recover.
- Design `update_host` as an idempotent upsert so retries are safe.
**Warning signs:** Peers show "Connecting…" indefinitely on handover screen.

### Pitfall 5: Mid-Session Join Race During Failover
**What goes wrong:** A peer is in the middle of joining (ICE negotiation in progress) when the host disconnects. The joining peer has a partially established connection to the old host.
**Why it happens:** Race between join flow and host disconnect.
**How to avoid:**
- `NetworkManager` tracks joining state: if `CONNECTING` when `server_disconnected` fires, abort the in-progress join and re-enter as a fresh joiner to the new host once it publishes.
- Show "Connecting…" on Surface 5 with a retry button (timeout after 30 s, show error).
**Warning signs:** Joining peer's handover screen never completes.

### Pitfall 6: Host Disconnect During a Snapshot Write
**What goes wrong:** Host is mid-`checkpoint()` (close_db → atomic rename → reopen) when device loses power or app is killed. SQLite may be in an inconsistent state.
**Why it happens:** Atomic rename + Zstd compression takes ~50-200ms; kill during this window.
**How to avoid:** The existing `WorldSaveIo.load_canonical_or_bak()` + `.bak.1/.bak.2/.bak.3` rolling backup chain (already in `world_save.gd`) is the mitigation. Failover snapshot is created BEFORE the old host considers itself disconnected — peers have the last successful checkpoint.
**Warning signs:** World rolls back more than 30 s unexpectedly on failover.

### Pitfall 7: ICE Candidate Exhaustion (Trickle ICE Timing)
**What goes wrong:** ICE candidates arrive at different rates on different networks. If the peer adds candidates before `set_remote_description()`, they are silently dropped by libdatachannel.
**Why it happens:** Trickle ICE requires SDP to be set before adding candidates.
**How to avoid:**
- Queue ICE candidates received from signaling server while SDP has not yet been set.
- Only call `add_ice_candidate()` after `set_remote_description()` returns.
- Pattern: maintain `_pending_ice_candidates: Array` per peer; flush after SDP set.
**Warning signs:** Connection hangs at ICE gathering on some networks but works on others.

### Pitfall 8: GDScript Autoload Order for NetworkManager
**What goes wrong:** `NetworkManager` calls `Inventory.apply_event()` — if NetworkManager loads before Inventory in the autoload sequence, the reference may be null.
**Why it happens:** Godot autoloads initialize top-to-bottom in project.godot.
**How to avoid:** Insert `NetworkManager`, `SessionRegistry`, and `FriendsClient` AFTER `Inventory` and `WorldSave` in `project.godot`. Use `get_node_or_null('/root/Inventory')` with null-check for safety in `_ready()`.
**Warning signs:** `Inventory: Null reference` errors at startup.

---

## Existing Pattern Reuse

### 1. `Inventory.apply_event` — Event Journal (Phase 3)

The `_journal` array, `_next_seq` counter, and the `apply_event → stamp seq → append` pipeline are exactly the substrate Phase 4 needs. The only Phase 4 addition is:

```gdscript
# In inventory.gd — add after line 285 (after _journal.append(event))
if NetworkManager.is_multiplayer_active() and multiplayer.is_server():
    NetworkManager.broadcast_event(event)
```

The `push_warning("unknown event kind")` already handles forward-compatible events from newer clients.

### 2. `WorldSave.checkpoint()` + `WorldSaveIo` — Snapshot Extension

The Zstd-compressed, atomic-rename, 3-backup-rolling checkpoint is already battle-tested. Phase 4 adds a `snapshots` table to `world.meta.sqlite` (schema v3 migration) and a `save_world_snapshot(snapshot_id)` method that writes a full world state blob. The migration follows the existing `_migrate_1_to_2()` transactional pattern.

### 3. `inventory_slide_in.gd` Chrome — Friends Panel + Chat Panel

`_setup_panel_style`, `_animate_to`, `_snap_to_nearest`, `PEEK_HEIGHT`, `TWEEN_DURATION_S`, `SIDEBAR_WIDTH` are all reused verbatim (per 04-UI-SPEC.md Surface 2). The Friends panel extends the mutual-exclusion contract via `notify_friends_open(bool)` following the existing `notify_inventory_open` / `notify_palette_open` pattern in `mobile_overlay.gd`.

### 4. `settings_menu.gd` — Players Tab Injection

The existing `settings_menu.tscn` gets a new "Players" tab injected as tab[0]. The `_apply_tab_style` pattern (accent-yellow 2px bottom border) already exists; Phase 4 calls it for the Players tab header. The existing Graphics/BrickPacks/About sections shift to a single "Settings" tab.

### 5. `features.gd` — Multiplayer Gate

`Features.is_enabled("large_servers_5plus")` is already false. Phase 4 adds a runtime gate (not a feature flag): `NetworkManager.is_multiplayer_active()` returns true when a session has ≥2 peers. This gates the Network Status HUD (Surface 10) and nameplate visibility.

### 6. `thermal_probe.gd` / Adaptive Quality — Network Rate Limiter Hook

`ThermalProbe` already dispatches to `settings_menu._apply_live_settings()`. Phase 4 adds `NetworkManager.set_update_rate_hz(int)` which is called by the adaptive-quality dispatcher on Tier-3 devices — reducing broadcast frequency from 20 Hz to 5 Hz when thermal headroom is low.

### 7. `toasts.gd` — "You are now friends" Toast

`Toasts.show("ui.join.new_friends_toast", "info")` is called by `FriendsClient` after invite redemption creates a friendship. The existing `toast_requested` signal + renderer (Plan 03-05 phase's Plan 06 deferred wiring) already provides the display pipeline.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | GUT (Godot Unit Test) — already installed |
| Config file | `tests/gut_config.cfg` — existing |
| Quick run | `godot --headless -s tests/gut_main.gd -- -gtest=tests/unit/test_*.gd` |
| Full suite | `godot --headless -s tests/gut_main.gd` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOC-06 | Election algorithm: lowest RTT wins, join-order tiebreak | Unit | `-- -gtest=tests/unit/test_election_algorithm.gd` | ❌ Wave 0 |
| DOC-06 | apply_event + broadcast + peer apply produces same state | Unit | `-- -gtest=tests/unit/test_event_replication.gd` | ❌ Wave 0 |
| DOC-06 | Keepalive: 3 lost → laggy warning; 6 lost → disconnect | Unit | `-- -gtest=tests/unit/test_keepalive_logic.gd` | ❌ Wave 0 |
| DOC-06 | friendships CHECK (user_a < user_b) enforced | Unit (schema validation logic) | `-- -gtest=tests/unit/test_friends_schema.gd` | ❌ Wave 0 |
| DOC-06 | Invite token: 26-char base32, single-use, 24h TTL | Unit | `-- -gtest=tests/unit/test_invite_token.gd` | ❌ Wave 0 |
| DOC-06 | Chat rate limit: 5/10s, over-limit dropped silently | Unit | `-- -gtest=tests/unit/test_chat_rate_limit.gd` | ❌ Wave 0 |
| DOC-06 | Profanity filter replaces flagged word with [filtered] | Unit | (inline in test_chat_rate_limit.gd or separate) | ❌ Wave 0 |
| DOC-06 | Snapshot save + load round-trip (schema v3 migration) | Integration | `-- -gtest=tests/integration/` | ❌ Wave 0 |
| DOC-06 | Handover screen appears + auto-dismisses on host_failover_complete | Manual UAT | — | — |
| DOC-06 | Two real devices connect via WebRTC (direct) | Manual UAT | — | — |
| DOC-06 | Two real cellular devices connect via TURN relay | Manual UAT | — | — |
| DOC-06 | Host kill → failover < 4 s end-to-end | Manual UAT / fault injection harness | (STATE.md Phase 4 todo: network-fault-injection harness) | — |

### Sampling Rate
- Per task commit: `godot --headless -s tests/gut_main.gd -- -gtest=tests/unit/test_election_algorithm.gd -gtest=tests/unit/test_keepalive_logic.gd`
- Per wave merge: full GUT suite
- Phase gate: full suite green + human UAT rows signed off before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/conftest_phase4.gd` — shared fixtures (mock NetworkManager, fake peer IDs, deterministic RTT tables)
- [ ] `tests/unit/test_election_algorithm.gd` — covers DOC-06 election
- [ ] `tests/unit/test_event_replication.gd` — covers DOC-06 event journal RPC bridge
- [ ] `tests/unit/test_keepalive_logic.gd` — covers DOC-06 peer disconnect detection
- [ ] `tests/unit/test_friends_schema.gd` — covers DOC-06 friendship canonical ordering
- [ ] `tests/unit/test_invite_token.gd` — covers DOC-06 invite token generation + expiry
- [ ] `tests/unit/test_chat_rate_limit.gd` — covers DOC-06 chat rate limiting + profanity filter
- [ ] Schema v3 migration test (add `snapshots` table) — extend `test_schema_migration.gd`

---

## Security Domain

> `security_enforcement` not explicitly set to false in config.json → enabled.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | Supabase GoTrue JWT (HS256/RS256), refresh token rotation |
| V3 Session Management | Yes | JWT expiry, stored in `user://auth.cfg`, refresh before expiry |
| V4 Access Control | Yes | Supabase RLS policies (per-row auth); Go server verifies JWT on WebSocket upgrade |
| V5 Input Validation | Yes | JSON envelope `v` field checked; chat length ≤200 enforced; event kinds validated in `apply_event` |
| V6 Cryptography | Yes | coturn `lt-cred-mech` for TURN credentials; HTTPS for GoTrue API calls; never roll own crypto |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Fake event injection (peer sends forged events as if from host) | Tampering | RPCs from peers to host use `multiplayer.get_remote_sender_id()` for origin check; only host broadcasts events back |
| Invite token replay (reused within 24h) | Spoofing | `redeemed_by IS NULL` check in RLS + Supabase update is atomic; single-use enforced at DB level |
| Chat spam (flood the event channel) | Denial of Service | 5/10s rate limit enforced on host before broadcast; dropped silently |
| Anonymous WebSocket to signaling server | Spoofing | Go server verifies Supabase JWT on connection upgrade; rejects unauthenticated connections |
| TURN open relay abuse | Denial of Service | coturn `restricted` mode (lt-cred-mech) + `total-quota=100` + `no-loopback-peers` |
| Malicious username / chat content | Tampering/Repudiation | Profanity filter on host before broadcast; username validated at account creation (DOCS §8) |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `MultiplayerSynchronizer` for all state | Event journal + RPC broadcast | Godot 4.0+ | More explicit, works with complex state like inventories |
| GDNative WebRTC plugin | GDExtension webrtc-native (libdatachannel) | Godot 4.1+ | Stable API, all-platform binary, no source build needed for common targets |
| Open relay coturn | lt-cred-mech restricted coturn | Best practice, always | Prevents abuse of relay bandwidth |
| Firebase auth | Supabase GoTrue (self-hosted) | Project decision | Open-source, self-hostable, Postgres for friends graph |

**Deprecated/outdated:**
- `GDNative` WebRTC plugin: use GDExtension version (webrtc-native GDExtension). GDNative is Godot 3.x only.
- `WebRTCMultiplayerPeer.create_mesh()` for listen-server games: use `create_server()` / `create_client()` — mesh adds unnecessary all-to-all connections for the host-authoritative model.

---

## Open Questions (RESOLVED)

1. **TURN credential rotation** — RESOLVED
   - **Decision (locked):** Rotate TURN credentials on session start; 24-hour max TTL; credentials generated server-side by the Go signaling server when a session is published via `session.publish`. The Go server generates a time-limited HMAC credential (username = `<unix_timestamp>:<uid>`, password = HMAC-SHA1 of username using the coturn shared secret) so each session gets a fresh credential without disrupting existing sessions. This is the standard coturn REST API / time-limited credential mechanism.
   - **Implemented in:** Plan 04-02 Task 2 — Go signaling server generates credentials on `publish_session`; coturn configured with `use-auth-secret` pointing to the shared HMAC secret in `signaling.env`.

2. **Supabase friends pagination** — RESOLVED
   - **Decision (locked):** No pagination in v1. Maximum 50 friends per account. Attempting to add a 51st friend returns HTTP 400 with error code `friends_limit_reached`; the UI surfaces `tr(ui.friends.limit_reached)`. The limit is enforced by FriendsClient before the POST (count check) and documented in `supabase/README.md`. Pagination deferred to Phase 5.
   - **Implemented in:** Plan 04-04 Task 1 — `is_friends_limit_reached()` guard added to `create_friendship()`; validation returns error signal if count >= 50.

3. **Snapshot size for a 2-4 player world after 30 min** — RESOLVED
   - **Decision (locked):** Add a GUT integration test in Plan 04-10 that builds a simulated 4-player snapshot (populating dirty chunks with synthetic data representing 30 min of building) and asserts `snapshot_size_kb < 2048` (2 MB budget). If the test fails during execution, the executor must implement chunked SNAPSHOT_RESET transfer before marking Plan 04-10 complete.
   - **Implemented in:** Plan 04-10 Task 1 verify block — `test_snapshot_size_under_2mb` assertion added to `test_snapshot_migration.gd`.

4. **Profanity filter library** — RESOLVED
   - **Decision (locked):** Phase 4 ships a minimal stub: 30-word ASCII regex blocklist embedded in `src/networking/profanity_filter.gd` as `const _STUB_WORDS: Array[String]`. The filter uses word-boundary matching (`<word>`) and replaces matches with `[filtered]`. Full word-list curation is explicitly deferred to Phase 5. The class is structured so Phase 5 can inject a custom word list via `ProfanityFilter.set_word_list(list: Array[String])` without changing the filter logic.
   - **Implemented in:** Plan 04-08 Task 1 — `profanity_filter.gd` with 30-word stub list and set_word_list() extension point.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Godot 4.6 | Game engine | Inferred from project (not checked at runtime) | 4.6 stable | — |
| webrtc-native GDExtension | WebRTCMultiplayerPeer on desktop | Not verified — must be added to project before Phase 4 tasks that test WebRTC | Latest (Godot 4.4+) | ENet for all LAN/dev testing |
| GUT test framework | All unit tests | ✓ (installed Phase 1, gut_config.cfg exists) | — | — |
| Go runtime | Signaling server build | Not checked (server-side) | Go 1.22+ | — |
| Supabase Docker Compose | Auth + friends backend | Not checked (server-side) | latest | — |
| coturn | TURN relay | Not checked (server-side) | latest | STUN-only (breaks CGNAT sessions) |

**Missing dependencies with no fallback:**
- webrtc-native GDExtension: must be present in `addons/webrtc-native/` before any Plan that exercises WebRTC. Plan Wave 0 must add this. Without it, `WebRTCPeerConnection.new()` returns null on native builds.

**Missing dependencies with fallback:**
- coturn: without TURN, ~15-30% of cellular connections fail. For dev testing on the same network, ENet LAN mode works without TURN.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `NetworkManager.broadcast_event()` call is safe to insert after line 285 of `inventory.gd` without breaking headless GUT tests | Existing Pattern Reuse §1 | If `NetworkManager` is null in tests, all apply_event calls will crash; mitigation: null-check `if is_instance_valid(NetworkManager)` |
| A2 | Chunk snapshot blob stays < 2 MB after 30 min of active 2-4 player building | Snapshot / Replication | If larger, the reliable RPC transfer of the snapshot during failover will be too slow; need chunked streaming |
| A3 | The `strawberry-session-id-fallback` pattern (STATE.md 03-09) will be replaced cleanly by Phase 4's real session_id | Existing Pattern Reuse | Stale fallback code could write wrong session tokens; plan must include a grep + replace pass |
| A4 | SIWA native flow on iOS uses `/auth/v1/token?grant_type=id_token` with `{"provider":"apple","id_token":"..."}` | Supabase Schema | If the endpoint changed, SIWA sign-in is broken; verify against live Supabase instance during Wave 1 |
| A5 | `WebRTCPeerConnection.initialize()` accepts ICE server config as a Dictionary with `iceServers` array directly (not a String) | Godot Patterns §Pattern 1 | If the API expects a different format, ICE negotiation silently fails; verify against webrtc-native plugin docs |
| A6 | `server_disconnected` signal fires reliably on all platforms including iOS when the host's WebRTC data channel closes | Host Failover State Machine | If the signal is unreliable on iOS, the failover trigger must fall back to keepalive-only detection |
| A7 | Go signaling server using `nhooyr.io/websocket` (or stdlib upgrade) works correctly for 200+ concurrent connections without additional event loop tuning | Go Signaling Server | If goroutine memory usage is higher than expected, 200-session cap may be too high; profile before deployment |

---

## References

### Primary (HIGH confidence — official documentation)
- [Godot WebRTCMultiplayerPeer docs](https://docs.godotengine.org/en/stable/classes/class_webrtcmultiplayerpeer.html) — create_server, create_client, add_peer, get_peer, remove_peer APIs
- [Godot WebRTCPeerConnection docs](https://docs.godotengine.org/en/stable/classes/class_webrtcpeerconnection.html) — initialize, create_offer, set_remote_description, add_ice_candidate, signals
- [Godot High-Level Multiplayer docs](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html) — @rpc syntax, set_multiplayer_authority, server_disconnected signal, peer_connected/peer_disconnected
- [Godot HTTPRequest docs](https://docs.godotengine.org/en/stable/tutorials/networking/http_request_class.html) — JSON REST API call pattern, headers, request_completed
- [Supabase RLS docs](https://supabase.com/docs/guides/database/postgres/row-level-security) — CREATE POLICY, auth.uid(), USING, WITH CHECK
- [Supabase GoTrue self-hosted API reference](https://supabase.com/docs/reference/self-hosting-auth/introduction) — /signup, /token endpoints, response shape
- [Supabase Sign in with Apple docs](https://supabase.com/docs/guides/auth/social-login/auth-apple) — native iOS id_token flow
- [webrtc-native GDExtension README](https://github.com/godotengine/webrtc-native) — installation, platform support

### Secondary (MEDIUM confidence — verified against Godot ecosystem)
- [Godot Proposals #7912 — host migration](https://github.com/godotengine/godot-proposals/issues/7912) — confirmed no built-in host migration; custom implementation required
- [coturn TURN configuration guide](https://www.govindbuilds.com/blogs/configuring-co-turn-for-NAT-across-ISP-and-FW-2025) — turnserver.conf settings for symmetric NAT/CGNAT
- [Godot WebRTC tutorial](https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html) — signaling exchange flow

### Tertiary (LOW confidence — WebSearch only, verify at implementation)
- Libdatachannel iOS background limitation — observed in react-native-webrtc community (ios #942); applies to libdatachannel because iOS OS-level suspension is universal
- Go signaling server goroutine model capacity — ASSUMED adequate for 200 sessions based on Go concurrency model; profile before production

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all locked in CLAUDE.md + official docs verified
- Godot WebRTC API: HIGH — official Godot docs read directly
- Supabase schema + RLS: HIGH — official Supabase docs + syntax verified
- Host failover state machine: MEDIUM — design is correct per CONTEXT, but no Godot-native host migration exists; must be custom; some sequence details marked [ASSUMED]
- Go signaling server: MEDIUM — standard WebSocket relay pattern, well-understood; specific Go lib choice is at discretion
- iOS background pitfall: MEDIUM — confirmed behavior pattern but libdatachannel-specific behavior not directly tested
- Snapshot size estimates: LOW — no empirical data; marked as assumption A2

**Research date:** 2026-05-29
**Valid until:** 2026-06-29 (30 days; WebRTC/Godot ecosystem is relatively stable)
