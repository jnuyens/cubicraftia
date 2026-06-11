# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# strawberry.gd — Grassland-biome strawberry collectible entity.
#
# A small StaticBody3D placed by main_scene (Plan 03-11) on chunk load when biome is
# GRASSLAND_FOREST and the chunk has not been picked this session (RESEARCH Pattern 5).
#
# Interaction model:
#   - Walk-up: builder approaches within INTERACT_RANGE_M → WalkupPrompt becomes visible.
#   - Pick: E key (desktop) / long-press (mobile) within range → instant pickup into inventory.
#   - On successful pickup: write per-chunk metadata to WorldSave + queue_free.
#   - On failed pickup (inventory full): Inventory.gd emits its own "ui.inventory.full" toast
#     via the existing _can_show_full_tip() cooldown; Strawberry does not emit a toast.
#
# Per-chunk respawn semantics (RESEARCH Pattern 5 + Pitfall 10):
#   WorldSave key: "strawberries:<x>_<y>_<z>" (chunk coord string).
#   Value: PackedByteArray of var_to_bytes({"last_picked_session_id": String, "picked_at_tick": float}).
#   On chunk load (Plan 03-11): if last_picked_session_id == current session_id → don't respawn.
#   Cross-session: respawn allowed (acceptable per D-16 "doesn't repopulate within one session").
#
# Session ID fallback (pre-Plan 03-11):
#   Plan 03-11 writes WorldSave.set_world_meta("session_id", uuid) at world-open before any
#   Strawberry._ready() fires. Until then, Strawberry lazily initialises a session_id from
#   Time.get_unix_time_from_system() and persists it. This race is benign: all strawberries
#   spawning in the same chunk-load cycle read the same sid (first to write wins).
#
# Threat mitigations:
#   T-03-09-DR-03: last_picked_session_id is checked vs current session_id in chunk-load
#                  (Plan 03-11). No within-session re-pick is possible once queue_free'd.
#
# References:
#   03-CONTEXT.md D-16 — strawberry rare super-heal; grassland biome surface spawn
#   03-RESEARCH.md Pattern 5 — per-chunk strawberry metadata (lines 358-364)
#   03-RESEARCH.md Pitfall 10 — last_picked_session_id semantics (lines 461-466)
#   03-UI-SPEC.md L151 — strawberry colours: body #D63828, leaves #5DBB46

class_name Strawberry
extends StaticBody3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Walk-up interact range in metres (mirrors ChestEntity.INTERACT_RANGE_M).
const INTERACT_RANGE_M: float = 2.0

## Heal amount in sync with strawberry.tres (heal_amount = 6 per D-16 super-heal).
## NOTE: the authoritative heal_amount is in strawberry.tres; this const is for
## reference only. Builder.eat_food reads the .tres value at runtime.
const HEAL_AMOUNT: int = 6

## Chunk size in metres — matches Spawning autoload and terrain chunk size.
const CHUNK_SIZE_M: int = 16

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _leaf_mesh: MeshInstance3D = $LeafMesh
@onready var _prompt_label: Label3D = $WalkupPrompt

# ─── State ────────────────────────────────────────────────────────────────────

## Chunk coordinate of this strawberry (computed from global_position in _ready).
var _chunk_coord: Vector3i = Vector3i.ZERO

## Whether a builder is currently within INTERACT_RANGE_M.
var _builder_in_range: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Real strawberry art (replaces the placeholder sphere+box when present).
const _MODEL_PATH: String = "res://assets/meshes/crops/strawberry.glb"
## Target height (m) the model is scaled to.
const _MODEL_HEIGHT_M: float = 0.45


func _ready() -> void:
	_chunk_coord = _world_to_chunk(global_position)
	add_to_group("strawberry")
	# Localise the walk-up prompt (Plan 03-05 owns the translation key).
	_prompt_label.text = tr("ui.strawberry.pickup_prompt")
	_prompt_label.visible = false
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_apply_model()


## Swap the placeholder meshes for the textured strawberry model (art pass). Keeps the
## placeholder as a fallback when the model asset is absent (headless/CI).
func _apply_model() -> void:
	if not ResourceLoader.exists(_MODEL_PATH):
		return
	var m := (load(_MODEL_PATH) as PackedScene).instantiate() as Node3D
	if m == null:
		return
	add_child(m)
	var ab: AABB = _model_aabb(m)
	var sc: float = _MODEL_HEIGHT_M / maxf(ab.size.y, 0.01)
	m.scale = Vector3(sc, sc, sc)
	m.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)
	if _mesh != null:
		_mesh.visible = false
	if _leaf_mesh != null:
		_leaf_mesh.visible = false


