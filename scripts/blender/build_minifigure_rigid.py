"""
Build a procedural Lego-style minifigure as rigid sub-pieces and export
each as its own .glb with a named pivot at the joint axis.

Run headless:
    blender --background --python scripts/blender/build_minifigure_rigid.py -- \\
        --out assets/meshes/avatars/builder

Each output .glb is centred so that its joint pivot is at the GLB origin
(0,0,0). The in-engine code parents the piece under a Node3D positioned
at the world-space hip / shoulder / neck location and rotates the piece
around the origin. This gives clean joint motion with no seam artefacts.

Pieces written (all dimensions in metres, 1 stud = 0.125m):
    builder_legs_l.glb   pivot = top of hip stud (rotates around X = walk)
    builder_legs_r.glb   pivot = top of hip stud (rotates around X = walk)
    builder_pelvis.glb   static hip belt
    builder_torso.glb    static body (chest)
    builder_arm_l.glb    pivot = top of shoulder (rotates around X = swing)
    builder_arm_r.glb    pivot = top of shoulder (rotates around X = swing)
    builder_head.glb     pivot = base of neck stud (rotates around Z = look)

The body uses Cubicraftia's six core palette colours so the result is
visually on-brand even before texture work.
"""

import bpy
import os
import sys
import math
import argparse


# ---------- palette ----------
# Brand palette from docs/art-direction-brief.md §1.3.
# Hex is sRGB. Blender's BSDF Base Color expects LINEAR values, so we
# convert with the standard sRGB->linear transform; otherwise every
# colour gets gamma-corrected a second time on render and the whole
# figure looks washed-out/pastel.

def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(hex_str: str) -> tuple:
    h = hex_str.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), 1.0)


PALETTE = {
    "skin":  hex_to_linear("#F5C30D"),  # accent_yellow (minifigure face skin)
    "shirt": hex_to_linear("#1E69C6"),  # vivid builder blue (off-palette but bright)
    "pants": hex_to_linear("#1B2C56"),  # brand navy
    "belt":  hex_to_linear("#6A4423"),  # leather brown
    "hair":  hex_to_linear("#3F2014"),  # dark brown
}


# ---------- dimensions (metres) ----------
LEG_W, LEG_D, LEG_H = 0.10, 0.10, 0.28
PELVIS_W, PELVIS_D, PELVIS_H = 0.22, 0.12, 0.05
TORSO_W, TORSO_D, TORSO_H = 0.30, 0.16, 0.32
ARM_W, ARM_D, ARM_H = 0.07, 0.08, 0.28
HEAD_W, HEAD_D, HEAD_H = 0.20, 0.20, 0.22
STUD_R, STUD_H = 0.045, 0.020


def reset_scene():
    bpy.ops.wm.read_homefile(use_empty=True)
    # remove default light/camera if any leaked through
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def make_material(name, rgba):
    # Brand brief says matte, no specular, no metalness -- roughness 1.0
    # kills the satin sheen that was lightening the perceived colour.
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Metallic"].default_value = 0.0
        # Principled BSDF in Blender 4+ has a Specular IOR Level input;
        # set to 0 so matte plastic doesn't pick up white hot-spots.
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return mat


