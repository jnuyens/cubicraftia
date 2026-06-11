"""
Cubicraftia creature primitive generator (Blender 5.1+, headless).

Generates primitive-mesh `.glb` placeholders for the 5 hostile creatures
(model-bible §4) and 13 atmospheric wildlife species (model-bible §5),
sized to the locked bounding boxes.

These are deliberately crude — box+cylinder+sphere compositions — meant as
"the shape is there so collisions + scale work, swap for hero meshes later."
Hunyuan3D-2 / commissioned artist output would replace any of these
one-for-one without code changes.

Usage:
    blender --background --python scripts/generate_creatures.py

Output:
    assets/meshes/creatures/<name>.glb
    assets/meshes/creatures/<name>.glb.license

License: GPL-3.0-or-later.
"""

import bpy
import bmesh
import os
import math
import sys

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "meshes", "creatures")

# Palette (from cubicraftia.tres)
COLORS = {
    "white":       (0.95, 0.94, 0.92, 1.0),
    "black":       (0.18, 0.19, 0.20, 1.0),
    "navy":        (0.11, 0.17, 0.34, 1.0),
    "red":         (0.84, 0.22, 0.16, 1.0),
    "yellow":      (0.96, 0.77, 0.05, 1.0),
    "green":       (0.24, 0.71, 0.38, 1.0),
    "green_dark":  (0.15, 0.50, 0.25, 1.0),
    "blue_pale":   (0.65, 0.78, 0.92, 1.0),
    "purple_pale": (0.75, 0.65, 0.85, 1.0),
    "brown":       (0.42, 0.31, 0.16, 1.0),
    "brown_light": (0.65, 0.50, 0.30, 1.0),
    "gray":        (0.54, 0.56, 0.57, 1.0),
    "tan":         (0.86, 0.77, 0.58, 1.0),
    "pink":        (0.96, 0.65, 0.76, 1.0),
    "orange":      (0.91, 0.54, 0.05, 1.0),
}


# ─── Definitions (bounding box dims from model-bible §4–5) ────────────────────
# Format: name → factory function
# Each builds 1 primitive composition centred at (0, 0, 0) with bottom at Z=0.

def laser_penguin():
    # bbox 0.5 × 0.7 × 0.5 — short waddling shape
    parts = []
    body = make_box("body", 0.40, 0.55, 0.35, z=0.05, color="navy")
    parts.append(body)
    belly = make_box("belly", 0.30, 0.45, 0.34, z=0.05, color="white")
    belly.location.y = 0.02
    parts.append(belly)
    head = make_box("head", 0.30, 0.30, 0.30, z=0.55, color="navy")
    parts.append(head)
    beak = make_cone("beak", 0.05, 0.10, z=0.62, axis="X", color="yellow")
    beak.location.y = -0.15
    parts.append(beak)
    return parts


def ghost():
    # bbox 0.8 × 1.4 × 0.8 — drifting humanoid
    parts = []
    body = make_capsule("body", 0.32, 1.1, z=0.5, color="blue_pale", alpha=0.65)
    parts.append(body)
    # Two black eye dots on the face
    return parts


def vampire_humanoid():
    # bbox 0.6 × 1.7 × 0.6
    parts = []
    legs = make_box("legs", 0.40, 0.60, 0.25, z=0.0, color="black")
    parts.append(legs)
    torso = make_box("torso", 0.50, 0.70, 0.30, z=0.60, color="red")
    parts.append(torso)
    head = make_box("head", 0.30, 0.30, 0.30, z=1.35, color="white")
    parts.append(head)
    cape = make_box("cape", 0.55, 0.80, 0.10, z=0.65, color="black")
    cape.location.y = 0.18
    parts.append(cape)
    return parts


def vampire_bat():
    # bbox 0.3 × 0.3 × 0.4 — small, wings spread
    parts = []
    body = make_box("body", 0.10, 0.10, 0.12, z=0.10, color="black")
    parts.append(body)
    wing_l = make_box("wing_l", 0.18, 0.04, 0.12, z=0.15, color="black")
    wing_l.location.x = -0.14
    parts.append(wing_l)
    wing_r = make_box("wing_r", 0.18, 0.04, 0.12, z=0.15, color="black")
    wing_r.location.x = 0.14
    parts.append(wing_r)
    return parts


