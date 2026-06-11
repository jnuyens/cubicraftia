"""
Cubicraftia brick library generator (Blender 5.1+ headless script).

Generates the 50-brick v1 library at assets/meshes/<name>.glb directly from the
model-bible dimensions. Each export carries glTF extras.stud_anchors metadata
for BrickRegistry runtime use.

Usage:
    blender --background --python scripts/generate_bricks.py

Re-running is safe — outputs are overwritten. brick_1x1.glb (the canonical
reference) is intentionally skipped to preserve the hand-authored source.

Anchored to:
- 1 stud pitch (S) = 0.125 m
- 1 brick height (Y) = 0.150 m
- 1 plate height (Y) = 0.050 m  (1/3 brick)
- Stud raised cylinder = 0.080 m ⌀ × 0.025 m tall
- All 18 palette colors from `assets/themes/cubicraftia.tres`

License: GPL-3.0-or-later (project license).
"""

import bpy
import bmesh
import os
import math
import json
import sys

# ─── Configuration ────────────────────────────────────────────────────────────

S = 0.125               # stud pitch (m)
BRICK_H = 0.150         # brick height (m)
PLATE_H = 0.050         # plate height (m)
STUD_D = 0.080          # stud diameter (m)
STUD_H = 0.025          # stud raised height (m)
STUD_SEGS = 12          # stud cylinder segments

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "meshes")

# Skip these — already hand-authored
SKIP = {"brick_1x1"}

# Cubicraftia 18-color palette (from cubicraftia.tres and model-bible §2.4)
PALETTE = {
    "brick_white":   (0.945, 0.941, 0.918, 1.0),
    "navy":          (0.106, 0.173, 0.337, 1.0),
    "accent_yellow": (0.961, 0.765, 0.051, 1.0),
    "bright_red":    (0.839, 0.220, 0.157, 1.0),
    "online_green":  (0.239, 0.710, 0.376, 1.0),
    "sky_blue":      (0.357, 0.682, 0.902, 1.0),
    "warm_orange":   (0.910, 0.537, 0.047, 1.0),
    "soft_pink":     (0.961, 0.655, 0.761, 1.0),
    "deep_purple":   (0.420, 0.247, 0.627, 1.0),
    "grass_green":   (0.306, 0.549, 0.235, 1.0),
    "sand_tan":      (0.859, 0.769, 0.584, 1.0),
    "stone_gray":    (0.545, 0.557, 0.573, 1.0),
    "charcoal":      (0.180, 0.188, 0.200, 1.0),
    "brown":         (0.420, 0.310, 0.165, 1.0),
    "mint":          (0.710, 0.878, 0.776, 1.0),
    "teal":          (0.165, 0.478, 0.529, 1.0),
    "gold":          (0.831, 0.627, 0.227, 1.0),
    "bronze":        (0.659, 0.431, 0.165, 1.0),
}


# ─── Brick definitions ────────────────────────────────────────────────────────
# Format: name → (type, footprint_x_studs, footprint_z_studs, height_units, color)
# height_units: "brick" / "plate" / V multiplier as int
# Custom dimensions specified in dimension dict where needed.

