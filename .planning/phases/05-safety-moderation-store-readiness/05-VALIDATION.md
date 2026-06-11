---
phase: 5
slug: safety-moderation-store-readiness
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-05-29
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | GUT (Godot Unit Test) for GDScript · `go test ./...` for Go signaling · `supabase test db` for RLS SQL · shell `grep` for file/structure checks |
| **Config file** | `tests/gut_config.cfg` (existing from Phase 1) · `tests/conftest_phase5.gd` (created in 05-01) |
| **Quick run command** | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=tests/gut_config.cfg 2>&1 \| grep -E "^(Passed\|Failed\|Errors\|Pending)"` |
| **Safety-only subset** | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_profanity_filter.gd,tests/unit/test_username_policy.gd,tests/unit/test_block_report_schema.gd,tests/unit/test_parental_consent_flow.gd,tests/unit/test_eula_hash.gd,tests/unit/test_consent_token.gd,tests/unit/test_report_rate_limit.gd 2>&1 \| grep -E "^(Passed\|Failed\|Errors\|Pending)"` |
| **Full suite command** | quick + `cd signaling-server && go test ./...` + `supabase test db` |
| **Estimated runtime** | ~35 s GUT safety subset · ~15 s Go tests · ~20 s Supabase tests = ~70 s full |

---

## Sampling Rate

