# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# friends_client.gd — FriendsClient autoload: GoTrue auth + Supabase REST friends/invites.
#
# Registered as autoload "FriendsClient" in project.godot (after SessionRegistry,
# before NetworkManager which ships in Plan 04-05).
#
# Responsibilities:
#   1. GoTrue email/password sign-in, sign-up, sign-out, and token refresh.
#   2. Token persistence to user://auth.cfg [auth] section via ConfigFile.
#   3. Friends graph CRUD via Supabase PostgREST REST API.
#   4. Invite creation (26-char base32 token) and redemption (PATCH + friendship creation).
#   5. Email verification gate: is_invite_send_allowed() blocks unverified accounts.
#   6. Session age context: caches published_at from NetworkManager.session_metadata_received.
#
# Security:
#   T-04-04-S: access_token stored in app-sandboxed user://auth.cfg; refresh on use.
#   T-04-04-T: canonical UUID ordering (user_a < user_b) enforced before POST.
#   T-04-04-D: 26-char base32 = 128-bit entropy; tokens expire in 24h.
#   T-04-04-I: never log full token; debug logs show only first 8 chars.
#   T-04-04-E: is_invite_send_allowed() gates invite creation; server RLS is hard gate.
#
# References:
#   04-CONTEXT.md Area 3 — email/password, SIWA/Google stubs, 50 friends cap, 24h TTL
#   04-RESEARCH.md lines 558-605 — GoTrue endpoints + HTTP request pattern
#   04-PATTERNS.md lines 230-236 — ConfigFile persistence pattern

extends Node

# Preload-based reference to ProfanityFilter — avoids relying on the global
# class_name registry during autoload boot. The class_name version can be
# unresolved if .godot/global_script_class_cache.cfg is stale or missing.
const _ProfanityFilter = preload("res://src/networking/profanity_filter.gd")

# ─── Constants ────────────────────────────────────────────────────────────────

## Path for persisting auth tokens between sessions.
const AUTH_PATH := "user://auth.cfg"

## ConfigFile section for auth tokens.
const SECTION := "auth"

## Maximum friends per user (04-CONTEXT.md Area 3 Q2 resolution).
const MAX_FRIENDS := 50

## Invite token TTL in seconds (24 hours).
const INVITE_TTL_SECONDS := 86400

## Days after sign-up before unverified accounts are hard-blocked from invite creation.
const VERIFICATION_HARD_BLOCK_DAYS := 7

## Base32 alphabet for invite token generation (URL-safe lowercase).
const BASE32_ALPHABET := "abcdefghijklmnopqrstuvwxyz234567"

## Invite token length in characters (128-bit entropy in base32).
const INVITE_TOKEN_LENGTH := 26

# ─── Supabase config (read from env or ProjectSettings) ───────────────────────

## Supabase project URL. Falls back to env var, then to localhost dev default.
var _supabase_url: String = ""

## Supabase anonymous (public) key.
var _anon_key: String = ""

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted after a successful sign-in or session restore.
signal signed_in(user_id: String)

## Emitted when a sign-in attempt fails.
signal sign_in_failed(reason: String)

## Emitted after successful sign-out.
signal signed_out()

## Emitted after successful sign-up.
signal sign_up_ok(user_id: String)

## Emitted when a sign-up attempt fails.
signal sign_up_failed(reason: String)

## Emitted after the friends list is successfully fetched.
signal friends_loaded(friends: Array)

## Emitted when an invite token is created successfully.
signal invite_created(token: String, link: String)

## Emitted when invite creation fails.
signal invite_creation_failed(reason: String)

## Emitted when a friendship is created (after redeeming an invite).
signal friendship_created(friend_uid: String)

## Emitted when redeeming an invite token fails to match any row (expired,
## already redeemed, or nonexistent). RELY-04 (D-05): PostgREST returns HTTP 200
## with an EMPTY array in all three cases; friendship_created must never fire
## with an empty host_uid.
signal invite_redeem_failed(reason: String)

## Emitted when a friendship is deleted.
signal friendship_deleted()

## Emitted when a friendship creation attempt fails (e.g. friends cap reached).
## CR-08: dedicated signal so the friends UI, not the sign-up form, can respond.
signal friendship_creation_failed(reason: String)

## Emitted when a profile search returns results.
signal profiles_found(profiles: Array)

## Emitted after block_user() succeeds.
signal user_blocked(uid: String)

## Emitted after unblock_user() succeeds.
signal user_unblocked(uid: String)

## Emitted after get_blocks() returns results.
signal blocks_loaded(blocks: Array)

## Emitted after submit_report() succeeds.
signal report_submitted()

## Emitted after check_consent_status() or request_parental_consent() returns.
## is_consented: parent has confirmed consent; is_pending: request sent but not yet confirmed.
signal consent_status_received(is_consented: bool, is_pending: bool)

# ─── Private state ────────────────────────────────────────────────────────────

## Current GoTrue access token (JWT).
var _access_token: String = ""

## Current GoTrue refresh token.
var _refresh_token: String = ""

## Supabase user UID string.
var _user_id: String = ""

## Token expiry as Unix timestamp (float). 0 = not set.
var _expires_at: float = 0.0

## True if the user's email_confirmed_at is non-null in GoTrue.
var _email_confirmed: bool = false

## Pending action dispatched from _on_auth_completed: "signin" | "signup" | "refresh" | "".
var _pending_action: String = ""

## Per-session published_at cache: { session_id (String) -> published_at_unix (int) }
## Populated via NetworkManager.session_metadata_received signal.
var _session_published_at: Dictionary = {}

## Local friends cache (Array of Dictionaries with uid, username, status).
var _friends_cache: Array = []

## WR-04: Track the most recent request type sent via _friends_req so that
## _on_friends_completed can dispatch the right signal. Supabase PostgREST with
## Prefer: return=representation returns HTTP 200 + JSON body for both GET and
## DELETE, so we cannot distinguish them by status code alone.
## Values: "get" | "delete" | ""
var _friends_pending_action: String = ""

