# Phase 6: First Five Minutes — Context

**Gathered:** 2026-05-30
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — 6/6 grey areas decided with defensible defaults

<domain>
## Phase Boundary

Phase 6 is the onboarding layer that wraps every previous phase into a coherent first-time experience. By the end of this phase:

- App launch shows a Cubicraftia title screen instead of auto-opening `dev_world_001` in survival mode.
- New players flow through: title → create account (Phase 5 sign_in_panel) → avatar creator → world selection → FTUE in-world tutorial.
- Returning players flow through: title → auto-restore session or sign in → world selection.
- Invite-link joiners bypass every screen and appear next to the host inside the host's world.
- All six areas listed in DOCS.md §1 ("First five minutes") are literally true of the shipped code.
- Every UI string is keyed in `locale/en.po` and `locale/nl.po` — no hardcoded strings. Dutch translations are authored for every Phase 6 key.
- A local-only telemetry event log captures step-by-step funnel data for playtesting without sending any data remotely.

Phase 5 shipped: sign_in_panel (with DOB picker and username validation), parental_gate_panel, EULA/privacy viewer, profanity filter, blocks/reports. Phase 6 wraps that existing UI in the title screen orchestration layer and adds only new elements: title_scene, avatar_creator, world_select_screen, FTUE overlay, deep-link handler, and the telemetry event log.

The main_scene.gd auto-open path (`WorldSave.open_world("dev_world_001", ...)` in `_ready()`) is removed in this phase. World creation is now user-initiated from world_select_screen.

</domain>

<decisions>
## Implementation Decisions

### Area 1 — Title Screen + Boot Flow

**Locked: title_scene.tscn replaces boot.gd as the run/main_scene in project.godot.**

- `src/ui/title_scene.gd` / `title_scene.tscn` — new scene, registered as `run/main_scene` in `project.godot`. The existing `boot.gd` splash is retained as the engine's `boot_splash` (millisecond flash); title_scene is what follows it.
- **Layout:** full-screen CanvasLayer (layer 0). Background is a pre-rendered or shader-generated low-poly brick world panorama (`assets/textures/title/title_bg.png` — placeholder stub for v1; artist can replace). Over it: Cubicraftia logo (SVG or 512px PNG), tagline, version string from `ProjectSettings.get_setting("application/config/version")`, and a vertical button stack.
- **Button stack:**
  - "Sign in" → opens Phase 5 `sign_in_panel.tscn` as a child CanvasLayer (layer 10, same as existing pattern). On `sign_in_complete` → check if avatar exists (`user://avatar.cfg`) → if not: show avatar creator → then world_select_screen. If avatar exists: world_select_screen directly.
  - "Create account" → same as "Sign in" but pre-selects the "Create account" tab in sign_in_panel.
  - "Continue offline" → skip sign-in, skip avatar (use default builder mesh), go directly to world_select_screen in offline mode (no Friends button, no invite creation).
  - "Settings" → opens existing `settings_menu.tscn` (same as Esc path in main_scene.gd).
- **Legal footer:** two small link labels at the bottom-left: "Terms of Use" and "Privacy Policy" — both open `legal_viewer.tscn` (Phase 5 scene). Same pattern as the existing About tab.
- **Already signed in (session restore):** if `FriendsClient.is_signed_in()` is true at title_scene `_ready()`, show a "Continue as [username]" button at the top of the stack (accent yellow). Tapping it bypasses sign-in and goes to world_select_screen with avatar check. The "Sign in" and "Create account" buttons are still visible below it for account switching.
- **Logo intro animation:** 2-second alpha-in tween on the logo + tagline (Tween.tween_property → modulate.a, 0.0 → 1.0, 2.0 s, ease in-out). Title music: placeholder silence (AudioStreamPlayer with no stream loaded — no crash if stream is null); artist drops `assets/audio/music/title_theme.ogg` in place and it loads automatically. Music loops. Fades out on scene transition.
- **Background animation:** slow pan via a ShaderMaterial UV offset uniform on the background TextureRect (0.002 UV units per second). No separate 3D scene for the title — pure 2D + shader for performance on Tier-3 mobile.
- **Deep-link intercept:** `title_scene._ready()` checks `OS.get_command_line_args()` for `--invite=TOKEN` (desktop) and a singleton `DeepLinkHandler` autoload checks the `cubicraftia://invite/{TOKEN}` URI on mobile (see Area 5). If a deep-link token is found at launch, title_scene emits `invite_link_received(token)` and transitions immediately to the join flow without showing the title UI.

### Area 2 — Avatar / Builder Customisation

**Locked: 5-part customiser, 8 one-tap presets, saved to user://avatar.cfg + Supabase profiles.avatar_json.**

