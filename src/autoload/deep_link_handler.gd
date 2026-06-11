# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# deep_link_handler.gd — DeepLinkHandler autoload
#
# Parses cubicraftia:// deep-link URIs and --invite= CLI arguments so the
# title_scene can start the invite-join flow without polling OS.get_cmdline_args()
# itself.
#
# Platform behaviour (Godot 4 + cubicraftia:// custom URL scheme):
#   - Desktop (macOS/Win/Linux): OS passes --uri=cubicraftia://invite/TOKEN
#     or --invite=TOKEN as a CLI argument when the app is launched from a link.
#   - iOS / Android: the OS relaunches the app with the URL as a --uri= CLI arg
#     (Godot 4.6 routes the URL to get_command_line_args() on both platforms).
#
# Security:
#   - T-06-T1 mitigation: client-side minimum token length of 20 chars rejects
#     trivially malformed tokens before any network call is made.
#   - Server-side single-use validation is enforced by FriendsClient.redeem_invite()
#     via the Go signaling server and Supabase RLS — this handler is NOT authoritative.
#
# _handled guard ensures invite_token_received fires at most once per launch even
# if both --invite= and --uri= args are present.
#
# Usage (from title_scene._ready()):
#   DeepLinkHandler.invite_token_received.connect(_on_invite_token_received)
#   if DeepLinkHandler.has_pending_token():
#       _on_invite_token_received(DeepLinkHandler.consume_pending_token())
#
# Registered as autoload "DeepLinkHandler" in project.godot after FriendsClient.

extends Node

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted once when a valid invite token is found in the launch arguments.
## Listeners should call consume_pending_token() to clear the stored token.
signal invite_token_received(token: String)

# ─── Constants ────────────────────────────────────────────────────────────────

## Minimum token length for client-side sanity check (T-06-T1 mitigation).
## Does NOT replace server-side validation in FriendsClient.redeem_invite().
const MIN_TOKEN_LENGTH: int = 20

## CLI arg prefix for bare invite tokens (desktop deep-link via --invite=TOKEN).
const _PREFIX_INVITE: String = "--invite="

## CLI arg prefix for full URI deep-links (mobile + macOS handler passes full URL).
const _PREFIX_URI: String = "--uri=cubicraftia://invite/"

# ─── State ────────────────────────────────────────────────────────────────────

## Token extracted from CLI args, or "" if no valid token was found at launch.
var _pending_token: String = ""

## Guard: prevents re-emission if both --invite= and --uri= args are present.
var _handled: bool = false


# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# NOTE: Godot 4.x renamed OS.get_command_line_args() to OS.get_cmdline_args().
	# The old name causes a parse error in Godot 4.6; use get_cmdline_args() here.
	var cli_args: PackedStringArray = OS.get_cmdline_args()
	var token: String = _parse_args(cli_args)
	if token != "":
		_pending_token = token
		_handled = true
		invite_token_received.emit(token)


# ─── Public API ───────────────────────────────────────────────────────────────

## Returns the pending invite token, or "" if none was found at launch.
## Callers should prefer consume_pending_token() to avoid stale reads.
func get_pending_token() -> String:
	return _pending_token


## Returns true if a valid invite token is waiting to be consumed.
func has_pending_token() -> bool:
	return _pending_token != ""


## Returns the pending invite token and clears it in one atomic step.
## title_scene should call this after connecting to invite_token_received
## to handle the race where _ready() fires before the signal connection.
##
## @return  The invite token string, or "" if nothing is pending.
func consume_pending_token() -> String:
	var token: String = _pending_token
	_pending_token = ""
	return token


# ─── Private helpers ──────────────────────────────────────────────────────────

## Parse an array of command-line arguments and return the first valid invite token found.
## Returns "" if no valid token is found or all tokens fail the minimum-length check.
## This is the testable core of _ready() — call this directly from unit tests
## instead of relying on OS.get_cmdline_args().
##
## @param args  Array of CLI argument strings to inspect.
## @return      The extracted token string, or "" if none found.
func _parse_args(args: PackedStringArray) -> String:
	for arg: String in args:
		var candidate: String = ""
		if arg.begins_with(_PREFIX_URI):
			candidate = arg.substr(_PREFIX_URI.length())
		elif arg.begins_with(_PREFIX_INVITE):
			candidate = arg.substr(_PREFIX_INVITE.length())
		if candidate.length() >= MIN_TOKEN_LENGTH:
			return candidate
		elif candidate.length() > 0:
			push_warning("DeepLinkHandler: ignoring token with length %d (< %d): T-06-T1 client check." % [
				candidate.length(), MIN_TOKEN_LENGTH])
	return ""


## Validate and accept a candidate token.
## Sets _pending_token, marks _handled, and emits invite_token_received.
## No-op if the token fails the minimum-length sanity check or _handled is set.
## @deprecated  Use _parse_args() + direct assignment for new code. Kept for compatibility.
func _try_accept(token: String) -> void:
	if _handled:
		return
	if token.length() < MIN_TOKEN_LENGTH:
		push_warning("DeepLinkHandler: ignoring token with length %d (< %d): T-06-T1 client check." % [
			token.length(), MIN_TOKEN_LENGTH])
		return
	_pending_token = token
	_handled = true
	invite_token_received.emit(token)
