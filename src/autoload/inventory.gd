# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# inventory.gd — Inventory autoload: event-sourced builder/chest/recipes-known state.
#
# Registered as autoload "Inventory" in project.godot (after BrickRegistry per load-order
# contract — Inventory may validate brick def_ids via BrickRegistry at event-apply time).
#
# DOCS.md §4 Inventory, items, and crafting.
#
# Pitfall 1 (TECH-9): Persistence cadence — mark dirty immediately on mutation; coalesce
#   writes on a 30 s timer OR day_boundary signal OR detach_world(), whichever comes first.
#   Belt-and-braces ensures worst-case data loss ≤ 30 real seconds.
# Pitfall 6: Wrong-tier key rejection — _apply_unlock validates REQUIRED_KEY before consuming
#   the key or toggling chest.locked. UI is NOT the authority; Inventory is.
# Pitfall 7: Recipe reveal cache — _revealed_recipes_cache is invalidated per builder when
#   an ingredient slot changes. Until Plan 03-07a wires the registry, invalidation is
#   unconditional; cache becomes load-bearing once IAP recipe packs ship.
# Pitfall 8: Toast spam — _can_show_full_tip() enforces a 2 s cooldown on "ui.inventory.full"
#   toasts. DroppedItem.try_pickup defers to this autoload and does NOT emit its own toast.
#
# All 9 event kinds (ADD / REMOVE / MOVE / SPLIT / SWAP / CRAFT / UNLOCK / DEATH_DROP /
# RECIPE_UNLOCK) flow through apply_event(). Phase 4 host failover replays the in-RAM
# journal onto a new host without retrofitting.
#
# References:
#   DOCS.md §4.1 — 6×8 inventory grid, 64/stack, hotbar = bottom 8 slots
#   DOCS.md §4.4 — 5 chest types, 4 key types, double chests
#   DOCS.md §4.5 — progressive recipe-book reveal
#   DOCS.md §5.1 — sandbox/survival world-creation property (not a §9 flag)
#   03-RESEARCH.md Pattern 1: Event-Sourced Inventory (lines 192-245)
#   03-RESEARCH.md Pitfalls 1, 6, 7, 8 (lines 408-465)
#   03-CONTEXT.md D-01, D-02, D-05, D-11, D-15
#   03-PATTERNS.md §"src/autoload/inventory.gd" analog: tool_wear.gd

extends Node

# ─── Script preloads ──────────────────────────────────────────────────────────
# Preloaded to ensure type resolution works in headless/autoload parse order.
# Mirrors headless-preload-pattern decision (STATE.md 02-07).
const _RecipeScript := preload("res://src/crafting/recipe.gd")
const _RecipeRegistryScript := preload("res://src/crafting/recipe_registry.gd")

# ─── Constants ────────────────────────────────────────────────────────────────

## Total number of inventory slots (6 rows × 8 columns per DOCS §4.1).
const SLOT_COUNT: int = 48

## Number of columns in the inventory grid.
const COLUMN_COUNT: int = 8

## Number of rows in the inventory grid.
const ROW_COUNT: int = 6

## Maximum items per stack (DOCS §4.1; universal in v1 — per-item override is §9-deferred).
const STACK_MAX: int = 64

## Zero-indexed row of the hotbar (bottom row of the 6×8 grid = row 5).
const HOTBAR_ROW: int = 5

## Coalesced persistence delay in seconds (Pitfall 1 — 30 s flush window).
const PERSIST_COALESCE_S: float = 30.0

## Minimum seconds between "inventory full" toast notifications (Pitfall 8).
const FULL_TIP_COOLDOWN_S: float = 2.0

## Required key def_id per chest tier (Pitfall 6 + DOCS §4.4 + D-02).
## The "regular" tier has no required_key entry (always unlocked; no lock mechanic).
const REQUIRED_KEY: Dictionary = {
	"bronze":  "key_bronze",
	"silver":  "key_silver",
	"gold":    "key_gold",
	"diamond": "key_diamond",
}

## Slot counts per chest tier (DOCS §4.4).
const CHEST_SLOT_COUNT: Dictionary = {
	"regular": 48,
	"bronze":  48,
	"silver":  54,
	"gold":    60,
	"diamond": 72,
}

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted after any mutation to a builder's inventory slots or recipes_known.
## @param builder_id  The builder UUID whose state changed.
signal inventory_changed(builder_id: String)

## Emitted when an ADD event successfully places items into a builder's inventory.
## Fires before inventory_changed so listeners can act on the new state.
## Does NOT fire for REMOVE, MOVE, or chest ADD events.
## @param builder_id  The builder UUID.
## @param def_id      The item def_id that was added.
## @param count       The number of items requested to add (original event count).
signal item_added(builder_id: String, def_id: String, count: int)

## Emitted when a chest lock is toggled to unlocked by an UNLOCK event.
## @param chunk_coord  The chunk coordinate key that was unlocked.
signal chest_unlocked(chunk_coord: Vector3i)

## Emitted by DEATH_DROP (survival only) when all builder slots are drained.
## Plan 03-04 / 03-11 listens and instantiates the DeathPile entity.
## @param builder_id       The builder UUID whose inventory was drained.
## @param position         World position for the death pile.
## @param dropped_contents Array of {def_id, count} dicts (non-empty slots only).
signal death_pile_spawned(builder_id: String, position: Vector3, dropped_contents: Array)

## Emitted when a recipe is revealed permanently (first-craft unlock).
## @param builder_id  The builder UUID.
## @param recipe_id   The recipe identifier.
signal recipe_revealed(builder_id: String, recipe_id: String)

## Emitted when all inventory state has been replaced via reset_from_state() (host failover).
## UI panels that cache slot arrays must subscribe and re-read from Inventory.get_slots().
signal inventories_replaced()

# ─── Private state ────────────────────────────────────────────────────────────

## Per-builder slot arrays. {builder_id: Array[Dictionary]}
## Each slot: {def_id: String, count: int}. Empty slot = {def_id: "", count: 0}.
var _inventories: Dictionary = {}

## Per-chunk-coord chest state. {chunk_coord_string: Dictionary}
## chunk_coord_string = "%d_%d_%d" % [x, y, z]
## Chest dict: {type: String, locked: bool, contents: Array, double_chest_partner: String}
var _chests: Dictionary = {}

## Per-builder permanently-revealed recipe set. {builder_id: Dictionary[recipe_id, bool]}
## Populated by CRAFT (first-craft) and RECIPE_UNLOCK events. Persisted to world_meta.
var _recipes_known: Dictionary = {}

## Reveal cache (ingredient-presence check). {builder_id: Dictionary[recipe_id, bool]}
## Includes both permanently-revealed AND "has all ingredients right now" entries.
## Invalidated per Pitfall 7 on inventory changes.
var _revealed_recipes_cache: Dictionary = {}

## In-RAM event journal (NOT persisted in Phase 3; Phase 4 replicates this).
var _journal: Array = []

## Monotonically-increasing event sequence number.
var _next_seq: int = 0

## Builders with unsaved inventory mutations. {builder_id: bool}
var _dirty_builders: Dictionary = {}

## One-shot timer for coalesced builder-inventory persistence (Pitfall 1).
var _persist_timer: Timer = null

## Timestamp of the last "inventory full" toast (Pitfall 8 cooldown).
var _last_full_tip_tick: float = -INF

## Test-only mode override. "" = use Features.is_survival_mode() normally.
## "survival" or "sandbox" force the gate. Set by _test_set_mode_override().
var _test_mode_override: String = ""

## Recipe registry loaded by Plan 03-07a: {recipe_id: Recipe}
var _recipe_registry: Dictionary = {}

## Per-session in-progress crafting grid buffers (not persisted — session-local).
## "crafting_2x2": Array of 4 slot dicts; "crafting_3x3": Array of 9 slot dicts.
## Plan 03-05 deferred this to Plan 03-02 author confirmation; confirmed here (03-07a).
var _floating_crafting_grid: Dictionary = {"crafting_2x2": [], "crafting_3x3": []}


