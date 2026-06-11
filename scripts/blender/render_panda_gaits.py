"""
Render a 3-up preview of the panda quadruped in idle / walk / attack
poses, using the same rotation formulas src/builder/quadruped_animator.gd
applies in-engine.

Output: /tmp/cubicraftia_panda_gaits.png
"""

import bpy
import os
import sys
import json
import math


IN_DIR = "assets/meshes/avatars/panda"
OUT = "/tmp/cubicraftia_panda_gaits.png"


def reset_scene():
    bpy.ops.wm.read_homefile(use_empty=True)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _hex(s):
    h = s.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), 1.0)


def add_floor():
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    floor = bpy.context.active_object
    mat = bpy.data.materials.new("floor")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = _hex("#D9D7CF")
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    floor.data.materials.append(mat)


def add_lighting_and_world():
    bpy.ops.object.light_add(type='SUN', location=(2, -2, 4))
    sun = bpy.context.active_object
    sun.data.energy = 4.0
    sun.data.color = (1.0, 0.97, 0.92)
    sun.rotation_euler = (math.radians(-50), math.radians(35), 0)

    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = _hex("#9EC0EE")
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    bpy.context.scene.world = world


def place_panda(layout, base_x, base_z, pose, body_tilt_z=0.0):
    """Spawn one panda at world x=base_x with given per-piece rotations.

    pose is { piece_short_key: (rx,ry,rz) }
    body_tilt_z applies a global tilt around the Z axis (for ATTACK lunge).
    """
    pieces = []
    for name, meta in layout["pieces"].items():
        glb = os.path.join(IN_DIR, f"{name}.glb")
        if not os.path.exists(glb):
            continue
        bpy.ops.import_scene.gltf(filepath=glb)
        for obj in bpy.context.selected_objects:
            if obj.type != "MESH":
                continue
            pivot = meta["pivot"]
            obj.location = (pivot[0] + base_x, pivot[1], pivot[2] + base_z)
            piece_key = name.replace("panda_", "")
            rot = pose.get(piece_key, (0, 0, 0))
            obj.rotation_euler = rot
            pieces.append(obj)
    # Apply body tilt by rotating all pieces around the body centre.
    if body_tilt_z != 0.0:
        # parent everything to an empty, rotate the empty
        bpy.ops.object.empty_add(location=(base_x, 0, base_z + 0.25))
        empty = bpy.context.active_object
        for obj in pieces:
            obj.parent = empty
            obj.matrix_parent_inverse = empty.matrix_world.inverted()
        empty.rotation_euler = (0, body_tilt_z, 0)


def pose_idle():
    # subtle pose: just a tail wag
    return {
        "leg_fl": (0, 0, 0),
        "leg_fr": (0, 0, 0),
        "leg_bl": (0, 0, 0),
        "leg_br": (0, 0, 0),
        "head":   (0, 0, math.radians(8)),     # slight yaw
        "tail":   (math.radians(12), 0, 0),
    }


def pose_walk():
    swing = math.radians(22)
    # diagonal pair A (FL+BR) forward, pair B (FR+BL) back
    return {
        "leg_fl": (swing, 0, 0),
        "leg_br": (swing, 0, 0),
        "leg_fr": (-swing, 0, 0),
        "leg_bl": (-swing, 0, 0),
        "head":   (0, 0, math.radians(4)),
        "tail":   (math.radians(18), 0, 0),
    }


def pose_attack():
    # mid-strike snapshot: body tilted forward, front legs slamming down
    return {
        "leg_fl": (math.radians(35), 0, 0),
        "leg_fr": (math.radians(35), 0, 0),
        "leg_bl": (0, 0, 0),
        "leg_br": (0, 0, 0),
        "head":   (0, 0, 0),
        "tail":   (math.radians(-15), 0, 0),
    }


def add_label(text, x, y, z):
    bpy.ops.object.text_add(location=(x, y, z))
    txt = bpy.context.active_object
    txt.data.body = text
    txt.data.size = 0.16
    txt.rotation_euler = (math.radians(90), 0, 0)
    mat = bpy.data.materials.new(f"label_{text}")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.1, 0.1, 0.1, 1)
    txt.data.materials.append(mat)


def main():
    reset_scene()
    with open(os.path.join(IN_DIR, "layout.json")) as fh:
        layout = json.load(fh)
    add_floor()
    add_lighting_and_world()

    spacing = 1.4
    place_panda(layout, -spacing, 0.0, pose_idle())
    place_panda(layout,       0.0, 0.0, pose_walk())
    place_panda(layout, +spacing, 0.0, pose_attack(), body_tilt_z=math.radians(12))

    add_label("IDLE",   -spacing - 0.25, 0.20, 0.95)
    add_label("WALK",          - 0.25, 0.20, 0.95)
    add_label("ATTACK", +spacing - 0.30, 0.20, 0.95)

    # 3/4 camera so leg swings + head + tail all read clearly
    bpy.ops.object.camera_add(
        location=(-0.4, -3.8, 1.0),
        rotation=(math.radians(80), 0, math.radians(-6)),
    )
    cam = bpy.context.active_object
    cam.data.lens = 36
    bpy.context.scene.camera = cam

    s = bpy.context.scene
    s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x = 1536
    s.render.resolution_y = 768
    s.render.image_settings.file_format = 'PNG'
    s.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    print(f"\nWrote {OUT}")


if __name__ == "__main__":
    main()
