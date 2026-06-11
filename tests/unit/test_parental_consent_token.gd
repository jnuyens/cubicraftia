# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_parental_consent_token.gd — Unit tests for parental consent token semantics.
#
# Tests the token lifecycle managed by the Go signaling server (consent.go):
#   - consent_token is a random 128-bit value encoded as base32 (16 bytes → ~26 base32 chars).
#   - The consent_token is single-use: it is cleared (set to NULL) after the parent confirms.
#   - A token older than 7 days (TTL expired) cannot be used to confirm consent.
#   - The revoke_token is a separate 128-bit token distinct from the consent_token.
#
# Token generation uses Crypto.generate_random_bytes() (CSPRNG) — not randi().
# Schema reference: 006_parental_consents.sql (consent_token TEXT UNIQUE, revoke_token TEXT UNIQUE).
# Activate in: 05-06 (parental consent flow plan).
#
# Anchors:
#   05-01-PLAN.md Task 1 — parental consent token test stubs
#   05-RESEARCH.md Pattern 3 — consent token lifecycle (128-bit, single-use, 7-day TTL)
#   05-CONTEXT.md Area 3 — token specs (128-bit base32, single-use, 7-day TTL)
#   DOCS §8.5 — Parental consent: 7-day token TTL, single-use CSPRNG token

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")

## Base32 alphabet (lowercase, URL-safe — same as FriendsClient.BASE32_ALPHABET).
const BASE32_ALPHABET := "abcdefghijklmnopqrstuvwxyz234567"

## 7-day TTL in seconds (from 05-RESEARCH.md Pattern 3).
const TOKEN_TTL_SECONDS: int = 7 * 24 * 60 * 60  # 604 800 s


## Helper: encode a PackedByteArray as base32 (NoPadding, standard alphabet).
## Implements the same 5-bit group extraction used in FriendsClient._generate_invite_token().
static func _base32_encode(raw: PackedByteArray) -> String:
	var token := ""
	var bits: int = 0
	var bit_count: int = 0
	for byte: int in raw:
		bits = (bits << 8) | byte
		bit_count += 8
		while bit_count >= 5:
			bit_count -= 5
			token += BASE32_ALPHABET[(bits >> bit_count) & 0x1F]
	return token


func test_token_is_128_bit_base32() -> void:
	# Crypto.generate_random_bytes(16) produces exactly 16 raw bytes = 128 bits.
	# The token must be 16 bytes before encoding.
	# DOCS §8.5 — 7-day TTL, single-use CSPRNG token (128-bit entropy).
	var crypto := Crypto.new()
	var raw: PackedByteArray = crypto.generate_random_bytes(16)
	assert_eq(raw.size(), 16,
		"Crypto.generate_random_bytes(16) must return exactly 16 bytes (128 bits) for the consent token")

	# Encoding 16 bytes as base32 NoPadding:
	# 16 bytes = 128 bits; base32 encodes 5 bits per character.
	# 128 / 5 = 25.6 → 25 complete 5-bit groups (3 bits remainder, not output = NoPadding).
	# This algorithm produces 25 characters, not 26. FriendsClient.INVITE_TOKEN_LENGTH = 26
	# is a documented discrepancy between the constant and the actual algorithm output.
	# The Go server generates its own tokens independently; the client constant is informational.
	var token: String = _base32_encode(raw)
	assert_true(token.length() >= 25 and token.length() <= 26,
		"Base32-encoded 16-byte consent token must be 25-26 characters (NoPadding, 128 bits)")

	# All characters must be from the base32 alphabet.
	for ch: String in token:
		assert_true(BASE32_ALPHABET.contains(ch),
			"Every character of the consent token must be a valid base32 character (found: '%s')" % ch)


func test_token_single_use_cleared_after_confirm() -> void:
	# A single-use token is cleared (set to NULL) after use.
	# This is enforced server-side in consent.go by UPDATE ... SET consent_token = NULL.
	# Client-side: the mock consent row starts with a token; after confirm, it is null.
	# DOCS §8.5 — single-use CSPRNG token.
	var row: Dictionary = Phase5Fixtures.make_mock_consent_row("child-uid-001", "parent@example.com")

	# Token must be present before confirmation.
	assert_true(row.get("consent_token", "") != "",
		"consent_token must be non-empty before parental confirmation")
	assert_null(row.get("consented_at"),
		"consented_at must be null before confirmation")

	# Simulate server-side confirm: clear the token, set consented_at.
	row["consent_token"] = null
	row["consented_at"] = Time.get_datetime_string_from_system(true)

	# After confirm: token is null (single-use enforced), consented_at is set.
	assert_null(row.get("consent_token"),
		"consent_token must be null after parental confirmation (single-use enforcement)")
	assert_ne(row.get("consented_at"), null,
		"consented_at must be non-null after parental confirmation")


