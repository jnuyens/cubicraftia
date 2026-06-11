# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# death_pile.gd — Single composite entity holding a builder's dropped inventory on death.
#
# Per DOCS.md §5.4 + D-11: exactly ONE DeathPile spawns on death, never 48 DroppedItems.
# The pile is a StaticBody3D (no physics tumble per 03-PATTERNS.md L889) with:
#   - Area3D (walk-through pickup — body_entered fires AddToInventory event)
#   - OmniLight3D (#F5C30D glow per UI-SPEC L78)
#   - MultiMeshInstance3D (up to 16 stacked brick instances for visual "heap" per D-11)
#
# Despawn: 2 Cubicraftia days after spawn (DESPAWN_AFTER_DAYS × SECONDS_PER_DAY).
# Game-time used (not wall-clock) per RESEARCH Pitfall 2 / T-03-04-DEATH-02.
#
# Walk-through pickup:
#   - On body_entered (builder walks through the Area3D), attempt Inventory.ADD for each
#     slot. Overflow entries remain. If all contents drained: despawn immediately.
#   - Per RESEARCH Pitfall 8: DeathPile does NOT show its own "inventory full" toast;
#     that toast is rate-limited inside the Inventory autoload.
#
# Threat mitigations:
#   T-03-04-DEATH-02 (despawn timer vs game-close): uses WorldClock.elapsed_seconds
#   T-03-04-DEATH-03 (void-fall raycast): pile spawns at surface coords (Builder handles)
#
# References:
#   DOCS.md §4.3 — dropped-item glow (OmniLight3D)
#   DOCS.md §5.4 — HP=0 → drop all → single DeathPile
#   03-CONTEXT.md D-11 — single composite entity
#   03-CONTEXT.md D-14 — 2-Cubicraftia-day despawn
#   03-UI-SPEC.md L78 — glow colour #F5C30D, 0.6 energy, 2 m range
#   03-PATTERNS.md L866-897 — DeathPile analog

class_name DeathPile
extends StaticBody3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Pile despawns after this many Cubicraftia days (≈ 30 real minutes per day).
const DESPAWN_AFTER_DAYS: float = 2.0

## Auto-pickup radius: walk within this distance to trigger the Area3D body_entered.
const INTERACT_RANGE_M: float = 1.0

## Maximum number of MultiMesh instances rendered in the stacked-bricks heap (Tier-3 budget).
const MAX_MESH_INSTANCES: int = 16

## Glow colour #F5C30D (accent yellow) per UI-SPEC L78 + L116.
const GLOW_COLOR: Color = Color(0.961, 0.765, 0.051, 1.0)

## Normal glow energy per UI-SPEC L78.
const GLOW_ENERGY_NORMAL: float = 0.6

## Tier-3 reduced glow energy per 03-PATTERNS.md L1045.
const GLOW_ENERGY_TIER3: float = 0.3

## Glow range in metres per UI-SPEC L78.
const GLOW_RANGE_M: float = 2.0

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when pickup attempt runs. Payload: number of slot entries still remaining.
signal contents_drained(remaining: int)

## Emitted when the pile is about to queue_free (despawn or fully picked up).
signal despawned()

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _pickup_area: Area3D = $PickupArea
@onready var _glow: OmniLight3D = $Glow
@onready var _composite_mesh: MultiMeshInstance3D = $CompositeMesh

# ─── State ────────────────────────────────────────────────────────────────────

## Contents: Array[Dictionary] of {def_id: String, count: int}, one per non-empty slot.
var _contents: Array = []

## WorldClock.elapsed_seconds at spawn time (game-clock despawn timer — Pitfall 2).
var _spawn_tick: float = 0.0

## Reference to the MainScene (for debug / future extension).
var _main_scene: Node = null

## Builder UUID whose death spawned this pile.
var _builder_id: String = ""

## True once queue_free has been called (guard against double-free).
var _despawned: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Record game-time at spawn (Pitfall 2: use WorldClock.elapsed_seconds, not wall-clock).
	_spawn_tick = WorldClock.elapsed_seconds

	# Wire the walk-through pickup trigger.
	if _pickup_area != null:
		_pickup_area.body_entered.connect(_on_body_entered)

	# Register in group so test_death_respawn.gd (and Plan 03-11 cleanup) can find piles.
	add_to_group("death_pile")