## Merged AABB (model-local) of every MeshInstance3D under `root` — static mesh, valid now.
func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv: Transform3D = root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var a: AABB = (inv * (n as MeshInstance3D).global_transform) * (n as MeshInstance3D).mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


func _process(_delta: float) -> void:
	var builder: Node = get_tree().get_first_node_in_group("builder")
	if builder == null:
		return
	var builder_3d: Node3D = builder as Node3D
	if builder_3d == null:
		return
	var dist: float = global_position.distance_to(builder_3d.global_position)
	var in_range: bool = dist <= INTERACT_RANGE_M
	if in_range != _builder_in_range:
		_builder_in_range = in_range
		_prompt_label.visible = in_range
	if in_range and Input.is_action_just_pressed("sleep_interact"):
		_try_pick(builder)
		get_viewport().set_input_as_handled()


# ─── Public API ───────────────────────────────────────────────────────────────

## Called by main_scene (Plan 03-11) to set the chunk coordinate at spawn time.
## If not called before _ready, _chunk_coord is computed from global_position.
func set_chunk_coord(coord: Vector3i) -> void:
	_chunk_coord = coord


# ─── Private helpers ──────────────────────────────────────────────────────────

## Attempt to add 1 strawberry to the builder's inventory and consume this entity.
func _try_pick(builder: Node) -> void:
	var builder_id: String = ""
	if builder.has_method("get_stable_builder_id"):
		builder_id = builder.get_stable_builder_id()
	else:
		builder_id = str(builder.get_meta("builder_id", ""))
	var ok: bool = Inventory.apply_event({
		"kind": "ADD",
		"builder_id": builder_id,
		"def_id": "strawberry",
		"count": 1,
	})
	if ok:
		_record_picked()
		queue_free()
	# else: Inventory.gd shows ui.inventory.full toast via its own _can_show_full_tip() cooldown.


## Write per-chunk pickup metadata to WorldSave so Plan 03-11 can gate respawn.
## Per RESEARCH Pattern 5 + Pitfall 10: stores last_picked_session_id and picked_at_tick.
func _record_picked() -> void:
	var key: String = "strawberries:%d_%d_%d" % [_chunk_coord.x, _chunk_coord.y, _chunk_coord.z]
	var session_id: String = _get_session_id()
	var blob: PackedByteArray = var_to_bytes({
		"last_picked_session_id": session_id,
		"picked_at_tick": WorldClock.elapsed_seconds,
	})
	WorldSave.set_world_meta(key, blob)


## Return the current session ID.
## Prefers NetworkManager.get_session_id() (multiplayer-aware session ID) when a session
## is active (STATE.md decision strawberry-session-id-fallback cleanup, Plan 04-09).
## Falls back to the WorldSave "session_id" meta key written by Plan 03-11, and finally
## generates a timestamp-based token if neither source is available.
func _get_session_id() -> String:
	# Prefer NetworkManager session ID when multiplayer is active (A3 cleanup).
	var _session_token: String = ""
	if is_instance_valid(NetworkManager) and not NetworkManager.get_session_id().is_empty():
		_session_token = NetworkManager.get_session_id()
	if not _session_token.is_empty():
		return _session_token
	# Fall back to WorldSave meta "session_id" (written by Plan 03-11 at world-open).
	var raw: Variant = WorldSave.get_world_meta("session_id")
	if raw == null:
		_session_token = str(int(Time.get_unix_time_from_system()))
		WorldSave.set_world_meta("session_id", _session_token)
		return _session_token
	if raw is PackedByteArray:
		var decoded: Variant = bytes_to_var(raw as PackedByteArray)
		return str(decoded)
	return str(raw)


## Convert a world-space position to chunk coordinates.
## Uses integer division with floori to handle negative coordinates correctly.
func _world_to_chunk(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / float(CHUNK_SIZE_M)),
		floori(world_pos.y / float(CHUNK_SIZE_M)),
		floori(world_pos.z / float(CHUNK_SIZE_M)),
	)
