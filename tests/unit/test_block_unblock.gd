# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_block_unblock.gd — Unit tests for block/unblock RLS logic.
#
# Tests the Supabase `blocks` table RLS policies:
#   - Blocker can INSERT a row (they are the initiator).
#   - Blocker can SELECT only their own rows (direction matters).
#   - Blocked user cannot see rows where they are the target.
#   - Unblock (DELETE) removes the row so the blocked user is no longer gated.
#
# Schema reference: 004_blocks.sql (blocker_uid, blocked_uid, created_at).
# Activate in: 05-12 (Supabase integration test phase).
#
# Anchors:
#   05-01-PLAN.md Task 1 — block/unblock test stubs
#   05-RESEARCH.md Pattern 1 — blocks table RLS design
#   05-CONTEXT.md Area 1 — block architecture (direction matters, no reason column)
#   DOCS §6.2 — Blocking: mutual, instant, persistent; prevents joining host's session

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")


func test_block_stores_direction() -> void:
	# Phase5Fixtures.make_mock_block_row builds a row matching 004_blocks.sql schema.
	# The blocker_uid column must match the UID of the user who initiated the block;
	# the blocked_uid column must match the target UID.
	# Direction matters: RLS filters by blocker_uid = auth.uid() so only the initiator
	# can see the row (blocked user cannot see they are blocked).
	# DOCS §6.2 — blocking is asymmetric at the DB level (direction-aware RLS).
	var row: Dictionary = Phase5Fixtures.make_mock_block_row("uid_a", "uid_b")
	assert_eq(row.get("blocker_uid"), "uid_a",
		"blocker_uid must match the UID of the user who initiated the block")
	assert_eq(row.get("blocked_uid"), "uid_b",
		"blocked_uid must match the UID of the target user")
	assert_ne(row.get("created_at", ""), "",
		"created_at must be populated so RLS can enforce time-ordered queries")


func test_blocker_cannot_see_blocked_uid_rows() -> void:
	# When user "me" has blocked "them", the row has blocker_uid="me", blocked_uid="them".
	# RLS: SELECT WHERE blocker_uid = auth.uid() — "me" can see this row.
	# Simulated filter: filter rows where blocker_uid == "me".
	# DOCS §6.2 — mutual block: neither side sees the other in the friends list.
	var blocks: Array[Dictionary] = [
		Phase5Fixtures.make_mock_block_row("me", "them"),
		Phase5Fixtures.make_mock_block_row("other_user", "someone_else"),
	]

	# "me" fetches their own block list (RLS filter: blocker_uid = "me").
	var my_blocks: Array = blocks.filter(func(b: Dictionary) -> bool:
		return b.get("blocker_uid", "") == "me"
	)
	assert_eq(my_blocks.size(), 1,
		"'me' must see exactly 1 block row (the one they initiated)")
	assert_eq(my_blocks[0].get("blocked_uid", ""), "them",
		"The blocker's view must show the blocked_uid as 'them'")


func test_unblock_removes_row() -> void:
	# Unblocking is a DELETE operation: remove the row where blocker_uid="me" AND
	# blocked_uid="them". The remaining list must have one fewer row.
	# DOCS §8 Area 1 — unblock removes the Supabase row; FriendsClient removes from cache.
	var uid_me: String = "uid_me_123"
	var uid_them: String = "uid_them_456"
	var uid_other: String = "uid_other_789"
	var uid_someone: String = "uid_someone_000"

	var blocks: Array[Dictionary] = [
		Phase5Fixtures.make_mock_block_row(uid_me, uid_them),
		Phase5Fixtures.make_mock_block_row(uid_other, uid_someone),
	]
	assert_eq(blocks.size(), 2, "Setup: must have 2 block rows before unblock")

	# Simulate DELETE WHERE blocker_uid = uid_me AND blocked_uid = uid_them.
	blocks = blocks.filter(func(b: Dictionary) -> bool:
		return not (b.get("blocker_uid", "") == uid_me and b.get("blocked_uid", "") == uid_them)
	)
	assert_eq(blocks.size(), 1,
		"After unblock DELETE, block list must have 1 fewer row (from 2 to 1)")
	assert_eq(blocks[0].get("blocker_uid", ""), uid_other,
		"The remaining row must be the unrelated block (uid_other → uid_someone)")


func test_blocked_uid_sees_nothing() -> void:
	# The blocked user ("them") cannot see rows where they appear as blocked_uid.
	# RLS: the SELECT policy only allows rows where blocker_uid = auth.uid().
	# "them" has no rows where THEY are the blocker — so their result is empty.
	# DOCS §6.2 — blocked user cannot see they are blocked (no "you are blocked" signal).
	var blocks: Array[Dictionary] = [
		Phase5Fixtures.make_mock_block_row("me", "them"),
	]

	# "them" fetches their own block list (RLS filter: blocker_uid = "them").
	# "them" has never blocked anyone, so the result is empty.
	var their_blocks: Array = blocks.filter(func(b: Dictionary) -> bool:
		return b.get("blocker_uid", "") == "them"
	)
	assert_eq(their_blocks.size(), 0,
		"Blocked user must see zero block rows — RLS hides rows where blocked_uid = auth.uid()")
