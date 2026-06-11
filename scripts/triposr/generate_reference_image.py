"""
Cubicraftia voxel-silhouette reference image generator for TripoSR.

Renders a pure black-on-white voxel-construction silhouette per creature.
This style is the TripoSR sweet spot: maximum contrast for clean background
removal, no interpretive ambiguity from colour, and the chunky brick
construction is preserved IN the silhouette outline itself (visible blocky
edges + stud nubs poking out the top of body sections).

Style reference: matches user-provided silhouette sheet 2026-05-31 —
pure (0,0,0) black on (255,255,255) white, chunky voxel construction
with visible stud bumps on top surfaces, clear single-subject framing.

Output: 512x512 PNG with the creature centred, ~80% bounding-box fill,
~10% margin all sides. Designed to maximise TripoSR shape coverage.

Usage:
    python3 scripts/triposr/generate_reference_image.py panda --out /tmp/panda.png

License: GPL-3.0-or-later.
"""

import os
import sys
import argparse
from PIL import Image, ImageDraw

BLACK = (0, 0, 0)
WHITE = (255, 255, 255)


# ─── Voxel primitives ─────────────────────────────────────────────────────────

def fill_voxel(d, x, y, size):
    """Fill a single 'voxel' (square) at integer grid coords."""
    d.rectangle((x, y, x + size, y + size), fill=BLACK)


def fill_voxels(d, cells, origin_x, origin_y, voxel_size):
    """Fill a list of (col, row) cells from a grid origin."""
    for col, row in cells:
        fill_voxel(d, origin_x + col * voxel_size, origin_y + row * voxel_size, voxel_size)


def fill_box(d, x, y, w, h):
    """Solid black filled rectangle (works at arbitrary px)."""
    d.rectangle((x, y, x + w, y + h), fill=BLACK)


def add_studs(d, x, y, w, voxel_size, count, stud_h_ratio=0.35):
    """Add row of round-top stud bumps on top of a horizontal section."""
    stud_h = int(voxel_size * stud_h_ratio)
    stud_w = int(voxel_size * 0.55)
    gap = (w - count * stud_w) // (count + 1) if count > 0 else 0
    for i in range(count):
        sx = x + gap + i * (stud_w + gap)
        d.ellipse((sx, y - stud_h, sx + stud_w, y + stud_h), fill=BLACK)


def cut_white(d, x, y, w, h):
    """Punch a white rectangle (eye/window/feature cut-out) inside black."""
    d.rectangle((x, y, x + w, y + h), fill=WHITE)


def cut_circle(d, cx, cy, r):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE)


# ─── Canvas ───────────────────────────────────────────────────────────────────

def new_canvas(size=512):
    img = Image.new("RGB", (size, size), WHITE)
    return img


# ─── Creature drawing functions (voxel-style black silhouettes) ──────────────

