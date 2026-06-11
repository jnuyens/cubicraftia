# Art still needed — sorted by priority

Companion to `docs/art-direction-brief.md` and `docs/model-bible.md`. Lists
every asset still procedural/placeholder/missing after the 23-creature batch
lands. Sorted by player-visible impact so you can sprint commission art in
batches that match your design tool sessions.

**Format reminder:** all assets ship in the Cubicraftia palette (see
art-direction-brief §1.3) and follow the trademark-avoidance
rules (§1.2). Drop files at the named path and Godot will pick them up; no
code changes needed.

---

## Batch A — Title screen hero set (HIGHEST priority)

These define first impression. Current procedural placeholders are obviously
programmer-art.

| File | Size | Format | What |
|---|---|---|---|
| `assets/textures/icons/title_bg.png` | 1920×1080 (or seamless 1024×1024 tile) | PNG-24 | Composed brick-world vista — golden-hour rolling brick terrain, distant village, a few yellow-accent details (wheat, lantern glow). Painterly soft-edge, *not* the procedural stud-dot pattern that ships today. Goal: "I want to play this." |
| `assets/textures/icons/cubicraftia_wordmark.png` | 1024×256 | PNG-24, alpha | Designed wordmark — custom letterforms or font with brick-aware treatment (one letter substituted with a brick, accent-yellow underline). Current asset is just NotoSans rendered to PNG. |
| `assets/textures/icons/title_character.png` *(new)* | 512×768 | PNG-24, alpha | Hero builder portrait — three-quarter view, hand on hip, default avatar pose, slight personality. Composes onto title screen left of wordmark. |

**Batch size:** 3 files. Roughly half a day of designer time.

---

## Batch B — Title music + core SFX (audio)

Sox-synthesised placeholders ship today; replace before any public showing.
Cubicraftia has zero audio AI tooling installed, so this batch is pure
human/commissioned work.

### Music (3 tracks)

| File | Length | What |
|---|---|---|
| `assets/audio/title_loop.ogg` | 90 s seamless loop | Warm, gentle, optimistic. Acoustic guitar + soft synth + glockenspiel. Like *Stardew Valley* title × *Animal Crossing* menu. 80–95 BPM, major key, -16 LUFS. |
| `assets/audio/world_day.ogg` *(new)* | 3 min loop | Daytime ambient — light pad + occasional flute or wind chime. Plays during normal exploration. |
| `assets/audio/world_night.ogg` *(new)* | 3 min loop | Night ambient — slightly darker pad, distant low woodwind. Subtle tension without scares. |

### SFX (~30 essential events)

Bundle as a single ZIP or per-file. All OGG mono 44.1 kHz quality 5, normalised -16 LUFS, length 0.1–2.0 s each.

| Category | Files |
|---|---|
| **Brick** | place_brick.ogg, break_brick.ogg, brick_pickup.ogg, palette_open.ogg, palette_select.ogg |
| **Builder** | footstep_grass.ogg, footstep_stone.ogg, footstep_wood.ogg, footstep_sand.ogg, jump.ogg, land_soft.ogg, land_hurt.ogg, hp_low_heartbeat_loop.ogg |
| **Combat** | sword_swing.ogg, pickaxe_swing.ogg, shovel_swing.ogg, dynamite_fuse.ogg, dynamite_explode.ogg, hit_mob.ogg, hit_player.ogg, death_player.ogg |
| **World** | bed_sleep_in.ogg, bed_wake_up.ogg, chest_open.ogg, chest_close.ogg, workbench_craft.ogg, rain_loop.ogg, lantern_light.ogg, lava_bubble_loop.ogg |
| **UI** | click_button.ogg, click_tab.ogg, toast_notify.ogg, error_negative.ogg, success_positive.ogg, ftue_step_complete.ogg (already a placeholder — replace) |
| **Mobs (per creature, 3 sounds each)** | <mob>_idle.ogg, <mob>_attack.ogg, <mob>_death.ogg — 15 creatures × 3 = 45 files but only 8 priority mobs (5 hostiles + 3 wildlife with sound) |

**Batch size:** 3 music tracks + ~35 SFX + ~24 mob SFX. ~1 week composer + ~3 days SFX work.

---

## Batch C — Builder + creature animation rigs (HIGH priority)

TripoSR outputs static meshes only. To make creatures actually animate
(walk cycle, attack, death) we need rigging + animations.

| Mesh | Animations needed | Notes |
|---|---|---|
| `assets/meshes/builder/builder_default.glb` | idle (breathing), walk, run, jump (rising + falling), place_brick, mine_block, sleep_in_bed | model-bible §3.4 spec |
| All 23 creature `.glb` (after TripoSR batch) | idle, move (walk/swim/fly), attack (where applicable), death | static today; rigging + skinning + 4-frame loops minimum |

