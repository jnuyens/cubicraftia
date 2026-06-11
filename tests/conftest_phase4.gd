# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# conftest_phase4.gd — Shared GUT fixtures for the Phase 4 multiplayer test suite.
#
# NOT extends GutTest — this is a helper class used by test files via preload().
# NOT registered as an autoload (test-only code per T-04-01-SC).
#
# Usage in test files:
#   const Phase4Fixtures = preload("res://tests/conftest_phase4.gd")
#   Phase4Fixtures.open_temp_world()
#
# Provides:
#   - open_temp_world(mode)             — open a fresh temp world, return the world_id
#   - cleanup_temp_world(world_id)      — delete the temp world directory
#   - make_rtt_table(peer_ids, rtts)    — build {peer_id: rtt_ms} dict for election tests
#   - make_join_order(peer_ids)         — build {peer_id: index} dict for tiebreaker tests
#
# Anchors:
#   04-PLAN.md 04-01 Task 1 — conftest_phase4 fixture spec
#   04-CONTEXT.md Area 1 — host election: RTT table + join-order tiebreaker
#   04-PATTERNS.md — mirrors conftest_phase3.gd structure verbatim

class_name Phase4Fixtures
extends RefCounted


# ─── Open / close helpers ──────────────────────────────────────────────────────

## Open a temporary world for test use.
##
## Creates a world in user://worlds/<uuid>/ with the given mode, calls
## WorldSave.open_world(), and returns the world_id string so the caller
## can close it later if needed.
##
## @param mode  "survival" or "sandbox" (default: "survival").
## @return      world_id string, or "" if open_world() failed.
static func open_temp_world(mode: String = "survival") -> String:
	if WorldSave.is_open():
		push_warning("Phase4Fixtures.open_temp_world: a world is already open — closing it first.")
		WorldSave.close_world()

	# Generate a pseudo-unique world_id using time + random to avoid collisions.
	var wid := "phase4_test_%d_%d" % [Time.get_ticks_msec(), randi()]
	var ok := WorldSave.open_world(wid, 42, mode)
	if not ok:
		push_error("Phase4Fixtures.open_temp_world: WorldSave.open_world('%s', 42, '%s') failed." % [wid, mode])
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


# ─── Election test helpers ─────────────────────────────────────────────────────

## Build a {peer_id: rtt_ms} Dictionary for use in host-election unit tests.
##
## Both arrays must be the same length; peer_ids[i] maps to rtts[i].
##
## @param peer_ids  Array of peer ID integers (or strings).
## @param rtts      Array of RTT values in milliseconds (float or int).
## @return          Dictionary mapping each peer_id to its RTT value.
static func make_rtt_table(peer_ids: Array, rtts: Array) -> Dictionary:
	var table: Dictionary = {}
	for i: int in range(peer_ids.size()):
		table[peer_ids[i]] = rtts[i]
	return table


## Build a {peer_id: join_index} Dictionary for use in tiebreaker unit tests.
##
## Index 0 = first to join (oldest peer, wins tiebreaker when RTTs are equal).
## Mirrors the election algorithm in 04-RESEARCH.md lines 668-681.
##
## @param peer_ids  Array of peer IDs in join order (oldest first).
## @return          Dictionary mapping each peer_id to its join-order index.
static func make_join_order(peer_ids: Array) -> Dictionary:
	var order: Dictionary = {}
	for i: int in range(peer_ids.size()):
		order[peer_ids[i]] = i
	return order
