# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# generate-brick-mesh.py — Blender Python script to generate the 1×1 concave-top-stud brick mesh.
#
# Run with:
#   blender -b -P scripts/generate-brick-mesh.py
#
# Produces:
#   assets/meshes/brick_1x1.blend   — Blender source
#   assets/meshes/brick_1x1.glb     — glTF binary with extras metadata
#
# Brick geometry (CONTEXT.md D-08, D-09, world scale: 1 stud = 1.0 m):
#   Body:    1.0 m × 1.2 m × 1.0 m  (W × H × D), centred at origin (bottom at Y=0)
#   Stud:    radius=0.3 m, height=0.18 m, centred on top face at (0, 1.2, 0)
#   Cavity:  radius=0.18 m, depth=0.12 m, subtracted from stud top → concave indent (D-08)
#
# The body bottom is at Y=0, top face at Y=1.2.
# The stud sits on top: its base at Y=1.2, tip at Y=1.38.
# The stud top has a concave cavity (bottle-cap shape per D-08).
#
# glTF extras written on the mesh object (Pattern 2 from RESEARCH.md):
#   cubicraftia.brick_id        = "brick_1x1"
#   cubicraftia.dimensions      = [1, 1, 1]
#   cubicraftia.studs_top       = [{"x":0.0,"y":1.0,"z":0.0,"gender":"male"}]
#   cubicraftia.studs_bottom    = [{"x":0.0,"y":0.0,"z":0.0,"gender":"female"}]
#   cubicraftia.material        = "plastic_solid"
#   cubicraftia.stud_profile    = "concave_top"

import bpy
import bmesh
import json
import math
import os
import sys

# ─── Resolve project root ────────────────────────────────────────────────────
# When invoked as `blender -b -P scripts/generate-brick-mesh.py` from the
# project root, __file__ is the absolute path to the script.
# We resolve paths relative to the project root (two levels up from scripts/).
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
MESH_DIR = os.path.join(PROJECT_ROOT, "assets", "meshes")
os.makedirs(MESH_DIR, exist_ok=True)

BLEND_PATH = os.path.join(MESH_DIR, "brick_1x1.blend")
GLB_PATH   = os.path.join(MESH_DIR, "brick_1x1.glb")

# ─── Brick dimensions (world scale: 1 stud = 1.0 m) ─────────────────────────
BODY_W      = 1.0    # width  (X)
BODY_H      = 1.2    # height (Y)  — 1 brick = 1.2 × 1 plate unit
BODY_D      = 1.0    # depth  (Z)
STUD_R      = 0.3    # stud outer radius
STUD_H      = 0.18   # stud height above body top face
CAVITY_R    = 0.18   # concave cavity radius (< STUD_R, per D-08 bottle-cap shape)
CAVITY_D    = 0.12   # depth of the concave cavity into the stud
SEGS        = 16     # cylinder segments (balanced quality vs poly count for mobile)

# ─── Reset scene ─────────────────────────────────────────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)
# Remove all default objects
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

# ─── Helper: create cylinder at position ─────────────────────────────────────
def make_cylinder(name, radius, depth, location):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=SEGS,
        radius=radius,
        depth=depth,
        location=location
    )
    obj = bpy.context.active_object
    obj.name = name
    return obj

# ─── 1. Body cuboid ──────────────────────────────────────────────────────────
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, BODY_H / 2.0, 0.0))
body = bpy.context.active_object
body.name = "BrickBody"
body.scale = (BODY_W, BODY_H, BODY_D)
bpy.ops.object.transform_apply(scale=True)

# ─── 2. Stud cylinder ────────────────────────────────────────────────────────
stud_center_y = BODY_H + STUD_H / 2.0
stud = make_cylinder("BrickStud", STUD_R, STUD_H, (0.0, stud_center_y, 0.0))

# ─── 3. Cavity cylinder (to be boolean-subtracted from stud top) ──────────────
# The cavity is centred at the TOP of the stud, sinking CAVITY_D into it.
cavity_center_y = BODY_H + STUD_H - CAVITY_D / 2.0
cavity = make_cylinder("BrickCavity", CAVITY_R, CAVITY_D * 1.5, (0.0, cavity_center_y, 0.0))

# ─── 4. Boolean subtract cavity from stud ────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
stud.select_set(True)
bpy.context.view_layer.objects.active = stud

bool_mod = stud.modifiers.new(name="CavityBoolean", type='BOOLEAN')
bool_mod.operation = 'DIFFERENCE'
bool_mod.object = cavity
bool_mod.solver = 'FLOAT'

bpy.ops.object.modifier_apply(modifier="CavityBoolean")

# Hide (then delete) the cavity cutter object
bpy.data.objects.remove(cavity, do_unlink=True)

# ─── 5. Join body + stud into one mesh object ────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
stud.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
brick_obj = bpy.context.active_object
brick_obj.name = "Brick_1x1"

# ─── 6. Assign a simple grey material (rough-art per D-09) ───────────────────
mat = bpy.data.materials.new(name="BrickPlastic")
mat.use_nodes = True
# Set base colour to a neutral brick grey
principled = mat.node_tree.nodes.get("Principled BSDF")
if principled:
    principled.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1.0)
    principled.inputs["Roughness"].default_value = 0.6
    principled.inputs["Metallic"].default_value = 0.0
brick_obj.data.materials.append(mat)

# ─── 7. Write glTF extras as Blender Custom Properties ───────────────────────
# Blender's glTF exporter writes these into the node-level `extras` dict.
# Godot 4.6 reads them via Object.get_meta("extras") on the MeshInstance3D.
#
# Arrays must be stored as JSON strings in Blender custom properties
# (Blender converts dicts to IDPropertyGroup which doesn't survive glTF round-trip
# cleanly; JSON strings are safer and parseable on both sides).
brick_obj["cubicraftia.brick_id"]     = "brick_1x1"
brick_obj["cubicraftia.dimensions"]   = json.dumps([1, 1, 1])
brick_obj["cubicraftia.studs_top"]    = json.dumps([{"x": 0.0, "y": 1.0, "z": 0.0, "gender": "male"}])
brick_obj["cubicraftia.studs_bottom"] = json.dumps([{"x": 0.0, "y": 0.0, "z": 0.0, "gender": "female"}])
brick_obj["cubicraftia.material"]     = "plastic_solid"
brick_obj["cubicraftia.stud_profile"] = "concave_top"

# ─── 8. Save .blend source ───────────────────────────────────────────────────
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print(f"[generate-brick-mesh] Saved .blend to: {BLEND_PATH}")

# ─── 9. Export to glTF binary (.glb) with custom properties ──────────────────
bpy.ops.export_scene.gltf(
    filepath=GLB_PATH,
    export_format='GLB',
    export_apply=True,
    export_extras=True,          # write custom properties into glTF extras
    export_materials='EXPORT',
    export_normals=True,
    use_selection=False,
    use_visible=True,
    export_yup=True,             # Godot uses Y-up; keep consistent
)
print(f"[generate-brick-mesh] Exported .glb to: {GLB_PATH}")

print("[generate-brick-mesh] Done.")