- **After every task commit:** Run the relevant subset (GUT for GDScript tasks, `go test` for Go/signaling tasks, `supabase test db` for SQL migration tasks)
- **After every plan wave:** Run full suite
- **Before `/gsd:verify-work`:** Full suite green AND all security grep gates pass
- **Max feedback latency:** 70 s

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-T1 | 05-01 | 1 | DOC-08 | T-05-SC | test stub files must not crash on import; all tests report Pending not FAILED | unit (stub) | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_profanity_filter.gd,tests/unit/test_username_policy.gd,tests/unit/test_block_report_schema.gd,tests/unit/test_parental_consent_flow.gd,tests/unit/test_eula_hash.gd,tests/unit/test_consent_token.gd,tests/unit/test_report_rate_limit.gd 2>&1 \| grep -E "(ERROR\|FAILED)" \| head -5` | ❌ W0 | ⬜ pending |
| 05-01-T2 | 05-01 | 1 | DOC-08 | — | 53 locale keys present; 3 StyleBoxes declared; icon stubs exist | file check (grep) | `grep -c 'msgid "ui\.block\.' locale/en.po && grep -c 'msgid "ui\.report\.' locale/en.po && grep -c 'msgid "ui\.consent\.' locale/en.po && grep "StyleBox_warning_banner" assets/themes/cubicraftia.tres && ls assets/icons/icon_block.png assets/icons/icon_report.png assets/icons/icon_error.png` | ❌ W0 | ⬜ pending |
| 05-02-T1 | 05-02 | 1 | DOC-08 | T-05-T1 | (SELECT auth.uid()) wrapper used in ALL RLS policies (never raw auth.uid()); no_self_block CHECK present; reports immutable (no DELETE policy) | unit (grep) | `grep -rn "auth\.uid()" /Users/jnuyens/src/LegoMinecraft/supabase/migrations/004_blocks.sql /Users/jnuyens/src/LegoMinecraft/supabase/migrations/005_reports.sql /Users/jnuyens/src/LegoMinecraft/supabase/migrations/006_parental_consents.sql /Users/jnuyens/src/LegoMinecraft/supabase/migrations/007_username_change_log.sql /Users/jnuyens/src/LegoMinecraft/supabase/migrations/008_profiles_safety_columns.sql \| grep -v "SELECT auth\.uid()" \| head -5 && grep "no_self_block\|CHECK.*blocker_id.*<>.*blocked_id" /Users/jnuyens/src/LegoMinecraft/supabase/migrations/004_blocks.sql && grep "SECURITY DEFINER" /Users/jnuyens/src/LegoMinecraft/supabase/migrations/007_username_change_log.sql` | ❌ W0 | ⬜ pending |
| 05-02-T2 | 05-02 | 1 | DOC-08 | T-05-I1 | parental_consents token is UNIQUE; consent_link_sent_at column exists; username_change_log 30-day cooldown check function present | unit (grep) | `grep "token.*UNIQUE\|UNIQUE.*token" /Users/jnuyens/src/LegoMinecraft/supabase/migrations/006_parental_consents.sql && grep "consent_link_sent_at\|is_under_13" /Users/jnuyens/src/LegoMinecraft/supabase/migrations/008_profiles_safety_columns.sql && grep "can_change_username" /Users/jnuyens/src/LegoMinecraft/supabase/migrations/007_username_change_log.sql` | ❌ W0 | ⬜ pending |
| 05-03-T1 | 05-03 | 1 | DOC-08 | — | CC-BY-4.0 attribution present in README; dual _regex_en and _regex_nl (never merged); filter_reject() method exists | unit (grep) | `grep "CC-BY-4.0\|Creative Commons" /Users/jnuyens/src/LegoMinecraft/assets/profanity/README.md && grep "filter_reject" /Users/jnuyens/src/LegoMinecraft/src/networking/profanity_filter.gd && grep -v "filter_reject" /Users/jnuyens/src/LegoMinecraft/src/networking/profanity_filter.gd \| grep "_regex_en\|_regex_nl" \| head -5` | ❌ W0 | ⬜ pending |
| 05-03-T2 | 05-03 | 1 | DOC-08 | — | word lists exist; _ensure_regex() warms up on class load; no single merged _regex_all | unit (stub + grep) | `ls /Users/jnuyens/src/LegoMinecraft/assets/profanity/wordlist_en.txt /Users/jnuyens/src/LegoMinecraft/assets/profanity/wordlist_nl.txt && grep "_ensure_regex" /Users/jnuyens/src/LegoMinecraft/src/networking/profanity_filter.gd && ! grep -q "_regex_all\|_regex_combined" /Users/jnuyens/src/LegoMinecraft/src/networking/profanity_filter.gd && godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_profanity_filter.gd 2>&1 \| grep -E "(Pending\|FAILED\|ERROR)" \| head -5` | ❌ W0 | ⬜ pending |
| 05-04-T1 | 05-04 | 2 | DOC-08 | T-05-T1, T-05-E2 | isBlockedBetween() queries both directions (A→B AND B→A); service-role key used (not anon); VerifyJWT called before block check | unit (go test + grep) | `cd /Users/jnuyens/src/LegoMinecraft/signaling-server && go build ./cmd/signaling 2>&1 && grep -c "isBlockedBetween\|blocked_uid.*=.*\$\|blocker_id.*=.*\$" hub.go && go test ./... 2>&1 \| grep -E "^(ok\|FAIL\|---)"` | ❌ W0 | ⬜ pending |
| 05-04-T2 | 05-04 | 2 | DOC-08 | T-05-S1, T-05-D1 | consent.go token generated via crypto/rand (128-bit); report rate limit 5/24h enforced before INSERT; consent Confirm endpoint invalidates token after use | unit (go test + grep) | `grep "crypto/rand\|rand\.Read" /Users/jnuyens/src/LegoMinecraft/signaling-server/consent.go && grep "5.*report\|rate.*limit\|report.*count" /Users/jnuyens/src/LegoMinecraft/signaling-server/hub.go && grep "redeemed_at\|single.use\|UPDATE.*token.*WHERE" /Users/jnuyens/src/LegoMinecraft/signaling-server/consent.go && cd /Users/jnuyens/src/LegoMinecraft/signaling-server && go test ./... 2>&1 \| grep -E "TestConsent\|TestReport\|FAIL"` | ❌ W0 | ⬜ pending |
| 05-05-T1 | 05-05 | 2 | DOC-08 | T-05-S1 | raw DOB never sent to Supabase; is_under_13 computed locally from timestamp; sign_up() accepts dob_year/dob_month/dob_day params and computes boolean | unit (stub + grep) | `grep "is_under_13\|_compute_age" /Users/jnuyens/src/LegoMinecraft/src/autoload/friends_client.gd && ! grep -q "dob.*=.*dob\|date_of_birth.*store\|raw.*dob" /Users/jnuyens/src/LegoMinecraft/src/autoload/friends_client.gd && grep "block_user\|unblock_user\|get_blocks\|submit_report\|request_parental_consent" /Users/jnuyens/src/LegoMinecraft/src/autoload/friends_client.gd && godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_parental_consent_flow.gd 2>&1 \| grep -E "(Pending\|FAILED\|ERROR)" \| head -5` | ❌ W0 | ⬜ pending |
| 05-05-T2 | 05-05 | 2 | DOC-08 | T-05-E1 | UsernamePol.validate() returns {valid, error_key}; reserved prefix check present; 30-day cooldown check present; ^[a-zA-Z0-9_]{3,20}$ regex enforced | unit (stub + grep) | `ls /Users/jnuyens/src/LegoMinecraft/src/autoload/username_policy.gd && grep "validate\|error_key\|reserved\|cooldown\|3,20" /Users/jnuyens/src/LegoMinecraft/src/autoload/username_policy.gd && godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_username_policy.gd 2>&1 \| grep -E "(Pending\|FAILED\|ERROR)" \| head -5` | ❌ W0 | ⬜ pending |
| 05-06-T1 | 05-06 | 2 | DOC-08 | — | docs/EULA.md and docs/PRIVACY.md exist; PRIVACY.md enumerates all 7 data types from §8.5; CC-BY-4.0 profanity list attribution present; NCMEC CSAM forwarding mentioned | file check | `ls /Users/jnuyens/src/LegoMinecraft/docs/EULA.md /Users/jnuyens/src/LegoMinecraft/docs/PRIVACY.md && grep -c "email\|username\|friend.*list\|blocked.*list\|world.*ownership\|parent.*email\|telemetry" /Users/jnuyens/src/LegoMinecraft/docs/PRIVACY.md && grep "NCMEC\|CSAM" /Users/jnuyens/src/LegoMinecraft/docs/PRIVACY.md && grep "plain.language\|Summary\|summary" /Users/jnuyens/src/LegoMinecraft/docs/EULA.md` | ❌ W0 | ⬜ pending |
| 05-07-T1 | 05-07 | 3 | DOC-08 | T-05-S2 | DOB picker uses 3 OptionButtons (not a free-text field); is_under_13 computed client-side from timestamp; _age_checkbox removed from scene; existing keys kept for transition | unit (grep + parse check) | `godot --headless --check-only /Users/jnuyens/src/LegoMinecraft/src/ui/sign_in_panel.gd 2>&1 \| grep -E "(ERROR\|Parse error)" \| head -5 && grep "dob_year\|dob_month\|dob_day\|OptionButton" /Users/jnuyens/src/LegoMinecraft/src/ui/sign_in_panel.gd && ! grep -q "_age_checkbox" /Users/jnuyens/src/LegoMinecraft/src/ui/sign_in_panel.gd` | ❌ W0 | ⬜ pending |
| 05-07-T2 | 05-07 | 3 | DOC-08 | T-05-E3 | parental_gate_panel.gd exists; restricted_banner on CanvasLayer 5 with amber StyleBox_warning_banner; FriendsClient.consent_status_received signal connected | unit (grep + parse check) | `godot --headless --check-only /Users/jnuyens/src/LegoMinecraft/src/ui/parental_gate_panel.gd 2>&1 \| grep -E "(ERROR\|Parse error)" \| head -5 && grep "CanvasLayer\|layer.*5\|LAYER_5" /Users/jnuyens/src/LegoMinecraft/src/ui/parental_gate_panel.gd && grep "StyleBox_warning_banner\|amber" /Users/jnuyens/src/LegoMinecraft/src/ui/parental_gate_panel.gd && grep "consent_status_received" /Users/jnuyens/src/LegoMinecraft/src/ui/parental_gate_panel.gd` | ❌ W0 | ⬜ pending |
| 05-08-T1 | 05-08 | 3 | DOC-08 | T-05-I1 | ContextMenu is a singleton (autoload), NOT instantiated per row; long-press Timer 500ms pattern used; block_modal and report_modal exist | unit (grep + parse check) | `godot --headless --check-only /Users/jnuyens/src/LegoMinecraft/src/ui/context_menu.gd 2>&1 \| grep -E "(ERROR\|Parse error)" \| head -5 && grep "ContextMenu" /Users/jnuyens/src/LegoMinecraft/project.godot && grep "0.5\|wait_time.*0.5\|500" /Users/jnuyens/src/LegoMinecraft/src/ui/context_menu.gd && ls /Users/jnuyens/src/LegoMinecraft/src/ui/block_modal.gd /Users/jnuyens/src/LegoMinecraft/src/ui/report_modal.gd` | ❌ W0 | ⬜ pending |
| 05-08-T2 | 05-08 | 3 | DOC-08 | T-05-T1 | report modal requires category selection (ButtonGroup exclusive) before submit; 2-step modal (category → reason) enforced; friends_panel and chat_overlay show context menu on long-press | unit (grep) | `grep "ButtonGroup\|button_group" /Users/jnuyens/src/LegoMinecraft/src/ui/report_modal.gd && grep "_long_press_timer\|long_press\|_on_long_press" /Users/jnuyens/src/LegoMinecraft/src/ui/chat_overlay.gd && grep "ContextMenu.show\|context_menu.show" /Users/jnuyens/src/LegoMinecraft/src/world/remote_builder_nameplate.gd && godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_block_report_schema.gd 2>&1 \| grep -E "(Pending\|FAILED\|ERROR)" \| head -5` | ❌ W0 | ⬜ pending |
| 05-09-T1 | 05-09 | 3 | DOC-08 | — | legal_viewer.gd parses Markdown to BBCode (6 constructs only); SHA-256 hash computed over EULA.md in 4096-byte chunks; footer displays first 16 hex chars | unit (grep + parse check) | `godot --headless --check-only /Users/jnuyens/src/LegoMinecraft/src/ui/legal_viewer.gd 2>&1 \| grep -E "(ERROR\|Parse error)" \| head -5 && grep "SHA256\|sha256\|HashingContext" /Users/jnuyens/src/LegoMinecraft/src/ui/legal_viewer.gd && grep "4096\|chunk" /Users/jnuyens/src/LegoMinecraft/src/ui/legal_viewer.gd && grep "16\|:16\|substr.*16" /Users/jnuyens/src/LegoMinecraft/src/ui/legal_viewer.gd` | ❌ W0 | ⬜ pending |
| 05-09-T2 | 05-09 | 3 | DOC-08 | — | eula_acknowledge_modal.gd writes hash via FriendsClient.store_eula_hash(); settings_menu.gd has Legal + Account sections; account deletion shows 7-day grace copy; EULA re-acknowledge modal fires on hash mismatch at startup | unit (grep + parse check) | `godot --headless --check-only /Users/jnuyens/src/LegoMinecraft/src/ui/eula_acknowledge_modal.gd 2>&1 \| grep -E "(ERROR\|Parse error)" \| head -5 && grep "store_eula_hash" /Users/jnuyens/src/LegoMinecraft/src/ui/eula_acknowledge_modal.gd && grep "Legal\|legal_viewer\|eula_acknowledge" /Users/jnuyens/src/LegoMinecraft/src/ui/settings_menu.gd && grep "7.day\|7 day\|grace" /Users/jnuyens/src/LegoMinecraft/src/ui/settings_menu.gd && godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_eula_hash.gd 2>&1 \| grep -E "(Pending\|FAILED\|ERROR)" \| head -5` | ❌ W0 | ⬜ pending |
| 05-10-T1 | 05-10 | 4 | DOC-08 | T-05-bypass, T-05-P-wn | inline username validation uses UsernamePol.validate() (format-only — no server call); 500ms debounce timer; ProfanityFilter.filter_reject() in create_world(); server uniqueness NOT checked inline | unit (grep + parse check) | `godot --headless --check-only /Users/jnuyens/src/LegoMinecraft/src/ui/sign_in_panel.gd 2>&1 \| grep -E "(ERROR\|Parse error)" \| head -5 && grep "UsernamePol.validate\|UsernamePol\.validate" /Users/jnuyens/src/LegoMinecraft/src/ui/sign_in_panel.gd && grep "0.5\|wait_time.*0.5" /Users/jnuyens/src/LegoMinecraft/src/ui/sign_in_panel.gd && grep "filter_reject" /Users/jnuyens/src/LegoMinecraft/src/autoload/world_save.gd` | ❌ W0 | ⬜ pending |
| 05-10-T2 | 05-10 | 4 | DOC-08 | T-05-bypass, T-05-E3 | _is_blocked_locally() used before peer_joined emission; chat packet suppressed for unconsented under-13; _session_muted list filters incoming messages; all guards use is_instance_valid(FriendsClient) | unit (grep + parse check) | `godot --headless --check-only /Users/jnuyens/src/LegoMinecraft/src/autoload/network_manager.gd 2>&1 \| grep -E "(ERROR\|Parse error)" \| head -5 && grep "_is_blocked_locally" /Users/jnuyens/src/LegoMinecraft/src/autoload/network_manager.gd && grep "_session_muted" /Users/jnuyens/src/LegoMinecraft/src/autoload/network_manager.gd && grep "is_instance_valid" /Users/jnuyens/src/LegoMinecraft/src/autoload/network_manager.gd` | ❌ W0 | ⬜ pending |
| 05-11-T1 | 05-11 | 4 | DOC-08 | — | 7 store-readiness docs exist; privacy-nutrition.json matches PRIVACY.md data types exactly | file check | `ls /Users/jnuyens/src/LegoMinecraft/docs/store-readiness/privacy-nutrition.json /Users/jnuyens/src/LegoMinecraft/docs/store-readiness/data-safety-form.md /Users/jnuyens/src/LegoMinecraft/docs/store-readiness/app-store-checklist.md /Users/jnuyens/src/LegoMinecraft/docs/store-readiness/play-store-checklist.md /Users/jnuyens/src/LegoMinecraft/docs/store-readiness/signing-runbook.md /Users/jnuyens/src/LegoMinecraft/docs/store-readiness/testflight-runbook.md /Users/jnuyens/src/LegoMinecraft/docs/store-readiness/play-internal-testing-runbook.md && python3 -c "import json; d=json.load(open('/Users/jnuyens/src/LegoMinecraft/docs/store-readiness/privacy-nutrition.json')); assert len(d.get('data_types',[])) >= 7, 'Missing data types'"` | ❌ W0 | ⬜ pending |
| 05-11-T2 | 05-11 | 4 | DOC-08 | — | iOS CI row added to ci.yml; macos-15 runner; dulvui/godot-ios-upload@v4; conditional on APPLE_CERTIFICATE_P12; D-04 closure comment present | file check (grep) | `grep "macos-15\|macos_15" /Users/jnuyens/src/LegoMinecraft/.github/workflows/ci.yml && grep "dulvui/godot-ios-upload" /Users/jnuyens/src/LegoMinecraft/.github/workflows/ci.yml && grep "APPLE_CERTIFICATE_P12\|secrets\.APPLE_CERTIFICATE" /Users/jnuyens/src/LegoMinecraft/.github/workflows/ci.yml && grep "D-04\|Phase.1.*deviation\|iOS.*CI.*closure" /Users/jnuyens/src/LegoMinecraft/.github/workflows/ci.yml` | ❌ W0 | ⬜ pending |
| 05-12-T1 | 05-12 | 5 | DOC-08 | T-05-T1, T-05-S1, T-05-E1 | All unit test stubs activated to real assertions; no pending() calls remain in Phase 5 test files; test_profanity_filter + test_username_policy + test_block_report_schema green | unit | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_profanity_filter.gd,tests/unit/test_username_policy.gd,tests/unit/test_block_report_schema.gd 2>&1 \| grep -E "^(Passed\|Failed\|Errors\|Pending)" \| tail -5` | ❌ W0 | ⬜ pending |
| 05-12-T2 | 05-12 | 5 | DOC-08 | T-05-S1, T-05-E3 | test_parental_consent_flow + test_eula_hash + test_consent_token + test_report_rate_limit green; _should_suppress_chat() exists as testable method; no pending() stubs in any Phase 5 test file | unit | `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=tests/unit/test_parental_consent_flow.gd,tests/unit/test_eula_hash.gd,tests/unit/test_consent_token.gd,tests/unit/test_report_rate_limit.gd 2>&1 \| grep -E "^(Passed\|Failed\|Errors\|Pending)" \| tail -5 && grep "_should_suppress_chat" /Users/jnuyens/src/LegoMinecraft/src/autoload/network_manager.gd && ! grep -rq "pending()" /Users/jnuyens/src/LegoMinecraft/tests/unit/test_profanity_filter.gd /Users/jnuyens/src/LegoMinecraft/tests/unit/test_username_policy.gd /Users/jnuyens/src/LegoMinecraft/tests/unit/test_block_report_schema.gd /Users/jnuyens/src/LegoMinecraft/tests/unit/test_parental_consent_flow.gd /Users/jnuyens/src/LegoMinecraft/tests/unit/test_eula_hash.gd /Users/jnuyens/src/LegoMinecraft/tests/unit/test_consent_token.gd /Users/jnuyens/src/LegoMinecraft/tests/unit/test_report_rate_limit.gd` | ❌ W0 | ⬜ pending |
| 05-12-T3 | 05-12 | 5 | DOC-08 | — | DOCS.md §8 updated to match implemented architecture; DDD discipline confirmed; no pending DOCS claims | integration (file check) | `grep "§8\|Section 8\|## 8" /Users/jnuyens/src/LegoMinecraft/.planning/DOCS.md \| head -3 && grep "block.*mutual\|report.*three.*surfaces\|profanity.*filter.*reject\|parental.*consent\|EULA\|privacy.*policy" /Users/jnuyens/src/LegoMinecraft/.planning/DOCS.md \| head -10` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Plan 05-01 IS the Wave 0 plan. It ships the following test-stub files that all subsequent plans depend on:

