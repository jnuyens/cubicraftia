extends Node3D
## Demo scene for the rigid-piece builder-figure animator.
##
## Builds a small stage programmatically, then drops 3 builders side by
## side -- one idle, one walking, one attacking -- so you can compare all
## gaits at once. Press 1/2/3 to retarget every builder to the same gait.

const MinifigureAnimatorScript := preload("res://src/builder/minifigure_animator.gd")
const QuadrupedAnimatorScript := preload("res://src/builder/quadruped_animator.gd")
const ShaderWobbleAnimatorScript := preload("res://src/builder/shader_wobble_animator.gd")

func _ready() -> void:
    _build_stage()
    # row 1: humanoid builder (z = -1.4)
    _spawn_builder("Idle",   Vector3(-0.9, 0, -1.4), "idle")
    _spawn_builder("Walk",   Vector3( 0.0, 0, -1.4), "walk")
    _spawn_builder("Attack", Vector3( 0.9, 0, -1.4), "attack")
    # row 2: quadruped panda (z = +0.0)
    _spawn_panda("Idle",   Vector3(-0.9, 0,  0.0), "idle")
    _spawn_panda("Walk",   Vector3( 0.0, 0,  0.0), "walk")
    _spawn_panda("Attack", Vector3( 0.9, 0,  0.0), "attack")
    # row 3: shader-wobble singles (z = +1.4) -- slime / fish / ghost
    _spawn_wobble("Slime", Vector3(-0.9, 0, 1.4),
        "slime",     ShaderWobbleAnimatorScript.BodyType.SLIME,
        Color("#3DB560"), 2.4, 0.22)
    _spawn_wobble("Fish",  Vector3( 0.0, 0, 1.4),
        "fish_blue", ShaderWobbleAnimatorScript.BodyType.FISH,
        Color("#1E69C6"), 3.0, 0.06)
    _spawn_wobble("Ghost", Vector3( 0.9, 0.4, 1.4),
        "ghost",     ShaderWobbleAnimatorScript.BodyType.GHOST,
        Color("#F1F0EA"), 1.6, 0.30)
    _spawn_camera_and_light()
    print("[animator-demo] row1 builder  row2 panda  row3 slime/fish/ghost (wobble)")
    # CLI snapshot: --snapshot /path.png writes a viewport screenshot after 2s.
    var args := OS.get_cmdline_user_args()
    for i in args.size():
        if args[i] == "--snapshot" and i + 1 < args.size():
            var path: String = args[i + 1]
            get_tree().create_timer(2.0).timeout.connect(func(): _save_snapshot(path))
            break

func _save_snapshot(path: String) -> void:
    var img: Image = get_viewport().get_texture().get_image()
    img.save_png(path)
    print("[builder-demo] snapshot -> %s" % path)
    get_tree().quit()

func _build_stage() -> void:
    var env := WorldEnvironment.new()
    var environ := Environment.new()
    environ.background_mode = Environment.BG_COLOR
    environ.background_color = Color(0.65, 0.78, 0.95)
    # Low neutral fill -- a strong white ambient was flooding every
    # surface and pastel-ising the brand colours. Sun does the work;
    # ambient just keeps shadows from being fully black.
    environ.ambient_light_color = Color(0.85, 0.88, 0.95)
    environ.ambient_light_energy = 0.18
    environ.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    env.environment = environ
    add_child(env)

    var floor_mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(5, 0.05, 6)
    floor_mesh.mesh = box
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.85, 0.85, 0.82)
    floor_mesh.set_surface_override_material(0, mat)
    floor_mesh.position.y = -0.025
    add_child(floor_mesh)

func _spawn_panda(label: String, pos: Vector3, gait: String) -> void:
    var anim := QuadrupedAnimatorScript.new()
    anim.position = pos
    anim.gait = gait
    anim.name = "Panda_%s" % label
    add_child(anim)
    var lbl := Label3D.new()
    lbl.text = "Panda " + label
    lbl.position = Vector3(0, 0.9, 0)
    lbl.modulate = Color(0.1, 0.1, 0.1)
    lbl.no_depth_test = true
    lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    anim.add_child(lbl)

func _spawn_wobble(label: String, pos: Vector3, mesh_set: String,
        body_type: int, body_colour: Color,
        speed: float, amount: float) -> void:
    var anim := ShaderWobbleAnimatorScript.new()
    anim.position = pos
    anim.mesh_set = mesh_set
    anim.body_type = body_type
    anim.body_colour = body_colour
    anim.wobble_speed = speed
    anim.wobble_amount = amount
    anim.time_offset = randf() * TAU  # de-sync multiple copies
    anim.name = label
    add_child(anim)
    var lbl := Label3D.new()
    lbl.text = label
    lbl.position = Vector3(0, 0.9, 0)
    lbl.modulate = Color(0.1, 0.1, 0.1)
    lbl.no_depth_test = true
    lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    anim.add_child(lbl)

func _spawn_camera_and_light() -> void:
    var sun := DirectionalLight3D.new()
    sun.position = Vector3(0, 4, 2)
    sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
    sun.light_energy = 2.2
    sun.light_color = Color(1.0, 0.97, 0.92)  # warm sunlight
    sun.shadow_enabled = true
    add_child(sun)

    var cam := Camera3D.new()
    cam.position = Vector3(0, 2.6, 3.4)
    cam.rotation = Vector3(deg_to_rad(-32), 0, 0)
    cam.current = true
    add_child(cam)

func _spawn_builder(label: String, pos: Vector3, gait: String) -> void:
    var anim := MinifigureAnimatorScript.new()
    anim.position = pos
    anim.gait = gait
    anim.name = "Builder_%s" % label
    add_child(anim)
    var lbl := Label3D.new()
    lbl.text = label
    lbl.position = Vector3(0, 1.3, 0)
    lbl.modulate = Color(0.1, 0.1, 0.1)
    lbl.no_depth_test = true
    lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    anim.add_child(lbl)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        var new_gait: String = ""
        match event.keycode:
            KEY_1: new_gait = "idle"
            KEY_2: new_gait = "walk"
            KEY_3: new_gait = "attack"
        if new_gait != "":
            for child in get_children():
                if child is MinifigureAnimatorScript or child is QuadrupedAnimatorScript:
                    child.gait = new_gait
            print("[animator-demo] gait -> %s" % new_gait)