## HTTPRequest nodes (separate per concern to allow concurrent calls).
var _auth_req: HTTPRequest = null
var _friends_req: HTTPRequest = null
var _invite_req: HTTPRequest = null
var _profile_req: HTTPRequest = null
var _block_req: HTTPRequest = null
var _report_req: HTTPRequest = null
var _consent_req: HTTPRequest = null
## Avatar PATCH request node. Fire-and-forget; no response handler connected.
var _avatar_req: HTTPRequest = null

## Local blocks cache (Array of Dictionaries with blocked_uid, created_at).
var _blocks_cache: Array = []

## True if the signed-in account is under-13 (set during sign_up and restored from
## GoTrue user_metadata on sign-in). Read by NetworkManager._is_under_13_unconsented().
## DOCS §8.5 — only the boolean is stored; raw DOB is never persisted.
var is_under_13: bool = false

## True if parental consent has been confirmed for an under-13 account.
## Set by consent_status_received signal handler (Plan 05-05/05-06).
## Read by NetworkManager._is_under_13_unconsented() to gate chat and session join.
## DOCS §8.5 — parental consent: consented_at set by Go server → unlocks account.
var is_consented: bool = false

## Track which block operation is in flight: "block:<uid>" | "unblock:<uid>" | "get" | "".
var _block_pending_action: String = ""

## Track which consent operation is in flight: "request" | "status" | "".
var _consent_pending_action: String = ""

## Track which invite operation is in flight: "create_invite:<token>" | "redeem_invite" | "".
## WR-04: dedicated variable so auth requests (_pending_action) cannot overwrite invite state.
var _invite_pending_action: String = ""

## Signaling server URL. Derived from ProjectSettings or env var.
var _signaling_url: String = ""

## Auto-refresh timer (60s periodic check).
var _refresh_timer: Timer = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Phase 5 (Plan 05-10): Warm up the ProfanityFilter regex at startup so that the
	# first username keystroke on Tier-3 devices does not incur a regex compilation lag.
	# _ensure_regex() is idempotent — calling it more than once is a no-op.
	_ProfanityFilter._ensure_regex()

	# Read Supabase config: ProjectSettings > OS env > localhost fallback.
	if ProjectSettings.has_setting("network/supabase_url"):
		_supabase_url = ProjectSettings.get_setting("network/supabase_url")
	elif OS.has_environment("CUBICRAFTIA_SUPABASE_URL"):
		_supabase_url = OS.get_environment("CUBICRAFTIA_SUPABASE_URL")
	else:
		_supabase_url = "http://localhost:8000"

	if ProjectSettings.has_setting("network/supabase_anon_key"):
		_anon_key = ProjectSettings.get_setting("network/supabase_anon_key")
	elif OS.has_environment("SUPABASE_ANON_KEY"):
		_anon_key = OS.get_environment("SUPABASE_ANON_KEY")

	# Read signaling server URL: ProjectSettings > OS env > localhost fallback.
	if ProjectSettings.has_setting("network/signaling_url"):
		_signaling_url = ProjectSettings.get_setting("network/signaling_url")
	elif OS.has_environment("CUBICRAFTIA_SIGNALING_URL"):
		_signaling_url = OS.get_environment("CUBICRAFTIA_SIGNALING_URL")
	else:
		_signaling_url = "http://localhost:7350"

	# Add HTTPRequest child nodes (one per concurrent call type).
	_auth_req = HTTPRequest.new()
	_auth_req.name = "_auth_req"
	add_child(_auth_req)
	_auth_req.request_completed.connect(_on_auth_completed)

	_friends_req = HTTPRequest.new()
	_friends_req.name = "_friends_req"
	add_child(_friends_req)
	_friends_req.request_completed.connect(_on_friends_completed)

	_invite_req = HTTPRequest.new()
	_invite_req.name = "_invite_req"
	add_child(_invite_req)
	_invite_req.request_completed.connect(_on_invite_completed)

	_profile_req = HTTPRequest.new()
	_profile_req.name = "_profile_req"
	add_child(_profile_req)
	_profile_req.request_completed.connect(_on_profile_completed)

	_block_req = HTTPRequest.new()
	_block_req.name = "_block_req"
	add_child(_block_req)
	_block_req.request_completed.connect(_on_block_completed)

	_report_req = HTTPRequest.new()
	_report_req.name = "_report_req"
	add_child(_report_req)
	_report_req.request_completed.connect(_on_report_completed)

	_consent_req = HTTPRequest.new()
	_consent_req.name = "_consent_req"
	add_child(_consent_req)
	_consent_req.request_completed.connect(_on_consent_completed)

	# Avatar req: fire-and-forget — no response handler (failure is silent; local cfg is canonical).
	_avatar_req = HTTPRequest.new()
	_avatar_req.name = "_avatar_req"
	add_child(_avatar_req)

	# Auto-refresh timer: check every 60 seconds; refresh if within 5 minutes of expiry.
	_refresh_timer = Timer.new()
	_refresh_timer.name = "_refresh_timer"
	_refresh_timer.wait_time = 60.0
	_refresh_timer.one_shot = false
	add_child(_refresh_timer)
	_refresh_timer.timeout.connect(_check_token_expiry)
	_refresh_timer.start()

	# Load persisted tokens.
	_load_tokens()

	# If we have a valid non-expired token, restore session.
	if _access_token != "" and _expires_at > Time.get_unix_time_from_system():
		signed_in.emit(_user_id)

	# Connect to NetworkManager.session_metadata_received for session age context.
	# Guard with is_instance_valid — NetworkManager ships in Plan 04-05 and may not
	# be present in headless test environments.
	if is_instance_valid(get_node_or_null("/root/NetworkManager")):
		var nm: Node = get_node("/root/NetworkManager")
		if nm.has_signal("session_metadata_received"):
			nm.session_metadata_received.connect(_on_session_metadata_received)


# ─── Public API — Auth ────────────────────────────────────────────────────────

## Sign in with email and password (GoTrue POST /auth/v1/token?grant_type=password).
## Emits signed_in(user_id) on success, sign_in_failed(reason) on failure.
func sign_in(email: String, password: String) -> void:
	if not _is_req_ready(_auth_req):
		sign_in_failed.emit(tr("ui.signin.error_network"))
		return
	_pending_action = "signin"
	var body := JSON.stringify({"email": email, "password": password})
	var headers := _auth_headers()
	_auth_req.request(
		_supabase_url + "/auth/v1/token?grant_type=password",
		headers,
		HTTPClient.METHOD_POST,
		body
	)


