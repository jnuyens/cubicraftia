# Architecture Research: v1.2 Multiplayer & Distribution

**Domain:** Live backend deployment (single Linux host) + cross-platform signed-release/distribution pipeline for an existing Godot 4.6 P2P multiplayer game.
**Researched:** 2026-07-08
**Scope:** This is a SUBSEQUENT-milestone research pass. The networking model, signaling protocol, TURN-credential scheme, and persistence format are already built and locked (see STATE.md, v1.0/v1.1 `.planning/research/ARCHITECTURE.md`). This document covers ONLY what changes to go from "code exists, runs on localhost" to "live on m1.linuxbe.com / cubicraftia.com, downloadable, auto-updating." It supersedes the prior ARCHITECTURE.md for the purposes of this milestone's roadmap.

---

## Overview

v1.2 has two independent but sequenced halves:

1. **Backend go-live.** Three services (Go signaling binary, coturn, self-hosted Supabase) must coexist on one Debian/Ubuntu host that already has root + DNS control (`cubicraftia.com`, host `m1.linuxbe.com`, per PROJECT.md operator prerequisites). None of this requires new game code — `network_manager.gd` and `friends_client.gd` already read `ProjectSettings` → OS env → localhost fallback for every backend URL (`network/signaling_url`, `network/supabase_url`, `network/stun_url`, `network/turn_url`, `network/supabase_anon_key`). **The client-side config-injection point is already built.** The v1.2 work here is almost entirely ops/deploy, not GDScript.

2. **Distribution go-live.** The CI export matrix already produces unsigned build artifacts on tag pushes (`.github/workflows/ci.yml`). v1.2 adds code-signing, release channels (itch.io, GitHub Releases, mobile stores), a version-match gate so mismatched peers don't silently desync, and a lightweight update-check for desktop (itch app auto-updates natively; GitHub Releases/own-site downloads do not, and need an explicit "update available" check).

The one integration point that ties both halves together: the **build-stamp mechanism that already exists** (`addons/build_stamp`, `res://version.txt`, `BuildInfo.version_string()`) is the natural substrate for the version-match gate — it needs a second, coarser field (a semantic/protocol version) alongside the existing git-sha stamp, because git-sha is unique-per-commit and would over-reject peers on the same released version built at slightly different CI times.

---

## Single-Host Backend Topology

### Services and where they run

| Service | Runtime | Binds to | Public exposure |
|---|---|---|---|
| Caddy (reverse proxy + TLS) | systemd (native package, not Docker) | `0.0.0.0:80`, `0.0.0.0:443` | Yes — the only HTTP(S)/WSS entry point |
| Go signaling server | systemd (`signaling.service` — already committed at `signaling-server/deploy/signaling.service`) | `127.0.0.1:8080` (loopback only) | No — proxied by Caddy over `wss://` |
| Supabase stack (Kong, GoTrue, PostgREST, Postgres, Realtime, Storage, Meta) | `docker compose` (official self-host manifest) | Kong gateway on `127.0.0.1:8000` | No — proxied by Caddy |
| coturn (STUN/TURN) | systemd (native `coturn` Debian/Ubuntu package — NOT Docker; Docker NAT-remapping of a huge UDP port range is a well-known coturn pain point) | `0.0.0.0:3478` (STUN/TURN), `0.0.0.0:5349` (TURNS/TLS), `0.0.0.0:49152-65535/udp` (relay range) | Yes — directly, bypassing Caddy entirely |

