# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_bed_pickup.gd — Regression tests for the "bed not in inventory after pickup" bug.
#
# Root cause (original bug): builder_bed.tres shipped in src/bricks/ but was absent from
# src/bricks/manifest.json, so BrickRegistry never loaded it at boot. BedEntity.on_break gated its
# Inventory ADD on BrickRegistry.get_definition("builder_bed") != null — which was always null — so
# the picked-up bed never entered the inventory and could never be re-placed.
#
# Fix: builder_bed.tres is now listed in manifest.json (loads as a normal base brick), AND
# BedEntity self-registers the bed def as a fallback (load .tres directly + register_pack) in
# _ready and on_break, then awards the bed unconditionally. These tests verify both halves:
#   1. After _ensure_bed_registered, BrickRegistry resolves "builder_bed" (re-placement path needs this).
#   2. An ADD event for "builder_bed" lands in the builder's inventory (pickup path).
#
# These tests do NOT open a world (the inventory ADD path uses lazy _ensure_inventory and needs no
# WorldSave), so they are independent of the SQLite-headless WorldSave init.

extends GutTest

const BedEntityScript = preload("res://src/world/bed_entity.gd")
const HotbarScript = preload("res://src/ui/hotbar.gd")

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
	# "builder_bed" must be resolvable in BrickRegistry after _ensure_bed_registered. On a normal
	# boot it is already present (manifest-loaded) so this is a no-op; the fallback self-register
	# still guarantees resolution if it were missing. _ensure_bed_registered is the public seam we
	# exercise here (calling it directly avoids a full scene-tree _ready with Spawning/world deps).
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


# ─── Test 3: a picked-up bed can be equipped + dispatched to the bed-place path ────
#
# Closes the second half of the loop: the bed must be SELECTABLE as the active hotbar
# brick and Builder._try_place must route it to _try_place_bed (brick_id check), not the
# generic stud-grid place. We exercise the same seams the UI uses:
#   palette tile click -> Hotbar.set_slot_brick -> Hotbar.get_active_brick
#   -> BrickRegistry.get_definition().brick_id == "builder_bed" (the _try_place dispatch test).
func test_bed_equips_and_routes_to_bed_place() -> void:
	var bed = BedEntityScript.new()
	bed._ensure_bed_registered()

	var hotbar = HotbarScript.new()
	add_child_autofree(hotbar)  # _ready builds the slot arrays so set_slot_brick works fully

	# Equip the bed into the active hotbar slot (the palette's equip seam).
	hotbar.set_slot_brick(0, "builder_bed", -1)
	hotbar.selected_slot = 0

	var active: Dictionary = hotbar.get_active_brick()
	assert_eq(str(active.get("def_id", "")), "builder_bed",
		"After equipping, the active hotbar brick must be builder_bed")

	# Mirror Builder._try_place's dispatch decision: the active def's brick_id drives whether
	# placement routes to _try_place_bed (spawn a BedEntity) instead of the stud grid.
	var active_def: Resource = BrickRegistry.get_definition(str(active.get("def_id", "")))
	assert_not_null(active_def, "Equipped builder_bed must resolve in BrickRegistry")
	if active_def != null:
		assert_eq(str(active_def.get("brick_id")), "builder_bed",
			"Active def's brick_id must be builder_bed so _try_place routes to _try_place_bed")

	bed.free()


# ─── Test 4: placing a bed from the inventory consumes exactly one ────────────────
#
# Mirrors Builder._try_place_bed's consume step: a REMOVE of one builder_bed must succeed
# when the player holds one and decrement to zero (no double-spend, no silent failure that
# would leave the bed stuck in the bag). This is the inventory side of re-placement.
func test_bed_place_consumes_one_from_inventory() -> void:
	var bed = BedEntityScript.new()
	bed._ensure_bed_registered()

	# Hold one bed, then place it (consume).
	Inventory.apply_event({"kind": "ADD", "builder_id": _builder_id, "def_id": "builder_bed", "count": 1})
	var consumed: bool = Inventory.apply_event({
		"kind": "REMOVE", "builder_id": _builder_id, "def_id": "builder_bed", "count": 1,
	})
	assert_true(consumed, "Placing a held bed must consume one builder_bed (REMOVE succeeds)")

	var remaining: int = 0
	for s: Dictionary in Inventory.get_slots(_builder_id):
		if s.get("def_id", "") == "builder_bed":
			remaining += int(s.get("count", 0))
	assert_eq(remaining, 0, "After placing the only bed, none must remain in the inventory")

	# With none held, a second place must NOT succeed (no phantom bed / double-spend).
	var consumed_again: bool = Inventory.apply_event({
		"kind": "REMOVE", "builder_id": _builder_id, "def_id": "builder_bed", "count": 1,
	})
	assert_false(consumed_again, "Placing a bed the player no longer holds must fail (no double-spend)")

	bed.free()
