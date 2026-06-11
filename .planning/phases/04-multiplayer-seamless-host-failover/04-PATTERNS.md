# Phase 4: Multiplayer & Seamless Host Failover — Pattern Map

**Mapped:** 2026-05-29
**Files analyzed:** 28 (new/modified files across autoloads, UI, networking, Go server, migrations, tests)
**Analogs found:** 22 / 28 (6 have no codebase analog — Go server, Supabase migrations, and new utility)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/autoload/network_manager.gd` | autoload/service | event-driven + request-response | `src/autoload/inventory.gd` | role-match |
| `src/autoload/session_registry.gd` | autoload/store | CRUD + event-driven | `src/autoload/inventory.gd` | role-match |
| `src/autoload/friends_client.gd` | autoload/service | request-response (HTTP REST) | `src/autoload/inventory.gd` (lifecycle) | partial-match |
| `src/autoload/inventory.gd` (EXTEND) | autoload | event-driven | `src/autoload/inventory.gd` | exact (self) |
| `src/autoload/world_save.gd` (EXTEND) | autoload/persistence | batch + CRUD | `src/autoload/world_save.gd` | exact (self) |
| `src/ui/sign_in_panel.gd/.tscn` | component | request-response | `src/ui/settings_menu.gd` | role-match |
| `src/ui/friends_panel.gd/.tscn` | component | request-response | `src/ui/inventory_slide_in.gd` | exact |
| `src/ui/invite_modal.gd/.tscn` | component | request-response | `src/ui/settings_menu.gd` (modal pattern) | role-match |
| `src/ui/join_screen.gd/.tscn` | component | request-response | `src/ui/hp_bar.gd` (CanvasLayer overlay) | partial-match |
| `src/ui/players_tab.gd` | component | CRUD + event-driven | `src/ui/settings_menu.gd` | role-match |
| `src/ui/chat_overlay.gd/.tscn` | component | event-driven | `src/ui/hp_bar.gd` (HUD overlay) | partial-match |
| `src/ui/handover_screen.gd/.tscn` | component | event-driven | `src/ui/hp_bar.gd` (overlay, signal-driven) | partial-match |
| `src/ui/network_hud.gd/.tscn` | component | event-driven (polling) | `src/ui/hp_bar.gd` | role-match |
| `src/world/remote_builder_nameplate.gd` | component | event-driven | `src/ui/hp_bar.gd` (signal → visual update) | partial-match |
| `src/networking/profanity_filter.gd` | utility | transform | none — new utility | no-analog |
| `mobile_overlay.gd` (EXTEND) | component | event-driven | `src/ui/mobile_overlay.gd` | exact (self) |
| `signaling-server/cmd/signaling/main.go` | service/config | request-response | none — new Go codebase | no-analog |
| `signaling-server/internal/hub/hub.go` | service | event-driven (pub-sub) | none — new Go codebase | no-analog |
| `signaling-server/internal/hub/session.go` | store | CRUD | none — new Go codebase | no-analog |
| `signaling-server/internal/hub/relay.go` | service | request-response | none — new Go codebase | no-analog |
| `signaling-server/internal/hub/auth.go` | middleware | request-response | none — new Go codebase | no-analog |
| `signaling-server/internal/config/config.go` | config | — | none — new Go codebase | no-analog |
| `supabase/migrations/001_friendships.sql` | migration | — | none — new Supabase codebase | no-analog |
| `supabase/migrations/002_invites.sql` | migration | — | none — new Supabase codebase | no-analog |
| `supabase/migrations/003_profiles.sql` | migration | — | none — new Supabase codebase | no-analog |
| `tests/conftest_phase4.gd` | test fixture | — | `tests/conftest_phase3.gd` | exact |
| `tests/unit/test_election_algorithm.gd` | test | — | `tests/unit/test_inventory_grid.gd` | exact |
| `tests/integration/test_snapshot_migration.gd` | test | — | `tests/integration/test_death_respawn.gd` | exact |

---

## Pattern Assignments

### `src/autoload/network_manager.gd` (autoload, event-driven)

**Analog:** `src/autoload/inventory.gd`

**File header pattern** (lines 1-35):
```gdscript
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# network_manager.gd — NetworkManager autoload: WebRTC peer lifecycle,
#   keepalive loop, host-failover state machine, event broadcast bridge.
#
# Registered as autoload "NetworkManager" in project.godot AFTER Inventory
# and WorldSave (load-order contract — NetworkManager calls both at runtime).
#
# References:
#   04-RESEARCH.md Patterns 1-4 (WebRTC host/peer setup, RPC bridge, keepalive)
#   04-CONTEXT.md Area 1 (failover policy, 6 s keepalive, RTT metric)
#   04-CONTEXT.md Area 4 (event replication, snapshot reset)

extends Node
```

**Autoload `_ready` + null-safe singleton reference pattern** (inventory.gd lines 171-194):
```gdscript
func _ready() -> void:
    # Subscribe via signal + connect-on-_ready (canonical decoupling pattern).
    if Engine.has_singleton("WorldClock"):
        var world_clock = Engine.get_singleton("WorldClock")
        if world_clock.has_signal("day_boundary"):
            world_clock.day_boundary.connect(_on_day_boundary)

    # Timer creation pattern (one-shot, restarted on demand).
    _persist_timer = Timer.new()
    _persist_timer.one_shot = true
    _persist_timer.wait_time = PERSIST_COALESCE_S
    _persist_timer.timeout.connect(_flush_persistence)
    add_child(_persist_timer)