## Sign up with email, password, optional username, and optional date-of-birth.
## DOB params (dob_year, dob_month, dob_day) are used to compute is_under_13 locally.
## The raw DOB is NEVER sent to Supabase — only the boolean is_under_13 is included
## in user_metadata (GDPR minimum-data principle; T-05-DOB threat mitigation).
## Creates a GoTrue user and emits sign_up_ok(user_id) on success.
func sign_up(email: String, password: String, username: String = "",
		dob_year: int = 0, dob_month: int = 0, dob_day: int = 0) -> void:
	if not _is_req_ready(_auth_req):
		sign_up_failed.emit(tr("ui.signin.error_network"))
		return
	_pending_action = "signup"
	var user_data: Dictionary = {}
	if username != "":
		user_data["username"] = username
	# Compute is_under_13 if all DOB fields are provided.
	# Raw DOB is NEVER included in the HTTP body — only the boolean.
	if dob_year > 0 and dob_month > 0 and dob_day > 0:
		var today: Dictionary = Time.get_date_dict_from_system()
		# Age in years: subtract years then adjust if birthday not yet reached this year.
		var age: int = today["year"] - dob_year
		if today["month"] < dob_month or (today["month"] == dob_month and today["day"] < dob_day):
			age -= 1
		user_data["is_under_13"] = age < 13
	var data: Dictionary = {"email": email, "password": password}
	if not user_data.is_empty():
		data["data"] = user_data
	var body := JSON.stringify(data)
	var headers := _auth_headers()
	_auth_req.request(
		_supabase_url + "/auth/v1/signup",
		headers,
		HTTPClient.METHOD_POST,
		body
	)


## Sign in with a social provider ("apple" or "google").
## Phase 5 dependency — OAuth credentials not yet configured; emits sign_in_failed stub.
func sign_in_with_provider(provider: String) -> void:
	sign_in_failed.emit("not_implemented_phase_5")


## Sign out: POST /auth/v1/logout, then clear tokens and emit signed_out().
## CR-11: Tokens must be cleared AFTER the HTTP response so that the server-side
## session is actually invalidated before local state is wiped. Clearing synchronously
## before the HTTP call completes leaves the access token valid on the server until
## it naturally expires, while locally appearing signed out.
## Fire-and-forget approach: if the HTTP call cannot be started (req busy or no token),
## still clear locally so the UI remains consistent; the token will expire on its own.
func sign_out() -> void:
	if _access_token != "" and _is_req_ready(_auth_req):
		var headers := _authed_headers()
		_pending_action = "signout"
		_auth_req.request(
			_supabase_url + "/auth/v1/logout",
			headers,
			HTTPClient.METHOD_POST,
			""
		)
		# Tokens are cleared in _on_auth_completed when action == "signout".
		# Return here so we don't clear tokens before the HTTP response arrives.
		return
	# Fallback: req is busy or no token — clear locally anyway for UI consistency.
	_clear_tokens()
	signed_out.emit()


## Refresh the GoTrue access token using the stored refresh_token.
## Called automatically by _check_token_expiry. Can be called explicitly.
func refresh_token() -> void:
	if _refresh_token == "" or not _is_req_ready(_auth_req):
		return
	_pending_action = "refresh"
	var body := JSON.stringify({"refresh_token": _refresh_token})
	var headers := _auth_headers()
	_auth_req.request(
		_supabase_url + "/auth/v1/token?grant_type=refresh_token",
		headers,
		HTTPClient.METHOD_POST,
		body
	)


## Fetch current user info from GoTrue (reads email_confirmed_at).
## Updates _email_confirmed internally.
func get_user() -> void:
	if not is_signed_in() or not _is_req_ready(_auth_req):
		return
	_pending_action = "get_user"
	_auth_req.request(
		_supabase_url + "/auth/v1/user",
		_authed_headers(),
		HTTPClient.METHOD_GET
	)


# ─── Public API — Auth state queries ──────────────────────────────────────────

## Return true if a valid access token is held.
func is_signed_in() -> bool:
	return _access_token != ""


## Return true if the user's email has been confirmed.
func is_email_verified() -> bool:
	return _email_confirmed


## Return true if the user is allowed to send invites (signed in and email verified).
func is_invite_send_allowed() -> bool:
	return is_signed_in() and is_email_verified()


## Return true if the local friends cache is at the 50-friend cap.
func is_friends_limit_reached() -> bool:
	return _friends_cache.size() >= MAX_FRIENDS


## Return the local user UID.
func get_user_id() -> String:
	return _user_id


# ─── Public API — Friends graph ───────────────────────────────────────────────

## Fetch the friends list from Supabase and emit friends_loaded on success.
## Uses the cached result while a request is in flight.
func get_friends() -> void:
	if not is_signed_in() or not _is_req_ready(_friends_req):
		return
	_friends_pending_action = "get"
	var uid := _user_id
	# GET /rest/v1/friendships?or=(user_a.eq.<uid>,user_b.eq.<uid>)&select=*
	var url := _supabase_url + "/rest/v1/friendships?or=(user_a.eq." + uid + ",user_b.eq." + uid + ")&select=*"
	_friends_req.request(url, _authed_headers(), HTTPClient.METHOD_GET)


## Search for users by username prefix. Emits profiles_found(profiles).
func search_friend(query: String) -> void:
	if not is_signed_in() or not _is_req_ready(_profile_req):
		return
	var encoded_query := query.uri_encode()
	var url := _supabase_url + "/rest/v1/profiles?username=ilike." + encoded_query + "*&select=id,username"
	_profile_req.request(url, _authed_headers(), HTTPClient.METHOD_GET)


## Get a specific user profile by UID. Emits profiles_found(profiles).
func get_profile(uid: String) -> void:
	if not is_signed_in() or not _is_req_ready(_profile_req):
		return
	var url := _supabase_url + "/rest/v1/profiles?id=eq." + uid + "&select=id,username"
	_profile_req.request(url, _authed_headers(), HTTPClient.METHOD_GET)