## Public read-only accessor for the floating crafting buffer of a given grid.
## Returns the slot Array directly — the caller MUST NOT mutate it (mutations
## should go through apply_event so signals fire correctly). Pre-fills with the
## expected slot count on first read so the UI never sees an undersized array.
func get_crafting_grid(grid: String) -> Array:
	var expected_size: int = 4 if grid == "crafting_2x2" else 9
	var arr: Array = _floating_crafting_grid.get(grid, [])
	if arr.size() != expected_size:
		arr = []
		for _i: int in range(expected_size):
			arr.append({"def_id": "", "count": 0})
		_floating_crafting_grid[grid] = arr
	return arr

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Subscribe to WorldClock.day_boundary for belt-and-braces persistence.
	if Engine.has_singleton("WorldClock"):
		var world_clock = Engine.get_singleton("WorldClock")
		if world_clock.has_signal("day_boundary"):
			world_clock.day_boundary.connect(_on_day_boundary)

	# Create the coalesced-persistence timer (one-shot; restarted on each dirty mark).
	_persist_timer = Timer.new()
	_persist_timer.one_shot = true
	_persist_timer.wait_time = PERSIST_COALESCE_S
	_persist_timer.timeout.connect(_flush_persistence)
	add_child(_persist_timer)

	# Bridge ToolWear.worn_out → REMOVE event for worn-out tool slots.
	if Engine.has_singleton("ToolWear"):
		var tool_wear = Engine.get_singleton("ToolWear")
		if tool_wear.has_signal("worn_out"):
			tool_wear.worn_out.connect(_on_tool_worn_out)

	# Load recipe registry (Plan 03-07a). RecipeRegistry.load_all() scans
	# src/crafting/recipes/ and also registers crafting-only items (stick) with BrickRegistry.
	# Uses preloaded script constant (headless-preload-pattern — STATE.md 02-07).
	_recipe_registry = _RecipeRegistryScript.load_all()


## Called by main_scene after WorldSave.open_world() to rehydrate in-memory state.
func attach_world() -> void:
	if not WorldSave.is_open():
		return

	# Discover known builder IDs from the meta DB.
	var known_ids: Variant = WorldSave.get_world_meta("known_builder_ids")
	var builder_ids: Array = []
	if known_ids is Array:
		builder_ids = known_ids as Array

	# Load each builder's inventory blob.
	for builder_id: Variant in builder_ids:
		if not builder_id is String:
			continue
		_load_builder_blob(builder_id as String)

	# Load all chests from the chests table.
	var chest_rows: Array = WorldSave.load_all_chests()
	for row: Dictionary in chest_rows:
		var cc: Vector3i = row.get("chunk_coord", Vector3i.ZERO)
		var key: String = _coord_key(cc)
		_chests[key] = {
			"type":                row.get("type", "regular"),
			"locked":              bool(row.get("locked", false)),
			"contents":            row.get("contents", []),
			"double_chest_partner": row.get("double_chest_partner", ""),
		}


## Called by main_scene before WorldSave.close_world().
func detach_world() -> void:
	_flush_persistence()
	_inventories.clear()
	_chests.clear()
	_recipes_known.clear()
	_revealed_recipes_cache.clear()
	_journal.clear()
	_dirty_builders.clear()


# ─── Snapshot API (Phase 4) ───────────────────────────────────────────────────

## Returns a serialisable representation of all inventory state.
## Used by WorldSave.save_world_snapshot() and NetworkManager for failover snapshots.
## The returned Dictionary is a deep copy — safe to serialise asynchronously.
func get_all_state() -> Dictionary:
	return {
		"inventories": _inventories.duplicate(true),
		"journal":     _journal.duplicate(true),
		"next_seq":    _next_seq,
	}


## Resets all inventory state from a serialised snapshot blob.
## Called during host failover when a peer receives a SNAPSHOT_RESET event from the new host.
##
## Deserialises a var_to_bytes(Dictionary) blob produced by get_all_state() and
## fully replaces _inventories, _journal, and _next_seq. Emits inventories_replaced so
## all UI panels know to re-read their slot arrays from Inventory.get_slots().
##
## Also emits inventory_changed per builder so individual panels can update slot-level state.
##
## @param state_blob  PackedByteArray from var_to_bytes(state_dict) (output of get_all_state()).
## @return            true on success; false if the blob is empty or malformed.
func reset_from_state(state_blob: PackedByteArray) -> bool:
	if state_blob.is_empty():
		push_warning("Inventory.reset_from_state: empty blob — no-op")
		return false
	var state: Variant = bytes_to_var(state_blob)
	if not (state is Dictionary):
		push_error("Inventory.reset_from_state: invalid blob format — expected Dictionary, got %s" % typeof(state))
		return false
	var state_dict := state as Dictionary
	if not (state_dict.has("inventories") and state_dict.has("journal") and state_dict.has("next_seq")):
		push_error("Inventory.reset_from_state: blob missing required keys (inventories/journal/next_seq)")
		return false
	# Replace in-RAM state with the snapshot.
	_inventories = state_dict["inventories"].duplicate(true)
	_journal     = state_dict["journal"].duplicate(true)
	_next_seq    = int(state_dict["next_seq"])
	# Invalidate reveal cache — all slots changed.
	_revealed_recipes_cache.clear()
	# Notify listeners: per-builder signal for slot panels + broad signal for full rehydration.
	for builder_id: String in _inventories:
		inventory_changed.emit(builder_id)
	inventories_replaced.emit()
	return true


# ─── Public API ───────────────────────────────────────────────────────────────

## Central event dispatcher. All inventory mutations go through here.
## Stamps a sequence number, dispatches to the typed applier, then journals and marks dirty.
##
## @param event  Dictionary with at least "kind" key.
## @return       true on success; false on validation failure or overflow.
func apply_event(event: Dictionary) -> bool:
	var kind: String = event.get("kind", "")
	var ok: bool = false

	match kind:
		"ADD":
			ok = _apply_add(event)
		"REMOVE":
			ok = _apply_remove(event)
		"MOVE":
			ok = _apply_move(event)
		"SPLIT":
			ok = _apply_split(event)
		"SWAP":
			ok = _apply_swap(event)
		"SINGLE_TAKE":
			ok = _apply_single_take(event)
		"CRAFT":
			ok = _apply_craft(event)
		"UNLOCK":
			ok = _apply_unlock(event)
		"DEATH_DROP":
			ok = _apply_death_drop(event)
		"RECIPE_UNLOCK":
			ok = _apply_recipe_unlock(event)
		"CRAFT_AUTOFILL":
			ok = _apply_craft_autofill(event)
		_:
			# Unknown event kind — push_warning but do NOT crash.
			# Phase 4 must tolerate forward-compatible event kinds from newer clients.
			push_warning("Inventory.apply_event: unknown event kind '%s' — ignored." % kind)
			return false

	if ok:
		# Stamp seq only after successful validation so the journal has no gaps
		# from rejected events (WR-02: gaps break Phase 4 host-failover replay).
		event["seq"] = _next_seq
		_next_seq += 1
		_journal.append(event)
		# Phase 4: broadcast accepted events to all peers (host only).
		# Guard with is_instance_valid per Pitfall 8 (autoload load order).
		if is_instance_valid(NetworkManager) \
				and NetworkManager.is_multiplayer_active() \
				and multiplayer.is_server():
			NetworkManager.broadcast_event(event)
		_mark_dirty_for_event(event)

	return ok


## Return a copy of the builder's 48-slot array.
## Creates an empty inventory on first access (lazy initialisation).
##
## @param builder_id  The builder UUID.
## @return            Array[Dictionary] of 48 slot dicts.
func get_slots(builder_id: String) -> Array:
	_ensure_inventory(builder_id)
	return _inventories[builder_id].duplicate(true)


## Return the 8 global slot indices corresponding to the hotbar (bottom row).
## Hotbar = row 5 (0-indexed) × 8 columns = slots 40..47.
##
## @param builder_id  The builder UUID (unused in v1 — all builders share the same layout).
## @return            Array of 8 ints [40, 41, 42, 43, 44, 45, 46, 47].
func get_hotbar_slots(_builder_id: String) -> Array:
	return [40, 41, 42, 43, 44, 45, 46, 47]


## Return hotbar slot indices as a typed Array[int].
## Equivalent to get_hotbar_slots but typed per plan spec.
func get_hotbar_slot_indices() -> Array[int]:
	return [40, 41, 42, 43, 44, 45, 46, 47]


## Return the slot count for a given chest tier (DOCS §4.4).
##
## @param chest_type  "regular", "bronze", "silver", "gold", or "diamond".
## @return            Number of slots; 0 for unknown tier.
func get_chest_slot_count(chest_type: String) -> int:
	return CHEST_SLOT_COUNT.get(chest_type, 0)


## Return the combined slot count of a double chest (2 × single-chest slot count).
##
## @param chest_coord  Coordinate of either half of the double chest.
## @return             Total slot count, or 0 if not a double chest.
func get_double_chest_slot_count(chest_coord: Vector3i) -> int:
	var state := get_chest_state(chest_coord)
	if state.is_empty() or state.get("double_chest_partner", "").is_empty():
		return 0
	return CHEST_SLOT_COUNT.get(state.get("type", ""), 0) * 2


## Return the chest state dict for the given chunk coordinate.
##
## @param chunk_coord  The chest's chunk coordinate.
## @return             {type, locked, contents, double_chest_partner} or {} if absent.
func get_chest_state(chunk_coord: Vector3i) -> Dictionary:
	var key := _coord_key(chunk_coord)
	return _chests.get(key, {})