- **Parts (locked from DOCS.md §1.1):**
  1. Head shape (3 shapes: square, round, tall) + face expression (5 expressions: neutral, happy, cool, surprised, sleepy) — combined as head + face picker, 3 × 5 = 15 combinations but UI shows shape row then expression row.
  2. Body torso colour (10 swatches from the 18-colour palette subset). Optional accessory slot: none / backpack / cape (3 options). Combined in one "body" section.
  3. Legs colour (10 swatches). Optional shoes: none / boots / sneakers (3 options). Combined in one "legs" section.
  4. Hand-held accessory: none / pickaxe / lantern / flower / blank (5 options — matches DOCS §1.1 exactly).
  5. **Skin colour (5 swatches):** applied to all exposed "skin" parts of the builder mesh (hands, face). Unlisted in DOCS §1.1 but required for inclusivity compliance. Considered a sub-option of the head section in the UI.
- **8 one-tap presets:** 8 pre-configured avatar dictionaries stored as constants in `avatar_creator.gd`. Tapping a preset applies all 5 parts instantly. The "Randomise" button (small, bottom-right) picks a random valid combination. Presets are diverse in skin tone, gender presentation, and accessory choice.
- **3D preview:** the avatar creator shows a rotating 3D builder preview using the existing `builder.tscn` mesh with `SubViewportContainer`. Camera orbits the builder slowly (0.4 rad/s). Each UI change triggers a rebuild of the builder's mesh by calling a new `Builder.apply_avatar_config(cfg: Dictionary)` method added to `src/builder/builder.gd`. The method is lightweight: it swaps material colours and sets accessory visibility flags on child nodes — no mesh re-import.
- **Persistence:**
  - Local: `user://avatar.cfg` ConfigFile, `[avatar]` section. Keys: `skin_colour_index`, `head_shape`, `face_expression`, `body_colour_index`, `body_accessory`, `leg_colour_index`, `leg_shoes`, `hand_accessory`. Written on "Done" and on any preset tap.
  - Remote: `FriendsClient.save_avatar(cfg: Dictionary)` → PATCH `/rest/v1/profiles?id=eq.<uid>` with `avatar_json = JSON.stringify(cfg)`. Fire-and-forget; failure is silent (local is canonical). A new `_avatar_req: HTTPRequest` node is added to FriendsClient following the existing HTTPRequest-per-concern pattern.
  - The `profiles` Supabase table already has an `avatar_json TEXT` column (add via migration `006_avatar.sql` in this phase).
- **Avatar is used for:** the builder mesh in-world (applied on world load via `Builder.apply_avatar_config`), the nameplate bubble (Phase 4 `remote_builder_nameplate.gd` reads `avatar_json` from the session state packet), and the friends list avatar icon (a 2D colour swatch derived from the body colour — no 3D render needed for the icon).
- **Avatar creator scene:** `src/ui/avatar_creator.gd` / `avatar_creator.tscn`. Full-screen CanvasLayer (layer 10). "Done" button → emits `avatar_complete`. "Back" button → emits `avatar_cancelled` (title_scene returns to sign-in or stays on title depending on context).
- **Phase 999.1 boundary:** unlockable avatar parts, animated emotes, and the full cosmetic store are deferred. The v1 customiser is fixed at the 5 parts above with no unlock gates.
- **Avatar name:** a single `avatar_name` field (display name, distinct from `username`) is NOT added in this phase. DOCS §8.4 and Phase 5 lock `username` as the single player-visible identity. Avatar name deferred to Phase 999.1.

### Area 3 — FTUE Guided Walkthrough

**Locked: 4-step embedded in-world tutorial, non-blocking overlay, unskippable per DOCS §1.2 and §1.4, persisted completion state.**

DOCS §1.4 explicitly states: "The tutorial is in-world and embedded — no separate tutorial scene" and "No 'skip tutorial' button — because the tutorial IS the first 60 seconds of play." The grey area description proposed a "Skip tutorial" link; this is overridden by the DOCS lock.

