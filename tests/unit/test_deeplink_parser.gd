# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_deeplink_parser.gd — Unit tests for DeepLinkHandler token parsing.
#
# Tests cover:
#   - "--invite=TOKEN" CLI arg yields the token string via _parse_args()
#   - "--uri=cubicraftia://invite/TOKEN" CLI arg yields the token string via _parse_args()
#   - token length < 20 chars is rejected (T-06-T1 mitigation)
#   - empty token is rejected
#   - malformed URI (wrong scheme) is rejected
#   - get_pending_token() / has_pending_token() / consume_pending_token() contract
#   - multiple args: first valid invite wins
#   - no relevant args -> get_pending_token() == ""
#
# Strategy: use _parse_args(args: PackedStringArray) directly to avoid depending on
# OS.get_command_line_args(). The handler instance is created fresh per test.
#
# Anchors:
#   06-09-PLAN.md Task 1 -- activate test_deeplink_parser stubs
#   06-CONTEXT.md Area 5 -- DeepLinkHandler token parsing

extends GutTest

const _HANDLER_SCRIPT: String = "res://src/autoload/deep_link_handler.gd"

# A valid 20-char token (exactly at the minimum length boundary).
const _VALID_TOKEN_20: String = "AAAABBBBCCCCDDDD0000"
# A valid 26-char token (typical base32 invite token).
const _VALID_TOKEN_26: String = "AAAABBBBCCCCDDDD00001111ZZ"

var _handler: Node


func before_each() -> void:
	_handler = load(_HANDLER_SCRIPT).new()
	add_child_autoqfree(_handler)


# ---- test_parse_cubicraftia_uri_invite_token ----------------------------------

func test_parse_cubicraftia_uri_invite_token() -> void:
	var args: PackedStringArray = PackedStringArray(["--uri=cubicraftia://invite/" + _VALID_TOKEN_26])
	var token: String = _handler._parse_args(args)
	assert_eq(token, _VALID_TOKEN_26, "_parse_args must return the token from a --uri= arg")


# ---- test_parse_invite_cli_arg -----------------------------------------------

func test_parse_invite_cli_arg() -> void:
	var args: PackedStringArray = PackedStringArray(["--invite=" + _VALID_TOKEN_20])
	var token: String = _handler._parse_args(args)
	assert_eq(token, _VALID_TOKEN_20, "_parse_args must return the token from a --invite= arg")


# ---- test_invalid_token_format_rejected --------------------------------------

func test_invalid_token_format_rejected() -> void:
	var args: PackedStringArray = PackedStringArray(["--invite=SHORT"])
	var result: String = _handler._parse_args(args)
	assert_eq(result, "", "Token shorter than 20 chars must return ''")


# ---- test_empty_token_rejected -----------------------------------------------

func test_empty_token_rejected() -> void:
	var args: PackedStringArray = PackedStringArray(["--invite="])
	var result: String = _handler._parse_args(args)
	assert_eq(result, "", "'--invite=' with empty token must return ''")


# ---- test_malformed_uri_rejected ---------------------------------------------

func test_malformed_uri_rejected() -> void:
	var args: PackedStringArray = PackedStringArray(["--uri=https://example.com/invite/" + _VALID_TOKEN_20])
	var result: String = _handler._parse_args(args)
	assert_eq(result, "", "Wrong-scheme URI must return ''")


# ---- test_consume_pending_token_clears ---------------------------------------

func test_consume_pending_token_clears() -> void:
	_handler._pending_token = _VALID_TOKEN_20
	var first: String = _handler.consume_pending_token()
	assert_eq(first, _VALID_TOKEN_20, "First consume must return the token")
	var second: String = _handler.get_pending_token()
	assert_eq(second, "", "get_pending_token must return '' after consume")


# ---- test_has_pending_token --------------------------------------------------

func test_has_pending_token() -> void:
	assert_false(_handler.has_pending_token(), "has_pending_token must be false on fresh instance")
	_handler._pending_token = _VALID_TOKEN_20
	assert_true(_handler.has_pending_token(), "has_pending_token must be true when token is set")


# ---- test_no_args_returns_empty_token ----------------------------------------

func test_no_args_returns_empty_token() -> void:
	var args: PackedStringArray = PackedStringArray([])
	var result: String = _handler._parse_args(args)
	assert_eq(result, "", "No invite args must return ''")


# ---- test_non_invite_arg_ignored ---------------------------------------------

func test_non_invite_arg_ignored() -> void:
	var args: PackedStringArray = PackedStringArray(["--other=value", "--flag", "--mode=survival"])
	var result: String = _handler._parse_args(args)
	assert_eq(result, "", "Non-invite args must return ''")


# ---- test_multiple_args_first_valid_wins -------------------------------------

func test_multiple_args_first_valid_wins() -> void:
	var token_a: String = "AAAABBBBCCCCDDDD0000"
	var token_b: String = "BBBBCCCCDDDDEEEE1111"
	var args: PackedStringArray = PackedStringArray([
		"--invite=" + token_a,
		"--invite=" + token_b,
	])
	var result: String = _handler._parse_args(args)
	assert_eq(result, token_a, "First valid token must be returned when multiple are present")
