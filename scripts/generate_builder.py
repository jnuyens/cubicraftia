"""
Cubicraftia builder character generator (Blender 5.1+ headless script).

Generates the default builder mesh + 8 avatar preset variants directly from
model-bible §3 anatomy. Each preset captures the in-game programmatic mesh
the avatar_creator SubViewport shows, so what the player picks IS what they get.

Outputs:
- assets/meshes/builder/builder_default.glb
- assets/meshes/builder/preset_0.glb .. preset_7.glb
- assets/textures/avatars/preset_0.png .. preset_7.png (3D viewport captures)

Usage:
    blender --background --python scripts/generate_builder.py

Anchored to:
- 1 BU (builder unit) = 0.050 m
- Head: 8 BU cube (0.40 m)
- Torso: 10 BU x 12 BU x 6 BU (0.50 x 0.60 x 0.30 m)
- Legs: 4 BU x 10 BU x 4 BU each
- Arms: 4 BU x 10 BU x 4 BU each
- Hands: 3 BU cube
- Total height: 30 BU = 1.5 m

License: GPL-3.0-or-later.
"""

import bpy
import bmesh
import os
import math
import sys

# ─── Configuration ────────────────────────────────────────────────────────────

BU = 0.050   # 1 builder unit (m)

OUTPUT_MESH_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "meshes", "builder")
OUTPUT_TEX_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures", "avatars")

# Skin tones (from avatar_creator.gd SKIN_COLOURS)
SKIN_COLOURS = [
    (0.95, 0.82, 0.70, 1.0),   # 0 fair
    (0.82, 0.65, 0.50, 1.0),   # 1 medium-light
    (0.60, 0.45, 0.35, 1.0),   # 2 medium
    (0.50, 0.35, 0.25, 1.0),   # 3 medium-dark
    (0.35, 0.25, 0.18, 1.0),   # 4 deep
]

# Body / leg colors index → RGBA (10 swatches)
BODY_COLOURS = [
    (0.84, 0.22, 0.16, 1.0),   # 0 red
    (0.91, 0.54, 0.05, 1.0),   # 1 orange
    (0.96, 0.77, 0.05, 1.0),   # 2 yellow
    (0.24, 0.71, 0.38, 1.0),   # 3 green
    (0.36, 0.68, 0.90, 1.0),   # 4 blue
    (0.42, 0.25, 0.63, 1.0),   # 5 purple
    (0.96, 0.65, 0.76, 1.0),   # 6 pink
    (0.95, 0.94, 0.92, 1.0),   # 7 white
    (0.54, 0.56, 0.57, 1.0),   # 8 gray
    (0.18, 0.19, 0.20, 1.0),   # 9 black
]

# 8 avatar presets — must match avatar_creator.gd PRESETS exactly
PRESETS = [
    {"name": "preset_0_classic",   "skin": 0, "body": 4, "legs": 9, "label": "Classic"},
    {"name": "preset_1_winter",    "skin": 3, "body": 7, "legs": 4, "label": "Winter"},
    {"name": "preset_2_explorer",  "skin": 2, "body": 1, "legs": 1, "label": "Explorer"},
    {"name": "preset_3_knight",    "skin": 1, "body": 8, "legs": 8, "label": "Knight"},
    {"name": "preset_4_rainbow",   "skin": 0, "body": 6, "legs": 2, "label": "Rainbow"},
    {"name": "preset_5_pirate",    "skin": 4, "body": 0, "legs": 9, "label": "Pirate"},
    {"name": "preset_6_ninja",     "skin": 1, "body": 9, "legs": 9, "label": "Ninja"},
    {"name": "preset_7_astronaut", "skin": 0, "body": 7, "legs": 7, "label": "Astronaut"},
]


# ─── Blender helpers ──────────────────────────────────────────────────────────

def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    for light in list(bpy.data.lights):
        bpy.data.lights.remove(light)
    for cam in list(bpy.data.cameras):
        bpy.data.cameras.remove(cam)