def add_cuboid(name, w, d, h, z_base, mat):
    """Add a cuboid sitting on z=z_base, centred on x=0,y=0.
    NB: primitive_cube_add(size=1) yields a 1m cube (vertices ±0.5), so
    scale must be the full (w, d, h) to land at the requested dimensions."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, z_base + h * 0.5))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (w, d, h)
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat)
    return obj


def add_stud(parent_obj, x, y, z, mat):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=STUD_R, depth=STUD_H, vertices=16, location=(x, y, z + STUD_H * 0.5)
    )
    stud = bpy.context.active_object
    stud.data.materials.append(mat)
    # join into parent
    bpy.ops.object.select_all(action="DESELECT")
    stud.select_set(True)
    parent_obj.select_set(True)
    bpy.context.view_layer.objects.active = parent_obj
    bpy.ops.object.join()


def recenter_to_pivot(obj, pivot_world):
    """Translate verts so pivot ends up at GLB origin (0,0,0)."""
    bpy.context.view_layer.objects.active = obj
    # set origin to 3D cursor at pivot location
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
    """Build a single piece using the builder closure, export to GLB."""
    reset_scene()
    obj, pivot_world = builder()
    obj.name = name
    recenter_to_pivot(obj, pivot_world)
    export_glb(obj, os.path.join(out_dir, f"{name}.glb"))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="assets/meshes/avatars/builder",
                   help="Output directory (relative to project root)")
    args, _ = p.parse_known_args(sys.argv[sys.argv.index("--") + 1:]
                                 if "--" in sys.argv else [])
    out_dir = args.out

    # ---- world-space layout (used to compute joint pivots) ----
    # legs sit on z=0, feet on the ground
    legs_z_base = 0.0
    pelvis_z_base = legs_z_base + LEG_H
    torso_z_base = pelvis_z_base + PELVIS_H
    head_z_base = torso_z_base + TORSO_H
    shoulder_z = torso_z_base + TORSO_H - 0.04  # near top of torso

    # ----- legs (split L / R at X = ±LEG_W/2) -----
    for side, x_offset in (("l", -LEG_W * 0.5 - 0.005), ("r", +LEG_W * 0.5 + 0.005)):
        def builder(side=side, x_offset=x_offset):
            mat = make_material(f"pants_{side}", PALETTE["pants"])
            bpy.ops.mesh.primitive_cube_add(
                size=1,
                location=(x_offset, 0, legs_z_base + LEG_H * 0.5),
            )
            obj = bpy.context.active_object
            obj.scale = (LEG_W, LEG_D, LEG_H)
            bpy.ops.object.transform_apply(scale=True)
            obj.data.materials.append(mat)
            # pivot at top of hip stud (so leg rotates from hip)
            pivot = (x_offset, 0, pelvis_z_base)
            return obj, pivot
        build_piece(f"builder_legs_{side}", builder, out_dir)

    # ----- pelvis (static) -----
    def pelvis_builder():
        mat = make_material("belt", PALETTE["belt"])
        obj = add_cuboid("pelvis", PELVIS_W, PELVIS_D, PELVIS_H, pelvis_z_base, mat)
        return obj, (0, 0, pelvis_z_base)
    build_piece("builder_pelvis", pelvis_builder, out_dir)

    # ----- torso (static) -----
    def torso_builder():
        mat = make_material("shirt", PALETTE["shirt"])
        obj = add_cuboid("torso", TORSO_W, TORSO_D, TORSO_H, torso_z_base, mat)
        # shoulder studs (visual only)
        add_stud(obj, -TORSO_W * 0.35, 0, torso_z_base + TORSO_H, mat)
        add_stud(obj, +TORSO_W * 0.35, 0, torso_z_base + TORSO_H, mat)
        return obj, (0, 0, torso_z_base)
    build_piece("builder_torso", torso_builder, out_dir)

    # ----- arms (split L / R) -----
    for side, x_offset in (("l", -TORSO_W * 0.5 - ARM_W * 0.5 - 0.005),
                           ("r", +TORSO_W * 0.5 + ARM_W * 0.5 + 0.005)):
        def arm_builder(side=side, x_offset=x_offset):
            mat_shirt = make_material(f"arm_{side}_shirt", PALETTE["shirt"])
            mat_skin = make_material(f"arm_{side}_skin", PALETTE["skin"])
            # arm cylinder hanging from shoulder
            arm_z_base = shoulder_z - ARM_H
            bpy.ops.mesh.primitive_cylinder_add(
                radius=ARM_W * 0.5,
                depth=ARM_H,
                vertices=12,
                location=(x_offset, 0, arm_z_base + ARM_H * 0.5),
            )
            obj = bpy.context.active_object
            obj.data.materials.append(mat_shirt)
            # hand cube at bottom
            bpy.ops.mesh.primitive_cube_add(
                size=1,
                location=(x_offset, 0, arm_z_base + 0.04),
            )
            hand = bpy.context.active_object
            hand.scale = (ARM_W * 1.4, ARM_W * 1.4, 0.08)
            bpy.ops.object.transform_apply(scale=True)
            hand.data.materials.append(mat_skin)
            # join
            bpy.ops.object.select_all(action="DESELECT")
            hand.select_set(True)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.join()
            pivot = (x_offset, 0, shoulder_z)
            return obj, pivot
        build_piece(f"builder_arm_{side}", arm_builder, out_dir)

    # ----- head -----
    def head_builder():
        mat = make_material("head_skin", PALETTE["skin"])
        mat_hair = make_material("hair", PALETTE["hair"])
        obj = add_cuboid("head", HEAD_W, HEAD_D, HEAD_H, head_z_base, mat)
        # hair cap (slightly oversized cube on top, brown)
        bpy.ops.mesh.primitive_cube_add(
            size=1,
            location=(0, 0, head_z_base + HEAD_H - 0.02),
        )
        hair = bpy.context.active_object
        hair.scale = (HEAD_W * 1.1, HEAD_D * 1.1, 0.1)
        bpy.ops.object.transform_apply(scale=True)
        hair.data.materials.append(mat_hair)
        # join hair
        bpy.ops.object.select_all(action="DESELECT")
        hair.select_set(True)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.join()
        # neck stud
        add_stud(obj, 0, 0, head_z_base + HEAD_H, mat_hair)
        pivot = (0, 0, head_z_base)
        return obj, pivot
    build_piece("builder_head", head_builder, out_dir)

    # ----- layout sidecar so Godot knows where to mount each piece -----
    layout = {
        "version": 1,
        "notes": "pivot positions are world-space anchors; each piece .glb is centred so its origin = pivot.",
        "pieces": {
            "builder_legs_l": {
                "pivot": [-LEG_W * 0.5 - 0.005, 0, pelvis_z_base],
                "rotates_on": "x",
                "joint": "hip_l",
            },
            "builder_legs_r": {
                "pivot": [+LEG_W * 0.5 + 0.005, 0, pelvis_z_base],
                "rotates_on": "x",
                "joint": "hip_r",
            },
            "builder_pelvis": {"pivot": [0, 0, pelvis_z_base], "rotates_on": None},
            "builder_torso": {"pivot": [0, 0, torso_z_base], "rotates_on": None},
            "builder_arm_l": {
                "pivot": [-TORSO_W * 0.5 - ARM_W * 0.5 - 0.005, 0, shoulder_z],
                "rotates_on": "x",
                "joint": "shoulder_l",
            },
            "builder_arm_r": {
                "pivot": [+TORSO_W * 0.5 + ARM_W * 0.5 + 0.005, 0, shoulder_z],
                "rotates_on": "x",
                "joint": "shoulder_r",
            },
            "builder_head": {
                "pivot": [0, 0, head_z_base],
                "rotates_on": "z",
                "joint": "neck",
            },
        },
    }
    import json
    layout_path = os.path.join(out_dir, "layout.json")
    with open(layout_path, "w") as fh:
        json.dump(layout, fh, indent=2)
    print(f"  wrote {layout_path}")
    print(f"\nDone -- 7 builder pieces + layout.json written to {out_dir}")


if __name__ == "__main__":
    main()