| File | Ships In | Test Functions (all `pending()`) |
|------|----------|----------------------------------|
| `tests/conftest_phase5.gd` | 05-01 T1 | `make_mock_block_row`, `make_mock_report_row`, `make_mock_consent_row` |
| `tests/unit/test_profanity_filter.gd` | 05-01 T1 | `test_en_word_rejected`, `test_nl_word_rejected`, `test_clean_word_passes`, `test_filter_reject_returns_bool`, `test_filter_replace_returns_string`, `test_no_word_echoed_in_error` |
| `tests/unit/test_username_policy.gd` | 05-01 T1 | `test_valid_username_passes`, `test_too_short_rejected`, `test_too_long_rejected`, `test_invalid_chars_rejected`, `test_reserved_prefix_rejected`, `test_profanity_match_rejected` |
| `tests/unit/test_block_report_schema.gd` | 05-01 T1 | `test_block_row_has_required_fields`, `test_report_row_has_required_fields`, `test_block_is_mutual_logically`, `test_report_immutable` |
| `tests/unit/test_parental_consent_flow.gd` | 05-01 T1 | `test_under_13_computed_correctly`, `test_over_13_not_flagged`, `test_consent_flow_started_on_under_13_signup`, `test_unconsented_blocks_session_join` |
| `tests/unit/test_eula_hash.gd` | 05-01 T1 | `test_hash_stored_on_accept`, `test_hash_mismatch_triggers_modal`, `test_hash_is_16_hex_chars`, `test_empty_eula_handled` |
| `tests/unit/test_consent_token.gd` | 05-01 T1 | `test_token_is_128_bit_base32`, `test_token_expires_after_7_days`, `test_token_single_use`, `test_revoke_clears_consent` |
| `tests/unit/test_report_rate_limit.gd` | 05-01 T1 | `test_5_reports_per_24h_allowed`, `test_6th_report_rejected`, `test_rate_limit_resets_after_24h` |
| `tests/integration/test_safety_integration.gd` | 05-01 T1 | `test_blocked_user_not_in_peer_joined`, `test_chat_suppressed_for_unconsented_under_13` |

