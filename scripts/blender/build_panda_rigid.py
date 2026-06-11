"""
Build a procedural brick-built panda as rigid sub-pieces and export
each as its own .glb with a named pivot at the joint axis.

Run headless:
    blender --background --python scripts/blender/build_panda_rigid.py -- \\
        --out assets/meshes/avatars/panda

Pieces written:
    panda_leg_fl.glb      pivot = front-left hip socket  (rotates X = walk)
    panda_leg_fr.glb      pivot = front-right hip socket (rotates X = walk)
    panda_leg_bl.glb      pivot = back-left hip socket   (rotates X = walk)
    panda_leg_br.glb      pivot = back-right hip socket  (rotates X = walk)
    panda_body.glb        static torso (black band around middle, white otherwise)
    panda_head.glb        pivot = neck joint at front of body (rotates Y/Z = look)
    panda_tail.glb        pivot = base of tail at back of body (rotates X = wag)
"""

import bpy
import os
import sys
import math
import argparse
import json


# ---------- palette ----------
# sRGB hex -> linear (Blender BSDF Base Color expects linear; passing
# raw sRGB values causes a double gamma correction = pastel render).

def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(hex_str: str) -> tuple:
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), 1.0)


PALETTE = {
    "white": hex_to_linear("#F1F0EA"),  # brick_white (brand)
    "black": hex_to_linear("#1A1A1A"),  # near-pure black
    "pink":  hex_to_linear("#E86A6A"),  # panda nose / mouth accent
}

# ---------- dimensions (metres) ----------
BODY_L, BODY_W, BODY_H = 0.55, 0.32, 0.28
LEG_W, LEG_D, LEG_H = 0.12, 0.12, 0.20
HEAD_W, HEAD_D, HEAD_H = 0.30, 0.28, 0.26
EAR_R = 0.05
TAIL_R = 0.06
EYE_R = 0.025


def reset_scene():
    bpy.ops.wm.read_homefile(use_empty=True)
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def make_material(name, rgba):
    # Matte plastic look (brief: "no specular, no metalness").
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Metallic"].default_value = 0.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return mat


