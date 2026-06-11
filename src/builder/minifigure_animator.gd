extends Node3D
class_name MinifigureAnimator

## Rigid-piece builder-figure animator.
##
## Loads the 7-piece builder rig from assets/meshes/avatars/<set>/ and
## drives idle / walk / attack motion by rotating each limb around its
## named pivot. The pieces themselves carry no animation data -- all
## motion is parametric and runs at full frame-rate without keyframe
## interpolation.

const PIECE_NAMES := [
    "builder_legs_l", "builder_legs_r",
    "builder_pelvis", "builder_torso",
    "builder_arm_l", "builder_arm_r",
    "builder_head",
]

@export var mesh_set: String = "builder"  ## subdir under assets/meshes/avatars/
@export var gait: String = "idle"  ## "idle" | "walk" | "attack"
@export var cadence_hz: float = 1.6
@export var swing_deg: float = 28.0

var _pivots: Dictionary = {}  # name -> Node3D pivot
var _pieces: Dictionary = {}  # name -> MeshInstance3D
var _t: float = 0.0
var _attack_t: float = -1.0

func _ready() -> void:
    var layout_path := "res://assets/meshes/avatars/%s/layout.json" % mesh_set
    var layout: Dictionary = _load_layout(layout_path)
    if layout.is_empty():
        push_error("MinifigureAnimator: failed to load %s" % layout_path)
        return
    _build_rig(layout)

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
        var pivot_pos := Vector3(float(pivot_arr[0]), float(pivot_arr[2]), -float(pivot_arr[1]))
        # Blender Z-up -> Godot Y-up:  (x,y,z)_blender -> (x, z, -y)_godot

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
        var inst: Node = scene.instantiate()
        pivot.add_child(inst)
        _pieces[name] = inst

func _process(delta: float) -> void:
    _t += delta
    match gait:
        "idle":   _apply_idle()
        "walk":   _apply_walk()
        "attack": _apply_attack(delta)
        _:        _apply_idle()

func _apply_idle() -> void:
    var sway := sin(_t * 2.0) * deg_to_rad(2.0)
    _rotate_pivot("builder_torso", Vector3(0, 0, sway))
    _rotate_pivot("builder_head", Vector3(0, sin(_t * 0.7) * deg_to_rad(8.0), 0))
    # subtle arm + leg dangle
    var dangle := sin(_t * 2.0) * deg_to_rad(3.0)
    _rotate_pivot("builder_arm_l", Vector3(dangle, 0, 0))
    _rotate_pivot("builder_arm_r", Vector3(-dangle, 0, 0))
    _rotate_pivot("builder_legs_l", Vector3.ZERO)
    _rotate_pivot("builder_legs_r", Vector3.ZERO)

func _apply_walk() -> void:
    var phase: float = _t * cadence_hz * TAU
    var leg_swing: float = sin(phase) * deg_to_rad(swing_deg)
    var bob: float = absf(sin(phase)) * 0.03
    _rotate_pivot("builder_legs_l", Vector3(leg_swing, 0, 0))
    _rotate_pivot("builder_legs_r", Vector3(-leg_swing, 0, 0))
    _rotate_pivot("builder_arm_l", Vector3(-leg_swing * 0.8, 0, 0))
    _rotate_pivot("builder_arm_r", Vector3(leg_swing * 0.8, 0, 0))
    position.y = bob
    _rotate_pivot("builder_torso", Vector3(0, sin(phase) * deg_to_rad(3.0), 0))
    _rotate_pivot("builder_head", Vector3(0, sin(phase * 0.5) * deg_to_rad(4.0), 0))

func _apply_attack(delta: float) -> void:
    if _attack_t < 0.0:
        _attack_t = 0.0
    _attack_t += delta
    var dur: float = 0.6
    var t: float = clampf(_attack_t / dur, 0.0, 1.0)
    # windup (0..0.3) -> strike (0.3..0.55) -> recovery (0.55..1.0)
    var ang_deg: float = 0.0
    if t < 0.3:
        ang_deg = lerpf(0.0, -60.0, t / 0.3)        # raise arm back
    elif t < 0.55:
        ang_deg = lerpf(-60.0, 90.0, (t - 0.3) / 0.25)  # swing down/forward
    else:
        ang_deg = lerpf(90.0, 0.0, (t - 0.55) / 0.45)  # recover
    _rotate_pivot("builder_arm_r", Vector3(deg_to_rad(ang_deg), 0, 0))
    _rotate_pivot("builder_arm_l", Vector3(deg_to_rad(-ang_deg * 0.2), 0, 0))
    if _attack_t >= dur:
        _attack_t = 0.0  # loop for demo

func _rotate_pivot(piece_name: String, rot_rad: Vector3) -> void:
    var p: Node3D = _pivots.get(piece_name)
    if p == null:
        return
    p.rotation = rot_rad


## Returns the right-arm pivot Node3D (the shoulder joint of the right arm), so a
## caller can parent a held tool under it. The tool then sits in the hand and swings
## with the arm during walk/attack. Null until _ready() has built the rig.
func get_right_hand_pivot() -> Node3D:
    return _pivots.get("builder_arm_r")
