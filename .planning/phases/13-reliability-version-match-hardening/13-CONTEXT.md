# Phase 13: Reliability & Version-Match Hardening - Context

**Gathered:** 2026-07-09 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Make multiplayer connection failures always explained, recoverable, and never silent, frozen, or desynced, and add a build-compatibility gate so peers on mismatched builds cannot connect-and-desync. Requirements: RELY-01..05, VER-01..02.

This is pure client-side code + a small handshake field. It does NOT deploy the backend (Phase 11), does NOT run real-device validation (Phase 12 — this phase's UX is validated against real conditions there), and does NOT add new gameplay. It builds on the already-shipped NetworkManager state machine, WebRTC P2P, host-failover, and invite/deep-link flow from v1.0.
</domain>

<decisions>
## Implementation Decisions

### Shared "connection problem" screen (RELY-01)
- **D-01:** Build ONE reusable connection-problem overlay/screen driven by a single reason enum, NOT N ad-hoc dialogs (per FEATURES.md — vague "connection failed" is the top support driver across Discord/Minecraft/Xbox GDK). Reason enum: `expired`, `full`, `ended`, `blocked`, `version_mismatch`, `relay_failed`, `timeout`. Each reason maps to a specific, actionable player-facing message + a primary action (e.g. Retry / Back to menu / Update).
- **D-02:** Drive it from NetworkManager's existing signals (`host_failover_failed(reason)`, `join_blocked(reason)`, plus new reason emissions). Reuse the existing string-constant state pattern in `network_manager.gd` — extend it with a `last_failure_reason` and a `connection_problem(reason)` signal rather than inventing a parallel system. The overlay lives alongside `network_hud.gd` / `join_screen.gd`.

### Auto-reconnect grace window (RELY-02)
- **D-03:** A brief network blip triggers a SILENT auto-reconnect within a grace window (use the existing `STATE_RECONNECTING`). Only if reconnection fails within the window (~5s, tunable const) does the connection-problem screen appear with reason `timeout`/`ended`. No flicker for sub-second blips.

### Connecting state (RELY-03)
- **D-04:** The "Connecting..." state is non-frozen (animated indicator) with a sane bounded timeout (10-15s const). On timeout it resolves to the connection-problem screen with reason `timeout` — never an indefinite hang.

### Stale/invalid invite links (RELY-04)
- **D-05:** Invalid/expired invite (deep-link `cubicraftia://` token or a session that no longer exists) resolves to the shared screen with reason `expired` (or `ended`/`full` as appropriate) and a clear action, not a silent no-op or hang. Wire through the existing DeepLinkHandler / join flow.

### Relay-vs-direct badge (RELY-05)
- **D-06:** `network_hud.gd` shows an honest connection-quality badge: direct P2P vs TURN-relay. Derive from the WebRTC ICE selected-candidate-pair type (relay = TURN in use). Badge is informational; its correctness under real relay conditions is validated in Phase 12.

### Build-compatibility gate (VER-01, VER-02)
- **D-07:** Add a COARSE `PROTOCOL_VERSION` integer constant (game-build compatibility), SEPARATE from `BuildInfo` git-sha (too fine-grained) and SEPARATE from the Go signaling wire `"v":1` (that is signaling-protocol, not gameplay-build compat). Bump it only on save/protocol-breaking changes, not every commit.
- **D-08:** Exchange `PROTOCOL_VERSION` in the P2P session-join handshake (peer-to-peer, host-authoritative). A joining peer whose version != host's is CLEANLY REJECTED with reason `version_mismatch` on the shared screen — never connect-and-silently-desync (FEATURES/PITFALLS: silent desync is worse than a clean rejection).
- **D-09:** A version-mismatched peer is ALSO excluded as a host-failover candidate — the failover election (SessionRegistry) must skip peers whose `PROTOCOL_VERSION` differs, so a mismatched build can never be promoted to host mid-session.

### Localisation
- **D-10:** All new player-facing strings (7 reason messages + badge labels + reconnect/connecting states) get `locale/en.po` + `locale/nl.po` keys, following existing i18n + walk-up-prompt conventions. NL strings mirror the native-reviewed style from Phase 9.

### Claude's Discretion
- Exact grace-window / connecting-timeout constants (within the stated ranges).
- Overlay visual layout (defer to the UI-SPEC produced by the UI design contract step).
- Whether `PROTOCOL_VERSION` lives in `BuildInfo` or its own small autoload/const.
</decisions>

<specifics>
## Specific Ideas

- Reuse, don't reinvent: the 10-state NetworkManager machine, `STATE_RECONNECTING`, and the `reason`-bearing signals already exist. This phase extends them, adds the shared overlay, and adds the version handshake + failover-candidate filter.
- The version check must be STRICT/binary (equal or reject), never "best-effort compatible" — per PITFALLS pitfall #17.
- Save/protocol migration chains (pitfall #18) are noted but the migration system itself is out of scope; this phase only adds the compatibility GATE, not migrations.
</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The design
- `.planning/research/FEATURES.md` — connection-failure reason-enum taxonomy (the shared "connection problem" screen), relay badge / nameplates / freeze UI, silent-reconnect grace window.
- `.planning/research/ARCHITECTURE.md` — `protocol_version` field placement, client endpoint-config, version-match gate in the join handshake; verified against `network_manager.gd` / `friends_client.gd`.
- `.planning/research/SUMMARY.md` § Feature Landscape + § Watch Out For (pitfalls #17 version-mismatch desync, #18 migration chains).
- `.planning/REQUIREMENTS.md` — RELY-01..05, VER-01..02.

### The code this phase extends
- `src/autoload/network_manager.gd` — 10-state machine, `host_failover_failed(reason)`, `join_blocked(reason)`, `freeze_build_changed`, `STATE_RECONNECTING`.
- `src/ui/network_hud.gd` — HUD surface for the relay badge.
- `src/ui/join_screen.gd` — join flow / where the connection-problem screen surfaces.
- `src/autoload/build_info.gd` — build stamp (git-sha); `PROTOCOL_VERSION` is a NEW, coarser sibling.
- `signaling-server/internal/hub/hub.go` — existing signaling wire `"v":1` + `version_mismatch` error (do NOT confuse with the new gameplay-build `PROTOCOL_VERSION`; the two are distinct layers).
- SessionRegistry / failover election code (for D-09 candidate filtering) — locate during planning.
- `locale/en.po`, `locale/nl.po` — i18n keys.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- NetworkManager string-constant state machine + `reason`-bearing signals (`host_failover_failed`, `join_blocked`) — extend rather than replace.
- `STATE_RECONNECTING` already exists — the grace-window reconnect hooks into it.
- `network_hud.gd` / `join_screen.gd` — existing UI surfaces for badge + problem screen.
- BuildInfo autoload pattern — model `PROTOCOL_VERSION` similarly if it warrants its own const.

### Established Patterns
- Player-facing strings go through `locale/*.po` (en + nl); walk-up-prompt phrasing conventions in CLAUDE.md.
- Signals-driven UI (HUD/overlays subscribe to NetworkManager signals) — the connection-problem overlay follows this.

### Integration Points
- New `connection_problem(reason)` signal + `last_failure_reason` on NetworkManager.
- New `PROTOCOL_VERSION` const exchanged in the P2P join handshake; reject path + failover-candidate filter in SessionRegistry.
- New overlay scene/script; relay badge in network_hud; en/nl locale keys.
</code_context>

<deferred>
## Deferred Ideas

- Desktop "update available" prompt + version manifest — that is DIST-05 (Phase 15); this phase only adds the peer-to-peer version-match GATE, not the update-check.
- Save/protocol MIGRATION system — out of scope; this phase adds the compatibility gate only.
- Real-device validation of the badge/nameplates/freeze UI under live relay/failover — Phase 12.
</deferred>

---

*Phase: 13-reliability-version-match-hardening*
*Context gathered: 2026-07-09*
