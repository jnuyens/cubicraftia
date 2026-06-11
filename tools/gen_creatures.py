# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# gen_creatures.py — Headless Blender generator for Cubicraftia's stylised
# low-poly creature meshes (wildlife procedural-fallback set + plain hostiles).
#
# Run:  blender --background --python tools/gen_creatures.py
#
# Authoring convention (MUST match src/world/wildlife.gd::_normalise_creature_mesh
# and src/combat/hostile_mob.gd::_apply_art_mesh, the `not is_art` branch):
#   - Build UPRIGHT, +Z up in Blender  -> Godot +Y up (glTF Z-up -> Y-up).
#   - FACE -Y in Blender (front)        -> Godot -Z forward (body look_at points
#     -Z at the walk direction, so the creature leads with its head).
#   - Feet at the mesh's LOWEST point (Z=0); centred on origin in X/Y.
#   - REAL BSDF materials (multi-colour). NO vertex colours (those route the
#     asset down the TripoSR path and get re-coloured flat).
#   - Natural proportions; absolute size irrelevant (the game scales the full
#     subtree to a per-kind target height).

import bpy
import os
import math
from mathutils import Vector

# ── Output dir ────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(REPO_ROOT, "assets", "meshes", "creatures")

# ── Material cache ──────────────────────────────────────────────────────────────
_MAT_CACHE = {}


def mat(name, rgb, rough=0.85, metal=0.0, alpha=1.0):
    """Return (creating if needed) a simple BSDF material with the given base colour."""
    key = (name, rgb, rough, metal, alpha)
    if key in _MAT_CACHE:
        return _MAT_CACHE[key]
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    r, g, b = rgb
    bsdf.inputs["Base Color"].default_value = (r, g, b, alpha)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = 'BLEND'
    _MAT_CACHE[key] = m
    return m


# ── Primitive helpers ───────────────────────────────────────────────────────────
def _finish(obj, material, rot=None):
    if rot:
        obj.rotation_euler = (math.radians(rot[0]), math.radians(rot[1]), math.radians(rot[2]))
    obj.data.materials.clear()
    obj.data.materials.append(material)
    return obj


def box(loc, size, material, rot=None):
    """Axis-aligned box. size = (sx, sy, sz) full dimensions."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.scale = (size[0] / 2.0, size[1] / 2.0, size[2] / 2.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, material, rot)


def cyl(loc, radius, depth, material, rot=None, verts=12):
    """Cylinder, default axis = Z."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc)
    return _finish(bpy.context.active_object, material, rot)


def sphere(loc, radius, material, scale=None, rot=None, segs=14, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=radius, location=loc)
    obj = bpy.context.active_object
    if scale:
        obj.scale = scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, material, rot)


def cone(loc, radius1, radius2, depth, material, rot=None, verts=12):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius1, radius2=radius2,
                                    depth=depth, location=loc)
    return _finish(bpy.context.active_object, material, rot)


def join_all(objs, name):
    """Join a list of objects into one mesh (keeping all material slots) so fine
    voxel creatures export as a single efficient MeshInstance rather than hundreds."""
    objs = [o for o in objs if o is not None]
    if not objs:
        return objs
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.active_object
    joined.name = name
    return [joined]


# ── Scene management ────────────────────────────────────────────────────────────
def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)


def export(kind, objs):
    """Drop everything to feet-on-floor / X-Y centred, then export selected objs as GLB."""
    minv = [1e9, 1e9, 1e9]
    maxv = [-1e9, -1e9, -1e9]
    for o in objs:
        for corner in o.bound_box:
            wc = o.matrix_world @ Vector(corner)
            for i in range(3):
                minv[i] = min(minv[i], wc[i])
                maxv[i] = max(maxv[i], wc[i])
    cx = (minv[0] + maxv[0]) / 2.0
    cy = (minv[1] + maxv[1]) / 2.0
    dz = -minv[2]  # lift feet to z=0
    for o in objs:
        o.location.x -= cx
        o.location.y -= cy
        o.location.z += dz

    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

    path = os.path.join(OUT_DIR, "%s.glb" % kind)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print("Exported %s -> %s" % (kind, path))


