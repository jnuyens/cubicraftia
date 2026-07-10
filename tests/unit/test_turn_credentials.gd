# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_turn_credentials.gd: Unit tests for NetworkManager applying the ephemeral
# TURN credentials the signaling server issues on register (coturn use-auth-secret).
#
# Regression guard: before this flow was wired, the server never sent creds and the
# client used empty static _turn_user/_turn_credential, so TURN relay fallback
# (symmetric-NAT/CGNAT peers) always failed. Server side is covered by
# TestHandleRegisterIssuesTURNCredentials in signaling-server.
#
# Off-tree GUT pattern mirrors tests/unit/test_connection_problem_reasons.gd.

extends GutTest

const NetworkManagerScript := preload("res://src/autoload/network_manager.gd")

var _nm: Node = null

func before_each() -> void:
	_nm = NetworkManagerScript.new()

func after_each() -> void:
	if is_instance_valid(_nm):
		_nm.free()

func test_turn_credentials_message_sets_user_and_credential() -> void:
	assert_eq(_nm._turn_user, "", "precondition: empty before message")
	assert_eq(_nm._turn_credential, "", "precondition: empty before message")
	_nm._on_signaling_message({
		"type": "turn_credentials",
		"payload": {"username": "3600:uid-x", "credential": "abc123==", "ttl": 3600},
	})
	assert_eq(_nm._turn_user, "3600:uid-x", "applies server-issued TURN username")
	assert_eq(_nm._turn_credential, "abc123==", "applies server-issued TURN credential")

func test_empty_turn_credentials_do_not_overwrite() -> void:
	_nm._turn_user = "existing-user"
	_nm._turn_credential = "existing-cred"
	_nm._on_signaling_message({
		"type": "turn_credentials",
		"payload": {"username": "", "credential": ""},
	})
	assert_eq(_nm._turn_user, "existing-user", "empty username must not clobber a valid credential")
	assert_eq(_nm._turn_credential, "existing-cred", "empty credential must not clobber a valid credential")
