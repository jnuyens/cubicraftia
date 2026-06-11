# Phase 5: Safety, Moderation & Store Readiness — Pattern Map

**Mapped:** 2026-05-29
**Files analyzed:** 29 new/modified files across autoloads, UI, Go server, migrations, tests, docs
**Analogs found:** 22 / 29 (7 have no codebase analog — new Go endpoints, new Supabase migrations, pure documentation)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `tests/conftest_phase5.gd` | test fixture | — | `tests/conftest_phase4.gd` | exact |
| `tests/unit/test_block_unblock.gd` | test | — | `tests/unit/test_friends_schema.gd` | exact |
| `tests/unit/test_report_submission.gd` | test | — | `tests/unit/test_friends_schema.gd` | exact |
| `tests/unit/test_dob_parser.gd` | test | — | `tests/unit/test_invite_token.gd` | exact |
| `tests/unit/test_parental_consent_token.gd` | test | — | `tests/unit/test_invite_token.gd` | exact |
| `tests/unit/test_profanity_multilang.gd` | test | — | `tests/unit/test_chat_rate_limit.gd` | exact |
| `tests/unit/test_username_validator.gd` | test | — | `tests/unit/test_election_algorithm.gd` (pure logic) | exact |
| `tests/unit/test_eula_hash_recompute.gd` | test | — | `tests/unit/test_election_algorithm.gd` | exact |
| `tests/integration/test_blocks_check_on_join.gd` | test | — | `tests/integration/test_failover_fault_injection.gd` | exact |
| `tests/integration/test_parental_consent_e2e.gd` | test | — | `tests/integration/test_snapshot_migration.gd` | exact |
| `src/networking/profanity_filter.gd` (EXTEND) | utility | transform | `src/networking/profanity_filter.gd` | exact (self) |
| `src/autoload/friends_client.gd` (EXTEND) | autoload/service | request-response | `src/autoload/friends_client.gd` | exact (self) |
| `src/autoload/username_policy.gd` | utility | pure transform | `src/networking/profanity_filter.gd` (class_name static) | role-match |
| `src/autoload/network_manager.gd` (EXTEND) | autoload/service | event-driven | `src/autoload/network_manager.gd` | exact (self) |
| `src/autoload/world_save.gd` (EXTEND) | autoload/persistence | CRUD | `src/autoload/world_save.gd` | exact (self) |
| `src/ui/sign_in_panel.gd/.tscn` (EXTEND) | component | request-response | `src/ui/sign_in_panel.gd` | exact (self) |
| `src/ui/parental_gate_panel.gd/.tscn` | component | event-driven | `src/ui/handover_screen.gd` (signal-driven CanvasLayer overlay) | partial-match |
| `src/ui/block_modal.gd/.tscn` | component | request-response | `src/ui/settings_menu.gd` (modal pattern) | role-match |
| `src/ui/report_modal.gd/.tscn` | component | request-response | `src/ui/settings_menu.gd` (modal pattern) | role-match |
| `src/ui/context_menu.gd/.tscn` | component | event-driven | `src/ui/mobile_overlay.gd` (singleton pattern) | partial-match |
| `src/ui/legal_viewer.gd/.tscn` | component | request-response | `src/ui/join_screen.gd` (CanvasLayer overlay, read-only display) | partial-match |
| `src/ui/eula_acknowledge_modal.gd/.tscn` | component | request-response | `src/ui/settings_menu.gd` (modal pattern) | role-match |
| `src/ui/settings_menu.gd/.tscn` (EXTEND) | component | CRUD | `src/ui/settings_menu.gd` | exact (self) |
| `src/ui/friends_panel.gd` (EXTEND) | component | event-driven | `src/ui/friends_panel.gd` | exact (self) |
| `src/ui/chat_overlay.gd` (EXTEND) | component | event-driven | `src/ui/chat_overlay.gd` | exact (self) |
| `src/world/remote_builder_nameplate.gd` (EXTEND) | component | event-driven | `src/world/remote_builder_nameplate.gd` | exact (self) |
| `signaling-server/internal/hub/consent.go` | service | request-response | `signaling-server/internal/hub/relay.go` (HTTP handler pattern) | partial-match |
| `supabase/migrations/004-008_*.sql` | migration | — | `supabase/migrations/001-003_*.sql` | exact (same pattern) |
| `docs/store-readiness/` + `docs/EULA.md` + `docs/PRIVACY.md` | documentation | — | none — new documentation | no-analog |

