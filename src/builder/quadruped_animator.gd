extends Node3D
class_name QuadrupedAnimator

## Rigid-piece quadruped animator. Same primitives as the humanoid
## MinifigureAnimator -- only the leg count, walk gait, and attack
## semantics differ. The fl/fr/bl/br naming convention is shared by
## every quadruped mesh set (panda, monkey, gnu, reindeer, giraffe, ...).

const PIECE_NAMES := [
    "panda_leg_fl", "panda_leg_fr",
    "panda_leg_bl", "panda_leg_br",
    "panda_body", "panda_head", "panda_tail",
]

@export var mesh_set: String = "panda"
@export var gait: String = "idle"  ## "idle" | "walk" | "attack"
@export var cadence_hz: float = 2.0
@export var swing_deg: float = 22.0

## Grounding baseline for the rig's local Y. The walk bob is added ON TOP of this so
## the feet stay on the terrain instead of snapping to y=0 every frame. The owner
## (e.g. wildlife.gd) sets this to the offset that drops the rig's feet onto the ground.
@export var base_y: float = 0.0

var _pivots: Dictionary = {}
var _t: float = 0.0
var _attack_t: float = -1.0

## Yaw (radians) that rotates the rig's authored forward axis (layout "facing") onto
## Godot's -Z, which is the direction wildlife.gd's look_at() points the body. Without
## this a rig authored facing -x walks sideways (its flank leads the movement direction).
var _facing_yaw: float = 0.0

func _ready() -> void:
    var layout_path := "res://assets/meshes/avatars/%s/layout.json" % mesh_set
    var layout: Dictionary = _load_layout(layout_path)
    if layout.is_empty():
        push_error("QuadrupedAnimator: failed to load %s" % layout_path)
        return
    _facing_yaw = _yaw_for_facing(String(layout.get("facing", "-z")))
    _build_rig(layout)
    rotation.y = _facing_yaw

## Maps a layout "facing" axis token to the Y rotation that aligns it with -Z (forward).
func _yaw_for_facing(f: String) -> float:
    match f.to_lower():
        "-x": return -PI / 2.0
        "+x", "x": return PI / 2.0
        "+z", "z": return PI
        _: return 0.0  # "-z" (already forward)

func _load_layout(p: String) -> Dictionary:
    if not FileAccess.file_exists(p):
        return {}
    var f := FileAccess.open(p, FileAccess.READ)
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    return parsed if parsed is Dictionary else {}

func _build_rig(layout: Dictionary) -> void:
    var pieces_meta: Dictionary = layout.get("pieces", {})
    for name: String in PIECE_NAMES:
        var meta: Dictionary = pieces_meta.get(name, {})
        var pivot_arr: Array = meta.get("pivot", [0, 0, 0])
        # Blender Z-up (x,y,z) -> Godot Y-up (x, z, -y)
        var pivot_pos := Vector3(float(pivot_arr[0]),
                                 float(pivot_arr[2]),
                                 -float(pivot_arr[1]))
        var pivot := Node3D.new()
        pivot.name = name + "_pivot"
        pivot.position = pivot_pos
        add_child(pivot)
        _pivots[name] = pivot

        var glb_path := "res://assets/meshes/avatars/%s/%s.glb" % [mesh_set, name]
        if not ResourceLoader.exists(glb_path):
            push_warning("piece missing: %s" % glb_path)
            continue
        var scene: PackedScene = load(glb_path)
        pivot.add_child(scene.instantiate())

## Lowest Y (this node's LOCAL frame, BEFORE this node's own scale/rotation) of every
## MeshInstance3D in the assembled rig (i.e. the rig's foot level relative to its origin).
## The owner (wildlife.gd) grounds the panda by setting base_y = -assembled_local_min_y() *
## scale so the rig's lowest piece lands on the feet plane (the body origin), NOT by
## assuming the rig is authored feet-at-origin. Returns 0.0 if the rig has no meshes yet
## (called before _ready built the pieces); 0.0 is the safe identity (no lift).
##
## Measured in IDLE rest pose (no leg swing): the walk bob/leg swing add only millimetres
## below this and ride on top of base_y, so the rest-pose minimum is the stable foot datum.
func assembled_local_min_y() -> float:
    var lo: float = INF
    var stack: Array = [self]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        # Accumulate the local transform of each piece relative to THIS animator (excluding
        # this animator's own transform), so the result is in the rig's own un-scaled frame.
        if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
            var mi := node as MeshInstance3D
            var xf: Transform3D = _local_xform_to_self(mi)
            var box: AABB = xf * mi.mesh.get_aabb()
            lo = minf(lo, box.position.y)
        for child: Node in node.get_children():
            stack.append(child)
    return 0.0 if lo == INF else lo