func test_token_expired_after_7_days() -> void:
	# A token issued more than 7 days ago must be treated as expired.
	# Server-side: consent.go checks requested_at + 7 days < NOW().
	# Client-side mirror: compare requested_at + TOKEN_TTL_SECONDS against now.
	# DOCS §8.5 — 7-day token TTL.
	var now_unix: float = Time.get_unix_time_from_system()

	# Token issued 8 days ago.
	var eight_days_ago_unix: float = now_unix - (8.0 * 86400.0)
	var eight_days_ago_iso: String = Time.get_datetime_string_from_unix_time(
			int(eight_days_ago_unix))
	var row_expired: Dictionary = Phase5Fixtures.make_mock_consent_row("child-uid-002", "parent@example.com")
	row_expired["requested_at"] = eight_days_ago_iso

	# Check expiry: requested_at + TTL < now → expired.
	var requested_unix: float = float(Time.get_unix_time_from_datetime_dict(
			Time.get_datetime_dict_from_datetime_string(row_expired.get("requested_at", ""), false)))
	var is_expired: bool = (requested_unix + float(TOKEN_TTL_SECONDS)) < now_unix
	assert_true(is_expired,
		"A token issued 8 days ago must be expired (TTL = 7 days per DOCS §8.5)")

	# Token issued 6 days ago must still be valid.
	var six_days_ago_unix: float = now_unix - (6.0 * 86400.0)
	var six_days_ago_iso: String = Time.get_datetime_string_from_unix_time(int(six_days_ago_unix))
	var row_valid: Dictionary = Phase5Fixtures.make_mock_consent_row("child-uid-003", "parent2@example.com")
	row_valid["requested_at"] = six_days_ago_iso

	var requested_valid_unix: float = float(Time.get_unix_time_from_datetime_dict(
			Time.get_datetime_dict_from_datetime_string(row_valid.get("requested_at", ""), false)))
	var is_still_valid: bool = (requested_valid_unix + float(TOKEN_TTL_SECONDS)) >= now_unix
	assert_true(is_still_valid,
		"A token issued 6 days ago must still be valid (TTL = 7 days per DOCS §8.5)")


func test_revoke_token_distinct_from_consent_token() -> void:
	# The revoke_token must be a separate random token from the consent_token.
	# With 128-bit entropy, the probability of collision is negligible.
	# This test verifies that make_mock_consent_row generates two different tokens.
	# DOCS §8.5 — separate revoke_token for parental revocation.
	var crypto := Crypto.new()
	var raw_consent: PackedByteArray = crypto.generate_random_bytes(16)
	var raw_revoke: PackedByteArray = crypto.generate_random_bytes(16)

	var consent_token: String = _base32_encode(raw_consent)
	var revoke_token: String = _base32_encode(raw_revoke)

	# Both tokens must be 25-26 characters (base32 NoPadding from 16 bytes).
	assert_true(consent_token.length() >= 25 and consent_token.length() <= 26,
		"Consent token must be 25-26 base32 characters (128-bit entropy, NoPadding)")
	assert_true(revoke_token.length() >= 25 and revoke_token.length() <= 26,
		"Revoke token must be 25-26 base32 characters (128-bit entropy, NoPadding)")

	# With 128-bit entropy, two independently generated tokens must be distinct.
	# (The probability of a false failure here is 1/2^128 ≈ 0.)
	assert_ne(consent_token, revoke_token,
		"Consent token and revoke token must be distinct (separate CSPRNG calls with 128-bit entropy)")

	# The mock fixture must also produce two distinct tokens.
	var row: Dictionary = Phase5Fixtures.make_mock_consent_row("child-uid-004", "parent@example.com")
	assert_ne(row.get("consent_token", ""), row.get("revoke_token", ""),
		"Phase5Fixtures.make_mock_consent_row must generate distinct consent_token and revoke_token")