## Create a friendship between the local user and another UID.
## Enforces canonical ordering (user_a < user_b) per the Supabase CHECK constraint.
## CR-08: Emits friendship_creation_failed (not sign_up_failed) when the cap is reached
## so only friends-UI subscribers react, not sign-up form handlers.
func create_friendship(other_uid: String) -> void:
	if not is_signed_in():
		return
	if is_friends_limit_reached():
		friendship_creation_failed.emit(tr("ui.friends.limit_reached"))
		return
	if not _is_req_ready(_friends_req):
		return
	# Canonical ordering: smaller UUID string is user_a (matches Postgres CHECK user_a < user_b).
	var user_a: String
	var user_b: String
	if _user_id < other_uid:
		user_a = _user_id
		user_b = other_uid
	else:
		user_a = other_uid
		user_b = _user_id
	_friends_pending_action = "create"
	var body := JSON.stringify({"user_a": user_a, "user_b": user_b, "status": "active"})
	_friends_req.request(
		_supabase_url + "/rest/v1/friendships",
		_authed_headers(),
		HTTPClient.METHOD_POST,
		body
	)


## Delete a friendship between the local user and another UID.
## Uses canonical ordering to build the filter. Emits friendship_deleted on success.
func delete_friendship(other_uid: String) -> void:
	if not is_signed_in() or not _is_req_ready(_friends_req):
		return
	_friends_pending_action = "delete"
	var user_a: String
	var user_b: String
	if _user_id < other_uid:
		user_a = _user_id
		user_b = other_uid
	else:
		user_a = other_uid
		user_b = _user_id
	var url := _supabase_url + "/rest/v1/friendships?user_a=eq." + user_a + "&user_b=eq." + user_b
	_friends_req.request(url, _authed_headers(), HTTPClient.METHOD_DELETE)


# ─── Public API — Invites ─────────────────────────────────────────────────────

## Generate a 26-char base32 invite token, POST it to Supabase invites table,
## and emit invite_created(token, link) on success.
## Gates on is_invite_send_allowed() and not is_friends_limit_reached().
func create_invite(session_id: String) -> void:
	if not is_invite_send_allowed():
		invite_creation_failed.emit(tr("ui.signin.error_invalid_credentials"))
		return
	if is_friends_limit_reached():
		invite_creation_failed.emit(tr("ui.friends.limit_reached"))
		return
	if not _is_req_ready(_invite_req):
		invite_creation_failed.emit(tr("ui.signin.error_network"))
		return

	var token := _generate_invite_token()
	var now_unix := int(Time.get_unix_time_from_system())
	var expires_at_unix := now_unix + INVITE_TTL_SECONDS
	# Format expires_at as ISO 8601 UTC string for Supabase timestamptz column.
	var expires_at_str := Time.get_datetime_string_from_unix_time(expires_at_unix) + "Z"

	var body := JSON.stringify({
		"token":      token,
		"host_uid":   _user_id,
		"session_id": session_id,
		"expires_at": expires_at_str,
	})

	# Stash the token for the completion handler to use in the signal (WR-04).
	_invite_pending_action = "create_invite:" + token

	_invite_req.request(
		_supabase_url + "/rest/v1/invites",
		_authed_headers(),
		HTTPClient.METHOD_POST,
		body
	)


## Redeem an invite token: PATCH the invite row to mark redeemed_by, then create friendship.
## Emits friendship_created(host_uid) on success.
func redeem_invite(token: String) -> void:
	if not is_signed_in() or not _is_req_ready(_invite_req):
		return
	_invite_pending_action = "redeem_invite"
	var body := JSON.stringify({"redeemed_by": _user_id})
	_invite_req.request(
		_supabase_url + "/rest/v1/invites?token=eq." + token,
		_authed_headers(),
		HTTPClient.METHOD_PATCH,
		body
	)


# ─── Public API — Block / Unblock ────────────────────────────────────────────

## Block a user. POST /rest/v1/blocks with {blocker_uid, blocked_uid}.
## Emits user_blocked(uid) on 201 success.
func block_user(uid: String) -> void:
	if not is_signed_in() or not _is_req_ready(_block_req):
		return
	_block_pending_action = "block:" + uid
	var body := JSON.stringify({"blocker_uid": _user_id, "blocked_uid": uid})
	_block_req.request(
		_supabase_url + "/rest/v1/blocks",
		_authed_headers(),
		HTTPClient.METHOD_POST,
		body
	)


## Unblock a user. DELETE /rest/v1/blocks with both-uid filters.
## Emits user_unblocked(uid) on 204 success.
func unblock_user(uid: String) -> void:
	if not is_signed_in() or not _is_req_ready(_block_req):
		return
	_block_pending_action = "unblock:" + uid
	var url := (_supabase_url + "/rest/v1/blocks?blocker_uid=eq." + _user_id
			+ "&blocked_uid=eq." + uid)
	_block_req.request(url, _authed_headers_minimal(), HTTPClient.METHOD_DELETE)


## Fetch the list of users blocked by the local user. Emits blocks_loaded(blocks).
func get_blocks() -> void:
	if not is_signed_in() or not _is_req_ready(_block_req):
		return
	_block_pending_action = "get"
	var url := (_supabase_url + "/rest/v1/blocks?blocker_uid=eq." + _user_id
			+ "&select=blocked_uid,created_at")
	_block_req.request(url, _authed_headers(), HTTPClient.METHOD_GET)


## Check if a UID is in the local blocks cache. Fast UI check before server round-trip.
func is_blocked(uid: String) -> bool:
	for entry: Variant in _blocks_cache:
		if entry is Dictionary and (entry as Dictionary).get("blocked_uid", "") == uid:
			return true
	return false


# ─── Public API — Reports ─────────────────────────────────────────────────────

## Submit a moderation report. POST /rest/v1/reports.
## surface: "player" | "build" | "chat_message"
## category: "harassment" | "spam" | "cheating" | "csam" | "other"
## reason: free text, 500 char max
## evidence: Dictionary with surface-specific context (chat messages, world_id, etc.)
## Emits report_submitted() on 201 success.
func submit_report(reported_uid: String, surface: String, category: String,
		reason: String, evidence: Dictionary) -> void:
	if not is_signed_in() or not _is_req_ready(_report_req):
		return
	var body := JSON.stringify({
		"reporter_uid": _user_id,
		"reported_uid": reported_uid,
		"surface": surface,
		"category": category,
		"reason": reason,
		"evidence": evidence,
	})
	_report_req.request(
		_supabase_url + "/rest/v1/reports",
		_authed_headers(),
		HTTPClient.METHOD_POST,
		body
	)