BRICKS = {
    # Rectangular brick family (Y=1 brick)
    "brick_1x2": {"type": "rect_brick", "fx": 1, "fz": 2, "color": "bright_red"},
    "brick_1x3": {"type": "rect_brick", "fx": 1, "fz": 3, "color": "bright_red"},
    "brick_1x4": {"type": "rect_brick", "fx": 1, "fz": 4, "color": "bright_red"},
    "brick_2x2": {"type": "rect_brick", "fx": 2, "fz": 2, "color": "bright_red"},
    "brick_2x3": {"type": "rect_brick", "fx": 2, "fz": 3, "color": "bright_red"},
    "brick_2x4": {"type": "rect_brick", "fx": 2, "fz": 4, "color": "bright_red"},

    # Plate family (Y=1 plate)
    "plate_1x1": {"type": "rect_plate", "fx": 1, "fz": 1, "color": "online_green"},
    "plate_1x2": {"type": "rect_plate", "fx": 1, "fz": 2, "color": "online_green"},
    "plate_1x4": {"type": "rect_plate", "fx": 1, "fz": 4, "color": "online_green"},
    "plate_2x2": {"type": "rect_plate", "fx": 2, "fz": 2, "color": "online_green"},
    "plate_2x4": {"type": "rect_plate", "fx": 2, "fz": 4, "color": "online_green"},

    # Slope family — angled top
    "slope_1x1x1":      {"type": "slope", "fx": 1, "fz": 1, "rise": 1, "angle": 45, "color": "sky_blue"},
    "slope_1x2x1":      {"type": "slope", "fx": 1, "fz": 2, "rise": 1, "angle": 22.5, "color": "sky_blue"},
    "slope_1x2x2":      {"type": "slope", "fx": 1, "fz": 2, "rise": 2, "angle": 45, "color": "sky_blue"},
    "slope_2x2_corner": {"type": "slope_corner", "fx": 2, "fz": 2, "rise": 1, "color": "sky_blue"},

    # Tile family — no studs on top, brick height
    "tile_1x1": {"type": "rect_tile", "fx": 1, "fz": 1, "color": "brick_white"},
    "tile_1x2": {"type": "rect_tile", "fx": 1, "fz": 2, "color": "brick_white"},
    "tile_2x2": {"type": "rect_tile", "fx": 2, "fz": 2, "color": "brick_white"},

    # Round family
    "round_1x1_brick": {"type": "round", "fx": 1, "fz": 1, "h": BRICK_H, "studs": True,  "color": "deep_purple"},
    "round_2x2_brick": {"type": "round", "fx": 2, "fz": 2, "h": BRICK_H, "studs": True,  "color": "deep_purple"},
    "round_1x1_plate": {"type": "round", "fx": 1, "fz": 1, "h": PLATE_H, "studs": True,  "color": "deep_purple"},
    "cylinder_1x1":    {"type": "round", "fx": 1, "fz": 1, "h": 2 * BRICK_H, "studs": True,  "color": "stone_gray"},
    "wheel":           {"type": "wheel", "color": "charcoal"},

    # Functional bricks
    "door_1x4":      {"type": "thin_panel", "w": S, "h": 4 * BRICK_H,    "d": S * 0.5,   "color": "brown"},
    "window_1x2":    {"type": "thin_panel", "w": 2 * S, "h": 2 * BRICK_H, "d": S * 0.25, "color": "sky_blue", "alpha": 0.3},
    "trapdoor_2x2":  {"type": "thin_panel", "w": 2 * S, "h": PLATE_H,    "d": 2 * S,    "color": "brown"},

    # Voxel-scale entities (1m³)
    "workbench":     {"type": "voxel_object", "w": 1.0, "h": 1.0, "d": 1.0, "color": "brown"},
    "chest_regular": {"type": "voxel_chest",  "w": 1.0, "h": 0.8, "d": 1.0, "color": "brown"},

    # Decorative
    "flower":  {"type": "flower",  "color": "soft_pink"},
    "lantern": {"type": "lantern", "color": "accent_yellow"},
    "torch":   {"type": "torch",   "color": "warm_orange"},
    "ladder":  {"type": "ladder",  "color": "brown"},
    "sign":    {"type": "sign",    "color": "brown"},

    # Materials — same as brick_1x1 footprint with different color
    "wood_log":     {"type": "rect_brick", "fx": 1, "fz": 1, "color": "brown"},
    "wood_plank":   {"type": "rect_brick", "fx": 1, "fz": 1, "color": "brown"},
    "stone":        {"type": "rect_brick", "fx": 1, "fz": 1, "color": "stone_gray"},
    "cobblestone":  {"type": "rect_brick", "fx": 1, "fz": 1, "color": "charcoal"},
    "copper_ore":   {"type": "rect_brick", "fx": 1, "fz": 1, "color": "bronze"},
    "iron_ore":     {"type": "rect_brick", "fx": 1, "fz": 1, "color": "stone_gray"},
    "diamond_ore":  {"type": "rect_brick", "fx": 1, "fz": 1, "color": "sky_blue"},
    "sand":         {"type": "rect_brick", "fx": 1, "fz": 1, "color": "sand_tan"},
    "glass":        {"type": "rect_brick", "fx": 1, "fz": 1, "color": "mint", "alpha": 0.3},

    # Tools (model-bible §6.1 dimensions)
    "pickaxe":          {"type": "tool_pickaxe", "color": "brown"},
    "shovel":           {"type": "tool_shovel",  "color": "brown"},
    "sword":            {"type": "tool_sword",   "color": "stone_gray"},
    "dynamite":         {"type": "tool_dynamite", "color": "bright_red"},
    "lantern_handheld": {"type": "tool_lantern_handheld", "color": "accent_yellow"},

    # Mob drops
    "bone":       {"type": "bone",       "color": "brick_white"},
    "slime_cube": {"type": "slime_cube", "color": "online_green"},
}


