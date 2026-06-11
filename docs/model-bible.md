# Cubicraftia — Model Bible (v1.0)

**Purpose:** Authoritative dimension reference for every 3D model, 2D sprite, and physics volume in Cubicraftia. Anchors the entire project to a single base-unit hierarchy so a modeller, animator, or AI 3D-asset tool can never accidentally introduce inconsistent scale.

**Authority:** This file overrides any conflicting dimension in PLAN.md, RESEARCH.md, or SUMMARY.md files. If implemented code differs from this bible, the code is wrong — open a Phase 999.x fix.

**Version:** 1.0 — locked 2026-05-30.

---

## 0. The five-tier unit hierarchy

Everything in Cubicraftia descends from one number: **1 meter = 1 Godot unit**. Every other unit is a clean integer or simple fraction of that.

| Tier | Unit name | Symbol | Size (m) | Used for |
|---|---|---|---|---|
| Macro | meter | m | 1.000 | Physics, draw distance, world scale |
| Voxel | terrain cube | V | 1.000 | Terrain block grid (voxel-sandbox-style 1 V = 1 m³) |
| Brick | stud pitch | S | 0.125 | Brick footprint grid (8 S per meter, 64 S² per voxel face) |
| Builder | builder unit | BU | 0.050 | Character anatomy (30 BU = 1 builder height) |
| UI | pixel | px | (screen-dep) | Inventory slots, icons, HUD |

**Quick conversion table:**

| From | To | Multiplier |
|---|---|---|
| 1 V | m | 1.0 |
| 1 V | S | 8 |
| 1 S | m | 0.125 |
| 1 S | BU | 2.5 |
| 1 BU | m | 0.05 |
| 1 m | BU | 20 |
| 1 m | S | 8 |
| 1 m | V | 1.0 |

**Why these numbers:**
- **1 V = 1 m** matches the blocky-sandbox mental model players already understand (a "block" is roughly the height of a person standing in front of them).
- **8 S per meter** gives clean integer brick layouts (no half-stud math) and is the closest match to a real-world 8 mm brick pitch at a comfortable game camera distance.
- **20 BU per meter** makes 1 BU = 50 mm — coarse enough to align with brick layers (1 plate = 1 BU) and fine enough to express character anatomy (head, torso, legs, hand).
- **1 BU = 1 plate height** intentionally — so bricks can be "worn" as accessories at native scale.

---

## 1. World scale

### 1.1 Terrain & player physics

| Property | Value | Notes |
|---|---|---|
| Voxel size (terrain cube) | 1 m × 1 m × 1 m | locked at engine level |
| Chunk size (terrain) | 16 V × 16 V × 16 V | 16 m³ — Zylann/godot_voxel default |
| Sea level | 12 V above world bottom | DOCS §2 reference |
| Sky ceiling | 256 V above sea level | absolute world height limit |
| Render distance (Tier-1 desktop) | 8 chunks (128 m) radius | adaptive — Tier-3 mobile drops to 4 chunks |
| LOD step | every 2 chunks | distant chunks render at 2 V mesh resolution |
| Gravity | 24 m/s² | snappier than real gravity (9.8); feels right for a 1.5 m character |
| Terminal velocity | 30 m/s | clamps at 5-V/frame max safe fall |
| Daylight cycle length | 20 minutes real time = 1 Cubicraftia day | DOCS §2; matches familiar sandbox pacing within ±5% |

### 1.2 Critical fall heights

| Fall distance | Damage | Notes |
|---|---|---|
| 0–3 V (0–3 m) | 0 HP | safe |
| 4 V | 1 HP | 1/10 of full HP |
| 5 V | 2 HP | |
| 6 V | 3 HP | |
| 7+ V | (V − 3) HP per voxel | linear |
| 12+ V | death | 10 HP cap |

---

## 2. Brick library dimensions

All bricks lock to the 1 S = 0.125 m stud pitch. The 50-brick library locks at Phase 2.

### 2.1 Base brick geometry