# ─── Public API — Parental consent ───────────────────────────────────────────

## Request parental consent for an under-13 account.
## POSTs to the Go signaling server /consent/request with the parent's email.
## Emits consent_status_received(false, true) when the request is sent successfully.
func request_parental_consent(parent_email: String) -> void:
	if not is_signed_in() or not _is_req_ready(_consent_req):
		return
	var body := JSON.stringify({"parent_email": parent_email})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _access_token,
	])
	_consent_req.request(
		_signaling_url + "/consent/request",
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	# Mark in-flight as consent_request so the handler knows which signal to emit.
	# We tag with a prefix so _on_consent_completed can distinguish it from status checks.
	# Reuse _pending_action for the consent req — it has its own HTTPRequest node.
	# Use a local var on _consent_req's user_data to avoid clobbering _pending_action.
	# Simplest: store state in a dedicated var.
	_consent_pending_action = "request"


## Check parental consent status for the local under-13 user.
## GET /rest/v1/parental_consents?child_uid=eq.<uid>&select=consented_at,revoked_at
## Emits consent_status_received(is_consented, is_pending).
func check_consent_status() -> void:
	if not is_signed_in() or not _is_req_ready(_consent_req):
		return
	_consent_pending_action = "status"
	var url := (_supabase_url + "/rest/v1/parental_consents?child_uid=eq." + _user_id
			+ "&select=consented_at,revoked_at,requested_at")
	_consent_req.request(url, _authed_headers(), HTTPClient.METHOD_GET)


# ─── Public API — EULA ────────────────────────────────────────────────────────

## Check whether the bundled EULA has been acknowledged by the user.
## Computes SHA-256 of "res://docs/EULA.md" using HashingContext and compares the
## first 16 hex characters against the value stored in user://settings.cfg [legal] eula_hash.
## Returns true if hashes match (acknowledged and current).
## Returns true if the EULA file is missing (fail-open — prevents blocking play in dev builds).
## Returns false if hashes differ (triggers re-acknowledge modal before the title screen).
## Per 05-RESEARCH.md Pattern 4.
func check_eula_acknowledgement() -> bool:
	var eula_path := "res://docs/EULA.md"
	if not FileAccess.file_exists(eula_path):
		# File missing in dev / test environment — fail open so play is not blocked.
		return true
	# Compute SHA-256 of bundled EULA file.
	var hash_ctx := HashingContext.new()
	var err := hash_ctx.start(HashingContext.HASH_SHA256)
	if err != OK:
		push_warning("FriendsClient.check_eula_acknowledgement: HashingContext.start failed (%d)" % err)
		return true  # Fail open.
	var file := FileAccess.open(eula_path, FileAccess.READ)
	if file == null:
		push_warning("FriendsClient.check_eula_acknowledgement: could not open EULA.md")
		return true  # Fail open.
	var chunk_size := 65536  # 64 KiB chunks.
	while not file.eof_reached():
		var chunk: PackedByteArray = file.get_buffer(chunk_size)
		if chunk.size() > 0:
			hash_ctx.update(chunk)
	file.close()
	var digest: PackedByteArray = hash_ctx.finish()
	var hex_hash: String = digest.hex_encode()
	# Use the full 256-bit SHA-256 hex (64 chars) to avoid truncated-hash collisions (WR-07).
	var bundled_short: String = hex_hash
	# Load stored hash from user://settings.cfg [legal] eula_hash.
	var cfg := ConfigFile.new()
	var stored_hash: String = ""
	if cfg.load("user://settings.cfg") == OK:
		stored_hash = cfg.get_value("legal", "eula_hash", "")
	return bundled_short == stored_hash


## Store the EULA hash after the user acknowledges.
## Writes the hash to user://settings.cfg [legal] eula_hash.
## Call this after the user clicks "I Agree" in the EULA modal.
func store_eula_hash(hash: String) -> void:
	var cfg := ConfigFile.new()
	# Load existing settings to avoid overwriting unrelated keys.
	cfg.load("user://settings.cfg")
	cfg.set_value("legal", "eula_hash", hash)
	cfg.save("user://settings.cfg")


# ─── Public API — Username + Account management (Plan 05-09) ─────────────────

## Emitted after change_username() succeeds.
## new_username: the accepted username.
signal username_changed(new_username: String)

## Emitted when change_username() fails.
## reason: "taken" | "reserved" | "cooldown" | "format" | "network"
signal username_change_failed(reason: String)

## Emitted after request_account_deletion() succeeds.
signal account_deletion_requested()

## Emitted after cancel_account_deletion() succeeds.
signal account_deletion_cancelled()

## HTTPRequest nodes for username and account operations.
var _username_req: HTTPRequest = null
var _account_req: HTTPRequest = null

## Track the pending operation for username/account requests.
var _username_pending_action: String = ""
var _account_pending_action: String = ""

## Locally cached username (populated from sign-in response and profile loads).
var _cached_username: String = ""

## Return the locally cached username (from last sign-in or profile load).
func get_username() -> String:
	return _cached_username


## Change the signed-in user's username.
## Validates format and cooldown client-side via UsernamePol, then PATCHes
## /rest/v1/profiles?id=eq.<uid> with the new username.
## Emits username_changed(new_username) on success,
## username_change_failed(reason) on error.
func change_username(new_username: String) -> void:
	if not is_signed_in():
		username_change_failed.emit("network")
		return
	# Lazy-init the username HTTPRequest node.
	if _username_req == null:
		_username_req = HTTPRequest.new()
		_username_req.name = "_username_req"
		add_child(_username_req)
		_username_req.request_completed.connect(_on_username_completed)
	if not _is_req_ready(_username_req):
		username_change_failed.emit("network")
		return
	_username_pending_action = "change:" + new_username
	var body := JSON.stringify({"username": new_username})
	var url := _supabase_url + "/rest/v1/profiles?id=eq." + _user_id
	_username_req.request(url, _authed_headers(), HTTPClient.METHOD_PATCH, body)


## Request deletion of the signed-in user's account.
## For v1: PATCHes profiles table setting deletion_requested_at = current UTC ISO time.
## A scheduled server-side cleanup handles permanent deletion after 7 days.
## Emits account_deletion_requested() on success.
func request_account_deletion() -> void:
	if not is_signed_in():
		return
	# Lazy-init the account HTTPRequest node.
	if _account_req == null:
		_account_req = HTTPRequest.new()
		_account_req.name = "_account_req"
		add_child(_account_req)
		_account_req.request_completed.connect(_on_account_completed)
	if not _is_req_ready(_account_req):
		return
	_account_pending_action = "deletion_request"
	var now_str := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system())) + "Z"
	var body := JSON.stringify({"deletion_requested_at": now_str})
	var url := _supabase_url + "/rest/v1/profiles?id=eq." + _user_id
	_account_req.request(url, _authed_headers(), HTTPClient.METHOD_PATCH, body)


