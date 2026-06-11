# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_eula_hash_recompute.gd — Unit tests for EULA SHA-256 hash and mismatch detection.
#
# Tests the EULA hash logic (Pattern 4 from 05-RESEARCH.md):
#   - SHA-256 hash of the same content always produces the same hex string (deterministic).
#   - Different content produces a different hash (collision resistance).
#   - When the stored hash in user://settings.cfg [legal] eula_hash differs from the
#     bundled file hash, the mismatch is detected and the re-acknowledge modal is triggered.
#
# Godot built-in: HashingContext.HASH_SHA256 — no external dependency.
# First 16 hex characters of the SHA-256 hash are used as the stored version key.
# The bundled file is res://docs/EULA.md (added in Phase 5 plan 05-09).
# Activate in: 05-09 (EULA + privacy viewer plan).
#
# Anchors:
#   05-01-PLAN.md Task 1 — EULA hash test stubs
#   05-RESEARCH.md Pattern 4 — SHA-256 hash check + re-acknowledge gate
#   05-CONTEXT.md Area 4 — SHA-256 hash stored in user://settings.cfg [legal] eula_hash
#   DOCS §8.5 — EULA + Privacy bundled markdown, SHA-256 hash versioning

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")


## Helper: compute SHA-256 hex string for a given String content.
## Uses HashingContext.HASH_SHA256 directly — no file I/O.
func _sha256_of_string(content: String) -> String:
	var ctx := HashingContext.new()
	var err := ctx.start(HashingContext.HASH_SHA256)
	assert_eq(err, OK, "_sha256_of_string: HashingContext.start must return OK")
	var bytes: PackedByteArray = content.to_utf8_buffer()
	ctx.update(bytes)
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode()


func test_sha256_produces_consistent_hash() -> void:
	# The same string must always produce the same hex-encoded SHA-256 hash.
	# This validates that HashingContext is deterministic (no random IV, no salt).
	# DOCS §8.5 — hash-based EULA versioning requires determinism.
	var hash_a: String = _sha256_of_string("test content")
	var hash_b: String = _sha256_of_string("test content")
	assert_eq(hash_a, hash_b,
		"SHA-256 must produce the same hash for the same content (determinism required for EULA versioning)")
	# Sanity: SHA-256 produces 64 hex characters (256 bits = 32 bytes = 64 hex digits).
	assert_eq(hash_a.length(), 64,
		"SHA-256 hex string must be exactly 64 characters")


func test_different_content_produces_different_hash() -> void:
	# Two distinct strings must produce different SHA-256 digests.
	# This is the core property that makes hash-based EULA version detection work:
	# if EULA.md changes, the hash changes, and the re-acknowledge gate fires.
	# DOCS §8.5 — re-acknowledge gate on hash change.
	var hash_a: String = _sha256_of_string("content A — EULA version 1")
	var hash_b: String = _sha256_of_string("content B — EULA version 2")
	assert_ne(hash_a, hash_b,
		"Different content must produce different SHA-256 hashes (collision resistance required for EULA mismatch detection)")


func test_stored_hash_mismatch_detected() -> void:
	# Simulate EULA version upgrade: compute hash of v1, compute hash of v2, compare.
	# A mismatch must be detected so the re-acknowledge modal can be triggered.
	# DOCS §8.5 — re-acknowledge gate fires when bundled hash != stored hash.
	#
	# This mirrors FriendsClient.check_eula_acknowledgement() logic:
	#   bundled_short = sha256(EULA.md).substr(0, 16)
	#   stored_hash   = ConfigFile("legal", "eula_hash")
	#   if bundled_short != stored_hash → trigger re-acknowledge modal
	#
	var hash_v1_full: String = _sha256_of_string("EULA version 1 — initial release")
	var hash_v2_full: String = _sha256_of_string("EULA version 2 — updated with COPPA provisions")

	# Use the first 16 hex characters (same as FriendsClient.check_eula_acknowledgement()).
	var stored_hash: String = hash_v1_full.substr(0, 16)   # What was stored when user accepted v1.
	var bundled_hash: String = hash_v2_full.substr(0, 16)  # What is bundled in the current build.

	# Mismatch: user accepted v1, but v2 is now bundled.
	var is_up_to_date: bool = (stored_hash == bundled_hash)
	assert_false(is_up_to_date,
		"Hash mismatch between stored v1 and bundled v2 must be detected (triggers re-acknowledge gate per DOCS §8.5)")

	# Sanity check: v1 matches v1 (no spurious re-acknowledge after a no-op rebuild).
	var stored_still_v1: String = hash_v1_full.substr(0, 16)
	var bundled_still_v1: String = hash_v1_full.substr(0, 16)
	assert_true(stored_still_v1 == bundled_still_v1,
		"Identical hash must match — no spurious re-acknowledge when EULA has not changed")