# ── Colour palette ──────────────────────────────────────────────────────────────
C_BROWN = (0.40, 0.26, 0.13)
C_BROWN_L = (0.62, 0.45, 0.28)
C_BROWN_D = (0.24, 0.15, 0.07)
C_TAN = (0.78, 0.62, 0.34)
C_TAN_L = (0.88, 0.76, 0.52)
C_GREY = (0.55, 0.55, 0.58)
C_GREY_D = (0.34, 0.34, 0.37)
C_WHITE = (0.95, 0.95, 0.93)
C_BLACK = (0.08, 0.08, 0.09)
C_ORANGE = (0.92, 0.45, 0.08)
C_YELLOW = (0.95, 0.78, 0.12)
C_SAND = (0.85, 0.72, 0.48)
C_PINK = (0.95, 0.62, 0.62)
C_BLUE_L = (0.62, 0.78, 0.92)
C_DARKBROWN_SPOT = (0.45, 0.28, 0.12)


# ════════════════════════════════════════════════════════════════════════════════
# CREATURE BUILDERS  (front faces -Y)
# ════════════════════════════════════════════════════════════════════════════════

def build_monkey():
    body = mat("monkey_body", C_BROWN)
    face = mat("monkey_face", C_BROWN_L)
    # box() halves its size arg; spans noted are ACTUAL extents.
    objs = []
    # Body: actual x[-0.15,0.15] y[-0.12,0.12] z[0.55,0.95].
    objs.append(box((0, 0, 0.75), (0.6, 0.5, 0.8), body))
    # Head lowered so it overlaps the body top (z=0.95).
    objs.append(sphere((0, -0.05, 1.22), 0.34, body))
    objs.append(sphere((0, -0.30, 1.19), 0.20, face, scale=(1.0, 0.5, 0.9)))
    objs.append(sphere((-0.30, 0, 1.29), 0.10, face))
    objs.append(sphere((0.30, 0, 1.29), 0.10, face))
    # Legs: feet at z=0, top z=0.65 (embed 0.10 into body bottom z=0.55). Hips inboard.
    for sx in (-0.10, 0.10):
        objs.append(box((sx, 0, 0.325), (0.16, 0.18, 1.30), body))
    # Arms: inner edge embedded into the body sides (body x edge=0.15).
    for sx in (-0.16, 0.16):
        objs.append(box((sx, -0.05, 0.85), (0.14, 0.16, 0.62), body))
    # Tail: base embedded in the body back (body back y=0.12).
    objs.append(cyl((0, 0.14, 0.7), 0.06, 0.7, body, rot=(50, 0, 0)))
    return objs


def build_elephant():
    body = mat("ele_body", C_GREY)
    ear = mat("ele_ear", C_GREY_D)
    tusk = mat("ele_tusk", C_WHITE)
    # box() halves its size arg; spans noted are ACTUAL extents.
    objs = []
    # Body: actual x[-0.32,0.32] y[-0.50,0.50] z[0.975,1.625].
    objs.append(box((0, 0, 1.3), (1.3, 2.0, 1.3), body))
    # Head: lengthened + pulled back so it overlaps the body front (body front y=-0.50)
    # while still reaching the trunk. actual y[-1.15,-0.45] z[1.0,2.0].
    objs.append(box((0, -0.80, 1.5), (1.0, 1.4, 1.0), body))
    # Trunk: top embedded in the head front (head front y=-1.15), tip kept above z=0.
    objs.append(cyl((0, -1.40, 0.95), 0.18, 1.1, body, rot=(20, 0, 0)))
    objs.append(cyl((0, -1.55, 0.55), 0.15, 0.5, body, rot=(45, 0, 0)))
    # Ears: inner edge embedded into the head sides (head x edge=0.25).
    objs.append(box((-0.28, -1.0, 1.6), (0.15, 0.7, 0.9), ear))
    objs.append(box((0.28, -1.0, 1.6), (0.15, 0.7, 0.9), ear))
    # Tusks: bases embedded into the head front (head front y=-1.15).
    objs.append(cyl((-0.25, -1.35, 1.0), 0.06, 0.6, tusk, rot=(30, 0, 0)))
    objs.append(cyl((0.25, -1.35, 1.0), 0.06, 0.6, tusk, rot=(30, 0, 0)))
    # Legs: feet at z=0, top z=1.10 (embed 0.125 into body bottom z=0.975). Hips inboard
    # of the body footprint (x+/-0.30, y+/-0.45 within x+/-0.32, y+/-0.50).
    for sx in (-0.30, 0.30):
        for sy in (-0.45, 0.45):
            objs.append(box((sx, sy, 0.55), (0.4, 0.4, 2.20), body))
    # Tail: base embedded in the body back (body back y=0.50).
    objs.append(cyl((0, 0.55, 1.1), 0.05, 0.6, body, rot=(15, 0, 0)))
    return objs


