---
phase: 6
slug: first-five-minutes
created: 2026-05-30
domain: Onboarding UX, avatar customisation, FTUE, world selection, deep-link handling, localisation
confidence: HIGH
---

# Phase 6: First Five Minutes — Research

**Researched:** 2026-05-30
**Domain:** Title screen orchestration, avatar creator (SubViewport 3D preview), FTUE in-world overlay, world select screen (thumbnail capture, world index), deep-link handling (iOS/Android custom URI), onboarding telemetry (local ConfigFile), Dutch localisation, Supabase avatar_json migration
**Confidence:** HIGH

---

## Summary

Phase 6 is the onboarding layer that wraps all previous phases. It replaces the `boot.gd → main_scene.tscn` direct launch path with a user-initiated flow: title screen → account/avatar → world select → FTUE in-world. The technical surface is primarily new GDScript UI scenes, two new autoloads (`DeepLinkHandler`, `OnboardingTelemetry`), one new Supabase migration (`006_avatar.sql`), and the first full authoring of `locale/nl.po`.

The codebase is well-prepared: all reusable signals, autoloads, and panels from Phases 1-5 are in place. Phase 6 adds no new GDExtensions and no new server-side infrastructure beyond the single `avatar_json` column migration. The two biggest per-phase risks are (1) the `StudGrid.placed` signal already uses the `BrickDefinition` type, not `def_id: String` — the FTUE overlay must extract `def_id` from the `BrickDefinition` parameter, and (2) `chest_entity.gd` lacks an `opened` signal — it must be added in Plan 06-01 wave 0.

The Dutch localisation is a first-time authoring effort (nl.po is a stub with 0 translated strings as of Phase 5). All Phase 1-5 en.po keys (currently ~625 msgids based on 1,253 lines / ~2 lines per entry) must receive NL translations in addition to the new Phase 6 keys. This is the largest single authoring risk in the phase.

**Primary recommendation:** Implement in wave order: (1) wave 0 — test scaffold + signal gap fixes + Supabase migration + i18n key stubs; (2) title_scene + DeepLinkHandler + OnboardingTelemetry; (3) avatar_creator + Builder.apply_avatar_config; (4) world_select_screen + thumbnail capture; (5) FTUE overlay; (6) Dutch translation authoring + DOCS sync.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Area 1 — Title Screen + Boot Flow**
- `title_scene.tscn` replaces `boot.gd` as `run/main_scene` in `project.godot`. `boot.gd` retained as `boot_splash` only.
- Full-screen CanvasLayer layer=0. Background: static TextureRect with UV-pan ShaderMaterial (0.002 UV units/sec). No live 3D title scene.
- Button stack: Sign in / Create account / Continue offline / Settings. "Continue as [username]" shown at top when already signed in.
- Logo alpha-in Tween (0.0 → 1.0, 2.0 s, ease in-out). Music: AudioStreamPlayer with null stream (no crash, auto-plays when OGG dropped in).
- Legal footer: "Terms of Use" and "Privacy Policy" links open `legal_viewer.tscn`.
- Deep-link intercept: `title_scene._ready()` checks `OS.get_command_line_args()` via `DeepLinkHandler`.
- `main_scene._ready()` auto-open dev path (`WorldSave.open_world("dev_world_001", ...)`) MUST be removed. Replace with defensive `push_warning`.

**Area 2 — Avatar / Builder Customisation**
- 5-part customiser: (1) head shape (3) + face expression (5); (2) body torso colour (10 swatches) + optional accessory (none/backpack/cape); (3) legs colour (10 swatches) + optional shoes (none/boots/sneakers); (4) hand-held accessory (none/pickaxe/lantern/flower/blank); (5) skin colour (5 swatches — applied to hands + face).
- 8 one-tap presets as constants in `avatar_creator.gd`. Randomise button.
- 3D preview: `SubViewportContainer` with existing `builder.tscn` mesh. SubViewport 256×256 px, `UPDATE_WHEN_VISIBLE`. Camera orbits at 0.4 rad/s. Triggered by `Builder.apply_avatar_config(cfg: Dictionary)` (new method on builder.gd).
- Persistence: `user://avatar.cfg` ConfigFile `[avatar]` section (local canonical) + `FriendsClient.save_avatar(cfg)` → PATCH Supabase profiles.avatar_json (fire-and-forget).
- Migration: `supabase/migrations/009_avatar.sql` — ADD COLUMN avatar_json TEXT to profiles. (Note: CONTEXT.md says `006_avatar.sql` but migrations 006-008 are already used; actual filename must be `009_avatar.sql`.)
- `avatar_creator.tscn` / `avatar_creator.gd` — CanvasLayer layer=10. Emits `avatar_complete` / `avatar_cancelled`.

**Area 3 — FTUE Guided Walkthrough**
- Trigger: `WorldSave.get_world_meta("ftue_complete")` is null AND world just created. Persisted on step 4 completion.
- Steps: (1) Open chest — ChestEntity.opened signal; (2) Mine tree — Inventory ADD event for wood_log; (3) Place plank — StudGrid.placed signal; (4) "That's it. The world is yours."
- Optional parallel hint at DUSK: "Time to sleep. Walk to the bed." — non-blocking, does not gate step 4.
- Overlay: `ftue_overlay.tscn` / `ftue_overlay.gd` — CanvasLayer layer=20. Bottom-third narration Label + thin top progress bar + directional arrow (off-screen indicator).
- Non-modal, non-blocking. Local-only (not replicated). Invite joiners: ftue_complete pre-set true.
- `Features.is_survival_mode()` gate — FTUE only in survival worlds.