## Transform of `node` expressed in THIS animator's local frame (product of every ancestor
## transform up to, but excluding, this node). Lets assembled_local_min_y() measure piece
## meshes in the rig's own frame regardless of how deep the pivot→glb→MeshInstance3D nests.
func _local_xform_to_self(node: Node3D) -> Transform3D:
    var xf := Transform3D.IDENTITY
    var n: Node = node
    while n != null and n != self:
        if n is Node3D:
            xf = (n as Node3D).transform * xf
        n = n.get_parent()
    return xf

func _process(delta: float) -> void:
    _t += delta
    match gait:
        "idle":   _apply_idle()
        "walk":   _apply_walk()
        "attack": _apply_attack(delta)
        _:        _apply_idle()

func _apply_idle() -> void:
    # Hold the grounded baseline (no vertical bob while idle).
    position.y = base_y
    # Subtle breathing scale + slow head sway + occasional tail wag.
    var breath: float = 1.0 + sin(_t * 1.6) * 0.015
    _scale_pivot("panda_body", Vector3.ONE * breath)
    _rotate_pivot("panda_head", Vector3(0, sin(_t * 0.6) * deg_to_rad(8.0), 0))
    _rotate_pivot("panda_tail", Vector3(sin(_t * 2.5) * deg_to_rad(12.0), 0, 0))
    for leg in ["panda_leg_fl", "panda_leg_fr", "panda_leg_bl", "panda_leg_br"]:
        _rotate_pivot(leg, Vector3.ZERO)

func _apply_walk() -> void:
    # Diagonal-pair trot: FL+BR phase A, FR+BL phase B (anti-phase).
    var phase: float = _t * cadence_hz * TAU
    var swing_a: float = sin(phase) * deg_to_rad(swing_deg)
    var swing_b: float = sin(phase + PI) * deg_to_rad(swing_deg)
    _rotate_pivot("panda_leg_fl", Vector3(swing_a, 0, 0))
    _rotate_pivot("panda_leg_br", Vector3(swing_a, 0, 0))
    _rotate_pivot("panda_leg_fr", Vector3(swing_b, 0, 0))
    _rotate_pivot("panda_leg_bl", Vector3(swing_b, 0, 0))
    # Body bob: small vertical oscillation at 2x leg cadence, ON TOP of the ground baseline.
    position.y = base_y + absf(sin(phase * 2.0)) * 0.025
    # Head bob with stride
    _rotate_pivot("panda_head", Vector3(0, 0, sin(phase) * deg_to_rad(4.0)))
    # Tail wag synced to stride
    _rotate_pivot("panda_tail", Vector3(sin(phase * 2.0) * deg_to_rad(18.0), 0, 0))

func _apply_attack(delta: float) -> void:
    # Lunge: rear back, then strike forward by tilting body + front-legs lift.
    if _attack_t < 0.0:
        _attack_t = 0.0
    position.y = base_y
    _attack_t += delta
    var dur: float = 0.7
    var t: float = clampf(_attack_t / dur, 0.0, 1.0)
    var body_tilt: float = 0.0
    var front_lift: float = 0.0
    if t < 0.35:
        # windup -- rear back, front legs lift
        body_tilt = lerpf(0.0, -18.0, t / 0.35)
        front_lift = lerpf(0.0, -55.0, t / 0.35)
    elif t < 0.55:
        # strike -- body tilts forward, front legs slam down
        body_tilt = lerpf(-18.0, 12.0, (t - 0.35) / 0.20)
        front_lift = lerpf(-55.0, 35.0, (t - 0.35) / 0.20)
    else:
        # recover
        body_tilt = lerpf(12.0, 0.0, (t - 0.55) / 0.45)
        front_lift = lerpf(35.0, 0.0, (t - 0.55) / 0.45)
    # Tilt the whole rig around Z (lunge), preserving the facing yaw on Y.
    rotation = Vector3(0, _facing_yaw, deg_to_rad(body_tilt))
    _rotate_pivot("panda_leg_fl", Vector3(deg_to_rad(front_lift), 0, 0))
    _rotate_pivot("panda_leg_fr", Vector3(deg_to_rad(front_lift), 0, 0))
    _rotate_pivot("panda_leg_bl", Vector3.ZERO)
    _rotate_pivot("panda_leg_br", Vector3.ZERO)
    if _attack_t >= dur:
        _attack_t = 0.0
        rotation = Vector3(0, _facing_yaw, 0)

func _rotate_pivot(piece_name: String, rot_rad: Vector3) -> void:
    var p: Node3D = _pivots.get(piece_name)
    if p != null:
        p.rotation = rot_rad

func _scale_pivot(piece_name: String, scale_v: Vector3) -> void:
    var p: Node3D = _pivots.get(piece_name)
    if p != null:
        p.scale = scale_v
