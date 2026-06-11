"""
Render a side-by-side preview PNG of the built minifigure pieces so we
can verify the rig visually without launching Godot.

Loads each builder_*.glb from assets/meshes/avatars/builder/, places
them at their layout.json pivots (re-assembling the figure), and
renders with Blender's Cycles to a single 1024x1024 PNG.

Run:
    blender --background --python scripts/blender/render_minifigure_preview.py -- \\
        --in  assets/meshes/avatars/builder \\
        --out /tmp/cubicraftia_builder_preview.png
"""

import bpy
import os
import sys
import json
import argparse
import math


def reset_scene():
    bpy.ops.wm.read_homefile(use_empty=True)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def main():
    args_after = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--in",  dest="in_dir", required=True)
    p.add_argument("--out", required=True)
    args = p.parse_args(args_after)

    reset_scene()

    layout_path = os.path.join(args.in_dir, "layout.json")
    with open(layout_path) as fh:
        layout = json.load(fh)

    for name, meta in layout["pieces"].items():
        glb = os.path.join(args.in_dir, f"{name}.glb")
        if not os.path.exists(glb):
            print(f"  skip missing {glb}")
            continue
        bpy.ops.import_scene.gltf(filepath=glb)
        # imported objects appear as new active selection
        for obj in bpy.context.selected_objects:
            pivot = meta["pivot"]
            obj.location = (pivot[0], pivot[1], pivot[2])
        print(f"  placed {name} at {meta['pivot']}")

    # camera + light -- frame on a 1m-tall figure
    bpy.ops.object.camera_add(location=(1.6, -2.0, 1.0),
                              rotation=(math.radians(78), 0, math.radians(38)))
    cam = bpy.context.active_object
    cam.data.lens = 55
    bpy.context.scene.camera = cam

    bpy.ops.object.light_add(type='SUN', location=(2, -2, 4))
    sun = bpy.context.active_object
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(-50), math.radians(35), 0)

    # ground plane
    bpy.ops.mesh.primitive_plane_add(size=4, location=(0, 0, 0))
    floor = bpy.context.active_object
    mat = bpy.data.materials.new("floor")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.85, 0.85, 0.82, 1.0)
    floor.data.materials.append(mat)

    # render
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'  # fast preview
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = args.out
    scene.world = bpy.data.worlds.new("world")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.65, 0.78, 0.95, 1.0)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8

    bpy.ops.render.render(write_still=True)
    print(f"\nWrote preview {args.out}")


if __name__ == "__main__":
    main()
