extends Node3D
class_name ShaderWobbleAnimator

## Single-mesh creature animator -- vertex deformation runs entirely on
## the GPU via assets/shaders/creature_wobble.gdshader. Works for
## creatures with no rigid-piece split: slime (squash/stretch),
## fish (tail-sway), ghost (float + alpha pulse).
##
## The mesh GLB must ship the body as a MeshInstance3D whose name ends
## in "_body". Anything else (eyes, decorations) keeps its imported
## material and rides the parent transform without deformation.
##
## Brand-palette note: body_colour is set in LINEAR space to match the
## Blender hex_to_linear() pipeline. Godot's Color() literal in
## GDScript IS interpreted as linear when passed to a shader uniform,
## so just authoring the same hex code keeps things consistent.

const SHADER := preload("res://assets/shaders/creature_wobble.gdshader")

enum BodyType { SLIME = 0, FISH = 1, GHOST = 2 }

@export var mesh_set: String = "slime"  ## subdir under assets/meshes/avatars/
@export var body_type: BodyType = BodyType.SLIME
@export var body_colour: Color = Color("#3DB560")  ## brand-aligned default
@export var wobble_speed: float = 2.0
@export var wobble_amount: float = 0.22
@export var time_offset: float = 0.0

var _shader_mat: ShaderMaterial


func _ready() -> void:
    _shader_mat = ShaderMaterial.new()
    _shader_mat.shader = SHADER
    _shader_mat.set_shader_parameter("body_type", int(body_type))
    _shader_mat.set_shader_parameter("wobble_speed", wobble_speed)
    _shader_mat.set_shader_parameter("wobble_amount", wobble_amount)
    _shader_mat.set_shader_parameter("time_offset", time_offset)
    # IMPORTANT: shader uniforms named source_color (the `tint` vec4)
    # accept a Color directly -- Godot serialises it as the linear
    # vec4 the shader expects. Hex code matches the brand palette.
    _shader_mat.set_shader_parameter("tint", body_colour)

    var glb_path := "res://assets/meshes/avatars/%s/%s.glb" % [mesh_set, mesh_set]
    if not ResourceLoader.exists(glb_path):
        push_error("ShaderWobbleAnimator: missing %s" % glb_path)
        return
    var scene: PackedScene = load(glb_path)
    var inst: Node = scene.instantiate()
    add_child(inst)
    _apply_shader_to_body(inst)


func _apply_shader_to_body(root: Node) -> void:
    # Apply the wobble shader (which drives ALBEDO from the `tint` uniform) to every
    # body MeshInstance3D, sparing only eyes/accessories so they keep their materials.
    # Previously this matched only names ending in "_body", but the exported meshes are
    # named after the set ("fish_blue", "slime", "ghost") — so the tint was NEVER applied
    # and every fish rendered with fish_blue's baked-blue material (fish_orange looked blue).
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if n is MeshInstance3D:
            var lname: String = n.name.to_lower()
            if not (lname.contains("eye") or lname.contains("accessor") or lname.contains("pupil")):
                n.material_override = _shader_mat
        for child in n.get_children():
            stack.push_back(child)