def build_giraffe():
    body = mat("gir_body", C_TAN)
    spot = mat("gir_spot", C_DARKBROWN_SPOT)
    horn = mat("gir_horn", C_BROWN_D)
    muzzle = mat("gir_muzzle", C_TAN_L)
    # NOTE: box() builds a unit cube then scales by size/2, so a box's ACTUAL full
    # extent is size/2 (the historical convention all creatures are tuned against).
    # All spans below are the resulting ACTUAL extents in Blender units.
    objs = []
    # Torso: actual x[-0.30,0.30] y[-0.50,0.50] z[1.95,2.75].
    objs.append(box((0, 0, 2.35), (1.2, 2.0, 1.6), body))
    # Neck: tilted 25deg, its base embeds in the torso top and its top meets the head.
    # actual span ~ y[-1.05,-0.27] z[2.27,3.97] (overlaps torso z<=2.75 and head).
    objs.append(box((0, -0.65, 3.05), (0.6, 0.6, 3.6), body, rot=(25, 0, 0)))
    # Head: overlaps the neck top. actual x[-0.18,0.18] y[-1.55,-0.95] z[3.55,4.05].
    objs.append(box((0, -1.25, 3.80), (0.72, 1.2, 1.0), body))
    # Muzzle: embedded into the head front. actual y[-1.75,-1.45] z[3.55,3.85].
    objs.append(box((0, -1.60, 3.70), (0.30, 0.6, 0.6), muzzle))
    # Horns: bases embedded into the head top (head top z=4.05).
    objs.append(cyl((-0.10, -1.15, 4.15), 0.05, 0.4, horn))
    objs.append(cyl((0.10, -1.15, 4.15), 0.05, 0.4, horn))
    # Spots on the torso flanks (z within torso 1.95..2.75).
    objs.append(box((-0.30, -0.2, 2.55), (0.10, 0.35, 0.30), spot))
    objs.append(box((0.30, 0.2, 2.20), (0.10, 0.35, 0.30), spot))
    objs.append(box((-0.30, 0.25, 2.10), (0.10, 0.30, 0.26), spot))
    objs.append(box((0.30, -0.25, 2.55), (0.10, 0.30, 0.26), spot))
    # Legs: feet at z=0, top at z=2.15 (embed 0.2 into torso bottom z=1.95). Hips at
    # x=+/-0.20, y=+/-0.32 -> inside the torso footprint (x+/-0.30, y+/-0.50). No gap.
    for sx in (-0.20, 0.20):
        for sy in (-0.32, 0.32):
            objs.append(box((sx, sy, 1.075), (0.32, 0.32, 4.30), body))
    return objs