```
Apply to NetworkManager: create keepalive `Timer` node in `_ready`, connect timeout → `_send_keepalive_to_all_peers`. Use `get_node_or_null('/root/Inventory')` with null-check for cross-autoload calls.

**Constants block pattern** (inventory.gd lines 44-74):
```gdscript
const SLOT_COUNT: int = 48
const PERSIST_COALESCE_S: float = 30.0
const FULL_TIP_COOLDOWN_S: float = 2.0
```
Apply to NetworkManager:
```gdscript
const KEEPALIVE_INTERVAL_S := 1.0
const KEEPALIVE_TIMEOUT_S := 6.0   # Area 1: 6 lost = disconnect
const KEEPALIVE_WARN_THRESHOLD := 3 # Area 4: 3 lost = laggy warning
const SNAPSHOT_INTERVAL_S := 30.0  # Area 4: snapshot cadence
```

**Signal declarations pattern** (inventory.gd lines 86-106):
```gdscript
signal inventory_changed(builder_id: String)
signal chest_unlocked(chunk_coord: Vector3i)
signal death_pile_spawned(builder_id: String, position: Vector3, dropped_contents: Array)
```
Apply to NetworkManager — declare all outward signals before private state:
```gdscript
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal peer_laggy(peer_id: int, is_laggy: bool)
signal host_failover_started()
signal host_failover_complete()
signal session_state_changed(new_state: String)
```

**Private state block pattern** (inventory.gd lines 108-153):
```gdscript
var _inventories: Dictionary = {}
var _journal: Array = []
var _next_seq: int = 0
var _dirty_builders: Dictionary = {}
var _persist_timer: Timer = null
```
Apply to NetworkManager — mirror structure with clearly typed private vars:
```gdscript
var _rtc_mp: WebRTCMultiplayerPeer = null
var _state: String = "IDLE"         # failover state machine string
var _keepalive_accum: float = 0.0
var _missed_keepalive_count: Dictionary = {}  # {peer_id: int}
var _pending_ice_candidates: Dictionary = {}  # {peer_id: Array}
var _snapshot_timer: Timer = null
```

**Event broadcast hook into Inventory** — add after `inventory.gd` line 283 (after `_journal.append(event)`):
```gdscript
# Phase 4: broadcast accepted events to peers (host only).
if is_instance_valid(NetworkManager) and NetworkManager.is_multiplayer_active() \
        and multiplayer.is_server():
    NetworkManager.broadcast_event(event)
```
Note: guard with `is_instance_valid(NetworkManager)` per Pitfall 8 — autoload order safety.

---

### `src/autoload/session_registry.gd` (autoload, CRUD + event-driven)

**Analog:** `src/autoload/inventory.gd`

**File header + extends Node pattern** (inventory.gd lines 1-36):
Same SPDX header, same `extends Node`, registered in project.godot after NetworkManager.

**Private state Dictionary pattern** (inventory.gd lines 108-153):
```gdscript
var _inventories: Dictionary = {}   # keyed collections
var _next_seq: int = 0              # monotonic counter
```
Apply to SessionRegistry:
```gdscript
var _peer_list: Dictionary = {}        # {peer_id: {uid, join_order, username}}
var _rtt_rolling_avg: Dictionary = {}  # {peer_id: float}  — 30s rolling avg (Area 1)
var _join_order: Dictionary = {}       # {peer_id: int} — monotonic join index
var _surviving_peers: Dictionary = {}  # updated during failover
var _session_id: String = ""
var _host_uid: String = ""
var _join_counter: int = 0
```

**Election algorithm** (04-RESEARCH.md lines 668-681):
```gdscript
func compute_elected_host() -> int:
    var candidates: Array = _surviving_peers.keys()
    candidates.sort_custom(func(a, b):
        var rtt_a: float = _rtt_rolling_avg.get(a, INF)
        var rtt_b: float = _rtt_rolling_avg.get(b, INF)
        if absf(rtt_a - rtt_b) < 1.0:
            return _join_order.get(a, INF) < _join_order.get(b, INF)
        return rtt_a < rtt_b
    )
    return candidates[0] if candidates.size() > 0 else multiplayer.get_unique_id()

func am_i_elected() -> bool:
    return compute_elected_host() == multiplayer.get_unique_id()
```

---

### `src/autoload/friends_client.gd` (autoload, request-response HTTP)

**Analog:** `src/autoload/inventory.gd` (lifecycle and singleton pattern only); HTTP call pattern from 04-RESEARCH.md.

**File header + extends Node** — identical to inventory.gd header. Registered in project.godot after NetworkManager.

**Private state for token storage** (04-RESEARCH.md lines 571-605):
```gdscript
var _access_token: String = ""
var _refresh_token: String = ""
var _user_id: String = ""
var _supabase_url: String = ""
var _anon_key: String = ""
```

**HTTP request pattern** (04-RESEARCH.md lines 583-605):
```gdscript
func _sign_in(email: String, password: String) -> void:
    var body := JSON.stringify({"email": email, "password": password})
    var headers := ["Content-Type: application/json", "apikey: " + _anon_key]
    $HTTPRequest.request(
        _supabase_url + "/auth/v1/token?grant_type=password",
        headers,
        HTTPClient.METHOD_POST,
        body
    )

func _on_request_completed(result, code, _headers, body):
    if result != HTTPRequest.RESULT_SUCCESS or code != 200:
        sign_in_failed.emit(tr("ui.signin.error_network"))
        return
    var json: Variant = JSON.parse_string(body.get_string_from_utf8())
    if json == null:
        sign_in_failed.emit(tr("ui.signin.error_network"))
        return
    _access_token = json.get("access_token", "")
    _refresh_token = json.get("refresh_token", "")
    _user_id = json.get("user", {}).get("id", "")
    _save_tokens()
    signed_in.emit(_user_id)
```
Token persistence uses `ConfigFile` with `user://auth.cfg`, `[auth]` section — mirrors settings_menu.gd's `SETTINGS_PATH = "user://settings.cfg"` / `ConfigFile` pattern (settings_menu.gd lines 197-202):
```gdscript
func _load_saved_preset() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) == OK:
        var saved: String = cfg.get_value(SECTION, "preset", "auto")
        _set_active_preset(saved as StringName)
```