**Why Caddy over nginx/Traefik (MEDIUM-HIGH confidence):** Caddy issues and renews Let's Encrypt certificates automatically with a ~5-line Caddyfile, no certbot cron job, no manual renewal hooks for the HTTP-proxied services. For a project maintained by one operator, this materially lowers ongoing ops burden versus nginx+certbot or Traefik's label-based Docker-native config (which adds complexity when half the stack — Go binary, coturn — is deliberately NOT in Docker). This matches the project's existing bias toward simple systemd units over container orchestration for anything that isn't already shipped as a docker-compose stack (Supabase is the one exception, because that's how upstream ships it).

**Why coturn is NOT proxied by Caddy:** TURN/STUN is not an HTTP protocol — clients speak raw UDP/TCP STUN binding requests and TURN allocate/refresh messages directly to port 3478/5349, and the *relayed* media itself flows over an ephemeral UDP port in the 49152-65535 range chosen per-allocation. A reverse proxy cannot sit in this path. coturn must bind directly to public IPs. **coturn does need its own TLS certificate for TURNS (port 5349)** — reuse the Let's Encrypt certificate Caddy already obtains for `cubicraftia.com` by pointing coturn's `cert=`/`pkey=` config at Caddy's certificate storage (`/var/lib/caddy/.local/share/caddy/certificates/...`), with a `systemctl reload coturn` triggered from Caddy's on-renewal exec hook (Caddy 2.x supports `on_cert_renewal` handlers in the Caddyfile) — otherwise coturn silently keeps serving an expired cert until manually restarted, a known operational trap. Validate the exact hook syntax against current Caddy docs at implementation time (MEDIUM confidence — this is a documented community pattern, not an official joint Caddy+coturn integration guide).

### Reverse proxy routing plan

```
cubicraftia.com, www.cubicraftia.com   -> static landing/download page (Caddy file_server)
signal.cubicraftia.com                 -> reverse_proxy 127.0.0.1:8080   (wss:// upgrade; /ws /health /consent/* /admin/reports)
api.cubicraftia.com  (or /supabase/*)  -> reverse_proxy 127.0.0.1:8000   (Supabase Kong gateway)
```

A subdomain-per-service layout (`signal.`, `api.`) is simpler to reason about and cert-manage than path-based routing under one domain, and matches Supabase's own self-host reverse-proxy guidance (Kong expects to own routing under its own host). Caddy auto-issues a cert per subdomain from the same Caddyfile block — no extra config for multi-domain TLS.

### Ports / firewall summary

| Port | Protocol | Service | Exposure |
|---|---|---|---|
| 80, 443 | TCP | Caddy | Public |
| 3478 | UDP+TCP | coturn STUN/TURN | Public |
| 5349 | UDP+TCP (DTLS/TLS) | coturn TURNS | Public |
| 49152-65535 | UDP | coturn relay allocations | Public (widest attack-surface item — see Gaps) |
| 8080 | TCP | Go signaling | Loopback only (never expose directly) |
| 8000 | TCP | Supabase Kong | Loopback only (never expose directly) |
| 5432 | TCP | Postgres | Loopback only, never public |

This matches the values already hardcoded as client defaults (`stun:cubicraftia.com:3478`, `turn:cubicraftia.com:3478` in `network_manager.gd`) — no client change needed for the STUN/TURN endpoint itself, only for the operator-side coturn config to actually listen there with the matching shared secret.

### Secrets management

Single-host, single-operator scale does not justify Vault/SOPS. Concrete plan:

- `/etc/cubicraftia/signaling.env` (root:cubicraftia-svc, mode 0600) — `SUPABASE_JWT_SECRET`, `SUPABASE_SERVICE_KEY`, `ADMIN_SECRET`, `TURN_SHARED_SECRET`, SMTP creds. Already referenced by the committed `signaling.service` unit's `EnvironmentFile=`.
- `/etc/coturn/turnserver.conf` — `static-auth-secret=` **must equal** the Go server's `TURN_SHARED_SECRET` (session.go's `GenerateTURNCredentials` HMAC-SHA1s a `timestamp:sessionID` username against this same secret — coturn validates client-presented credentials against the identical secret via `use-auth-secret`). This is the single most important secret-parity requirement in the whole deploy: if the two values drift, every TURN relay allocation is silently rejected and only symmetric-NAT peers (a meaningful fraction of real-world sessions) will fail to connect, with no obvious error surfaced client-side beyond "peer unreachable."
- `supabase/.env` (docker-compose) — `POSTGRES_PASSWORD`, `JWT_SECRET` (same value as `SUPABASE_JWT_SECRET` above — GoTrue and the Go server must trust the same signing secret), `ANON_KEY`, `SERVICE_ROLE_KEY`, `SITE_URL`.
- None of these are committed to git; `.gitignore` already excludes `release.keystore*` — extend the same discipline to `*.env` at the repo root (already conventional) and add an ops-only runbook (not a repo secret) documenting where each file lives on the host and how to rotate it.
- GitHub Actions secrets remain scoped to CI-time needs only (LFS password, Android keystore, notarization credentials) — they are not used to push runtime secrets to the host; that stays a manual/SSH operator step for a single host at this scale.