- **Trigger:** FTUE runs only when `WorldSave.get_world_meta("ftue_complete")` is null AND the world was just created (first-ever world for this profile). It does NOT re-run on subsequent logins to the same world. Persisted as `WorldSave.set_world_meta("ftue_complete", var_to_bytes(true))` when step 4 completes.
- **Steps (verbatim from DOCS §1.2):**
  1. Narration line appears bottom-third: **"Open the chest — you'll need what's inside before nightfall."** The starter chest (already spawned by Phase 3 `spawn_starter_chest_and_bed`) glows with an outline pulse (Shader on ChestEntity, `ftue_highlight` uniform bool). Completed when `ChestEntity.opened` signal fires.
  2. Narration line: **"Try mining the tree. Tap and hold a tree block."** The nearest tree trunk block is highlighted with a soft pulse for ~10 seconds (set nearest wood_log VoxelTool position as a highlight origin in a new `ftue_overlay.gd` uniform). Completed when first `wood_log` item enters inventory (Inventory event `PICK_UP` with `def_id == "wood_log"`).
  3. Narration line: **"Try placing a wooden plank."** Palette is soft-highlighted (pulsing border on `BrickPalette` node) on the `wood_plank` slot. Completed on first `StudGrid.placed` signal with `def_id == "wood_plank"`.
  4. Completion notification: **"That's it. The world is yours."** (fades in, stays 3 s, fades out). Optional 5th prompt (night-approach gate): if WorldClock transitions to DUSK before step 4 completes, an additional non-blocking hint appears: **"Time to sleep. Walk to the bed."** — this hint does NOT block step 4 completion. It is a parallel overlay, not a required step.
- **Overlay implementation:** `src/ui/ftue_overlay.gd` / `ftue_overlay.tscn` — CanvasLayer, layer 20 (above game UI at 10, below handover_screen at 100). The overlay contains only: a bottom-third narration Label (navy background, rounded corners, 80% screen width, auto-wrapping), and a thin top progress bar (Label: "Step N/4", ProgressBar: value = current step).
- **Arrow indicators:** the narration label has a directional arrow stub (TextureRect, `assets/icons/ftue_arrow.png`) that rotates to point toward the target entity using `get_viewport().get_camera_3d().unproject_position(target_world_pos)`. If the target is off-screen, the arrow clings to the screen edge (standard off-screen indicator pattern).
- **No modals:** all hints are non-blocking CanvasLayer elements. The player can walk, look, open inventory, chat — the tutorial does not pause the game.
- **Per DOCS §1.3:** invite-link joiners do NOT see the FTUE. Their `ftue_complete` meta is pre-set to `true` when they join via the deep-link path, before the world scene loads.
- **Multiplayer consideration:** if a friend joins a host who is mid-FTUE, the FTUE continues for the host. The joining peer never sees the FTUE (they are not first-world joiners). FTUE overlay is local-only, not replicated.

### Area 4 — World Selection / Home Screen

**Locked: world_select_screen.tscn with world cards (max 5 visible, scrollable), "New world" primary button, "Friends" secondary button.**

- **Scene:** `src/ui/world_select_screen.gd` / `world_select_screen.tscn`. Full-screen CanvasLayer (layer 0, replaces title_scene after sign-in).
- **World cards:** each card shows:
  - World name (bold, truncated to 24 chars with ellipsis)
  - Last played date ("Today", "Yesterday", or "3 days ago" — relative time via Time API)
  - Mode badge: "Creative" (blue pill) or "Survival" (orange pill)
  - Thumbnail: `user://worlds/{world_id}/thumbnail.png` — 256×144px screenshot taken at last save via `get_viewport().get_texture().get_image()`. If missing: a placeholder brick-pattern PNG (`assets/textures/ui/world_thumb_placeholder.png`).
  - Thumbnail is captured at `WorldSave.save_world()` call — a new `WorldSave.capture_thumbnail(world_id)` static method that calls `RenderingServer.force_draw()` then saves the viewport image. Called asynchronously (deferred 1 frame after save completes so the viewport has a valid image).
- **Actions on a world card:**
  - Tap / left-click → load world immediately (calls `WorldSave.open_world(world_id, seed, mode)` then `change_scene_to_file("res://src/world/main_scene.tscn")`).
  - Long-press (mobile) / right-click (desktop) → context menu with: Rename, Delete (confirmation modal), Duplicate, Export (saves a `.ccw` zip of the world SQLite files to the system Downloads folder via `OS.shell_open`).
- **"New world" button:** opens a creation modal (inline within world_select_screen, not a separate scene): name field (profanity-filtered via `ProfanityFilter.filter_reject` + `WorldSave.create_world` validation), seed field (empty = random `randi()`), mode toggle (Creative / Survival, default Survival). "Create" button → `WorldSave.create_world(name, seed, mode)` → if OK, appends to the world list and immediately loads the new world (triggering the FTUE flow for first-ever worlds).
- **"Friends" button:** opens `friends_panel.tscn` (Phase 4 existing scene) as an overlay. Friends who are in active sessions show "Open — [username] is playing [world name]" with a one-tap "Join" button (calls `FriendsClient.redeem_invite` flow → `NetworkManager.join_session`). This matches DOCS §6.4.
- **World list persistence:** `user://worlds/index.cfg` ConfigFile — one section per world: `[world_id]` with keys `name`, `seed`, `mode`, `last_played_unix`, `created_unix`. Maximum 5 worlds enforced at creation (show "Delete a world to create a new one" error if at cap). The index is rebuilt from the filesystem on each world_select_screen `_ready()` call (scan `user://worlds/` directories) as a consistency measure.
- **Offline mode:** in offline mode (Continue offline path from title), the Friends button is hidden. The world list is identical (worlds are local files). Session join is disabled.