def make_material(name, rgba):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 0.7
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
    return mat


def create_box(name, w, h, d, location=(0, 0, 0)):
    """Create a box centred at the given location. w=X, h=Z (up), d=Y."""
    mesh = bpy.data.meshes.new(name=f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(w, d, h), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    obj.location = location
    return obj


def join_objects(name, objects):
    if len(objects) == 1:
        objects[0].name = name
        return objects[0]
    for obj in objects:
        obj.select_set(False)
    bpy.context.view_layer.objects.active = objects[0]
    objects[0].select_set(True)
    for obj in objects[1:]:
        obj.select_set(True)
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    return joined


def assign_material(obj, mat):
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)


# ─── Builder construction ─────────────────────────────────────────────────────

def build_builder(skin_idx, body_idx, legs_idx, name="builder"):
    """Construct the builder with the given color indices. Returns the joined object."""
    skin_mat = make_material(f"{name}_skin", SKIN_COLOURS[skin_idx])
    body_mat = make_material(f"{name}_body", BODY_COLOURS[body_idx])
    legs_mat = make_material(f"{name}_legs", BODY_COLOURS[legs_idx])

    # Reference: root at (0, 0, 0). Z is up (Blender convention; glTF converts to Y-up on export).
    # Heights cumulative bottom-up:
    #   legs:  Z = 0   .. 10 BU
    #   torso: Z = 10 BU .. 22 BU
    #   head:  Z = 22 BU .. 30 BU
    parts = []

    # Legs — bottom-centred, separated by 5 BU along X
    leg_w = 4 * BU
    leg_h = 10 * BU
    leg_d = 4 * BU
    for side, x in [("L", -2.5 * BU), ("R", +2.5 * BU)]:
        leg = create_box(f"{name}_leg_{side}", leg_w, leg_h, leg_d, location=(x, 0, leg_h * 0.5))
        assign_material(leg, legs_mat)
        parts.append(leg)

    # Torso — sits on top of legs, centred
    torso_w = 10 * BU
    torso_h = 12 * BU
    torso_d = 6 * BU
    torso_z = leg_h + torso_h * 0.5
    torso = create_box(f"{name}_torso", torso_w, torso_h, torso_d, location=(0, 0, torso_z))
    assign_material(torso, body_mat)
    parts.append(torso)

    # Arms — hang from shoulders. Shoulder Y = leg_h + torso_h (top of torso).
    arm_w = 4 * BU
    arm_h = 10 * BU
    arm_d = 4 * BU
    shoulder_z = leg_h + torso_h - arm_h * 0.5
    for side, x in [("L", -7 * BU), ("R", +7 * BU)]:
        arm = create_box(f"{name}_arm_{side}", arm_w, arm_h, arm_d, location=(x, 0, shoulder_z))
        assign_material(arm, body_mat)
        parts.append(arm)

    # Hands — at end of arms
    hand_w = 3 * BU
    hand_h = 3 * BU
    hand_d = 3 * BU
    hand_z = shoulder_z - arm_h * 0.5 - hand_h * 0.5
    for side, x in [("L", -7 * BU), ("R", +7 * BU)]:
        hand = create_box(f"{name}_hand_{side}", hand_w, hand_h, hand_d, location=(x, 0, hand_z))
        assign_material(hand, skin_mat)
        parts.append(hand)

    # Head — sits on top of torso
    head_w = 8 * BU
    head_h = 8 * BU
    head_d = 8 * BU
    head_z = leg_h + torso_h + head_h * 0.5
    head = create_box(f"{name}_head", head_w, head_h, head_d, location=(0, 0, head_z))
    assign_material(head, skin_mat)
    parts.append(head)

    return join_objects(name, parts)


# ─── Render preset thumbnails ─────────────────────────────────────────────────