| Property | Value (m) | Value (S) |
|---|---|---|
| Stud pitch (X, Z) | 0.125 | 1 |
| Brick height (Y) | 0.150 | 1.2 (locked non-integer to give 5:6 footprint:height ratio) |
| Plate height (Y) | 0.050 | 0.4 (1/3 brick) |
| Tile height (Y) | 0.150 | same as brick — no top studs |
| Stud raised cylinder height | 0.025 | 0.2 |
| Stud raised cylinder diameter | 0.080 | 0.64 (slightly smaller than the 1 S pitch so they don't touch at adjacent placements) |

**Visual stud rendering:** Studs are visually present on bricks but **physically inert** for placement — bricks snap to the brick-below grid, not to studs themselves. This is by design: a 1×1 brick can be placed off-centre, on grid, without stud-collision logic.

### 2.2 Locked brick footprints (subset — full 50 in `src/bricks/`)

Format: `name — X × Z stud footprint × Y height`

**Rectangular family:**
| Name | Footprint (S) | Height | Volume (m³) |
|---|---|---|---|
| `brick_1x1` | 1 × 1 | 1 brick | 0.00234 |
| `brick_1x2` | 1 × 2 | 1 brick | 0.00469 |
| `brick_1x3` | 1 × 3 | 1 brick | 0.00703 |
| `brick_1x4` | 1 × 4 | 1 brick | 0.00938 |
| `brick_2x2` | 2 × 2 | 1 brick | 0.00938 |
| `brick_2x3` | 2 × 3 | 1 brick | 0.01406 |
| `brick_2x4` | 2 × 4 | 1 brick | 0.01875 |

**Plate family (Y = 1/3 of brick):**
| `plate_1x1` | 1 × 1 | 1 plate | 0.00078 |
| `plate_1x2` | 1 × 2 | 1 plate | 0.00156 |
| `plate_1x4` | 1 × 4 | 1 plate | 0.00313 |
| `plate_2x2` | 2 × 2 | 1 plate | 0.00313 |
| `plate_2x4` | 2 × 4 | 1 plate | 0.00625 |

**Slope family (footprint same as brick, top is angled):**
| `slope_1x1x1` | 1 × 1 base | 1 brick angled 45° down one side | — |
| `slope_1x2x1` | 1 × 2 base | 1 brick angled 22.5° (gentler) | — |
| `slope_1x2x2` | 1 × 2 base | 2 bricks tall angled 45° | — |
| `slope_2x2_corner` | 2 × 2 base | 1 brick angled 45° at one corner | — |

**Tile family (footprint same as brick, no top studs):**
| `tile_1x1` | 1 × 1 | 1 brick | smooth top |
| `tile_1x2` | 1 × 2 | 1 brick | smooth top |
| `tile_2x2` | 2 × 2 | 1 brick | smooth top |

**Round family (cylinder approximations):**
| `round_1x1_brick` | 1 stud-pitch cylinder ⌀ 0.125 | 1 brick | — |
| `round_2x2_brick` | 2-stud cylinder ⌀ 0.25 | 1 brick | — |
| `round_1x1_plate` | 1 stud-pitch cylinder ⌀ 0.125 | 1 plate | — |
| `cylinder_1x1` | 1 stud-pitch cylinder ⌀ 0.125 | 2 bricks (0.3 m tall) | technic-style |

**Functional bricks (custom dimensions):**
| Name | Footprint | Height | Notes |
|---|---|---|---|
| `door_1x4` | 1 S × 4 S | 4 bricks (0.6 m) | hinge along one stud edge; door swings ±90° |
| `window_1x2` | 1 S × 2 S | 2 bricks (0.3 m) | transparent material; no studs |
| `trapdoor_2x2` | 2 S × 2 S | 1 plate (0.05 m) | hinge along one edge; opens 90° |
| `workbench` | 2 V × 1 V × 1 V | 1 m × 0.5 m × 1 m | Phase 3 — full voxel-sized utility object, not a brick |
| `chest_regular` | 2 V × 1 V × 1 V | 1 m × 0.5 m × 1 m | placed as voxel-scale entity |
| `flower` | 1 S × 1 S | 1 brick (decorative) | thin stem + petal sprite |
| `lantern` | 1 S × 1 S | 1 brick | emits PointLight3D, range 8 m |
| `torch` | 1 S × 1 S | 1 brick | emits PointLight3D, range 4 m |
| `ladder` | 1 S × 1 S | 1 brick | climb interaction zone 0.25 m deep |
| `sign` | 1 S × 2 S | 1 plate | top face is text-editable surface |

### 2.3 Brick stud-anchor metadata

Every brick `.glb` carries `extras.stud_anchors` per CLAUDE.md tech stack. Format:

```json
{
  "stud_anchors": [
    { "position": [0.0625, 0.150, 0.0625], "facing": "Y_UP" },
    { "position": [0.0625, 0.150, 0.1875], "facing": "Y_UP" }
  ]
}
```

Positions are in meters relative to the brick's local origin (bottom-back-left corner). For a 1×2 brick, two anchors on top face. For tiles, zero anchors (smooth top).

### 2.4 Brick color palette

The 18-colour palette (locked Phase 2):

| ID | Name | Hex | Notes |
|---|---|---|---|
| 0 | brick_white | #F1F0EA | core brand |
| 1 | navy | #1B2C56 | core brand |
| 2 | accent_yellow | #F5C30D | core brand |
| 3 | bright_red | #D63828 | semantic destructive |
| 4 | online_green | #3DB560 | semantic |
| 5 | sky_blue | #5BAEE6 | |
| 6 | warm_orange | #E8890C | semantic relay amber |
| 7 | soft_pink | #F5A7C2 | |
| 8 | deep_purple | #6B3FA0 | |
| 9 | grass_green | #4E8C3C | terrain accent |
| 10 | sand_tan | #DBC495 | terrain accent |
| 11 | stone_gray | #8B8E92 | terrain accent |
| 12 | charcoal | #2E3033 | "black" replacement; not pure black |
| 13 | brown | #6B4F2A | wood-tone |
| 14 | mint | #B5E0C6 | |
| 15 | teal | #2A7A87 | |
| 16 | gold | #D4A03A | |
| 17 | bronze | #A86E2A | |

Each brick `.tres` references a palette index, not a hex value — palette indices may render with subtle texture variations at runtime.

---

## 3. Builder anatomy

The builder is the player character. Phase 6 ships v1 with programmatic primitive geometry (BoxMesh per part). v1.1+ may swap in sculpted .glb parts using the same dimensions.

### 3.1 Total proportions

| Property | BU | m | Notes |
|---|---|---|---|
| Total height | 30 BU | 1.500 | from foot bottom to head top |
| Total width (shoulders) | 14 BU | 0.700 | across full torso + arms hanging |
| Total depth (chest-to-back) | 6 BU | 0.300 | |
| Eye height (camera attach point) | 26 BU | 1.300 | head Y midpoint |
| Pivot point (root) | 0 BU | 0.000 | between feet, on terrain surface |

### 3.2 Per-part dimensions (definitive)

| Part | X (width) | Y (height) | Z (depth) | Position offset (X, Y, Z from root) | Notes |
|---|---|---|---|---|---|
| **Head** | 8 BU (0.40 m) | 8 BU (0.40 m) | 8 BU (0.40 m) | (0, 22 BU, 0) | Cube. Slight bevel ≤0.5 BU per edge. Face is a flat-shaded forward-facing surface — no pixel-grid. |
| **Torso** | 10 BU (0.50 m) | 12 BU (0.60 m) | 6 BU (0.30 m) | (0, 10 BU, 0) | Rectangular box. Top-front edge bevelled 1 BU for a shoulder line. |
| **Left leg** | 4 BU (0.20 m) | 10 BU (0.50 m) | 4 BU (0.20 m) | (−2.5 BU, 0, 0) | Solid block. Slightly tapered at the foot ≤1 BU. |
| **Right leg** | 4 BU (0.20 m) | 10 BU (0.50 m) | 4 BU (0.20 m) | (+2.5 BU, 0, 0) | mirror of left |
| **Left arm** | 4 BU (0.20 m) | 10 BU (0.50 m) | 4 BU (0.20 m) | (−7 BU, 10 BU, 0) | hangs from shoulder; default pose vertical |
| **Right arm** | 4 BU (0.20 m) | 10 BU (0.50 m) | 4 BU (0.20 m) | (+7 BU, 10 BU, 0) | mirror |
| **Left hand** | 3 BU (0.15 m) | 3 BU (0.15 m) | 3 BU (0.15 m) | (−7 BU, 5 BU, 0) | end of arm; grip point for tools |
| **Right hand** | 3 BU (0.15 m) | 3 BU (0.15 m) | 3 BU (0.15 m) | (+7 BU, 5 BU, 0) | mirror |
| **Hand accessory mount** | — | — | — | right hand pivot | tools attach here; orient with grip pointing −Z |

Sum check: head (8) + torso (12) + leg (10) = 30 BU = 1.5 m ✓

### 3.3 Physics collider (used by Builder.gd)

A single CapsuleShape3D for movement; per-part shapes are visual-only.

| Property | Value | Notes |
|---|---|---|
| Capsule radius | 0.30 m (6 BU) | shoulders fit through 1 V doorway |
| Capsule height | 1.40 m (28 BU) | shorter than visual height (1.5 m) so head doesn't hit ceilings on jumps |
| Capsule centre Y | 0.75 m (15 BU) | midpoint relative to root |
| Step climb height | 0.60 m (12 BU) | can climb a 1 V terrain block via input |
| Jump initial velocity | 7.5 m/s | gives 1.5 V (1.5 m) peak jump arc; clears 1-V obstacle |
| Walk speed | 4.5 m/s (3 V/s) | brisk |
| Run speed | 7.0 m/s (4.6 V/s) | shift-modified |
| Crouch speed | 2.0 m/s | future v1.x — crouch not in v1.0 |

### 3.4 Builder animation pose offsets

| Pose | Head Y | Arm rotation (X-axis at shoulder) | Leg rotation | Notes |
|---|---|---|---|---|
| Idle | base | 0° | 0° | breathing tween Y ±0.5 BU |
| Walk | base ±0.5 BU at 2 Hz | swings ±30° at 1.2 Hz | swings ±25° at 1.2 Hz | counter-rotated |
| Run | base ±0.7 BU at 3 Hz | swings ±45° at 1.8 Hz | swings ±40° at 1.8 Hz | |
| Jump (rising) | base +1 BU | arms up +60° both | legs tucked +20° | |
| Jump (falling) | base | arms forward +30° | legs straight 0° | |
| Place brick | base | right arm forward +75°, left arm +20° | base | brick previews at hand_R + 0.5 m forward |
| Mine block | base | right arm forward swings +60° to +90° at 2 Hz | base | swing tool |
| Sleeping (in bed) | base −10 BU (rotated 90°) | arms folded at chest | legs straight | rotation applied at root pivot |
| Sit | base −8 BU | arms at sides | legs folded 90° | future use |

---

## 4. Hostile creatures (5 v1 mobs)

DOCS §5 locks the v1 hostile roster. Each creature has a bounding box (for spawn validation and collision), a visual mesh dimension, and behaviour parameters.

### 4.1 Laser penguin

| Property | Value |
|---|---|
| Bounding box | 0.5 m × 0.7 m × 0.5 m |
| Visual height | 0.6 m (12 BU) — shorter than builder |
| Visual width (waddle) | 0.4 m (8 BU) |
| Spawn biomes | snow, ice |
| Movement speed | 2.5 m/s (waddle) |
| Attack | ranged laser projectile, 8 m range, 2 HP damage |
| HP | 4 |

### 4.2 Ghost

| Property | Value |
|---|---|
| Bounding box | 0.8 m × 1.4 m × 0.8 m |
| Visual height | 1.3 m (transparent — drifts) |
| Spawn condition | night-only, in dungeons + mineshafts |
| Movement speed | 1.5 m/s |
| Wall-pass | yes — bypasses voxel collision; **repelled by bed-bubble** (1.5 V radius from registered beds) |
| Attack | melee touch, 1 HP damage |
| HP | 5 |

### 4.3 Vampire

| Property | Value (humanoid form) | Value (bat form) |
|---|---|---|
| Bounding box | 0.6 m × 1.7 m × 0.6 m | 0.3 m × 0.3 m × 0.4 m |
| Visual height | 1.5 m (matches builder) | 0.25 m wingspan flying |
| Spawn condition | night-only | transforms in daylight |
| Movement speed | 4 m/s (humanoid) | 6 m/s (bat) |
| Attack | melee bite, 3 HP damage, drains 1 HP healed to vampire | 1 HP nuisance |
| HP | 6 (humanoid) / 2 (bat) | — |
| Transform trigger | sunrise (WorldClock.is_day == true) | sunset for the reverse |

### 4.4 Regular bat (atmospheric)

| Property | Value |
|---|---|
| Bounding box | 0.25 m × 0.25 m × 0.3 m |
| Visual wingspan | 0.4 m |
| Spawn condition | dusk + caves |
| Movement speed | 5 m/s |
| Attack | none (flees) |
| HP | 1 |

### 4.5 Cube slime (tier-splitting)

| Tier | Bounding box | HP | On death |
|---|---|---|---|
| Large | 0.8 m × 0.8 m × 0.8 m | 6 | splits into 2× Medium |
| Medium | 0.5 m × 0.5 m × 0.5 m | 3 | splits into 2× Small |
| Small | 0.25 m × 0.25 m × 0.25 m | 1 | drops slime_cube item |

| Property | Value |
|---|---|
| Spawn biomes | swamp, jungle |
| Movement | hop physics — 1.5 V horizontal × 0.5 V vertical per hop, every 1.2 s |
| Attack | melee contact, 2 HP damage (large) / 1 HP (medium/small) |

---

## 5. Atmospheric wildlife

Locked Phase 2 per biome. Non-hostile. Spawn radius 32 m from player.

| Species | Biome | Bounding box (m) |
|---|---|---|
| Panda | jungle | 0.7 × 1.0 × 1.2 |
| Desert mouse | desert | 0.15 × 0.10 × 0.20 |
| Reindeer | snow | 0.8 × 1.4 × 1.8 |
| Snowman | snow (player-buildable on first snow) | 0.5 × 1.6 × 0.5 |
| Monkey | jungle | 0.4 × 0.7 × 0.6 |
| Toucan | jungle | 0.3 × 0.4 × 0.5 |
| Elephant | savannah | 1.5 × 2.5 × 3.5 |
| Giraffe | savannah | 0.8 × 4.5 × 1.2 |
| Gnu | savannah | 0.7 × 1.3 × 1.8 |
| Manta ray | ocean | 2.0 × 0.4 × 2.5 (wingspan-dominated) |
| Orca | ocean | 1.5 × 1.5 × 6.0 |
| Generic fish (3 variants) | ocean | 0.2 × 0.15 × 0.4 |
| Jellyfish | ocean | 0.5 × 0.8 × 0.5 |

---

## 6. Items, tools, structures

### 6.1 Handheld tools (attach to right hand)

All tools fit a "tool socket" of max 0.4 m × 0.6 m × 0.1 m in the right hand.

| Tool | Mesh size (m) | Hand pivot offset | Notes |
|---|---|---|---|
| Pickaxe (wood) | 0.3 × 0.5 × 0.05 | (0, 0, −0.05) | head at top |
| Pickaxe (bronze) | 0.3 × 0.5 × 0.05 | same | larger head, bronze palette |
| Pickaxe (iron) | 0.3 × 0.5 × 0.05 | same | iron palette |
| Pickaxe (diamond) | 0.3 × 0.5 × 0.05 | same | diamond crystal mesh on head |
| Shovel | 0.2 × 0.5 × 0.05 | (0, 0, −0.05) | narrower head |
| Sword | 0.1 × 0.6 × 0.05 | (0, 0, −0.05) | long thin |
| Dynamite stick | 0.1 × 0.2 × 0.1 | (0, 0, −0.05) | red cylinder |
| Handheld lantern | 0.15 × 0.25 × 0.15 | (0, 0, −0.10) | emits PointLight3D range 5 m, attached to builder |

### 6.2 Structure entities (placed via voxel grid)

| Structure | Footprint (V) | Visual height | Interactable height |
|---|---|---|---|
| Bed | 1 × 2 | 0.5 m | bottom 0.5 V (lay down) |
| Workbench | 1 × 1 | 1.0 m | top face |
| Chest (regular, bronze, silver, gold, diamond) | 1 × 1 | 0.8 m | top face — opens on `interact` |
| Double chest | 1 × 2 | 0.8 m | combines two adjacent chests |
| Lantern (placed) | 1 × 1 | 1.5 m (post + lantern) | light source PointLight3D range 8 m |
| Sign | 0.5 × 0.5 | 1.0 m (post + plate) | text-editable via UI |

### 6.3 Brick-derived weapons & tools (recipes)

| Item | Recipe pattern (in 3×3 grid) | Result count | Durability (use uses) |
|---|---|---|---|
| `pickaxe_wood` | top row: 3× wood_plank, middle: stick in centre, bottom: stick in centre | 1 | 60 |
| `pickaxe_bronze` | top row: 3× bronze_ingot, middle: stick centre, bottom: stick centre | 1 | 150 |
| `sword_wood` | top: plank centre, middle: plank centre, bottom: stick centre | 1 | 50 |
| `sword_iron` | same pattern, iron_ingot | 1 | 200 |
| `shovel_wood` | top: plank centre, middle: stick centre, bottom: stick centre | 1 | 50 |
| `dynamite` | top: paper centre, middle: gunpowder centre, bottom: stick centre | 4 | 1 (consumable) |
| `torch` | top: coal centre, middle: stick centre | 4 | 600 sec burn time |
| `stick` (shapeless) | 2× wood_plank anywhere | 4 | — |
| `wood_plank` (shapeless) | 1× wood_log | 4 | — |

(Full list of ~10 recipes in `src/crafting/recipes/*.tres`.)

---

## 7. Camera & motion

### 7.1 Third-person chase camera (default)

Locked Phase 2 (Plan 02-08.5).

| Property | Value |
|---|---|
| Offset behind builder | 4 m (32 BU) |
| Offset above builder | 1.2 m (24 BU) |
| Focus target | builder head + 0.5 m forward |
| FOV | 75° (desktop), 80° (mobile portrait-aware) |
| Camera smoothing | Lerp factor 0.15 per frame at 60 fps |
| Pitch range | −60° (looking down) to +20° (looking up) |
| RMB-held + mouse | mouse X → yaw (rotates builder), mouse Y → camera pitch |
| Mouse motion no-RMB | ignored (cursor free for UI) |

### 7.2 First-person camera (toggle reserved for v1.x)

| Property | Value |
|---|---|
| Eye height | 1.3 m (26 BU) |
| Forward offset from head | 0.05 m |
| FOV | 90° |

### 7.3 Bird's-eye preview (avatar creator + world thumbnail capture)

| Property | Value |
|---|---|
| Camera position | (0, 3 m, 4 m) relative to builder |
| Camera look-at | builder center |
| FOV | 35° (telephoto-feel; flattens the silhouette) |

### 7.4 World thumbnail capture

| Property | Value |
|---|---|
| Capture resolution | 256 × 144 px (16:9) |
| Capture timing | 1 frame after WorldSave.save (avoids UI overlays) |
| Encoding | JPEG quality 85 |
| Saved path | `user://worlds/{world_id}/thumbnail.jpg` |

---

## 8. Inventory & HUD UI grids

UI scales from screen DPI but layout grid is in CSS-like pixels.

### 8.1 Inventory slide-in (Phase 3)

| Element | Size (px) | Notes |
|---|---|---|
| Slide-in panel width (desktop) | 360 | from right edge |
| Slide-in panel width (mobile) | 100% screen | bottom sheet |
| Slot size | 48 × 48 | with 4 px outer padding = 56 unit grid |
| Slot gutter | 8 | 8 px between slots |
| Slot icon | 32 × 32 | centered inside slot |
| Count badge | 16 × 16 | bottom-right corner |
| Inventory grid | 6 cols × 8 rows | 48 slots total |
| Hotbar | 1 row of 8 slots | bottom of screen, slightly larger 56 × 56 |
| Hotbar Y offset | 16 px from screen bottom (mobile: 80 px to avoid notch) | |

### 8.2 Brick palette (Phase 2/3)

| Element | Size (px) | Notes |
|---|---|---|
| Tile size | 64 × 64 | larger than inventory for tappability |
| Tile icon | 48 × 48 | |
| Category chip | 32 × 96 | text chip |
| Search bar | 320 × 40 | top of palette |

### 8.3 Player nameplate (in-world Label3D)

| Property | Value |
|---|---|
| Position above head | +0.7 m (14 BU) |
| Billboard mode | enabled |
| Font size | 14 px at 2 m camera distance |
| Fade start | 16 m |
| Fade end | 20 m |
| Background pill | 4 px horizontal padding, navy 0.85α |
| Nameplate row height | 24 px |

---

## 9. World structures (procedurally generated)

22 hand-authored templates locked Phase 2. All voxel-grid sized.

### 9.1 Villages

| Type | Footprint (V) | Notes |
|---|---|---|
| Snow village | 32 × 32 | igloos + central fire pit |
| Desert village | 28 × 28 | adobe huts + well |
| Savannah village | 24 × 24 | thatched-roof huts + watering hole |

Each variant ships 3 templates (a, b, c). All spawn with a chunk-aligned origin.

### 9.2 Temples

| Type | Footprint (V) | Notes |
|---|---|---|
| Jungle temple | 16 × 16 × 8 tall | aboveground stepped pyramid |
| Underwater temple | 24 × 24 × 12 tall | submerged ruin |

### 9.3 Shipwrecks

| Type | Footprint (V) | Notes |
|---|---|---|
| Surface | 20 × 8 × 6 | beached/coastal |
| Submerged | 20 × 8 × 6 | seabed |

### 9.4 Dungeons

| Property | Value |
|---|---|
| Footprint | 16 × 16 × 4 | single underground floor |
| Spawn depth | 16–48 V below sea level |
| Mob spawner | 1 per dungeon (ghost or vampire) |

### 9.5 Mineshafts (procedurally-stitched corridors)

| Piece | Footprint (V) | Notes |
|---|---|---|
| Corridor straight | 5 × 1 × 3 | wood ribs, rail track |
| Corridor cross | 5 × 5 × 3 | 4-way intersection |
| Corridor T-junction | 5 × 5 × 3 | 3-way |
| Corridor room | 9 × 9 × 4 | larger chamber, loot chest spawn |
| Corridor dead-end | 5 × 1 × 3 | terminal |

Pieces snap on stud-aligned XZ origin + voxel-aligned Y.

---

## 10. Doors, gates, portals

| Element | Footprint (V) | Notes |
|---|---|---|
| Standard doorway opening (in voxel build) | 1 × 1 wide × 2 tall | 1 m × 2 m — clears 1.5 m builder + headroom |
| Wide doorway | 2 × 1 × 2 | 2-builder-wide |
| Gate (decorative) | 3 × 1 × 3 | gateway frame |
| Trapdoor opening (floor) | 1 × 1 (XZ) | for ladders/mineshaft entrances |

### 10.1 Door brick (`door_1x4`)

The placeable brick that fills a doorway opening:

| Property | Value |
|---|---|
| Brick footprint | 1 stud-pitch × 4 studs tall × 0.5 stud thick | 0.125 m × 0.5 m × 0.0625 m |
| Hinge axis | along one stud edge (X-axis) |
| Open angle | ±90° |
| Open trigger | `interact` (Left Shift) while looking at the door |

**Door + opening ratio:** A standard 1×1×2 doorway opening (1 m × 2 m) hosts **8 vertical `door_1x4` bricks stacked** (or 2 sets of 4-stud-tall bricks) along the hinge edge. Most player builds use a more compact 1×1×2 *voxel-scale* door entity (placed as a single object) rather than the brick. The brick version exists for fine-detail builds.

---

## 11. Lighting & visibility ranges

| Light source | PointLight3D range (m) | Energy | Color |
|---|---|---|---|
| Handheld lantern | 5 | 1.2 | warm yellow #FFE08A |
| Placed lantern | 8 | 1.5 | warm yellow #FFE08A |
| Torch (placed) | 4 | 0.8 | warm orange #FFB347 |
| Brick mob "ghost" glow | 2 | 0.6 | pale blue #88B3DD |
| Brick mob "fire" puff | 1.5 | 1.0 (decaying over 0.3s) | orange-red #FF6B33 |
| Lava block | 6 | 1.0 | orange #FF8530 |
| Sky panorama dawn | (directional) | 1.0 | warm pink #FFB199 |
| Sky panorama day | (directional) | 1.5 | warm white #FFF5E6 |
| Sky panorama dusk | (directional) | 0.8 | warm orange #FFA866 |
| Sky panorama night | (directional, moon) | 0.3 | cool blue #6E8DBA |

---

## 12. Acceptance test — silhouette check

Before any new model ships, validate against this silhouette test:

1. **Place the model at game origin (0, 0, 0)** in a Godot test scene
2. **Add a Builder reference next to it** — known 1.5 m tall capsule
3. **Render at 8 m camera distance, 75° FOV, eye-height camera**
4. **Compare on-screen pixel height** to the dimension table — should match the listed m × pixel-per-meter for the test viewport
5. **Take a 256×144 screenshot, place next to the world thumbnail of an existing build**
6. **Eyeball test:** does the new model look like it belongs in the same world? Or does scale read wrong?

If the answer is "scale reads wrong", the issue is almost always that source units were inches/feet/cm rather than meters. Confirm exporter unit is meters. Re-verify.

---

## 13. Quick reference — "what size is this thing?"

| Asset | One-line spec |
|---|---|
| 1 voxel | 1 m³ |
| 1 stud pitch | 0.125 m |
| 1×1 brick | 0.125 × 0.150 × 0.125 m |
| 2×4 brick | 0.250 × 0.150 × 0.500 m |
| Builder total | 0.70 × 1.50 × 0.30 m (X × Y × Z) |
| Builder head | 0.40 × 0.40 × 0.40 m |
| Builder torso | 0.50 × 0.60 × 0.30 m |
| Builder leg (each) | 0.20 × 0.50 × 0.20 m |
| Builder arm (each) | 0.20 × 0.50 × 0.20 m |
| Builder hand (each) | 0.15 × 0.15 × 0.15 m |
| Doorway (voxel-built) | 1 × 2 m (W × H) |
| Door brick | 0.125 × 0.500 × 0.063 m |
| Sword | 0.10 × 0.60 × 0.05 m |
| Bed | 1 × 0.5 × 2 m (V-footprint × height) |
| Chest | 1 × 0.8 × 1 m |
| Workbench | 1 × 1 × 1 m |
| Lantern (placed) | 1 V tall, light range 8 m |
| Cube slime (large) | 0.8 × 0.8 × 0.8 m |
| Elephant | 1.5 × 2.5 × 3.5 m |
| Camera follow distance | 4 m behind, 1.2 m above |
| Render distance (desktop) | 128 m radius |
| Jump height | 1.5 m peak |
| Walk speed | 4.5 m/s |
| 1 inventory slot | 48 × 48 px |
| Nameplate Y offset | 0.7 m above head |

---

## 14. Sign-off

When any new 3D asset is delivered:

- [ ] Exporter unit = meters
- [ ] Origin at the gameplay-meaningful pivot (root for builders, bottom-centre for static objects)
- [ ] Bounding-box checked against §3 / §4 / §6 / §9 tables
- [ ] glTF `extras.stud_anchors` populated if the model is a brick
- [ ] Materials: matte, no metalness, no specular (per art-direction-brief §1.5)
- [ ] Test scene render at standard FOV passes silhouette check (§12)
- [ ] Sibling `.license` file in SPDX format
- [ ] Code path that loads the asset still works (`godot --headless --quit-after 5`)

When code changes a dimension defined in this bible, update this file *first* and link the commit. If the bible says builder is 1.5 m and the code makes it 1.7 m, the bible is the source of truth — fix the code.

---

*Bible authored 2026-05-30 at v1.0 milestone close. Anchors every dimension across the codebase. Maintain alongside `docs/art-direction-brief.md` going forward.*
