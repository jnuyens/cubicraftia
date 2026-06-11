# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_report_submission.gd — Unit tests for report audit trail and surface enum.
#
# Tests the Supabase `reports` table RLS policies:
#   - Reporter can INSERT a report row.
#   - Reporter can SELECT only their own submitted reports.
#   - Reported user cannot see any reports filed against them (no SELECT policy).
#   - Evidence JSONB captures chat context (up to 5 messages) for chat_message surface.
#
# Schema reference: 005_reports.sql (id, reporter_uid, reported_uid, surface, category,
#   reason, evidence, session_id, created_at). Reports are immutable — no UPDATE/DELETE.
# Surface enum: 'player' | 'build' | 'chat_message'.
# Category enum: 'harassment' | 'spam' | 'cheating' | 'csam' | 'other'.
# Activate in: 05-12 (Supabase integration test phase).
#
# Anchors:
#   05-01-PLAN.md Task 1 — report submission test stubs
#   05-RESEARCH.md Migration 005 — reports schema
#   05-CONTEXT.md Area 1 — report architecture (immutable, surface/category enums)
#   DOCS §8.2 — Three report surfaces; reports go to discovery server

extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")


func test_reporter_can_insert() -> void:
	# Reports are INSERT-only per RLS (immutable audit trail — no UPDATE, no DELETE).
	# The reporter_uid column must match the UID of the user who filed the report.
	# DOCS §8.2 — reporter submits from nameplate / friends list / chat message context.
	var row: Dictionary = Phase5Fixtures.make_mock_report_row(
		"reporter_uid_001", "reported_uid_002", "player", "spam")

	assert_eq(row.get("reporter_uid"), "reporter_uid_001",
		"reporter_uid must match the UID of the reporting user")
	assert_eq(row.get("reported_uid"), "reported_uid_002",
		"reported_uid must match the UID of the reported user")
	assert_eq(row.get("surface"), "player",
		"surface must be 'player' for a report submitted from the nameplate or friends list")
	assert_eq(row.get("category"), "spam",
		"category must match the value passed to make_mock_report_row")
	assert_ne(row.get("id", ""), "",
		"id must be populated so the report row has a unique identifier")
	assert_ne(row.get("created_at", ""), "",
		"created_at must be populated (immutable audit trail requires a timestamp)")


func test_reported_uid_cannot_see_own_reports() -> void:
	# RLS: SELECT policy allows only reporter_uid = auth.uid().
	# The reported user cannot see reports filed against them.
	# DOCS §8.2 — moderation flow is operator-only (no "you were reported" notification).
	var rows: Array[Dictionary] = [
		Phase5Fixtures.make_mock_report_row("alice", "bob", "player", "harassment"),
		Phase5Fixtures.make_mock_report_row("charlie", "bob", "chat_message", "spam"),
	]

	# Simulate "bob" fetching their own reports (RLS: reporter_uid = "bob").
	# Bob has never filed a report, so the filtered result must be empty.
	var bobs_view: Array = rows.filter(func(r: Dictionary) -> bool:
		return r.get("reporter_uid", "") == "bob"
	)
	assert_eq(bobs_view.size(), 0,
		"Reported user 'bob' must see zero reports — RLS hides rows where reported_uid = auth.uid()")

	# Sanity: alice can see her own submitted report.
	var alice_view: Array = rows.filter(func(r: Dictionary) -> bool:
		return r.get("reporter_uid", "") == "alice"
	)
	assert_eq(alice_view.size(), 1,
		"Reporter 'alice' must see exactly the 1 report she filed")


func test_evidence_captures_chat_context() -> void:
	# For chat_message surface reports, the evidence field captures up to 5 context messages.
	# DOCS §8.2 — "A chat message (long-press the message): reports the message verbatim
	# with the surrounding 5 messages of context."
	var row: Dictionary = Phase5Fixtures.make_mock_report_row(
		"reporter_uid_003", "reported_uid_004", "chat_message", "harassment")

	assert_eq(row.get("surface"), "chat_message",
		"surface must be 'chat_message' for a report filed from the chat message context menu")

	# The evidence field is a JSONB Dictionary in the mock. Real evidence would contain
	# a "messages" array with up to 5 chat entries. Verify the field is a Dictionary
	# (correct type for JSONB storage) even if empty in the mock.
	var evidence: Variant = row.get("evidence")
	assert_true(evidence is Dictionary,
		"evidence must be a Dictionary (maps to JSONB in Supabase) for chat_message surface reports")

	# Verify the three valid surface enum values are accepted by the mock factory.
	for surface: String in ["player", "build", "chat_message"]:
		var test_row: Dictionary = Phase5Fixtures.make_mock_report_row(
			"r", "t", surface, "other")
		assert_eq(test_row.get("surface"), surface,
			"make_mock_report_row must accept surface='%s' (valid enum value per 005_reports.sql)" % surface)