**Signal declarations** — declare before private state, same as inventory.gd:
```gdscript
signal signed_in(user_id: String)
signal sign_in_failed(reason: String)
signal signed_out()
signal friends_loaded(friends: Array)
signal invite_created(token: String, link: String)
signal friendship_created(friend_uid: String)
```

---

### `src/autoload/world_save.gd` (EXTEND — add `save_world_snapshot`)

**Analog:** `src/autoload/world_save.gd` (self)

**Existing migration pattern to follow** (world_save.gd lines 610-632):
```gdscript
func _migrate_1_to_2() -> bool:
    push_warning("WorldSave._migrate_1_to_2: migrating world '%s' from schema v1 to v2." % world_id)

    if not _db.call("query", "BEGIN;"):
        push_error("WorldSave._migrate_1_to_2: could not BEGIN transaction.")
        return false

    var stmts := _v2_table_stmts()
    var table_names: Array[String] = ["inventories", "chests", "dropped_items", "recipes_known"]
    for i: int in stmts.size():
        if not _db.call("query", stmts[i]):
            push_error("WorldSave._migrate_1_to_2: failed to create '%s' table — rolling back." % table_names[i])
            _db.call("query", "ROLLBACK;")
            return false
    if not _db.call("query", "COMMIT;"):
        _db.call("query", "ROLLBACK;")
        return false
    return true
```
Phase 4 adds `_migrate_2_to_3()` following this exact pattern. New v3 table:
```sql
CREATE TABLE IF NOT EXISTS snapshots (
    snapshot_id   TEXT PRIMARY KEY,
    created_at    REAL NOT NULL,
    chunk_blob    BLOB,
    inventory_blob BLOB
);
```
Bump `SCHEMA_VERSION` from `2` to `3`. Add `3` case to `_migrate_schema()` while loop.

**New `save_world_snapshot` method** — mirrors `save_chest` pattern (world_save.gd lines 349-359):
```gdscript
func save_chest(chunk_coord: Vector3i, tier: String, locked: bool,
                contents_blob: PackedByteArray, double_partner: String) -> bool:
    if _db == null:
        return false
    _db.call("query_with_bindings",
        """INSERT OR REPLACE INTO chests ...""",
        [chunk_coord.x, chunk_coord.y, chunk_coord.z, tier, int(locked), contents_blob, double_partner])
    return true
```
Apply to `save_world_snapshot`:
```gdscript
func save_world_snapshot(snapshot_id: String) -> bool:
    if _db == null:
        return false
    var inventory_blob := var_to_bytes(Inventory.get_all_state())
    # chunk_blob: Zstd-compressed serialisation of dirty chunks (reuse _save_chunk path)
    _db.call("query_with_bindings",
        "INSERT OR REPLACE INTO snapshots(snapshot_id, created_at, chunk_blob, inventory_blob) VALUES (?, ?, ?, ?);",
        [snapshot_id, Time.get_unix_time_from_system(), PackedByteArray(), inventory_blob])
    return true
```

---

### `src/ui/sign_in_panel.gd/.tscn` (component, request-response)

**Analog:** `src/ui/settings_menu.gd`

**Class header + extends pattern** (settings_menu.gd lines 38-43):
```gdscript
extends PanelContainer
```
`sign_in_panel.gd` uses `extends Control` (full-screen CanvasLayer child, not a sub-panel).

**ConfigFile persistence pattern** (settings_menu.gd lines 197-202):
```gdscript
const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "graphics"

func _load_saved_preset() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) == OK:
        var saved: String = cfg.get_value(SECTION, "preset", "auto")
```
Apply: `const AUTH_PATH := "user://auth.cfg"` / `const SECTION := "auth"`.

**Tab styling pattern** (inventory_slide_in.gd lines 570-598):
```gdscript
func _apply_tab_style(btn: Button, active: bool) -> void:
    if active:
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.106, 0.173, 0.337, 1.0)
        style.border_width_bottom = 2
        style.border_color = COLOR_ACCENT
        style.content_margin_left = 12.0
        style.content_margin_top = 8.0
        style.content_margin_right = 12.0
        style.content_margin_bottom = 6.0
        style.corner_radius_top_left = 8
        style.corner_radius_top_right = 8
        btn.add_theme_stylebox_override("normal", style)
        btn.add_theme_color_override("font_color", COLOR_ACCENT)
    else:
        var style := StyleBoxFlat.new()
        style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
        ...
        btn.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.7))
```
The Sign-in panel's "Sign in" / "Create account" tab buttons use `_apply_tab_style` verbatim. Import it as a static helper or copy it directly (same file is fine; it's < 30 lines).

**i18n string pattern** — all labels use `tr("ui.signin.<key>")` never hardcoded English strings. Mirror settings_menu.gd `_setup_labels()` (lines 130-139):
```gdscript
func _setup_labels() -> void:
    _title_label.text = "Settings"      # ← Phase 4 must use tr("ui.signin.title")
    _graphics_label.text = "Graphics"   # ← Phase 4 equivalent: tr("ui.signin.tab.signin")
    _brick_packs_label.text = tr("ui.settings.iap.title")
```

**Destructive / button style pattern** (settings_menu.gd lines 178-195):
```gdscript
var style := StyleBoxFlat.new()
style.bg_color = Color(0.106, 0.173, 0.337, 0.85)
style.border_width_left = 2
...
style.border_color = COLOR_DESTRUCTIVE
style.corner_radius_top_left = 8
...
_reset_button.add_theme_stylebox_override("normal", style)
_reset_button.add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
```
For the new `StyleBox_button_secondary` (UI-SPEC surface 4): transparent background, 1px brick-white border at 80% alpha, 8px corners — add to `cubicraftia.tres` as a new entry (do NOT redefine existing StyleBoxes).

---

### `src/ui/friends_panel.gd/.tscn` (component, request-response)

**Analog:** `src/ui/inventory_slide_in.gd` — copy chrome verbatim.