**Wave 0 gate:** GUT runs all 7 unit test files + 1 integration stub without import errors. All tests report Risky/Pending (not FAILED, not ERROR). `conftest_phase5.gd` is NOT registered as an autoload in `project.godot`. The 3 icon stubs (icon_block.png, icon_report.png, icon_error.png) are 16×16 placeholder PNGs — GUT does not import PNGs but Godot scene load must not error on them.

---

## Security Grep Gates (run after every wave)

These gates verify safety-critical invariants that unit tests cannot express:

| Gate ID | What It Checks | Command | Must Return |
|---------|----------------|---------|-------------|
| SG-01 | No raw auth.uid() in RLS (always wrapped) | `grep -rn "auth\.uid()" /Users/jnuyens/src/LegoMinecraft/supabase/migrations/ \| grep -v "SELECT auth\.uid()" \| grep -v "^--"` | 0 lines |
| SG-02 | Raw DOB never stored in FriendsClient | `grep -n "date_of_birth\|raw_dob\|dob.*store\|store.*dob" /Users/jnuyens/src/LegoMinecraft/src/autoload/friends_client.gd` | 0 lines |
| SG-03 | Profanity regex not merged into one | `grep -n "_regex_all\|_regex_combined\|_regex_merged" /Users/jnuyens/src/LegoMinecraft/src/networking/profanity_filter.gd` | 0 lines |
| SG-04 | Rejected profanity not echoed in error keys | `grep -n "filter_reject.*echo\|error.*word\|word.*error" /Users/jnuyens/src/LegoMinecraft/src/networking/profanity_filter.gd` | 0 lines |
| SG-05 | consent token uses crypto/rand (not math/rand) | `grep -n "math/rand\|rand\.Intn\|rand\.New" /Users/jnuyens/src/LegoMinecraft/signaling-server/consent.go` | 0 lines |
| SG-06 | GoTrue email templates NOT used for consent | `grep -rn "resend\|mailer\|gotrue.*email\|auth.*resend" /Users/jnuyens/src/LegoMinecraft/signaling-server/consent.go` | 0 lines |
| SG-07 | ContextMenu NOT instantiated per row | `grep -rn "ContextMenu\.new()\|context_menu\.new()\|preload.*context_menu.*new()" /Users/jnuyens/src/LegoMinecraft/src/ui/` | 0 lines |
| SG-08 | CC-BY-4.0 attribution present in word list README | `grep -c "CC-BY-4.0\|Creative Commons Attribution 4" /Users/jnuyens/src/LegoMinecraft/assets/profanity/README.md` | ≥ 1 |
| SG-09 | iOS CI row conditional on APPLE_CERTIFICATE_P12 | `grep "APPLE_CERTIFICATE_P12" /Users/jnuyens/src/LegoMinecraft/.github/workflows/ci.yml` | ≥ 1 line |
| SG-10 | _should_suppress_chat() is testable (not inlined) | `grep "func _should_suppress_chat" /Users/jnuyens/src/LegoMinecraft/src/autoload/network_manager.gd` | ≥ 1 line |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Under-13 full consent flow (email delivery + link click) | DOC-08 §8.5 | Real SMTP delivery and browser-link-click cannot be automated headlessly | Sign up with DOB = 10 years ago → check parent email arrives → click consent link → verify restricted banner dismisses in-game |
| Block mutual enforcement across sessions | DOC-08 §8.1 | Requires two real signed-in accounts in a live session | Account A blocks Account B → B opens a new session → A joins → verify A does NOT appear in B's peer list from B's side |
| Report submission to moderation queue | DOC-08 §8.1 | Requires running Go signaling server + Supabase with real data | Player submits report → query `reports` table in Supabase → verify row exists with correct category, reporter_uid, reported_uid, context |
| Profanity filter coverage gaps (EN + NL) | DOC-08 §8.3 | Word list is curated; automated tests cover known words; manual review catches creative evasions | Each tester sends 20 candidate messages including l33t-speak, diacritics, intentional misspellings in EN and NL; log what slips through |
| EULA re-acknowledge modal on version bump | DOC-08 §8.5 | Requires a live settings.cfg from a previous version with a different hash | Manually change docs/EULA.md → launch game → verify re-acknowledge modal appears before main menu |
| Parental consent revocation flow | DOC-08 §8.5 | Requires live parent consent link + two browser sessions | Parent confirms consent → verify banner dismisses → parent clicks revoke link → verify restricted banner reappears next session |
| App Store privacy nutrition label accuracy | DOC-08 §8.5 | Human review of Apple's submission form vs privacy-nutrition.json | Compare privacy-nutrition.json data_types against the App Store Connect "App Privacy" page entries one-by-one |
| Play Store data safety form accuracy | DOC-08 §8.5 | Human review of Google Play Console form vs data-safety-form.md | Follow data-safety-form.md answers on Play Console; verify "Safety" tab shows "No data shared with third parties" for production build |
| iOS CI pipeline end-to-end (TestFlight upload) | DOC-08 + Phase 1 D-04 | Requires Apple Developer Program certs in GitHub secrets | Push to main with valid APPLE_CERTIFICATE_P12 secret set → verify CI ios-build job passes → verify build appears in TestFlight |

