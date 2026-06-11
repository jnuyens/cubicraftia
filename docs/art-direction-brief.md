# Cubicraftia — Art Direction Brief (v1.0 → v1.1)

**Purpose:** Complete production specification for every visual and audio asset Cubicraftia v1 ships. Designed to be handed to an external illustrator, art director, or AI image-generation tool as a master prompt set.

**Audience:** Illustrators, 3D artists, sound designers, AI-prompt operators.

**Status:** v1.0 ships with 1×1 transparent PNG stubs for every asset listed here. Drop in real artwork at the named paths and the build will pick it up automatically — no code changes required.

**Version:** 1.0 — generated 2026-05-30 at milestone v1.0 close.

---

## 1. Brand foundation

### 1.1 Identity

**Game name:** Cubicraftia (always one word, capital C). Never "Cubic Craftia" or "Cubicraft".

**Tagline:** "Bricks. Worlds. Friends."

**Elevator pitch:** A 3D voxel sandbox where everything — terrain, players, builds — is made of interlocking studded bricks. Combines the procedurally infinite world of Minecraft-style sandboxes with the expressive vocabulary of real Lego bricks (slopes, tiles, plates, not just 1×1 cubes). Play solo or with 2–4 friends across Mac / PC / Linux / iOS / Android.

**Tonal anchors:** Friendly. Playful. Cosy. Kid-safe but not babyish. Indie hand-crafted feel, not corporate AAA polish. Think *Stardew Valley* warmth, not *Fortnite* hyper-energy.

### 1.2 Strict trademark rules (read first)

Cubicraftia is *not* affiliated with the LEGO Group or Mojang Studios. Every art asset must respect these legal boundaries:

| ❌ Never depict | ✅ Use instead |
|---|---|
| Lego *minifigure* silhouette (cylindrical head, claw hands, trapezoidal torso) | Cube-headed builder with rounded edges; flat hands; rectangular torso with chamfered corners |
| Lego *typography* | NotoSans SemiBold for all wordmarks |
| The word "Lego" anywhere in art (even as joke / wink) | "brick", "stud", "builder" |
| Minecraft-style *blocky pixel face* (Steve eyes, beard pixels) | Flat shaded face with expressive but non-pixel-grid features |
| Notch/cliff-face Minecraft terrain silhouette | Softer, more rounded terrain edges (still cube-based, but with bevels visible at LOD) |
| Lego brand colours exactly (signal red #DA291C, etc.) | Cubicraftia palette in §1.3 — distinct hex values |
| 4×4 stud square as standalone hero element | 2×4 or 2×2 brick (the most recognisable Cubicraftia silhouette) |

**Reviewer checklist before delivery:** Run every asset past these 7 rules. If a piece would survive a side-by-side comparison with Lego/Minecraft official art without confusion, ship it. If a casual viewer would say "oh, Lego" or "oh, Minecraft", revise.

### 1.3 Locked colour palette

All assets must work in this palette. Off-palette hex values are not permitted except where explicitly noted (skin tones, brick textures).

| Token | Hex | RGB | Role | Usage |
|---|---|---|---|---|
| `navy` | `#1B2C56` | 27, 44, 86 | Dominant 60% | UI backgrounds, panel fills, title bg base |
| `brick_white` | `#F1F0EA` | 241, 240, 234 | Secondary 30% | Text, icons, UI strokes, builder skin highlights |
| `accent_yellow` | `#F5C30D` | 245, 195, 13 | Accent 10% | CTAs, freeze ring, FTUE arrow, tab underline |
| `destructive_red` | `#D63828` | 214, 56, 40 | Semantic | Destructive buttons, errors, blood (mild — kid-safe) |
| `online_green` | `#3DB560` | 61, 181, 96 | Semantic | Online status dot, creative mode badge, success toasts |
| `relay_amber` | `#E8890C` | 232, 137, 12 | Semantic | TURN relay badge, survival mode badge, warnings |
| `offline_gray` | `#6B7280` | 107, 114, 128 | Semantic | Offline status, disabled states |

**60/30/10 rule:** Every composition should be roughly 60% navy, 30% brick-white, 10% accent yellow + semantics. Sample any frame; if accent yellow exceeds ~15%, reduce.

### 1.4 Typography

| Font | Use | Weight |
|---|---|---|
| `NotoSans-SemiBold.ttf` | Headings, button labels, wordmark | 600 |
| `NotoSans-Regular.ttf` | Body, captions, status text | 400 |

Type sizes locked at 12 / 14 / 16 / 20 / 28 px (UI). The Cubicraftia wordmark on the title screen is the only documented exception at **96 px**.

**Wordmark treatment** (when included in art): Use NotoSans SemiBold at the target px, brick-white on navy or navy on brick-white. Optionally add a single 2 px accent-yellow underline on the final stroke. Do not add drop shadows, outer glow, bevel, or any other effect — clean and graphic.

### 1.5 Visual style summary (one paragraph)

Soft-shaded low-poly 3D for in-world objects, with chamfered cube edges (no pure right angles) and matte materials (no specular highlights, no metalness). Studs on bricks are subtle — a 0.3 mm raised cylinder on top of each 1× unit, *not* the deep cylindrical stud of real Lego. UI iconography is flat-shaded with a single soft drop shadow allowed (4 px / 25% opacity / brick-white on navy backgrounds). Hand-illustrated promotional and FTUE art uses a friendly chunky cartoon style — think *Adventure Time* rounded silhouettes with *Stardew Valley* warmth, never *Pixar* slickness.

---

## 2. Production constraints

### 2.1 File specifications

| Asset type | Format | Colour space | Compression | Alpha |
|---|---|---|---|---|
| UI icon (≤64 px) | PNG-8 or PNG-24 | sRGB | Optimised (pngcrush) | Yes — 1 px transparent border around the visible shape |
| UI background tile | PNG-24 | sRGB | Optimised | Yes |
| Hero illustration | PNG-24 | sRGB | Optimised | Yes |
| World thumbnail | JPG | sRGB | Quality 85 | No |
| Avatar preset preview | PNG-24 | sRGB | Optimised | Yes — circular crop with anti-aliasing |
| 3D model (avatar parts) | glTF 2.0 (.glb binary) | linear | Draco compression OK | — |
| Audio | OGG Vorbis | 44.1 kHz stereo | Quality 5 | — |
| Vector source (master) | SVG | sRGB | — | Yes |

**Master files:** Always deliver both the PNG/JPG output *and* the editable source (.svg, .ai, .psd, .blend) into `assets/source/` (gitignored — sent separately). Source files are needed for future re-scaling and asset variations.

**Naming:** All-lowercase, underscores between words, descriptive. `icon_warning.png`, not `Warning.png` or `warning-icon.png`. Match the locked filenames in §3 exactly — code references them by literal path.

### 2.2 Mobile / multi-density considerations

iOS and Android need pixel-perfect rendering across DPI. For UI icons:

- Author each icon at **3× the listed size** in the source (e.g., 16 px icon → 48 px master)
- Export PNG at the listed size (no @2x / @3x suffixes — Godot scales)
- Use clean integer pixel anchors at 16 / 24 / 32 / 48 / 64 — no half-pixel offsets in source
- Test render at the smallest size; if a 16 px icon becomes unreadable, simplify the silhouette rather than adding detail

For hero illustrations and the title background, deliver at **1920×1080** target resolution. Godot scales down per platform; never up.

### 2.3 Accessibility

- **WCAG AA contrast** for any text-on-background combination. Brick-white on navy = 11.4:1 (pass). Accent yellow on navy = 8.7:1 (pass). Brick-white on accent yellow = 1.3:1 (fail — never combine).
- **Colour-blind safety:** Never encode information by colour alone. Online/relay/offline status pairs colour with an icon shape (green dot vs amber triangle vs gray X).
- **No flashing:** Photosensitive epilepsy safety — no animation faster than 3 Hz, no high-contrast strobes.

### 2.4 Localisation hooks

Cubicraftia ships with English and Dutch (v1.0); more languages later. Where art contains text:

- Title wordmark stays in English globally (proper noun)
- FTUE step bubbles in art are *outside the image* (rendered via `tr("ui.ftue.*")` overlay) — do not bake text into the FTUE arrow PNG
- World card mode badge text ("Creative" / "Survival") is overlaid by code — only the badge shape ships as art

---

## 3. Asset list

Every asset below ships in v1.0 as a 1×1 transparent stub. Drop a real file at the named path and the build picks it up. No code changes needed unless explicitly noted.

### 3.1 Title screen (Surface 1)

#### `assets/textures/icons/title_bg.png` — Title background tile

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/textures/icons/title_bg.png`
- **Size:** 512 × 512 (seamlessly tileable)
- **Format:** PNG-24, opaque, sRGB
- **Renders at:** Full-screen, UV-panned 0.002 units/sec via `assets/shaders/title_bg_pan.gdshader`. The shader has a navy fallback when the texture's alpha is below threshold — so the texture *must* be fully opaque for the brick pattern to show.
- **Visual brief:**
  - A seamless top-down or near-top-down view of an infinite Cubicraftia brick landscape
  - 60% navy tones (deep sky, distant hills); 30% brick-white (clouds, snow patches, sand); 10% accent yellow (a few hero brick highlights — perhaps wheat, lantern glow, gold ore)
  - Visible 2×2 and 2×4 brick silhouettes; no minifig figures
  - Pan-friendly: the eye should find new detail every 5 seconds at the locked pan speed
  - No text, no characters, no UI elements
- **Mood:** Promising vista, "this is the world you're about to explore". Cosy, not epic.
- **Reference style:** Think Stardew Valley splash painting × isometric brick world. Soft edges, warm light.
- **Acceptance:** Tiled 2×2, the seam is invisible. Pans smoothly without a visually obvious repeat. Reads as "brick world" from 2 feet away.

#### `assets/audio/title_loop.ogg` — Title music

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/audio/title_loop.ogg`
- **Format:** OGG Vorbis, 44.1 kHz, stereo, quality 5, **seamless 90-second loop**
- **Tone:** Warm, gentle, optimistic. Acoustic guitar / soft synth / glockenspiel palette. No vocals. No drums until the second loop entry. Inspired by *Stardew Valley* title theme + *Animal Crossing* main menu.
- **Tempo:** 80–95 BPM. Major key (C, D, or G).
- **Levels:** -16 LUFS integrated, -1 dBTP true peak. Headroom for SFX overlay.
- **Loop point:** First and last 100 ms must crossfade seamlessly. Test by playing the file on repeat for 5 minutes — no audible click or breath at the seam.
- **Acceptance:** Listenable for an entire title-screen idle without becoming irritating; recedes mentally when player isn't focused on it.

#### `assets/textures/icons/cubicraftia_wordmark.png` — Wordmark (optional asset, can also be rendered as Label)

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/textures/icons/cubicraftia_wordmark.png`
- **Size:** 1024 × 256 (4:1 aspect)
- **Visual brief:** The word "Cubicraftia" in NotoSans SemiBold at 96 px (or custom letterforms if commissioned), brick-white. Optional: substitute one letter — most often the "C" or the "i" — for a small graphic 2×2 brick. Single 2 px accent-yellow underline below the final stroke.
- **Mood:** Confident, friendly, indie. Not screaming. Not corporate.
- **Acceptance:** Reads cleanly at 256 px wide on a 6.7" phone. Recognisable as a wordmark, not a paragraph.

---

### 3.2 FTUE overlay (Surface 5)

#### `assets/textures/icons/ftue_arrow.png` — Bouncing tutorial arrow

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/textures/icons/ftue_arrow.png`
- **Size:** 128 × 128 (transparent PNG; visible shape ≤96 × 96 with 16 px padding all sides)
- **Visual brief:**
  - A chunky downward-pointing arrow with personality — slight cartoon bounce-pose tilt
  - Accent yellow fill, navy 2 px outline, soft drop shadow (4 px / 25% opacity)
  - Optional: small face/expression on the arrowhead (one eye + smile, kid-friendly)
  - Will be rendered with a 0.6 s vertical bounce tween in-game
- **Mood:** Helpful, cheerful, slightly impatient. "Look here! No, here!"
- **Acceptance:** Readable at 32 px on a small mobile screen. Not so detailed that the bounce animation reduces it to noise.

#### `assets/audio/ftue_step_complete.ogg` — FTUE step completion chime (optional but recommended)

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/audio/ftue_step_complete.ogg`
- **Format:** OGG Vorbis, 44.1 kHz, mono, quality 6, length 0.8 s
- **Tone:** Bright glockenspiel triad (C–E–G) ascending. Adds a half-second sparkle reverb tail. Warm, never harsh.
- **Levels:** Same loudness as the title music (-16 LUFS); plays *over* title music without ducking.

---

### 3.3 Avatar system (Surface 2)

The v1.0 avatar is rendered programmatically from primitive meshes (BoxMesh head/body/legs, color overrides per `avatar_config`). Phase 999.1 backlog defines an "avatar customisation as gameplay progression" system that needs real sculpted parts. For v1.0, only the *preview thumbnails* need art.

#### `assets/textures/avatars/preset_0.png` through `preset_7.png` — 8 avatar preset previews

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/textures/avatars/preset_<N>.png` (N = 0..7)
- **Size:** 128 × 128, transparent PNG with subtle circular crop
- **Production method (recommended):**
  - Run the Godot scene `avatar_creator.tscn` headless with each preset config
  - Capture the SubViewport at 256 × 256 anti-aliased, downsample to 128 × 128
  - Avoid sculpting from scratch — capture the actual in-game appearance so the player sees what they're getting
- **Preset visual briefs:**

| N | Name | Skin | Body color | Legs color | Hand accessory | Vibe |
|---|---|---|---|---|---|---|
| 0 | Classic | Index 0 (fair) | Blue | Black | None | "The default" — recognisably the v1 silhouette |
| 1 | Winter | Index 3 (medium-dark) | White | Navy | Lantern | Snow-explorer / first-night-survival |
| 2 | Explorer | Index 2 (medium) | Brown | Tan | Pickaxe | Mineshaft adventurer |
| 3 | Knight | Index 1 (medium-light) | Gray | Gray | Sword | Brick-built armor look |
| 4 | Rainbow | Index 0 | Pink | Yellow | None | Creative-mode joy |
| 5 | Pirate | Index 4 (deep) | Red | Black | Sword | Shipwreck-survivor |
| 6 | Ninja | Index 1 | Black | Black | None | Stealth black-on-black |
| 7 | Astronaut | Index 0 | White | White | Torch | Space-explorer (foreshadows future content) |

- **Mood per thumbnail:** A 3/4 portrait view (the same camera angle for all 8), neutral expression, slight smile. Background is fully transparent.
- **Acceptance:** Side-by-side, all 8 read as the same builder character with cosmetic variation — not 8 different characters.

#### *(Phase 999.1 work)* `assets/meshes/avatar/head_*.glb`, `body_*.glb`, `legs_*.glb`

Detailed brief for actual sculpted parts is captured in `.planning/phases/999.1-avatar-customisation-as-gameplay-progression/`. Defer until that phase planning starts.

---

### 3.4 World select screen (Surface 3)

#### `assets/textures/icons/world_thumb_placeholder.png` — Default thumbnail before save capture

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/textures/icons/world_thumb_placeholder.png`
- **Size:** 256 × 144 (16:9)
- **Format:** JPG (matches the captured-screenshot format from `WorldSave.capture_thumbnail`)
- **Visual brief:** A single Cubicraftia 2×4 brick centered on a navy background with a small "?" overlay in accent yellow. Optional: subtle dotted-line border suggesting "no screenshot yet".
- **Mood:** "World awaiting first visit." Not error, not empty — just expectant.
- **Acceptance:** Visually distinct from a real captured world thumbnail. A player at a glance can tell which worlds have been entered and which are fresh.

---

### 3.5 Network status + UI icons (Surfaces 4–10)

All icons render at the listed display size. Author at 3× source resolution per §2.2.

#### `assets/textures/icons/icon_friends.png` — Friends button

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/textures/icons/icon_friends.png`
- **Display size:** 32 × 32 (author 96 × 96)
- **Visual brief:** Two stylised cube-head builder silhouettes side by side, the second slightly behind and smaller. Brick-white fill, no outline. Friendly proximity, not a hand-holding cliché.
- **Acceptance:** Readable as "two people / friends" at 24 px on mobile.

#### `assets/textures/icons/icon_signal_1.png`, `icon_signal_2.png`, `icon_signal_3.png` — Network strength bars

- **Path:** `/Users/jnuyens/src/LegoMinecraft/assets/textures/icons/icon_signal_<N>.png`
- **Display size:** 16 × 16 (author 48 × 48)
- **Visual brief:** Three vertical bars increasing in height left→right. `signal_1.png` shows only the first bar lit (others 20% opacity); `signal_2.png` shows first two lit; `signal_3.png` shows all three. Lit bars use online green (`#3DB560`) at signal_3, accent yellow at signal_2, relay amber at signal_1. Brick-white at 20% for the unlit bars. No outline.
- **Acceptance:** Single-glance recognition of network quality. Distinct from a vertical "bars" icon you'd see on a phone status bar — these are flatter, chunkier.

#### `assets/textures/icons/icon_mute.png` — Muted status

- **Display size:** 16 × 16
- **Visual brief:** A speaker silhouette with a 45° diagonal line through it. Brick-white at 80%, line in destructive red.

#### `assets/textures/icons/icon_freeze.png` — Build freeze admin action

- **Display size:** 16 × 16 (badge) and 32 × 32 (admin panel)
- **Visual brief:** A six-pointed crystalline snowflake — but stylised, not photoreal. Accent yellow when active, brick-white at 60% when inactive.
- **Connotation:** "Build frozen by host." Not weather snow.

#### `assets/textures/icons/icon_spinner.png` — Loading spinner

- **Display size:** 32 × 32
- **Visual brief:** An indeterminate spinner. **4-frame sprite sheet** of the same circular spinner at 0°, 90°, 180°, 270° rotation (or use Godot's rotation tween on a single frame). Brick-white circular dashed-arc. UI-SPEC explicitly bans ProgressBar — this is the only loading affordance.
- **Acceptance:** Rotates smoothly at 2 Hz. Recognisable as "loading" without text.

#### `assets/textures/icons/icon_error.png` — Error state badge

- **Display size:** 16 × 16
- **Visual brief:** A small destructive-red circle with a brick-white exclamation mark. Solid, no outline.

#### `assets/textures/icons/icon_warning.png` — Warning badge (used inside amber backgrounds)

- **Display size:** 16 × 16
- **Visual brief:** A triangle with rounded corners, **navy fill** on transparent (because it sits on amber `StyleBox_warning_banner`). White exclamation mark in the centre.

#### `assets/textures/icons/icon_email.png` — Parental consent success

- **Display size:** 48 × 48 (larger — used in the consent success state)
- **Visual brief:** A clean envelope outline with a subtle check mark on the flap. Brick-white fill, navy outline at 2 px.

#### `assets/textures/icons/icon_check.png` — Generic check mark (tinted green at runtime)

- **Display size:** 16 × 16
- **Visual brief:** A bold check mark with rounded line caps. Brick-white at source; runtime tints to online green.

#### `assets/textures/icons/icon_plus.png` — Add friend / new world

- **Display size:** 24 × 24
- **Visual brief:** A plus sign with rounded line caps. Brick-white. Equal arms (not + cross — a proper plus).

#### `assets/textures/icons/icon_arrow_down.png` — Dropdown chevron

- **Display size:** 16 × 16
- **Visual brief:** A downward-pointing chevron (V shape), 2 px stroke, rounded line caps. Brick-white at 70% opacity (used as secondary affordance).

#### `assets/textures/icons/icon_dice.png` — Randomise button

- **Display size:** 24 × 24
- **Visual brief:** A 3/4 view of a single die showing the face "5" (dots arranged classically). Brick-white face, navy dots. Slight perspective so it reads as a die, not a flat square.

---

### 3.6 Existing assets (already shipped, do not regenerate)

These are real assets locked from Phase 1–3. Reference them for style continuity:

- `assets/meshes/brick_1x1.glb` — the canonical Cubicraftia brick geometry
- `assets/bricks/voxel_blocks/dirt.tres`, `stone.tres`, `grass.tres`, etc. — terrain block materials
- `assets/themes/cubicraftia.tres` — the locked theme (colors, fonts, styleboxes)
- `assets/fonts/NotoSans-Regular.ttf`, `NotoSans-SemiBold.ttf` — license: SIL OFL
- `assets/textures/icons/place.png`, `break.png`, `jump.png`, `move_stick.png`, `palette.png` — mobile control overlay (Phase 1)
- `assets/textures/icons/hotbar_slot_empty.png`, `brick_pack_locked.png` — Phase 3 inventory chrome
- `assets/textures/icons/preset_auto.png`, `preset_low.png`, `preset_medium.png`, `preset_high.png` — settings preset thumbnails
- `assets/shaders/sky_procedural.gdshader` — sky procedural (does not need a panorama texture; the sky panorama `.license` files in `assets/textures/sky/` are documentation-only)

---

### 3.7 Marketing / store screenshots (post-launch, not in code)

For App Store + Play Store submission, 6 screenshots per platform per locale. The locked shot list lives in `docs/store-readiness/screenshot-checklist.md`. Brief recap:

| # | Scene | Mood |
|---|---|---|
| 1 | Title screen | Inviting |
| 2 | Fresh world spawn — builder next to starter chest at dawn | Quiet possibility |
| 3 | Brick palette open, building a small house | Creative agency |
| 4 | Friends panel open, "Friend joined" toast | Social warmth |
| 5 | Chat overlay during 2-player session, both nameplates visible | Together |
| 6 | Dawn over a finished player-built castle | Accomplishment |

Capture via real gameplay session — these are not illustrations.

---

## 4. Production roadmap (suggested order)

Prioritise by player visibility / blockers:

| Priority | Assets | Why |
|---|---|---|
| **P0 — must-have for any showing** | `title_bg.png`, `cubicraftia_wordmark.png`, `title_loop.ogg`, `icon_spinner.png` | First impression. Without these the game looks unfinished from frame 1. |
| **P1 — visible in core loop** | All `icon_*.png` (16/24/32 px), `icon_friends.png`, `icon_signal_*.png`, `world_thumb_placeholder.png` | UI feels stub-y without these. |
| **P2 — onboarding polish** | `ftue_arrow.png`, `ftue_step_complete.ogg`, 8 avatar `preset_*.png` | FTUE works without them but feels lower-quality. |
| **P3 — store submission** | 6 marketing screenshots per platform per locale | Required for App Store / Play Store review. |
| **P4 — v1.x** | Sculpted avatar parts for Phase 999.1 | Not blocking v1.0; planned alongside avatar-progression system. |

Total assets in P0–P2: **~25 PNGs + 2 OGG files + 1 optional sculpted wordmark**.

---

## 5. Delivery checklist

For every asset:

- [ ] File saved at the exact path listed in §3 (lowercase, underscored, correct extension)
- [ ] Master source (`.svg`, `.psd`, `.ai`, `.blend`, project file) delivered separately to `assets/source/` (gitignored)
- [ ] Trademark checklist §1.2 passes (no Lego / Minecraft / minifig silhouette / pixel-art face)
- [ ] Palette compliance §1.3 — sample any frame, off-palette pixels only where explicitly allowed (skin tones, world detail)
- [ ] WCAG AA contrast for any text-on-art combination
- [ ] No flashing > 3 Hz
- [ ] Tested at smallest target size for legibility
- [ ] License documented in `assets/source/PROVENANCE.md` (e.g., commissioned work, attribution required, public domain, etc.)
- [ ] License file `assets/textures/icons/<name>.png.license` written using SPDX format (e.g., `SPDX-FileCopyrightText: 2026 <author>` / `SPDX-License-Identifier: <SPDX-id>`) — matches existing `.license` siblings in the repo
- [ ] Sibling `.gd` and `.tscn` files still load — verified by `godot --headless --quit-after 5`

---

## 6. AI image-tool prompt templates

If using an AI image generator (Midjourney, DALL-E, Stable Diffusion, etc.) as a starting point, the following master prompts encode the brand foundation. Feed them in alongside per-asset specs from §3.

### 6.1 Master prefix (prepend to every prompt)

```
Cubicraftia game art. Brand style: cosy indie hand-illustrated, friendly cartoon, soft chunky silhouettes, matte materials, no specular highlights, no metalness. Palette: navy #1B2C56 (60%), brick-white #F1F0EA (30%), accent yellow #F5C30D (10%), with semantic destructive-red #D63828, online-green #3DB560, relay-amber #E8890C used sparingly. Not Lego. Not Minecraft. No minifigures. No pixel-grid faces. Builder silhouette: rounded cube head, no claw hands. 2×4 brick is the iconic shape. Soft drop shadows allowed (4 px / 25%). WCAG AA contrast. Reference mood: Stardew Valley warmth × low-poly voxel × Adventure Time rounded silhouette.
```

### 6.2 Negative prompt (paste into negative field if your tool supports it)

```
lego, minecraft, minifig, minifigure, pixel art, pixelated face, blocky steve, notch terrain, claw hands, specular shine, metallic, glossy, photorealistic, hyperrealistic, AAA game, fortnite, dark gritty, blood, gore, scary, horror, sexual content, copyright trademark watermark signature text
```

### 6.3 Per-asset prompts (examples)

**title_bg.png:**
```
[MASTER PREFIX]. Top-down isometric vista of an infinite brick-built sandbox world at golden hour. Seamlessly tileable 512x512 texture. Rolling brick terrain with small forests of stylised trees, a thatched-roof brick village in the distance, scattered 2x2 yellow accent bricks (wheat, lanterns, gold ore). Soft warm light. No characters. No text. No UI. Painterly soft-edge style.
```

**ftue_arrow.png:**
```
[MASTER PREFIX]. A chunky cartoon downward-pointing arrow with personality, slight tilt. Bright accent yellow fill, 2px navy outline, soft drop shadow. Optional friendly face on the arrowhead with one cheerful eye and a small smile. Transparent background. Centered 96x96 visible shape on 128x128 canvas with 16px padding. Designed to be bouncing vertically when animated.
```

**preset_0.png (avatar):**
```
[MASTER PREFIX]. Three-quarter portrait of a Cubicraftia builder character. Cube-shaped head with rounded edges, fair skin tone, neutral friendly expression with subtle smile. Blue chunky torso, black legs. Transparent background. Soft circular vignette. 128x128. Same camera angle as a passport photo. No Lego minifig silhouette.
```

(Repeat pattern for presets 1–7 with the swatches in §3.3.)

---

## 7. Source assets reference

For style continuity, examine these existing locked assets when authoring new work:

| File | What to learn |
|---|---|
| `assets/bricks/voxel_blocks/dirt.tres` | Matte material treatment for terrain |
| `assets/themes/cubicraftia.tres` | All StyleBox colors, corner radii, padding constants |
| `src/ui/title_scene.tscn` | Layout / composition the title art must work within |
| `src/shaders/title_bg_pan.gdshader` | The shader the title background tiles through — has a navy fallback when alpha = 0 |
| `locale/en.po` | UI copy tone (informal "you", warm but never twee) |
| `docs/store-readiness/app-store-metadata.md` | The marketing voice the art must support |

---

## 8. Sign-off

When this brief is satisfied:

1. Drop assets at listed paths
2. Run `godot --headless --quit-after 5 src/world/title_scene.tscn` — boots clean
3. Launch in editor and step through title → sign-in → world select → FTUE — visually inspect against this brief
4. Mark the corresponding row complete in `.planning/STATE.md § Deferred Items`
5. Update `.planning/v1.0-MILESTONE-AUDIT.md § Art / audio` from open to resolved

After v1.0 art ships, this brief lives on as the style anchor for v1.1+ work (sculpted avatar parts, expansion content, marketing collateral).

---

*Brief authored 2026-05-30 at v1.0 milestone close. Maintained by the Cubicraftia art lead going forward.*