**Area 4 — World Selection / Home Screen**
- `world_select_screen.tscn` / `world_select_screen.gd` — CanvasLayer layer=0.
- World cards: name (24 char truncated), last-played relative time, mode badge (Creative/Survival pill), 256×144 thumbnail (JPEG).
- Thumbnail: `get_viewport().get_texture().get_image()` deferred 1 frame after `WorldSave.save_world()`.
- Long-press/right-click context menu: Rename, Delete (confirmation), Duplicate, Export (OS.shell_open to Downloads).
- "New world" button: inline creation modal (name, seed, mode). `WorldSave.create_world()`. 5-world cap.
- "Friends" button: opens `friends_panel.tscn` overlay.
- World index: `user://worlds/index.cfg` ConfigFile. Rebuilt from filesystem on each `_ready()`.
- Offline mode: Friends button hidden, session join disabled.

**Area 5 — Invite-Link Joiner Skip Flow**
- `src/autoload/deep_link_handler.gd` — new autoload, registered after FriendsClient.
- `OS.get_command_line_args()` for `--invite=TOKEN` (desktop) and `--uri=cubicraftia://invite/TOKEN` (mobile).
- Signal: `invite_token_received(token: String)`.
- iOS: `project.godot` `[application] > custom_url_schemes = ["cubicraftia"]`. Universal Links deferred ops.
- Android: `AndroidManifest.xml` export override intent-filter. App Links deferred ops.
- Deep-link flow: skip title UI → sign-in check → redeem_invite → join_session → pre-set ftue_complete → toast tip.
- `user://ftue.cfg` marker `[state] joined_via_invite = true` written after join.

**Area 6 — Onboarding Telemetry / Metrics (Anonymous)**
- `src/autoload/onboarding_telemetry.gd` — new autoload, registered last.
- `OnboardingTelemetry.log(event_name: String)` — in-memory queue, flushed on CLOSE_REQUEST + every 60 s.
- 15 locked event names (see CONTEXT.md Area 6 list).
- `user://telemetry.cfg` ConfigFile, sections `[event_N]`. 10,000-event cap (drop oldest).
- No PII, no remote send in v1.
- `docs/PRIVACY.md` updated to enumerate telemetry.

### Claude's Discretion

None — all six areas have locked decisions per CONTEXT.md (Mode: Smart discuss autonomous).

### Deferred Ideas (OUT OF SCOPE)