def build_gnu():
    body = mat("gnu_body", C_BROWN_D)
    mane = mat("gnu_mane", C_BLACK)
    horn = mat("gnu_horn", C_GREY_D)
    # box() halves its size arg; spans noted are ACTUAL extents.
    objs = []
    # Body: actual x[-0.175,0.175] y[-0.35,0.35] z[0.775,1.225].
    objs.append(box((0, 0, 1.0), (0.7, 1.4, 0.9), body))
    # Shoulder/neck hump: pulled back so it embeds in the body front (body front y=-0.35).
    objs.append(box((0, -0.38, 1.30), (0.6, 0.6, 0.6), body))
    # Head: overlaps the neck hump (head box y[-0.80,-0.50]).
    objs.append(box((0, -0.65, 1.15), (0.45, 0.60, 0.55), body))
    # Snout: embedded into the head front (head front y=-0.80).
    objs.append(box((0, -0.85, 1.02), (0.3, 0.34, 0.40), body))
    # Mane: bridges the body, the neck hump and the head.
    objs.append(box((0, -0.45, 1.30), (0.3, 0.6, 0.7), mane))
    # Horns: bases embedded into the head top (head top z~1.425).
    objs.append(cyl((-0.18, -0.62, 1.55), 0.06, 0.4, horn, rot=(0, -50, 0)))
    objs.append(cyl((0.18, -0.62, 1.55), 0.06, 0.4, horn, rot=(0, 50, 0)))
    # Beard: under the head (head bottom z~0.875), embedded in the head front.
    objs.append(box((0, -0.78, 0.90), (0.1, 0.12, 0.4), mane))
    # Legs: feet at z=0, top z=0.90 (embed 0.125 into body bottom z=0.775). Hips inboard
    # of the body footprint (x+/-0.13, y+/-0.28 within x+/-0.175, y+/-0.35).
    for sx in (-0.13, 0.13):
        for sy in (-0.28, 0.28):
            objs.append(box((sx, sy, 0.45), (0.18, 0.18, 1.80), body))
    # Tail: base embedded in the body back (body back y=0.35).
    objs.append(cyl((0, 0.33, 0.85), 0.04, 0.5, mane, rot=(20, 0, 0)))
    return objs


def build_reindeer():
    body = mat("rein_body", C_BROWN)
    muzzle = mat("rein_muzzle", C_TAN_L)
    antler = mat("rein_antler", C_BROWN_D)
    # box() halves its size arg; spans below are ACTUAL extents.
    objs = []
    # Torso: actual x[-0.15,0.15] y[-0.32,0.32] z[0.90,1.30].
    objs.append(box((0, 0, 1.1), (0.6, 1.3, 0.8), body))
    # Neck: base embeds in the torso, leans 30deg forward up to the head.
    objs.append(box((0, -0.50, 1.30), (0.4, 0.7, 0.7), body, rot=(30, 0, 0)))
    # Head: overlaps the neck top and front.
    objs.append(box((0, -0.88, 1.62), (0.40, 0.66, 0.46), body))
    # Muzzle: embedded into the head front.
    objs.append(box((0, -1.12, 1.55), (0.30, 0.34, 0.30), muzzle))
    # Ears embed into the head sides/top (head x edge=0.10).
    objs.append(box((-0.12, -0.85, 1.78), (0.10, 0.12, 0.22), body))
    objs.append(box((0.12, -0.85, 1.78), (0.10, 0.12, 0.22), body))
    # Antlers: main beam base embeds in the head top (head top z~1.85); each tine
    # base overlaps the beam so the rack stays one connected piece.
    for sx in (-0.13, 0.13):
        objs.append(cyl((sx, -0.85, 1.95), 0.04, 0.5, antler))
        objs.append(cyl((sx * 1.55, -0.88, 2.10), 0.03, 0.3, antler, rot=(0, sx * 200, 0)))
        objs.append(cyl((sx * 1.25, -0.98, 2.08), 0.03, 0.28, antler, rot=(40, 0, 0)))
    # Legs: feet at z=0, top z=1.05 (embed 0.15 into torso bottom z=0.90). Hips inboard
    # of the torso footprint (x+/-0.10, y+/-0.20 within x+/-0.15, y+/-0.32).
    for sx in (-0.10, 0.10):
        for sy in (-0.20, 0.20):
            objs.append(box((sx, sy, 0.525), (0.16, 0.16, 2.10), body))
    # Tail: base embedded in the torso back (torso back y=0.32).
    objs.append(box((0, 0.36, 1.10), (0.12, 0.20, 0.18), muzzle))
    return objs


