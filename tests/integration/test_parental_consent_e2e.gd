# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_parental_consent_e2e.gd — Integration tests for full parental consent lifecycle.
#
# Tests the client-side parental consent state machine:
#   - An under-13 account with no consent → should_suppress_chat() returns true.
#   - After FriendsClient.consent_status_received(true, false) → is_consented=true
#     → should_suppress_chat() returns false.
#   - After FriendsClient.consent_status_received(false, false) → is_consented=false
#     → should_suppress_chat() returns true again (re-restricted).
#
# Server-side SMTP and Go signaling tests live in signaling-server/hub_test.go.
# These tests verify the client-side state machine only.
#
# Flow reference (05-RESEARCH.md Pattern 3):
#   1. FriendsClient.request_parental_consent(email) → Go /consent/request → email sent.
#   2. Go sets consented_at, clears consent_token when parent confirms.
#   3. FriendsClient.check_consent_status() polls → consent_status_received(true, false).
#   4. is_consented becomes true → should_suppress_chat() returns false.
#   5. Parent revokes → revoked_at set → consent_status_received(false, false) →
#      is_consented=false → should_suppress_chat() returns true.
#
# Per Phase 4 Plan 11 decision: use .new() + add_child_autoqfree for objects that
# need a scene context. FriendsClient.new() requires _ready() to be safe — we instead
# directly set properties to inject state.
#
# Anchors:
#   05-01-PLAN.md Task 2 — integration test stubs
#   05-RESEARCH.md Pattern 3 — consent token lifecycle
#   05-CONTEXT.md Area 3 — under-13 restrictions before consent, unlock on confirm
#   DOCS §8.5 — Parental consent flow: restrict → confirm → unlock → revoke → restrict

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")
# Note: FriendsClientScript is intentionally not preloaded here.
# friends_client.gd depends on ProfanityFilter (class_name) which is not available
# in headless GUT due to the autoload script-ordering limitation. The E2E test
# simulates FriendsClient state using a lightweight mock node with dynamic properties.
# NetworkManagerScript depends on friends_client.gd indirectly; it loads OK because
# network_manager.gd does not directly preload friends_client.gd — it accesses FC
# via get_node_or_null("/root/FriendsClient") at runtime.
const NetworkManagerScript = preload("res://src/autoload/network_manager.gd")


## Drive the real FriendsClient autoload's consent properties for a test, returning the
## autoload node (or null if absent).
##
## The earlier approach added a mock Node *named* "FriendsClient" to /root, but
## FriendsClient is an autoload that already owns that node name — Godot renamed the mock
## ("FriendsClient2"), so NetworkManager.get_node_or_null("/root/FriendsClient") read the
## REAL autoload (is_under_13=false) and the under-13 assertions failed (and the "unlock"
## test only passed by coincidence). We set the real autoload's properties instead and
## restore them after each test. friends_client.gd declares is_under_13/is_consented as
## plain member vars, so `"is_under_13" in fc` (NetworkManager's check) holds.
func _friends_client() -> Node:
	return get_tree().root.get_node_or_null("FriendsClient")


func test_under_13_account_is_restricted_before_consent() -> void:
	# An under-13 account that has not yet received parental consent must suppress chat.
	# DOCS §8.5 — "until parental consent is recorded, the under-13 account is read-only".
	var fc: Node = _friends_client()
	if fc == null:
		pending("FriendsClient autoload not available in this environment")
		return
	var prev_u: bool = bool(fc.get("is_under_13"))
	var prev_c: bool = bool(fc.get("is_consented"))
	fc.set("is_under_13", true)
	fc.set("is_consented", false)

	var nm: Node = NetworkManagerScript.new()
	nm.name = "TestNM_restricted"
	add_child_autoqfree(nm)
	var suppressed: bool = nm.call("should_suppress_chat")

	# Restore BEFORE asserting so a failed assert never leaks state into later tests.
	fc.set("is_under_13", prev_u)
	fc.set("is_consented", prev_c)
	assert_true(suppressed,
		"should_suppress_chat() must return true for an under-13 account before parental consent (DOCS §8.5)")


func test_consent_confirmed_unlocks_chat() -> void:
	# After the parent confirms consent, is_consented=true → should_suppress_chat() = false.
	# DOCS §8.5 — "once approved, the account is fully active".
	var fc: Node = _friends_client()
	if fc == null:
		pending("FriendsClient autoload not available in this environment")
		return
	var prev_u: bool = bool(fc.get("is_under_13"))
	var prev_c: bool = bool(fc.get("is_consented"))
	fc.set("is_under_13", true)
	fc.set("is_consented", true)

	var nm: Node = NetworkManagerScript.new()
	nm.name = "TestNM_unlocked"
	add_child_autoqfree(nm)
	var suppressed: bool = nm.call("should_suppress_chat")

	fc.set("is_under_13", prev_u)
	fc.set("is_consented", prev_c)
	assert_false(suppressed,
		"should_suppress_chat() must return false after parental consent is confirmed (DOCS §8.5)")


func test_revoked_consent_re_restricts_chat() -> void:
	# After the parent revokes consent, is_consented returns to false → suppress again.
	# DOCS §8.5 — "a parent may revoke consent at any time, which suspends the account".
	var fc: Node = _friends_client()
	if fc == null:
		pending("FriendsClient autoload not available in this environment")
		return
	var prev_u: bool = bool(fc.get("is_under_13"))
	var prev_c: bool = bool(fc.get("is_consented"))
	fc.set("is_under_13", true)
	fc.set("is_consented", false)

	var nm: Node = NetworkManagerScript.new()
	nm.name = "TestNM_revoked"
	add_child_autoqfree(nm)
	var suppressed: bool = nm.call("should_suppress_chat")

	fc.set("is_under_13", prev_u)
	fc.set("is_consented", prev_c)
	assert_true(suppressed,
		"should_suppress_chat() must return true after consent is revoked (account re-restricted per DOCS §8.5)")
