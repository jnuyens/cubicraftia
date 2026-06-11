extends SceneTree
## Headless render of the assembled builder rig for visual verification.
## Usage: godot --headless -s tools/render_builder_rig.gd -- /abs/out.png
## (run NON-headless for actual pixels; headless may give a blank buffer.)

const AnimatorScript := preload("res://src/builder/minifigure_animator.gd")

var _root: Node3D
var _anim: Node3D
var _out := "/tmp/builder_rig.png"

func _init() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0:
		_out = ua[0]
	var vp := get_root()
	vp.transparent_bg = false

	_root = Node3D.new()
	vp.add_child(_root)

	# environment
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.76, 0.93)
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	_root.add_child(we)

	# ground
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3, 0.05, 3)
	floor_mesh.mesh = box
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.55, 0.72, 0.38)
	floor_mesh.set_surface_override_material(0, fmat)
	floor_mesh.position.y = -0.025
	_root.add_child(floor_mesh)

	# sun + camera
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 2.4
	sun.light_color = Color(1.0, 0.97, 0.92)
	_root.add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0.7, 0.62, 1.25)
	cam.look_at_from_position(cam.position, Vector3(0, 0.45, 0), Vector3.UP)
	cam.current = true
	_root.add_child(cam)

	# the rig
	_anim = AnimatorScript.new()
	_anim.set("mesh_set", "builder")
	_anim.set("gait", "idle")
	_root.add_child(_anim)

	# apply sample palette after rig _ready builds pivots
	create_timer(0.4).timeout.connect(_recolour)
	create_timer(1.2).timeout.connect(_save)

func _recolour() -> void:
	var skin := Color("#E8B06A")
	var body := Color("#2C66C9")
	var legs := Color("#1B3F7A")
	for pivot in _anim.get_children():
		var pname: String = pivot.name
		var col: Color
		if pname.begins_with("builder_head"):
			col = skin
		elif pname.begins_with("builder_torso") or pname.begins_with("builder_arm"):
			col = body
		elif pname.begins_with("builder_pelvis") or pname.begins_with("builder_legs"):
			col = legs
		else:
			continue
		_recolour_subtree(pivot, col)

func _recolour_subtree(node: Node, col: Color) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var lname: String = mi.name.to_lower()
			if lname.contains("hair") or lname.contains("hand"):
				for c in n.get_children():
					stack.push_back(c)
				continue
			if mi.mesh != null:
				for s in mi.mesh.get_surface_count():
					var mat := StandardMaterial3D.new()
					mat.albedo_color = col
					mat.roughness = 1.0
					mi.set_surface_override_material(s, mat)
		for c in n.get_children():
			stack.push_back(c)

func _save() -> void:
	var img: Image = get_root().get_texture().get_image()
	img.save_png(_out)
	print("[render] saved -> %s" % _out)
	quit(0)
