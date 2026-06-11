# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# render_creatures_lineup.py — Verification render replicating the game's
# `not is_art` normalise path: import each <kind>.glb, scale full-subtree AABB
# largest extent to a per-kind sample target height, centre X/Z, drop feet to
# ground, then lay out in a lineup on a plane. Renders a 3/4-front PNG and a
# side PNG.  Run:  blender --background --python tools/render_creatures_lineup.py

import bpy
import os
import math
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
CRE_DIR = os.path.join(REPO_ROOT, "assets", "meshes", "creatures")
OUT_DIR = os.path.join(REPO_ROOT, "tools", "_render_out")

# Per-kind target heights (mirrors wildlife.gd _TARGET_HEIGHT / hostile heights),
# scaled down by /3 so the tall ones (giraffe 5.0) fit the frame next to mice.
TARGET = {
    "monkey": 1.0, "elephant": 3.6, "giraffe": 5.0, "gnu": 1.8, "reindeer": 2.1,
    "desert_mouse": 0.4, "snowman": 1.9, "toucan": 0.5, "orca": 3.8, "manta": 1.6,
    "jellyfish": 1.0, "bat": 0.6, "laser_penguin": 1.1,
}
ORDER = ["monkey", "elephant", "giraffe", "gnu", "reindeer", "desert_mouse",
         "snowman", "toucan", "orca", "manta", "jellyfish", "bat", "laser_penguin"]


def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for c in (bpy.data.meshes, bpy.data.materials):
        for b in list(c):
            c.remove(b)


def subtree_aabb(objs):
    mn = [1e9] * 3
    mx = [-1e9] * 3
    for o in objs:
        if o.type != 'MESH':
            continue
        for corner in o.bound_box:
            w = o.matrix_world @ Vector(corner)
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return Vector(mn), Vector(mx)


def place(kind, x):
    path = os.path.join(CRE_DIR, "%s.glb" % kind)
    return import_grouped(path, TARGET[kind], (x, 0.0), centre_xy=(True, True))


def import_grouped(path, target_h, place_xy, centre_xy=(True, True)):
    """Import a glb (which arrives as FLAT, parentless meshes — Godot wraps them
    in a scene root but Blender's importer does not), parent them all under one
    Empty, then scale-largest-extent-to-target_h, centre on the requested axes,
    and drop feet to z=0.  Mirrors the game's `not is_art` normalise on the whole
    subtree.  Returns the Empty root."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    bpy.ops.object.empty_add(location=(0, 0, 0))
    root = bpy.context.active_object
    for o in new:
        o.parent = root
    bpy.context.view_layer.update()

    mn, mx = subtree_aabb(new)
    native = max((mx - mn).x, (mx - mn).y, (mx - mn).z, 1e-3)
    root.scale = (target_h / native,) * 3
    bpy.context.view_layer.update()

    mn, mx = subtree_aabb(new)
    if centre_xy[0]:
        root.location.x += place_xy[0] - (mn.x + mx.x) / 2.0
    if centre_xy[1]:
        root.location.y += place_xy[1] - (mn.y + mx.y) / 2.0
    root.location.z += -mn.z
    bpy.context.view_layer.update()
    return root


def setup_world():
    # ground
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    g = bpy.context.active_object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.5, 0.25, 1)
    g.data.materials.append(gm)
    # sun
    bpy.ops.object.light_add(type='SUN', location=(5, -8, 12))
    sun = bpy.context.active_object
    sun.data.energy = 2.0
    sun.rotation_euler = (math.radians(50), math.radians(20), math.radians(30))
    # ambient
    w = bpy.data.worlds['World']
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.7, 0.85, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.25
    bpy.context.scene.view_settings.view_transform = 'Standard'


def _look_at(cam, target):
    d = (Vector(cam.location) - Vector(target))
    cam.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()


def render(name, cam_loc, target, lens=40, res=(1920, 720)):
    scn = bpy.context.scene
    cam = bpy.data.objects.get("RCam")
    if cam is None:
        cd = bpy.data.cameras.new("RCam")
        cam = bpy.data.objects.new("RCam", cd)
        scn.collection.objects.link(cam)
    cam.location = cam_loc
    _look_at(cam, target)
    cam.data.lens = lens
    scn.camera = cam
    scn.render.engine = 'BLENDER_EEVEE'
    scn.render.resolution_x = res[0]
    scn.render.resolution_y = res[1]
    scn.render.film_transparent = False
    os.makedirs(OUT_DIR, exist_ok=True)
    scn.render.filepath = os.path.join(OUT_DIR, name)
    bpy.ops.render.render(write_still=True)
    print("Rendered", scn.render.filepath + ".png")


def contact_sheet():
    """Each creature normalised to a UNIFORM display height so small ones are
    visible, placed on a grid; one 3/4-front render. Best for silhouette/colour
    inspection (the in-game lineup keeps true relative sizes)."""
    clear()
    setup_world()
    cols = 7
    cell = 3.0
    disp_h = 2.0  # uniform display height
    for i, kind in enumerate(ORDER):
        cx = (i % cols) * cell - (cols - 1) * cell / 2.0
        cyf = (i // cols) * cell - cell * 0.5  # row 0 nearer camera (-Y), row 1 behind
        path = os.path.join(CRE_DIR, "%s.glb" % kind)
        import_grouped(path, disp_h, (cx, cyf), centre_xy=(True, True))
    bpy.context.view_layer.update()
    render("contact_sheet", (0, -20, 6), (0, 1.0, 1.1), lens=42, res=(1600, 900))
    print("CONTACT SHEET DONE")


def main():
    clear()
    setup_world()
    spacing = 4.0
    x0 = -(len(ORDER) - 1) * spacing / 2.0
    for i, kind in enumerate(ORDER):
        place(kind, x0 + i * spacing)
    span = len(ORDER) * spacing
    tgt = (0, 0, 1.2)
    # 3/4 front: camera in front (-Y, since creatures face -Y), slightly +X, raised.
    render("lineup_front", (span * 0.18, -span * 0.45, span * 0.18), tgt, lens=32)
    # side view: camera on +X looking back along -X.
    render("lineup_side", (span * 0.55, -span * 0.05, span * 0.12), tgt, lens=28)
    print("LINEUP DONE")
    contact_sheet()
    orient_check()


def orient_check():
    """Side view of a few creatures: camera on +X looking along -X. Forward is -Y,
    so a correctly-authored creature's NOSE points to the RIGHT of frame here."""
    picks = ["giraffe", "reindeer", "laser_penguin", "monkey", "elephant"]
    clear()
    setup_world()
    for i, kind in enumerate(picks):
        import_grouped(os.path.join(CRE_DIR, "%s.glb" % kind), 2.2,
                       (0.0, i * 4.0 - (len(picks) - 1) * 2.0), centre_xy=(True, True))
    bpy.context.view_layer.update()
    span = len(picks) * 4.0
    render("orient_side", (span * 0.9, 0, span * 0.18), (0, 0, 1.0),
           lens=30, res=(1600, 700))
    print("ORIENT DONE")


if __name__ == "__main__":
    main()
