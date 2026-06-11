"""Generate the 7-piece builder minifig rig as separate .glb pieces.

Run headless:
    blender --background --python tools/gen_builder_rig.py

Each piece is authored in Blender with its ORIGIN at the joint pivot (matching
assets/meshes/avatars/builder/layout.json) and geometry extending in the natural
direction. Blender is Z-up; the glTF exporter converts to Y-up, so authoring
along +Z / -Z here maps to Godot's +Y / -Y. The animator (minifigure_animator.gd)
instantiates each piece at LOCAL ZERO under a pivot Node3D placed at the joint.

Overall assembled height is matched to the previous rig: feet at world y~0,
head top at world y~0.90 (neck pivot 0.65 + head/hair ~0.25).

Accents that must survive runtime recolour are SEPARATE mesh objects whose names
contain `hair` (brown) or `hand` (yellow); see builder.gd _recolour_subtree().
"""

import bpy
import os
import math


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgba(hex_str):
    hex_str = hex_str.lstrip("#")
    r = int(hex_str[0:2], 16) / 255.0
    g = int(hex_str[2:4], 16) / 255.0
    b = int(hex_str[4:6], 16) / 255.0
    return (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)


COL_SKIN = hex_rgba("#E8B06A")  # head base (recoloured at runtime)
COL_BLUE = hex_rgba("#2C66C9")  # torso / arms / legs / pelvis (recoloured)
COL_HAIR = hex_rgba("#7A4E2A")  # ACCENT warm chestnut brown (matches hero art; survives recolour)
COL_HAND = hex_rgba("#F2C200")  # ACCENT yellow (survives recolour)

_mat_cache = {}