**Chrome verbatim copy** (inventory_slide_in.gd lines 220-236):
```gdscript
func _setup_panel_style() -> void:
    if _body == null:
        return
    var style := StyleBoxFlat.new()
    style.bg_color = COLOR_NAVY
    if layout == "sidebar":
        style.corner_radius_top_left = 16
        style.corner_radius_bottom_left = 16
        style.corner_radius_top_right = 0
        style.corner_radius_bottom_right = 0
    else:
        style.corner_radius_top_left = 16
        style.corner_radius_top_right = 16
        style.corner_radius_bottom_left = 0
        style.corner_radius_bottom_right = 0
    _body.add_theme_stylebox_override("panel", style)
```

**Animate-to pattern** (inventory_slide_in.gd lines 684-691):
```gdscript
func _animate_to(target_y: float) -> void:
    if _tween != null and _tween.is_running():
        _tween.kill()
    _tween = create_tween()
    _tween.tween_property(self, "position:y", target_y, TWEEN_DURATION_S)\
        .set_ease(Tween.EASE_OUT)\
        .set_trans(Tween.TRANS_CUBIC)
```
Use `TWEEN_DURATION_S = 0.22` (verbatim from `inventory_slide_in.gd` constant).

**Snap-to-nearest gesture** (inventory_slide_in.gd lines 670-679):
```gdscript
func _snap_to_nearest() -> void:
    var mid: float = (_expanded_y + _collapsed_y) * 0.5
    if position.y <= mid:
        _animate_to(_expanded_y)
        _is_expanded = true
        _notify_mobile_overlay(true)
    else:
        _animate_to(_collapsed_y)
        _is_expanded = false
        _notify_mobile_overlay(false)
```

**Mobile overlay notification pattern** (inventory_slide_in.gd lines 709-722):
```gdscript
func _notify_mobile_overlay(is_open: bool) -> void:
    if not is_inside_tree():
        return
    var overlay: Node = null
    if get_tree().has_group("mobile_overlay"):
        overlay = get_tree().get_first_node_in_group("mobile_overlay")
    if overlay != null:
        if overlay.has_method("notify_inventory_open"):
            overlay.call("notify_inventory_open", is_open)
```
For friends panel: call `overlay.call("notify_friends_open", is_open)` — the new method added to `mobile_overlay.gd` (see mobile_overlay extension below).

**Tab styling** — apply `_apply_tab_style` from `inventory_slide_in.gd` lines 570-598 (copy verbatim into `friends_panel.gd`).

**Mutual exclusion pattern** (inventory_slide_in.gd lines 293-300):
```gdscript
func open() -> void:
    # Close brick palette (mutual exclusion).
    if is_inside_tree():
        var palette := get_tree().get_first_node_in_group("brick_palette") if get_tree().has_group("brick_palette") else null
        if palette != null and palette.has_method("close"):
            palette.call("close")
```
Friends panel extends: also close the inventory slide-in on open.

**Exported layout property** (inventory_slide_in.gd line 65):
```gdscript
@export var layout: String = "sidebar"
```
Friends panel: same `@export var layout: String = "sidebar"` drives sidebar vs. bottomsheet chrome.

---

### `src/ui/invite_modal.gd/.tscn` (component, request-response)

**Analog:** `src/ui/settings_menu.gd` (modal pattern)

**Confirmation modal pattern** (settings_menu.gd lines 334-343):
```gdscript
func _show_reset_confirmation() -> void:
    var dialog := AcceptDialog.new()
    dialog.title = tr("ui.settings.graphics.reset")
    dialog.dialog_text = tr("ui.settings.graphics.reset.confirm")
    dialog.ok_button_text = tr("ui.settings.graphics.reset.do")
    dialog.get_ok_button().add_theme_color_override("font_color", COLOR_DESTRUCTIVE)
    dialog.confirmed.connect(_on_reset_confirmed)
    dialog.canceled.connect(dialog.queue_free)
    add_child(dialog)
    dialog.popup_centered()
```
Invite modal does NOT use `AcceptDialog` (not on-brand). Instead: `PanelContainer` with `StyleBoxFlat` navy background, manually positioned — mirrors the `_body` panel in `inventory_slide_in.gd`. The TTL countdown uses a `Timer` node created in `_ready` (timer pattern from inventory.gd lines 178-183).

**Clipboard copy pattern** — use `DisplayServer.clipboard_set(link)`. No GDScript analog exists; this is a one-liner.

---

### `src/ui/join_screen.gd/.tscn` (component, request-response)

**Analog:** `src/ui/hp_bar.gd` (signal-driven HUD overlay on CanvasLayer)

**Signal subscription in `_ready`** (hp_bar.gd lines 68-84):
```gdscript
func _ready() -> void:
    visible = Features.is_survival_mode()
    _build_hearts()
    var b: Node = get_tree().get_first_node_in_group("builder")
    if b != null and b.has_signal("hp_changed"):
        b.hp_changed.connect(_on_hp_changed)
        _builder = b as Builder
        _on_hp_changed(b.get("hp") if b.get("hp") != null else Builder.MAX_HP)
```
Apply to join_screen.gd: subscribe to `NetworkManager.session_state_changed` in `_ready`; show/hide based on state.

**CanvasLayer overlay pattern** (04-UI-SPEC.md Surface 5): `CanvasLayer` layer=20, full-screen `ColorRect` with navy 80% alpha. All text in `VBoxContainer` centred. Spinner: 4-frame `AnimatedSprite2D` (NOT ProgressBar — Tier-3 constraint per UI-SPEC).

---

### `src/ui/players_tab.gd` (component, CRUD + event-driven)

**Analog:** `src/ui/settings_menu.gd`