def bat():
    # bbox 0.25 × 0.25 × 0.3 — atmospheric small bat
    parts = []
    body = make_box("body", 0.08, 0.08, 0.10, z=0.10, color="brown")
    parts.append(body)
    wing_l = make_box("wing_l", 0.16, 0.03, 0.10, z=0.13, color="brown")
    wing_l.location.x = -0.12
    parts.append(wing_l)
    wing_r = make_box("wing_r", 0.16, 0.03, 0.10, z=0.13, color="brown")
    wing_r.location.x = 0.12
    parts.append(wing_r)
    return parts


def cube_slime_large():
    return [make_box("body", 0.75, 0.75, 0.75, z=0.0, color="green", alpha=0.85)]


def cube_slime_medium():
    return [make_box("body", 0.48, 0.48, 0.48, z=0.0, color="green", alpha=0.85)]


def cube_slime_small():
    return [make_box("body", 0.23, 0.23, 0.23, z=0.0, color="green", alpha=0.85)]


def panda():
    # bbox 0.7 × 1.0 × 1.2
    parts = []
    body = make_box("body", 0.55, 0.85, 1.0, z=0.10, color="white")
    parts.append(body)
    # Black patches
    head = make_box("head", 0.45, 0.45, 0.45, z=0.55, color="white")
    head.location.y = -0.65
    parts.append(head)
    # Black ears
    for x_off in (-0.13, 0.13):
        ear = make_box(f"ear_{x_off}", 0.10, 0.10, 0.10, z=0.95, color="black")
        ear.location.x = x_off
        ear.location.y = -0.65
        parts.append(ear)
    # Legs
    for x in (-0.18, 0.18):
        for y in (-0.30, 0.30):
            leg = make_box(f"leg_{x}_{y}", 0.12, 0.30, 0.12, z=0.0, color="black")
            leg.location.x = x
            leg.location.y = y
            parts.append(leg)
    return parts


def desert_mouse():
    parts = []
    body = make_box("body", 0.10, 0.08, 0.16, z=0.04, color="tan")
    parts.append(body)
    head = make_box("head", 0.07, 0.07, 0.07, z=0.06, color="tan")
    head.location.y = -0.10
    parts.append(head)
    tail = make_box("tail", 0.02, 0.02, 0.10, z=0.06, color="tan")
    tail.location.y = 0.13
    parts.append(tail)
    return parts


def reindeer():
    parts = []
    body = make_box("body", 0.60, 0.80, 1.60, z=0.85, color="brown")
    parts.append(body)
    head = make_box("head", 0.30, 0.30, 0.30, z=1.65, color="brown")
    head.location.y = -0.85
    parts.append(head)
    # Antlers
    for x_off in (-0.10, 0.10):
        for branch in range(3):
            antler = make_box(f"antler_{x_off}_{branch}", 0.02, 0.20, 0.02, z=1.80 + branch * 0.10, color="brown_light")
            antler.location.x = x_off
            antler.location.y = -0.90 + (branch - 1) * 0.10
            parts.append(antler)
    # Legs
    for x in (-0.20, 0.20):
        for y in (-0.30, 0.30):
            leg = make_box(f"leg_{x}_{y}", 0.10, 0.85, 0.10, z=0.0, color="brown")
            leg.location.x = x
            leg.location.y = y
            parts.append(leg)
    return parts


def snowman():
    parts = []
    bottom = make_box("bottom", 0.40, 0.40, 0.40, z=0.20, color="white")
    parts.append(bottom)
    middle = make_box("middle", 0.30, 0.30, 0.30, z=0.60, color="white")
    parts.append(middle)
    top = make_box("top", 0.20, 0.20, 0.20, z=0.95, color="white")
    parts.append(top)
    # Hat
    hat = make_box("hat", 0.22, 0.10, 0.22, z=1.10, color="black")
    parts.append(hat)
    # Carrot nose
    nose = make_cone("nose", 0.02, 0.10, z=0.97, axis="X", color="orange")
    nose.location.y = -0.11
    parts.append(nose)
    return parts