def get_mat(name, rgba):
    if name in _mat_cache:
        return _mat_cache[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.1
    _mat_cache[name] = m
    return m


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mat_cache.clear()


def add_mesh(name, mat):
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def cylinder(name, mat, radius, depth, location, verts=16, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=location)
    ob = add_mesh(name, mat)
    ob.rotation_euler = rot
    ob.scale = scale
    return ob


def box(name, mat, size, location, rot=(0, 0, 0)):
    # primitive_cube_add(size=1.0) spans 1.0 total per axis, so scale == total size.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    ob = add_mesh(name, mat)
    ob.scale = (size[0], size[1], size[2])
    ob.rotation_euler = rot
    return ob


def uv_sphere(name, mat, radius, location, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=16, ring_count=8, location=location)
    ob = add_mesh(name, mat)
    ob.scale = scale
    return ob


def shade_smooth(ob):
    for poly in ob.data.polygons:
        poly.use_smooth = True


def export_piece(objs, filename, out_dir):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    path = os.path.join(out_dir, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"[gen_builder_rig] exported {filename}")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.object.delete()


# ===========================================================================
# Piece builders. All origins at the joint pivot (local 0,0,0).
# Blender Z = up = Godot Y. +Z geometry goes up, -Z goes down.
# Blender -Y = front (faces camera in demo).
# ===========================================================================

def make_head(out_dir):
    """Neck pivot at origin. Cylindrical tan head UP, brown hair on top.
    Head top ~ +0.25 (world y 0.90)."""
    objs = []
    # Neck pivot world y0.65. Head base sits at world ~0.60 (meets shoulders),
    # crown ~0.82, hair ~0.90. Blender z: base -0.05 .. crown +0.17.
    head = cylinder("builder_head", get_mat("skin", COL_SKIN),
                    radius=0.105, depth=0.215, location=(0, 0, 0.06))
    shade_smooth(head)
    objs.append(head)

    # hair cap: brown dome, SEPARATE object whose name contains 'hair'.
    hair = uv_sphere("builder_hair", get_mat("hair", COL_HAIR),
                     radius=0.122, location=(0, 0, 0.175), scale=(1.0, 1.0, 0.62))
    shade_smooth(hair)
    objs.append(hair)
    # tousled fringe at front-lower edge of the hair
    fringe = box("builder_hair_fringe", get_mat("hair", COL_HAIR),
                 size=(0.205, 0.05, 0.06), location=(0, -0.088, 0.135))
    objs.append(fringe)

    export_piece(objs, "builder_head.glb", out_dir)


def make_torso(out_dir):
    """Torso pivot at origin (world y0.33). Trapezoidal blue torso UP to ~+0.34."""
    objs = []
    # Torso pivot world y0.33. Geometry spans Blender z -0.03 .. +0.29
    # (world 0.30 .. 0.62), so it overlaps the pelvis below and meets the
    # shoulders (world y0.61) and head base above -- no gaps.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.13))
    torso = add_mesh("builder_torso", get_mat("blue", COL_BLUE))
    # total size: width 0.28, depth 0.16, height 0.32 -> z [-0.03, 0.29]
    torso.scale = (0.28, 0.16, 0.32)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    me = torso.data
    for v in me.vertices:
        if v.co.z < 0.10:  # waist (bottom) narrower than shoulders -> trapezoid
            v.co.x *= 0.70
            v.co.y *= 0.82
    for poly in torso.data.polygons:
        poly.use_smooth = False
    objs.append(torso)
    export_piece(objs, "builder_torso.glb", out_dir)


def make_arm(out_dir, side):
    """Shoulder pivot at origin. Arm hangs DOWN to ~-0.24, yellow hand at bottom."""
    objs = []
    arm = cylinder("builder_arm_%s" % side, get_mat("blue", COL_BLUE),
                   radius=0.052, depth=0.22, location=(0.0, 0, -0.105))
    shade_smooth(arm)
    objs.append(arm)
    cap = uv_sphere("builder_arm_%s_cap" % side, get_mat("blue", COL_BLUE),
                    radius=0.055, location=(0, 0, -0.005), scale=(1, 1, 0.8))
    shade_smooth(cap)
    objs.append(cap)
    # yellow C-hand ring at bottom. SEPARATE object, name contains 'hand'.
    hand = cylinder("builder_hand_%s" % side, get_mat("hand", COL_HAND),
                    radius=0.046, depth=0.058, location=(0, 0.012, -0.235),
                    rot=(math.radians(90), 0, 0))
    shade_smooth(hand)
    objs.append(hand)
    export_piece(objs, "builder_arm_%s.glb" % side, out_dir)


def make_pelvis(out_dir):
    """Hip pivot at origin (world y0.28). Small blue hip block."""
    objs = []
    hip = box("builder_pelvis", get_mat("blue", COL_BLUE),
              size=(0.20, 0.115, 0.06), location=(0, 0, 0.018))
    objs.append(hip)
    export_piece(objs, "builder_pelvis.glb", out_dir)


def make_leg(out_dir, side):
    """Hip pivot at origin (world y0.28). Leg extends DOWN to ~-0.28, foot forward."""
    objs = []
    leg = box("builder_legs_%s" % side, get_mat("blue", COL_BLUE),
              size=(0.075, 0.072, 0.24), location=(0, 0, -0.12))
    objs.append(leg)
    # foot juts forward (-Y in Blender = front)
    foot = box("builder_legs_%s_foot" % side, get_mat("blue", COL_BLUE),
               size=(0.085, 0.13, 0.045), location=(0, -0.028, -0.2575))
    objs.append(foot)
    export_piece(objs, "builder_legs_%s.glb" % side, out_dir)


def main():
    out_dir = os.path.join(os.getcwd(), "assets/meshes/avatars/builder")
    out_dir = os.path.abspath(out_dir)
    print("[gen_builder_rig] out_dir =", out_dir)

    clear_scene()
    make_head(out_dir)
    make_torso(out_dir)
    make_arm(out_dir, "l")
    make_arm(out_dir, "r")
    make_pelvis(out_dir)
    make_leg(out_dir, "l")
    make_leg(out_dir, "r")
    print("[gen_builder_rig] done")


if __name__ == "__main__":
    main()