---

## Nyquist Coverage Targets

Per DOC-08 + CONTEXT.md Areas 1-6 + DOCS.md §8, the block/report enforcement and parental consent gate are the highest-risk surfaces. Coverage targets:

- **Block enforcement (Go signaling)** — 100% of peer_join attempts check both directions of the block relationship (A→B and B→A); TestBlockedPeer asserts join is rejected
- **Profanity filter** — 100% coverage for filter() (chat replace) and filter_reject() (username/world-name/avatar-name hard reject); edge cases: empty string, string = exactly one blacklisted word, string with diacritics that normalise to a blacklisted word
- **Username policy** — 100% of validate() branches: too_short, too_long, invalid_chars, reserved_prefix, profanity_match, cooldown_active; valid case returns {valid: true, error_key: ""}
- **Consent token lifecycle** — single-use enforcement + 7-day TTL + revoke-clears-consent path
- **Report rate limit** — 5/24h threshold + over-limit rejection + reset-after-24h
- **EULA hash** — stores on accept + triggers modal on mismatch + is exactly 16 hex chars
- **Parental consent gate** — under-13 account cannot join session until consent row exists; over-13 account is unaffected; age computed from DOB at sign-up time (raw DOB never stored)
- **NetworkManager suppress guards** — _is_blocked_locally() called before every peer_joined emission; _should_suppress_chat() called before every outbound chat packet; is_instance_valid(FriendsClient) wraps every guard

Manual-only tests above cover the remaining behaviour that headless GUT cannot reach.