def monkey():
    parts = []
    body = make_box("body", 0.30, 0.45, 0.40, z=0.30, color="brown")
    parts.append(body)
    head = make_box("head", 0.20, 0.20, 0.20, z=0.65, color="brown")
    head.location.y = -0.30
    parts.append(head)
    tail = make_box("tail", 0.04, 0.04, 0.40, z=0.35, color="brown")
    tail.location.y = 0.30
    parts.append(tail)
    return parts


def toucan():
    parts = []
    body = make_box("body", 0.15, 0.22, 0.25, z=0.10, color="black")
    parts.append(body)
    head = make_box("head", 0.10, 0.10, 0.10, z=0.32, color="black")
    head.location.y = -0.15
    parts.append(head)
    # Big yellow beak
    beak = make_cone("beak", 0.06, 0.20, z=0.30, axis="Y", color="yellow")
    beak.location.y = -0.30
    parts.append(beak)
    return parts


def elephant():
    parts = []
    body = make_box("body", 1.10, 1.40, 2.50, z=1.30, color="gray")
    parts.append(body)
    head = make_box("head", 0.80, 0.80, 0.80, z=1.70, color="gray")
    head.location.y = -1.50
    parts.append(head)
    # Ears
    for x_off in (-0.55, 0.55):
        ear = make_box(f"ear_{x_off}", 0.06, 0.50, 0.50, z=1.70, color="gray")
        ear.location.x = x_off
        ear.location.y = -1.50
        parts.append(ear)
    # Trunk
    trunk = make_cone("trunk", 0.15, 1.20, z=1.50, axis="Z_DOWN", color="gray")
    trunk.location.y = -2.00
    trunk.location.z = 1.40
    parts.append(trunk)
    # Tusks
    for x_off in (-0.20, 0.20):
        tusk = make_cone(f"tusk_{x_off}", 0.04, 0.30, z=1.40, axis="Y_DOWN", color="white")
        tusk.location.x = x_off
        tusk.location.y = -1.80
        parts.append(tusk)
    # Legs
    for x in (-0.40, 0.40):
        for y in (-0.50, 0.50):
            leg = make_box(f"leg_{x}_{y}", 0.30, 1.30, 0.30, z=0.0, color="gray")
            leg.location.x = x
            leg.location.y = y
            parts.append(leg)
    return parts


def giraffe():
    parts = []
    body = make_box("body", 0.60, 1.20, 1.00, z=2.20, color="tan")
    parts.append(body)
    neck = make_box("neck", 0.25, 1.80, 0.30, z=2.20, color="tan")
    neck.location.y = -0.40
    parts.append(neck)
    head = make_box("head", 0.25, 0.30, 0.25, z=4.20, color="tan")
    head.location.y = -0.50
    parts.append(head)
    # Legs (long)
    for x in (-0.25, 0.25):
        for y in (-0.40, 0.40):
            leg = make_box(f"leg_{x}_{y}", 0.12, 2.20, 0.12, z=0.0, color="tan")
            leg.location.x = x
            leg.location.y = y
            parts.append(leg)
    return parts


def gnu():
    parts = []
    body = make_box("body", 0.55, 0.80, 1.60, z=0.80, color="brown_light")
    parts.append(body)
    head = make_box("head", 0.30, 0.30, 0.40, z=1.30, color="brown_light")
    head.location.y = -0.95
    parts.append(head)
    # Curved horns (simple boxes)
    for x_off in (-0.12, 0.12):
        horn = make_box(f"horn_{x_off}", 0.04, 0.25, 0.04, z=1.50, color="black")
        horn.location.x = x_off
        horn.location.y = -1.00
        parts.append(horn)
    # Legs
    for x in (-0.20, 0.20):
        for y in (-0.30, 0.30):
            leg = make_box(f"leg_{x}_{y}", 0.10, 0.80, 0.10, z=0.0, color="black")
            leg.location.x = x
            leg.location.y = y
            parts.append(leg)
    return parts