def build_desert_mouse():
    body = mat("mouse_body", C_SAND)
    ear = mat("mouse_ear", C_PINK)
    objs = []
    objs.append(sphere((0, 0, 0.35), 0.30, body, scale=(1.0, 1.4, 0.9)))
    objs.append(sphere((0, -0.35, 0.40), 0.20, body))
    objs.append(sphere((0, -0.52, 0.36), 0.06, ear))
    objs.append(sphere((-0.16, -0.30, 0.62), 0.14, ear, scale=(0.4, 1.0, 1.0)))
    objs.append(sphere((0.16, -0.30, 0.62), 0.14, ear, scale=(0.4, 1.0, 1.0)))
    for sx in (-0.14, 0.14):
        for sy in (-0.15, 0.15):
            objs.append(box((sx, sy, 0.08), (0.07, 0.07, 0.16), body))
    # Tail: raised + shallower tilt so its lower end stays above the foot line (z=0.04);
    # base touches the body back (body back y~0.42).
    objs.append(cyl((0, 0.42, 0.46), 0.025, 0.7, ear, rot=(48, 0, 0)))
    return objs


def build_snowman():
    snow = mat("snow", C_WHITE, rough=0.9)
    coal = mat("coal", C_BLACK)
    carrot = mat("carrot", C_ORANGE)
    stick = mat("stick", C_BROWN_D)
    hat = mat("hat", C_BLACK, rough=0.6)
    objs = []
    objs.append(sphere((0, 0, 0.55), 0.55, snow))
    objs.append(sphere((0, 0, 1.25), 0.40, snow))
    objs.append(sphere((0, 0, 1.85), 0.30, snow))
    objs.append(cone((0, -0.32, 1.88), 0.06, 0.0, 0.3, carrot, rot=(-90, 0, 0)))
    objs.append(sphere((-0.11, -0.26, 1.98), 0.04, coal))
    objs.append(sphere((0.11, -0.26, 1.98), 0.04, coal))
    for z in (1.15, 1.3):
        objs.append(sphere((0, -0.38, z), 0.045, coal))
    objs.append(cyl((-0.5, 0, 1.3), 0.03, 0.7, stick, rot=(0, 70, 0)))
    objs.append(cyl((0.5, 0, 1.3), 0.03, 0.7, stick, rot=(0, -70, 0)))
    objs.append(cyl((0, 0, 2.10), 0.34, 0.05, hat))
    objs.append(cyl((0, 0, 2.28), 0.22, 0.35, hat))
    return objs


def build_toucan():
    body = mat("tou_body", C_BLACK)
    chest = mat("tou_chest", C_WHITE)
    beak = mat("tou_beak", C_ORANGE)
    beak2 = mat("tou_beak2", C_YELLOW)
    objs = []
    objs.append(sphere((0, 0, 0.5), 0.32, body, scale=(1.0, 1.3, 1.1)))
    objs.append(sphere((0, -0.22, 0.45), 0.20, chest, scale=(0.9, 0.6, 1.0)))
    objs.append(sphere((0, -0.18, 0.85), 0.22, body))
    objs.append(cone((0, -0.55, 0.85), 0.16, 0.02, 0.6, beak, rot=(-90, 0, 0)))
    objs.append(cone((0, -0.45, 0.92), 0.10, 0.02, 0.35, beak2, rot=(-90, 0, 0)))
    objs.append(sphere((-0.10, -0.30, 0.92), 0.04, chest))
    objs.append(sphere((0.10, -0.30, 0.92), 0.04, chest))
    objs.append(box((-0.30, 0.05, 0.55), (0.08, 0.35, 0.3), body))
    objs.append(box((0.30, 0.05, 0.55), (0.08, 0.35, 0.3), body))
    objs.append(box((0, 0.35, 0.5), (0.18, 0.3, 0.1), body))
    objs.append(cyl((-0.1, 0, 0.18), 0.03, 0.3, beak))
    objs.append(cyl((0.1, 0, 0.18), 0.03, 0.3, beak))
    return objs