## Return the contents (slot array) of a chest.
##
## @param chest_coord  The chest's chunk coordinate.
## @return             Array of slot dicts, or [] if absent.
func get_chest_contents(chest_coord: Vector3i) -> Array:
	var state := get_chest_state(chest_coord)
	return state.get("contents", [])


## Register a chest (called by main_scene when placing a chest entity).
## If the chest already exists (e.g. world reloaded via attach_world), this is a no-op.
##
## @param chunk_coord  The chest's chunk coordinate.
## @param tier         "regular", "bronze", "silver", "gold", or "diamond".
## @param locked       true if the chest starts locked (default true for non-regular).
## @param contents     Initial slot array (optional; default empty).
func register_chest(chunk_coord: Vector3i, tier: String,
					locked: bool = false, contents: Array = [],
					force_replace: bool = false) -> void:
	var key := _coord_key(chunk_coord)
	if _chests.has(key) and not force_replace:
		return  # Already registered (attach_world already loaded it).

	var slot_count := get_chest_slot_count(tier)
	var slots: Array = []
	if contents.is_empty():
		for _i: int in range(slot_count):
			slots.append({"def_id": "", "count": 0})
	else:
		slots = contents

	_chests[key] = {
		"type":                tier,
		"locked":              locked,
		"contents":            slots,
		"double_chest_partner": "",
	}

	# Persist immediately via WorldSave chest CRUD.
	if WorldSave.is_open():
		WorldSave.save_chest(chunk_coord, tier, locked, var_to_bytes(slots), "")


## Attempt to combine two adjacent same-tier chests into a double chest.
##
## @param pos_a  Coordinate of the first chest.
## @param pos_b  Coordinate of the second chest.
## @return       true if combined; false if tiers differ or either chest is missing.
func try_combine_double_chest(pos_a: Vector3i, pos_b: Vector3i) -> bool:
	var key_a := _coord_key(pos_a)
	var key_b := _coord_key(pos_b)
	if not _chests.has(key_a) or not _chests.has(key_b):
		return false

	var type_a: String = _chests[key_a].get("type", "")
	var type_b: String = _chests[key_b].get("type", "")
	if type_a != type_b:
		return false  # Different tiers cannot combine.

	_chests[key_a]["double_chest_partner"] = str(pos_b)
	_chests[key_b]["double_chest_partner"] = str(pos_a)

	# Persist both halves.
	if WorldSave.is_open():
		var ca: Dictionary = _chests[key_a] as Dictionary
		WorldSave.save_chest(pos_a, ca["type"] as String, bool(ca["locked"]), var_to_bytes(ca["contents"] as Array), str(pos_b))
		var cb: Dictionary = _chests[key_b] as Dictionary
		WorldSave.save_chest(pos_b, cb["type"] as String, bool(cb["locked"]), var_to_bytes(cb["contents"] as Array), str(pos_a))

	return true


## Break one half of a double chest, splitting contents proportionally.
## Each half receives a proportional share; combined total is preserved.
##
## @param pos  Coordinate of either half.
func break_double_chest(pos: Vector3i) -> void:
	var key := _coord_key(pos)
	if not _chests.has(key):
		return

	var partner_str: String = _chests[key].get("double_chest_partner", "")
	if partner_str.is_empty():
		return  # Not a double chest.

	# Find partner coordinate.
	var partner_coord := _parse_coord_key(partner_str)
	var key_b := _coord_key(partner_coord)

	# Collect all items from both halves into a flat array of {def_id, count}.
	var all_items: Array = []
	for s: Dictionary in _chests[key].get("contents", []):
		if s.get("def_id", "") != "" and s.get("count", 0) > 0:
			all_items.append({"def_id": s["def_id"], "count": s["count"]})
	if _chests.has(key_b):
		for s: Dictionary in _chests[key_b].get("contents", []):
			if s.get("def_id", "") != "" and s.get("count", 0) > 0:
				all_items.append({"def_id": s["def_id"], "count": s["count"]})

	# Count total items.
	var total: int = 0
	for item: Dictionary in all_items:
		total += item.get("count", 0)

	# Target for first half: ceil(total / 2).
	var half_a_target: int = ceili(float(total) / 2.0)

	# Build fresh slot arrays.
	var size_a: int = get_chest_slot_count(_chests[key].get("type", "regular") as String)
	var size_b: int = size_a
	if _chests.has(key_b):
		size_b = get_chest_slot_count(_chests[key_b].get("type", "regular") as String)

	var slots_a: Array = []
	for _i: int in range(size_a):
		slots_a.append({"def_id": "", "count": 0})
	var slots_b: Array = []
	for _i: int in range(size_b):
		slots_b.append({"def_id": "", "count": 0})

	# Helper: insert 'amount' of 'def_id' into 'target_slots', returns actual placed.
	# (inner function via nested approach — GDScript 4 allows this with a local func)
	var placed_a: int = 0
	var placed_b: int = 0

	for item: Dictionary in all_items:
		var def_id: String = item["def_id"]
		var remaining: int = item["count"]

		# Fill into slots_a up to half_a_target.
		if placed_a < half_a_target and remaining > 0:
			for sl: Dictionary in slots_a:
				if remaining <= 0 or placed_a >= half_a_target:
					break
				if sl.get("def_id", "") == "" or sl.get("def_id", "") == def_id:
					if sl.get("def_id", "") == "":
						sl["def_id"] = def_id
						sl["count"] = 0
					var can_add: int = mini(STACK_MAX - sl["count"],
					                        mini(remaining, half_a_target - placed_a))
					if can_add > 0:
						sl["count"] += can_add
						remaining -= can_add
						placed_a += can_add

		# Remainder goes into slots_b.
		for sl: Dictionary in slots_b:
			if remaining <= 0:
				break
			if sl.get("def_id", "") == "" or sl.get("def_id", "") == def_id:
				if sl.get("def_id", "") == "":
					sl["def_id"] = def_id
					sl["count"] = 0
				var can_add: int = mini(STACK_MAX - sl["count"], remaining)
				if can_add > 0:
					sl["count"] += can_add
					remaining -= can_add
					placed_b += can_add

	_chests[key]["contents"] = slots_a
	_chests[key]["double_chest_partner"] = ""
	if _chests.has(key_b):
		_chests[key_b]["contents"] = slots_b
		_chests[key_b]["double_chest_partner"] = ""

	# Persist.
	if WorldSave.is_open():
		var ca: Dictionary = _chests[key] as Dictionary
		WorldSave.save_chest(pos, ca["type"] as String, bool(ca["locked"]), var_to_bytes(slots_a), "")
		if _chests.has(key_b):
			var cb: Dictionary = _chests[key_b] as Dictionary
			WorldSave.save_chest(partner_coord, cb["type"] as String, bool(cb["locked"]), var_to_bytes(slots_b), "")


## Return the permanently-revealed recipe dict for a builder.
##
## @param builder_id  The builder UUID.
## @return            {recipe_id: bool} — only permanently unlocked recipes (first-craft).
func get_recipes_known(builder_id: String) -> Dictionary:
	return _recipes_known.get(builder_id, {})


## Return the full set of revealed recipes (permanent + ingredient-present) as an Array.
## Per D-05: a recipe is shown if (a) the builder has crafted it before, OR
## (b) all required ingredients are currently in the builder's inventory.
## Until Plan 03-07a wires the recipe registry, only permanently-known recipes are returned.
##
## @param builder_id  The builder UUID.
## @return            Array of recipe_id Strings.
func get_revealed_recipes(builder_id: String) -> Array:
	if _revealed_recipes_cache.has(builder_id):
		return _revealed_recipes_cache[builder_id].keys()

	# Start with permanently-known recipes.
	var result: Dictionary = {}
	for recipe_id: String in _recipes_known.get(builder_id, {}):
		result[recipe_id] = true

	# Ingredient-presence check (requires registry from Plan 03-07a).
	if not _recipe_registry.is_empty():
		var slots: Array = _inventories.get(builder_id, []) as Array
		for recipe_id: String in _recipe_registry:
			if result.has(recipe_id):
				continue  # Already revealed permanently.
			var recipe: Resource = _recipe_registry[recipe_id]
			if recipe == null:
				continue
			if _builder_has_all_ingredients(builder_id, recipe, slots):
				result[recipe_id] = true

	# Cache the result.
	_revealed_recipes_cache[builder_id] = result
	return result.keys()


## Wire in the recipe registry (called by Plan 03-07a on autoload boot).
## Required for ingredient-presence reveal logic and CRAFT validation.
##
## @param registry  {recipe_id: Recipe Resource}
func register_recipe_registry(registry: Dictionary) -> void:
	_recipe_registry = registry
	# Invalidate all reveal caches — registry changed.
	_revealed_recipes_cache.clear()