def manta():
    # bbox 2.0 × 0.4 × 2.5 wing-dominated
    parts = []
    body = make_box("body", 0.40, 0.30, 1.80, z=0.15, color="navy")
    parts.append(body)
    wing_l = make_box("wing_l", 0.85, 0.10, 1.20, z=0.20, color="navy")
    wing_l.location.x = -0.65
    parts.append(wing_l)
    wing_r = make_box("wing_r", 0.85, 0.10, 1.20, z=0.20, color="navy")
    wing_r.location.x = 0.65
    parts.append(wing_r)
    # Tail
    tail = make_box("tail", 0.05, 0.05, 0.50, z=0.20, color="navy")
    tail.location.y = 1.15
    parts.append(tail)
    return parts


def orca():
    # bbox 1.5 × 1.5 × 6.0
    parts = []
    body = make_box("body", 1.30, 1.20, 4.50, z=0.85, color="black")
    parts.append(body)
    # White belly patch
    belly = make_box("belly", 1.0, 0.50, 3.50, z=0.85, color="white")
    belly.location.z = 0.40
    parts.append(belly)
    # Tail fluke
    fluke = make_box("fluke", 1.20, 0.10, 0.40, z=0.85, color="black")
    fluke.location.y = 2.50
    parts.append(fluke)
    # Dorsal fin
    fin = make_box("fin", 0.10, 0.40, 0.40, z=1.65, color="black")
    parts.append(fin)
    return parts


def fish_blue():
    parts = []
    body = make_box("body", 0.10, 0.12, 0.30, z=0.06, color="blue_pale")
    parts.append(body)
    tail = make_box("tail", 0.02, 0.10, 0.10, z=0.06, color="blue_pale")
    tail.location.y = 0.20
    parts.append(tail)
    return parts


def fish_orange():
    parts = []
    body = make_box("body", 0.10, 0.12, 0.30, z=0.06, color="orange")
    parts.append(body)
    tail = make_box("tail", 0.02, 0.10, 0.10, z=0.06, color="orange")
    tail.location.y = 0.20
    parts.append(tail)
    return parts


def fish_yellow():
    parts = []
    body = make_box("body", 0.10, 0.12, 0.30, z=0.06, color="yellow")
    parts.append(body)
    tail = make_box("tail", 0.02, 0.10, 0.10, z=0.06, color="yellow")
    tail.location.y = 0.20
    parts.append(tail)
    return parts


def jellyfish():
    parts = []
    dome = make_dome("dome", 0.25, 0.30, z=0.50, color="purple_pale", alpha=0.65)
    parts.append(dome)
    for i in range(5):
        a = (i / 5) * math.tau
        x = math.cos(a) * 0.15
        y = math.sin(a) * 0.15
        tentacle = make_box(f"tentacle_{i}", 0.02, 0.40, 0.02, z=0.10, color="purple_pale", alpha=0.50)
        tentacle.location.x = x
        tentacle.location.y = y
        parts.append(tentacle)
    return parts


# ─── Blender mesh helpers ─────────────────────────────────────────────────────

def make_material(name, rgba):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 0.7
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
        if rgba[3] < 1.0:
            mat.blend_method = "BLEND"
    return mat


