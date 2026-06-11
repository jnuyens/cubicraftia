# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# conftest_phase5.gd — Shared GUT fixtures for the Phase 5 safety/moderation test suite.
#
# NOT extends GutTest — this is a helper class used by test files via preload().
# NOT registered as an autoload (test-only code per T-05-W0-SC).
#
# Usage in test files:
#   const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")
#   Phase5Fixtures.make_mock_block_row("uid-a", "uid-b")
#
# Provides:
#   - open_temp_world(mode)                        — delegates to Phase4Fixtures pattern
#   - cleanup_temp_world(world_id)                 — deletes the temp world directory
#   - make_mock_block_row(blocker, blocked)         — Dictionary matching 004_blocks.sql schema
#   - make_mock_report_row(reporter, reported, surface, category) — Dictionary matching 005_reports.sql schema
#   - make_mock_consent_row(child_uid, parent_email) — Dictionary matching 006_parental_consents.sql schema
#
# Schema column references:
#   blocks:             blocker_uid, blocked_uid, created_at
#   reports:            id, reporter_uid, reported_uid, surface, category, reason, evidence, session_id, created_at
#   parental_consents:  child_uid, parent_email, requested_at, consented_at, revoked_at, consent_token, revoke_token
#
# Anchors:
#   05-01-PLAN.md Task 1 — conftest_phase5 fixture spec
#   05-RESEARCH.md Pattern 1 — blocks schema (blocker_uid, blocked_uid, created_at)
#   05-RESEARCH.md Migration 005 — reports schema
#   05-RESEARCH.md Migration 006 — parental_consents schema

class_name Phase5Fixtures
extends RefCounted


# ─── Open / close helpers ──────────────────────────────────────────────────────

## Open a temporary world for test use.
##
## Delegates to the Phase4Fixtures pattern: creates a world in user://worlds/<uuid>/
## with the given mode and returns the world_id string so the caller can close it.
##
## @param mode  "survival" or "sandbox" (default: "survival").
## @return      world_id string, or "" if open_world() failed.
static func open_temp_world(mode: String = "survival") -> String:
	if WorldSave.is_open():
		push_warning("Phase5Fixtures.open_temp_world: a world is already open — closing it first.")
		WorldSave.close_world()

	var wid := "phase5_test_%d_%d" % [Time.get_ticks_msec(), randi()]
	var ok := WorldSave.open_world(wid, 42, mode)
	if not ok:
		push_error("Phase5Fixtures.open_temp_world: WorldSave.open_world('%s', 42, '%s') failed." % [wid, mode])
		return ""
	return wid


## Clean up a temp world directory created by open_temp_world.
##
## Deletes the world.meta.sqlite file and world directory.
## Call this in after_each() to keep the filesystem tidy.
##
## @param world_id  The world_id returned by open_temp_world().
static func cleanup_temp_world(world_id: String) -> void:
	if world_id.is_empty():
		return
	var abs_path := ProjectSettings.globalize_path("user://worlds/%s" % world_id)
	var meta_path := abs_path + "/world.meta.sqlite"
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(meta_path)
	for bak_n: int in [1, 2, 3]:
		var bak := meta_path + ".bak.%d" % bak_n
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
	if DirAccess.dir_exists_absolute(abs_path):
		DirAccess.remove_absolute(abs_path)


# ─── Block table mock helpers ──────────────────────────────────────────────────

## Build a mock row Dictionary matching the blocks table schema (004_blocks.sql).
##
## Column reference: blocker_uid, blocked_uid, created_at.
## Direction matters: only the blocker can see this row via RLS.
##
## @param blocker  UUID string of the user who initiated the block.
## @param blocked  UUID string of the user who was blocked.
## @return         Dictionary with all schema columns populated.
static func make_mock_block_row(blocker: String, blocked: String) -> Dictionary:
	return {
		"blocker_uid": blocker,
		"blocked_uid": blocked,
		"created_at": Time.get_datetime_string_from_system(true),
	}


# ─── Report table mock helpers ─────────────────────────────────────────────────

## Build a mock row Dictionary matching the reports table schema (005_reports.sql).
##
## Column reference: id, reporter_uid, reported_uid, surface, category, reason,
##   evidence, session_id, created_at.
## Reports are immutable — no UPDATE or DELETE policies.
##
## @param reporter  UUID string of the reporting user.
## @param reported  UUID string of the reported user.
## @param surface   One of: "player", "build", "chat_message".
## @param category  One of: "harassment", "spam", "cheating", "csam", "other".
## @return          Dictionary with all schema columns populated (reason/evidence/session_id empty).
static func make_mock_report_row(
		reporter: String,
		reported: String,
		surface: String = "player",
		category: String = "harassment") -> Dictionary:
	return {
		"id": "report-%d" % randi(),
		"reporter_uid": reporter,
		"reported_uid": reported,
		"surface": surface,
		"category": category,
		"reason": "",
		"evidence": {},
		"session_id": "",
		"created_at": Time.get_datetime_string_from_system(true),
	}


# ─── Parental consent table mock helpers ───────────────────────────────────────

## Build a mock row Dictionary matching the parental_consents table schema (006_parental_consents.sql).
##
## Column reference: child_uid, parent_email, requested_at, consented_at, revoked_at,
##   consent_token, revoke_token.
## Only the Go signaling server (service role) can write this table; child can only SELECT.
##
## @param child_uid    UUID string of the under-13 child account.
## @param parent_email Email address of the parent or guardian.
## @return             Dictionary with all schema columns populated (consented_at/revoked_at null).
static func make_mock_consent_row(child_uid: String, parent_email: String) -> Dictionary:
	return {
		"child_uid": child_uid,
		"parent_email": parent_email,
		"requested_at": Time.get_datetime_string_from_system(true),
		"consented_at": null,
		"revoked_at": null,
		"consent_token": "MOCKTOKEN%d" % randi(),
		"revoke_token": "MOCKREVOKETOKEN%d" % randi(),
	}
