# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# model_gallery.gd — Dev showroom that lays out every 3D entity at its real in-game
# size so art can be verified (relative scale, colour, detail, grounding, facing).
#
# Run it directly:
#   godot --path . res://src/dev/model_gallery.tscn
#
# Entities are instantiated through the SAME code paths the game uses (Wildlife with a
# `kind`, the mob scenes, builder.tscn) so their normalised sizes and materials match
# what you see while playing — NOT raw .glb scale.
#
# Camera: free-fly. WASD / arrows move, Q/E down/up, hold RIGHT MOUSE to look around,
# hold SHIFT to move faster, ESC to quit.
extends Node3D

const _WildlifeScript := preload("res://src/world/wildlife.gd")

# Creatures by behaviour (instantiated via Wildlife(kind) → real normalised size).
const _LAND_CREATURES: Array[String] = [
	"desert_mouse", "monkey", "panda", "gnu", "snowman", "reindeer", "elephant", "giraffe",
]
const _WATER_AIR_CREATURES: Array[String] = [
	"fish_blue", "fish_orange", "fish_yellow", "jellyfish", "manta", "toucan", "orca",
]
# Hostile mob scenes.
const _MOB_SCENES: Array[String] = [
	"res://src/combat/bat.tscn",
	"res://src/combat/cube_slime.tscn",
	"res://src/combat/ghost.tscn",
	"res://src/combat/laser_penguin.tscn",
	"res://src/combat/vampire.tscn",
]

const _CELL: float = 6.0      # horizontal spacing between models in a row
const _ROW: float = 9.0       # spacing between category rows (−Z into the scene)


# ── Free-fly camera state ────────────────────────────────────────────────────
var _cam: Camera3D = null
var _yaw: float = 0.0
var _pitch: float = -0.15
const _LOOK_SENS: float = 0.005
const _MOVE_SPEED: float = 8.0


func _ready() -> void:
	_build_environment()
	_build_floor_and_grid()
	_build_camera()

	var row: int = 0
	_label_row("LAND CREATURES (height in metres)", row)
	for i: int in _LAND_CREATURES.size():
		_spawn_creature(_LAND_CREATURES[i], _row_x(i, _LAND_CREATURES.size()), -float(row) * _ROW, true)
	row += 1

	_label_row("WATER / AIR CREATURES", row)
	for i: int in _WATER_AIR_CREATURES.size():
		_spawn_creature(_WATER_AIR_CREATURES[i], _row_x(i, _WATER_AIR_CREATURES.size()), -float(row) * _ROW, false)
	row += 1

	_label_row("HOSTILE MOBS", row)
	for i: int in _MOB_SCENES.size():
		_spawn_mob(_MOB_SCENES[i], _row_x(i, _MOB_SCENES.size()), -float(row) * _ROW)
	row += 1

	_label_row("BUILDER + FOLIAGE", row)
	_spawn_builder(_row_x(0, 4), -float(row) * _ROW)
	_spawn_flower(_row_x(1, 4), -float(row) * _ROW)
	_spawn_grass(_row_x(2, 4), -float(row) * _ROW)
	_spawn_reference_cube(_row_x(3, 4), -float(row) * _ROW, "1 m REFERENCE")

	# Re-assert our camera after one frame in case a spawned entity (builder) grabbed
	# `current` via a deferred call during its own _ready.
	await get_tree().process_frame
	if is_instance_valid(_cam):
		_cam.make_current()


# ── Layout helpers ────────────────────────────────────────────────────────────

func _row_x(i: int, count: int) -> float:
	# Centre the row on x=0.
	return (float(i) - float(count - 1) * 0.5) * _CELL


