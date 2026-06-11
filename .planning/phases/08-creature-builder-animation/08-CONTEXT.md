# Phase 8: Creature & Builder Animation - Context

**Gathered:** 2026-06-03
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — all areas accepted as recommended

<domain>
## Phase Boundary

Wire the three already-built animator POCs into the LIVE game so every creature and
the player's builder visibly animates in-world (idle when still, locomotion when
moving) with no measurable frame-rate regression. The animator systems exist
(`src/builder/minifigure_animator.gd`, `quadruped_animator.gd`,
`shader_wobble_animator.gd`, `creature_wobble.gdshader`) but are currently only
referenced by `minifigure_animator_demo.gd` — never by `wildlife.gd`,
`hostile_mob.gd`, or `builder.gd`. This phase is the integration, plus a universal
fallback so creatures that lack a dedicated rig still animate.

Requirements: ANIM-01..ANIM-06. ANIM-07 (combat/death states) is OUT of scope (nice-to-have).
</domain>

<decisions>
## Implementation Decisions

### Coverage & Approach
- Rig/wobble assets exist for only 5 mesh sets: `builder`, `panda`, `fish_blue`,
  `ghost`, `slime` (under `assets/meshes/avatars/<set>/`). The other ~18 live
  creatures use single-mesh TripoSR art with no rig.
- **Tiered approach:** use the proper systems where assets exist; apply a lightweight
  **procedural transform animation** (idle-breathe; walk bob + sway) to the existing
  TripoSR `_mesh_root`/mesh for every creature WITHOUT a dedicated rig — so every
  creature animates (meets ANIM-02 / ANIM-05) with no new rig assets.
- Soft-body creatures (slime, fish, ghost) use the existing **shader-wobble** GPU
  system (`creature_wobble.gdshader`) where the wobble mesh ships a `_body`
  MeshInstance; procedural squash fallback otherwise.

### Builder
- Swap the builder's single-mesh `builder_default.glb` avatar to the **7-piece
  MinifigureAnimator rig** (`assets/meshes/avatars/builder/`) so limbs actually move.
- Remap the avatar config skin/body/legs colours onto the rig pieces (head=skin,
  torso/arms=body, pelvis/legs=legs) — preserving the existing avatar-colour feature.
- Humanoid hostiles (vampire) share the same MinifigureAnimator rig.

### Drivers (gait)
- Velocity / AI-state driven:
  - **Builder:** horizontal speed → idle / walk / run thresholds.
  - **Wildlife:** existing `_is_walking` flag → idle / walk.
  - **Hostiles:** AI `state` → idle / walk; attack gait on the attack state.
- Gaits exposed by the animators: `idle` | `walk` | (`attack` where applicable).

### Performance (ANIM-06)
- Active + distance LOD: only animate creatures active in the world; freeze/skip
  animation updates for creatures beyond a distance threshold from the local builder.
- All motion stays **parametric** (no keyframe interpolation) — the POC animators
  already drive limb rotation per-frame; the procedural fallback is a few transform
  writes per creature. Verify against v1.0 mobile targets (reference Tier-3 device).

### Claude's Discretion
- Exact cadence/swing/threshold tuning values, LOD distance, the procedural-fallback
  motion curves, and how the fallback attaches to `_mesh_root` are at Claude's discretion.