### Area 5 — Invite-Link Joiner Skip Flow

**Locked: DeepLinkHandler autoload + cubicraftia:// custom URI scheme + OS.get_command_line_args() for desktop. Deep-link joiners skip title + FTUE + world selection, appearing directly in the host's world.**

- **`src/autoload/deep_link_handler.gd`** — new autoload, registered after FriendsClient in `project.godot`. Responsibilities:
  - On `_ready()`: check `OS.get_command_line_args()` for any arg containing `--invite=` (desktop); emit `invite_token_received(token)` if found.
  - On mobile: Godot's `MainLoop.on_request_permissions_result` / `OS.get_main_thread_id()` is not the right hook. Instead, use the `Application` notification pattern: in `_notification(what)`, handle `NOTIFICATION_WM_ABOUT_TO_QUIT` for cleanup and register a callback via `Engine.get_singleton("DeepLinkHandlerPlugin")` — but since a GDNative plugin is complex, the simpler v1 approach is: iOS Universal Links and Android App Links both relaunch the app with the URL as a command-line argument on Godot 4 (via the `--uri` argument passed by the OS on re-activation). Parse `--uri` arg: if it matches `cubicraftia://invite/{TOKEN}`, emit `invite_token_received(token)`.
  - Signal: `signal invite_token_received(token: String)`.
- **title_scene.gd** connects to `DeepLinkHandler.invite_token_received` in `_ready()`. On receipt: skip all title UI, call `_handle_invite_deep_link(token)`.
- **`_handle_invite_deep_link(token)`** flow:
  1. If `FriendsClient.is_signed_in()`: proceed to step 2.
  2. If not signed in: show a minimal inline sign-in prompt ("Sign in to join your friend's world", email + password fields only, no Create account tab). On sign-in complete: proceed to step 2. If the user taps "Create account" instead: run abbreviated sign-up (email + password + DOB only — no avatar creator, that comes post-join).
  3. `FriendsClient.redeem_invite(token)` → on `friendship_created(host_uid)`: `NetworkManager.join_session(host_uid)`.
  4. Pre-set `ftue_complete = true` in the pending world_meta (written before main_scene loads so the FTUE overlay never appears).
  5. Spawn position: the join_screen (Phase 4) handles "next to host" spawning via the existing `NetworkManager.peer_joined` → host broadcasts spawn position.
  6. Show the floating tip from DOCS §1.3: `"This is [Friend]'s world. They have what you need to get started."` — implemented as a one-shot `Toasts.show(...)` call (Phase 1 Toasts autoload, 8-second duration) after the world scene finishes loading.
- **Anonymous accounts for invite joiners:** in v1, invite redemption requires a signed-in account. There is no anonymous account path. A joiner who is not signed in sees the inline sign-in/create-account prompt before redemption. DOCS §1.3 implies the joiner creates their account via the invite link — this is the standard sign-up flow with the token preserved across the sign-up.
- **`first_time_joiner_marker`:** after joining via deep link, `user://ftue.cfg` is written with `[state] joined_via_invite = true`. On subsequent app launches, title_scene checks this marker and goes directly to world_select_screen (skipping title UI) if the user is signed in. This prevents the invite joiner from seeing "first launch" title animations on their second session.
- **Platform deep-link configuration:**
  - iOS: `project.godot` `[application] > custom_url_schemes = ["cubicraftia"]`. The `Info.plist` export override adds `CFBundleURLSchemes`. Universal Links require an `apple-app-site-association` file on `https://cubicraftia.com/.well-known/` — document in `docs/store-readiness/code-signing-runbook.md` as a pre-launch ops task.
  - Android: `AndroidManifest.xml` export override adds `<intent-filter>` with `<data android:scheme="cubicraftia"/>`. App Links (HTTPS) require `assetlinks.json` on the server — same pre-launch ops doc.
  - Desktop (macOS / Windows / Linux): `--invite=TOKEN` or `--uri=cubicraftia://invite/TOKEN` passed as CLI args by the OS when the user clicks the invite link and the game is not running.

### Area 6 — Onboarding Telemetry / Metrics (Anonymous)

**Locked: Local-only event log in user://telemetry.cfg, append-only, timestamp + event name only, no PII. No remote analytics in v1.**