## Return the result of matching a crafting grid against registered recipes.
## Pure function — does not mutate state.
##
## @param grid      Array of slot dicts (def_id, count) for the crafting grid.
## @param shapeless true = check shapeless recipes (position-independent);
##                  false = check shaped recipes (position must match exactly).
## @return          Matching Recipe Resource or null.
func match_recipe(grid: Array, shapeless: bool) -> Resource:
	for recipe_id: String in _recipe_registry:
		var recipe: Resource = _recipe_registry[recipe_id]
		if recipe == null:
			continue
		# shaped=false means shapeless; shaped=true means shaped.
		var is_shapeless: bool = not bool(recipe.get("shaped"))
		if is_shapeless != shapeless:
			continue
		if shapeless:
			if _recipe_shapeless_match(grid, recipe):
				return recipe
		else:
			if _recipe_shaped_match(grid, recipe):
				return recipe
	return null


## Link two adjacent same-tier chests as a double-chest pair.
## Validates that both chests exist and share the same tier before linking.
## Called by ChestEntity._check_for_double_chest_partner (Plan 03-06).
##
## @param chunk_a  Coordinate of the first chest half.
## @param chunk_b  Coordinate of the second chest half.
## @return         true if linked; false if either chest missing or tier mismatch.
func set_double_chest_partner(chunk_a: Vector3i, chunk_b: Vector3i) -> bool:
	var key_a := _coord_key(chunk_a)
	var key_b := _coord_key(chunk_b)
	if not _chests.has(key_a) or not _chests.has(key_b):
		return false
	if _chests[key_a].get("type", "") != _chests[key_b].get("type", ""):
		return false  # Only same-tier chests may pair (T-03-06-CH-02).
	_chests[key_a]["double_chest_partner"] = str(chunk_b)
	_chests[key_b]["double_chest_partner"] = str(chunk_a)
	if WorldSave.is_open():
		WorldSave.mark_chunk_dirty(chunk_a)
		WorldSave.mark_chunk_dirty(chunk_b)
	return true


## Unregister a standalone (or paired) chest from in-memory state and WorldSave.
## If the chest has a double-chest partner, the partner's link is severed so it becomes
## a singleton; the partner's contents are preserved unmodified.
## Called by ChestEntity.on_break (Plan 03-06) for standalone chests.
##
## @param chunk_coord  The chunk coordinate of the chest to remove.
func unregister_chest(chunk_coord: Vector3i) -> void:
	var key := _coord_key(chunk_coord)
	if not _chests.has(key):
		return

	var partner_str: String = _chests[key].get("double_chest_partner", "")
	if not partner_str.is_empty():
		# Sever the partner's link so it remains a standalone chest.
		var partner_coord := _parse_coord_key(partner_str)
		var key_p := _coord_key(partner_coord)
		if _chests.has(key_p):
			_chests[key_p]["double_chest_partner"] = ""
			if WorldSave.is_open():
				WorldSave.mark_chunk_dirty(partner_coord)

	_chests.erase(key)
	if WorldSave.is_open():
		WorldSave.mark_chunk_dirty(chunk_coord)


## Break one half of a double-chest: splits contents proportionally between the two halves,
## drops the broken half's items (caller handles DroppedItem spawning), severs the pairing,
## and retains the surviving half's items unchanged.
##
## Slots [0..half_capacity-1] are assigned to the broken half (these items should be dropped
## by the caller via get_chest_contents after this call). Slots [half_capacity..] go to partner.
##
## After this call: broken half is removed from _chests; partner half is standalone (partner
## link cleared) with items [half_capacity..end).
##
## Called by ChestEntity.on_break for double-chest halves (Plan 03-06).
##
## @param chunk_coord  Coordinate of the half that is being broken.
func unregister_chest_half(chunk_coord: Vector3i) -> void:
	var key := _coord_key(chunk_coord)
	if not _chests.has(key):
		return

	var partner_str: String = _chests[key].get("double_chest_partner", "")
	if partner_str.is_empty():
		# Fallback: no partner; treat as standalone unregister.
		unregister_chest(chunk_coord)
		return

	var partner_coord := _parse_coord_key(partner_str)
	var key_p := _coord_key(partner_coord)
	var half_capacity: int = CHEST_SLOT_COUNT.get(_chests[key].get("type", "regular") as String, 48)

	# Collect all items from both halves.
	var all_items: Array = []
	for s: Dictionary in _chests[key].get("contents", []):
		if s.get("def_id", "") != "" and s.get("count", 0) > 0:
			all_items.append({"def_id": s["def_id"], "count": s["count"]})
	if _chests.has(key_p):
		for s: Dictionary in _chests[key_p].get("contents", []):
			if s.get("def_id", "") != "" and s.get("count", 0) > 0:
				all_items.append({"def_id": s["def_id"], "count": s["count"]})

	# Same proportional split as break_double_chest: first ceil(total/2) items go to broken half
	# (will be dropped by caller); remainder goes to partner (stays in inventory).
	var total: int = 0
	for item: Dictionary in all_items:
		total += item.get("count", 0)
	var half_a_target: int = ceili(float(total) / 2.0)

	# Rebuild partner slots with the second half of items.
	var size_p: int = half_capacity
	if _chests.has(key_p):
		size_p = CHEST_SLOT_COUNT.get(_chests[key_p].get("type", "regular") as String, 48)

	var slots_p: Array = []
	for _i: int in range(size_p):
		slots_p.append({"def_id": "", "count": 0})

	# Build drop slots for the broken half (for caller to iterate).
	var slots_broken: Array = []
	for _i: int in range(half_capacity):
		slots_broken.append({"def_id": "", "count": 0})

	var placed_broken: int = 0
	for item: Dictionary in all_items:
		var def_id: String = item["def_id"]
		var remaining: int = item["count"]

		# Fill broken-half slots up to half_a_target.
		if placed_broken < half_a_target and remaining > 0:
			for sl: Dictionary in slots_broken:
				if remaining <= 0 or placed_broken >= half_a_target:
					break
				if sl.get("def_id", "") == "" or sl.get("def_id", "") == def_id:
					if sl.get("def_id", "") == "":
						sl["def_id"] = def_id
						sl["count"] = 0
					var can_add: int = mini(STACK_MAX - sl["count"], mini(remaining, half_a_target - placed_broken))
					if can_add > 0:
						sl["count"] += can_add
						remaining -= can_add
						placed_broken += can_add

		# Remainder into partner slots.
		for sl: Dictionary in slots_p:
			if remaining <= 0:
				break
			if sl.get("def_id", "") == "" or sl.get("def_id", "") == def_id:
				if sl.get("def_id", "") == "":
					sl["def_id"] = def_id
					sl["count"] = 0
				var can_add: int = mini(STACK_MAX - sl["count"], remaining)
				if can_add > 0:
					sl["count"] += can_add
					remaining -= can_add

	# Write broken half's drop slots back so caller can iterate get_chest_contents().
	_chests[key]["contents"] = slots_broken
	_chests[key]["double_chest_partner"] = ""

	# Update partner to standalone with trimmed contents.
	if _chests.has(key_p):
		_chests[key_p]["contents"] = slots_p
		_chests[key_p]["double_chest_partner"] = ""
		if WorldSave.is_open():
			var cp: Dictionary = _chests[key_p] as Dictionary
			WorldSave.save_chest(partner_coord, cp["type"] as String,
				bool(cp["locked"]), var_to_bytes(slots_p), "")

	# Remove the broken half.
	_chests.erase(key)
	if WorldSave.is_open():
		WorldSave.mark_chunk_dirty(chunk_coord)


## Unit-test helper: override the survival/sandbox mode without a live WorldSave.
## Call with "" to restore normal Features.is_survival_mode() behaviour.
## @param mode  "survival", "sandbox", or "".
func _test_set_mode_override(mode: String) -> void:
	_test_mode_override = mode


# ─── Private appliers ─────────────────────────────────────────────────────────