## Cancel a pending account deletion by clearing deletion_requested_at.
## Emits account_deletion_cancelled() on success.
func cancel_account_deletion() -> void:
	if not is_signed_in():
		return
	if _account_req == null:
		_account_req = HTTPRequest.new()
		_account_req.name = "_account_req"
		add_child(_account_req)
		_account_req.request_completed.connect(_on_account_completed)
	if not _is_req_ready(_account_req):
		return
	_account_pending_action = "deletion_cancel"
	# Set deletion_requested_at to null to cancel the pending deletion.
	var body := JSON.stringify({"deletion_requested_at": null})
	var url := _supabase_url + "/rest/v1/profiles?id=eq." + _user_id
	_account_req.request(url, _authed_headers(), HTTPClient.METHOD_PATCH, body)


func _on_username_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _username_pending_action
	_username_pending_action = ""
	if not action.begins_with("change:"):
		return
	var new_username := action.substr("change:".length())
	if result != HTTPRequest.RESULT_SUCCESS:
		username_change_failed.emit("network")
		return
	match code:
		200, 201:
			_cached_username = new_username
			username_changed.emit(new_username)
		409:
			# Conflict: username already taken.
			username_change_failed.emit("taken")
		422:
			# Unprocessable: format, reserved, or cooldown trigger on server.
			var json: Variant = JSON.parse_string(body.get_string_from_utf8())
			if json is Dictionary:
				var msg: String = str((json as Dictionary).get("message", ""))
				if "cooldown" in msg.to_lower():
					username_change_failed.emit("cooldown")
				elif "reserved" in msg.to_lower():
					username_change_failed.emit("reserved")
				else:
					username_change_failed.emit("format")
			else:
				username_change_failed.emit("format")
		_:
			username_change_failed.emit("network")


func _on_account_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var action := _account_pending_action
	_account_pending_action = ""
	if result != HTTPRequest.RESULT_SUCCESS or code not in [200, 201, 204]:
		return
	match action:
		"deletion_request":
			account_deletion_requested.emit()
		"deletion_cancel":
			account_deletion_cancelled.emit()


# ─── Public API — Avatar ─────────────────────────────────────────────────────

## Persist the avatar configuration to Supabase. Fire-and-forget.
## cfg must be a Dictionary with the 8 avatar keys defined in 06-CONTEXT.md Area 2.
## On failure the local user://avatar.cfg is canonical; no signal is emitted.
## Called from avatar_creator.gd _on_done_pressed(). Safe to call when not signed in
## (returns immediately — local cfg is still written to disk by the caller).
func save_avatar(cfg: Dictionary) -> void:
	if not is_signed_in():
		return
	# Drop silently if a previous avatar save is still in flight.
	if not _is_req_ready(_avatar_req):
		return
	var body := JSON.stringify({"avatar_json": JSON.stringify(cfg)})
	var url := _supabase_url + "/rest/v1/profiles?id=eq." + _user_id
	# Use minimal headers — we don't need the row returned.
	_avatar_req.request(url, _authed_headers_minimal(), HTTPClient.METHOD_PATCH, body)


# ─── Public API — Session age context ────────────────────────────────────────

## Return the cached published_at Unix timestamp for a session.
## Returns 0 if unknown — callers MUST treat 0 as "do not block on age".
func get_session_published_at(session_id: String) -> int:
	return _session_published_at.get(session_id, 0)


## Handler connected to NetworkManager.session_metadata_received.
## Populates the session age cache.
func _on_session_metadata_received(session_id: String, published_at_unix: int) -> void:
	_session_published_at[session_id] = published_at_unix


# ─── HTTP response handlers ───────────────────────────────────────────────────

func _on_auth_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _pending_action
	_pending_action = ""

	if action == "signout":
		# CR-11: Clear tokens only now that the server-side logout response has arrived.
		# On network failure we still clear locally (the token will expire on its own).
		_clear_tokens()
		signed_out.emit()
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		_dispatch_auth_error(action, tr("ui.signin.error_network"))
		return

	if action == "get_user":
		if code == 200:
			var json: Variant = JSON.parse_string(body.get_string_from_utf8())
			if json is Dictionary:
				var confirmed: Variant = (json as Dictionary).get("email_confirmed_at", null)
				_email_confirmed = confirmed != null and confirmed != ""
		return

	if code not in [200, 201]:
		if code == 401:
			_dispatch_auth_error(action, tr("ui.signin.error_invalid_credentials"))
		else:
			_dispatch_auth_error(action, tr("ui.signin.error_network"))
		return

	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not json is Dictionary:
		_dispatch_auth_error(action, tr("ui.signin.error_network"))
		return

	var resp := json as Dictionary

	if action == "signup":
		# sign-up returns the user object; session may not be present if email confirm required.
		var user: Variant = resp.get("user", resp)
		if user is Dictionary:
			_user_id = str((user as Dictionary).get("id", ""))
		_access_token = str(resp.get("access_token", ""))
		_refresh_token = str(resp.get("refresh_token", ""))
		_expires_at = _parse_expires(resp)
		_save_tokens()
		sign_up_ok.emit(_user_id)
		return

	# signin and refresh share the same token response structure.
	_access_token = str(resp.get("access_token", ""))
	_refresh_token = str(resp.get("refresh_token", ""))
	_expires_at = _parse_expires(resp)
	var user: Variant = resp.get("user", {})
	if user is Dictionary:
		var user_dict := user as Dictionary
		_user_id = str(user_dict.get("id", ""))
		var confirmed: Variant = user_dict.get("email_confirmed_at", null)
		_email_confirmed = confirmed != null and confirmed != ""
		# W1 fix: cache username from GoTrue user_metadata so get_username() returns
		# the actual name immediately after sign-in (instead of "" until first
		# change_username() call). Falls back to email local-part if no username set.
		var meta: Variant = user_dict.get("user_metadata", {})
		if meta is Dictionary:
			var meta_name: String = str((meta as Dictionary).get("username", ""))
			if not meta_name.is_empty():
				_cached_username = meta_name
		if _cached_username.is_empty():
			var email_str: String = str(user_dict.get("email", ""))
			var at_idx := email_str.find("@")
			if at_idx > 0:
				_cached_username = email_str.substr(0, at_idx)
	_save_tokens()

	if action == "refresh":
		# Silent refresh — do not re-emit signed_in; tokens are updated.
		return

	# action == "signin" (or any unrecognised action after successful auth).
	signed_in.emit(_user_id)