**`_ready` + `_setup_labels` pattern** (settings_menu.gd lines 122-139):
```gdscript
func _ready() -> void:
    _setup_labels()
    _build_preset_chips()
    _update_iap_section()
    _setup_buttons()
    _load_saved_preset()

func _setup_labels() -> void:
    _title_label.text = "Settings"
    _graphics_label.text = "Graphics"
    _brick_packs_label.text = tr("ui.settings.iap.title")
    _about_label.text = "About"
```
Apply to players_tab.gd: `_ready` calls `_setup_tab()`, `_build_player_list()`, `_setup_admin_controls()`.

**Tab header injection** — the existing `settings_menu.tscn` gets a new "Players" tab injected as tab[0]. Use the `_apply_tab_style` pattern (inventory_slide_in.gd lines 570-598) for the tab underline. Existing Graphics/BrickPacks/About sections shift into a "Settings" tab.

**Destructive button style** (settings_menu.gd lines 178-195): copy the `StyleBoxFlat` with `bg_color = COLOR_DESTRUCTIVE` pattern for Kick and Roll back buttons. Store as `StyleBox_button_destructive` in `cubicraftia.tres`.

**`@onready` node reference pattern** (settings_menu.gd lines 104-114):
```gdscript
@onready var _chips_container: HBoxContainer = $VBox/GraphicsSection/ChipsRow
@onready var _iap_label: Label = $VBox/BrickPacksSection/ComingLaterLabel
@onready var _done_button: Button = $VBox/DoneButton
```
Players tab: use `@onready` for the player list `VBoxContainer`, invite button, and roll-back section.

---

### `src/ui/chat_overlay.gd/.tscn` (component, event-driven)

**Analog:** `src/ui/hp_bar.gd` + `src/ui/mobile_overlay.gd`

**HUD visibility gate pattern** (hp_bar.gd lines 68-70):
```gdscript
func _ready() -> void:
    visible = Features.is_survival_mode()
```
Apply: `visible = NetworkManager.is_multiplayer_active()` — gate chat overlay on multiplayer session.

**Signal-driven update (no `_process`)** (hp_bar.gd lines 126-146):
```gdscript
func _on_hp_changed(new_hp: int) -> void:
    var hp_ratio: float = float(new_hp) / float(HEART_COUNT)
    ...
    for i: int in range(HEART_COUNT):
        var filled: bool = i < new_hp
```
Apply: connect to `NetworkManager`'s `chat_message_received` signal; update the `VBoxContainer` of Label nodes only on signal, never in `_process`.

**Mobile button wiring pattern** (mobile_overlay.gd lines 81-96):
```gdscript
var palette_btn := get_node_or_null("PaletteButton")
if palette_btn != null and palette_btn.has_signal("pressed"):
    palette_btn.pressed.connect(_on_palette_pressed)
if palette_btn != null:
    palette_btn.tooltip_text = tr("ui.palette.open")
```
Apply: new "Chat" `TouchScreenButton` in `mobile_overlay.tscn` wired to `_on_chat_pressed` using the same `get_node_or_null` + null-guard pattern.

**Input action pattern** (mobile_overlay.gd lines 183-185):
```gdscript
func _on_inventory_pressed() -> void:
    Input.action_press("ui_inventory_toggle")
    Input.action_release("ui_inventory_toggle")
```
Apply: `_on_chat_pressed` triggers `ui_chat_toggle` action.

---

### `src/ui/handover_screen.gd/.tscn` (component, event-driven)

**Analog:** `src/ui/hp_bar.gd`

**Signal subscription + auto-dismiss** (hp_bar.gd lines 78-84):
```gdscript
var b: Node = get_tree().get_first_node_in_group("builder")
if b != null and b.has_signal("hp_changed"):
    b.hp_changed.connect(_on_hp_changed)
```
Apply: in `_ready`, subscribe to `NetworkManager.host_failover_complete`:
```gdscript
func _ready() -> void:
    if is_instance_valid(NetworkManager):
        NetworkManager.host_failover_started.connect(_on_failover_started)
        NetworkManager.host_failover_complete.connect(_on_failover_complete)
```

**Tween dismiss pattern** (inventory_slide_in.gd lines 684-691 + line 704):
```gdscript
func _animate_to(target_y: float) -> void:
    if _tween != null and _tween.is_running():
        _tween.kill()
    _tween = create_tween()
    _tween.tween_property(self, "position:y", target_y, TWEEN_DURATION_S)\
        .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# hide after tween (inventory_slide_in.gd lines 700-704):
_tween.tween_callback(func(): visible = false)
```
Apply to handover: 0.22s fade-out tween on `modulate.a` → 0, then `queue_free()` (not hide — per UI-SPEC "removes itself").

**CanvasLayer 100** — highest layer, above all other UI. Use `CanvasLayer` with `layer = 100`. Not dismissible by player (no `_input` handler, no Escape key).

---

### `src/ui/network_hud.gd/.tscn` (component, event-driven polling)

**Analog:** `src/ui/hp_bar.gd`

**`_ready` build + signal subscribe** (hp_bar.gd lines 68-84):
```gdscript
func _ready() -> void:
    visible = Features.is_survival_mode()
    add_theme_constant_override("separation", HEART_GAP_PX)
    _build_hearts()
    var b: Node = get_tree().get_first_node_in_group("builder")
    if b != null and b.has_signal("hp_changed"):
        b.hp_changed.connect(_on_hp_changed)
```
Apply: `visible` gated on `NetworkManager.is_multiplayer_active()`. Build peer rows in `_build_peer_rows()`. Subscribe to `NetworkManager.peer_connected`, `peer_disconnected`, `peer_laggy`.

**Timer polling (1 Hz, not `_process`)** — create Timer in `_ready` for RTT bucket updates:
```gdscript
var _update_timer: Timer = Timer.new()
_update_timer.wait_time = 1.0
_update_timer.timeout.connect(_refresh_rtt_indicators)
add_child(_update_timer)
_update_timer.start()
```
All TextureRect icon sources are cached on peer-connect, not per-frame — mirrors hp_bar.gd's `load(ICON_FULL)` called once in `_build_hearts`.