## Apply an ADD event: add count items of def_id to a builder's or chest's inventory.
## Two-pass: top-up existing stacks first, then fill empty slots.
## Returns false (with overflow handling) if items don't fit.
func _apply_add(event: Dictionary) -> bool:
	var def_id: String = event.get("def_id", "")
	var count: int = event.get("count", 1)

	if def_id.is_empty() or count <= 0:
		push_warning("Inventory._apply_add: invalid def_id or count.")
		return false

	# Determine target: builder inventory or chest.
	if event.has("chest_coord"):
		return _apply_add_to_chest(event.get("chest_coord", Vector3i.ZERO) as Vector3i, def_id, count)

	var builder_id: String = event.get("builder_id", "")
	if builder_id.is_empty():
		push_warning("Inventory._apply_add: missing builder_id.")
		return false

	_ensure_inventory(builder_id)
	var slots: Array = _inventories[builder_id]

	# Record original requested count for item_added signal (emitted before inventory_changed).
	var original_count: int = count

	# Respect slot hint if provided.
	var slot_hint: int = event.get("slot", -1)
	if slot_hint >= 0 and slot_hint < SLOT_COUNT:
		var sl: Dictionary = slots[slot_hint]
		if (sl.get("def_id", "") == "" or sl.get("def_id", "") == def_id) and sl.get("count", 0) < STACK_MAX:
			if sl.get("def_id", "") == "":
				sl["def_id"] = def_id
				sl["count"] = 0
			var can_add := mini(STACK_MAX - sl["count"], count)
			sl["count"] += can_add
			count -= can_add

	if count <= 0:
		item_added.emit(builder_id, def_id, original_count)
		inventory_changed.emit(builder_id)
		return true

	# Pass 1: top up existing stacks of the same def_id.
	for sl: Dictionary in slots:
		if sl.get("def_id", "") == def_id and sl.get("count", 0) < STACK_MAX:
			var can_add := mini(STACK_MAX - sl["count"], count)
			sl["count"] += can_add
			count -= can_add
			if count <= 0:
				break

	# Pass 2: fill empty slots.
	if count > 0:
		for sl: Dictionary in slots:
			if sl.get("def_id", "") == "":
				sl["def_id"] = def_id
				var can_add := mini(STACK_MAX, count)
				sl["count"] = can_add
				count -= can_add
				if count <= 0:
					break

	# Handle overflow.
	if count > 0:
		if _can_show_full_tip():
			Toasts.show("ui.inventory.full", "info")
		inventory_changed.emit(builder_id)
		return false

	item_added.emit(builder_id, def_id, original_count)
	inventory_changed.emit(builder_id)
	# Invalidate reveal cache — def_id may be a recipe ingredient.
	_invalidate_reveal_cache(builder_id, def_id)
	return true


## Add items to a chest inventory (not a builder's).
func _apply_add_to_chest(chest_coord: Vector3i, def_id: String, count: int) -> bool:
	var key := _coord_key(chest_coord)
	if not _chests.has(key):
		# Auto-create a regular chest slot for convenience in tests.
		register_chest(chest_coord, "regular")

	var slots: Array = _chests[key]["contents"]

	# Pass 1: top up existing stacks.
	for sl: Dictionary in slots:
		if sl.get("def_id", "") == def_id and sl.get("count", 0) < STACK_MAX:
			var can_add := mini(STACK_MAX - sl["count"], count)
			sl["count"] += can_add
			count -= can_add
			if count <= 0:
				break

	# Pass 2: empty slots.
	if count > 0:
		for sl: Dictionary in slots:
			if sl.get("def_id", "") == "":
				sl["def_id"] = def_id
				var can_add := mini(STACK_MAX, count)
				sl["count"] = can_add
				count -= can_add
				if count <= 0:
					break

	# Mark chunk dirty.
	if WorldSave.is_open():
		WorldSave.mark_chunk_dirty(chest_coord)

	return count <= 0


