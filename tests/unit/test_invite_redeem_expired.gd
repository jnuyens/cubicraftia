# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_invite_redeem_expired.gd: unit tests for RELY-04 (D-05), a zero-row
# redeem_invite PATCH result (expired, already-redeemed, or nonexistent token)
# must emit invite_redeem_failed("expired") and must NEVER emit
# friendship_created with an empty host_uid.
#
# Anchors:
#   13-CONTEXT.md D-05 (silent stale/invalid invite-redeem bug)
#   13-03-PLAN.md Task 1 (FriendsClient._on_invite_completed() fix)
#   tests/unit/test_invite_token.gd (off-tree FriendsClientScript.new() pattern)

extends GutTest

const FriendsClientScript = preload("res://src/autoload/friends_client.gd")

# Do NOT add FriendsClient to the scene tree: _ready() creates HTTPRequest nodes
# and a Timer that require a live scene, which would leak and interfere with later tests.

var _fc: Node = null


func before_each() -> void:
	_fc = FriendsClientScript.new()


func after_each() -> void:
	if is_instance_valid(_fc):
		_fc.free()
	_fc = null


## test_zero_row_redeem_emits_failure: an empty-array PATCH body (stale/invalid/
## nonexistent token) must emit invite_redeem_failed("expired") and must NOT
## emit friendship_created.
func test_zero_row_redeem_emits_failure() -> void:
	_fc._invite_pending_action = "redeem_invite"
	watch_signals(_fc)

	_fc._on_invite_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		"[]".to_utf8_buffer())

	assert_signal_emitted_with_parameters(_fc, "invite_redeem_failed", ["expired"])
	assert_signal_not_emitted(_fc, "friendship_created")


## test_nonempty_row_redeem_still_succeeds: regression guard for the unchanged
## success path (a non-empty body with a valid host_uid must still emit
## friendship_created and must NOT emit invite_redeem_failed).
func test_nonempty_row_redeem_still_succeeds() -> void:
	_fc._invite_pending_action = "redeem_invite"
	watch_signals(_fc)

	_fc._on_invite_completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(),
		'[{"host_uid":"uid-x"}]'.to_utf8_buffer())

	assert_signal_emitted_with_parameters(_fc, "friendship_created", ["uid-x"])
	assert_signal_not_emitted(_fc, "invite_redeem_failed")