### Backups

- **Postgres only** is the durable server-side state that needs backup — friends graph, invites, blocks, reports, parental consents, profiles (`supabase/migrations/001..009`). Nightly `pg_dump`/`pg_dumpall` (cron) to a compressed file, retained ~14-30 days, copied off-host (rsync to a second disk/location, or an S3-compatible bucket) so a host failure doesn't also destroy the only backup copy.
- **World data is explicitly NOT backend state** — per the existing architecture, worlds are SQLite files that live with whichever peer is hosting, transferred peer-to-peer during host migration. The backend never stores game-world data. This materially simplifies backend backup scope versus a naive "back up everything" instinct.
- **coturn and the Go signaling server are stateless** (in-memory session registry, no persistent store) — nothing to back up beyond their config files, which should be captured in the ops runbook / a private ops-config repo, not the game's public GPL repo.

### Observability (right-sized for a single host, 200-session soft cap)

Prometheus/Grafana is disproportionate for this scale. Minimum viable:
- Caddy access logs -> file with `logrotate` (JSON log format so subdomain/latency/status are greppable later if needed).
- `journalctl -u signaling -u coturn` for the two systemd-managed services; `docker compose logs` for Supabase.
- An external uptime check (e.g., a free-tier HTTP+WSS monitor) against `https://signal.cubicraftia.com/health` (the endpoint already exists in `signaling-server/cmd/signaling/main.go`) and `https://api.cubicraftia.com/` — this is the cheapest possible "is the backend actually up" signal and should exist before real-device MP testing begins, since intermittent host issues are otherwise indistinguishable from client-side WebRTC bugs during testing.
- Defer real metrics/dashboards to a later milestone unless session volume materially grows; flag this explicitly so the roadmap doesn't over-invest here.

---

## Client <-> Backend Integration

### Endpoint configurability (already built — confirm, don't redesign)

Both `network_manager.gd` and `friends_client.gd` resolve every backend URL through the same three-tier precedence, already in the codebase:

```
ProjectSettings.get_setting("network/<key>")   # highest priority — override.cfg / export preset
  -> OS.get_environment("<ENV_VAR>")            # CI / dev-shell override
  -> hardcoded localhost / cubicraftia.com default
```

Concretely: `network/signaling_url`, `network/supabase_url`, `network/supabase_anon_key`, `network/stun_url`, `network/turn_url`, `network/turn_user`, `network/turn_credential`. The STUN/TURN defaults are **already** `cubicraftia.com`, not `localhost` — a deliberate prior decision that means production TURN/STUN needs zero client-side config change once coturn is actually listening at that hostname with matching secrets. Signaling and Supabase URLs still default to `localhost` and need an `override.cfg` (or export-time `ProjectSettings` override) pointing release builds at `wss://signal.cubicraftia.com/ws` and `https://api.cubicraftia.com`.

**New work for v1.2 is packaging this correctly per channel, not writing new config code:**
- Release export presets need a `[network]` section baked in (or an `override.cfg` shipped alongside the exported binary) pointing at production URLs, while local dev/editor runs keep hitting `localhost`.
- CI's tag-triggered export job is the natural place to inject production `ProjectSettings` overrides — a small addition to the existing `export` job in `ci.yml`, not a new subsystem.

### JWT + TURN credential flow (already designed, needs live verification)