func _label_row(text: String, row: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.004
	l.modulate = Color(1, 1, 0.6)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(-(_CELL * 4.5), 3.2, -float(row) * _ROW)
	add_child(l)


func _name_label(text: String, x: float, z: float, y: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.003
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(0.95, 0.97, 1.0)
	l.outline_size = 12
	l.position = Vector3(x, y, z)
	add_child(l)


# ── Spawners (real code paths) ─────────────────────────────────────────────────

func _spawn_creature(kind: String, x: float, z: float, is_land: bool) -> void:
	var w := _WildlifeScript.new() as Node3D
	if w == null:
		return
	w.set("kind", kind)
	# Land creatures ground feet to capsule bottom (-0.45): body at y=0.45 → feet at 0.
	# Water/air have no body and float free — show them at a readable height.
	w.position = Vector3(x, 0.45 if is_land else 1.4, z)
	add_child(w)  # _ready() builds + grounds the mesh/rig synchronously here
	# Freeze the wander/gravity loop immediately so the creature stays on its pedestal.
	# _ready already grounded it; the rig animator (its own _process) keeps idling.
	w.set_process(false)
	_name_label(kind, x, z, 0.2)


func _spawn_mob(scene_path: String, x: float, z: float) -> void:
	if not ResourceLoader.exists(scene_path):
		return
	var ps := load(scene_path) as PackedScene
	if ps == null:
		return
	var mob := ps.instantiate() as Node3D
	if mob == null:
		return
	mob.position = Vector3(x, 0.55, z)  # ~grounded; mesh is centred on the body in _ready
	add_child(mob)  # super._ready() applies the art mesh / rig synchronously here
	# Freeze immediately: ground mobs (penguin/vampire/slime) were FALLING THROUGH the
	# gallery floor during the old settle window and reading as "empty". Their visual is
	# already built in _ready, so freezing now keeps them on their pedestal.
	mob.set_physics_process(false)
	mob.set_process(false)
	var label := scene_path.get_file().get_basename()
	_name_label(label, x, z, 0.2)


func _spawn_builder(x: float, z: float) -> void:
	var ps := load("res://src/builder/builder.tscn") as PackedScene
	if ps == null:
		return
	var b := ps.instantiate() as Node3D
	add_child(b)
	b.global_position = Vector3(x, 0.2, z)
	b.set_physics_process(false)
	# builder.tscn ships its own Camera3D(s) — disable them so they don't steal `current`
	# from the gallery's free-fly camera (this was why the camera "didn't work").
	for c: Node in _find_cameras(b):
		(c as Camera3D).current = false
	_name_label("builder", x, z, 0.2)


func _find_cameras(root: Node) -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Camera3D:
			out.append(n as Camera3D)
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


func _spawn_flower(x: float, z: float) -> void:
	var p := "res://assets/meshes/flower.glb"
	if ResourceLoader.exists(p):
		var f := (load(p) as PackedScene).instantiate() as Node3D
		add_child(f)
		f.global_position = Vector3(x, 0.0, z)
	_name_label("flower", x, z, 0.2)


func _spawn_grass(x: float, z: float) -> void:
	# Same procedural tuft as the in-world grass (a fan of tapered green blades).
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _grass_tuft_mesh()
	mm.instance_count = 7
	for i: int in 7:
		var ang := TAU * float(i) / 7.0
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, ang),
			Vector3(cos(ang) * 0.35, 0.0, sin(ang) * 0.35)))
	mmi.multimesh = mm
	add_child(mmi)
	mmi.global_position = Vector3(x, 0.0, z)
	_name_label("grass tuft", x, z, 0.2)


func _spawn_reference_cube(x: float, z: float, label: String) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.3)
	bm.material = mat
	mi.mesh = bm
	mi.position = Vector3(x, 0.5, z)
	add_child(mi)
	_name_label(label, x, z, 0.2)


func _grass_tuft_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: int in 5:
		var ang: float = TAU * float(b) / 5.0 + 0.4
		var dx: float = cos(ang)
		var dz: float = sin(ang)
		var bx: float = dx * 0.10
		var bz: float = dz * 0.10
		var px: float = -dz * 0.035
		var pz: float = dx * 0.035
		st.add_vertex(Vector3(bx - px, 0.0, bz - pz))
		st.add_vertex(Vector3(bx + px, 0.0, bz + pz))
		st.add_vertex(Vector3(bx + dx * 0.10, 0.28, bz + dz * 0.10))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.27, 0.52, 0.20)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	st.set_material(mat)
	return st.commit()


# ── Scene scaffolding (lighting matched to the game so colours read true) ──────

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.62, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.85, 0.9)  # matches main_scene.tscn
	env.ambient_light_energy = 0.55
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.2
	add_child(sun)


func _build_floor_and_grid() -> void:
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.50, 0.62, 0.40)
	pm.material = fmat
	floor_mi.mesh = pm
	add_child(floor_mi)
	# 1 m grid lines so size is readable at a glance.
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(1, 1, 1, 0.12)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, gmat)
	for i: int in range(-30, 31):
		im.surface_add_vertex(Vector3(float(i), 0.02, -60))
		im.surface_add_vertex(Vector3(float(i), 0.02, 60))
		im.surface_add_vertex(Vector3(-60, 0.02, float(i)))
		im.surface_add_vertex(Vector3(60, 0.02, float(i)))
	im.surface_end()
	grid.mesh = im
	add_child(grid)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.far = 500.0
	add_child(_cam)
	_cam.current = true  # make sure OUR camera is the active one
	_cam.position = Vector3(0, 6, 16)
	_yaw = 0.0
	_pitch = -0.30
	_apply_cam_rotation()
	# Capture the mouse so look works reliably (relative motion is unreliable uncaptured).
	# Esc releases it (and a second Esc quits); click re-captures.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_hint()


func _build_hint() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var lbl := Label.new()
	lbl.text = "Move: WASD / arrows   Up·Down: E / Q   Look: mouse   Faster: Shift   Release cursor: Esc   Quit: Esc again"
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(16, 12)
	cl.add_child(lbl)


# ── Free-fly camera ─────────────────────────────────────────────────────────

func _apply_cam_rotation() -> void:
	_cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _input(event: InputEvent) -> void:
	# Look — only while the mouse is captured.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * _LOOK_SENS
		_pitch = clampf(_pitch - mm.relative.y * _LOOK_SENS, -1.4, 1.4)
		_apply_cam_rotation()
	# Click re-captures the cursor for look.
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		# First Esc releases the cursor; a second Esc (cursor already free) quits.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			get_tree().quit()


func _process(delta: float) -> void:
	if _cam == null:
		return
	var basis := _cam.global_transform.basis
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    dir -= basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  dir += basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  dir -= basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir += basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	if dir.length_squared() > 0.0:
		var speed := _MOVE_SPEED * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		_cam.global_position += dir.normalized() * speed * delta