</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/builder/minifigure_animator.gd` (`class_name MinifigureAnimator`) — rigid 7-piece
  humanoid; `@export gait/cadence_hz/swing_deg`; loads `assets/meshes/avatars/<set>/`.
- `src/builder/quadruped_animator.gd` (`class_name QuadrupedAnimator`) — 4-leg+body/head/tail.
- `src/builder/shader_wobble_animator.gd` (`class_name ShaderWobbleAnimator`) —
  GPU vertex deform; `enum BodyType { SLIME, FISH, GHOST }`; needs a `_body` MeshInstance.
- `assets/shaders/creature_wobble.gdshader` — the wobble shader.
- `assets/meshes/avatars/{builder,panda,fish_blue,ghost,slime}/` — rig piece meshes + layout.json.
- `src/builder/minifigure_animator_demo.gd` — reference wiring for all three animators.

### Established Patterns
- Wildlife (`src/world/wildlife.gd`): `_mesh_root` holds the visual; `_is_walking`
  drives movement; `_normalise_creature_mesh()` orients the TripoSR mesh; `_process()`.
- Hostiles (`src/combat/hostile_mob.gd`): `_apply_art_mesh()` builds the visual;
  `state` enum drives `_physics_process`.
- Builder (`src/builder/builder.gd`): `_setup_avatar_mesh_nodes()` builds the avatar
  (currently `builder_default.glb` single mesh + box fallback); velocity in `_physics_process`.

### Integration Points
- Replace/augment the visual-mesh creation in `wildlife._setup_*`, `hostile_mob._apply_art_mesh`,
  and `builder._setup_avatar_mesh_nodes` to attach the appropriate animator and drive its gait.
</code_context>

<specifics>
## Specific Ideas

- Keep the TripoSR single-mesh art + procedural motion as the universal fallback so
  the recent orientation/scale work (`_YAW_OVERRIDE`, feet-on-ground) is preserved.
- Don't regress the avatar-colour customisation when swapping the builder to the rig.
</specifics>

<deferred>
## Deferred Ideas

- ANIM-07: combat/death animation states (attack already exists on the rigs; hurt/death deferred).
- Per-creature dedicated rigs for the remaining ~18 creatures (procedural fallback covers them for now).
</deferred>

## Reconciliation (shipped reality vs. pre-implementation projections)

The three entries below were added 2026-06-09 after implementation shipped. They supersede the corresponding projections in the "Implementation Decisions" section above; the original projections are preserved for historical context.

- D-RECON-01 (hostile animator tier — supersedes "Humanoid hostiles (vampire) share the same MinifigureAnimator rig" from the Coverage & Approach and Builder decisions above): vampire, cube_slime, and ghost do NOT use MinifigureAnimator or ShaderWobbleAnimator rigs. Instead they use textured Meshy art loaded via HostileMob._apply_art_mesh(), with _art_kind() returning "vampire", "slime", and "ghost" respectively (not "" as originally projected). A ProceduralCreatureAnimator idle is attached on top of the textured mesh in each subclass _ready(). ANIM-05 (hostile locomotion) is satisfied by this textured-Meshy + procedural-idle path. ShaderWobbleAnimator and the avatar wobble sets remain in use for WILDLIFE fish/ghost via wildlife.gd::_setup_animator, so ANIM-01 (wildlife animation) is satisfied via that path. Sources: src/combat/vampire.gd:95-109, src/combat/cube_slime.gd:108-115.

- D-RECON-02 (builder avatar — supersedes "Swap the builder's single-mesh builder_default.glb avatar to the 7-piece MinifigureAnimator rig" from the Builder decision above): the builder evolved to a v1.1 textured rigged Meshy avatar (builder_avatar.glb + AnimationPlayer) ahead of the projected 7-piece rig swap. MinifigureAnimator is now the FALLBACK used only when the Meshy avatar asset (builder_avatar.glb) is absent. The avatar-colour customisation is preserved via the rig-colour remap on the fallback path (_apply_rig_colours maps head to skin, torso/arms to body, pelvis/legs to legs). Source: src/builder/builder.gd:1955-1963.

- D-RECON-03 (shader wobble scope — supersedes "Soft-body creatures (slime, fish, ghost) use the existing shader-wobble GPU system where the wobble mesh ships a _body MeshInstance" from the Coverage & Approach decision above): ShaderWobbleAnimator applies to ALL MeshInstance3D nodes except those whose names contain "eye", "accessor", or "pupil". The earlier rule that limited tinting to the _body MeshInstance only was a bug — exported Meshy meshes are named after the set (e.g. "fish_blue", "slime", "ghost"), so the _body match never fired and every fish rendered with the baked-blue material regardless of the configured tint colour. The fix (lines 54-68) iterates the full node subtree and applies _shader_mat to every non-eye mesh. Source: src/builder/shader_wobble_animator.gd:54-68.
