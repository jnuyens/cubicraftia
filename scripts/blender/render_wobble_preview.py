"""
Render a 3-up preview of the wobble-class creatures (slime / fish / ghost)
in a representative deformed pose, mirroring the formulas in
src/builder/shader_wobble_animator.gd + assets/shaders/creature_wobble.gdshader.

Output: /tmp/cubicraftia_wobble_gaits.png  (also copied to docs/)

Pose snapshots:
  Slime: mid-squash (Y * 0.85, X/Z * 1/sqrt(0.85))
  Fish:  mid-swim   (tail bent +X by amount * 0.9, head straight)
  Ghost: floated up (Y +0.10) and slight X sway
"""

import bpy
import os
import math


IN_DIR = "assets/meshes/avatars"
OUT = "/tmp/cubicraftia_wobble_gaits.png"


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _hex(s):
    h = s.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (_srgb_to_linear(r), _srgb_to_linear(g), _srgb_to_linear(b), 1.0)


def reset_scene():
    bpy.ops.wm.read_homefile(use_empty=True)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def add_floor():
    bpy.ops.mesh.primitive_plane_add(size=10, location=(0, 0, 0))
    floor = bpy.context.active_object
    mat = bpy.data.materials.new("floor")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = _hex("#D9D7CF")
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    floor.data.materials.append(mat)


def add_lighting_and_world():
    bpy.ops.object.light_add(type='SUN', location=(2, -2, 4))
    sun = bpy.context.active_object
    sun.data.energy = 4.0
    sun.data.color = (1.0, 0.97, 0.92)
    sun.rotation_euler = (math.radians(-50), math.radians(35), 0)

    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = _hex("#9EC0EE")
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
    bpy.context.scene.world = world


def import_creature(glb_rel, base_x, deform_fn):
    bpy.ops.import_scene.gltf(filepath=os.path.join(IN_DIR, glb_rel))
    for obj in bpy.context.selected_objects:
        if obj.type != "MESH":
            continue
        obj.location.x += base_x
        # apply per-vertex deformation only to the body mesh
        if obj.name.endswith("_body"):
            for v in obj.data.vertices:
                v.co = deform_fn(v.co.copy())
            obj.data.update()


def slime_pose(co):
    # mid-squash: Y * 0.78, X/Z * 1/sqrt(0.78)
    s = 0.78
    inv = 1.0 / math.sqrt(s)
    co.z *= s          # in Blender Z is up
    co.x *= inv
    co.y *= inv
    return co


def fish_pose(co):
    # tail-swim mid-pose: max bend at tail end (-Y).
    spine_length = 0.20
    along = max(0.0, min(1.0, (spine_length * 0.5 - co.y) / spine_length))
    co.x += math.sin(along * 6.28318) * 0.08 * along
    return co


def ghost_pose(co):
    # floated up + slight breath
    co.z += 0.08
    br = 1.04
    co.x *= br
    co.y *= br
    return co


def add_label(text, x, z):
    # Text faces +Y by default; rotate +90 around X so it faces the
    # camera at -Y. ALSO need a small material that reads clearly.
    bpy.ops.object.text_add(location=(x, 0.0, z))
    txt = bpy.context.active_object
    txt.data.body = text
    txt.data.size = 0.10
    txt.data.align_x = "CENTER"
    txt.rotation_euler = (math.radians(90), 0, 0)
    mat = bpy.data.materials.new(f"label_{text}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.05, 0.05, 0.05, 1)
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    txt.data.materials.append(mat)


def main():
    reset_scene()
    add_floor()
    add_lighting_and_world()

    spacing = 0.8
    import_creature("slime/slime.glb",         -spacing, slime_pose)
    import_creature("fish_blue/fish_blue.glb",   0.0,    fish_pose)
    import_creature("ghost/ghost.glb",          +spacing, ghost_pose)

    add_label("SLIME",  -spacing, 0.75)
    add_label("FISH",          0, 0.75)
    add_label("GHOST", +spacing, 1.10)

    bpy.ops.object.camera_add(
        location=(0.0, -1.8, 0.55),
        rotation=(math.radians(82), 0, 0),
    )
    cam = bpy.context.active_object
    cam.data.lens = 35
    bpy.context.scene.camera = cam

    s = bpy.context.scene
    s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x = 1536
    s.render.resolution_y = 768
    s.render.image_settings.file_format = 'PNG'
    s.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    print(f"\nWrote {OUT}")


if __name__ == "__main__":
    main()