**Workflow:** Re-export from Blender with armature + actions. ~1 day per
creature for a competent animator if mesh is already in Blender format.
Builder is the priority — 7 actions × ~half-day each = 4 days.

**Batch size:** 1 builder (7 actions) + 23 creatures (3-5 actions each) ≈ 2-3 weeks of animator time.

---

## Batch D — Particle effects (textures + animation curves)

Each particle is a small PNG sprite + a Godot ParticleProcessMaterial. None
shipped today — fall back to default Godot particles.

| Particle | Sprite path | Notes |
|---|---|---|
| Brick-break dust | `assets/textures/particles/brick_dust.png` (32×32) | Greyish puff |
| Wood chip | `assets/textures/particles/wood_chip.png` (16×16) | Small brown rectangle |
| Stone shard | `assets/textures/particles/stone_shard.png` (16×16) | Small grey triangle |
| Dynamite explosion | `assets/textures/particles/explosion.png` (128×128) | Orange/yellow puff |
| Water splash | `assets/textures/particles/water_drop.png` (16×16) | Blue droplet |
| Lava bubble | `assets/textures/particles/lava_bubble.png` (24×24) | Glowing orange dot |
| Lantern glow | `assets/textures/particles/glow_warm.png` (64×64) | Soft warm orb |
| Mob death puff | `assets/textures/particles/death_puff.png` (64×64) | Grey/white burst |
| Sleep Zzz | `assets/textures/particles/sleep_z.png` (32×32) | Letter Z, white |
| Rain drop | `assets/textures/particles/rain_streak.png` (8×64) | Vertical blue streak |
| Snow flake | `assets/textures/particles/snow_flake.png` (16×16) | White soft hex |
| Ghost wisp trail | `assets/textures/particles/wisp.png` (32×32) | Pale blue smoke |
| Fire flame | `assets/textures/particles/flame.png` (32×64) | Orange flicker, 4-frame |

**Batch size:** ~13 sprites, each 5 minutes of designer time. Half a day total.

---

## Batch E — World structure variants (MEDIUM priority)

Phase 2 ships 22 hand-authored template `.tres` files (villages, temples,
shipwrecks, dungeons, mineshafts). Real artist could create **render-ready
preview images** for each so the world-select / loading screens can show
mood vignettes.

Plus your earlier image-8 reference showed a much richer set than v1 spec:
castles, market stalls, lampposts, wells, fences, treasure chests, banners,
flags, gates. If you want to expand the in-world content vocabulary beyond
v1:

| Asset | Size / format | What |
|---|---|---|
| **Marketing structure preview images (22 files)** | 256×144 JPG each | Iconic shot per template — castle silhouette at dusk, jungle temple from above, etc. Used for "Did you know..." loading tips. |
| **(Stretch) Castle hero variants** | 3× `.glb` + textures | The brick castles in your image-8 reference — different sizes for "boss" structures |
| **(Stretch) Market stall** | 1× `.glb` | Free-standing village decoration |
| **(Stretch) Banner + flag pole** | 2× `.glb` | Hangable on walls / standalone |

**Batch size:** 22 preview JPGs (1 day designer work). Stretch items: ~3-5 days each.

---

## Batch F — Mobile control polish (MEDIUM priority)

Current mobile overlay uses Phase 1 placeholder PNGs (`place.png`,
`break.png`, `jump.png`, `move_stick.png`, `palette.png`). Functional but
clearly placeholder.

| File | Size | Notes |
|---|---|---|
| `assets/textures/icons/touch_dpad.png` | 192×192 | Round 4-way pad |
| `assets/textures/icons/touch_joystick_base.png` | 192×192 | Joystick ring |
| `assets/textures/icons/touch_joystick_knob.png` | 96×96 | Joystick draggable knob |
| `assets/textures/icons/touch_button_jump.png` | 128×128 | Up-arrow round button |
| `assets/textures/icons/touch_button_attack.png` | 128×128 | Sword icon round button |
| `assets/textures/icons/touch_button_place.png` | 128×128 | Plus icon round button |
| `assets/textures/icons/touch_button_break.png` | 128×128 | Pickaxe icon round button |
| `assets/textures/icons/touch_palette.png` | 96×96 | Replace existing `palette.png` |

**Batch size:** 8 icons, half a day designer time.

---

## Batch G — Sky / weather sprites (LOWER priority)

Currently uses `assets/shaders/sky_procedural.gdshader` (a runtime shader).
Some Tier-3 mobile devices may benefit from baked panoramas:

| File | Size | What |
|---|---|---|
| `assets/textures/sky/dawn_panorama.png` | 2048×1024 equirectangular | Warm pink sky with cloud strands |
| `assets/textures/sky/day_panorama.png` | 2048×1024 | Soft warm blue with scattered clouds |
| `assets/textures/sky/dusk_panorama.png` | 2048×1024 | Warm orange with low clouds |
| `assets/textures/sky/night_panorama.png` | 2048×1024 | Cool blue with stars + moon |
| `assets/textures/sky/cloud_1.png` … `cloud_4.png` | 128×64 each | Sprite cards for parallax clouds |
| `assets/textures/sky/moon.png` | 256×256 | Crescent and full variants |

**Batch size:** 4 panoramas + 4 clouds + 1 moon = ~9 files. ~2-3 days designer time.

---

## Batch H — Marketing capture set (CAN'T be generated — must be captured from gameplay)

6 screenshots per platform per locale (per `docs/store-readiness/screenshot-checklist.md`). Listed for completeness; this is **gameplay capture**, not art generation.

For each platform (iOS 6.7", iOS 5.5", iPad 12.9", Android Phone, Android Tablet):
1. Title screen
2. Fresh world spawn at dawn (builder + starter chest visible)
3. Brick palette open, building a small house
4. Friends panel, "Friend joined" toast
5. Chat overlay during 2-player session (both nameplates visible)
6. Dawn over finished player-built castle

**Batch size:** 30 captures across platforms × 2 locales = 60 PNG/JPG. ~1 day work once gameplay is polished.

---

## Total summary

| Batch | Files | Designer time | Player impact |
|---|---|---|---|
| A — Title hero | 3 | ~half day | 🔴 Highest |
| B — Music + SFX | 3 + ~60 | ~10 days | 🔴 Highest |
| C — Animation rigs | ~24 | ~2-3 weeks | 🔴 Highest |
| D — Particles | ~13 | ~half day | 🟡 High |
| E — Structure previews | 22 + stretch | ~1 day + stretch | 🟡 High |
| F — Mobile controls | 8 | ~half day | 🟡 Medium |
| G — Sky panoramas | 9 | ~3 days | 🟢 Low |
| H — Marketing captures | 60 | ~1 day | 🟡 High (store submission) |

---

## Suggested commission order

If you batch art with image-gen sessions matching the 23-creature workflow we just ran:

1. **Next session →** Batch A (title hero set, 3 files) — biggest single visual win
2. **Then →** Batch D (particle sprites, 13 files) — quick wins, completes the visual feedback loop
3. **Then →** Batch F (mobile controls, 8 files) — needed for mobile playtests
4. **Then →** Batch E preview images (22 files) — fills loading screens with personality
5. **Music + SFX** (Batch B) and **Animation rigs** (Batch C) — commission separately to specialists, not image-gen
6. **Sky panoramas** (Batch G) — only if mobile shader perf is an issue
7. **Marketing captures** (Batch H) — at end, once game is polished enough to screenshot

---

## Batch I — Inventory item icons: chest keys (v1.1 Phase 7 gap)

Surfaced by the Phase 7 asset-integration audit. Four `key_*.tres` item
definitions reference icon PNGs that were never drawn. Code guards them
(item renders with no icon; no crash), and they're referenced only in `.tres`
so they don't block the scene-stub audit — but they're real inventory polish gaps.

| File | Size | Format | What |
|---|---|---|---|
| `assets/textures/icons/key_bronze.png` | 256×256 | PNG, RGBA | Brick-built chest key, **bronze/warm-brown** tier colour |
| `assets/textures/icons/key_silver.png` | 256×256 | PNG, RGBA | Same key, **cool light-grey/silver** tier colour |
| `assets/textures/icons/key_gold.png` | 256×256 | PNG, RGBA | Same key, **bright gold/yellow** tier colour |
| `assets/textures/icons/key_diamond.png` | 256×256 | PNG, RGBA | Same key, **pale cyan/white** with a gem accent |

**Style:** chunky stud/brick-built *key* (player term "key"; never a trademarked brand), bold
silhouette legible at ~48px inventory-slot size, soft top-left key light to match
other icons. Tier colour is the only differentiator — keep them instantly
distinguishable at small size. Add a `<file>.png.license` (GPL-3.0-or-later)
sidecar per icon. No code change needed after delivery.

**Batch size:** 4 files (one key drawn once, recoloured ×4). Also sweep
`src/bricks/*.tres` `icon_path` for the broader missing item-icon set
(`food_*.png`, etc.) and batch them together.

> **Not artist work:** the 8 avatar preset thumbnails (`assets/textures/ui/avatar_presets/preset_1-8.png`)
> are a *capture* task, not a draw task — rendered from the live avatar SubViewport
> in a windowed Godot session. Steps: `.planning/phases/07-asset-integration/07-DEFERRED-HANDOFF.md` §2.

---

*Last updated 2026-06-01, added Batch I (chest-key icons) from v1.1 Phase 7.
Earlier: 2026-05-31, after 23-creature TripoSR batch landed. Maintain
alongside `art-direction-brief.md` going forward.*