---

## Pattern Assignments

### `tests/conftest_phase5.gd` (test fixture)

**Analog:** `tests/conftest_phase4.gd` — copy structure verbatim.

**File header + class_name** (conftest_phase4.gd lines 1-12):
```gdscript
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# conftest_phase5.gd — Shared GUT fixtures for the Phase 5 safety test suite.
#
# NOT extends GutTest — helper class used by test files via preload().
# Usage:
#   const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")

class_name Phase5Fixtures
extends RefCounted
```

**Mock row helpers** (extend Phase4's make_rtt_table pattern):
```gdscript
static func make_mock_block_row(blocker: String, blocked: String) -> Dictionary:
    return {
        "blocker_uid": blocker,
        "blocked_uid": blocked,
        "created_at": Time.get_datetime_string_from_system()
    }

static func make_mock_report_row(reporter: String, reported: String, surface: String, category: String) -> Dictionary:
    return {
        "reporter_uid": reporter,
        "reported_uid": reported,
        "surface": surface,
        "category": category,
        "reason": "",
        "evidence": {},
        "created_at": Time.get_datetime_string_from_system()
    }

static func make_mock_consent_row(child_uid: String, parent_email: String) -> Dictionary:
    return {
        "child_uid": child_uid,
        "parent_email": parent_email,
        "requested_at": Time.get_datetime_string_from_system(),
        "consented_at": null,
        "revoked_at": null,
        "consent_token": "TESTTOKEN12345678",
        "revoke_token": "REVOKETOKEN12345"
    }
```

---

### `tests/unit/test_profanity_multilang.gd` (unit test)

**Analog:** `tests/unit/test_chat_rate_limit.gd`

**ProfanityFilter test pattern** (test_chat_rate_limit.gd):
```gdscript
func test_profanity_filter_replaces_word() -> void:
    ProfanityFilter.set_word_list(["badword"])
    var result := ProfanityFilter.filter("This is a badword message")
    assert_eq(result, "This is a [filtered] message",
        "filter() must replace matched word with [filtered] per DOCS §8.3")
```
Apply: use `load_word_lists()` instead of `set_word_list()` in Phase 5 (to test the real file-loaded lists). In `before_each()`:
```gdscript
func before_each() -> void:
    ProfanityFilter.load_word_lists()
```

**File structure** (test_chat_rate_limit.gd):
```gdscript
extends GutTest

const Phase5Fixtures = preload("res://tests/conftest_phase5.gd")

func before_each() -> void:
    ProfanityFilter.load_word_lists()

func test_filter_replaces_en_word() -> void:
    var known_word := "shit"  # from wordlist_en.txt
    var result := ProfanityFilter.filter("This is " + known_word + " content")
    assert_eq(result, "This is [filtered] content",
        "filter() must replace EN profanity with [filtered] per DOCS §8.3")
```

---

### `tests/unit/test_username_validator.gd` (unit test)

**Analog:** `tests/unit/test_election_algorithm.gd` (pure logic, no WorldSave needed)

**Pure-logic test pattern** (test_election_algorithm.gd):
```gdscript
func before_each() -> void:
    pass  # Election algorithm is pure: no world needed

func test_lowest_rtt_wins() -> void:
    var rtt_table := Phase4Fixtures.make_rtt_table([1, 2, 3], [100.0, 50.0, 75.0])
    ...
    assert_eq(elected, 2, "Peer with lowest RTT (50ms) must be elected")
```
Apply to username validator:
```gdscript
func before_each() -> void:
    pass  # UsernamePol is pure static: no setup needed

func test_reserved_prefix_admin_rejected() -> void:
    assert_true(UsernamePol.is_reserved("admin"),
        "Username 'admin' must be rejected as reserved per CONTEXT D-06 Area 6")

func test_reserved_prefix_catches_admin_prefix() -> void:
    assert_true(UsernamePol.is_reserved("admin123"),
        "Username 'admin123' must be rejected (starts with reserved prefix 'admin')")

func test_validate_returns_error_key() -> void:
    var result := UsernamePol.validate("cubicraftia")
    assert_false(result.valid, "Reserved username must not be valid")
    assert_eq(result.error_key, "ui.username.error_reserved",
        "Error key must match the i18n key used in the UI")
```

---

### `src/autoload/username_policy.gd` (utility, pure transform)

**Analog:** `src/networking/profanity_filter.gd` (static utility class, no HTTP, no autoload)

**Class structure** (profanity_filter.gd):
```gdscript
class_name ProfanityFilter
extends RefCounted

static var _regex: RegEx = null

static func filter(text: String) -> String: ...
static func filter_reject(text: String) -> bool: ...
```
Apply exactly to username_policy.gd:
```gdscript
class_name UsernamePol
extends RefCounted

const RESERVED_PREFIXES: Array[String] = [
    "admin", "mod", "moderator", "cubicraftia",
    "support", "staff", "system", "official"
]
const USERNAME_REGEX: String = "^[a-zA-Z0-9_]{3,20}$"

static func is_valid_format(username: String) -> bool:
    if username.is_empty():
        return false
    var regex := RegEx.new()
    regex.compile(USERNAME_REGEX)
    return regex.search(username) != null

static func is_reserved(username: String) -> bool:
    var lower := username.to_lower()
    for prefix: String in RESERVED_PREFIXES:
        if lower == prefix or lower.begins_with(prefix):
            return true
    return false

static func validate(username: String) -> Dictionary:
    if not is_valid_format(username):
        return {valid: false, error_key: "ui.username.error_format"}
    if is_reserved(username):
        return {valid: false, error_key: "ui.username.error_reserved"}
    if ProfanityFilter.filter_reject(username):
        return {valid: false, error_key: "ui.username.error_profanity"}
    return {valid: true, error_key: ""}
```

---

### `src/ui/block_modal.gd` / `src/ui/report_modal.gd` (modal components)

**Analog:** `src/ui/settings_menu.gd` (modal pattern via AcceptDialog or custom PanelContainer)

**Custom PanelContainer modal pattern** (settings_menu.gd destructive button style):
```gdscript
var style := StyleBoxFlat.new()
style.bg_color = Color(0.106, 0.173, 0.337, 0.85)  # dominant navy
style.border_width_left = 2
style.border_color = COLOR_DESTRUCTIVE
style.corner_radius_top_left = 8
```
Apply: Block modal and Report modal use PanelContainer (not AcceptDialog) with navy background and manual button layout. Cannot dismiss by tapping outside (mouse_filter = MOUSE_FILTER_STOP on the overlay ColorRect).

**Toast pattern** (existing Toasts autoload, Phase 1):
```gdscript
# Show confirmation toast via existing Toasts singleton
Toasts.show(tr("ui.block.toast_blocked").format({"username": username}), 3.0)
```

**CanvasLayer layer** (from 05-UI-SPEC.md Panel Mutual-Exclusion):
```gdscript
# Block modal, Report modal, EulaAcknowledgeModal: layer 20
# Context menu: layer 25 (above modals — can appear when modal not open)
```

---

### `src/ui/context_menu.gd` (singleton context menu)

**Analog:** `src/ui/mobile_overlay.gd` (singleton pattern, single instance reused)

**Singleton scene access pattern** (mobile_overlay.gd accessed via group):
```gdscript
# mobile_overlay.gd registers itself in "mobile_overlay" group
func _ready() -> void:
    add_to_group("mobile_overlay")

# Callers access via:
var overlay: Node = get_tree().get_first_node_in_group("mobile_overlay")
if overlay != null and overlay.has_method("notify_friends_open"):
    overlay.call("notify_friends_open", is_open)
```
Apply to ContextMenu: register as an autoloaded scene via project.godot (class_name ContextMenu), accessed globally. `show(items, screen_pos)` API:
```gdscript
static func show(items: Array[Dictionary], screen_pos: Vector2) -> void:
    # "items" entries: {label: String, action: Callable}
    # Clears existing buttons, builds new ones, positions, shows
```

**Dismissal pattern** (inventory_slide_in.gd _unhandled_input pattern for outside-tap dismiss):
```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return
    if event is InputEventMouseButton or event is InputEventScreenTouch:
        if not _panel.get_global_rect().has_point(event.position):
            hide()
            get_viewport().set_input_as_handled()
```

---

### `src/ui/legal_viewer.gd` (Markdown renderer)

**Analog:** `src/ui/join_screen.gd` (CanvasLayer overlay) + RichTextLabel pattern

**CanvasLayer show/hide pattern** (join_screen.gd, handover_screen.gd):
```gdscript
func _ready() -> void:
    visible = false

func show_screen() -> void:
    visible = true

func hide_screen() -> void:
    visible = false
```

**Chunked file hash pattern** (05-RESEARCH.md Pattern 4):
```gdscript
func _compute_hash(path: String) -> String:
    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return ""
    while not f.eof_reached():
        ctx.update(f.get_buffer(4096))
    f.close()
    return ctx.finish().hex_encode().substr(0, 16)
```

**Node tree build pattern for document rendering:**
```gdscript
# Build once in open(), cache the node tree. No re-parse on scroll.
func _build_document_nodes(content: String) -> void:
    for child in _scroll_content.get_children():
        child.queue_free()
    var lines := content.split("\n")
    for line in lines:
        var node := _line_to_node(line)
        if node != null:
            _scroll_content.add_child(node)
```

---

### `signaling-server/internal/hub/consent.go` (Go HTTP handler)

**Analog:** `signaling-server/internal/hub/relay.go` (HTTP handler, PostgREST calls)

**Go HTTP handler pattern** (relay.go):
```go
func (h *Hub) handleRelay(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, `{"error":"method_not_allowed"}`, http.StatusMethodNotAllowed)
        return
    }
    // Parse JWT, decode body, validate, call Supabase
}
```
Apply to consent.go:
```go
type ConsentHandler struct {
    Hub *Hub
}

func (c *ConsentHandler) HandleRequest(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, `{"error":"method_not_allowed"}`, http.StatusMethodNotAllowed)
        return
    }
    // verify JWT via c.Hub auth, generate tokens, INSERT, send SMTP
}
```

**Token generation pattern** (from existing FriendsClient invite token, ported to Go):
```go
// Generate 128-bit CSPRNG token, base32-encoded, no padding
import (
    "crypto/rand"
    "encoding/base32"
)

func generateToken() (string, error) {
    b := make([]byte, 16)
    if _, err := rand.Read(b); err != nil {
        return "", err
    }
    return base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b), nil
}
```

---

### `supabase/migrations/004-008_*.sql` (Supabase migrations)

**Analog:** `supabase/migrations/001_friendships.sql` / `002_invites.sql` / `003_profiles.sql`

**RLS policy pattern** (001_friendships.sql — exact pattern to replicate):
```sql
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- CRITICAL: Always (SELECT auth.uid()), never raw auth.uid()
CREATE POLICY "Users see own friendships"
  ON public.friendships FOR SELECT TO authenticated
  USING ( (SELECT auth.uid()) = user_a OR (SELECT auth.uid()) = user_b );
```

**SECURITY DEFINER function pattern** (new in Phase 5 — for functions that need to read restricted tables):
```sql
CREATE OR REPLACE FUNCTION public.can_change_username(user_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER  -- Runs as function owner, bypasses RLS
AS $$
BEGIN
  -- Query username_change_log without RLS restrictions
  RETURN (SELECT changed_at < NOW() - INTERVAL '30 days'
          FROM public.username_change_log
          WHERE uid = user_uid
          ORDER BY changed_at DESC LIMIT 1)
         IS NOT FALSE;  -- NULL = no changes = allowed
END;
$$;
```

---

## Shared Patterns

### SPDX File Header
**Source:** All existing GDScript files
**Apply to:** ALL new .gd files in Phase 5
```gdscript
# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
```

### Long-Press Timer Pattern (new in Phase 5)
**Source:** Mobile overlay button press detection (Phase 4)
**Apply to:** friends_panel.gd, chat_overlay.gd, remote_builder_nameplate.gd
```gdscript
var _long_press_timer: Timer = null
var _long_press_target_uid: String = ""

func _ready() -> void:
    _long_press_timer = Timer.new()
    _long_press_timer.one_shot = true
    _long_press_timer.wait_time = 0.5
    _long_press_timer.timeout.connect(_on_long_press_timeout)
    add_child(_long_press_timer)

# On input down:
func _start_long_press(uid: String, screen_pos: Vector2) -> void:
    _long_press_target_uid = uid
    _long_press_target_pos = screen_pos
    _long_press_timer.start()

# On input up:
func _cancel_long_press() -> void:
    _long_press_timer.stop()
```

### ConfigFile Legal Hash Storage Pattern (new in Phase 5)
**Source:** settings_menu.gd ConfigFile pattern + 05-RESEARCH.md Pattern 4
**Apply to:** friends_client.gd (check_eula_acknowledgement, store_eula_hash)
```gdscript
const LEGAL_SECTION := "legal"
const EULA_HASH_KEY := "eula_hash"

func check_eula_acknowledgement() -> bool:
    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    var f := FileAccess.open("res://docs/EULA.md", FileAccess.READ)
    if f == null:
        return true  # Fail open — don't block play if file missing
    while not f.eof_reached():
        ctx.update(f.get_buffer(4096))
    f.close()
    var current_hash: String = ctx.finish().hex_encode().substr(0, 16)
    var cfg := ConfigFile.new()
    cfg.load("user://settings.cfg")
    var stored_hash: String = cfg.get_value(LEGAL_SECTION, EULA_HASH_KEY, "")
    return stored_hash == current_hash

func store_eula_hash(hash: String) -> void:
    var cfg := ConfigFile.new()
    cfg.load("user://settings.cfg")
    cfg.set_value(LEGAL_SECTION, EULA_HASH_KEY, hash)
    cfg.save("user://settings.cfg")
```

### Phase 4 EULA Anti-Patterns (DO NOT)
From Phase 4 Plan 11 decisions:
- **DO NOT** use `add_child_autoqfree` for autoload instantiation in tests → use `.new()` + `.free()`
- **DO NOT** use `auth.uid()` directly in RLS USING clauses → use `(SELECT auth.uid())`
- **DO NOT** use GoTrue email template types for parental consent → use `net/smtp` directly
- **DO NOT** merge EN and NL word lists into one regex → use `_regex_en` and `_regex_nl` separately
- **DO NOT** store raw date-of-birth in Supabase → compute and store `is_under_13` boolean only
- **DO NOT** echo rejected profanity in error messages → always use "Please choose another name."
- **DO NOT** add server-side uniqueness check to the inline username validation debounce → format-only inline, uniqueness only on submit

---

## No Analog Found (New Infrastructure)

| File | Role | Reason |
|---|---|---|
| `docs/EULA.md` | Legal document | No prior legal documents in codebase |
| `docs/PRIVACY.md` | Legal document | No prior legal documents in codebase |
| `docs/store-readiness/*.md + .json` | Store submission docs | No prior store metadata in codebase |
| `assets/profanity/wordlist_en.txt` | Word list data | No prior word list data files |
| `assets/profanity/wordlist_nl.txt` | Word list data | No prior word list data files |
| `assets/profanity/README.md` | Attribution | CC-BY-4.0 attribution requirement; no prior attribution docs |
| `signaling-server/internal/hub/consent.go` | Go HTTP handler | Phase 4 Go code exists but consent lifecycle is entirely new |

---

## Metadata

**Analog search scope:** `src/autoload/`, `src/ui/`, `src/world/`, `src/networking/`, `tests/`, `signaling-server/internal/hub/`, `supabase/migrations/`
**Files scanned:** Phase 4 PATTERNS.md (complete), Phase 4 Plan 11 SUMMARY (decisions), 05-RESEARCH.md patterns 1-5
**Pattern extraction date:** 2026-05-29
**Valid until:** 2026-06-29