def draw_panda(img):
    """Chunky voxel panda — broad body + cube head + stubby legs."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    cx = w // 2
    V = w // 32   # voxel pitch — 32 voxels across the canvas
    # Body — 12 V wide × 8 V tall, centred lower
    body_w = 12 * V
    body_h = 8 * V
    body_x = cx - body_w // 2
    body_y = int(w * 0.50)
    fill_box(d, body_x, body_y, body_w, body_h)
    # Studs along body top
    add_studs(d, body_x, body_y, body_w, V, count=6)
    # Head — 8 V cube, sitting above body slightly offset
    head_w = 8 * V
    head_h = 8 * V
    head_x = cx - head_w // 2
    head_y = body_y - head_h + V  # overlap 1V with body
    fill_box(d, head_x, head_y, head_w, head_h)
    # Ear nubs (two black circles poking from top corners of head)
    ear_r = int(V * 1.2)
    d.ellipse((head_x - ear_r // 2, head_y - ear_r, head_x + ear_r * 2, head_y + ear_r), fill=BLACK)
    d.ellipse((head_x + head_w - ear_r * 2, head_y - ear_r, head_x + head_w + ear_r // 2, head_y + ear_r), fill=BLACK)
    # Eye cut-outs (white)
    cut_white(d, head_x + 2 * V, head_y + 3 * V, V, V)
    cut_white(d, head_x + 5 * V, head_y + 3 * V, V, V)
    # Legs — 4 chunky black boxes
    leg_w = int(V * 1.5)
    leg_h = int(V * 2)
    for x_off in (-int(body_w * 0.40), -int(body_w * 0.15), int(body_w * 0.15), int(body_w * 0.40)):
        fill_box(d, cx + x_off - leg_w // 2, body_y + body_h, leg_w, leg_h)


def draw_laser_penguin(img):
    """Voxel penguin — vertical egg-shape body with feet + beak."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    cx = w // 2
    V = w // 32
    # Body — tall narrow voxel column
    body_w = 8 * V
    body_h = 14 * V
    body_x = cx - body_w // 2
    body_y = int(w * 0.30)
    fill_box(d, body_x, body_y, body_w, body_h)
    # Studs along top
    add_studs(d, body_x, body_y, body_w, V, count=4)
    # Head pokes higher (slight notch on top centre)
    head_w = 6 * V
    head_h = 4 * V
    head_x = cx - head_w // 2
    head_y = body_y - head_h
    fill_box(d, head_x, head_y, head_w, head_h)
    # Beak (triangle nub poking forward — drawn as a small triangle)
    d.polygon([
        (head_x + head_w, head_y + 2 * V),
        (head_x + head_w + 2 * V, head_y + 2 * V + V // 2),
        (head_x + head_w, head_y + 3 * V),
    ], fill=BLACK)
    # Eye cut
    cut_white(d, head_x + head_w - 2 * V, head_y + V, V // 2, V // 2)
    # Feet (small black bumps below body)
    foot_w = int(V * 1.5)
    foot_h = int(V * 0.8)
    fill_box(d, body_x + V, body_y + body_h, foot_w, foot_h)
    fill_box(d, body_x + body_w - foot_w - V, body_y + body_h, foot_w, foot_h)


def draw_elephant(img):
    """Voxel elephant — large body + side-mounted head + trunk + 4 legs."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Body — large horizontal box, centred lower
    body_w = 16 * V
    body_h = 10 * V
    body_x = cx - body_w // 2
    body_y = int(w * 0.40)
    fill_box(d, body_x, body_y, body_w, body_h)
    add_studs(d, body_x, body_y, body_w, V, count=8)
    # Head (left side, taller than body top)
    head_w = 6 * V
    head_h = 8 * V
    head_x = body_x - head_w + 2 * V  # overlap into body
    head_y = body_y - V
    fill_box(d, head_x, head_y, head_w, head_h)
    # Ear (round bump on left of head)
    d.ellipse((head_x - 3 * V, head_y + V, head_x + V, head_y + 6 * V), fill=BLACK)
    # Trunk (descending column from front of head)
    trunk_w = int(V * 1.8)
    trunk_h = int(V * 7)
    fill_box(d, head_x + V, head_y + head_h - V, trunk_w, trunk_h)
    # Tusks (two small white triangles on the front of head — cut-outs)
    d.polygon([
        (head_x + V, head_y + head_h - V),
        (head_x + V * 2, head_y + head_h + V * 2),
        (head_x + V * 2, head_y + head_h - V),
    ], fill=WHITE)
    # Legs (4 thick boxes under body)
    leg_w = 2 * V
    leg_h = 4 * V
    leg_y = body_y + body_h
    for x_off in (int(body_w * 0.15), int(body_w * 0.40), int(body_w * 0.60), int(body_w * 0.85)):
        fill_box(d, body_x + x_off - leg_w // 2, leg_y, leg_w, leg_h)


def draw_orca(img):
    """Voxel orca — long horizontal body + tail fluke + dorsal fin."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    cy = w // 2
    # Body — long horizontal slab
    body_w = 22 * V
    body_h = 7 * V
    body_x = cx - body_w // 2
    body_y = cy - body_h // 2
    fill_box(d, body_x, body_y, body_w, body_h)
    # Head taper (cut top-left and bottom-left corners with white triangles)
    d.polygon([(body_x, body_y), (body_x + 3 * V, body_y), (body_x, body_y + 3 * V)], fill=WHITE)
    d.polygon([(body_x, body_y + body_h), (body_x + 3 * V, body_y + body_h),
               (body_x, body_y + body_h - 3 * V)], fill=WHITE)
    # Tail fluke — black triangle on right
    fluke_x = body_x + body_w
    d.polygon([
        (fluke_x, body_y + V),
        (fluke_x + 5 * V, body_y - V),
        (fluke_x + 5 * V, body_y + body_h + V),
        (fluke_x, body_y + body_h - V),
    ], fill=BLACK)
    # Dorsal fin — black triangle above body, centre
    fin_x = cx
    d.polygon([
        (fin_x - 2 * V, body_y),
        (fin_x, body_y - 5 * V),
        (fin_x + 2 * V, body_y),
    ], fill=BLACK)
    # White eye patch on head (small white rectangle near front-top)
    cut_white(d, body_x + 3 * V, body_y + V, V * 2, int(V * 1.2))


def draw_ghost(img):
    """Voxel ghost — drift column with wavy bottom + eye cuts."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    body_w = 10 * V
    body_h = 14 * V
    body_x = cx - body_w // 2
    body_y = int(w * 0.20)
    # Rounded-top body
    d.rounded_rectangle((body_x, body_y, body_x + body_w, body_y + body_h),
                        radius=body_w // 2, corners=(True, True, False, False), fill=BLACK)
    # Wavy bottom — 3 black half-circles below
    bump_w = body_w // 3
    for i in range(3):
        bx = body_x + i * bump_w
        d.ellipse((bx, body_y + body_h - bump_w, bx + bump_w * 2 - V, body_y + body_h + bump_w), fill=BLACK)
    # Eye cuts
    cut_white(d, body_x + 2 * V, body_y + 5 * V, V + V // 2, V * 2)
    cut_white(d, body_x + body_w - 3 * V - V // 2, body_y + 5 * V, V + V // 2, V * 2)
    # Open "O" mouth cut
    cut_circle(d, cx, body_y + 9 * V, V)


def draw_reindeer(img):
    """Voxel reindeer — tall body + slender head + antlers + 4 legs."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Body
    body_w = 14 * V
    body_h = 7 * V
    body_x = cx - body_w // 2
    body_y = int(w * 0.45)
    fill_box(d, body_x, body_y, body_w, body_h)
    # Head — to upper-left, neck rising
    head_w = 4 * V
    head_h = 5 * V
    head_x = body_x - 2 * V
    head_y = body_y - 8 * V
    fill_box(d, head_x, head_y, head_w, head_h)
    # Neck (vertical strip)
    fill_box(d, head_x + V, head_y + head_h, head_w - 2 * V, body_y - (head_y + head_h) + V)
    # Antlers — 2 branching shapes on top of head
    for x_off in (V // 2, head_w - V):
        d.line((head_x + x_off, head_y, head_x + x_off, head_y - 4 * V), fill=BLACK, width=V // 2)
        d.line((head_x + x_off, head_y - 2 * V, head_x + x_off - 2 * V, head_y - 4 * V),
               fill=BLACK, width=V // 2)
        d.line((head_x + x_off, head_y - 3 * V, head_x + x_off + 2 * V, head_y - 4 * V),
               fill=BLACK, width=V // 2)
    # Legs — 4 long thin
    leg_w = V
    leg_h = 6 * V
    leg_y = body_y + body_h
    for x_off in (int(body_w * 0.10), int(body_w * 0.30), int(body_w * 0.65), int(body_w * 0.85)):
        fill_box(d, body_x + x_off - leg_w // 2, leg_y, leg_w, leg_h)


def draw_snowman(img):
    """Voxel snowman — 3 stacked rounded blocks with hat + carrot nose."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Bottom ball
    fill_box(d, cx - 5 * V, int(w * 0.65), 10 * V, 8 * V)
    # Middle ball
    fill_box(d, cx - 4 * V, int(w * 0.50), 8 * V, 6 * V)
    # Head
    fill_box(d, cx - 3 * V, int(w * 0.38), 6 * V, 5 * V)
    # Hat (black wide brim + tall cylinder above head)
    fill_box(d, cx - 4 * V, int(w * 0.34), 8 * V, V)        # brim
    fill_box(d, cx - 2 * V, int(w * 0.30), 4 * V, 4 * V)    # crown
    # Carrot nose poking right
    d.polygon([
        (cx + 2 * V, int(w * 0.41)),
        (cx + 5 * V, int(w * 0.42)),
        (cx + 2 * V, int(w * 0.43)),
    ], fill=BLACK)
    # Eye cuts
    cut_white(d, cx - 2 * V, int(w * 0.40), V, V)
    cut_white(d, cx + V, int(w * 0.40), V, V)
    # Coal buttons on middle (cut white circles)
    cut_circle(d, cx, int(w * 0.55), V // 2)
    cut_circle(d, cx, int(w * 0.59), V // 2)


def draw_monkey(img):
    """Voxel monkey — upright stance with long tail + ears."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Body
    fill_box(d, cx - 4 * V, int(w * 0.45), 8 * V, 9 * V)
    # Head
    fill_box(d, cx - 4 * V, int(w * 0.30), 8 * V, 7 * V)
    # Ears (round bumps)
    d.ellipse((cx - 6 * V, int(w * 0.32), cx - 3 * V, int(w * 0.36)), fill=BLACK)
    d.ellipse((cx + 3 * V, int(w * 0.32), cx + 6 * V, int(w * 0.36)), fill=BLACK)
    # Face cut (white oval)
    cut_white(d, cx - 2 * V, int(w * 0.33), 4 * V, 3 * V)
    # Eye dots inside face cut
    cut_circle(d, cx - V, int(w * 0.35), V // 4)  # actually white-on-white, just frames a face
    # Arms — pendulum down sides
    fill_box(d, cx - 6 * V, int(w * 0.47), 2 * V, 6 * V)
    fill_box(d, cx + 4 * V, int(w * 0.47), 2 * V, 6 * V)
    # Legs
    fill_box(d, cx - 3 * V, int(w * 0.72), 2 * V, 5 * V)
    fill_box(d, cx + V, int(w * 0.72), 2 * V, 5 * V)
    # Curled tail (right side)
    fill_box(d, cx + 4 * V, int(w * 0.55), V, 8 * V)
    fill_box(d, cx + 4 * V, int(w * 0.68), 4 * V, V)


def draw_toucan(img):
    """Voxel toucan — round body + huge beak + small feet."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Body
    fill_box(d, cx - 4 * V, int(w * 0.40), 8 * V, 10 * V)
    # Head (above body, slightly forward)
    fill_box(d, cx - 4 * V, int(w * 0.32), 6 * V, 6 * V)
    # Massive beak (right-pointing curved triangle)
    d.polygon([
        (cx + 2 * V, int(w * 0.34)),
        (cx + 12 * V, int(w * 0.36)),
        (cx + 2 * V, int(w * 0.42)),
    ], fill=BLACK)
    # Feet (two pairs of small bumps)
    fill_box(d, cx - 3 * V, int(w * 0.72), V, 2 * V)
    fill_box(d, cx + 2 * V, int(w * 0.72), V, 2 * V)
    # Eye cut
    cut_white(d, cx - 2 * V, int(w * 0.34), V, V)


def draw_giraffe(img):
    """Voxel giraffe — tall neck + small head + spots-via-cuts + long legs."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Body
    fill_box(d, cx - 5 * V, int(w * 0.55), 10 * V, 6 * V)
    # Neck — tall vertical
    neck_w = 2 * V
    neck_h = 14 * V
    neck_x = cx + V
    neck_y = int(w * 0.20)
    fill_box(d, neck_x, neck_y, neck_w, neck_h)
    # Head — small box on top of neck
    fill_box(d, neck_x - V, neck_y - 3 * V, 4 * V, 3 * V)
    # Horns (2 small black sticks)
    fill_box(d, neck_x, neck_y - 5 * V, V // 2, 2 * V)
    fill_box(d, neck_x + 2 * V, neck_y - 5 * V, V // 2, 2 * V)
    # Legs (4 long thin)
    leg_w = V + V // 2
    leg_h = 7 * V
    for x_off in (-4 * V, -V, 2 * V, 4 * V):
        fill_box(d, cx + x_off, int(w * 0.55) + 6 * V, leg_w, leg_h)
    # Spot cut-outs (3 white rectangles on body)
    cut_white(d, cx - 3 * V, int(w * 0.57), V * 2, V)
    cut_white(d, cx, int(w * 0.59), V, V)
    cut_white(d, cx + 2 * V, int(w * 0.57), V * 2, V)


def draw_jellyfish(img):
    """Voxel jellyfish — dome + 5 tentacle strips."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Dome top
    fill_box(d, cx - 7 * V, int(w * 0.30), 14 * V, 4 * V)
    # Dome upper curve (rounded)
    d.ellipse((cx - 7 * V, int(w * 0.20), cx + 7 * V, int(w * 0.34)), fill=BLACK)
    # Tentacles
    for x_off in (-5 * V, -2 * V, 0, 2 * V, 5 * V):
        fill_box(d, cx + x_off, int(w * 0.34), V, 12 * V)


def draw_bat(img):
    """Voxel bat — small body + outstretched wings."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Body — small centre
    fill_box(d, cx - 2 * V, int(w * 0.40), 4 * V, 8 * V)
    # Head (above body)
    fill_box(d, cx - 2 * V, int(w * 0.32), 4 * V, 4 * V)
    # Ear nubs (two triangles pointing up)
    d.polygon([(cx - 2 * V, int(w * 0.32)), (cx - V, int(w * 0.28)), (cx, int(w * 0.32))], fill=BLACK)
    d.polygon([(cx, int(w * 0.32)), (cx + V, int(w * 0.28)), (cx + 2 * V, int(w * 0.32))], fill=BLACK)
    # Wings — left
    d.polygon([
        (cx - 2 * V, int(w * 0.40)),
        (cx - 12 * V, int(w * 0.38)),
        (cx - 10 * V, int(w * 0.50)),
        (cx - 2 * V, int(w * 0.50)),
    ], fill=BLACK)
    # Wings — right
    d.polygon([
        (cx + 2 * V, int(w * 0.40)),
        (cx + 12 * V, int(w * 0.38)),
        (cx + 10 * V, int(w * 0.50)),
        (cx + 2 * V, int(w * 0.50)),
    ], fill=BLACK)


def draw_cube_slime(img, tier="medium"):
    """Voxel cube slime — chunky cube with eye cuts and slight drip below."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Size by tier
    sz_map = {"large": 18, "medium": 12, "small": 7}
    size_v = sz_map.get(tier, 12)
    cube_w = size_v * V
    cube_h = size_v * V
    cube_x = cx - cube_w // 2
    cube_y = w // 2 - cube_h // 2
    fill_box(d, cube_x, cube_y, cube_w, cube_h)
    # Top studs
    add_studs(d, cube_x, cube_y, cube_w, V, count=max(3, size_v // 3))
    # Eye cuts (two black pupils with white rims)
    eye_size = V * 2
    eye_y = cube_y + cube_h // 3
    cut_white(d, cube_x + cube_w // 4 - eye_size // 2, eye_y, eye_size, eye_size)
    cut_white(d, cube_x + 3 * cube_w // 4 - eye_size // 2, eye_y, eye_size, eye_size)
    fill_box(d, cube_x + cube_w // 4 - V // 2, eye_y + V // 2, V, V)
    fill_box(d, cube_x + 3 * cube_w // 4 - V // 2, eye_y + V // 2, V, V)


def draw_cube_slime_large(img): draw_cube_slime(img, "large")
def draw_cube_slime_medium(img): draw_cube_slime(img, "medium")
def draw_cube_slime_small(img): draw_cube_slime(img, "small")


def draw_vampire_humanoid(img):
    """Voxel vampire — tall thin humanoid + pointed collar."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Body
    fill_box(d, cx - 3 * V, int(w * 0.40), 6 * V, 10 * V)
    # Head
    fill_box(d, cx - 3 * V, int(w * 0.25), 6 * V, 6 * V)
    # Hair / pointed top (chevron)
    d.polygon([
        (cx - 3 * V, int(w * 0.25)),
        (cx, int(w * 0.20)),
        (cx + 3 * V, int(w * 0.25)),
    ], fill=BLACK)
    # Cape — wide triangles either side
    d.polygon([
        (cx - 3 * V, int(w * 0.40)),
        (cx - 8 * V, int(w * 0.65)),
        (cx - 3 * V, int(w * 0.65)),
    ], fill=BLACK)
    d.polygon([
        (cx + 3 * V, int(w * 0.40)),
        (cx + 8 * V, int(w * 0.65)),
        (cx + 3 * V, int(w * 0.65)),
    ], fill=BLACK)
    # Legs
    fill_box(d, cx - 2 * V, int(w * 0.70), V + V // 2, 5 * V)
    fill_box(d, cx + V // 2, int(w * 0.70), V + V // 2, 5 * V)
    # Eye cuts
    cut_white(d, cx - 2 * V, int(w * 0.28), V, V)
    cut_white(d, cx + V, int(w * 0.28), V, V)


def draw_vampire_bat(img):
    """Smaller, wings-folded variant of bat — pointier ears for vampire feel."""
    draw_bat(img)
    # Add pointier extra ears
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    d.polygon([(cx - V, int(w * 0.32)), (cx - V // 2, int(w * 0.26)), (cx, int(w * 0.32))], fill=BLACK)


def draw_gnu(img):
    """Voxel gnu — bulky 4-legged grazer with curved horns."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    # Body
    fill_box(d, cx - 7 * V, int(w * 0.50), 14 * V, 7 * V)
    # Head (front-left, lower)
    fill_box(d, cx - 11 * V, int(w * 0.55), 5 * V, 5 * V)
    # Horns — two curved black bumps
    d.polygon([(cx - 11 * V, int(w * 0.55)), (cx - 13 * V, int(w * 0.50)),
               (cx - 10 * V, int(w * 0.53))], fill=BLACK)
    d.polygon([(cx - 6 * V, int(w * 0.55)), (cx - 4 * V, int(w * 0.50)),
               (cx - 7 * V, int(w * 0.53))], fill=BLACK)
    # Legs (4 thick)
    for x_off in (-5 * V, -2 * V, 2 * V, 5 * V):
        fill_box(d, cx + x_off - V, int(w * 0.57) + 6 * V, 2 * V, 5 * V)


def draw_manta(img):
    """Voxel manta ray — wide diamond wingspan."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    cy = w // 2
    # Wings + body as a single diamond
    d.polygon([
        (cx, cy - 4 * V),       # top
        (cx + 13 * V, cy),      # right wing tip
        (cx + 2 * V, cy + 3 * V),  # bottom-right notch
        (cx, cy + 8 * V),       # tail base
        (cx - 2 * V, cy + 3 * V),  # bottom-left notch
        (cx - 13 * V, cy),      # left wing tip
    ], fill=BLACK)
    # Tail (thin black line down)
    fill_box(d, cx - V // 2, cy + 8 * V, V, 6 * V)


def draw_fish(img, color="generic"):
    """Voxel fish — simple body + tail fluke + dorsal."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    cy = w // 2
    # Body (oval)
    d.ellipse((cx - 8 * V, cy - 3 * V, cx + 5 * V, cy + 3 * V), fill=BLACK)
    # Tail fluke
    d.polygon([
        (cx + 5 * V, cy - V),
        (cx + 10 * V, cy - 4 * V),
        (cx + 10 * V, cy + 4 * V),
        (cx + 5 * V, cy + V),
    ], fill=BLACK)
    # Dorsal fin top
    d.polygon([
        (cx - 3 * V, cy - 3 * V),
        (cx - V, cy - 6 * V),
        (cx + V, cy - 3 * V),
    ], fill=BLACK)
    # Eye cut (white)
    cut_circle(d, cx - 5 * V, cy - V, V // 2 + V // 4)


def draw_fish_blue(img): draw_fish(img, "blue")
def draw_fish_orange(img): draw_fish(img, "orange")
def draw_fish_yellow(img): draw_fish(img, "yellow")


def draw_desert_mouse(img):
    """Voxel mouse — small body + round ears + tail."""
    d = ImageDraw.Draw(img)
    w = img.size[0]
    V = w // 32
    cx = w // 2
    cy = w // 2 + 2 * V
    # Body
    fill_box(d, cx - 5 * V, cy, 9 * V, 5 * V)
    # Head (left side, lower)
    fill_box(d, cx - 8 * V, cy + V, 5 * V, 4 * V)
    # Round ears
    d.ellipse((cx - 9 * V, cy - V, cx - 5 * V, cy + 3 * V), fill=BLACK)
    # Tail (curled right)
    fill_box(d, cx + 4 * V, cy + 2 * V, 6 * V, V)
    # Eye
    cut_white(d, cx - 7 * V, cy + 2 * V, V, V)


# ─── Registry ────────────────────────────────────────────────────────────────

CREATURES = {
    # Hostiles (5)
    "laser_penguin":     draw_laser_penguin,
    "ghost":             draw_ghost,
    "vampire_humanoid":  draw_vampire_humanoid,
    "vampire_bat":       draw_vampire_bat,
    "bat":               draw_bat,
    "cube_slime_large":  draw_cube_slime_large,
    "cube_slime_medium": draw_cube_slime_medium,
    "cube_slime_small":  draw_cube_slime_small,
    # Atmospheric wildlife (13)
    "panda":             draw_panda,
    "desert_mouse":      draw_desert_mouse,
    "reindeer":          draw_reindeer,
    "snowman":           draw_snowman,
    "monkey":            draw_monkey,
    "toucan":            draw_toucan,
    "elephant":          draw_elephant,
    "giraffe":           draw_giraffe,
    "gnu":               draw_gnu,
    "manta":             draw_manta,
    "orca":              draw_orca,
    "fish_blue":         draw_fish_blue,
    "fish_orange":       draw_fish_orange,
    "fish_yellow":       draw_fish_yellow,
    "jellyfish":         draw_jellyfish,
}


def main():
    parser = argparse.ArgumentParser(description="Cubicraftia voxel silhouette generator for TripoSR")
    parser.add_argument("creature")
    parser.add_argument("--out", required=True)
    parser.add_argument("--size", type=int, default=512)
    args = parser.parse_args()
    if args.creature not in CREATURES:
        sys.exit(f"unknown creature '{args.creature}'. Choices: {', '.join(sorted(CREATURES))}")
    img = new_canvas(args.size)
    CREATURES[args.creature](img)
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    img.save(args.out, optimize=True)
    print(f"✓ wrote {args.out}")


if __name__ == "__main__":
    main()
