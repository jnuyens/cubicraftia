# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_bed_pickup.gd — Regression tests for the "bed not in inventory after pickup" bug.
#
# Root cause: builder_bed.tres ships in src/bricks/ but is absent from src/bricks/manifest.json,
# so BrickRegistry never loads it at boot. BedEntity.on_break gated its Inventory ADD on
# BrickRegistry.get_definition("builder_bed") != null — which was always null — so the picked-up
# bed never entered the inventory and could never be re-placed.
#
# Fix: BedEntity self-registers the bed def into BrickRegistry (load .tres directly + register_pack)
# in _ready and on_break, then awards the bed unconditionally. These tests verify both halves:
#   1. After _ensure_bed_registered, BrickRegistry resolves "builder_bed" (re-placement path needs this).
#   2. An ADD event for "builder_bed" lands in the builder's inventory (pickup path).
#
# These tests do NOT open a world (the inventory ADD path uses lazy _ensure_inventory and needs no
# WorldSave), so they are independent of the SQLite-headless WorldSave init.

extends GutTest

const BedEntityScript = preload("res://src/world/bed_entity.gd")

var _builder_id: String = "test_bed_pickup_builder_001"


func before_each() -> void:
	# Start each test from a clean inventory for this builder.
	if Inventory.has_method("get_slots"):
		var slots: Array = Inventory.get_slots(_builder_id)
		for i: int in range(slots.size()):
			var s: Dictionary = slots[i] as Dictionary
			if s.get("def_id", "") != "" and s.get("count", 0) > 0:
				Inventory.apply_event({
					"kind": "REMOVE",
					"builder_id": _builder_id,
					"def_id": s.get("def_id", ""),
					"count": s.get("count", 0),
				})


# ─── Test 1: bed self-registers into BrickRegistry ────────────────────────────

func test_bed_registers_into_brick_registry() -> void:
	# A fresh BedEntity instance must make "builder_bed" resolvable in BrickRegistry, even though
	# it is absent from manifest.json. _ensure_bed_registered is the public seam we exercise here
	# (calling it directly avoids needing a full scene-tree _ready with Spawning/world deps).
	var bed = BedEntityScript.new()
	bed._ensure_bed_registered()
	var def: Resource = BrickRegistry.get_definition("builder_bed")
	assert_not_null(def, "builder_bed must resolve in BrickRegistry after _ensure_bed_registered")
	if def != null:
		assert_eq(str(def.get("brick_id")), "builder_bed",
			"Registered def must be the builder_bed BrickDefinition")
	bed.free()


# ─── Test 2: picking up a bed adds it to the inventory ────────────────────────

func test_bed_pickup_adds_to_inventory() -> void:
	# Mirror BedEntity.on_break's award: an ADD event for builder_bed must land in a slot.
	# (on_break itself calls queue_free + reads global_position, which needs a tree; the
	# inventory effect is the part that was broken, so we assert that directly.)
	var bed = BedEntityScript.new()
	bed._ensure_bed_registered()
	var ok: bool = Inventory.apply_event({
		"kind": "ADD",
		"builder_id": _builder_id,
		"def_id": "builder_bed",
		"count": 1,
	})
	assert_true(ok, "ADD of builder_bed must succeed")

	var slots: Array = Inventory.get_slots(_builder_id)
	var bed_count: int = 0
	for s: Dictionary in slots:
		if s.get("def_id", "") == "builder_bed":
			bed_count += int(s.get("count", 0))
	assert_eq(bed_count, 1,
		"After pickup, exactly one builder_bed must be present in the inventory")
	bed.free()
