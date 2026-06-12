# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# render_item_icon.gd — Render a 3D inventory-item thumbnail to a transparent PNG.
#
# Loads a .glb, frames it by its full-subtree AABB, lights it with a soft 3/4 key,
# and screenshots a 256x256 RGBA image with a transparent background — matching the
# existing assets/textures/icons/*.png item-thumbnail style.
#
# Godot --headless has NO rendering, so run this WITH a rendering display:
#   godot -s tools/render_item_icon.gd -- <abs_glb_path> <abs_out_png> \
#         [pitch_deg] [yaw_deg] [albedo_res_path] [scale_x,scale_y,scale_z]
#
# The optional pitch/yaw (degrees) rotate the camera around the framed model; defaults
# give a Minecraft-style 3/4 view (yaw 35, pitch -25). The optional 5th arg is a res://
# path to an albedo texture applied to every surface (used to give the plain wood_plank
# brick model a visible wood-plank grain so the thumbnail clearly reads as a plank).
#
# The optional 6th arg is a non-uniform model scale "x,y,z" applied to the instance
# before framing. The shipped brick meshes are unit 1x1 studs (the wood_plank.glb is a
# tall single-stud cube), so on its own a "plank" reads as a box. Passing e.g. 3.2,0.5,1
# stretches the brick into a wide, flat plank silhouette that clearly reads as a wooden
# plank in the inventory slot. The camera framing follows the scaled AABB, so the icon
# stays centred and fills the frame at any scale.

extends SceneTree

const ICON_SIZE := 256

var _glb := ""
var _out := "/tmp/item_icon.png"
var _yaw_deg := 35.0
var _pitch_deg := -25.0
var _wood_texture := ""
var _scale := Vector3.ONE
var _root: Node3D
var _cam: Camera3D
var _inst: Node3D


func _init() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() >= 1:
		_glb = ua[0]
	if ua.size() >= 2:
		_out = ua[1]
	if ua.size() >= 3:
		_pitch_deg = float(ua[2])
	if ua.size() >= 4:
		_yaw_deg = float(ua[3])
	if ua.size() >= 5:
		_wood_texture = ua[4]
	if ua.size() >= 6:
		_scale = _parse_scale(ua[5])

	if _glb.is_empty():
		push_error("[render_item_icon] usage: -- <glb_path> <out_png> [pitch] [yaw] [albedo] [sx,sy,sz]")
		quit(1)
		return

	var vp := get_root()
	vp.transparent_bg = true
	# Render at a higher internal resolution, then downsample on save for crisp edges.
	vp.size = Vector2i(ICON_SIZE * 4, ICON_SIZE * 4)

	_root = Node3D.new()
	vp.add_child(_root)

	# Environment: transparent background, soft ambient so the model reads in 3D.
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.92, 0.94, 0.99)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	_root.add_child(we)

	# Key + fill lights for a soft 3/4 read.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-50), deg_to_rad(40), 0)
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.98, 0.94)
	_root.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-15), deg_to_rad(-120), 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.85, 0.90, 1.0)
	_root.add_child(fill)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_root.add_child(_cam)

	var scene: PackedScene = load(_glb) as PackedScene
	if scene == null:
		push_error("[render_item_icon] failed to load: %s" % _glb)
		quit(1)
		return
	_inst = scene.instantiate() as Node3D
	# Non-uniform model scale (e.g. stretch a unit brick into a wide flat plank). Applied
	# before framing so the camera AABB follows the scaled silhouette.
	if not _scale.is_equal_approx(Vector3.ONE):
		_inst.scale = _scale
	_root.add_child(_inst)
	if not _wood_texture.is_empty():
		_apply_wood_texture(_inst)

	# Frame after the node is inside the tree (global_transform is only valid then),
	# then give the renderer a moment to settle (texture upload, light) before saving.
	create_timer(0.05).timeout.connect(_frame)
	create_timer(0.6).timeout.connect(_save)


## Parse a "x,y,z" command-line scale token into a Vector3 (defaults to ONE on any
## malformed component so a bad arg can never silently zero-out the model).
func _parse_scale(token: String) -> Vector3:
	var parts := token.split(",", false)
	var v := Vector3.ONE
	if parts.size() >= 1 and parts[0].is_valid_float():
		v.x = float(parts[0])
	if parts.size() >= 2 and parts[1].is_valid_float():
		v.y = float(parts[1])
	if parts.size() >= 3 and parts[2].is_valid_float():
		v.z = float(parts[2])
	# Guard against zero/negative components that would collapse the AABB.
	v.x = maxf(v.x, 0.001)
	v.y = maxf(v.y, 0.001)
	v.z = maxf(v.z, 0.001)
	return v


func _frame() -> void:
	var inst := _inst
	# Compute the combined AABB of all MeshInstance3D descendants in world space.
	var aabb := _subtree_aabb(inst)
	if aabb.size == Vector3.ZERO:
		push_error("[render_item_icon] no mesh geometry in %s" % _glb)
		quit(1)
		return

	var centre := aabb.position + aabb.size * 0.5
	var radius := aabb.size.length() * 0.5

	# Orthogonal framing: size the camera box to the model's largest screen extent.
	_cam.size = radius * 2.05

	# Position the camera on a 3/4 orbit around the model centre.
	var yaw := deg_to_rad(_yaw_deg)
	var pitch := deg_to_rad(_pitch_deg)
	var dir := Vector3(
		cos(pitch) * sin(yaw),
		-sin(pitch),
		cos(pitch) * cos(yaw)
	).normalized()
	var dist: float = maxf(radius * 4.0, 1.0)
	_cam.position = centre + dir * dist
	_cam.look_at_from_position(_cam.position, centre, Vector3.UP)
	_cam.near = 0.01
	_cam.far = dist + radius * 4.0


## Apply an albedo texture (triplanar so it wraps cleanly on the brick) to every
## MeshInstance3D surface — gives the plain wood_plank brick a wood-grain look.
func _apply_wood_texture(node: Node) -> void:
	var tex: Texture2D = load(_wood_texture) as Texture2D
	if tex == null:
		push_warning("[render_item_icon] wood texture not found: %s" % _wood_texture)
		return
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var mat := StandardMaterial3D.new()
				mat.albedo_texture = tex
				mat.uv1_triplanar = true
				mat.uv1_scale = Vector3(2.2, 2.2, 2.2)
				mat.roughness = 0.9
				mat.metallic = 0.0
				for s in mi.mesh.get_surface_count():
					mi.set_surface_override_material(s, mat)
		for c in n.get_children():
			stack.push_back(c)


func _subtree_aabb(node: Node) -> AABB:
	var out := AABB()
	var has_any := false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var local := mi.mesh.get_aabb()
				var world := mi.global_transform * local
				if not has_any:
					out = world
					has_any = true
				else:
					out = out.merge(world)
		for c in n.get_children():
			stack.push_back(c)
	return out


func _save() -> void:
	var img: Image = get_root().get_texture().get_image()
	# Downsample the 4x supersample to the final 256x256 icon.
	img.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	var err := img.save_png(_out)
	if err != OK:
		push_error("[render_item_icon] save_png failed (%d) -> %s" % [err, _out])
		quit(1)
		return
	print("[render_item_icon] saved -> %s" % _out)
	quit(0)