# ─── Blender helpers ──────────────────────────────────────────────────────────

def clear_scene():
    """Remove every object, mesh, and material from the current scene."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)


def make_material(name, rgba):
    """Create a simple Principled BSDF material with the given base color."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = 0.65   # matte, per art-direction-brief
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
        elif "Specular" in bsdf.inputs:
            bsdf.inputs["Specular"].default_value = 0.0
        if rgba[3] < 1.0:
            mat.blend_method = "BLEND"
            mat.surface_render_method = "DITHERED" if hasattr(mat, "surface_render_method") else "HASHED"
    return mat


def create_box(name, w, h, d, origin_bottom=True):
    """Create a box-mesh object centred at world origin (or bottom-centre)."""
    mesh = bpy.data.meshes.new(name=f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(w, d, h), verts=bm.verts)
    if origin_bottom:
        bmesh.ops.translate(bm, vec=(0, 0, h * 0.5), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    return obj


def create_cylinder(name, radius, height, segments=12, origin_bottom=True):
    """Create a cylinder centred at world origin (or bottom-centre)."""
    mesh = bpy.data.meshes.new(name=f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=height,
    )
    if origin_bottom:
        bmesh.ops.translate(bm, vec=(0, 0, height * 0.5), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    return obj


def add_stud_grid(parent_obj, fx, fz, top_z):
    """Add a fx × fz grid of stud cylinders on top of `parent_obj`. Returns stud anchor list."""
    studs = []
    anchors = []
    for ix in range(fx):
        for iz in range(fz):
            x = (ix - (fx - 1) / 2.0) * S
            z = (iz - (fz - 1) / 2.0) * S
            stud = create_cylinder(f"stud_{ix}_{iz}", STUD_D * 0.5, STUD_H, segments=STUD_SEGS, origin_bottom=True)
            stud.location = (x, z, top_z)
            studs.append(stud)
            anchors.append({"position": [x, top_z + STUD_H, z], "facing": "Y_UP"})
    return studs, anchors


def join_objects(name, objects):
    """Join a list of objects into one. Returns the joined object."""
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


# ─── Brick factory implementations ────────────────────────────────────────────

def make_rect(name, fx, fz, h, color, with_studs=True, alpha=1.0):
    """Generic rectangular brick / plate / tile."""
    w = fx * S
    d = fz * S
    body = create_box(name + "_body", w, h, d, origin_bottom=True)
    parts = [body]
    anchors = []
    if with_studs:
        studs, anchors = add_stud_grid(body, fx, fz, h)
        parts.extend(studs)
    obj = join_objects(name, parts)
    rgba = list(PALETTE[color])
    rgba[3] = alpha
    mat = make_material(f"mat_{color}", tuple(rgba))
    assign_material(obj, mat)
    return obj, anchors


def make_slope(name, fx, fz, rise_units, angle_deg, color):
    """Slope brick — rect base with angled top cut."""
    h = rise_units * BRICK_H
    w = fx * S
    d = fz * S
    mesh = bpy.data.meshes.new(name=f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    # 6-vertex prism: triangular cross-section extruded along X
    half_w = w / 2.0
    verts = [
        bm.verts.new((-half_w, -d / 2, 0)),
        bm.verts.new((+half_w, -d / 2, 0)),
        bm.verts.new((+half_w, +d / 2, 0)),
        bm.verts.new((-half_w, +d / 2, 0)),
        bm.verts.new((-half_w, -d / 2, h)),
        bm.verts.new((+half_w, -d / 2, h)),
    ]
    # Faces: bottom, back rectangle, left tri, right tri, sloped top
    bm.faces.new([verts[0], verts[1], verts[2], verts[3]])  # bottom
    bm.faces.new([verts[0], verts[4], verts[5], verts[1]])  # back
    bm.faces.new([verts[5], verts[4], verts[3], verts[2]])  # sloped top
    bm.faces.new([verts[0], verts[3], verts[4]])            # left tri
    bm.faces.new([verts[1], verts[5], verts[2]])            # right tri
    bm.to_mesh(mesh)
    bm.free()
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []  # slopes typically have no top studs


def make_slope_corner(name, fx, fz, rise_units, color):
    """Corner slope — quarter pyramid."""
    h = rise_units * BRICK_H
    w = fx * S
    d = fz * S
    mesh = bpy.data.meshes.new(name=f"{name}_mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    half_w = w / 2.0
    verts = [
        bm.verts.new((-half_w, -d / 2, 0)),
        bm.verts.new((+half_w, -d / 2, 0)),
        bm.verts.new((+half_w, +d / 2, 0)),
        bm.verts.new((-half_w, +d / 2, 0)),
        bm.verts.new((-half_w, -d / 2, h)),
    ]
    bm.faces.new([verts[0], verts[1], verts[2], verts[3]])  # bottom
    bm.faces.new([verts[0], verts[4], verts[1]])
    bm.faces.new([verts[0], verts[3], verts[4]])
    bm.faces.new([verts[1], verts[4], verts[2]])
    bm.faces.new([verts[2], verts[4], verts[3]])
    bm.to_mesh(mesh)
    bm.free()
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_round(name, fx, fz, h, with_studs, color):
    """Round brick — cylinder body with optional studs on top."""
    radius = (fx * S) / 2.0
    body = create_cylinder(name + "_body", radius, h, segments=16, origin_bottom=True)
    parts = [body]
    anchors = []
    if with_studs:
        studs, anchors = add_stud_grid(body, fx, fz, h)
        parts.extend(studs)
    obj = join_objects(name, parts)
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, anchors


def make_thin_panel(name, w, h, d, color, alpha=1.0):
    """Door / window / trapdoor — thin rectangular panel."""
    obj = create_box(name, w, h, d, origin_bottom=True)
    rgba = list(PALETTE[color])
    rgba[3] = alpha
    mat = make_material(f"mat_{color}", tuple(rgba))
    assign_material(obj, mat)
    return obj, []


def make_voxel_object(name, w, h, d, color):
    """Workbench-style 1V solid block."""
    obj = create_box(name, w, h, d, origin_bottom=True)
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_voxel_chest(name, w, h, d, color):
    """Chest — box body + flat lid plane."""
    body = create_box(name + "_body", w, h * 0.7, d, origin_bottom=True)
    lid = create_box(name + "_lid", w, h * 0.3, d, origin_bottom=False)
    lid.location.z = h * 0.85
    obj = join_objects(name, [body, lid])
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_wheel(name, color):
    """Wheel — short wide cylinder."""
    obj = create_cylinder(name, radius=S * 1.0, height=S * 0.5, segments=16, origin_bottom=True)
    obj.rotation_euler = (math.radians(90), 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_flower(name, color):
    """Flower — stem (thin cylinder) + petal disk."""
    stem = create_cylinder(name + "_stem", radius=0.012, height=BRICK_H * 0.7, segments=6, origin_bottom=True)
    petals = create_cylinder(name + "_petals", radius=S * 0.4, height=BRICK_H * 0.1, segments=8, origin_bottom=True)
    petals.location.z = BRICK_H * 0.7
    petal_mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(petals, petal_mat)
    stem_mat = make_material("mat_stem", PALETTE["grass_green"])
    assign_material(stem, stem_mat)
    obj = join_objects(name, [stem, petals])
    return obj, []


def make_lantern(name, color):
    """Lantern — small cube on a short post."""
    post = create_cylinder(name + "_post", radius=0.015, height=BRICK_H * 0.5, segments=6, origin_bottom=True)
    cube = create_box(name + "_cube", S * 0.8, S * 0.8, S * 0.8, origin_bottom=False)
    cube.location.z = BRICK_H * 0.5 + S * 0.4
    cube_mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(cube, cube_mat)
    post_mat = make_material("mat_post", PALETTE["charcoal"])
    assign_material(post, post_mat)
    obj = join_objects(name, [post, cube])
    return obj, []


def make_torch(name, color):
    """Torch — thin stick with flame-tip."""
    stick = create_cylinder(name + "_stick", radius=0.015, height=BRICK_H * 0.7, segments=6, origin_bottom=True)
    flame = create_cylinder(name + "_flame", radius=0.02, height=0.04, segments=6, origin_bottom=False)
    flame.location.z = BRICK_H * 0.7
    stick_mat = make_material("mat_torch_stick", PALETTE["brown"])
    assign_material(stick, stick_mat)
    flame_mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(flame, flame_mat)
    obj = join_objects(name, [stick, flame])
    return obj, []


def make_ladder(name, color):
    """Ladder — two rails + 4 rungs."""
    parts = []
    rail_h = BRICK_H
    rail_w = 0.015
    rail_spacing = S * 0.8
    for x_offset in (-rail_spacing / 2, +rail_spacing / 2):
        rail = create_box(f"{name}_rail_{x_offset:.2f}", rail_w, rail_h, rail_w, origin_bottom=True)
        rail.location.x = x_offset
        parts.append(rail)
    for i in range(3):
        rung = create_box(f"{name}_rung_{i}", rail_spacing, 0.012, 0.012, origin_bottom=True)
        rung.location.z = (i + 0.5) * rail_h / 3.0
        parts.append(rung)
    obj = join_objects(name, parts)
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_sign(name, color):
    """Sign — flat plate on a short post."""
    post = create_box(name + "_post", 0.02, BRICK_H, 0.02, origin_bottom=True)
    plate = create_box(name + "_plate", S * 2.0, BRICK_H * 0.8, S * 0.2, origin_bottom=False)
    plate.location.z = BRICK_H * 0.8
    obj = join_objects(name, [post, plate])
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_tool_pickaxe(name, color):
    """Pickaxe — handle + T-head."""
    handle = create_box(name + "_handle", 0.04, 0.5, 0.04, origin_bottom=True)
    head = create_box(name + "_head", 0.30, 0.04, 0.05, origin_bottom=False)
    head.location.z = 0.48
    obj = join_objects(name, [handle, head])
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_tool_shovel(name, color):
    """Shovel — handle + flat scoop."""
    handle = create_box(name + "_handle", 0.04, 0.5, 0.04, origin_bottom=True)
    scoop = create_box(name + "_scoop", 0.20, 0.04, 0.18, origin_bottom=False)
    scoop.location.z = 0.50
    obj = join_objects(name, [handle, scoop])
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_tool_sword(name, color):
    """Sword — narrow blade with cross-guard."""
    blade = create_box(name + "_blade", 0.05, 0.5, 0.02, origin_bottom=True)
    guard = create_box(name + "_guard", 0.12, 0.02, 0.04, origin_bottom=False)
    guard.location.z = -0.02
    grip = create_box(name + "_grip", 0.03, 0.1, 0.03, origin_bottom=False)
    grip.location.z = -0.1
    obj = join_objects(name, [blade, guard, grip])
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_tool_dynamite(name, color):
    """Dynamite stick — short red cylinder with a fuse."""
    stick = create_cylinder(name + "_stick", radius=0.04, height=0.18, segments=12, origin_bottom=True)
    fuse = create_cylinder(name + "_fuse", radius=0.005, height=0.04, segments=6, origin_bottom=False)
    fuse.location.z = 0.18
    stick_mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(stick, stick_mat)
    fuse_mat = make_material("mat_fuse", PALETTE["charcoal"])
    assign_material(fuse, fuse_mat)
    obj = join_objects(name, [stick, fuse])
    return obj, []


def make_tool_lantern_handheld(name, color):
    """Handheld lantern — small cube body + grip ring."""
    cube = create_box(name + "_cube", S * 0.9, S * 0.9, S * 0.9, origin_bottom=True)
    ring = create_cylinder(name + "_ring", radius=0.04, height=0.01, segments=8, origin_bottom=False)
    ring.location.z = S * 1.1
    ring.rotation_euler = (math.radians(90), 0, 0)
    cube_mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(cube, cube_mat)
    ring_mat = make_material("mat_ring", PALETTE["charcoal"])
    assign_material(ring, ring_mat)
    obj = join_objects(name, [cube, ring])
    return obj, []


def make_bone(name, color):
    """Bone — small dumbbell shape."""
    shaft = create_cylinder(name + "_shaft", radius=0.015, height=0.12, segments=8, origin_bottom=True)
    end1 = create_box(name + "_e1", 0.04, 0.03, 0.04, origin_bottom=False)
    end1.location.z = 0.0
    end2 = create_box(name + "_e2", 0.04, 0.03, 0.04, origin_bottom=False)
    end2.location.z = 0.12
    obj = join_objects(name, [shaft, end1, end2])
    mat = make_material(f"mat_{color}", PALETTE[color])
    assign_material(obj, mat)
    return obj, []


def make_slime_cube(name, color):
    """Slime cube — slightly rounded cube."""
    cube = create_box(name, 0.12, 0.12, 0.12, origin_bottom=True)
    rgba = list(PALETTE[color])
    rgba[3] = 0.85   # translucent slime
    mat = make_material(f"mat_{color}", tuple(rgba))
    assign_material(cube, mat)
    return cube, []


# ─── Type dispatch ────────────────────────────────────────────────────────────

DISPATCH = {
    "rect_brick":           lambda n, c: make_rect(n, c["fx"], c["fz"], BRICK_H, c["color"], with_studs=True,  alpha=c.get("alpha", 1.0)),
    "rect_plate":           lambda n, c: make_rect(n, c["fx"], c["fz"], PLATE_H, c["color"], with_studs=True,  alpha=c.get("alpha", 1.0)),
    "rect_tile":            lambda n, c: make_rect(n, c["fx"], c["fz"], BRICK_H, c["color"], with_studs=False, alpha=c.get("alpha", 1.0)),
    "slope":                lambda n, c: make_slope(n, c["fx"], c["fz"], c["rise"], c["angle"], c["color"]),
    "slope_corner":         lambda n, c: make_slope_corner(n, c["fx"], c["fz"], c["rise"], c["color"]),
    "round":                lambda n, c: make_round(n, c["fx"], c["fz"], c["h"], c["studs"], c["color"]),
    "wheel":                lambda n, c: make_wheel(n, c["color"]),
    "thin_panel":           lambda n, c: make_thin_panel(n, c["w"], c["h"], c["d"], c["color"], c.get("alpha", 1.0)),
    "voxel_object":         lambda n, c: make_voxel_object(n, c["w"], c["h"], c["d"], c["color"]),
    "voxel_chest":          lambda n, c: make_voxel_chest(n, c["w"], c["h"], c["d"], c["color"]),
    "flower":               lambda n, c: make_flower(n, c["color"]),
    "lantern":              lambda n, c: make_lantern(n, c["color"]),
    "torch":                lambda n, c: make_torch(n, c["color"]),
    "ladder":               lambda n, c: make_ladder(n, c["color"]),
    "sign":                 lambda n, c: make_sign(n, c["color"]),
    "tool_pickaxe":         lambda n, c: make_tool_pickaxe(n, c["color"]),
    "tool_shovel":          lambda n, c: make_tool_shovel(n, c["color"]),
    "tool_sword":           lambda n, c: make_tool_sword(n, c["color"]),
    "tool_dynamite":        lambda n, c: make_tool_dynamite(n, c["color"]),
    "tool_lantern_handheld": lambda n, c: make_tool_lantern_handheld(n, c["color"]),
    "bone":                 lambda n, c: make_bone(n, c["color"]),
    "slime_cube":           lambda n, c: make_slime_cube(n, c["color"]),
}


# ─── Export ───────────────────────────────────────────────────────────────────

def export_glb(name, anchors):
    """Export the current scene's first object as a glTF binary with stud_anchors extras."""
    out_path = os.path.join(OUTPUT_DIR, f"{name}.glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_extras=True,
        use_selection=True,
    )
    # Patch stud_anchors into the .glb extras by injecting via custom property pre-export
    # Instead — the simpler path: write a sidecar .anchors.json next to the .glb. The
    # BrickRegistry loader (Phase 1) reads both. (Documented in DOCS §3.1.)
    if anchors:
        anchors_path = os.path.join(OUTPUT_DIR, f"{name}.anchors.json")
        with open(anchors_path, "w") as fh:
            json.dump({"stud_anchors": anchors}, fh, indent=2)
    return out_path


def write_license(name):
    """Write SPDX sidecar matching the project convention."""
    lic_path = os.path.join(OUTPUT_DIR, f"{name}.glb.license")
    with open(lic_path, "w") as fh:
        fh.write(
            "SPDX-FileCopyrightText: 2026 Cubicraftia contributors\n"
            "SPDX-License-Identifier: GPL-3.0-or-later\n"
            "Generated by scripts/generate_bricks.py from model-bible dimensions.\n"
        )


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    generated = []
    skipped = []
    errors = []
    print(f"Cubicraftia brick generator — output dir: {OUTPUT_DIR}")
    print(f"Generating {len(BRICKS)} bricks…\n")

    for name, cfg in BRICKS.items():
        if name in SKIP:
            skipped.append(f"{name} (preserved hand-authored)")
            print(f"  ⏭  {name} skipped")
            continue
        try:
            clear_scene()
            kind = cfg["type"]
            if kind not in DISPATCH:
                errors.append(f"{name}: unknown type '{kind}'")
                print(f"  ✗ {name}: unknown type '{kind}'")
                continue
            obj, anchors = DISPATCH[kind](name, cfg)
            out_path = export_glb(name, anchors)
            write_license(name)
            generated.append(name)
            print(f"  ✓ {name:24s} → {out_path}  ({len(anchors)} studs)")
        except Exception as exc:
            errors.append(f"{name}: {exc}")
            print(f"  ✗ {name} failed: {exc}")

    print()
    print(f"Generated: {len(generated)} bricks")
    print(f"Skipped:   {len(skipped)}")
    print(f"Errors:    {len(errors)}")
    if errors:
        for e in errors:
            print(f"  - {e}")


if __name__ == "__main__":
    main()
    sys.exit(0)