- **`src/autoload/onboarding_telemetry.gd`** — new autoload, registered last in `project.godot` (after all other autoloads; telemetry must not block startup). Static convenience methods:
  - `OnboardingTelemetry.log(event_name: String)` — appends `{unix_ts: int, event: String}` to an in-memory queue. Queue is flushed to `user://telemetry.cfg` on `NOTIFICATION_WM_CLOSE_REQUEST` and every 60 seconds via a Timer.
  - No parameters beyond the event name — no world IDs, no usernames, no session IDs. The event name alone is sufficient for "did this player reach step 3?" analysis.
- **Locked event names (exhaustive list for Phase 6):**
  - `title_shown` — title_scene `_ready()` fires.
  - `deep_link_received` — DeepLinkHandler.invite_token_received fires.
  - `signup_started` — user taps "Create account".
  - `signup_complete` — FriendsClient.sign_up_ok fires.
  - `signin_complete` — FriendsClient.signed_in fires (covers both sign-in and session restore).
  - `avatar_picker_shown` — avatar_creator scene `_ready()` fires.
  - `avatar_complete` — user taps "Done" in avatar creator.
  - `world_select_shown` — world_select_screen `_ready()` fires.
  - `world_created` — WorldSave.create_world() returns OK.
  - `world_loaded` — main_scene.world_ready signal fires.
  - `ftue_step_1_complete` — chest opened.
  - `ftue_step_2_complete` — first wood_log picked up.
  - `ftue_step_3_complete` — first wood_plank placed.
  - `ftue_complete` — "That's it. The world is yours." notification shown.
  - `invite_joined` — deep-link join flow completes (NetworkManager.peer_joined fires for the self peer).
- **Persistence format:** `user://telemetry.cfg` is a ConfigFile with sections named `[event_N]` (N = incrementing integer, read from `[meta] event_count` key). Each section has `ts = <unix_int>` and `event = "<event_name>"`. Append-only; never deleted by the game. Total file size is capped at 10,000 events (oldest events are dropped on cap; this is ~6 months of daily play, well beyond the playtesting window).
- **Privacy policy compliance:** `docs/PRIVACY.md` (Phase 5 file) is updated in Phase 6 to enumerate the telemetry event log under "opt-in anonymous telemetry" (it is actually always-on for v1 since it is local-only, but the privacy policy describes it as "anonymous local log used for game improvement; never transmitted"). The privacy nutrition label is also updated if needed.
- **Remote analytics:** explicitly deferred to v1.x. If a future operator wants to enable remote analytics, `OnboardingTelemetry.log()` will be the single hook point — no other code needs to change.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets from Phases 1–5

- **`src/ui/boot.gd`** — current run/main_scene. Phase 6 replaces `run/main_scene` in `project.godot` with `title_scene.tscn`. `boot.gd` is retained as Godot's `boot_splash` (engine property), not as a scene. The `_MAIN_SCENE_PATH` constant and threaded load pattern in `boot.gd` should be reused in `title_scene.gd` for loading `main_scene.tscn` after the user initiates world load.

- **`src/ui/sign_in_panel.gd`** — Phase 5 full implementation. Emits `sign_in_complete`, `play_offline_requested`, `under_13_signup_required`. Phase 6's title_scene connects to these signals to advance the flow. The panel is opened as a child CanvasLayer (layer 10) — same as how the existing main_scene flow works. Phase 6 adds no code to sign_in_panel; it only adds a caller (title_scene).

- **`src/autoload/friends_client.gd`** — `is_signed_in()`, `get_user_id()`, `get_username()`, `signed_in`, `sign_up_ok`, `redeem_invite()`, `save_avatar()` (new method to add). The `_cached_username` field (Phase 5) is used to show "Continue as [username]" on the title screen. The new `_avatar_req: HTTPRequest` node follows the existing pattern (one HTTPRequest node per concurrent call type).

- **`src/autoload/world_save.gd`** — `create_world(name, seed, mode)` (Phase 5 wrapper with profanity check), `open_world(world_id, seed, mode)`, `is_open()`, `get_world_meta()`, `set_world_meta()`. Phase 6 uses `create_world()` from world_select_screen. The auto-open dev path in `main_scene._ready()` (`if not WorldSave.is_open(): WorldSave.open_world("dev_world_001", ...)`) must be removed — main_scene now only runs after world_select_screen has called `open_world()`.

- **`src/autoload/network_manager.gd`** — `join_session(host_uid)`, `get_session_id()`, `peer_joined` signal. Used by deep-link handler to initiate the join flow after invite redemption.

- **`src/ui/settings_menu.gd`** — opened via "Settings" on title screen (same `load("res://src/ui/settings_menu.tscn").instantiate()` pattern as main_scene._open_settings()).