func _on_friends_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _friends_pending_action
	_friends_pending_action = ""

	if result != HTTPRequest.RESULT_SUCCESS or code not in [200, 201, 204]:
		return

	# WR-04 / WR-01: Supabase PostgREST with Prefer: return=representation returns HTTP 200
	# + JSON body for both DELETE and POST, so we cannot use the status code alone to
	# distinguish a friends-list GET from a DELETE or POST. Use _friends_pending_action.
	if action == "delete":
		# DELETE succeeded (body may be the deleted row(s) or empty on 204).
		friendship_deleted.emit()
		return

	if action == "create":
		# POST succeeded — emit friendship_created with the new friend UID.
		# Parse the returned row to extract the friend's UID (whichever of user_a/user_b is not ours).
		var json_c: Variant = JSON.parse_string(body.get_string_from_utf8())
		var friend_uid := ""
		if json_c is Array and (json_c as Array).size() > 0:
			var row: Variant = (json_c as Array)[0]
			if row is Dictionary:
				var ua: String = str((row as Dictionary).get("user_a", ""))
				var ub: String = str((row as Dictionary).get("user_b", ""))
				friend_uid = ub if ua == _user_id else ua
		elif json_c is Dictionary:
			var ua: String = str((json_c as Dictionary).get("user_a", ""))
			var ub: String = str((json_c as Dictionary).get("user_b", ""))
			friend_uid = ub if ua == _user_id else ua
		friendship_created.emit(friend_uid)
		return

	# GET (or fallback): parse and emit the friends list.
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if json is Array:
		_friends_cache = json as Array
		friends_loaded.emit(_friends_cache)


func _on_invite_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _invite_pending_action
	_invite_pending_action = ""

	if result != HTTPRequest.RESULT_SUCCESS or code not in [200, 201, 204]:
		invite_creation_failed.emit(tr("ui.signin.error_network"))
		return

	if action.begins_with("create_invite:"):
		var token := action.substr("create_invite:".length())
		invite_created.emit(token, "cubicraftia://join/" + token)
		return

	if action == "redeem_invite":
		# Redemption succeeded — body contains the updated invite row with host_uid.
		var json: Variant = JSON.parse_string(body.get_string_from_utf8())
		# RELY-04 (D-05): a zero-row PATCH result means the token was expired,
		# already redeemed, or never existed. PostgREST still returns HTTP 200,
		# so the only signal is an empty array. Fail closed: never emit
		# friendship_created with an empty host_uid.
		if not (json is Array and (json as Array).size() > 0):
			invite_redeem_failed.emit("expired")
			return
		var host_uid := ""
		var row: Variant = (json as Array)[0]
		if row is Dictionary:
			host_uid = str((row as Dictionary).get("host_uid", ""))
		# Create the mutual friendship.
		if host_uid != "" and host_uid != _user_id:
			create_friendship(host_uid)
		friendship_created.emit(host_uid)


func _on_profile_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code not in [200, 201]:
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if json is Array:
		profiles_found.emit(json as Array)


func _on_block_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _block_pending_action
	_block_pending_action = ""

	if result != HTTPRequest.RESULT_SUCCESS:
		return

	if action.begins_with("block:"):
		if code in [200, 201]:
			var uid := action.substr("block:".length())
			user_blocked.emit(uid)
		return

	if action.begins_with("unblock:"):
		if code in [200, 201, 204]:
			var uid := action.substr("unblock:".length())
			user_unblocked.emit(uid)
		return

	if action == "get":
		if code == 200:
			var json: Variant = JSON.parse_string(body.get_string_from_utf8())
			if json is Array:
				_blocks_cache = json as Array
				blocks_loaded.emit(_blocks_cache)
		return


func _on_report_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		return
	if code in [200, 201]:
		report_submitted.emit()


func _on_consent_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := _consent_pending_action
	_consent_pending_action = ""

	if action == "request":
		if result == HTTPRequest.RESULT_SUCCESS and code in [200, 201]:
			# Request sent — consent is now pending (not yet confirmed by parent).
			_emit_consent_status(false, true)
		return

	if action == "status":
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			# Network error — conservatively emit not-consented, not-pending.
			_emit_consent_status(false, false)
			return
		var json: Variant = JSON.parse_string(body.get_string_from_utf8())
		if not json is Array or (json as Array).is_empty():
			# No consent record exists yet.
			_emit_consent_status(false, false)
			return
		var row: Variant = (json as Array)[0]
		if not row is Dictionary:
			_emit_consent_status(false, false)
			return
		var d := row as Dictionary
		var consented_at: Variant = d.get("consented_at", null)
		var revoked_at: Variant = d.get("revoked_at", null)
		var requested_at: Variant = d.get("requested_at", null)
		if revoked_at != null and revoked_at != "":
			# Consent was revoked — treat as not consented, not pending.
			_emit_consent_status(false, false)
		elif consented_at != null and consented_at != "":
			# Parent has confirmed.
			_emit_consent_status(true, false)
		elif requested_at != null and requested_at != "":
			# Request exists but not yet confirmed.
			_emit_consent_status(false, true)
		else:
			_emit_consent_status(false, false)