## Apply a REMOVE event: decrement count items of def_id (or from a specific slot).
## Returns false if insufficient items.
func _apply_remove(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	var count: int = event.get("count", 1)

	if builder_id.is_empty():
		return false

	_ensure_inventory(builder_id)
	var slots: Array = _inventories[builder_id]

	# Slot-specific removal.
	if event.has("slot"):
		var slot_idx: int = event.get("slot", -1)
		if slot_idx < 0 or slot_idx >= SLOT_COUNT:
			return false
		var sl: Dictionary = slots[slot_idx]
		var available: int = sl.get("count", 0)
		if available == 0:
			return true  # Removing from empty slot is a no-op.
		var to_remove: int = mini(available, count)
		sl["count"] -= to_remove
		if sl["count"] <= 0:
			sl["def_id"] = ""
			sl["count"] = 0
		inventory_changed.emit(builder_id)
		return true

	# def_id-based removal.
	var def_id: String = event.get("def_id", "")
	if def_id.is_empty():
		return false

	# Check we have enough.
	var available: int = 0
	for sl: Dictionary in slots:
		if sl.get("def_id", "") == def_id:
			available += sl.get("count", 0)
	if available < count:
		return false

	# Decrement.
	var remaining: int = count
	for sl: Dictionary in slots:
		if sl.get("def_id", "") == def_id and remaining > 0:
			var take := mini(sl.get("count", 0), remaining)
			sl["count"] -= take
			remaining -= take
			if sl["count"] <= 0:
				sl["def_id"] = ""
				sl["count"] = 0

	inventory_changed.emit(builder_id)
	_invalidate_reveal_cache(builder_id, def_id)
	return true


## Apply a MOVE event: move slot content to an empty target slot.
## Resolve a (grid, chest_id, slot_index) tuple to the underlying slot Array
## (so callers can read or write that index). Returns null if invalid.
##   - grid="inventory" or "" → builder inventory for builder_id.
##   - grid="chest"           → _chests[chest_id]["contents"].
## chest_id is the coord-key form ("x,y,z" from _coord_key).
func _resolve_slot_array(grid: String, builder_id: String, chest_id: String) -> Variant:
	if grid == "chest":
		# ChestEntity uses "chest_X_Y_Z" as its stable id; Inventory._chests is
		# keyed by _coord_key which produces "X_Y_Z" (no prefix). Strip the
		# prefix so the lookup succeeds regardless of which format was passed.
		var key: String = chest_id
		if key.begins_with("chest_"):
			key = key.substr(6)
		if key.is_empty() or not _chests.has(key):
			return null
		return _chests[key]["contents"]
	if grid == "crafting_2x2" or grid == "crafting_3x3":
		# Crafting grids live in the per-session _floating_crafting_grid buffer.
		# Lazy-init with the right number of empty slots so writes succeed.
		var expected_size: int = 4 if grid == "crafting_2x2" else 9
		var arr: Array = _floating_crafting_grid.get(grid, [])
		if arr.size() != expected_size:
			arr = []
			for _i: int in range(expected_size):
				arr.append({"def_id": "", "count": 0})
			_floating_crafting_grid[grid] = arr
		return arr
	# Default to builder inventory.
	if builder_id.is_empty():
		return null
	_ensure_inventory(builder_id)
	return _inventories[builder_id]


func _apply_move(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	var from_slot: int = event.get("from_slot", -1)
	var to_slot: int = event.get("to_slot", -1)
	var from_grid: String = event.get("from_grid", "inventory")
	var to_grid: String = event.get("to_grid", "inventory")
	var from_chest_id: String = event.get("from_chest_id", "")
	var to_chest_id: String = event.get("to_chest_id", "")

	var src_slots: Variant = _resolve_slot_array(from_grid, builder_id, from_chest_id)
	var dst_slots: Variant = _resolve_slot_array(to_grid, builder_id, to_chest_id)
	if src_slots == null or dst_slots == null:
		return false
	if from_slot < 0 or from_slot >= (src_slots as Array).size():
		return false
	if to_slot < 0 or to_slot >= (dst_slots as Array).size():
		return false

	# No-op: source and target are the same slot in the same array.
	if src_slots == dst_slots and from_slot == to_slot:
		return false

	var src: Dictionary = (src_slots as Array)[from_slot]
	var dst: Dictionary = (dst_slots as Array)[to_slot]

	if src.get("def_id", "") == "":
		return false  # Source is empty.
	if dst.get("def_id", "") != "":
		return false  # Target not empty — use SWAP instead.

	dst["def_id"] = src["def_id"]
	dst["count"]  = src["count"]
	src["def_id"] = ""
	src["count"]  = 0

	# Persist any chest contents that changed.
	if from_grid == "chest":
		_persist_chest(from_chest_id)
	if to_grid == "chest" and to_chest_id != from_chest_id:
		_persist_chest(to_chest_id)

	inventory_changed.emit(builder_id)
	return true


## Write the current state of a chest back to WorldSave.
func _persist_chest(chest_id: String) -> void:
	# Strip the "chest_" prefix if the caller passed the ChestEntity id form.
	var key: String = chest_id
	if key.begins_with("chest_"):
		key = key.substr(6)
	if key.is_empty() or not _chests.has(key):
		return
	if not WorldSave.is_open():
		return
	var rec: Dictionary = _chests[key]
	var chest_coord: Vector3i = _parse_coord_key(key)
	var slots: Array = rec.get("contents", [])
	var tier: String = rec.get("type", "regular") as String
	var locked: bool = rec.get("locked", false)
	WorldSave.save_chest(chest_coord, tier, locked, var_to_bytes(slots), "")


## Apply a SPLIT event: split a stack in half (floor/ceil).
func _apply_split(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	var from_slot: int = event.get("from_slot", -1)
	var to_slot: int = event.get("to_slot", -1)

	if builder_id.is_empty() or from_slot < 0 or from_slot >= SLOT_COUNT or to_slot < 0 or to_slot >= SLOT_COUNT:
		return false

	_ensure_inventory(builder_id)
	var slots: Array = _inventories[builder_id]
	var src: Dictionary = slots[from_slot]
	var dst: Dictionary = slots[to_slot]

	if src.get("def_id", "") == "" or src.get("count", 0) <= 1:
		return false  # Nothing to split.

	var src_def: String = src["def_id"]

	# Destination must be empty OR same def_id with room.
	if dst.get("def_id", "") != "" and dst.get("def_id", "") != src_def:
		return false

	var total: int = src.get("count", 0)
	var give: int = ceili(float(total) / 2.0)
	var keep: int = total - give

	# Check dst has room.
	if dst.get("def_id", "") == src_def:
		if dst.get("count", 0) + give > STACK_MAX:
			give = STACK_MAX - dst.get("count", 0)
			keep = total - give

	src["count"] = keep
	if dst.get("def_id", "") == "":
		dst["def_id"] = src_def
		dst["count"] = 0
	dst["count"] += give

	inventory_changed.emit(builder_id)
	return true


## Apply a SWAP event: exchange two non-empty slots' contents.
func _apply_swap(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	# inventory_slot.gd dispatches SWAP using the same from_slot/to_slot/
	# from_grid/to_grid keys as MOVE (its _drop_data picks the kind based on
	# whether the destination already has an item). Fall back to legacy
	# slot_a/slot_b naming if those are missing.
	var slot_a: int = event.get("from_slot", event.get("slot_a", -1))
	var slot_b: int = event.get("to_slot", event.get("slot_b", -1))
	var grid_a: String = event.get("from_grid", "inventory")
	var grid_b: String = event.get("to_grid", "inventory")
	var chest_id_a: String = event.get("from_chest_id", "")
	var chest_id_b: String = event.get("to_chest_id", "")

	var slots_a: Variant = _resolve_slot_array(grid_a, builder_id, chest_id_a)
	var slots_b: Variant = _resolve_slot_array(grid_b, builder_id, chest_id_b)
	if slots_a == null or slots_b == null:
		return false
	if slot_a < 0 or slot_a >= (slots_a as Array).size():
		return false
	if slot_b < 0 or slot_b >= (slots_b as Array).size():
		return false

	var tmp_def: String = (slots_a as Array)[slot_a]["def_id"]
	var tmp_count: int  = (slots_a as Array)[slot_a]["count"]
	(slots_a as Array)[slot_a]["def_id"]  = (slots_b as Array)[slot_b]["def_id"]
	(slots_a as Array)[slot_a]["count"]   = (slots_b as Array)[slot_b]["count"]
	(slots_b as Array)[slot_b]["def_id"]  = tmp_def
	(slots_b as Array)[slot_b]["count"]   = tmp_count

	if grid_a == "chest":
		_persist_chest(chest_id_a)
	if grid_b == "chest" and chest_id_b != chest_id_a:
		_persist_chest(chest_id_b)

	inventory_changed.emit(builder_id)
	return true


## Apply a SINGLE_TAKE event: take exactly 1 item from a slot and deposit it
## into the first available builder-inventory slot (or merge into an existing
## stack of the same def_id). Source can be any grid (chest, crafting, builder).
##
## Event keys (both 'from' and 'slot' supported for back-compat): from/slot,
## from_grid, from_chest_id, builder_id.
func _apply_single_take(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	var slot_idx: int = event.get("from", event.get("slot", -1))
	var from_grid: String = event.get("from_grid", "inventory")
	var from_chest_id: String = event.get("from_chest_id", "")

	var src_slots: Variant = _resolve_slot_array(from_grid, builder_id, from_chest_id)
	if src_slots == null:
		return false
	if slot_idx < 0 or slot_idx >= (src_slots as Array).size():
		return false
	var src: Dictionary = (src_slots as Array)[slot_idx]
	if src.get("count", 0) <= 0:
		return false

	# Directional routing: right-click source picks the most useful destination.
	#   inventory  → crafting_2x2 (if any space) else nothing useful → no-op
	#   chest      → builder inventory
	#   crafting_* → builder inventory
	# Picking inventory→crafting matches the classic "right-click while holding
	# in a recipe slot" intuition without needing a held-cursor item concept.
	var src_def: String = src["def_id"]
	var dst_slots: Array
	if from_grid == "inventory":
		# Route to crafting_2x2 (pre-init via get_crafting_grid).
		dst_slots = get_crafting_grid("crafting_2x2")
	else:
		# Default: route to builder inventory.
		if builder_id.is_empty():
			return false
		_ensure_inventory(builder_id)
		dst_slots = _inventories[builder_id]
	var dst_idx: int = -1
	# Merge into existing same-id stack first.
	for i: int in range(dst_slots.size()):
		if (dst_slots[i] as Dictionary).get("def_id", "") == src_def \
				and (dst_slots[i] as Dictionary).get("count", 0) > 0:
			dst_idx = i
			break
	# Else first empty slot.
	if dst_idx == -1:
		for i: int in range(dst_slots.size()):
			if (dst_slots[i] as Dictionary).get("def_id", "") == "":
				dst_idx = i
				break
	if dst_idx == -1:
		return false  # Destination is full.

	var dst: Dictionary = dst_slots[dst_idx]
	if dst.get("def_id", "") == "":
		dst["def_id"] = src_def
		dst["count"] = 1
	else:
		dst["count"] = int(dst["count"]) + 1

	src["count"] = int(src["count"]) - 1
	if src["count"] <= 0:
		src["def_id"] = ""
		src["count"] = 0

	if from_grid == "chest":
		_persist_chest(from_chest_id)

	inventory_changed.emit(builder_id)
	return true


## Apply a CRAFT event: consume grid inputs, produce output, mark recipe as known on first craft.
## RESEARCH Anti-Patterns L373: touch ONLY recipe grid slots + output + recipes_known.
func _apply_craft(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	var recipe_id: String = event.get("recipe_id", "")

	if builder_id.is_empty() or recipe_id.is_empty():
		return false

	_ensure_inventory(builder_id)

	# If no recipe registry wired yet (Plan 03-07a), accept the event gracefully.
	if _recipe_registry.is_empty():
		# First-craft unlock (permanent).
		_ensure_recipes_known(builder_id)
		if not _recipes_known[builder_id].get(recipe_id, false):
			_recipes_known[builder_id][recipe_id] = true
			recipe_revealed.emit(builder_id, recipe_id)
		inventory_changed.emit(builder_id)
		return true

	var recipe: Resource = _recipe_registry.get(recipe_id, null)
	if recipe == null:
		push_warning("Inventory._apply_craft: unknown recipe_id '%s'." % recipe_id)
		return false

	# The ingredients live in the floating crafting-grid buffer (moved there by a drag
	# or by CRAFT_AUTOFILL), NOT in the main inventory — so consume from the grid. The
	# previous code looked for a nonexistent `ingredients` Dict and ignored the grid,
	# which produced output for free and left the grid stuck (the plank-craft bug).
	var grid_size: int = int(event.get("grid_size", recipe.get("grid_size") if recipe.get("grid_size") != null else 2))
	var grid_name: String = "crafting_2x2" if grid_size == 2 else "crafting_3x3"
	var grid: Array = get_crafting_grid(grid_name)

	# Validate this recipe actually matches what's in the grid (prevents free crafting).
	var is_shapeless: bool = not bool(recipe.get("shaped"))
	var matched: bool = _recipe_shapeless_match(grid, recipe) if is_shapeless \
		else _recipe_shaped_match(grid, recipe)
	if not matched:
		return false

	# Consume the recipe inputs from the grid buffer.
	var inputs: Variant = recipe.get("inputs")
	if inputs is Array:
		for inp: Dictionary in (inputs as Array):
			_consume_from_grid(grid, str(inp.get("def_id", "")), int(inp.get("count", 1)))
	_floating_crafting_grid[grid_name] = grid

	# Produce output into the main inventory.
	if recipe.has_method("get") and recipe.get("output_def_id") != null:
		var out_def: String = recipe.get("output_def_id")
		var out_count: int = recipe.get("output_count") if recipe.get("output_count") != null else 1
		_apply_add({"kind": "ADD", "builder_id": builder_id, "def_id": out_def, "count": out_count})

	# First-craft permanent unlock.
	_ensure_recipes_known(builder_id)
	if not _recipes_known[builder_id].get(recipe_id, false):
		_recipes_known[builder_id][recipe_id] = true
		recipe_revealed.emit(builder_id, recipe_id)

	inventory_changed.emit(builder_id)
	_invalidate_reveal_cache(builder_id, "")
	return true


## Apply an UNLOCK event: validate key tier, consume key, unlock chest, emit signal.
## Pitfall 6: validation order is strict — check BEFORE consuming anything.
func _apply_unlock(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	var key_def_id: String = event.get("key_def_id", "")

	if builder_id.is_empty() or key_def_id.is_empty():
		return false

	# Resolve chest coordinate and type.
	var chest_coord: Vector3i
	var chest_type: String

	if event.has("chest_coord"):
		chest_coord = event.get("chest_coord", Vector3i.ZERO) as Vector3i
		chest_type = event.get("chest_type", "")
		# Ensure chest is registered (auto-register for tests).
		var key := _coord_key(chest_coord)
		if not _chests.has(key):
			if chest_type.is_empty():
				return false
			# Auto-create chest for validation tests.
			var slot_count := get_chest_slot_count(chest_type)
			var slots: Array = []
			for _i: int in range(slot_count):
				slots.append({"def_id": "", "count": 0})
			_chests[key] = {
				"type":                chest_type,
				"locked":              true,
				"contents":            slots,
				"double_chest_partner": "",
			}
		else:
			chest_type = _chests[key].get("type", chest_type)
	else:
		# Legacy path: chest_id as string.
		var chest_id: String = event.get("chest_id", "")
		if chest_id.is_empty():
			return false
		if not _chests.has(chest_id):
			return false
		chest_type = _chests[chest_id].get("type", "")
		# Parse coord from key.
		chest_coord = _parse_coord_key(chest_id)

	var key := _coord_key(chest_coord)

	# Gate 1: chest must be locked.
	var chest: Dictionary = _chests[key] as Dictionary
	if not chest.get("locked", true):
		return false  # Already unlocked.

	# Gate 2: "regular" tier has no lock.
	if chest_type == "regular":
		return false

	# Gate 3: key tier must match.
	var required: String = REQUIRED_KEY.get(chest_type, "")
	if required.is_empty() or required != key_def_id:
		return false  # Wrong tier (Pitfall 6).

	# Gate 4: builder must have ≥ 1 of the key.
	_ensure_inventory(builder_id)
	var slots: Array = _inventories[builder_id]
	var key_count: int = 0
	for sl: Dictionary in slots:
		if sl.get("def_id", "") == key_def_id:
			key_count += sl.get("count", 0)
	if key_count < 1:
		return false  # No key in inventory.

	# All gates passed — consume 1 key, unlock chest.
	_apply_remove({"builder_id": builder_id, "def_id": key_def_id, "count": 1})
	chest["locked"] = false

	# Persist.
	if WorldSave.is_open():
		WorldSave.save_chest(chest_coord, chest["type"], false, var_to_bytes(chest["contents"]),
		                     chest.get("double_chest_partner", ""))
		WorldSave.mark_chunk_dirty(chest_coord)

	chest_unlocked.emit(chest_coord)
	return true


## Apply a DEATH_DROP event: drain all builder slots into a death pile.
## No-op (returns true) in sandbox mode per D-01.
func _apply_death_drop(event: Dictionary) -> bool:
	if not _is_survival_mode():
		return true  # Sandbox: no death drops per D-01.

	var builder_id: String = event.get("builder_id", "")
	var position: Vector3 = event.get("position", Vector3.ZERO)

	if builder_id.is_empty():
		return false

	_ensure_inventory(builder_id)
	var slots: Array = _inventories[builder_id]

	# Collect non-empty slots.
	var dropped: Array = []
	for sl: Dictionary in slots:
		if sl.get("def_id", "") != "" and sl.get("count", 0) > 0:
			dropped.append({"def_id": sl["def_id"], "count": sl["count"]})
		sl["def_id"] = ""
		sl["count"] = 0

	death_pile_spawned.emit(builder_id, position, dropped)
	inventory_changed.emit(builder_id)
	return true


## Apply a RECIPE_UNLOCK event: permanently reveal a recipe for a builder.
func _apply_recipe_unlock(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	var recipe_id: String = event.get("recipe_id", "")

	if builder_id.is_empty() or recipe_id.is_empty():
		return false

	_ensure_recipes_known(builder_id)
	_recipes_known[builder_id][recipe_id] = true
	_invalidate_reveal_cache(builder_id, "")
	recipe_revealed.emit(builder_id, recipe_id)
	return true


## Apply a CRAFT_AUTOFILL event: validate ingredients, remove from inventory, populate
## the target crafting grid buffer.
##
## T-03-07a-CR-01/CR-02: validate ALL ingredients BEFORE removing anything.
## The buffer write is synchronous — no interleaving (GDScript single-threaded).
##
## @param event  {kind, builder_id, recipe_id, target_grid: "crafting_2x2" | "crafting_3x3"}
func _apply_craft_autofill(event: Dictionary) -> bool:
	var builder_id: String = event.get("builder_id", "")
	var recipe_id: String = event.get("recipe_id", "")
	var target_grid: String = event.get("target_grid", "crafting_2x2")

	if builder_id.is_empty() or recipe_id.is_empty():
		return false
	if not _recipe_registry.has(recipe_id):
		push_warning("Inventory._apply_craft_autofill: unknown recipe_id '%s'." % recipe_id)
		return false
	if not _floating_crafting_grid.has(target_grid):
		push_warning("Inventory._apply_craft_autofill: unknown target_grid '%s'." % target_grid)
		return false

	var recipe: Resource = _recipe_registry[recipe_id]
	if recipe == null:
		return false
	var inputs: Variant = recipe.get("inputs")
	if inputs == null or not inputs is Array:
		return false

	# Gate: validate ALL ingredients before consuming anything (T-03-07a-CR-01).
	for inp: Dictionary in (inputs as Array):
		var need: int = inp.get("count", 1)
		var have: int = _count_in_inventory(builder_id, inp.get("def_id", ""))
		if have < need:
			return false  # Missing ingredients — abort without side effects.

	# All ingredients validated — remove them from inventory.
	for inp: Dictionary in (inputs as Array):
		_apply_remove({
			"builder_id": builder_id,
			"def_id":     inp.get("def_id", ""),
			"count":      inp.get("count", 1),
		})

	# Populate the target grid buffer.
	_floating_crafting_grid[target_grid] = _build_grid_from_recipe(recipe, target_grid)

	inventory_changed.emit(builder_id)
	return true


# ─── Mode gate ────────────────────────────────────────────────────────────────

## Returns the effective survival-mode state, honouring the test override if set.
func _is_survival_mode() -> bool:
	if _test_mode_override != "":
		return _test_mode_override == "survival"
	return Features.is_survival_mode()


# ─── Dirty marking and persistence ────────────────────────────────────────────

## Mark the relevant entity dirty based on the event kind.
func _mark_dirty_for_event(event: Dictionary) -> void:
	var kind: String = event.get("kind", "")
	match kind:
		"UNLOCK":
			# Chest chunk is already marked dirty in _apply_unlock.
			pass
		_:
			var builder_id: String = event.get("builder_id", "")
			if not builder_id.is_empty():
				_dirty_builders[builder_id] = true
				if _persist_timer != null:
					_persist_timer.start()


## Flush all dirty builder blobs to WorldSave immediately.
func _flush_persistence() -> void:
	if not WorldSave.is_open():
		return

	for builder_id: String in _dirty_builders:
		var blob: Dictionary = {
			"slots":         _inventories.get(builder_id, []),
			"recipes_known": _recipes_known.get(builder_id, {}),
		}
		WorldSave.set_world_meta("inventory:" + builder_id, var_to_bytes(blob))

	_dirty_builders.clear()


# ─── Internal helpers ─────────────────────────────────────────────────────────

## Ensure a builder's inventory array exists (lazy init 48 empty slots).
func _ensure_inventory(builder_id: String) -> void:
	if _inventories.has(builder_id):
		return
	var slots: Array = []
	for _i: int in range(SLOT_COUNT):
		slots.append({"def_id": "", "count": 0})
	_inventories[builder_id] = slots

	# Track this builder_id in the known set for attach_world rehydration.
	if WorldSave.is_open():
		var known: Variant = WorldSave.get_world_meta("known_builder_ids")
		var ids: Array = []
		if known is Array:
			ids = known as Array
		if not ids.has(builder_id):
			ids.append(builder_id)
			WorldSave.set_world_meta("known_builder_ids", ids)


## Ensure a builder's recipes_known entry exists.
func _ensure_recipes_known(builder_id: String) -> void:
	if not _recipes_known.has(builder_id):
		_recipes_known[builder_id] = {}


## Load a builder's inventory blob from WorldSave.
func _load_builder_blob(builder_id: String) -> void:
	var raw: Variant = WorldSave.get_world_meta("inventory:" + builder_id)
	if raw == null:
		return
	var decoded: Variant
	if raw is PackedByteArray:
		decoded = bytes_to_var(raw as PackedByteArray)
	else:
		decoded = raw

	# Shape check per T-03-02-INV-02.
	if not decoded is Dictionary:
		push_warning("Inventory._load_builder_blob: bad blob shape for builder '%s' — starting empty." % builder_id)
		return

	var blob := decoded as Dictionary
	var slots: Variant = blob.get("slots", null)
	if slots is Array and (slots as Array).size() == SLOT_COUNT:
		_inventories[builder_id] = slots as Array
	else:
		push_warning("Inventory._load_builder_blob: malformed slots for builder '%s' — starting empty." % builder_id)
		_ensure_inventory(builder_id)

	var rk: Variant = blob.get("recipes_known", null)
	if rk is Dictionary:
		# Shape check: all keys must be String, all values must be bool.
		var valid := true
		for k: Variant in (rk as Dictionary):
			if not k is String or not (rk as Dictionary)[k] is bool:
				valid = false
				break
		if valid:
			_recipes_known[builder_id] = rk as Dictionary
		else:
			push_warning("Inventory._load_builder_blob: malformed recipes_known for builder '%s' — starting empty." % builder_id)


## Return a string key for a chest chunk coordinate.
func _coord_key(coord: Vector3i) -> String:
	return "%d_%d_%d" % [coord.x, coord.y, coord.z]


## Parse a chunk coordinate from a string key.
## Handles both _coord_key format ("%d_%d_%d") and str(Vector3i) format ("(x, y, z)").
func _parse_coord_key(key: String) -> Vector3i:
	# Handle Godot's str(Vector3i) format: "(x, y, z)"
	if key.begins_with("("):
		var trimmed := key.trim_prefix("(").trim_suffix(")")
		var parts := trimmed.split(", ")
		if parts.size() >= 3:
			return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		return Vector3i.ZERO

	# Handle _coord_key format: "x_y_z" (may have negative numbers)
	# For negative numbers like "-1_0_5", split("_") gives ["", "1", "0", "5"] or ["-1","0","5"]
	# Use a regex-free approach: find the 3 integers.
	var parts := key.split("_")
	if parts.size() >= 3:
		return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	return Vector3i.ZERO


## Returns true if the builder currently has all ingredients for the recipe.
## Used by get_revealed_recipes for ingredient-presence reveal (D-05).
func _builder_has_all_ingredients(builder_id: String, recipe: Resource, _slots: Array) -> bool:
	if recipe == null:
		return false
	var inputs: Variant = recipe.get("inputs")
	if inputs == null or not inputs is Array:
		return false
	# Aggregate required counts per def_id (ingredients may repeat across slots).
	var required: Dictionary = {}
	for inp: Dictionary in (inputs as Array):
		var did: String = inp.get("def_id", "")
		var cnt: int = inp.get("count", 1)
		required[did] = required.get(did, 0) + cnt
	# Check builder has enough of each ingredient.
	for did: String in required:
		if _count_in_inventory(builder_id, did) < required[did]:
			return false
	return true


## Returns true if the crafting grid matches the recipe.
func _grid_matches_recipe(grid: Array, _grid_size: int, recipe: Resource) -> bool:
	if recipe == null:
		return false
	if recipe.get("shaped"):
		return _recipe_shaped_match(grid, recipe)
	else:
		return _recipe_shapeless_match(grid, recipe)


## Count how many of a given def_id the builder has across all inventory slots.
## T-03-07a-CR-01: used by CRAFT_AUTOFILL to validate before consuming.
func _count_in_inventory(builder_id: String, def_id: String) -> int:
	if def_id.is_empty():
		return 0
	_ensure_inventory(builder_id)
	var slots: Array = _inventories[builder_id]
	var total: int = 0
	for sl: Dictionary in slots:
		if sl.get("def_id", "") == def_id:
			total += sl.get("count", 0)
	return total


## Check whether a shaped recipe matches the exact grid positions.
## All inputs must have grid[slot].def_id == input.def_id AND count >= input.count.
func _recipe_shaped_match(grid: Array, recipe: Resource) -> bool:
	var inputs: Array = recipe.get("inputs") as Array
	if inputs == null or inputs.is_empty():
		return false
	var required_slots: Dictionary = {}
	for inp: Dictionary in inputs:
		var slot: int = inp.get("slot", -1)
		if slot < 0 or slot >= grid.size():
			return false
		var cell: Dictionary = grid[slot]
		if cell.get("def_id", "") != inp.get("def_id", ""):
			return false
		if cell.get("count", 0) < inp.get("count", 1):
			return false
		required_slots[slot] = true
	# EXACT match: every cell OUTSIDE the recipe pattern must be empty. Without this a grid
	# filled for a larger recipe (pickaxe: slots 0,1,2,4,7) also satisfied a subset recipe
	# (shovel: 1,4,7), and the first subset in registry order won — so tools crafted the wrong
	# item or appeared to "fail". This makes each shaped recipe match only its exact layout.
	for i: int in range(grid.size()):
		if required_slots.has(i):
			continue
		if not str((grid[i] as Dictionary).get("def_id", "")).is_empty():
			return false
	return true


## Check whether a shapeless recipe matches the grid (ingredient presence, any slot).
func _recipe_shapeless_match(grid: Array, recipe: Resource) -> bool:
	var inputs: Array = recipe.get("inputs") as Array
	if inputs == null or inputs.is_empty():
		return false
	# Count all def_ids in the grid.
	var grid_counts: Dictionary = {}
	for cell: Dictionary in grid:
		var did: String = cell.get("def_id", "")
		if not did.is_empty():
			grid_counts[did] = grid_counts.get(did, 0) + cell.get("count", 0)
	# Aggregate required counts per def_id.
	var required: Dictionary = {}
	for inp: Dictionary in inputs:
		var did: String = inp.get("def_id", "")
		required[did] = required.get(did, 0) + inp.get("count", 1)
	# All required must be present in sufficient quantity.
	for did: String in required:
		if grid_counts.get(did, 0) < required[did]:
			return false
	return true


## Decrement `count` of `def_id` from a crafting-grid buffer, draining across slots
## and clearing emptied slots. Mutates `grid` in place. Used by _apply_craft to consume
## the ingredients that were dragged (or auto-filled) into the grid.
func _consume_from_grid(grid: Array, def_id: String, count: int) -> void:
	var remaining: int = count
	for slot: Dictionary in grid:
		if remaining <= 0:
			break
		if str(slot.get("def_id", "")) == def_id:
			var have: int = int(slot.get("count", 0))
			var take: int = mini(have, remaining)
			slot["count"] = have - take
			remaining -= take
			if int(slot["count"]) <= 0:
				slot["def_id"] = ""
				slot["count"] = 0


## Build a crafting grid Array from a recipe's inputs.
## For shaped recipes: place each input at its slot index; unfilled slots are {}.
## For shapeless recipes: fill slots sequentially from index 0.
##
## @param recipe       The Recipe resource (duck-typed).
## @param target_grid  "crafting_2x2" or "crafting_3x3" — determines grid size.
## @return             Array of {def_id, count} dicts (or {} for empty slots).
func _build_grid_from_recipe(recipe: Resource, target_grid: String) -> Array:
	var size: int = 4 if target_grid == "crafting_2x2" else 9
	var grid: Array = []
	for _i: int in size:
		grid.append({})

	var is_shaped: bool = recipe.get("shaped") as bool
	var inputs: Array = recipe.get("inputs") as Array

	if is_shaped:
		for inp: Dictionary in inputs:
			var slot: int = inp.get("slot", -1)
			if slot >= 0 and slot < size:
				grid[slot] = {"def_id": inp.get("def_id", ""), "count": inp.get("count", 1)}
	else:
		var idx: int = 0
		for inp: Dictionary in inputs:
			var remaining: int = inp.get("count", 1)
			var did: String = inp.get("def_id", "")
			while remaining > 0 and idx < size:
				var place: int = mini(remaining, 64)
				grid[idx] = {"def_id": did, "count": place}
				remaining -= place
				idx += 1

	return grid


## Check and update the "inventory full" toast cooldown (Pitfall 8).
## Returns true and updates the timestamp if enough time has elapsed.
func _can_show_full_tip() -> bool:
	var elapsed: float = 0.0
	if Engine.has_singleton("WorldClock"):
		elapsed = Engine.get_singleton("WorldClock").elapsed_seconds
	else:
		elapsed = Time.get_ticks_msec() / 1000.0
	if elapsed - _last_full_tip_tick > FULL_TIP_COOLDOWN_S:
		_last_full_tip_tick = elapsed
		return true
	return false


## Invalidate the reveal cache for a builder when a slot's def_id changes.
## Per Pitfall 7: until Plan 03-07a wires the recipe registry, always invalidate.
func _invalidate_reveal_cache(builder_id: String, _def_id_changed: String) -> void:
	_revealed_recipes_cache.erase(builder_id)


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_day_boundary(_day_index: int) -> void:
	# Belt-and-braces flush every Cubicraftia day (per Pitfall 1 / T-03-02-INV-06).
	_flush_persistence()


func _on_tool_worn_out(tool_id: String, _instance_id: String) -> void:
	# When ToolWear.worn_out fires, find and remove the worn tool from all inventories.
	for builder_id: String in _inventories:
		var slots: Array = _inventories[builder_id]
		for sl: Dictionary in slots:
			if sl.get("def_id", "") == tool_id:
				sl["def_id"] = ""
				sl["count"] = 0
				inventory_changed.emit(builder_id)
				break