- **`src/ui/legal_viewer.gd`** — opened via "Terms of Use" and "Privacy Policy" links on title screen (same `load().instantiate()` pattern).

- **`src/ui/friends_panel.gd`** — Phase 4 scene. Opened from world_select_screen "Friends" button. No changes needed to the panel itself.

- **`src/ui/parental_gate_panel.gd`** — Phase 5 scene. title_scene must connect to `sign_in_panel.under_13_signup_required` and show parental_gate_panel (same flow as Phase 5 planned but not yet wired in a title-screen context). Phase 5 left the wiring for the parent scene (now title_scene) to implement.

- **`src/autoload/toasts.gd`** — `Toasts.show(key, duration)`. Used for the invite-joiner tip ("This is [Friend]'s world...").

- **`src/world/main_scene.gd`** — `world_ready` signal (line 481). Phase 6 connects to this from the scene-change callback to show the FTUE overlay after the world has finished streaming its first chunks. The EULA check on sign-in (lines 466-476) remains unchanged.

- **`src/autoload/features.gd`** — `Features.is_survival_mode()`. FTUE only runs in survival mode (sandbox worlds don't have the starter chest + bed at a predictable location).

- **`src/networking/profanity_filter.gd`** — `ProfanityFilter.filter_reject(name)`. Used in world creation modal for the world name field (already called inside `WorldSave.create_world()` per Phase 5, but the UI must also show the rejection error).

- **`src/world/chest_entity.gd`** — emits an `opened` signal (check: if not present, Phase 6 plan must add it). Used as the FTUE step 1 completion trigger. The `ftue_highlight` uniform on ChestEntity's material is a new addition.

- **`src/autoload/inventory.gd`** — PICK_UP events. FTUE step 2 completion listens for the first `def_id == "wood_log"` PICK_UP event.

- **`src/world/stud_grid.gd`** — `placed` signal (check: if not present as a global signal, use `StudGrid` node group pattern). FTUE step 3 completion listens for first `def_id == "wood_plank"` placed event.

### Established Patterns

- **Autoloads:** `extends Node`, single-file, registered in `project.godot`. New autoloads: `DeepLinkHandler`, `OnboardingTelemetry`. Both are side-effect-free at import time (no HTTP calls, no file I/O in `class_name` scope).
- **Signals + connect-on-_ready** for decoupling. All title_scene-to-sign_in_panel connections follow this.
- **CanvasLayer layering scheme (confirmed from existing code):**
  - Layer 0: title_scene background, world_select_screen
  - Layer 10: sign_in_panel, avatar_creator, settings_menu (all existing patterns)
  - Layer 20: ftue_overlay (new — above game UI)
  - Layer 100: handover_screen (Phase 4 — unchanged)
  - Layer 128: in-world loading overlay in main_scene._build_loading_overlay() (unchanged)
- **ConfigFile persistence:** `user://` path, section-based. Both `user://avatar.cfg` and `user://telemetry.cfg` follow the same pattern as `user://auth.cfg` (FriendsClient) and `user://settings.cfg` (EULA hash).
- **Every UI string via `tr("ui.<surface>.<key>")`** in `locale/en.po` and `locale/nl.po`. Phase 6 adds new i18n keys for: title screen buttons, continue-as label, avatar creator section labels and preset names, world card relative-time strings, world creation modal, FTUE narration lines, invite-joiner tip, world-cap error. Dutch translations are authored for every key in this phase (not deferred).
- **GUT tests in `tests/unit/` and `tests/integration/`**: Phase 6 adds `tests/conftest_phase6.gd` with fixtures for: avatar cfg read/write, telemetry event append, world index CRUD, deep-link token parse, FTUE step completion logic.
- **Thumbnail capture:** uses `get_viewport().get_texture().get_image()` pattern (standard Godot). Must be called from main thread after `RenderingServer.force_draw()`. Deferred 1 frame after save to avoid capturing a partially-rendered frame.

### Integration Points

- **main_scene.gd line 332:** `if not WorldSave.is_open(): WorldSave.open_world("dev_world_001", _WORLD_SEED, "survival")` — **must be removed** in Phase 6. This is the only code path that auto-opens a world on engine boot. After removal, main_scene.tscn is only loaded when world_select_screen explicitly calls `change_scene_to_file`.
- **FriendsClient `signed_in` signal (line 65):** title_scene subscribes to this to advance from sign-in to avatar check. The same signal is already used by main_scene for EULA gate (line 472) — both subscriptions coexist safely (Godot signals are multicast).
- **WorldClock + main_scene _ready():** the `WorldClock.start(WorldClock.SECONDS_PER_DAY * 0.35)` call on line 393 starts the clock at midday only when it is not already running. FTUE step 1 narration mentions "before nightfall" — this is only meaningful if the world starts at midday, which this code ensures. No change needed.
- **ChestEntity `opened` signal:** Phase 6 plan must verify whether `chest_entity.gd` emits an `opened` signal. If it does not (it may only emit to its internal panel), the signal must be added in Phase 6 plan 06-XX alongside the ftue_overlay step 1 wiring.
- **StudGrid `placed` signal:** `stud_grid.gd` must emit a `placed(def_id, position)` signal (or an equivalent that the FTUE overlay can subscribe to) for FTUE step 3. If this signal does not exist, it must be added.
- **Supabase migration 006_avatar.sql:** adds `avatar_json TEXT` column to `profiles` table (if not already present from Phase 4 or 5). Phase 6 plan must verify the current profiles schema before adding.

</code_context>

<specifics>
## Specific Implementation Considerations

### Deep-Link Handling on Godot 4 Mobile

Godot 4 does not have a built-in `deep_link_received` signal. The canonical v1 approach for iOS and Android:

- **iOS:** Custom URL scheme (`cubicraftia://`) is registered in `project.godot` under `[application] > custom_url_schemes`. When the app is launched from a `cubicraftia://invite/TOKEN` link, iOS passes the URL to the app's `application:openURL:options:` delegate. Godot 4 exposes this as `OS.get_command_line_args()` containing a `--uri=cubicraftia://invite/TOKEN` argument. `DeepLinkHandler._ready()` parses this. Universal Links (`https://cubicraftia.com/invite/TOKEN` → app) require the `apple-app-site-association` file — a pre-launch ops task, not a code task; document in `docs/store-readiness/code-signing-runbook.md`.
- **Android:** Android App Links are handled similarly. The `cubicraftia://` scheme is declared in the `AndroidManifest.xml` export override. Godot 4 passes the intent URI as a CLI arg.
- **Godot version note:** confirm this behaviour on Godot 4.6 with a quick test build before committing to the pattern. If `OS.get_command_line_args()` does not include the URI on mobile, the fallback is a GDExtension plugin wrapper (Kotlin for Android, Swift for iOS) that writes the token to `user://pending_invite.cfg` before the Godot scene tree starts. The GDExtension fallback is a contingency, not the plan.

### Avatar 3D Preview Performance on Tier-3

The SubViewportContainer for the rotating builder preview is a second render pass. On Tier-3 devices (Motorola-class) this may cause frame budget pressure if the main scene is also running. Mitigations:

- Avatar creator runs before world load — there is no main 3D scene active. The SubViewport renders only the builder mesh, not terrain. This should be well within budget.
- SubViewport size: 256×256 px maximum. Use `update_mode = SubViewport.UPDATE_WHEN_VISIBLE`.
- If Tier-3 thermal events fire during the avatar creator (unlikely but possible if the user has been in the title for a long time), the `ThermalProbe.thermal_throttled` signal from main_scene is not active yet. The avatar creator should subscribe directly if needed — but this is unlikely to be necessary.

### Dutch Localisation Completeness

Phase 6 is the first phase where Dutch translations are authored alongside English (DOCS §1.4 lock). All previous phases used `tr()` calls but only populated `locale/en.po`. Phase 6 must:

1. Run `scripts/extract-pot.sh` to generate an updated `.pot` file from all GDScript `tr()` calls across all phases.
2. Author `locale/nl.po` translations for every key (including back-filling Phase 1-5 keys that already exist but have no NL translation). A native Dutch speaker review is recommended before store submission.
3. Add `locale/nl.po` to the `project.godot` `[application] > translations` array.
4. The CI glossary check script already validates that no hardcoded English strings appear in player-facing code. Dutch does not need a separate glossary check — the `tr()` key system is language-agnostic.

### World Thumbnail Capture

`get_viewport().get_texture().get_image()` is synchronous and blocks the main thread for ~5–15 ms on Tier-3 devices. To avoid a frame hitch at save time, the thumbnail capture must be scheduled with `call_deferred` after `WorldSave.save_world()` returns, and the viewport must have rendered at least one frame with the current world state. The 256×144 px size is chosen to keep file size under 30 KB (JPEG compression via `Image.save_jpg()`).

### World Index Rebuild vs. Persistent Index

The world_select_screen rebuilds the world list by scanning `user://worlds/` on every `_ready()`. This is safe for up to 5 worlds (the v1 cap) — directory enumeration of 5 entries is sub-millisecond. The `user://worlds/index.cfg` file serves as a cache for metadata (name, seed, mode, last_played) that is not stored in the world's SQLite file itself. If `index.cfg` is missing or corrupt, the fallback is to scan the SQLite files directly (each has a `world_meta.name` row). This fallback is documented but not implemented in v1 — if `index.cfg` is corrupt, the user sees an empty world list and must recreate (acceptable for a 5-world cap with SQLite backups).

### FTUE Signal Availability Verification

Before Phase 6 plans are written, two signal existence checks must be confirmed in the existing codebase:

1. Does `chest_entity.gd` emit an `opened` signal when the chest panel is opened by the local builder? If not, add: `signal opened` + `opened.emit()` in `_on_interact()` before calling `get_main_scene().spawn_chest_panel()`.
2. Does `stud_grid.gd` emit a `placed(def_id: String, position: Vector3)` signal? If not, add it and emit it from `StudGrid.place()` on success.

These additions are 2-line changes each and belong in the first Phase 6 plan (wave 0 scaffolding).

### Settings from Title Screen

The "Settings" button on the title screen opens `settings_menu.tscn`. The existing settings_menu was designed to run inside main_scene (it accesses `ThermalProbe`, `Features`, `translations`). All of these are autoloads and are available regardless of which scene is active — no changes to settings_menu are needed. The mouse-mode restore on settings close (Phase 2 main_scene._open_settings pattern) is not applicable at the title screen (no mouse capture at the title), so the title_scene's `_open_settings()` does not need to restore mouse mode.

### Main Scene Dev-Mode Removal

The `WorldSave.open_world("dev_world_001", _WORLD_SEED, "survival")` block in `main_scene._ready()` (lines 332-335) must be removed cleanly. It must NOT be replaced with a push_error — the condition `if not WorldSave.is_open()` should simply be removed. After Phase 6, `WorldSave.is_open()` is always true when `main_scene.tscn` loads (world_select_screen ensures this). A `push_warning` can be left as a defensive guard: `if not WorldSave.is_open(): push_warning("main_scene: WorldSave not open — world_select_screen should have opened it first")`.

</specifics>

<deferred>
## Deferred — Explicitly Out of Scope for Phase 6

- **Real avatar mesh editor** (Phase 999.1): sliders for body proportions, custom decal uploads, animated expressions. The v1 customiser is the 5-part palette described in Area 2, with no mesh deformation.
- **Daily login rewards / streak system**: not in DOCS. Deferred indefinitely.
- **Achievement system**: not in DOCS v1. Deferred to Phase 999.x.
- **Social FTUE prompts ("Invite a friend" push after tutorial")**: not in DOCS. Deferred.
- **Push notifications for "Your friend is online"**: not in DOCS. Deferred.
- **In-game news feed / MOTD**: not in DOCS. Deferred.
- **Avatar unlockables / cosmetic progression**: Phase 999.1 explicitly. v1 ships with fixed parts, no unlock gates.
- **Avatar display name** (distinct from username): DOCS §8.4 locks `username` as the single player-visible identity. No display name in v1.
- **Title screen 3D world background** (live rendered 3D scene): replaced with a static/shader-panned 2D texture for Tier-3 performance. Live 3D title background deferred to a future art pass.
- **Title music (original composition)**: placeholder silence in v1. The `AudioStreamPlayer` node is wired and will auto-play `assets/audio/music/title_theme.ogg` when that file is dropped in. Artist delivers it post-v1.
- **Universal Links / App Links server-side configuration**: `apple-app-site-association` and `assetlinks.json` are pre-launch ops tasks, not code tasks. Documented in `docs/store-readiness/code-signing-runbook.md` but not implemented in this phase.
- **Remote / cloud telemetry**: explicitly deferred to v1.x. Local-only telemetry.cfg is the v1 boundary.
- **World export / import UI**: Export is a context-menu item that calls `OS.shell_open` on the world directory. A full import UI (drag-and-drop `.ccw` file) is deferred.
- **More than 5 worlds**: v1 cap is 5. Higher limits require a world archive / cloud sync feature — deferred.
- **World thumbnail animated GIF / video**: static JPEG screenshot only in v1.
- **Localisation beyond EN + NL**: DOCS §1.4 locks English and Dutch for v1. FR, ES, DE, and others are contributable via the `locale/` file pattern but not required before v1 store submission.
- **FTUE "Skip" button**: explicitly forbidden by DOCS §1.4 ("No 'skip tutorial' button — because the tutorial IS the first 60 seconds of play"). Not deferred — permanently excluded.
- **Adaptive quality polish as a Phase 6 tail item**: ROADMAP.md Phase 6 spike mentions "adaptive quality polish" but the specific deliverable (the "Graphics adjusted for performance" notification UX pass) is already wired via `ThermalProbe.thermal_throttled` in main_scene and `settings_menu.gd`. No additional adaptive-quality work is required in Phase 6 unless the playtesting spike reveals a Tier-3 regression introduced by the title screen or avatar creator.

</deferred>