func _process(_delta: float) -> void:
	if _despawned:
		return
	# Despawn when 2 Cubicraftia days of game-time have elapsed since spawn (Pitfall 2).
	var elapsed_game_s: float = WorldClock.elapsed_seconds - _spawn_tick
	if elapsed_game_s > DESPAWN_AFTER_DAYS * WorldClock.SECONDS_PER_DAY:
		_despawn()


# ─── Public API ───────────────────────────────────────────────────────────────

## Called by main_scene.spawn_death_pile immediately after instantiation.
## Sets the contents, builder_id, and world position; configures glow + mesh heap.
##
## @param contents    Array[Dictionary] of {def_id, count} — non-empty inventory slots.
## @param builder_id  UUID of the builder whose death spawned this pile.
## @param world_pos   World-space position for the pile.
func set_contents(contents: Array, builder_id: String, world_pos: Vector3) -> void:
	_contents = contents.duplicate(true)
	_builder_id = builder_id
	global_position = world_pos

	# ── Configure glow ──────────────────────────────────────────────────────
	if _glow != null:
		_glow.light_color = GLOW_COLOR
		# Tier-3 adaptive: reduce glow energy on low-end devices (03-PATTERNS.md L1045).
		var energy: float = GLOW_ENERGY_NORMAL
		if ThermalProbe.has_method("is_tier_3") and ThermalProbe.is_tier_3():
			energy = GLOW_ENERGY_TIER3
		_glow.light_energy = energy
		_glow.omni_range = GLOW_RANGE_M
		_glow.light_cull_mask = 1  # CHANNEL_VISUAL_MASK (STATE.md lighting-channel-partition)

	# ── Configure composite mesh heap ────────────────────────────────────────
	if _composite_mesh != null and _composite_mesh.multimesh != null:
		var count: int = min(_contents.size(), MAX_MESH_INSTANCES)
		_composite_mesh.multimesh.instance_count = count
		# Position each instance at small random offsets to form a "heap" shape.
		for idx: int in range(count):
			var rand_x: float = randf_range(-0.5, 0.5)
			var rand_z: float = randf_range(-0.5, 0.5)
			var stack_y: float = (float(idx) / float(MAX_MESH_INSTANCES)) * 1.2
			var t := Transform3D(Basis.IDENTITY, Vector3(rand_x, stack_y, rand_z))
			_composite_mesh.multimesh.set_instance_transform(idx, t)


## Store the main scene reference (called by main_scene.spawn_death_pile).
func set_main_scene(scene: Node) -> void:
	_main_scene = scene


# ─── Private helpers ──────────────────────────────────────────────────────────

## Called when a body (hopefully the Builder) walks through the pickup area.
func _on_body_entered(body: Node) -> void:
	if not (body is Builder):
		return
	_try_drain_into(body as Builder)


## Attempt to drain contents into the builder's inventory via Inventory.apply_event(ADD).
## Items that overflow (inventory full) remain in _contents.
func _try_drain_into(builder: Builder) -> void:
	var remaining: Array = []
	for entry: Dictionary in _contents:
		var def_id: String = entry.get("def_id", "")
		var count: int = entry.get("count", 0)
		if def_id.is_empty() or count <= 0:
			continue
		var ok: bool = Inventory.apply_event({
			"kind": "ADD",
			"builder_id": builder.get_stable_builder_id(),
			"def_id": def_id,
			"count": count,
		})
		if not ok:
			# Inventory returned false (full or overflow). Keep this entry.
			remaining.append({"def_id": def_id, "count": count})

	_contents = remaining
	contents_drained.emit(_contents.size())

	# If all contents were picked up, despawn immediately.
	if _contents.is_empty():
		_despawn()


## Queue-free the pile node and emit the despawned signal.
func _despawn() -> void:
	if _despawned:
		return
	_despawned = true
	despawned.emit()
	queue_free()
