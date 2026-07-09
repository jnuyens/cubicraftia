---
phase: 13-reliability-version-match-hardening
plan: 02
status: complete
completed: 2026-07-09
type: execute
requirements: [VER-01, VER-02]
tasks_total: 2
tasks_complete: 2
recovered: true
---

# Plan 13-02 Summary: PROTOCOL_VERSION + SessionRegistry failover-election exclusion

Delivers the VER-01 build-compatibility constant and the VER-02 host-failover-election exclusion filter. (The full VER-01 join-handshake exchange + VER-02 join-time reject are delivered by plan 13-04; this plan provides the constant and the election-side guard those build on.)

## What changed

- `src/autoload/build_info.gd`: added `BuildInfo.PROTOCOL_VERSION` (a coarse integer, bumped only on save/protocol-breaking changes), deliberately separate from the git-sha build stamp and from the Go signaling wire `"v":1`. Committed in `d81cc18`.
- `src/autoload/session_registry.gd`: per-peer protocol-version tracking plus a strict/binary compatibility check, wired into `compute_elected_host()` so a peer whose `PROTOCOL_VERSION` differs from the local build is excluded from the host-failover candidate set (D-09). A version-mismatched build can never be promoted to host mid-session. Committed in `d21609e`.
- `tests/unit/test_session_registry_version_filter.gd`: GUT tests for the compatibility check and the election exclusion. RED test committed in `b2278f8`; GREEN implementation verified 5/5 passing headless.

## Verification

- `godot --headless ... -gtest=tests/unit/test_session_registry_version_filter.gd`: **5/5 passed** (6 asserts, 0.565s).
- Strict binary equality confirmed (equal-or-exclude, no best-effort compatibility).
- No new em-dashes/en-dashes introduced (pre-existing Phase-4 header/comment dashes in session_registry.gd are out of scope).

## Recovery note

This plan's executor terminated on an infrastructure API error (server error mid-response) after completing the implementation but before its final commit + summary. Recovery was performed directly by the orchestrator: the completed, uncommitted implementation (session_registry.gd + test, which sibling plan 13-01 had correctly restored to the working tree after an accidental cross-plan staging incident) was verified GREEN (5/5) and committed as `d21609e`. The `PROTOCOL_VERSION` const and RED test were already committed by the executor before it died (`d81cc18`, `b2278f8`). No work was lost. VER-01/VER-02 requirement checkboxes are left for the phase verifier to confirm once plan 13-04 lands the handshake exchange + join-time reject.

## Deferred / downstream

- The P2P join-handshake exchange of PROTOCOL_VERSION and the host-authoritative join-time reject (with `version_mismatch` connection-problem reason) are plan 13-04.
- The bounded RPC-broadcast residual window during the reject round-trip is documented as an accepted residual in 13-04's threat model (T-13-04-02).
