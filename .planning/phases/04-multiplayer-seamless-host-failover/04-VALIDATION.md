---
phase: 4
slug: multiplayer-seamless-host-failover
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-29
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | GUT (Godot Unit Test) for GDScript + `go test ./...` for the signaling server + `pgtap` or `psql` SQL fixtures for Supabase RLS |
| **Config file** | `tests/gut_config.cfg` (existing from Phase 1) + new `signaling-server/go.mod` + new `supabase/migrations/` |
| **Quick run command** | `godot --headless --quit-after 120 -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg` |
| **Full suite command** | quick + `cd signaling-server && go test ./...` + `supabase test db` |
| **Estimated runtime** | ~30 s GUT quick · ~10 s Go tests · ~15 s Supabase tests = ~60 s full |

---

## Sampling Rate

- **After every task commit:** Run the relevant subset (GUT for GDScript tasks, `go test` for signaling tasks, `supabase test db` for SQL tasks)
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite green AND host-failover integration test green
- **Max feedback latency:** 60 s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-T1 | 04-01 | 1 | DOC-06 | T-04-01-SC | webrtc-native addon downloaded from official github.com/godotengine/webrtc-native only | unit (stub) | `godot --headless --quit-after 60 -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg -- -gtest=tests/unit/test_election_algorithm.gd -gtest=tests/unit/test_keepalive_logic.gd 2>&1 \| grep -E "(Pending\|Risky\|FAILED\|ERROR)" \| head -10` | ❌ W0 | ⬜ pending |
| 04-01-T2 | 04-01 | 1 | DOC-06 | T-04-01-I18N | locale keys are developer-facing strings; no secrets in en.po | unit (file check) | `ls addons/webrtc-native/*.gdextension && grep -c 'msgid "ui\.signin\.' locale/en.po && grep 'msgid "ui.settings.show_nameplates"' locale/en.po` | ❌ W0 | ⬜ pending |
| 04-02-T1 | 04-02 | 1 | DOC-06 | T-04-02-T | RLS UPDATE policy USING (redeemed_by IS NULL) enforces single-use invite at DB level | unit (grep) | `grep -c "CHECK (user_a < user_b)" supabase/migrations/001_friendships.sql && grep -c "redeemed_by IS NULL" supabase/migrations/002_invites.sql && grep -c "username TEXT NOT NULL UNIQUE" supabase/migrations/003_profiles.sql` | ❌ W0 | ⬜ pending |
| 04-02-T2 | 04-02 | 1 | DOC-06 | T-04-02-S | VerifyJWT() called on every WebSocket upgrade; uid from verified sub claim; TestJWTRejectionOnConnect asserts 401 | unit (go test) | `cd /Users/jnuyens/src/LegoMinecraft/signaling-server && go build ./cmd/signaling 2>&1 && go test ./... 2>&1 \| grep -E "^(ok\|FAIL\|---)"` | ❌ W0 | ⬜ pending |
| 04-03-T1 | 04-03 | 1 | DOC-06 | — | Schema v3 migration inside BEGIN/COMMIT transaction; no string-concatenation SQL | unit (grep) | `grep -c "_migrate_2_to_3" src/autoload/world_save.gd && grep "SessionRegistry" project.godot && grep "StyleBox_button_secondary" assets/themes/cubicraftia.tres` | ❌ W0 | ⬜ pending |
| 04-03-T2 | 04-03 | 1 | DOC-06 | — | SessionRegistry compute_elected_host is pure function; no network calls | unit (file check) | `grep -c "compute_elected_host\|am_i_elected" src/autoload/session_registry.gd` | ❌ W0 | ⬜ pending |
| 04-04-T1 | 04-04 | 2 | DOC-06 | T-04-04-E | is_invite_send_allowed() gates on is_email_verified(); is_friends_limit_reached() blocks at 50 friends; unverified accounts cannot send invites; FriendsClient connects to NetworkManager.session_metadata_received signal in _ready to populate _session_published_at cache; get_session_published_at() returns 0 for cache-miss sessions (unknown age — callers must not block on age when result is 0) | unit (stub + grep) | `grep -c "signed_in" src/autoload/friends_client.gd && grep "create_invite" src/autoload/friends_client.gd && grep "FriendsClient" project.godot && godot --headless --quit-after 30 -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg -- -gtest=tests/unit/test_friends_schema.gd -gtest=tests/unit/test_invite_token.gd 2>&1 \| grep -E "(Pending\|FAILED\|ERROR)" \| head -10` | ❌ W0 | ⬜ pending |
| 04-05-T1a | 04-05 | 2 | DOC-06 | T-04-05-T | broadcast_event guard: if not multiplayer.is_server(): return — peers cannot broadcast; session_list message from Go signaling server is parsed and session_metadata_received(session_id, published_at_unix) is emitted for each session entry in the array | unit (stub + grep) | `grep -c "keepalive_received\|keepalive_timeout" src/autoload/network_manager.gd && grep "_keepalive_ping\|_keepalive_pong" src/autoload/network_manager.gd && grep "session_metadata_received" src/autoload/network_manager.gd && grep "NetworkManager" project.godot && godot --headless --quit-after 30 -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg -- -gtest=tests/unit/test_keepalive_logic.gd -gtest=tests/unit/test_event_replication.gd 2>&1 \| grep -E "(Pending\|Risky\|FAILED\|ERROR)" \| head -10` | ❌ W0 | ⬜ pending |
| 04-05-T1b | 04-05 | 2 | DOC-06 | T-04-05-T2 | @rpc("authority") on _receive_replicated_event prevents non-host peers from calling it | unit (stub + grep) | `grep -c "FAILOVER_DETECTING\|FAILOVER_ELECTED\|FAILOVER_PROMOTING\|FAILOVER_COMPLETE\|FAILOVER_WAITING" src/autoload/network_manager.gd && grep "_on_failover_timer_timeout\|_do_failover_elected\|_do_failover_waiting" src/autoload/network_manager.gd && godot --headless --quit-after 30 -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg -- -gtest=tests/unit/test_election_algorithm.gd 2>&1 \| grep -E "(Pending\|Risky\|FAILED\|ERROR)" \| head -10` | ❌ W0 | ⬜ pending |
| 04-05-T2 | 04-05 | 2 | DOC-06 | T-04-05-T | broadcast hook uses is_instance_valid(NetworkManager) guard so tests do not crash when NetworkManager absent | unit (grep + phase3 regression) | `grep -v "^#" src/autoload/inventory.gd \| grep -c "NetworkManager.broadcast_event" && grep "get_all_state" src/autoload/inventory.gd && grep "reset_from_state" src/autoload/inventory.gd && godot --headless --quit-after 60 -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg -- -gtest=tests/unit/test_inventory_grid.gd 2>&1 \| grep -E "(PASSED\|FAILED\|ERROR)" \| head -5` | ❌ W0 | ⬜ pending |
| 04-06-T1 | 04-06 | 3 | DOC-06 | T-04-04-S | Sign-in credentials never logged; access token stored only in user://auth.cfg | checkpoint:human-verify | `ls src/ui/sign_in_panel.gd src/ui/sign_in_panel.tscn && grep "FriendsClient\.sign_in" src/ui/sign_in_panel.gd && grep "notify_friends_open" src/ui/mobile_overlay.gd` | ❌ W0 | ⬜ pending |
| 04-06-T2 | 04-06 | 3 | DOC-06 | — | Friends panel mutual exclusion prevents inventory + friends being open simultaneously | checkpoint:human-verify | `ls src/ui/friends_panel.gd src/ui/friends_panel.tscn && grep "FriendsClient\.get_friends" src/ui/friends_panel.gd` | ❌ W0 | ⬜ pending |
| 04-07-T1 | 04-07 | 3 | DOC-06 | T-04-07-I | Invite link in clipboard is deliberate user action; link expires in 24h; unverified-account join-age gate uses `published_at > 0` guard so sessions with unknown age (cache miss) are never false-blocked | unit (grep) | `ls src/ui/invite_modal.gd src/ui/invite_modal.tscn src/ui/join_screen.gd src/ui/join_screen.tscn && grep "DisplayServer.clipboard_set" src/ui/invite_modal.gd && grep "session_state_changed" src/ui/join_screen.gd && grep "published_at > 0" src/ui/join_screen.gd` | ❌ W0 | ⬜ pending |
| 04-07-T2 | 04-07 | 3 | DOC-06 | T-04-07-T | Players tab admin controls only shown when NetworkManager.is_session_host(); kick_peer RPC decorated @rpc("authority") | unit (grep) | `ls src/ui/players_tab.gd && grep "_build_rollback_section" src/ui/players_tab.gd && grep "PlayersTabBtn\|_set_active_tab" src/ui/settings_menu.gd && grep "FREEZE_BUILD" src/ui/players_tab.gd` | ❌ W0 | ⬜ pending |
| 04-08-T1 | 04-08 | 4 | DOC-06 | T-04-05-D | Chat does not go through event journal; rate limit enforced on host before broadcast; profanity filter applied before broadcast | unit (grep) | `ls src/ui/chat_overlay.gd src/networking/profanity_filter.gd && grep "_is_rate_limited\|_msg_count" src/ui/chat_overlay.gd && grep "ProfanityFilter\.filter" src/autoload/network_manager.gd` | ❌ W0 | ⬜ pending |
| 04-08-T2 | 04-08 | 4 | DOC-06 | — | Nameplates show/hide via settings; no PII in Label3D text beyond username | checkpoint:human-verify | `ls src/world/remote_builder_nameplate.gd src/ui/network_hud.gd src/ui/network_hud.tscn && grep "SessionRegistry\.get_peer_rtt" src/ui/network_hud.gd && grep "show_nameplates" src/world/remote_builder_nameplate.gd` | ❌ W0 | ⬜ pending |
| 04-09-T1 | 04-09 | 4 | DOC-06 | — | Handover screen NOT dismissible by user input; no Escape handler | unit (grep) | `ls src/ui/handover_screen.gd src/ui/handover_screen.tscn && grep "host_failover_started" src/ui/handover_screen.gd && grep "host_failover_complete" src/ui/handover_screen.gd` | ❌ W0 | ⬜ pending |
| 04-09-T2 | 04-09 | 4 | DOC-06 | T-04-05-SC | Autoload order enforced; NetworkManager loads after Inventory and WorldSave per Pitfall 8 | unit (grep) | `grep -n "NetworkManager\|FriendsClient\|Inventory\|WorldSave" project.godot \| grep "autoload"` | ❌ W0 | ⬜ pending |
| 04-10-T1 | 04-10 | 5 | DOC-06 | T-04-10-T | SNAPSHOT_RESET only from host (@rpc("authority")); snapshot blob validated before apply | integration | `godot --headless --quit-after 120 -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg -- -gtest=tests/integration/test_snapshot_migration.gd 2>&1 \| grep -E "(PASSED\|FAILED\|ERROR\|Pending)" \| head -10` | ❌ W0 | ⬜ pending |
| 04-10-T2 | 04-10 | 5 | DOC-06 | T-04-10-P6 | Snapshot timer stops on DISCONNECTED; background snapshot saved on iOS focus loss | unit (grep) | `grep -v "^#" src/autoload/network_manager.gd \| grep -c "save_world_snapshot" && grep "_receive_snapshot_reset" src/autoload/network_manager.gd && grep "_on_snapshot_timer_timeout" src/autoload/network_manager.gd && grep "focus_exited\|focus_lost\|app_focus" src/autoload/network_manager.gd` | ❌ W0 | ⬜ pending |
| 04-11-T1 | 04-11 | 6 | DOC-06 | T-04-11-01 | @rpc("authority") on _receive_replicated_event prevents non-authority peers from calling; test asserts guard logic | unit | `cd /Users/jnuyens/src/LegoMinecraft && godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_election_algorithm.gd,tests/unit/test_event_replication.gd,tests/unit/test_keepalive_logic.gd 2>&1 \| grep -E "^(Passed\|Failed\|Errors\|Pending)" \| tail -5` | ❌ W0 | ⬜ pending |
| 04-11-T2 | 04-11 | 6 | DOC-06 | T-04-04-D | Invite token alphabet enforced (26 chars, base32 only); expired token rejected; single-use enforced | unit | `cd /Users/jnuyens/src/LegoMinecraft && godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_friends_schema.gd,tests/unit/test_invite_token.gd,tests/unit/test_chat_rate_limit.gd 2>&1 \| grep -E "^(Passed\|Failed\|Errors\|Pending)" \| tail -5` | ❌ W0 | ⬜ pending |
| 04-11-T3 | 04-11 | 6 | DOC-06 | T-04-11-03 | Rate-limit test uses direct field manipulation (not wall-clock); time-bounded failover assertion: elapsed < 4000ms; failover state machine transitions through all 4 expected states (DETECTING → ELECTED → PROMOTING → COMPLETE) with cross-autoload dependencies satisfied via Engine.register_singleton (not silently no-op'd) | integration | `cd /Users/jnuyens/src/LegoMinecraft && godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/integration/test_failover_fault_injection.gd 2>&1 \| grep -E "^(Passed\|Failed\|Errors\|Pending)" \| tail -5` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Plan 04-01 IS the Wave 0 plan. It ships the following test-stub files that all subsequent plans depend on:

| File | Ships In | Test Functions (all `pending()`) |
|------|----------|----------------------------------|
| `tests/conftest_phase4.gd` | 04-01 T1 | `make_rtt_table`, `make_join_order`, `open_temp_world`, `cleanup_temp_world` |
| `tests/unit/test_election_algorithm.gd` | 04-01 T1 | `test_lowest_rtt_wins`, `test_tiebreaker_older_peer_wins`, `test_sole_survivor_elects_self`, `test_equal_rtt_sorted_join_order` |
| `tests/unit/test_event_replication.gd` | 04-01 T1 | `test_host_broadcast_called_on_apply`, `test_peer_apply_produces_same_state`, `test_non_host_does_not_broadcast` |
| `tests/unit/test_keepalive_logic.gd` | 04-01 T1 | `test_3_missed_emits_laggy`, `test_6_missed_emits_disconnect`, `test_recovery_clears_laggy` |
| `tests/unit/test_friends_schema.gd` | 04-01 T1 | `test_canonical_order_enforced`, `test_select_own_friendships_only`, `test_delete_own_friendship` |
| `tests/unit/test_invite_token.gd` | 04-01 T1 | `test_token_is_26_chars_base32`, `test_single_use_enforced`, `test_24h_ttl_expiry` |
| `tests/unit/test_chat_rate_limit.gd` | 04-01 T1 | `test_5_per_10s_allowed`, `test_6th_message_dropped`, `test_profanity_replaced_with_filtered` |
| `tests/integration/test_snapshot_migration.gd` | 04-01 T1 | `test_migrate_2_to_3_creates_snapshots_table`, `test_save_and_load_snapshot_roundtrip`, `test_snapshot_size_under_2mb` |
| `addons/webrtc-native/webrtc_native.gdextension` | 04-01 T2 | N/A — extension manifest |
| `locale/en.po` (65+ Phase 4 keys) | 04-01 T2 | N/A — i18n resource |

**Wave 0 gate:** GUT runs all 7 unit test files without import errors. All tests report Risky/Pending (not FAILED, not ERROR). `conftest_phase4.gd` is NOT registered as an autoload in `project.godot`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Host-failover handover budget on real mobile network | DOC-06 §6.5 | Real LTE/5G + WebRTC reconnect latency only measurable on hardware | 2-device session, host on cellular, kill host's app via OS — measure handover from peer's POV stopwatch (target 2-4 s per DOCS) |
| Cross-platform play (macOS host ↔ Windows peer ↔ iOS peer) | DOC-06 §6.4 | Cross-platform WebRTC behavior only verifiable with real OS combinations | 3-device session with one of each platform; place + break bricks; verify state converges |
| TURN relay activation when both peers are on cellular CGNAT | DOC-06 §7.4 | Symmetric NAT scenarios only reproducible with real cellular networks | 2 phones on different carriers, force WebRTC to TURN by blocking STUN port — verify "Relay" badge shows on both ends |
| Invite-link OS share sheet (iOS Universal Links + Android App Links) | DOC-06 §6.3 | Deep linking only works on real devices | Generate invite, share via iMessage / WhatsApp, open on second device — verify deep link opens app and takes joiner into join flow |
| Profanity filter coverage gaps | DOC-06 §6.6 | Word list is Phase 5 scope; Phase 4 ships a 30-word stub; manual review captures coverage gaps | Each tester sends 20 candidate messages including edge cases (l33t, multi-language, intentional misspellings); log what slips through |
| Unverified account join block (session >24h old) | DOC-06 + CONTEXT Area 3 | Requires a real Supabase instance with an unverified-email account and a session published >24h ago | Sign up, do not click verification link, wait 25h (or set published_at to 25h ago in test DB), attempt join — verify error message appears and join is blocked |

---

## Nyquist Coverage Targets

Per DOC-06 + CONTEXT §Area 1-4 + DOCS §6.5 the failover behaviour and Inventory event replication are the highest-risk surfaces. Coverage targets:

- **NetworkManager state machine** — 100% branch coverage for the 10 failover states (IDLE / CONNECTING / CONNECTED_AS_HOST / CONNECTED_AS_PEER / FAILOVER_DETECTING / FAILOVER_ELECTED / FAILOVER_PROMOTING / FAILOVER_COMPLETE / FAILOVER_WAITING / RECONNECTING / DISCONNECTED)
- **Inventory event broadcast hook** — 100% of `apply_event` event kinds verified to broadcast when `is_server()` and to NOT broadcast otherwise (Phase 3 regression guard)
- **Friends graph RLS** — 100% policy coverage: SELECT/INSERT/DELETE positive + negative cases per policy
- **Invite token lifecycle** — single-use enforcement + 24h TTL + redeem-while-expired error path
- **Chat rate limit** — 5/10s threshold + over-limit message dropping + countdown label render
- **Snapshot promotion** — promotes most-recent-snapshot when host disconnects mid-write (no partial commit)
- **Failover SLA** — `elapsed < 4000ms` assertion in `test_failover_fault_injection.gd` (mandatory, no fallback)
- **Friends count limit** — 50-friend cap enforced in `is_friends_limit_reached()` before friendship POST
- **Unverified-account join gate** — `get_session_published_at()` check in JoinScreen blocks join only when `published_at > 0` (cache hit) AND age > 86400s AND email not verified; sessions with unknown age (cache miss = 0) are never blocked

Manual-only tests above cover the remaining behaviour that headless GUT cannot reach.