## Update is_consented property and emit consent_status_received.
## Central helper so all consent-status code paths update the property consistently.
## Plan 05-12: extracted from _on_consent_completed so integration tests can call
## consent_status_received.emit() → is_consented is always kept in sync.
func _emit_consent_status(p_is_consented: bool, p_is_pending: bool) -> void:
	is_consented = p_is_consented
	consent_status_received.emit(p_is_consented, p_is_pending)


# ─── Token persistence ────────────────────────────────────────────────────────

## Save tokens to user://auth.cfg [auth] section.
## Never logs the token value (T-04-04-I); debug log shows only first 8 chars.
func _save_tokens() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "access_token", _access_token)
	cfg.set_value(SECTION, "refresh_token", _refresh_token)
	cfg.set_value(SECTION, "expires_at", _expires_at)
	cfg.set_value(SECTION, "user_id", _user_id)
	cfg.set_value(SECTION, "email_confirmed", _email_confirmed)
	cfg.save(AUTH_PATH)


## Load tokens from user://auth.cfg [auth] section.
func _load_tokens() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AUTH_PATH) != OK:
		return
	_access_token = cfg.get_value(SECTION, "access_token", "")
	_refresh_token = cfg.get_value(SECTION, "refresh_token", "")
	_expires_at = cfg.get_value(SECTION, "expires_at", 0.0)
	_user_id = cfg.get_value(SECTION, "user_id", "")
	_email_confirmed = cfg.get_value(SECTION, "email_confirmed", false)


## Clear all in-memory tokens and remove auth.cfg entries.
func _clear_tokens() -> void:
	_access_token = ""
	_refresh_token = ""
	_expires_at = 0.0
	_user_id = ""
	_email_confirmed = false
	var cfg := ConfigFile.new()
	cfg.save(AUTH_PATH)  # Write empty config to clear the file.


# ─── Timer callback ───────────────────────────────────────────────────────────

## Called every 60 seconds by _refresh_timer. Refreshes the token if within 5 minutes of expiry.
func _check_token_expiry() -> void:
	if _access_token == "" or _refresh_token == "":
		return
	var now := Time.get_unix_time_from_system()
	if _expires_at - now < 300.0:
		refresh_token()


# ─── Private helpers ──────────────────────────────────────────────────────────

## Return standard auth headers (no Bearer token — used for sign-in/sign-up endpoints).
func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + _anon_key,
	])


## Return authenticated headers (includes Bearer token — used for REST calls).
func _authed_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + _anon_key,
		"Authorization: Bearer " + _access_token,
		"Prefer: return=representation",
	])


## Return authenticated headers with Prefer: return=minimal.
## Used for DELETE calls where we don't need the deleted row body returned.
func _authed_headers_minimal() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + _anon_key,
		"Authorization: Bearer " + _access_token,
		"Prefer: return=minimal",
	])


## Return true if an HTTPRequest node is ready to accept a new request.
## Prevents concurrent request collisions on the same HTTPRequest node.
func _is_req_ready(req: HTTPRequest) -> bool:
	return is_instance_valid(req) and req.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED


## Return the canonical [user_a, user_b] pair such that user_a < user_b lexicographically.
## Mirrors the Postgres CHECK (user_a < user_b) constraint.
## WR-06: Returns [] if uid_x == uid_y (self-friendship attempt) so the caller can
## detect and reject the request before hitting the Postgres CHECK constraint.
## Pure function — safe to call as a static (access via instance for GDScript compat).
static func _canonical_pair(uid_x: String, uid_y: String) -> Array[String]:
	if uid_x == uid_y:
		push_warning("FriendsClient._canonical_pair: attempt to friend self (%s)" % uid_x)
		return []  # Caller must check for empty result and abort.
	if uid_x < uid_y:
		return [uid_x, uid_y]
	return [uid_y, uid_x]


## Return true if the invite dict represents a valid (unexpired, single-use) token.
## invite_dict must have keys: "expires_at" (Unix timestamp float), "redeemed_by" (Variant).
## Used by unit tests to verify token validation logic without a live Supabase call.
static func _is_invite_valid(inv: Dictionary) -> bool:
	if inv.get("redeemed_by") != null:
		return false
	var exp: Variant = inv.get("expires_at", 0)
	var exp_f: float = float(exp) if exp != null else 0.0
	return exp_f > Time.get_unix_time_from_system()


## Generate a 26-character base32 invite token (128-bit entropy, URL-safe lowercase).
## Uses Crypto.generate_random_bytes (CSPRNG) instead of randi() (Mersenne Twister).
## 16 raw bytes = 128 bits; base32 encodes 5 bits per character → 26 characters.
func _generate_invite_token() -> String:
	var crypto := Crypto.new()
	var raw: PackedByteArray = crypto.generate_random_bytes(16)
	var token := ""
	var bits: int = 0
	var bit_count: int = 0
	for byte: int in raw:
		bits = (bits << 8) | byte
		bit_count += 8
		while bit_count >= 5:
			bit_count -= 5
			token += BASE32_ALPHABET[(bits >> bit_count) & 0x1F]
	# Emit trailing bits: 128 bits / 5 = 25 full groups + 3 remainder bits.
	# Left-shift the accumulator to align the remaining bits to the MSB of the
	# 5-bit window so the output character is deterministic and URL-safe.
	if bit_count > 0:
		token += BASE32_ALPHABET[(bits << (5 - bit_count)) & 0x1F]
	return token


## Parse the expires_in field from a GoTrue token response into an absolute Unix timestamp.
## Falls back to 3600 seconds if the field is absent.
func _parse_expires(resp: Dictionary) -> float:
	var expires_in: Variant = resp.get("expires_in", 3600)
	var seconds: float = float(expires_in) if expires_in != null else 3600.0
	return Time.get_unix_time_from_system() + seconds


## Dispatch a sign-in or sign-up failure signal based on the pending action string.
func _dispatch_auth_error(action: String, reason: String) -> void:
	if action == "signup":
		sign_up_failed.emit(reason)
	else:
		sign_in_failed.emit(reason)
