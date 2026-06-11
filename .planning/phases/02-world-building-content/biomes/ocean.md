# Biome Brief: Ocean

**ID:** `ocean` | **Phase:** 02 | **Status:** pending — awaiting user approval

---

## 1. Identity

A broad glittering expanse of blue from horizon to horizon, with the surface shimmering above
a twilight of sand and stone below. Traversing the ocean is a voyage — the biggest sense of
scale in the game. The emptiness above water makes the richness below more striking. A shipwreck
half-visible in the shallows, or stone columns of an underwater temple rising from the deep,
feel genuinely mysterious. Hardest biome to live in; most rewarding to explore.

## 2. Whittaker classification

Moisture > 0.5 (any temperature) OR cold+wet (t < −0.4 and m > 0.3).
`_classify`: `m > 0.5 OR (m > 0.3 AND t < -0.4)` → `OCEAN`.

## 3. Ambient tint

**Hex:** `#3A9EE8` — deep saturated ocean-blue; underwater areas at full saturation, surface
world slightly lightened. Anchored on `#1F7BCB` (brick blue) shifted toward cyan to read as
clear water rather than sky.

## 4. Sun colour temperature

5 800 K — near-neutral, slightly warm (`#FFF5E8`). Blue dominance comes from the ambient tint
channel rather than sun colour; represents light reflected off open water.

## 5. Terrain palette

`sand` (seabed surface) · `stone` (seabed deep) · `water` (water column) ·
`water_surface` (surface layer)

## 6. Signature flora (VoxelInstancer species)

1. `kelp_tall` — 5-8 cell vertical green-cyan tile strands; clusters of 4-8 stalks from
   sandy seabed
2. `kelp_short` — 2-4 cell variant; fills gaps between tall kelp clusters
3. `sea_grass` — 1-2 cell broad rounded flat prop on seabed; wide coverage near kelp
4. `coral_orange` — 1-2 cell branching coral in vivid orange; sparse on stone ledges
5. `coral_purple` — 1-2 cell purple-violet coral variant; alternates with orange on ledges

## 7. Atmospheric wildlife

1. **Manta ray** — wide flat diamond-shaped brick figure assembled from overlapping 2×4 and 2×2 flat plates in dark grey-blue; glides in slow sweeping arcs through mid-water above the seabed.
2. **Orca** — large elongated brick-built cetacean with a bold black-and-white plate livery and a tall dorsal fin of upright 1×2 tiles; moves in pods of 2-3 near the water surface.
3. **School of fish** — dense cluster of 8-16 small 1×2 brick fish in silver and blue; the cluster moves as a single VoxelInstancer group, shifting direction periodically to suggest shoaling behaviour.
4. **Jellyfish** — translucent dome of pale blue-cyan 2×2 curved plates with trailing 1×1 tile tentacles in white; drifts slowly upward then sinks in a gentle pulsing loop in open mid-water.

*Note: kelp is listed under §6 Signature flora, not here — it is rooted vegetation, not fauna.*

*Implementation: rendered like Village NPCs (Plan 02-13) using VoxelInstancer for non-interactive crowds; scope and exact implementation plan are deferred — these species are locked here so downstream plans can bind to them.*

## 8. Signature props

1. **Kelp-stand brick cluster** — 5-8 kelp and sea-grass props around a central sandy column;
   appears in groups of 2-3 in shallower ocean areas; marks productive-looking seabed patches.
2. **Barnacle-encrusted rock** — 2×2 dark-grey stone brick with tan 1×1 round plates on its
   face surfaces; reads as a sea-worn boulder; singly on seabed or half-protruding from sand.

## 9. Structures owned

**Abandoned shipwreck** (4-5 variants: surface, partially submerged, and fully submerged on
seabed; weathered wood and stone brick; contains loot tables per DOCS §2). **Underwater
temple** (3 variants; dark-prismarine brick; fully submerged; contains loot and creature
spawners per DOCS §2). **Shared** (all biomes): dungeons and mineshafts per DOCS §2.

## 10. Ambient sound

Deferred to a later audio pass. Target feel: two layers — surface (gentle wave lap, wind over
water, distant seabird cry) and underwater (muffled low hum, bubble streams, distant
whale-song texture) — switching based on builder camera height relative to water level.

## 11. NPC skin variants

n/a — no village in this biome.