def build_orca():
    # Voxel orca matching the reference art (black body, white belly + eye patches,
    # dorsal fin, pectoral fins, horizontal tail flukes). Faces -Y. box() halves the
    # size arg (actual extent = size / 2); locations are in actual world units.
    # FINE voxel orca (~100 small cubes) built from a tapered voxel grid, then joined
    # into one mesh per material. Far more detailed than the old box-assembly. Faces -Y
    # (snout at low iy). V = voxel edge; cubes at integer grid cells tile seamlessly.
    black = mat("orca_black", C_BLACK, rough=0.45)
    white = mat("orca_white", C_WHITE, rough=0.45)
    eye = mat("orca_eye", (0.03, 0.03, 0.04), rough=0.3)
    V = 0.16
    cz = 0.95
    objs = []

    def vx(ix, iy, iz, m):
        objs.append(box((ix * V, iy * V, cz + iz * V), (2 * V, 2 * V, 2 * V), m))

    # CHUNKY orca: a big rounded HEAD at the front (-Y) tapering to a short thin tail (+Y).
    # half-extents (half_width, half_height) per length slice iy.
    def profile(iy):
        if iy <= -7: return (2, 2)   # rounded snout
        if iy <= -3: return (3, 3)   # big head — widest + tallest
        if iy <= -1: return (3, 2)   # shoulder
        if iy <= 1:  return (2, 2)   # mid, tapering
        if iy <= 3:  return (1, 1)   # tail
        return (0, 0)
    for iy in range(-8, 4):
        hw, hh = profile(iy)
        for ix in range(-hw, hw + 1):
            for iz in range(-hh, hh + 1):
                rx = ix / (hw + 0.6) if hw else 0.0
                rz = iz / (hh + 0.6) if hh else 0.0
                if rx * rx + rz * rz > 1.15:
                    continue
                # Belly (bottom row, fore of the tail) white; rest black.
                m = white if (hh and iz == -hh and iy < 3) else black
                vx(ix, iy, iz, m)

    # Tail peduncle + horizontal flukes (short, fanned).
    vx(0, 4, 0, black)
    for ix in (-2, -1, 0, 1, 2):
        vx(ix, 5, 0, black)

    # White eye patch (rounded, upper-front flank) + dark eye notch at its lower-front.
    for d in (-1, 1):
        vx(d * 3, -5, 1, white)
        vx(d * 3, -4, 1, white)
        vx(d * 3, -4, 0, white)
        vx(d * 3, -5, 0, eye)

    # Dorsal fin: tall, swept BACK, on the upper back just behind the head.
    vx(0, -1, 3, black)
    vx(0, -1, 4, black)
    vx(0, 0, 4, black)
    vx(0, 0, 5, black)

    # Pectoral fins: flat flippers swept DOWN + BACK from the lower-front flanks (ix=3 edge).
    for d in (-1, 1):
        vx(d * 3, -4, -2, black)
        vx(d * 4, -3, -2, black)
        vx(d * 4, -2, -3, black)
    return join_all(objs, "orca")


def build_manta():
    dark = mat("manta_dark", C_GREY_D, rough=0.5)
    light = mat("manta_light", C_WHITE, rough=0.5)
    # box() halves its size arg; spans noted are ACTUAL extents.
    objs = []
    # Central body: actual x[-0.15,0.15] y[-0.30,0.30].
    objs.append(box((0, 0, 0.5), (0.6, 1.2, 0.25), dark))
    # Wings: inner ends embedded into the central body (body x edge=0.15).
    objs.append(box((-0.45, 0, 0.5), (1.4, 0.9, 0.08), dark, rot=(0, 0, 15)))
    objs.append(box((0.45, 0, 0.5), (1.4, 0.9, 0.08), dark, rot=(0, 0, -15)))
    objs.append(box((0, 0, 0.42), (0.5, 1.0, 0.06), light))
    # Pelvic fins: bases embedded into the body front (body front y=-0.30).
    objs.append(box((-0.10, -0.30, 0.5), (0.12, 0.4, 0.08), dark))
    objs.append(box((0.10, -0.30, 0.5), (0.12, 0.4, 0.08), dark))
    # Tail: base embedded in the body back (body back y=0.30).
    objs.append(cyl((0, 0.55, 0.5), 0.04, 1.0, dark, rot=(90, 0, 0)))
    return objs