**Icon cache pattern** (hp_bar.gd lines 96-116):
```gdscript
if ResourceLoader.exists(ICON_FULL, "Texture2D"):
    var tr_node := TextureRect.new()
    ...
    var tex: Texture2D = load(ICON_FULL)
    if tex != null:
        tr_node.texture = tex
    add_child(tr_node)
    _hearts.append(tr_node)
else:
    var cr_node := ColorRect.new()
    ...
```
Apply: load `icon_signal_1.png`, `icon_signal_2.png`, `icon_signal_3.png` once in `_ready`, cache in a `Dictionary`. Assign to `TextureRect.texture` in `_refresh_rtt_indicators` based on RTT bucket.

---

### `src/world/remote_builder_nameplate.gd` (component, event-driven)

**Analog:** `src/ui/hp_bar.gd` (signal → visual update, no per-frame text shaping)

This is a lightweight script attached to a `Label3D` node that is parented to each remote builder's head bone. No panel chrome needed.

**One-time setup pattern** (hp_bar.gd lines 68-84):
```gdscript
func _ready() -> void:
    visible = Features.is_survival_mode()
    _build_hearts()
```
Apply:
```gdscript
func _ready() -> void:
    # Username set once on spawn — never reshaped in _process.
    visible = _should_show_nameplates()
    _apply_label3d_settings()

func setup(username: String, builder_colour: Color) -> void:
    # Called by remote builder spawn logic immediately after add_child.
    $Label3D.text = username.left(16)  # truncate at 16 chars per UI-SPEC
    $Label3D.modulate = builder_colour
```

**Feature gate pattern** (hp_bar.gd line 70):
```gdscript
visible = Features.is_survival_mode()
```
Apply: `visible = _load_nameplate_setting()` reading from `user://settings.cfg` `[multiplayer]` section.

---

### `src/networking/profanity_filter.gd` (utility, transform)

**No codebase analog.** New pure-GDScript utility class.

**Structure to follow** — static utility class with no autoload, matching the `class_name` + `extends RefCounted` pattern used by `conftest_phase3.gd`:
```gdscript
class_name ProfanityFilter
extends RefCounted

# Stub word list; Phase 5 replaces with open contributable list.
const _WORD_LIST: Array[String] = ["badword1", "badword2"]  # ~20 test words

static func filter(text: String) -> String:
    var result := text
    for word: String in _WORD_LIST:
        var regex := RegEx.new()
        regex.compile("(?i)\\b" + word + "\\b")
        result = regex.sub(result, "[filtered]", true)
    return result
```

---

### `src/ui/mobile_overlay.gd` (EXTEND)

**Analog:** `src/ui/mobile_overlay.gd` (self)

**New `notify_friends_open(bool)` method** — mirrors existing `notify_inventory_open` (mobile_overlay.gd lines 143-168):
```gdscript
func notify_inventory_open(is_open: bool) -> void:
    _inventory_panel_open = is_open
    if is_open:
        if _palette_open and _palette_bottom_sheet != null and _palette_bottom_sheet.has_method("close"):
            _palette_bottom_sheet.call("close")
            _set_palette_open(false)
        var inv_btn := get_node_or_null("InventoryButton")
        if inv_btn != null and "tooltip_text" in inv_btn:
            inv_btn.tooltip_text = tr("ui.inventory.close")
    else:
        var inv_btn := get_node_or_null("InventoryButton")
        if inv_btn != null and "tooltip_text" in inv_btn:
            inv_btn.tooltip_text = tr("ui.inventory.open")
    if _crosshair != null:
        _crosshair.visible = not _palette_open and not _inventory_panel_open
```
Phase 4 adds `_friends_panel_open: bool = false` state var and `notify_friends_open(bool)` with identical structure: close palette + inventory on open; update crosshair visibility.

**New TouchScreenButton wiring** — add "Chat" and "Friends" buttons to `mobile_overlay.tscn` following the existing PaletteButton / InventoryButton node structure (lines 81-95). Wire in `_ready`:
```gdscript
var chat_btn := get_node_or_null("ChatButton")
if chat_btn != null and chat_btn.has_signal("pressed"):
    chat_btn.pressed.connect(_on_chat_pressed)
var friends_btn := get_node_or_null("FriendsButton")
if friends_btn != null and friends_btn.has_signal("pressed"):
    friends_btn.pressed.connect(_on_friends_pressed)
```

---

### `tests/conftest_phase4.gd` (test fixture)

**Analog:** `tests/conftest_phase3.gd` — copy structure verbatim, replacing Phase 3 references.

**File header** (conftest_phase3.gd lines 1-27):
```gdscript
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# conftest_phase4.gd — Shared GUT fixtures for the Phase 4 multiplayer test suite.
#
# NOT extends GutTest — helper class used by test files via preload().
# NOT registered as an autoload (test-only code).
#
# Usage:
#   const Phase4Fixtures = preload("res://tests/conftest_phase4.gd")
#   Phase4Fixtures.open_temp_world()

class_name Phase4Fixtures
extends RefCounted
```

**`open_temp_world` static pattern** (conftest_phase3.gd lines 39-50):
```gdscript
static func open_temp_world(mode: String = "survival") -> String:
    if WorldSave.is_open():
        push_warning("Phase3Fixtures.open_temp_world: a world is already open — closing it first.")
        WorldSave.close_world()
    var wid := "phase3_test_%d_%d" % [Time.get_ticks_msec(), randi()]
    var ok := WorldSave.open_world(wid, 42, mode)
    if not ok:
        push_error("Phase3Fixtures.open_temp_world: WorldSave.open_world('%s', 42, '%s') failed." % [wid, mode])
        return ""
    return wid
```
Phase 4 adds new fixture helpers for mock NetworkManager, fake peer RTT tables, and deterministic election setup:
```gdscript
## Create a fake peer RTT table for election algorithm tests.
static func make_rtt_table(peer_ids: Array, rtts: Array) -> Dictionary:
    var table: Dictionary = {}
    for i: int in range(peer_ids.size()):
        table[peer_ids[i]] = rtts[i]
    return table

## Create a fake join-order table for tiebreaker tests.
static func make_join_order(peer_ids: Array) -> Dictionary:
    var order: Dictionary = {}
    for i: int in range(peer_ids.size()):
        order[peer_ids[i]] = i
    return order
```