1. Player authenticates via GoTrue (`friends_client.gd` -> `https://api.cubicraftia.com/auth/v1/...`), receives a Supabase JWT (HS256, signed with `SUPABASE_JWT_SECRET`).
2. Client opens `wss://signal.cubicraftia.com/ws`, presents the JWT; Go server's `auth.go` verifies the HMAC-SHA256 signature and expiry using the **same** `SUPABASE_JWT_SECRET` — this is the second secret-parity dependency (alongside the TURN shared secret) that only manifests as a bug once both services are live on separate deploy artifacts.
3. On session creation, the Go server calls `GenerateTURNCredentials(sessionID, TURN_SHARED_SECRET, ttl)` (already implemented in `session.go`, HMAC-SHA1 per coturn's `use-auth-secret` REST-API convention — deliberately SHA1, not SHA256, because that's what coturn's protocol requires) and relays the resulting short-lived `{username, credential}` pair to the client alongside session metadata.
4. Client feeds these into its `WebRTCPeerConnection` ICE server list alongside the static STUN URL.

**Nothing here needs new design** — the credential *scheme* is locked. What v1.2 adds is making all three secrets (`SUPABASE_JWT_SECRET`, `TURN_SHARED_SECRET`, coturn's `static-auth-secret`) consistent across three independently-deployed artifacts (Go binary env file, Supabase docker-compose env file, coturn conf file) on the same host — a deploy-correctness problem, not an architecture problem.

### NAT traversal path (unchanged design, first live validation)

STUN-first, TURN-fallback is already the design (`_stun_url` tried before `_turn_url` in the WebRTC ICE gathering). v1.0's dev-local NAT-traversal probe validated >=50% direct-P2P success rate on real cellular (STATE.md Performance Metrics) — but that was necessarily against a placeholder/dev STUN target, not the production coturn instance. **The single biggest unknown this milestone resolves is not "does the NAT-traversal design work" (already proven) but "does the live coturn deployment on `m1.linuxbe.com` actually relay correctly for symmetric-NAT peers"** — this is squarely why a live-backend deploy must precede any further multi-device WebRTC validation (see Build Order).

---

## Release & Distribution Pipeline

### Version scheme

The existing `build_stamp` plugin stamps `res://version.txt` with `<short-sha>[+] <date>` on every export/play (`addons/build_stamp/version_export_plugin.gd`) — this is a **build identifier**, not a semantic version, and is intentionally unique per commit (useful for support/debugging: "which exact build is this bug in"). For a version-match gate this granularity is wrong on its own: release builds cut from the identical tag do produce an identical stamp (good), but the gap is that **there is currently no separate, coarser "protocol/release version" that the multiplayer handshake can compare** — relying on the raw git-sha string for that comparison conflates "different commit" with "actually incompatible," which will over-reject in benign cases (e.g., a docs-only or asset-only follow-up commit that doesn't touch the network protocol).

**Recommendation:** Add a second field, e.g. `PROTOCOL_VERSION` (a small monotonic integer, bumped only when the RPC/serialization contract in `network_manager.gd` actually changes — not on every commit) alongside the existing build-stamp string. Store it as a `const` in an autoload (or a new small `res://protocol_version.txt` written by the same export plugin) and exchange it during the signaling handshake (`session_metadata_received` already carries session metadata — extend the envelope with `protocol_version`). This is additive to the existing build-stamp mechanism, not a replacement. (MEDIUM confidence — this is this document's own synthesis, not something already built; flag for roadmap scrutiny.)

### Signed artifacts per platform

| Platform | Signing requirement | Where it plugs into existing CI |
|---|---|---|
| macOS | Apple Developer ID cert + notarization (`notarytool`) — required or Gatekeeper blocks the app on first launch | New step in the existing `export` job's macOS leg, after the current unsigned `.app` is produced |
| Windows | Code-signing certificate (EV or standard) via `signtool` — not strictly required to run, but removes SmartScreen warnings that will otherwise scare away a large fraction of first-time downloaders | New step after the existing Windows export leg |
| Linux | No OS-level signing requirement; optionally GPG-sign release tarballs for supply-chain integrity | Optional, low priority |
| Android | Already wired — `SECRET_RELEASE_KEYSTORE_BASE64` / `_PASSWORD` / `_USER` GitHub Secrets are documented and consumed in `docs/CI_KEYSTORE_SETUP.md` and the existing `export` job | No new work — this is v1.2's one "already solved" platform |
| iOS | Apple Developer Program enrollment + distribution certificate + provisioning profile — the `export_ios` job already exists in `ci.yml` but is gated behind `startsWith(github.ref, 'refs/tags/v')` / `workflow_dispatch` and depends on credentials not yet present | Populate the existing gated job with real signing secrets once Apple Developer enrollment (an operator/legal prerequisite, already tracked in PROJECT.md) completes |

**Google Play target API level (HIGH confidence, time-sensitive):** as of 2026, new apps/updates must target Android 15 (API 35); **August 31, 2026 is the deadline for Android 16 (API 36)** to remain submittable, per multiple corroborating sources. Given the project's current date (2026-07-08) and this milestone's timeline, the Android export template / Godot Android build config should target API 36 from the start of this milestone's Android work to avoid a second submission-blocked rework a few weeks later. (MEDIUM confidence on the exact date — re-check the official Android Developers page at implementation time since policy dates have moved before.)

### Channels

| Channel | Mechanism | Auto-update behavior |
|---|---|---|
| itch.io | `butler push` (a well-worn CI action exists: "Butler to Itch") per platform/channel (`windows`, `osx`, `linux`) | **Only** the itch **app** (not browser downloads) auto-updates, and only via butler's binary-diff channel mechanism. A player who downloads the zip from the itch.io web page gets no auto-update at all. |
| GitHub Releases | Attach signed platform artifacts to the same tag the CI export job already builds from | No auto-update mechanism exists — GitHub Releases is a passive download host. Needs the custom update-check below. |
| Own site (`cubicraftia.com`) | Static download page pointing at either the GitHub Release assets or a self-hosted mirror | Same — no built-in auto-update. |
| Apple App Store / Google Play | Standard store submission | Both platforms auto-update natively via the OS store client — no custom code needed, this is the *simplest* auto-update path of the four. |

**Auto-update / version-match gate — concrete design implication:** Because 2 of 4 desktop channels (GitHub Releases, own-site) have zero built-in auto-update, "auto-update keeping every peer on the same build" cannot be achieved passively for those channels. The pragmatic architecture is a **lightweight update-check, not a self-replacing binary updater** (Godot has no built-in updater and building one is a disproportionate amount of new engineering for a 2-4-friends game): on launch, `HTTPRequest` a small JSON manifest (`https://cubicraftia.com/version.json` — hosted statically, updated by the same CI job that cuts a release) containing `{"latest_protocol_version": N, "latest_build": "...", "download_url": "..."}`; compare against the local `protocol_version.txt`; if behind, show a non-blocking "a new version is available" banner with a direct download link (title screen, not mid-session). The itch app and both stores independently keep those channels current regardless.

**Version-match gate at the session layer:** extend the existing signaling handshake so the Go server (or the host peer, since the server is stateless/game-agnostic) rejects or warns when `protocol_version` mismatches between joining peers — this is a small, additive change to the already-existing `session_metadata_received` / join-handshake path in `network_manager.gd`, not new architecture.

---

## Real-Device Validation Harness

The 6 deferred multi-device WebRTC tests (host-failover SLA, relay badge, nameplates, freeze UI, NAT traversal — tracked in STATE.md Deferred Items, Phase 4) were validated headlessly/locally but explicitly deferred pending a live backend. Structuring the harness:

- **Fixed device roster.** At minimum 2 physically distinct devices on 2 different real networks (e.g., one on home broadband, one on cellular/hotspot) to actually exercise NAT diversity — testing 2 devices on the same LAN/router will not surface symmetric-NAT TURN-relay bugs, which is the whole point of this pass.
- **Repeatable scenario scripts**, not ad hoc play sessions: a short written checklist per deferred test (mirroring the existing `*-VERIFICATION.md` / `*-HUMAN-UAT.md` pattern already used throughout the project for hardware-gated items) so the same steps can be re-run after any backend config change.
- **Backend-state visibility during tests:** tail `journalctl -u signaling -u coturn` on the host during each test run — the `/admin/reports` and `/health` endpoints plus raw logs are the only current operator-facing visibility, and reading them live while a real device test happens is how a relay failure gets distinguished from a client bug.
- **Explicit "which network path was used" instrumentation:** the client already has a relay/direct badge concept (per the deferred "relay badge" test) — confirm it surfaces which ICE candidate type won (host/srflx/relay) so a failed test run's root cause (STUN succeeded vs. had to fall back to TURN vs. both failed) is diagnosable without packet capture.
- **Version-match validation folds into this same harness** once the protocol-version field exists: deliberately run one device on an older tagged build against a newer one to confirm the mismatch gate behaves (reject or warn) instead of silently corrupting shared state.

---

## Suggested Build Order

Dependency-ordered; each phase's exit criterion is what the next phase needs as a precondition.

1. **Deploy backend infra (Caddy + coturn + Supabase docker-compose + Go signaling systemd unit) on m1.linuxbe.com.** No game-code changes. Exit: all three services reachable over TLS/WSS from an external machine, `/health` green, TURN allocation succeeds against coturn from an external STUN/TURN test client (e.g. `turnutils_uclient` or a simple WebRTC trickle-ice test page) — validate the backend in isolation *before* wiring the game client to it, so backend bugs and client bugs don't get conflated.
2. **Point a release export at production endpoints and smoke-test end-to-end from the actual Godot client** (sign-up, friend invite, session join, direct P2P + forced-TURN connect) on a single machine pair first. Exit: one real session, one real TURN-relayed connection, both working against the live host.
3. **Real-device multi-network validation harness** (the 6 deferred WebRTC tests) against the now-live backend. This is the first point where host-failover SLA, relay badge, nameplates, freeze UI, and NAT traversal can be honestly verified rather than headlessly approximated. Exit: all 6 deferred tests pass on real hardware/networks.
4. **Reliability hardening** (reconnect flows, connection-failure UX, session recovery, invite-link robustness) — informed directly by whatever the Phase 3 real-device pass surfaces; doing this before live validation risks hardening against imagined failure modes instead of observed ones.
5. **Protocol-version field + version-match gate**, added to the signaling handshake now that the harness from Phase 3 exists to validate it (deliberately mismatched builds joining the same session).
6. **Code-signing pipeline** (macOS notarization, Windows signtool, Android — already done, iOS once Apple enrollment lands) wired into the existing CI export job. This can start in parallel with Phases 3-5 once operator/legal prerequisites (Apple Developer, EV cert if used) are in hand, since it doesn't depend on backend state.
7. **Release channels** (itch.io via butler, GitHub Releases attach-to-tag, own-site download page with platform auto-detection) — needs Phase 6's signed artifacts as input.
8. **Desktop update-check manifest** (`version.json` + in-game banner) — needs Phase 5's protocol-version field and Phase 7's published channel URLs to point at.
9. **Mobile store submission** (Apple App Store + Google Play metadata, screenshots, IAP wiring, privacy/COPPA review gates already tracked as operator/legal prerequisites) — last, because store review is the longest and least controllable lead time, and should only start once the build being submitted is the actually-final signed, version-matched, backend-validated one.

**Rationale for this order:** deploy before validate before harden before sign before submit. Every step after Phase 1 depends on a live backend existing; every step after Phase 6 depends on signed artifacts existing; store submission is deliberately last because it is the only step with an external, non-negotiable review-time dependency (Apple/Google) that should not gate earlier engineering work.

---

## Confidence Assessment

| Area | Confidence | Reasoning |
|---|---|---|
| Client endpoint-configuration strategy | HIGH | Verified directly in `network_manager.gd` / `friends_client.gd` — the three-tier `ProjectSettings -> env -> default` pattern already exists and needs no redesign |
| Single-host topology (Caddy + coturn + Supabase coexistence) | HIGH | Confirmed via official Supabase self-host reverse-proxy docs + coturn's documented port requirements; this is a well-trodden deployment pattern, not novel |
| JWT/TURN credential flow | HIGH | Verified directly in `signaling-server/internal/hub/{auth,session}.go` — HMAC-SHA1 TURN credential generation and HMAC-SHA256 JWT verification are already implemented; only the shared-secret parity across three artifacts is new operational risk |
| Version-match / protocol-version gate | MEDIUM | The existing build-stamp mechanism is git-sha-granular (verified in `build_stamp` addon); the recommendation to add a coarser protocol-version field is this document's own synthesis, not something already built — flag for roadmap scrutiny |
| itch.io / GitHub Releases auto-update behavior | MEDIUM-HIGH | Confirmed via itch.io's own documentation that auto-update is itch-app-only; GitHub Releases having no auto-update is definitionally true (it is a static asset host) |
| Google Play API-level deadline specifics | MEDIUM | WebSearch-sourced (multiple secondary sources agreeing: API 35 baseline now, API 36 deadline August 31 2026); recommend an official Android Developers page re-check at Phase 6 implementation time since policy dates have moved before |
| coturn/Caddy cert-sharing mechanism | MEDIUM | The general approach (coturn reusing a Caddy-issued cert + reload-on-renew hook) is a documented community pattern, not an official joint Caddy+coturn integration guide — validate the exact `on_cert_renewal` Caddyfile syntax against current Caddy docs at implementation time |

## Gaps to Address

- Exact Supabase self-host docker-compose service list to actually run (full stack vs. GoTrue+PostgREST+Postgres only) needs a resource-budget decision against the actual VPS spec (not inspected in this pass — confirm `m1.linuxbe.com` capacity with the operator).
- Whether Windows code-signing uses a purchased EV certificate (removes SmartScreen friction immediately) or a standard cert (still accumulates reputation over time) is a cost/timeline tradeoff for the operator, not a research gap resolvable here.
- The exact wire format for the new `protocol_version` handshake field (where in the existing JSON envelope it lives, whether the Go server enforces it or only relays it for host-side enforcement) is an implementation detail for phase-planning, not architecture.
- Real VPS network capacity (uplink bandwidth for TURN-relayed sessions, since relayed media is proxied through the host) was not verified — flag for a dedicated capacity check before assuming coturn can comfortably relay multiple concurrent 4-peer sessions.

## Sources

- [Self-Hosting Supabase with Docker and Caddy as a Reverse Proxy](https://flori.dev/reads/supabase-self-host-docker-caddy-reverse-proxy/)
- [Supabase Docs — Self-Hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker)
- [Supabase Docs — Configure Reverse Proxy and HTTPS](https://supabase.com/docs/guides/self-hosting/self-hosted-proxy-https)
- [coturn/coturn — examples/etc/turnserver.conf](https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf)
- [coturn wiki — turnserver](https://github.com/coturn/coturn/wiki/turnserver)
- [WebRTC TURN Server Setup: Complete Production Guide](https://celloip.com/blog/webrtc-turn-server-production-guide/)
- [itch.io — Pushing builds with butler is now in the itch app](https://itch.io/updates/pushing-builds-with-butler-is-now-in-the-itch-app)
- [itch.io — The butler manual: Pushing builds](https://itch.io/docs/butler/pushing.html)
- [itch.io app book — How updates work](https://itch.io/docs/itch/integrating/updates.html)
- [Meet Google Play's target API level requirement](https://developer.android.com/google/play/requirements/target-sdk)
- [Google Play API 36 Deadline: Aug 31, 2026](https://vadimages.com/news/google-play-api-36-deadline-august-2026-logistics-apps)
- [Godot Forums — check new version](https://godotforums.org/d/26261-check-new-version)
- [Godot proposal #10348 — Check for Godot/project version on multiplayer connect](https://github.com/godotengine/godot-proposals/issues/10348)
- Repo-internal (verified directly, not web sources): `src/autoload/network_manager.gd`, `src/autoload/friends_client.gd`, `src/autoload/build_info.gd`, `addons/build_stamp/*.gd`, `signaling-server/internal/hub/{auth,session,relay}.go`, `signaling-server/internal/config/config.go`, `signaling-server/deploy/signaling.service`, `signaling-server/cmd/signaling/main.go`, `.github/workflows/ci.yml`, `docs/CI.md`, `docs/CI_KEYSTORE_SETUP.md`, `supabase/migrations/*.sql`