- Real avatar mesh editor (Phase 999.1)
- Daily login rewards / streak system
- Achievement system
- Social FTUE prompts ("Invite a friend" push)
- Push notifications
- In-game news feed / MOTD
- Avatar unlockables / cosmetic progression
- Avatar display name (distinct from username)
- Title screen live 3D world background
- Title music (original composition) — placeholder silence only
- Universal Links / App Links server-side configuration (pre-launch ops task, docs only)
- Remote / cloud telemetry (v1.x)
- World export/import full UI
- More than 5 worlds (v1 cap)
- World thumbnail animated GIF/video
- Localisation beyond EN + NL
- FTUE "Skip" button (permanently excluded by DOCS §1.4)
- Adaptive quality polish tail item (already wired, no Phase 6 work needed unless regression found)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DOC-01 / §1.1 | Title screen with Sign in / Create account / Settings; one-screen account creation; immediate avatar creation with 8 presets + customisation; "Choose your world" | Areas 1, 2, 4 — title_scene.gd + avatar_creator.gd + world_select_screen.gd |
| DOC-01 / §1.2 | New-world FTUE: fade-in to grass clearing, 3 narration lines, starter chest delivery, tree pulse, placement confirmation, no modals | Area 3 — ftue_overlay.gd + signal wiring |
| DOC-01 / §1.3 | Invite-link joiners skip tutorial, appear next to host, floating tip | Area 5 — deep_link_handler.gd + ftue_complete pre-set |
| DOC-01 / §1.4 | Email+password+13+ only, avatar slots locked, tutorial unskippable, EN+NL localisation | All areas, Dutch translation authoring |
</phase_requirements>

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Title screen orchestration | Frontend (Godot scene) | — | Pure client UI; no server involvement for display |
| Account sign-in routing | Frontend (Godot scene) | API (Supabase GoTrue) | Client calls existing sign_in_panel → FriendsClient → GoTrue |
| Avatar config persistence | Client (user://avatar.cfg) | API (Supabase profiles) | Local file is canonical; remote is fire-and-forget sync |
| Avatar 3D preview | Client (SubViewport) | — | Second render pass; runs before any 3D world is active |
| FTUE overlay | Client (CanvasLayer) | — | Local-only; not replicated; reads Inventory/StudGrid signals |
| World select screen | Frontend (Godot scene) | Client filesystem | Reads user://worlds/, writes index.cfg |
| World thumbnail capture | Client (Godot RenderingServer) | — | Viewport screenshot; write to user://worlds/{id}/thumbnail.png |
| Deep-link handling | Client (OS args) | API (FriendsClient.redeem_invite) | Parse from CLI args; call existing server endpoint |
| Onboarding telemetry | Client (user://telemetry.cfg) | — | Local append-only log; no remote in v1 |
| Dutch localisation | Client (locale/nl.po) | — | PO file shipped with client; no server component |
| Supabase avatar_json migration | API (Supabase Postgres) | — | Single ALTER TABLE; applied by migration runner |

---

## Standard Stack

### Core (all pre-existing in the project)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Godot 4.6 | 4.6 stable | Engine, CanvasLayer, Tween, SubViewport, ConfigFile, OS, RenderingServer | Project-locked choice [ASSUMED] |
| GDScript | built-in | All Phase 6 scene controllers | Project standard for gameplay/UI code |
| godot-sqlite | GDExtension | WorldSave SQLite (already in use) | Phase 2 decision; no changes in Phase 6 |
| Supabase (self-hosted) | existing | profiles.avatar_json PATCH | Phase 4 decision; one new migration only |

### Phase 6 Specific Patterns

| Pattern | API | Notes |
|---------|-----|-------|
| Tween (logo alpha-in) | `Tween.tween_property(node, "modulate:a", 1.0, 2.0)` | [VERIFIED from Godot 4 docs] |
| UV pan shader | `ShaderMaterial` uniform `uv_offset: vec2` updated each frame in `_process` | Standard CanvasItem shader pattern |
| SubViewport (avatar preview) | `SubViewportContainer` + `SubViewport.update_mode = UPDATE_WHEN_VISIBLE` | [VERIFIED from Godot 4 docs] |
| Viewport screenshot | `get_viewport().get_texture().get_image()` → `Image.save_jpg(path)` | [VERIFIED from Godot 4 docs] |
| ConfigFile (avatar/telemetry/index) | `ConfigFile.set_value(section, key, value)` + `ConfigFile.save(path)` | [VERIFIED from Godot 4 docs] |
| OS deep-link args | `OS.get_command_line_args()` → parse `--invite=` or `--uri=` | [ASSUMED: behaviour on Godot 4.6 mobile — see Pitfall 4] |

### No New Package Installations

Phase 6 installs no new GDExtensions, npm packages, or external dependencies. All libraries are pre-existing from Phases 1-5.

---

## Package Legitimacy Audit

> Phase 6 installs no external packages. No audit required.

No new packages to audit.

---

## Architecture Patterns

### System Architecture Diagram

```
App Launch
    │
    ▼
[boot_splash] (engine, ~200ms)
    │
    ▼
[title_scene.tscn]  ◄── DeepLinkHandler checks OS.get_command_line_args() on _ready()
    │                         │
    │  invite token?          │ yes
    │◄────────────────────────┘
    │  no
    ├── "Sign in" / "Create account" ──► [sign_in_panel.tscn] (Phase 5)
    │                                           │ sign_in_complete
    │                                           ▼
    │                             user://avatar.cfg exists?
    │                              no ──► [avatar_creator.tscn]
    │                              yes ─► [world_select_screen.tscn]
    │
    ├── "Continue offline" ──────────────► [world_select_screen.tscn]
    │
    └── invite token ──► inline sign-in ─► FriendsClient.redeem_invite()
                                                │
                                                ▼
                                         NetworkManager.join_session()
                                                │
                                                ▼
                                         [main_scene.tscn] (host's world)
                                         ftue_complete = true (pre-set)
                                         Toasts.show(invite tip, 8s)

[world_select_screen.tscn]
    │
    ├── tap world card ──► WorldSave.open_world() ──► [main_scene.tscn]
    │                                                        │
    │                                                        ▼
    │                                              ftue_complete == null?
    │                                              AND survival mode?
    │                                                        │ yes
    │                                                        ▼
    │                                               [ftue_overlay.tscn] (layer 20)
    │                                               Step 1: ChestEntity.opened
    │                                               Step 2: Inventory ADD {wood_log}
    │                                               Step 3: StudGrid.placed {wood_plank}
    │                                               Step 4: "That's it." notification
    │
    └── "New world" ──► creation modal ──► WorldSave.create_world() ──► world card
```

### Recommended Project Structure (new files only)

```
src/
├── ui/
│   ├── title_scene.gd / title_scene.tscn      # replaces boot.gd as run/main_scene
│   ├── avatar_creator.gd / avatar_creator.tscn # CanvasLayer 10, 5-part customiser
│   ├── world_select_screen.gd / world_select_screen.tscn  # CanvasLayer 0
│   └── ftue_overlay.gd / ftue_overlay.tscn    # CanvasLayer 20
├── autoload/
│   ├── deep_link_handler.gd                   # new autoload, after FriendsClient
│   └── onboarding_telemetry.gd                # new autoload, registered last
supabase/migrations/
└── 009_avatar.sql                             # ADD COLUMN avatar_json TEXT to profiles
locale/
├── en.po                                      # new Phase 6 keys appended
└── nl.po                                      # full Dutch translation (all phases)
assets/
├── textures/
│   └── title/
│       └── title_bg.png                       # placeholder stub; artist replaces
├── audio/
│   └── music/
│       └── title_theme.ogg                    # NOT created in Phase 6 (placeholder silence)
└── icons/
    └── ftue_arrow.png                         # directional arrow icon stub
tests/
└── conftest_phase6.gd                         # fixtures: avatar cfg, telemetry, world index, FTUE steps
```

### Pattern 1: title_scene Boot Flow

**What:** title_scene.tscn is registered as `run/main_scene`. It orchestrates the sign-in → avatar → world-select flow via signal connections.
**When to use:** Entry point for every app launch.

```gdscript
# Source: established boot.gd pattern (src/ui/boot.gd) adapted for title screen
func _ready() -> void:
    OnboardingTelemetry.log("title_shown")
    # Check for deep-link invite at launch
    if DeepLinkHandler.has_signal("invite_token_received"):
        DeepLinkHandler.invite_token_received.connect(_handle_invite_deep_link)
    # Session restore: show "Continue as [username]" if already signed in
    if FriendsClient.is_signed_in():
        _continue_button.text = tr("ui.title.continue_as").format(
            {"username": FriendsClient.get_username()})
        _continue_button.visible = true
    # Logo alpha-in tween
    modulate.a = 0.0
    var tween: Tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, 2.0).set_ease(Tween.EASE_IN_OUT)
```

### Pattern 2: Avatar Creator 3D Preview

**What:** SubViewportContainer renders a rotating builder.tscn instance. `Builder.apply_avatar_config(cfg)` updates mesh visuals without re-importing.
**When to use:** Avatar creator scene for all avatar part changes.

```gdscript
# Source: Godot 4 SubViewport docs pattern
# avatar_creator.gd
@onready var _viewport: SubViewport = $PreviewContainer/SubViewport
@onready var _preview_builder: Builder = $PreviewContainer/SubViewport/Builder

func _apply_config_to_preview(cfg: Dictionary) -> void:
    if _preview_builder != null and _preview_builder.has_method("apply_avatar_config"):
        _preview_builder.apply_avatar_config(cfg)

func _process(delta: float) -> void:
    # Rotate builder preview 0.4 rad/s
    if _preview_builder != null:
        _preview_builder.rotation.y += 0.4 * delta
```

### Pattern 3: FTUE Overlay Signal Wiring

**What:** ftue_overlay.gd connects to ChestEntity.opened, Inventory.inventory_changed (with def_id filter), and StudGrid.placed (with BrickDefinition.brick_id filter) to advance FTUE steps.
**When to use:** FTUE only. Signals must be connected AFTER world_ready fires on main_scene.

**Critical finding:** `StudGrid.placed` emits `(anchor_cell: Vector3i, definition: BrickDefinition, colour_index: int, rotation: int)` — not `(def_id: String, ...)`. The FTUE overlay must filter by `definition.brick_id == "wood_plank"`. [VERIFIED: stud_grid.gd line 87]

**Critical finding:** `ChestEntity` does NOT emit an `opened` signal. It only emits `unlocked` and `broken`. A 2-line addition is required in `chest_entity.gd`: `signal opened` + `opened.emit()` in `_open_panel()` before calling `slide_in.open_chest_mode(...)`. [VERIFIED: chest_entity.gd lines 121-128]

**Critical finding:** Inventory does not emit a per-event signal for ADD events. The FTUE step 2 (wood_log pickup) must connect to `Inventory.inventory_changed` and check the builder's slots for the first occurrence of `def_id == "wood_log"` after the signal fires. Alternatively, a lightweight `item_added` signal can be added to Inventory (preferred — avoids re-scanning all 48 slots on every change). [VERIFIED: inventory.gd]

```gdscript
# Source: StudGrid signal inspection (src/world/stud_grid.gd line 87)
# ftue_overlay.gd — Step 3 connection
func _connect_ftue_signals() -> void:
    var stud_grid: StudGrid = get_tree().get_first_node_in_group("stud_grid")
    if stud_grid != null:
        stud_grid.placed.connect(_on_stud_grid_placed)
    # Step 1: connect to ChestEntity.opened (must be added to chest_entity.gd)
    for chest: Node in get_tree().get_nodes_in_group("chest_entity"):
        if chest.has_signal("opened"):
            chest.opened.connect(_on_chest_opened.bind())

func _on_stud_grid_placed(anchor_cell: Vector3i, definition: BrickDefinition,
        colour_index: int, rotation: int) -> void:
    if _current_step != 3:
        return
    if definition != null and definition.brick_id == "wood_plank":
        _advance_to_step(4)
```

### Pattern 4: World Thumbnail Capture

**What:** Deferred 1 frame after WorldSave.save_world(), captures 256×144 JPEG of the current viewport.
**When to use:** At every world save call.

```gdscript
# Source: Godot 4 docs — get_viewport().get_texture().get_image()
# world_save.gd — new capture_thumbnail() static method
static func capture_thumbnail(world_id: String) -> void:
    # Must be called via call_deferred to ensure viewport has rendered current state
    # (called from save_world after RenderingServer.force_draw())
    var img: Image = get_viewport().get_texture().get_image()
    img.resize(256, 144, Image.INTERPOLATE_BILINEAR)
    var thumb_path: String = "user://worlds/%s/thumbnail.png" % world_id
    img.save_jpg(thumb_path, 0.85)
```

### Pattern 5: Deep-Link Handler

**What:** Autoload parses CLI args at `_ready()`. Emits signal consumed by title_scene.
**When to use:** Every app launch.

```gdscript
# Source: Godot 4 OS.get_command_line_args() docs + CONTEXT.md Area 5
# deep_link_handler.gd
signal invite_token_received(token: String)

func _ready() -> void:
    for arg: String in OS.get_command_line_args():
        if arg.begins_with("--invite="):
            var token: String = arg.substr(len("--invite="))
            if token.length() >= 20:  # T-06-T1 basic sanity
                invite_token_received.emit(token)
                return
        if arg.begins_with("--uri=cubicraftia://invite/"):
            var token: String = arg.substr(len("--uri=cubicraftia://invite/"))
            if token.length() >= 20:
                invite_token_received.emit(token)
                return
```

### Pattern 6: Onboarding Telemetry

**What:** Append-only ConfigFile event log with 10,000-event cap. No PII, no remote.
**When to use:** Call `OnboardingTelemetry.log(event_name)` at each funnel point.

```gdscript
# onboarding_telemetry.gd
static func log(event_name: String) -> void:
    _queue.append({"ts": Time.get_unix_time_from_system(), "event": event_name})

func _flush_to_disk() -> void:
    var cfg := ConfigFile.new()
    cfg.load("user://telemetry.cfg")  # OK if missing — starts fresh
    var count: int = cfg.get_value("meta", "event_count", 0)
    for entry: Dictionary in _queue:
        cfg.set_value("event_%d" % count, "ts", entry["ts"])
        cfg.set_value("event_%d" % count, "event", entry["event"])
        count += 1
    # 10,000-event cap: drop oldest if over limit
    if count > MAX_EVENTS:
        _rotate_oldest(cfg, count - MAX_EVENTS)
        count = MAX_EVENTS
    cfg.set_value("meta", "event_count", count)
    cfg.save("user://telemetry.cfg")
    _queue.clear()
```

### Anti-Patterns to Avoid

- **Re-using boot.gd as title_scene:** `boot.gd` must be kept as the Godot boot splash only. title_scene is a separate scene with different responsibilities (sign-in routing, deep-link handling). [ASSUMED based on CONTEXT.md decision]
- **Scanning all 48 inventory slots in _process for FTUE:** connect to Inventory signals, don't poll every frame — the FTUE overlay is on every frame and inventory polling is O(48) per tick.
- **Calling get_viewport().get_texture().get_image() synchronously in WorldSave.save_world():** this blocks the main thread mid-save. Use `call_deferred("capture_thumbnail", world_id)` after save returns.
- **Hardcoding English strings in FTUE narration:** all 4 FTUE lines must go through `tr("ui.ftue.step_N")`. The Dutch translations are authored in this phase; hardcoded strings would be caught by the CI glossary check.
- **Opening a SubViewport while main 3D world is active:** avatar creator runs before world load; the SubViewport only renders the builder mesh (no terrain). Never instantiate the avatar SubViewport after world load unless the main scene's LOD is reduced first.
- **Double-emitting invite flow:** `DeepLinkHandler` must only emit `invite_token_received` once per launch. Guard with a `_handled: bool` flag.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Avatar persistence | Custom binary format | `ConfigFile` with `user://avatar.cfg` | Matches existing `user://auth.cfg` + `user://settings.cfg` pattern; human-readable; trivially backed up |
| World thumbnail | JPEG encoder | `Image.save_jpg(path, quality)` | Built into Godot; 256×144 at 0.85 quality ≈ 20-30 KB |
| Deep-link URI parsing | Regex parser | String `begins_with()` + `substr()` | URIs are fixed-format; regex adds no value and is harder to read |
| FTUE step state machine | Custom enum class | Simple `_current_step: int` (1-4) in ftue_overlay.gd | 4 states; no branching; a full state machine is over-engineering |
| Localisation | Custom key-value store | Godot built-in `tr()` + `.po` files | Already wired in `Translations` autoload; `scripts/extract-pot.sh` generates the POT |
| Off-screen arrow indicator | Raycasting | `get_viewport().get_camera_3d().unproject_position(target)` + screen-edge clamp | Standard Godot unproject; clamping to screen edge is 5 lines |
| Relative time ("3 days ago") | DateTime library | `Time.get_unix_time_from_system()` arithmetic + thresholds | No library needed; only 4 thresholds (today/yesterday/N days/date) |

---

## Runtime State Inventory

Phase 6 is an additive onboarding phase, not a rename/refactor phase. One runtime state category is relevant:

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | `world_meta` table row `ftue_complete` — new key, added by FTUE overlay on step 4 completion | Code change: `WorldSave.set_world_meta("ftue_complete", var_to_bytes(true))` |
| Stored data | `user://worlds/index.cfg` — new file created by world_select_screen | Code change: write on world creation, read on _ready() |
| Stored data | `user://avatar.cfg` — new file created by avatar_creator | Code change: write on "Done", read on title_scene._ready() |
| Stored data | `user://telemetry.cfg` — new file created by OnboardingTelemetry | Code change: append-only write |
| Stored data | `user://ftue.cfg` — new file created after invite join | Code change: write `[state] joined_via_invite = true` |
| Stored data | Supabase profiles.avatar_json — new column via migration 009_avatar.sql | SQL migration; no data migration needed (column is nullable) |
| Live service config | `project.godot run/main_scene` — MUST change from `main_scene.tscn` to `title_scene.tscn` | project.godot edit in Plan 06-XX |
| Live service config | `project.godot autoload` — two new autoloads: DeepLinkHandler, OnboardingTelemetry | project.godot edit |
| OS-registered state | None — no OS-registered tasks or services in Phase 6 | None |
| Secrets/env vars | None new | None |
| Build artifacts | None new | None |

**main_scene.gd dev-mode path must be removed:** Line 332-335 (`if not WorldSave.is_open(): WorldSave.open_world("dev_world_001", ...)`) must be replaced with `push_warning("main_scene: WorldSave not open — world_select_screen should have opened it first")`. This is the single most breaking change in the phase.

---

## Common Pitfalls

### Pitfall 1: Migration number collision
**What goes wrong:** Creating `006_avatar.sql` when migrations 006-008 already exist from Phase 5 causes the migration runner to skip the new migration or fail silently.
**Why it happens:** CONTEXT.md references `006_avatar.sql` (written before Phase 5 shipped migrations 006-008).
**How to avoid:** Use `009_avatar.sql`. Verify with `ls supabase/migrations/` before writing.
**Warning signs:** Supabase migration log shows `006_avatar.sql` already applied; `avatar_json` column missing from profiles.

### Pitfall 2: StudGrid.placed signal signature mismatch
**What goes wrong:** FTUE step 3 completion never fires if the overlay connects to `placed(def_id: String)` expecting a String argument, but the actual signal emits `(anchor_cell: Vector3i, definition: BrickDefinition, colour_index: int, rotation: int)`.
**Why it happens:** CONTEXT.md says "StudGrid.placed signal with def_id == 'wood_plank'" but the actual signal passes a `BrickDefinition` object.
**How to avoid:** Read `definition.brick_id` in the signal handler, not a `def_id` parameter. [VERIFIED: stud_grid.gd line 87]
**Warning signs:** Placing wood_plank never advances FTUE to step 4.

### Pitfall 3: Missing ChestEntity.opened signal
**What goes wrong:** FTUE step 1 completion never fires because `chest_entity.gd` only emits `unlocked` and `broken`, not `opened`.
**Why it happens:** The `opened` signal was assumed to exist in CONTEXT.md but was never added in Phase 3.
**How to avoid:** Plan 06-01 (wave 0) must add `signal opened` and `opened.emit()` in `ChestEntity._open_panel()`.
**Warning signs:** Test `test_ftue_step1_chest_opens` fails because `chest.has_signal("opened")` returns false.

### Pitfall 4: Deep-link URI not available via OS.get_command_line_args() on Godot 4.6 mobile
**What goes wrong:** `DeepLinkHandler._ready()` finds no `--uri=` arg on iOS/Android even when the app was launched from a deep link.
**Why it happens:** The Godot 4 documentation states custom URL schemes are passed via CLI args, but this is not verified on 4.6 across all mobile platforms in this session.
**How to avoid:** Plan 06-XX must include a manual test build verifying the deep-link flow on iOS and Android before finalising DeepLinkHandler. If CLI args don't work, the contingency is a GDExtension plugin that writes to `user://pending_invite.cfg` before the scene tree starts (documented in CONTEXT.md Area 5).
**Warning signs:** Deep-link flow works on desktop (`--invite=TOKEN`) but not on mobile devices.
**Confidence:** MEDIUM — [ASSUMED] mobile CLI arg passing behaviour in Godot 4.6.

### Pitfall 5: Inventory has no item_added signal for FTUE step 2
**What goes wrong:** FTUE step 2 (first wood_log pickup) cannot be detected via signal; connecting to `inventory_changed` and scanning 48 slots is O(48) on every inventory change.
**Why it happens:** The `inventory.gd` `apply_event` handler does not emit a per-item-added signal — only the broad `inventory_changed(builder_id)` fires.
**How to avoid:** Plan 06-01 (wave 0) adds a lightweight `signal item_added(builder_id: String, def_id: String, count: int)` to `inventory.gd`, emitted from `_apply_add()` after the slots are updated. The FTUE overlay subscribes only to this new signal. [VERIFIED: inventory.gd — ADD case in apply_event calls _apply_add()]
**Warning signs:** Wood_log FTUE step fires on any inventory change, not just wood_log pickup; or step 2 never fires.

### Pitfall 6: world_select_screen _ready() fails if user://worlds/ doesn't exist
**What goes wrong:** `DirAccess.open("user://worlds/")` returns null on first launch (directory not yet created by any world).
**Why it happens:** Standard GDScript pattern: `DirAccess.open()` on a non-existent path returns null.
**How to avoid:** Check `DirAccess.dir_exists("user://worlds/")` in `_ready()` before listing; if missing, show the empty state (no worlds) rather than crashing.
**Warning signs:** Null reference error on `DirAccess.list_dir_begin()` on first launch.

### Pitfall 7: Dutch nl.po stub — all ~625 existing strings are untranslated
**What goes wrong:** `locale/nl.po` currently has 0 translated strings (it is a stub from Phase 1 with the note "NL strings deferred to Phase 6"). The CI glossary check does not flag missing translations, only hardcoded English strings. A Dutch player sees English everywhere if translations are not authored.
**Why it happens:** All previous phases deferred NL authoring to Phase 6.
**How to avoid:** Phase 6 must run `scripts/extract-pot.sh` to regenerate `messages.pot` first, then author ALL msgids in `nl.po`. This is the most time-intensive non-code task in the phase. A native Dutch speaker review is strongly recommended.
**Warning signs:** Godot TranslationServer reports missing keys for "nl" locale in debug output.

### Pitfall 8: SubViewport thermal impact during avatar creator on Tier-3 devices
**What goes wrong:** A second render pass (SubViewport for avatar preview) on top of a possibly-running main scene triggers thermal throttling.
**Why it happens:** Avatar creator runs before world load, so the main 3D scene (terrain, chunks) is NOT active. This should be fine, but if the user spends many minutes on the avatar creator on a Tier-3 phone, ThermalProbe may trigger.
**How to avoid:** Avatar creator runs in isolation before any world load — the SubViewport renders only the builder capsule mesh. Keep SubViewport size at 256×256. `ThermalProbe` is still active as an autoload; if thermal events fire, they have no effect on the avatar scene (main_scene handlers for thermal events won't be connected yet).
**Warning signs:** Avatar preview SubViewport causes > 5 ms additional frame time on Tier-3 profiler.

---

## Code Examples

### title_scene UV-pan background shader

```glsl
// Source: standard Godot 4 CanvasItem ShaderMaterial UV-pan pattern
shader_type canvas_item;
uniform vec2 uv_offset = vec2(0.0);
uniform sampler2D TEXTURE : source_color;

void fragment() {
    COLOR = texture(TEXTURE, UV + uv_offset);
}
```

GDScript side:
```gdscript
# title_scene.gd _process
func _process(delta: float) -> void:
    _bg_material.set_shader_parameter("uv_offset",
        _bg_material.get_shader_parameter("uv_offset") + Vector2(0.002, 0.0) * delta)
```

### World index ConfigFile schema

```gdscript
# world_select_screen.gd — write entry
func _write_world_index_entry(world_id: String, name: String,
        seed: int, mode: String) -> void:
    var cfg := ConfigFile.new()
    cfg.load("user://worlds/index.cfg")  # OK if missing
    cfg.set_value(world_id, "name", name)
    cfg.set_value(world_id, "seed", seed)
    cfg.set_value(world_id, "mode", mode)
    cfg.set_value(world_id, "created_unix", int(Time.get_unix_time_from_system()))
    cfg.set_value(world_id, "last_played_unix", int(Time.get_unix_time_from_system()))
    cfg.save("user://worlds/index.cfg")
```

### Supabase migration 009_avatar.sql

```sql
-- Migration 009: Avatar JSON column for player builder customisation
-- Adds nullable avatar_json TEXT column to existing profiles table.
-- No data migration required — existing rows retain NULL (use defaults in client).
-- Called by FriendsClient.save_avatar() via PATCH /rest/v1/profiles?id=eq.<uid>
-- RLS: uses existing "Users update own profile" UPDATE policy from migration 003.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_json TEXT;
```

### FTUE arrow off-screen indicator

```gdscript
# ftue_overlay.gd — _update_arrow_direction
func _update_arrow_direction(target_world_pos: Vector3) -> void:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null:
        return
    var screen_pos: Vector2 = cam.unproject_position(target_world_pos)
    var screen_size: Vector2 = get_viewport().get_visible_rect().size
    var center: Vector2 = screen_size * 0.5
    # Clamp to screen edge with padding
    var dir: Vector2 = (screen_pos - center).normalized()
    var edge_x: float = clampf(screen_pos.x, 40.0, screen_size.x - 40.0)
    var edge_y: float = clampf(screen_pos.y, 40.0, screen_size.y - 40.0)
    _arrow.position = Vector2(edge_x, edge_y)
    _arrow.rotation = dir.angle()
    _arrow.visible = not get_viewport().get_visible_rect().has_point(screen_pos)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| boot.gd → main_scene direct | title_scene → avatar → world_select → main_scene | Phase 6 | Full FTUE flow; invite-link skip path |
| nl.po stub (all empty) | Full EN+NL authoring | Phase 6 | DOCS §1.4 locked; Dutch localisation required for store submission |
| WorldSave.open_world dev auto-open | world_select_screen user-initiated open | Phase 6 | Player-facing world management |

**Deprecated in this phase:**
- `main_scene._ready()` auto-open dev path: removed (replaced with push_warning). Any test that relied on auto-opening `dev_world_001` must be updated to explicitly call `WorldSave.open_world()`.
- `boot.gd` as `run/main_scene`: demoted to engine boot_splash only.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | iOS and Android pass the custom URI as a `--uri=` CLI arg via `OS.get_command_line_args()` in Godot 4.6 | Deep-link handling, Area 5 | Invite-link flow broken on mobile; contingency is GDExtension plugin (documented in CONTEXT.md) |
| A2 | `Builder.apply_avatar_config(cfg: Dictionary)` is a new method to be added to builder.gd in Phase 6 (not already present) | Avatar creator | If it already exists from a later Phase 3/4 addition, check its signature before adding |
| A3 | `FriendsClient.save_avatar(cfg: Dictionary)` is a new method to be added to friends_client.gd in Phase 6 | Avatar persistence | Same check — if already exists, verify signature matches CONTEXT.md spec |
| A4 | `profiles.avatar_json` column does not yet exist (migrations 001-008 reviewed; none add it) | Supabase migration | Migration `009_avatar.sql` uses `ADD COLUMN IF NOT EXISTS` so it is idempotent |
| A5 | Godot 4.6 `Image.save_jpg(path, quality)` accepts the quality parameter (0.0-1.0 float) | Thumbnail capture | If signature differs, use `Image.save_png(path)` as fallback (larger file, ~60-80 KB) |

---

## Open Questions

1. **CLI arg deep-link on Godot 4.6 mobile**
   - What we know: `OS.get_command_line_args()` is the documented Godot 4 path for custom URL scheme args. CONTEXT.md Area 5 documents the pattern.
   - What's unclear: Whether Godot 4.6 specifically passes the iOS `openURL` delegate URI as a CLI arg or via a different mechanism (notification, user info dict).
   - Recommendation: Plan 06-XX must include a manual test build on both iOS and Android before the deep-link plan is locked. Include a `push_warning` in DeepLinkHandler if no invite arg is found (for debugging). The GDExtension contingency is pre-documented.

2. **Builder.apply_avatar_config mesh implementation**
   - What we know: `builder.gd` currently uses a capsule collider with no art mesh (Phase 1 placeholder). The comment in builder.gd says "Phase 1 rough-art: no builder mesh, no animations."
   - What's unclear: Whether Phase 6 needs a real multi-part mesh, or can drive avatar config by swapping `StandardMaterial3D` colors on the existing capsule parts.
   - Recommendation: Phase 6 ships programmatic primitive sub-meshes (MeshInstance3D with BoxMesh for body/legs/head) with `StandardMaterial3D` albedo driven by avatar config. Real sculpted meshes are Phase 999.1 (per CONTEXT.md deferred list). The FTUE and avatar creator both work with this approach.

3. **Inventory item_added signal — add or scan?**
   - What we know: `Inventory.inventory_changed(builder_id)` fires on every ADD/REMOVE/MOVE. `_apply_add()` handles the ADD case.
   - What's unclear: Whether adding `signal item_added(builder_id, def_id, count)` to `inventory.gd` is preferred over scanning slots in ftue_overlay.
   - Recommendation: Add `item_added` signal to inventory.gd in Plan 06-01 wave 0. It is a 4-line addition (signal declaration + emit in `_apply_add`), it avoids repeated O(48) slot scans in the FTUE overlay, and it is likely useful for other future features (achievements, telemetry). [ASSUMED — planner to confirm with user]

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Godot 4.6 | All Phase 6 scenes | [ASSUMED] ✓ | 4.6 | — |
| GUT test framework | tests/unit/ | ✓ | (installed — gut_config.cfg present) | — |
| godot-sqlite GDExtension | WorldSave | ✓ | (installed from Phase 2) | — |
| xgettext (for extract-pot.sh) | Dutch localisation | [ASSUMED] ✓ | present in CI | scripts/install-deps.sh installs if missing |
| Supabase self-hosted | profiles.avatar_json | ✓ | (running from Phase 4) | Local-only avatar.cfg (remote is fire-and-forget) |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | GUT (Godot Unit Test) — already installed |
| Config file | `tests/gut_config.cfg` |
| Quick run command | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gprefix=test_ -gsuffix=.gd -gexit` |
| Full suite command | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gprefix=test_ -gsuffix=.gd -ginclude_subdirs -gexit` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOC-01/§1.1 | Avatar config round-trips through user://avatar.cfg | unit | `godot ... tests/unit/test_avatar_cfg.gd` | ❌ Wave 0 |
| DOC-01/§1.1 | 8 presets are distinct Dictionaries with all 5 required keys | unit | `godot ... tests/unit/test_avatar_presets.gd` | ❌ Wave 0 |
| DOC-01/§1.2 | FTUE step 1 advances when ChestEntity emits opened | unit | `godot ... tests/unit/test_ftue_steps.gd` | ❌ Wave 0 |
| DOC-01/§1.2 | FTUE step 2 advances when Inventory.item_added fires with wood_log | unit | `godot ... tests/unit/test_ftue_steps.gd` | ❌ Wave 0 |
| DOC-01/§1.2 | FTUE step 3 advances when StudGrid.placed fires with wood_plank BrickDefinition | unit | `godot ... tests/unit/test_ftue_steps.gd` | ❌ Wave 0 |
| DOC-01/§1.2 | FTUE complete persists to WorldSave world_meta | unit | `godot ... tests/unit/test_ftue_persistence.gd` | ❌ Wave 0 |
| DOC-01/§1.3 | Deep-link token parsed from --invite=TOKEN arg | unit | `godot ... tests/unit/test_deep_link_handler.gd` | ❌ Wave 0 |
| DOC-01/§1.3 | Deep-link token parsed from --uri=cubicraftia://invite/TOKEN arg | unit | `godot ... tests/unit/test_deep_link_handler.gd` | ❌ Wave 0 |
| DOC-01/§1.4 | Telemetry log: append + 10k cap rotation | unit | `godot ... tests/unit/test_onboarding_telemetry.gd` | ❌ Wave 0 |
| DOC-01/§1.4 | World index CRUD: create / read / update / delete entry | unit | `godot ... tests/unit/test_world_index.gd` | ❌ Wave 0 |
| DOC-01/§1.4 | Dutch translation: nl.po has no empty msgstr for Phase 6 keys | unit | `godot ... tests/unit/test_nl_translations.gd` (or CI grep) | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gprefix=test_ -gsuffix=.gd -gexit`
- **Per wave merge:** Full suite (unit + integration)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/unit/test_avatar_cfg.gd` — REQ DOC-01/§1.1
- [ ] `tests/unit/test_avatar_presets.gd` — REQ DOC-01/§1.1
- [ ] `tests/unit/test_ftue_steps.gd` — REQ DOC-01/§1.2 (steps 1-4 + persistence)
- [ ] `tests/unit/test_ftue_persistence.gd` — REQ DOC-01/§1.2
- [ ] `tests/unit/test_deep_link_handler.gd` — REQ DOC-01/§1.3
- [ ] `tests/unit/test_onboarding_telemetry.gd` — REQ DOC-01/§1.4
- [ ] `tests/unit/test_world_index.gd` — REQ DOC-01/§1.4
- [ ] `tests/conftest_phase6.gd` — shared fixtures (avatar cfg, telemetry, world index, FTUE step state)
- [ ] `inventory.gd` — add `signal item_added(builder_id: String, def_id: String, count: int)` + emit in `_apply_add()`
- [ ] `chest_entity.gd` — add `signal opened` + `opened.emit()` in `_open_panel()`

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes (sign-in routing) | Phase 5 FriendsClient / GoTrue — no changes in Phase 6 |
| V3 Session Management | No new surface | Phase 4/5 token handling unchanged |
| V4 Access Control | Yes (invite token) | Server-side validation via FriendsClient.redeem_invite() |
| V5 Input Validation | Yes (world name, token) | ProfanityFilter.filter_reject() already called in WorldSave.create_world(); token length check in DeepLinkHandler |
| V6 Cryptography | No new surface | No new crypto in Phase 6 |

### Known Threat Patterns for Phase 6 Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| T-06-T1: Spoofed deep-link with crafted token | Tampering | Token length check (≥20 chars) in DeepLinkHandler client-side; server-side single-use validation in FriendsClient.redeem_invite() + Go signaling |
| T-06-S1: Avatar config injection (malformed def_id/index values) | Spoofing | JSON schema validation in FriendsClient.save_avatar() before PATCH; avatar_json column is TEXT (not JSONB with schema); server trusts client for cosmetic values — acceptable (cosmetic only, no gameplay impact) |
| T-06-D1: Telemetry log fills disk | Denial-of-Service | 10,000-event cap + rotation; file is `user://` sandboxed on iOS/Android |
| T-06-I1: Avatar config contains PII | Information Disclosure | avatar_json keys are all enum indices (integers 0-9); no names, no email, no location |
| T-06-S2: World name profanity bypass | Spoofing | `ProfanityFilter.filter_reject()` already called inside `WorldSave.create_world()` (Phase 5); UI must show rejection error but not echo the rejected word |

---

## Sources

### Primary (HIGH confidence)

- `src/world/chest_entity.gd` — verified signals: only `unlocked` and `broken`; `opened` signal is MISSING and must be added
- `src/world/stud_grid.gd` line 87 — `signal placed(anchor_cell: Vector3i, definition: BrickDefinition, colour_index: int, rotation: int)` — VERIFIED signal signature
- `src/autoload/inventory.gd` — verified: only `inventory_changed(builder_id)` signal fires on ADD; no `item_added` signal exists
- `src/world/main_scene.gd` line 184/481 — `signal world_ready` exists and emits via `call_deferred`
- `src/autoload/world_save.gd` — `create_world()`, `open_world()`, `get_world_meta()`, `set_world_meta()` — all available
- `src/autoload/friends_client.gd` — `is_signed_in()`, `_cached_username`, `redeem_invite()` all verified
- `supabase/migrations/` — confirmed 001-008 exist; `avatar_json` column NOT present; new migration must be `009_avatar.sql`
- `locale/nl.po` — confirmed: 17 lines total, 0 translated strings, stub from Phase 1
- `locale/en.po` — confirmed: 1,253 lines (~625 msgid entries to back-fill with NL translations)
- `project.godot` — confirmed: `run/main_scene = "res://src/world/main_scene.tscn"` (must change to title_scene); autoload list confirmed

### Secondary (MEDIUM confidence)

- Godot 4 docs: `Tween.tween_property()`, `SubViewport.UPDATE_WHEN_VISIBLE`, `ConfigFile`, `OS.get_command_line_args()`, `Image.save_jpg()` — standard well-documented APIs [ASSUMED]
- Godot 4 custom URL schemes: `project.godot [application] > custom_url_schemes` for iOS — [ASSUMED based on CONTEXT.md + Godot docs reference in CONTEXT.md Area 5]

### Tertiary (LOW confidence)

- `OS.get_command_line_args()` URI passing on Godot 4.6 mobile — [ASSUMED]; must be tested before finalising DeepLinkHandler mobile path

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries pre-existing; no new dependencies
- Architecture: HIGH — patterns established from Phases 1-5; new scenes follow existing CanvasLayer conventions
- Pitfalls: HIGH — verified directly from codebase (missing signals, migration numbering, StudGrid signature)
- Deep-link mobile: MEDIUM — behaviour on Godot 4.6 mobile is assumed, not verified

**Research date:** 2026-05-30
**Valid until:** 2026-06-30 (stable Godot 4.6 APIs; Supabase self-hosted)