**`cleanup_temp_world` pattern** (conftest_phase3.gd lines 67-82):
```gdscript
static func cleanup_temp_world(world_id: String) -> void:
    if world_id.is_empty():
        return
    var world_dir := "user://worlds/%s" % world_id
    var abs_path := ProjectSettings.globalize_path(world_dir)
    var meta_path := abs_path + "/world.meta.sqlite"
    if FileAccess.file_exists(meta_path):
        DirAccess.remove_absolute(meta_path)
    for bak_n: int in [1, 2, 3]:
        var bak := meta_path + ".bak.%d" % bak_n
        if FileAccess.file_exists(bak):
            DirAccess.remove_absolute(bak)
    if DirAccess.dir_exists_absolute(abs_path):
        DirAccess.remove_absolute(abs_path)
```
Copy verbatim — same cleanup applies for Phase 4 temp worlds.

---

### `tests/unit/test_election_algorithm.gd` (test, unit)

**Analog:** `tests/unit/test_inventory_grid.gd`

**File structure** (test_inventory_grid.gd lines 1-32):
```gdscript
extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_grid_001"

func before_each() -> void:
    _world_id = Phase3Fixtures.open_temp_world("survival")
    Inventory.detach_world()
    Inventory.attach_world()

func after_each() -> void:
    Phase3Fixtures.close_temp_world()
    Phase3Fixtures.cleanup_temp_world(_world_id)
    _world_id = ""
```
Apply to test_election_algorithm.gd:
```gdscript
extends GutTest

const Phase4Fixtures = preload("res://tests/conftest_phase4.gd")

func before_each() -> void:
    pass  # Election algorithm is pure: no world needed

func after_each() -> void:
    pass

func test_lowest_rtt_wins() -> void:
    var rtt_table := Phase4Fixtures.make_rtt_table([1, 2, 3], [100.0, 50.0, 75.0])
    var join_order := Phase4Fixtures.make_join_order([1, 2, 3])
    # Assert peer 2 (lowest RTT 50ms) is elected.
    ...
```

**`assert_eq` test pattern** (test_inventory_grid.gd lines 37-42):
```gdscript
func test_grid_is_6x8_48_slots() -> void:
    var slots: Array = Inventory.get_slots(_builder_id)
    assert_eq(slots.size(), 48,
        "Inventory must have exactly 48 slots (6 rows × 8 columns per DOCS §4.1)")
```
Copy structure: one `func test_<behaviour>()` per behaviour, `assert_eq` / `assert_true` with descriptive error messages referencing DOCS or CONTEXT section.

---

### `tests/integration/test_snapshot_migration.gd` (test, integration)

**Analog:** `tests/integration/test_death_respawn.gd`

**File structure** (test_death_respawn.gd lines 1-30):
```gdscript
extends GutTest

const Phase3Fixtures = preload("res://tests/conftest_phase3.gd")

var _world_id: String = ""
var _builder_id: String = "test_builder_death_001"

func before_each() -> void:
    _world_id = Phase3Fixtures.open_temp_world("survival")

func after_each() -> void:
    Phase3Fixtures.close_temp_world()
    Phase3Fixtures.cleanup_temp_world(_world_id)
    _world_id = ""
```
Apply: use Phase4Fixtures, open a temp world, verify schema v3 migration ran cleanly, call `WorldSave.save_world_snapshot("test_snap_001")` and verify the snapshot row exists.

**`watch_signals` pattern** (test_death_respawn.gd line 44):
```gdscript
watch_signals(Inventory)
...
assert_signal_emitted(Inventory, "death_pile_spawned", ...)
```
Apply to snapshot integration tests: `watch_signals(WorldSave)` for any signals emitted during snapshot creation.

---

## Shared Patterns

### SPDX File Header
**Source:** All existing GDScript files (e.g., inventory.gd lines 1-2)
**Apply to:** ALL new `.gd` files
```gdscript
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
```

### Autoload Singleton Access (null-safe)
**Source:** `src/autoload/inventory.gd` lines 171-188 (_ready connect pattern); pitfall 8 in RESEARCH.md
**Apply to:** `network_manager.gd`, `session_registry.gd`, `friends_client.gd` — any cross-autoload call
```gdscript
# Safe cross-autoload reference — load order: NetworkManager after Inventory
if is_instance_valid(Inventory) and Inventory.has_method("apply_event"):
    Inventory.apply_event(event)
```

### Signal + Connect-on-Ready Decoupling
**Source:** `src/autoload/inventory.gd` lines 172-176; `src/ui/inventory_slide_in.gd` lines 144-153
**Apply to:** All new autoloads and UI components
```gdscript
# Connect in _ready, guard with has_signal for forward-compat.
if some_node.has_signal("some_signal"):
    some_node.some_signal.connect(_on_some_signal)
```

### i18n String Pattern
**Source:** `src/ui/settings_menu.gd` lines 130-139; `locale/en.po` header
**Apply to:** ALL new UI files (sign_in_panel, friends_panel, invite_modal, join_screen, players_tab, chat_overlay, handover_screen, network_hud)
```gdscript
# NEVER hardcode English strings — always use tr():
some_label.text = tr("ui.signin.title")
some_button.text = tr("ui.players.kick")
```
All new msgid keys use `ui.<surface>.<key>` namespace. Add to `locale/en.po` in the same plan that ships the surface. Do NOT collide with existing namespaces (`ui.builder.*`, `ui.hotbar.*`, `ui.settings.*`, `ui.inventory.*`, `ui.palette.*`, `ui.hp.*`, `ui.about.*`, `ui.common.*`).

