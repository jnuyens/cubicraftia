# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# bed_entity.gd — Placed builder-bed entity: walk-up interact for sleep + bed-bubble registration.
#
# Placed as a StaticBody3D in the world. On _ready, registers with Spawning autoload
# so the bed-bubble (8 m sphere) suppresses hostile spawning and ghost phase-through
# per CONTEXT.md D-10. Unregisters on _exit_tree so stale bed entries never accumulate
# (RESEARCH.md Pitfall 5).
#
# Walk-up + interact pattern (03-PATTERNS.md L951-963):
#   BedEntity is in group "bed_entity". Builder._try_sleep_interact() (Plan 03-04)
#   already polls that group for the nearest bed within INTERACT_RANGE_M and calls
#   WorldClock.start_sleep_lapse(10.0) when the player presses the sleep action.
#   BedEntity does NOT duplicate that input poll; it only updates the walk-up prompt.
#
# Bed-bubble registration (D-10 + RESEARCH Pitfall 5):
#   Spawning.register_bed(global_position) is called in _ready so the 8 m sphere is
#   immediately active for spawn-suppression and ghost-repel.
#   Spawning.unregister_bed(global_position) is called in _exit_tree to remove the
#   entry on break or scene reload.
#
# Threat mitigations:
#   T-03-11-BED-01: starter bed is placed by main_scene at world_spawn — always safe ground.
#   Pitfall 9: Builder._try_sleep_interact polls hostiles_inside_bed_bubble() before allowing
#              lapse start; this entity does not need to cancel a lapse itself.
#
# References:
#   DOCS.md §5.5 — sleep mechanic (10× time lapse + bed-respawn anchor)
#   03-CONTEXT.md D-10 — bed-radius sacred (8 m, any placed bed)
#   03-CONTEXT.md D-12 — solo sleep = accelerated 10× time-lapse
#   03-CONTEXT.md D-15 — starter bed placed at world origin
#   03-PATTERNS.md L949-965 — BedEntity analog
#   03-UI-SPEC.md L76 — walk-up prompt 1.5 m above origin, billboarded
#   03-UI-SPEC.md L43 — bed mesh (placeholder in Phase 3; art pass deferred)

class_name BedEntity
extends StaticBody3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Walk-up interact range in metres (UI-SPEC L76 — matches ChestEntity.INTERACT_RANGE_M).
const INTERACT_RANGE_M: float = 2.0

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _prompt_label: Label3D = $WalkupPrompt

# ─── State ────────────────────────────────────────────────────────────────────

## Whether this bed has been registered into Spawning's bed-bubble index.
## Guards unregister_bed from firing if _ready never completed (e.g. freed before _ready).
var _registered: bool = false

## Whether a builder is currently within INTERACT_RANGE_M.
var _builder_in_range: bool = false

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Register into Spawning's chunk-keyed bed-bubble index (D-10).
	# The 8 m sphere is immediately active for spawn-suppression + ghost-repel.
	Spawning.register_bed(global_position)
	_registered = true

	# Add to group so Builder._try_sleep_interact can find the nearest bed.
	add_to_group("bed_entity")

	# Initialise walk-up prompt label.
	if _prompt_label != null:
		_prompt_label.visible = false
		_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_update_prompt()

	_apply_model()


## Swap the placeholder boxes (mattress/headboard/pillow) for the textured bed model.
## Falls back to the placeholders when the model asset is absent (headless/CI).
func _apply_model() -> void:
	var path := "res://assets/meshes/furniture/bed.glb"
	if not ResourceLoader.exists(path):
		return
	var m := (load(path) as PackedScene).instantiate() as Node3D
	if m == null:
		return
	add_child(m)
	# Scale the bed to ~2 m long, base at y=0, centred on X/Z.
	var ab: AABB = _furniture_aabb(m)
	var longest: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	var sc: float = 2.0 / maxf(longest, 0.01)
	m.scale = Vector3(sc, sc, sc)
	m.position = Vector3(-ab.get_center().x * sc, -ab.position.y * sc, -ab.get_center().z * sc)
	for n: String in ["Mesh", "Headboard", "Pillow"]:
		var ph: Node = get_node_or_null(n)
		if ph is GeometryInstance3D:
			(ph as GeometryInstance3D).visible = false


## Merged local-space AABB of every MeshInstance3D under `root` (static mesh, valid now).
func _furniture_aabb(root: Node3D) -> AABB:
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


func _exit_tree() -> void:
	# Unregister from the bed-bubble index (RESEARCH Pitfall 5 — no stale entries).
	if _registered:
		Spawning.unregister_bed(global_position)
		_registered = false


func _process(_delta: float) -> void:
	# Locate the local builder (Phase 3 is solo; get_first_node_in_group is deterministic).
	var builder: Node = get_tree().get_first_node_in_group("builder")
	if builder == null:
		return

	var dist: float = global_position.distance_to((builder as Node3D).global_position)
	var in_range: bool = dist <= INTERACT_RANGE_M

	# Update prompt visibility only when the in-range state changes.
	if in_range != _builder_in_range:
		_builder_in_range = in_range
		if _prompt_label != null:
			_prompt_label.visible = in_range
		_update_prompt()

	# NOTE: Builder._try_sleep_interact (Plan 03-04) handles the actual sleep action
	# via Input.is_action_just_pressed("sleep_interact") and group "bed_entity".
	# No additional input handling is needed here.


# ─── Private helpers ──────────────────────────────────────────────────────────

## Update the walk-up prompt text based on the current time of day.
## At night: "Press E to sleep". During the day: "Too early to sleep".
func _update_prompt() -> void:
	if _prompt_label == null:
		return
	if WorldClock.is_night():
		_prompt_label.text = tr("ui.bed.sleep_prompt")
	else:
		_prompt_label.text = tr("ui.bed.too_early_prompt")


# ─── Public API ───────────────────────────────────────────────────────────────

## Called externally (e.g. by main_scene at spawn time) to set the initial
## prompt text before the builder is in range — avoids the empty-label flash
## on the first process frame.
func refresh_prompt() -> void:
	_update_prompt()