def add_cuboid(name, w, d, h, location, mat):
    """size=1 cube + scale to (w,d,h) (NOT half -- see the builder bug log)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (w, d, h)
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat)
    return obj


def add_sphere(location, radius, mat, segments=14):
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=radius, segments=segments, ring_count=max(6, segments // 2),
        location=location,
    )
    obj = bpy.context.active_object
    obj.data.materials.append(mat)
    return obj


def join_into(parent, *extras):
    bpy.ops.object.select_all(action="DESELECT")
    for o in extras:
        o.select_set(True)
    parent.select_set(True)
    bpy.context.view_layer.objects.active = parent
    bpy.ops.object.join()


def recenter_to_pivot(obj, pivot_world):
    """Re-origin the mesh so its glb origin is the joint pivot."""
    bpy.context.view_layer.objects.active = obj
    bpy.context.scene.cursor.location = pivot_world
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR", center="MEDIAN")
    obj.location = (0, 0, 0)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)


def export_glb(obj, out_path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
    )
    print(f"  wrote {out_path}")


def build_piece(name, builder, out_dir):
    reset_scene()
    obj, pivot_world = builder()
    obj.name = name
    recenter_to_pivot(obj, pivot_world)
    export_glb(obj, os.path.join(out_dir, f"{name}.glb"))


def main():
    args_after = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="assets/meshes/avatars/panda")
    args = p.parse_args(args_after)
    out_dir = args.out

    # ---- world-space layout ----
    # body sits centred on origin, feet on z=0
    leg_top_z = LEG_H                          # top of legs (where they attach to body)
    body_z_base = leg_top_z                    # bottom of body
    body_z_top = body_z_base + BODY_H
    body_z_centre = body_z_base + BODY_H * 0.5
    head_z_base = body_z_centre                # neck pivot at front-centre of body
    neck_x = -BODY_L * 0.5                     # front of body  (animal faces -X)
    tail_x = +BODY_L * 0.5                     # back  of body
    leg_inset_x = BODY_L * 0.35
    leg_inset_y = BODY_W * 0.35

    # ----- 4 legs -----
    leg_positions = [
        ("fl", (-leg_inset_x, -leg_inset_y, LEG_H * 0.5)),
        ("fr", (-leg_inset_x, +leg_inset_y, LEG_H * 0.5)),
        ("bl", (+leg_inset_x, -leg_inset_y, LEG_H * 0.5)),
        ("br", (+leg_inset_x, +leg_inset_y, LEG_H * 0.5)),
    ]
    for tag, loc in leg_positions:
        def leg_builder(loc=loc):
            mat = make_material(f"leg_{tag}", PALETTE["black"])
            obj = add_cuboid(f"leg_{tag}", LEG_W, LEG_D, LEG_H, loc, mat)
            pivot = (loc[0], loc[1], leg_top_z)
            return obj, pivot
        build_piece(f"panda_leg_{tag}", leg_builder, out_dir)

    # ----- body (white with black shoulder band) -----
    def body_builder():
        mat_white = make_material("body_white", PALETTE["white"])
        body = add_cuboid("body", BODY_L, BODY_W, BODY_H,
                          (0, 0, body_z_centre), mat_white)
        # black band over shoulders (front third)
        mat_black = make_material("body_band", PALETTE["black"])
        band = add_cuboid("band", BODY_L * 0.32, BODY_W * 1.01, BODY_H * 1.01,
                          (-BODY_L * 0.18, 0, body_z_centre), mat_black)
        # subtle taper: black hindquarter cap
        rump = add_cuboid("rump", BODY_L * 0.18, BODY_W * 1.01, BODY_H * 1.01,
                          (BODY_L * 0.40, 0, body_z_centre), mat_black)
        join_into(body, band, rump)
        return body, (0, 0, body_z_centre)
    build_piece("panda_body", body_builder, out_dir)

    # ----- head (white sphere + 2 black ears + 2 eye-patches + nose) -----
    def head_builder():
        mat_white = make_material("head_white", PALETTE["white"])
        mat_black = make_material("head_black", PALETTE["black"])
        mat_pink = make_material("nose_pink", PALETTE["pink"])
        head_centre = (neck_x - HEAD_W * 0.5, 0, body_z_centre + 0.03)
        # head as cube (cleaner brick look)
        head = add_cuboid("head", HEAD_W, HEAD_D, HEAD_H, head_centre, mat_white)
        # 2 ears on top
        ear_l = add_sphere(
            (head_centre[0], -HEAD_D * 0.35, head_centre[2] + HEAD_H * 0.45),
            EAR_R, mat_black,
        )
        ear_r = add_sphere(
            (head_centre[0], +HEAD_D * 0.35, head_centre[2] + HEAD_H * 0.45),
            EAR_R, mat_black,
        )
        # 2 black eye patches (small spheres on the face -- face is at -X)
        eye_y_off = HEAD_D * 0.25
        eye_z = head_centre[2] + HEAD_H * 0.1
        eye_x = head_centre[0] - HEAD_W * 0.48
        patch_l = add_sphere((eye_x, -eye_y_off, eye_z), EYE_R * 2.0, mat_black)
        patch_r = add_sphere((eye_x, +eye_y_off, eye_z), EYE_R * 2.0, mat_black)
        # pink nose
        nose = add_sphere(
            (eye_x - 0.005, 0, head_centre[2] - HEAD_H * 0.15),
            EYE_R * 1.1, mat_pink,
        )
        join_into(head, ear_l, ear_r, patch_l, patch_r, nose)
        # pivot at the back of the head (where it joins the body)
        pivot = (neck_x, 0, head_centre[2])
        return head, pivot
    build_piece("panda_head", head_builder, out_dir)

    # ----- tail (small black puff) -----
    def tail_builder():
        mat = make_material("tail", PALETTE["black"])
        tail_centre = (tail_x + TAIL_R, 0, body_z_top - TAIL_R)
        tail = add_sphere(tail_centre, TAIL_R, mat)
        tail.name = "tail"
        pivot = (tail_x, 0, body_z_top - TAIL_R)
        return tail, pivot
    build_piece("panda_tail", tail_builder, out_dir)

    # ----- layout sidecar -----
    layout = {
        "version": 1,
        "kind": "quadruped",
        "facing": "-x",
        "notes": "Quadruped layout. legs rotate around their hip socket (X axis = forward/back swing). Head rotates around Y (yaw look L/R) and Z (pitch nod). Tail rotates around X (wag).",
        "pieces": {
            "panda_leg_fl": {"pivot": [-leg_inset_x, -leg_inset_y, leg_top_z],
                             "rotates_on": "x", "joint": "hip_fl"},
            "panda_leg_fr": {"pivot": [-leg_inset_x, +leg_inset_y, leg_top_z],
                             "rotates_on": "x", "joint": "hip_fr"},
            "panda_leg_bl": {"pivot": [+leg_inset_x, -leg_inset_y, leg_top_z],
                             "rotates_on": "x", "joint": "hip_bl"},
            "panda_leg_br": {"pivot": [+leg_inset_x, +leg_inset_y, leg_top_z],
                             "rotates_on": "x", "joint": "hip_br"},
            "panda_body":   {"pivot": [0, 0, body_z_centre],
                             "rotates_on": None},
            "panda_head":   {"pivot": [neck_x, 0, body_z_centre + 0.03],
                             "rotates_on": "y", "joint": "neck"},
            "panda_tail":   {"pivot": [tail_x, 0, body_z_top - TAIL_R],
                             "rotates_on": "x", "joint": "tail_base"},
        },
    }
    layout_path = os.path.join(out_dir, "layout.json")
    with open(layout_path, "w") as fh:
        json.dump(layout, fh, indent=2)
    print(f"  wrote {layout_path}")
    print(f"\nDone -- 7 panda pieces + layout.json written to {out_dir}")


if __name__ == "__main__":
    main()