### Theme Extension (cubicraftia.tres)
**Source:** `src/ui/inventory_slide_in.gd` `_setup_panel_style` (lines 220-236); `src/ui/settings_menu.gd` (lines 178-195)
**Apply to:** All Phase 4 UI files that need new StyleBoxes
- Add `StyleBox_button_secondary`, `StyleBox_button_destructive`, `StyleBox_relay_badge`, `StyleBox_chat_history_panel` to `assets/themes/cubicraftia.tres`.
- NEVER redefine existing Phase 1-3 StyleBoxes — only add new entries.

### ConfigFile Persistence
**Source:** `src/ui/settings_menu.gd` lines 197-202; `src/autoload/world_save.gd` open_world pattern
**Apply to:** `friends_client.gd` (auth token persistence), `players_tab.gd` (nameplate toggle)
```gdscript
# Read pattern:
var cfg := ConfigFile.new()
if cfg.load("user://auth.cfg") == OK:
    _access_token = cfg.get_value("auth", "access_token", "")

# Write pattern:
cfg.set_value("auth", "access_token", _access_token)
cfg.save("user://auth.cfg")
```

### get_node_or_null Tree Traversal
**Source:** `src/ui/inventory_slide_in.gd` lines 174-207 (`_resolve_node_refs`); `src/ui/mobile_overlay.gd` lines 81-95
**Apply to:** All new UI scene controllers
```gdscript
# Always use get_node_or_null, never get_node — missing nodes must not crash.
var btn := get_node_or_null("SomeButton") as Button
if btn != null and btn.has_signal("pressed"):
    btn.pressed.connect(_on_btn_pressed)
```

### Tween Kill-Before-Create
**Source:** `src/ui/inventory_slide_in.gd` lines 684-691
**Apply to:** `friends_panel.gd`, `handover_screen.gd`, any new animated panel
```gdscript
if _tween != null and _tween.is_running():
    _tween.kill()
_tween = create_tween()
_tween.tween_property(self, "position:y", target_y, TWEEN_DURATION_S)\
    .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
```

### Parameterised SQLite Queries (no string concatenation)
**Source:** `src/autoload/world_save.gd` lines 349-359 (`save_chest`)
**Apply to:** ALL new `_db.call("query_with_bindings", ...)` calls in world_save.gd extensions
```gdscript
# ALWAYS use query_with_bindings — never string concatenation:
_db.call("query_with_bindings",
    "INSERT OR REPLACE INTO snapshots(snapshot_id, created_at, chunk_blob, inventory_blob) VALUES (?, ?, ?, ?);",
    [snapshot_id, Time.get_unix_time_from_system(), chunk_blob, inventory_blob])
```

### Transactional Migration (BEGIN/COMMIT/ROLLBACK)
**Source:** `src/autoload/world_save.gd` lines 610-632 (`_migrate_1_to_2`)
**Apply to:** New `_migrate_2_to_3()` method in world_save.gd
```gdscript
func _migrate_2_to_3() -> bool:
    if not _db.call("query", "BEGIN;"):
        return false
    if not _db.call("query", "CREATE TABLE IF NOT EXISTS snapshots(...);"):
        _db.call("query", "ROLLBACK;")
        return false
    if not _db.call("query", "COMMIT;"):
        _db.call("query", "ROLLBACK;")
        return false
    return true
```

### Features Gate
**Source:** `src/autoload/features.gd` `is_enabled()` pattern; `src/ui/hp_bar.gd` line 70
**Apply to:** `network_hud.gd`, `chat_overlay.gd`, `remote_builder_nameplate.gd`
```gdscript
# Runtime multiplayer gate (not a feature flag — this is dynamic session state):
visible = is_instance_valid(NetworkManager) and NetworkManager.is_multiplayer_active()
```

---

## No Analog Found (Go + Supabase)

The Go signaling server and Supabase migrations are entirely new codebases. The planner should use RESEARCH.md sections directly as the spec for these files.

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `signaling-server/cmd/signaling/main.go` | service/entrypoint | request-response | No Go code exists in repo |
| `signaling-server/internal/hub/hub.go` | service | pub-sub (WebSocket) | No Go code exists in repo |
| `signaling-server/internal/hub/session.go` | store | CRUD | No Go code exists in repo |
| `signaling-server/internal/hub/relay.go` | service | request-response | No Go code exists in repo |
| `signaling-server/internal/hub/auth.go` | middleware | request-response | No Go code exists in repo |
| `signaling-server/internal/config/config.go` | config | — | No Go code exists in repo |
| `supabase/migrations/001_friendships.sql` | migration | — | No Supabase code exists in repo |
| `supabase/migrations/002_invites.sql` | migration | — | No Supabase code exists in repo |
| `supabase/migrations/003_profiles.sql` | migration | — | No Supabase code exists in repo |

**Planner reference for Go server:** Use 04-RESEARCH.md "Go Signaling Server" section (lines 349-438) as the complete spec — message envelope, module layout, JWT verification, deployment recipe are all specified there.

**Planner reference for Supabase migrations:** Use 04-RESEARCH.md "Supabase Schema" section (lines 446-552) — the complete CREATE TABLE + CREATE INDEX + RLS policy SQL is specified there verbatim.

**Go module structure note:** Go standard library only (`net/http` + `nhooyr.io/websocket` or stdlib upgrade). No third-party game frameworks. Single `go.mod` at `signaling-server/`. Build produces a single static binary per RESEARCH.md deployment recipe.

---

## Metadata

**Analog search scope:** `src/autoload/`, `src/ui/`, `tests/unit/`, `tests/integration/`, `locale/`, `assets/themes/`
**Files scanned:** 12 source files read in full; locale/en.po header; features.gd header
**Pattern extraction date:** 2026-05-29
**Valid until:** 2026-06-29 (consistent with RESEARCH.md validity)