def build_jellyfish():
    bell = mat("jelly_bell", C_BLUE_L, rough=0.3, alpha=0.7)
    tent = mat("jelly_tent", C_PINK, rough=0.3, alpha=0.7)
    objs = []
    objs.append(sphere((0, 0, 1.0), 0.5, bell, scale=(1.0, 1.0, 0.8)))
    for i in range(7):
        a = i / 7.0 * math.tau
        rx = math.cos(a) * 0.28
        ry = math.sin(a) * 0.28
        objs.append(cyl((rx, ry, 0.45), 0.03, 0.9, tent))
    objs.append(cyl((0, 0, 0.55), 0.05, 0.7, tent))
    return objs


def build_bat():
    body = mat("bat_body", C_GREY_D)
    wing = mat("bat_wing", (0.22, 0.22, 0.26))
    eye = mat("bat_eye", C_ORANGE)
    objs = []
    objs.append(sphere((0, 0, 0.6), 0.18, body, scale=(1.0, 1.1, 1.2)))
    objs.append(sphere((0, -0.12, 0.78), 0.13, body))
    objs.append(cone((-0.08, -0.1, 0.92), 0.05, 0.0, 0.14, body))
    objs.append(cone((0.08, -0.1, 0.92), 0.05, 0.0, 0.14, body))
    objs.append(sphere((-0.06, -0.2, 0.80), 0.025, eye))
    objs.append(sphere((0.06, -0.2, 0.80), 0.025, eye))
    # Wings: inner ends embedded into the body (body x edge~0.175).
    objs.append(box((-0.30, 0.02, 0.62), (0.6, 0.4, 0.04), wing, rot=(0, 0, 10)))
    objs.append(box((0.30, 0.02, 0.62), (0.6, 0.4, 0.04), wing, rot=(0, 0, -10)))
    return objs


def build_laser_penguin():
    back = mat("pen_back", C_BLACK)
    front = mat("pen_front", C_WHITE)
    beak = mat("pen_beak", C_ORANGE)
    feet = mat("pen_feet", C_ORANGE)
    objs = []
    objs.append(sphere((0, 0, 0.85), 0.45, back, scale=(1.0, 0.85, 1.5)))
    objs.append(sphere((0, -0.18, 0.8), 0.36, front, scale=(0.9, 0.6, 1.4)))
    objs.append(sphere((0, 0, 1.55), 0.30, back))
    objs.append(sphere((0, -0.18, 1.50), 0.20, front, scale=(0.9, 0.5, 0.9)))
    objs.append(sphere((-0.11, -0.26, 1.60), 0.045, back))
    objs.append(sphere((0.11, -0.26, 1.60), 0.045, back))
    objs.append(cone((0, -0.34, 1.48), 0.09, 0.0, 0.25, beak, rot=(-90, 0, 0)))
    objs.append(box((-0.45, 0.05, 0.85), (0.1, 0.25, 0.6), back, rot=(0, 15, 0)))
    objs.append(box((0.45, 0.05, 0.85), (0.1, 0.25, 0.6), back, rot=(0, -15, 0)))
    # Feet: tops embedded into the body bottom (body bottom z~0.175).
    objs.append(box((-0.16, -0.12, 0.16), (0.18, 0.3, 0.1), feet))
    objs.append(box((0.16, -0.12, 0.16), (0.18, 0.3, 0.1), feet))
    return objs


# ── Registry ───────────────────────────────────────────────────────────────────
BUILDERS = {
    "monkey": build_monkey,
    "elephant": build_elephant,
    "giraffe": build_giraffe,
    "gnu": build_gnu,
    "reindeer": build_reindeer,
    "desert_mouse": build_desert_mouse,
    "snowman": build_snowman,
    "toucan": build_toucan,
    "orca": build_orca,
    "manta": build_manta,
    "jellyfish": build_jellyfish,
    "bat": build_bat,
    "laser_penguin": build_laser_penguin,
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for kind, builder in BUILDERS.items():
        clear_scene()
        _MAT_CACHE.clear()
        objs = builder()
        export(kind, objs)
    print("ALL CREATURES GENERATED")


if __name__ == "__main__":
    main()