def setup_thumbnail_render():
    """Set up a camera + lights for the avatar preview thumbnail."""
    # Camera — 3/4 portrait view
    cam_data = bpy.data.cameras.new(name="ThumbCam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("ThumbCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (1.2, -1.4, 0.95)
    # Point at builder centre (Z ~= 0.8 m, which is mid-torso for 1.5 m builder)
    direction = (0, 0, 0.85)
    look_dx = direction[0] - cam.location.x
    look_dy = direction[1] - cam.location.y
    look_dz = direction[2] - cam.location.z
    cam.rotation_mode = "XYZ"
    cam.rotation_euler = (
        math.atan2(math.sqrt(look_dx ** 2 + look_dy ** 2), -look_dz),
        0,
        math.atan2(look_dx, -look_dy),
    )
    bpy.context.scene.camera = cam

    # Key light — front-right
    key_data = bpy.data.lights.new(name="Key", type="AREA")
    key_data.energy = 200
    key_data.size = 1.5
    key = bpy.data.objects.new("Key", key_data)
    bpy.context.collection.objects.link(key)
    key.location = (1.5, -1.0, 2.0)
    key.rotation_euler = (math.radians(-45), 0, math.radians(45))

    # Fill light — left
    fill_data = bpy.data.lights.new(name="Fill", type="AREA")
    fill_data.energy = 80
    fill_data.size = 1.0
    fill = bpy.data.objects.new("Fill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.location = (-1.2, -0.8, 1.4)
    fill.rotation_euler = (math.radians(-30), 0, math.radians(-50))

    # Transparent background
    bpy.context.scene.render.film_transparent = True

    # Render settings
    bpy.context.scene.render.resolution_x = 256
    bpy.context.scene.render.resolution_y = 256
    bpy.context.scene.render.image_settings.file_format = "PNG"
    bpy.context.scene.render.image_settings.color_mode = "RGBA"
    bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"


def render_thumbnail(out_path):
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)


# ─── Export ───────────────────────────────────────────────────────────────────

def export_glb(name, out_dir):
    out_path = os.path.join(out_dir, f"{name}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        use_selection=True,
    )
    return out_path


def write_license(path, generator="generate_builder.py"):
    with open(path + ".license", "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            f"Generated by scripts/{generator} from model-bible dimensions.\n"
        )


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(OUTPUT_MESH_DIR, exist_ok=True)
    os.makedirs(OUTPUT_TEX_DIR, exist_ok=True)
    print(f"Cubicraftia builder generator")
    print(f"  Meshes  → {OUTPUT_MESH_DIR}")
    print(f"  Thumbs  → {OUTPUT_TEX_DIR}\n")

    # 1) Default builder (skin 0, body 4 blue, legs 9 black — matches Phase 6 default)
    print("Default builder…")
    clear_scene()
    build_builder(skin_idx=0, body_idx=4, legs_idx=9, name="builder_default")
    glb_path = export_glb("builder_default", OUTPUT_MESH_DIR)
    write_license(glb_path)
    print(f"  ✓ {glb_path}\n")

    # 2) 8 avatar presets — mesh + thumbnail render
    for i, preset in enumerate(PRESETS):
        print(f"Preset {i}: {preset['label']}…")
        clear_scene()
        build_builder(
            skin_idx=preset["skin"],
            body_idx=preset["body"],
            legs_idx=preset["legs"],
            name=preset["name"],
        )
        # Export mesh
        glb_path = export_glb(preset["name"], OUTPUT_MESH_DIR)
        write_license(glb_path)

        # Render thumbnail
        setup_thumbnail_render()
        thumb_path = os.path.join(OUTPUT_TEX_DIR, f"preset_{i}.png")
        try:
            render_thumbnail(thumb_path)
            write_license(thumb_path, generator="generate_builder.py")
            print(f"  ✓ mesh: {glb_path}")
            print(f"  ✓ thumb: {thumb_path}")
        except Exception as exc:
            print(f"  ✗ thumb render failed: {exc} (mesh still saved)")

    print("\nDone.")


if __name__ == "__main__":
    main()
    sys.exit(0)