def make_box(name, w, h, d, z=0.0, color="white", alpha=1.0):
    mesh = bpy.data.meshes.new(name=f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(w, d, h), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    obj.location.z = z + h * 0.5
    rgba = list(COLORS[color])
    rgba[3] = alpha
    mat = make_material(f"mat_{name}", tuple(rgba))
    obj.data.materials.append(mat)
    return obj


def make_cone(name, radius, height, z=0.0, axis="Z", color="white"):
    mesh = bpy.data.meshes.new(name=f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=8,
        radius1=radius,
        radius2=0.001,
        depth=height,
    )
    bm.to_mesh(mesh)
    bm.free()
    obj.location.z = z + height * 0.5
    # Rotate if not Z-up
    if axis == "X":
        obj.rotation_euler = (0, math.pi / 2, 0)
    elif axis == "Y":
        obj.rotation_euler = (math.pi / 2, 0, 0)
    elif axis == "Y_DOWN":
        obj.rotation_euler = (-math.pi / 2, 0, 0)
    elif axis == "Z_DOWN":
        obj.rotation_euler = (math.pi, 0, 0)
    mat = make_material(f"mat_{name}", COLORS[color])
    obj.data.materials.append(mat)
    return obj


def make_capsule(name, radius, height, z=0.0, color="white", alpha=1.0):
    """Approximate capsule with a cylinder + sphere top."""
    parts = []
    cyl_mesh = bpy.data.meshes.new(name=f"{name}_cyl_mesh")
    cyl_obj = bpy.data.objects.new(f"{name}_cyl", cyl_mesh)
    bpy.context.collection.objects.link(cyl_obj)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=12, radius1=radius, radius2=radius, depth=height)
    bm.to_mesh(cyl_mesh)
    bm.free()
    cyl_obj.location.z = z + height * 0.5
    parts.append(cyl_obj)
    # Top sphere
    sphere_mesh = bpy.data.meshes.new(name=f"{name}_sph_mesh")
    sphere_obj = bpy.data.objects.new(f"{name}_sph", sphere_mesh)
    bpy.context.collection.objects.link(sphere_obj)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=radius)
    bm.to_mesh(sphere_mesh)
    bm.free()
    sphere_obj.location.z = z + height
    parts.append(sphere_obj)
    # Join + material
    rgba = list(COLORS[color])
    rgba[3] = alpha
    mat = make_material(f"mat_{name}", tuple(rgba))
    for p in parts:
        p.data.materials.append(mat)
    # Return parent (caller will join the parts)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    return joined


def make_dome(name, radius, h_scale, z=0.0, color="white", alpha=1.0):
    mesh = bpy.data.meshes.new(name=f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=radius)
    # Squash bottom half by scaling top half
    bmesh.ops.scale(bm, vec=(1, 1, h_scale), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    obj.location.z = z
    rgba = list(COLORS[color])
    rgba[3] = alpha
    mat = make_material(f"mat_{name}", tuple(rgba))
    obj.data.materials.append(mat)
    return obj


# ─── Build + export ───────────────────────────────────────────────────────────

CREATURES = {
    "laser_penguin":      laser_penguin,
    "ghost":              ghost,
    "vampire_humanoid":   vampire_humanoid,
    "vampire_bat":        vampire_bat,
    "bat":                bat,
    "cube_slime_large":   cube_slime_large,
    "cube_slime_medium":  cube_slime_medium,
    "cube_slime_small":   cube_slime_small,
    "panda":              panda,
    "desert_mouse":       desert_mouse,
    "reindeer":           reindeer,
    "snowman":            snowman,
    "monkey":             monkey,
    "toucan":             toucan,
    "elephant":           elephant,
    "giraffe":            giraffe,
    "gnu":                gnu,
    "manta":              manta,
    "orca":               orca,
    "fish_blue":          fish_blue,
    "fish_orange":        fish_orange,
    "fish_yellow":        fish_yellow,
    "jellyfish":          jellyfish,
}


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)


def join_all(name):
    """Join every mesh in the scene into a single named object."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    return joined


def export_glb(name):
    out_path = os.path.join(OUTPUT_DIR, f"{name}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        use_selection=True,
    )
    return out_path


def write_license(name):
    path = os.path.join(OUTPUT_DIR, f"{name}.glb.license")
    with open(path, "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Generated by scripts/generate_creatures.py from model-bible bounding boxes.\n"
            "Placeholder primitive composition — swap for hero mesh when available.\n"
        )


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Cubicraftia creature generator → {OUTPUT_DIR}\n")
    generated = []
    errors = []
    for name, builder in CREATURES.items():
        try:
            clear_scene()
            builder()
            join_all(name)
            out_path = export_glb(name)
            write_license(name)
            print(f"  ✓ {name:24s} → {out_path}")
            generated.append(name)
        except Exception as exc:
            print(f"  ✗ {name} failed: {exc}")
            errors.append((name, str(exc)))

    print(f"\nGenerated: {len(generated)}, errors: {len(errors)}")
    if errors:
        for name, err in errors:
            print(f"  ✗ {name}: {err}")


if __name__ == "__main__":
    main()
    sys.exit(0)
