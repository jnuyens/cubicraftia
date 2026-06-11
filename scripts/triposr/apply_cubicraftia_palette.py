"""
Apply Cubicraftia palette materials to TripoSR-generated meshes.

TripoSR outputs meshes with vertex-colour or texture data baked from the
2D reference image. For Cubicraftia we want clean matte palette materials
per docs/model-bible.md §1.5 (matte, no specular, no metalness, palette-
locked colours).

This script loads each `<name>_triposr.glb` in assets/meshes/creatures/,
strips its existing material, applies a per-creature Cubicraftia palette
material, and exports the result as `<name>.glb` (overwriting the
procedural primitive that was there).

Usage:
    blender --background --python scripts/triposr/apply_cubicraftia_palette.py

License: GPL-3.0-or-later.
"""

import bpy
import os
import sys

REPO = "/Users/jnuyens/src/Cubicraftia"
MESH_DIR = os.path.join(REPO, "assets", "meshes", "creatures")

# Per-creature palette material assignment (matches model-bible §2.4 + §4-5)
# Format: name → (base_color RGBA, roughness)
PALETTE = {
    # Hostiles
    "laser_penguin":     ((0.106, 0.173, 0.337, 1.0), 0.65),   # navy body
    "ghost":             ((0.65, 0.78, 0.92, 0.85), 0.70),     # pale blue translucent
    "vampire_humanoid":  ((0.84, 0.22, 0.16, 1.0), 0.55),      # bright red cape
    "vampire_bat":       ((0.18, 0.19, 0.20, 1.0), 0.65),      # charcoal
    "bat":               ((0.42, 0.31, 0.16, 1.0), 0.70),      # brown
    "cube_slime_large":  ((0.24, 0.71, 0.38, 0.88), 0.40),     # online green translucent
    "cube_slime_medium": ((0.24, 0.71, 0.38, 0.88), 0.40),
    "cube_slime_small":  ((0.24, 0.71, 0.38, 0.88), 0.40),

    # Atmospheric wildlife
    "panda":         ((0.945, 0.941, 0.918, 1.0), 0.70),       # brick-white
    "desert_mouse":  ((0.859, 0.769, 0.584, 1.0), 0.70),       # sand-tan
    "reindeer":      ((0.420, 0.310, 0.165, 1.0), 0.70),       # brown
    "snowman":       ((0.945, 0.941, 0.918, 1.0), 0.55),       # brick-white
    "monkey":        ((0.420, 0.310, 0.165, 1.0), 0.70),       # brown
    "toucan":        ((0.180, 0.188, 0.200, 1.0), 0.65),       # charcoal w/ yellow beak (single mat OK)
    "elephant":      ((0.545, 0.557, 0.573, 1.0), 0.70),       # stone-gray
    "giraffe":       ((0.859, 0.769, 0.584, 1.0), 0.70),       # sand-tan
    "gnu":           ((0.659, 0.431, 0.165, 1.0), 0.70),       # bronze/brown
    "manta":         ((0.106, 0.173, 0.337, 1.0), 0.65),       # navy
    "orca":          ((0.180, 0.188, 0.200, 1.0), 0.65),       # charcoal
    "fish_blue":     ((0.357, 0.682, 0.902, 1.0), 0.45),
    "fish_orange":   ((0.910, 0.537, 0.047, 1.0), 0.45),
    "fish_yellow":   ((0.961, 0.765, 0.051, 1.0), 0.45),
    "jellyfish":     ((0.420, 0.247, 0.627, 0.65), 0.30),       # deep purple translucent
}


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)


def make_palette_material(name, rgba, roughness):
    mat = bpy.data.materials.new(name=f"cubicraftia_{name}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        return mat
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    # Zero specular / zero metalness — matte per art-direction-brief §1.5
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = 0.0
    if rgba[3] < 1.0:
        mat.blend_method = "BLEND"
    return mat


def process_creature(name):
    src = os.path.join(MESH_DIR, f"{name}_triposr.glb")
    dst = os.path.join(MESH_DIR, f"{name}.glb")
    if not os.path.exists(src):
        return False, f"missing {src}"
    if name not in PALETTE:
        return False, f"no palette entry for {name}"

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=src)

    # Find imported mesh objects (TripoSR usually puts one)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        return False, "no mesh found in glb"

    rgba, roughness = PALETTE[name]
    mat = make_palette_material(name, rgba, roughness)

    for mesh_obj in meshes:
        # Strip existing materials, replace with palette mat
        mesh_obj.data.materials.clear()
        mesh_obj.data.materials.append(mat)
        # If the mesh has vertex colors that override material color, remove them
        if mesh_obj.data.color_attributes:
            for attr in list(mesh_obj.data.color_attributes):
                mesh_obj.data.color_attributes.remove(attr)

    # Export
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=dst,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        use_selection=True,
    )
    return True, dst


def main():
    if not os.path.isdir(MESH_DIR):
        sys.exit(f"missing {MESH_DIR}")
    targets = []
    for name in PALETTE:
        if os.path.exists(os.path.join(MESH_DIR, f"{name}_triposr.glb")):
            targets.append(name)

    print(f"Cubicraftia palette post-process — {len(targets)} TripoSR meshes")
    ok, fail = 0, 0
    for name in targets:
        success, msg = process_creature(name)
        if success:
            print(f"  ✓ {name:24s} → {msg}")
            ok += 1
        else:
            print(f"  ✗ {name:24s}: {msg}")
            fail += 1

    print(f"\nDone: {ok} ok, {fail} failed.")


if __name__ == "__main__":
    main()
