"""
Build 3 single-mesh creatures (slime, fish, ghost) as procedural
primitives ready for the shader-wobble animator.

Each is a SINGLE mesh (no rigid-piece split) saved as one .glb. The
runtime applies vertex-deform shaders to each.

Convention (Blender Z-up; Godot will load with Y-up via the glTF
importer's standard axis remap):
    +Z = up
    +Y = forward (the direction the creature faces)
    +X = right

Output: assets/meshes/avatars/<name>/<name>.glb

NB: brand-palette colours are sRGB hex; Blender BSDF Base Color
expects LINEAR. Pass everything through hex_to_linear() or the
render comes out pastel (see commit 883e862).
"""

import bpy
import os
import sys
import math
import argparse


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(hex_str):
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), 1.0)


PALETTE = {
    "slime_green": hex_to_linear("#3DB560"),  # online_green (brand)
    "fish_blue":   hex_to_linear("#1E69C6"),  # vivid blue
    "fish_orange": hex_to_linear("#E8890C"),  # relay_amber
    "ghost_white": hex_to_linear("#F1F0EA"),  # brick_white
    "eye_black":   hex_to_linear("#101010"),
    "fin_dark":    hex_to_linear("#0B3D80"),
}


def reset_scene():
    bpy.ops.wm.read_homefile(use_empty=True)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def make_material(name, rgba, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Metallic"].default_value = 0.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
        if alpha < 1.0 and "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
            mat.blend_method = "BLEND"
    return mat


def join_into(parent, *extras):
    bpy.ops.object.select_all(action="DESELECT")
    for o in extras:
        o.select_set(True)
    parent.select_set(True)
    bpy.context.view_layer.objects.active = parent
    bpy.ops.object.join()


def export_glb(obj_or_list, out_path):
    bpy.ops.object.select_all(action="DESELECT")
    objs = obj_or_list if isinstance(obj_or_list, list) else [obj_or_list]
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print(f"  wrote {out_path}  ({len(objs)} object(s))")


# ----- slime: squashed dome with two eye dots -----
# Body and eyes ship as SEPARATE objects so the runtime can apply the
# wobble shader to the body only while leaving the eyes static.
def build_slime(out_dir):
    reset_scene()
    mat_body = make_material("slime", PALETTE["slime_green"])
    mat_eye = make_material("eye", PALETTE["eye_black"])
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.30, segments=20, ring_count=14, location=(0, 0, 0.20),
    )
    body = bpy.context.active_object
    body.scale = (1.0, 1.0, 0.65)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    body.data.materials.append(mat_body)
    body.name = "slime_body"
    # eyes joined into one object (so we keep total surface count low)
    eyes = []
    for i, x_off in enumerate((-0.08, +0.08)):
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=0.035, segments=12, ring_count=8,
            location=(x_off, 0.24, 0.24),
        )
        e = bpy.context.active_object
        e.data.materials.append(mat_eye)
        eyes.append(e)
    join_into(eyes[0], eyes[1])
    eyes[0].name = "slime_eyes"
    export_glb([body, eyes[0]], os.path.join(out_dir, "slime", "slime.glb"))


# ----- fish: lozenge body + triangle tail (body+fins shader-deformed; eyes static) -----
def build_fish(out_dir, colour_key="fish_blue", tag="blue"):
    reset_scene()
    mat_body = make_material("fish_body", PALETTE[colour_key])
    mat_eye = make_material("eye", PALETTE["eye_black"])
    mat_fin = make_material("fin", PALETTE["fin_dark"])
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.10, segments=20, ring_count=12, location=(0, 0, 0.30),
    )
    body = bpy.context.active_object
    body.scale = (0.7, 2.0, 0.9)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    body.data.materials.append(mat_body)
    # tail + dorsal fins -- join into body so the whole "body" deforms together
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.27, 0.30))
    tail = bpy.context.active_object
    tail.scale = (0.005, 0.10, 0.18)
    bpy.ops.object.transform_apply(scale=True)
    tail.data.materials.append(mat_fin)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.0, 0.42))
    dorsal = bpy.context.active_object
    dorsal.scale = (0.005, 0.12, 0.10)
    bpy.ops.object.transform_apply(scale=True)
    dorsal.data.materials.append(mat_fin)
    join_into(body, tail, dorsal)
    body.name = f"fish_{tag}_body"
    # eyes as a separate object so they stay rigid
    eyes = []
    for x_off in (-0.06, +0.06):
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=0.022, segments=10, ring_count=6,
            location=(x_off, 0.13, 0.32),
        )
        e = bpy.context.active_object
        e.data.materials.append(mat_eye)
        eyes.append(e)
    join_into(eyes[0], eyes[1])
    eyes[0].name = f"fish_{tag}_eyes"
    export_glb([body, eyes[0]],
               os.path.join(out_dir, f"fish_{tag}", f"fish_{tag}.glb"))


# ----- ghost: rounded torso + tapered base (single mesh) -----
def build_ghost(out_dir):
    reset_scene()
    mat_body = make_material("ghost", PALETTE["ghost_white"], alpha=0.78)
    mat_eye = make_material("eye", PALETTE["eye_black"])
    # body: cone-ish via stretched sphere then taper
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=0.22, segments=20, ring_count=14, location=(0, 0, 0.45),
    )
    body = bpy.context.active_object
    body.scale = (1.0, 1.0, 1.4)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    body.data.materials.append(mat_body)
    # taper bottom -- pull lower vertices inward (rough robe shape)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    for v in bm.verts:
        if v.co.z < 0.40:
            squeeze = 1.0 - (0.40 - v.co.z) * 0.6
            v.co.x *= max(0.2, squeeze)
            v.co.y *= max(0.2, squeeze)
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    body.name = "ghost_body"
    # eyes as a separate object
    eyes = []
    for x_off in (-0.06, +0.06):
        bpy.ops.mesh.primitive_uv_sphere_add(
            radius=0.028, segments=12, ring_count=8,
            location=(x_off, 0.18, 0.55),
        )
        e = bpy.context.active_object
        e.data.materials.append(mat_eye)
        eyes.append(e)
    join_into(eyes[0], eyes[1])
    eyes[0].name = "ghost_eyes"
    export_glb([body, eyes[0]], os.path.join(out_dir, "ghost", "ghost.glb"))


def main():
    args_after = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="assets/meshes/avatars")
    args = p.parse_args(args_after)
    build_slime(args.out)
    build_fish(args.out, "fish_blue", "blue")
    build_ghost(args.out)
    print("\nDone -- slime + fish_blue + ghost meshes written.")


if __name__ == "__main__":
    main()
