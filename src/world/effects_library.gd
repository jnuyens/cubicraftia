# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# effects_library.gd — One-shot visual-effect spawner for the art-movements asset set.
#
# The art-movements.glb sheet provides textured brick-built effect props (explosion, fire,
# water splash, rain/snow clouds, sleep "Zzz", dust poof, …). This static helper loads them
# by logical name, scales each to a sane world size, and spawns a self-freeing instance —
# optionally drifting up, spinning, and fading — so gameplay systems can fire an effect with
# one call:
#
#   EffectsLibrary.spawn(parent, "explosion", world_pos)
#   EffectsLibrary.spawn(builder, "sleep_zzz", head_pos, {"float_up": 0.4, "lifetime": 1.6})
#
# Pure static API + a tiny per-instance driver script (_FxInstance) attached at runtime, so
# there is no autoload to register and headless tests that never call spawn() pay nothing.
#
# References:
#   assets/meshes/fx/                      — the split effect meshes (+ .license sidecars)
#   src/tools/dynamite_handler.gd          — explosion call site
#   src/builder/builder.gd  start_sleep_*  — sleep "Zzz" call site

class_name EffectsLibrary
extends RefCounted

## Logical effect name → mesh path. Names are the gameplay-facing identifiers.
const _FX: Dictionary = {
	"sleep_zzz":    "res://assets/meshes/fx/sleep_zzz.glb",
	"dust_poof":    "res://assets/meshes/fx/dust_poof.glb",
	"explosion":    "res://assets/meshes/fx/explosion.glb",
	"rain_cloud":   "res://assets/meshes/fx/rain_cloud.glb",
	"snow_cloud":   "res://assets/meshes/fx/snow_cloud.glb",
	"water_splash": "res://assets/meshes/fx/water_splash.glb",
	"water_spirit": "res://assets/meshes/fx/water_spirit.glb",
	"lava_embers":  "res://assets/meshes/fx/lava_embers.glb",
	"fire_flame":   "res://assets/meshes/fx/fire_flame.glb",
}

## Default longest-axis world size (m) per effect, so the split-mesh native scale (~0.3 m)
## reads at a gameplay-appropriate size. Overridable via opts.size.
const _DEFAULT_SIZE: Dictionary = {
	"sleep_zzz":    0.6,
	"dust_poof":    1.0,
	"explosion":    2.2,
	"rain_cloud":   2.0,
	"snow_cloud":   2.0,
	"water_splash": 1.2,
	"water_spirit": 1.0,
	"lava_embers":  1.4,
	"fire_flame":   1.0,
}

## True if a logical effect name is known.
static func has_effect(name: String) -> bool:
	return _FX.has(name)


## Spawn a one-shot effect instance under `parent` at `world_pos`.
##
## opts (all optional):
##   "size"     : float  — longest-axis target size in metres (default per-effect table)
##   "lifetime" : float  — seconds before auto-free (default 1.5; <=0 = persist until freed)
##   "float_up" : float  — upward drift speed m/s (default 0.0)
##   "spin"     : float  — yaw spin speed rad/s (default 0.0)
##   "fade"     : bool   — fade alpha to 0 over the back half of lifetime (default true)
##   "ground"  : bool   — base at world_pos.y (true) vs centred on it (false). Default true.
##
## Returns the spawned Node3D (already in-tree), or null if the effect/parent is invalid.
static func spawn(parent: Node, name: String, world_pos: Vector3, opts: Dictionary = {}) -> Node3D:
	if parent == null or not _FX.has(name):
		return null
	var path: String = _FX[name]
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var holder := Node3D.new()
	holder.name = "Fx_" + name
	var mesh_inst := packed.instantiate() as Node3D
	if mesh_inst == null:
		return null
	holder.add_child(mesh_inst)
	parent.add_child(holder)
	holder.global_position = world_pos

	# Scale to the target longest-axis size and base/centre it.
	var target: float = float(opts.get("size", _DEFAULT_SIZE.get(name, 1.0)))
	var ground: bool = bool(opts.get("ground", true))
	_normalise(mesh_inst, target, ground)

	# Attach the lifetime/motion/fade driver.
	var driver := _FxInstance.new()
	driver.lifetime = float(opts.get("lifetime", 1.5))
	driver.float_up = float(opts.get("float_up", 0.0))
	driver.spin = float(opts.get("spin", 0.0))
	driver.fade = bool(opts.get("fade", true))
	driver.mesh_inst = mesh_inst
	holder.add_child(driver)
	return holder


## Scale `inst` so its longest local-AABB axis equals `target_m`, then base it on y=0
## (feet on the spawn point) or centre it. Independent of the .glb's native scale/offset.
static func _normalise(inst: Node3D, target_m: float, ground: bool) -> void:
	var ab := _subtree_aabb(inst)
	var native: float = maxf(ab.size.x, maxf(ab.size.y, ab.size.z))
	native = maxf(native, 0.001)
	var s: float = target_m / native
	inst.scale = Vector3(s, s, s)
	var c: Vector3 = ab.get_center() * s
	if ground:
		inst.position = Vector3(-c.x, -ab.position.y * s, -c.z)
	else:
		inst.position = -c


## Merged local-space AABB of every MeshInstance3D under `root`.
static func _subtree_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv: Transform3D = root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c: Node in n.get_children():
			stack.push_back(c)
	return out


## Per-instance driver: drives lifetime, upward drift, spin, and a back-half alpha fade,
## then frees its holder. Inner class so the whole effects system is one file.
class _FxInstance extends Node3D:
	var lifetime: float = 1.5
	var float_up: float = 0.0
	var spin: float = 0.0
	var fade: bool = true
	var mesh_inst: Node3D = null
	var _age: float = 0.0
	var _fade_mats: Array = []

	func _ready() -> void:
		if fade and mesh_inst != null:
			# Collect (and make transparent) the materials we'll fade. Duplicate so we don't
			# mutate the shared imported material on other instances.
			var stack: Array[Node] = [mesh_inst]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is MeshInstance3D:
					var mi := n as MeshInstance3D
					for si: int in range(mi.get_surface_override_material_count()):
						var m: Material = mi.mesh.surface_get_material(si) if mi.mesh != null else null
						if m is StandardMaterial3D:
							var dup := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
							dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
							mi.set_surface_override_material(si, dup)
							_fade_mats.append(dup)
				for c: Node in n.get_children():
					stack.push_back(c)

	func _process(delta: float) -> void:
		_age += delta
		var parent := get_parent() as Node3D
		if parent != null:
			if float_up != 0.0:
				parent.global_position.y += float_up * delta
			if spin != 0.0:
				parent.rotation.y += spin * delta
		if fade and lifetime > 0.0 and not _fade_mats.is_empty():
			var t: float = _age / lifetime
			if t > 0.5:
				var a: float = clampf(1.0 - (t - 0.5) / 0.5, 0.0, 1.0)
				for m: Material in _fade_mats:
					var sm := m as StandardMaterial3D
					sm.albedo_color = Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, a)
		if lifetime > 0.0 and _age >= lifetime:
			if parent != null:
				parent.queue_free()
			else:
				queue_free()
