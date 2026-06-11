"""
Render a 3-up preview of the rigid-piece minifigure in idle / walk /
attack poses, using the EXACT same rotation formulas that
src/builder/minifigure_animator.gd applies in-engine.

Output: /tmp/cubicraftia_builder_gaits.png  (1536x512)

Run:
    blender --background --python scripts/blender/render_minifigure_gaits.py
"""

import bpy
import os
import sys
import json
import math


IN_DIR = "assets/meshes/avatars/builder"
OUT = "/tmp/cubicraftia_builder_gaits.png"


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
    bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, 0))
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


def place_builder(layout, base_x, pose):
    """Spawn one builder at world x=base_x with the given pose dict.

    pose is { 'legs_l': (rx,ry,rz), 'legs_r': ..., 'arm_l': ..., ... }
    Each entry is a (rotX, rotY, rotZ) in radians, applied AT the pivot
    (so it matches the in-engine pivot-rotation behaviour exactly).
    """
    for name, meta in layout["pieces"].items():
        glb = os.path.join(IN_DIR, f"{name}.glb")
        if not os.path.exists(glb):
            continue
        bpy.ops.import_scene.gltf(filepath=glb)
        for obj in bpy.context.selected_objects:
            if obj.type != "MESH":
                continue
            pivot = meta["pivot"]
            # Apply rotation IN PLACE (pivot stays at pivot world location).
            # Strategy: parent-less object whose location is pivot. Rotate.
            # Because our recentered mesh has the pivot at the GLB origin,
            # this works directly when we just set obj.location = pivot
            # and obj.rotation_euler = rot.
            obj.location = (pivot[0] + base_x, pivot[1], pivot[2])
            piece_key = name.replace("builder_", "")
            rot = pose.get(piece_key, (0, 0, 0))
            obj.rotation_euler = rot


def pose_idle():
    return {
        "legs_l": (0, 0, 0),
        "legs_r": (0, 0, 0),
        "arm_l":  (math.radians(3), 0, 0),
        "arm_r":  (math.radians(-3), 0, 0),
        "torso":  (0, 0, math.radians(2)),
        "head":   (0, math.radians(6), 0),
    }


def pose_walk():
    # mid-stride snapshot (phase = pi/2) -- one leg forward, one back
    swing = math.radians(28)
    return {
        "legs_l": (swing, 0, 0),
        "legs_r": (-swing, 0, 0),
        "arm_l":  (-swing * 0.8, 0, 0),
        "arm_r":  (swing * 0.8, 0, 0),
        "torso":  (0, math.radians(3), 0),
        "head":   (0, 0, 0),
    }


def pose_attack():
    # mid-swing of a downward strike
    return {
        "legs_l": (0, 0, 0),
        "legs_r": (0, 0, 0),
        "arm_l":  (math.radians(-15), 0, 0),
        "arm_r":  (math.radians(75), 0, 0),
        "torso":  (math.radians(10), 0, 0),
        "head":   (math.radians(5), 0, 0),
    }


def add_label(text, x, y, z):
    bpy.ops.object.text_add(location=(x, y, z))
    txt = bpy.context.active_object
    txt.data.body = text
    txt.data.size = 0.18
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

    spacing = 1.2
    poses = [("IDLE", pose_idle(), -spacing),
             ("WALK", pose_walk(), 0.0),
             ("ATTACK", pose_attack(), +spacing)]
    for label, pose, x in poses:
        place_builder(layout, x, pose)
        add_label(label, x - 0.25, 0.15, 1.05)

    # camera framing all 3 -- side-on so leg/arm swings read clearly
    bpy.ops.object.camera_add(
        location=(0.0, -3.6, 0.55),
        rotation=(math.radians(88), 0, 0),
    )
    cam = bpy.context.active_object
    cam.data.lens = 38
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
