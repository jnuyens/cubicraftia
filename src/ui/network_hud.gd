# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# network_hud.gd — Network status HUD (Surface 10, top-right corner).
#
# Shows per-peer RTT signal strength icon (1/2/3 bars) and optional "Relay"
# badge when the connection uses TURN relay. Updates at 1 Hz via Timer (never
# via _process) to avoid frame-budget impact.
#
# RTT buckets per UI-SPEC Surface 10:
#   <50 ms   → 3-bar icon (green)
#   50-150 ms → 2-bar icon (amber)
#   >150 ms  → 1-bar icon (red)
#
# Relay badge: shown when the peer ICE selected-candidate is TURN type (amber
# #E8890C per CONTEXT-locked semantic colour). Call show_relay_badge(peer_id, true).
#
# References:
#   04-UI-SPEC.md Surface 10 — network status HUD
#   04-08-PLAN.md Task 2 — HUD behaviour spec
#   04-PATTERNS.md lines 641-663 — Timer pattern + icon cache

class_name NetworkHud
extends VBoxContainer

# ─── Constants ────────────────────────────────────────────────────────────────

## RTT threshold for 3-bar (best) icon.
const RTT_EXCELLENT_MS: float = 50.0

## RTT threshold for 2-bar (ok) icon.
const RTT_OK_MS: float = 150.0

## Colors per CONTEXT-locked semantic palette.
const COLOR_GOOD: Color    = Color(0.31, 0.87, 0.22, 1.0)   # green
const COLOR_AMBER: Color   = Color(0.91, 0.54, 0.05, 1.0)   # relay amber #E8890C
const COLOR_BAD: Color     = Color(0.84, 0.22, 0.16, 1.0)   # red

## Signal icon texture asset paths.
const ICON_SIGNAL_1: String = "res://assets/textures/icons/icon_signal_1.png"
const ICON_SIGNAL_2: String = "res://assets/textures/icons/icon_signal_2.png"
const ICON_SIGNAL_3: String = "res://assets/textures/icons/icon_signal_3.png"

## Max username chars in HUD per UI-SPEC (10 chars).
const HUD_USERNAME_MAX: int = 10

# ─── State ────────────────────────────────────────────────────────────────────

## Cached signal icon textures: { 1 → Texture2D, 2 → Texture2D, 3 → Texture2D }
var _signal_textures: Dictionary = {}

## Per-peer row nodes: { peer_id (int) → HBoxContainer }
var _peer_rows: Dictionary = {}

## 1 Hz update timer.
var _update_timer: Timer = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Hidden until a session is active.
	visible = false

	_cache_signal_icons()

	# 1 Hz timer for RTT refresh (not _process — avoids frame budget impact).
	_update_timer = Timer.new()
	_update_timer.one_shot = false
	_update_timer.wait_time = 1.0
	_update_timer.timeout.connect(_refresh_rtt_indicators)
	add_child(_update_timer)
	_update_timer.start()

	# Wire NetworkManager signals.
	if is_instance_valid(NetworkManager):
		NetworkManager.peer_connected.connect(_on_peer_connected)
		NetworkManager.peer_disconnected.connect(_on_peer_disconnected)
		NetworkManager.session_state_changed.connect(_on_session_state_changed)
		NetworkManager.peer_laggy.connect(_on_peer_laggy)


# ─── Signal handlers ──────────────────────────────────────────────────────────

func _on_session_state_changed(state: String) -> void:
	var active: bool = state in ["CONNECTED_AS_HOST", "CONNECTED_AS_PEER",
		"FAILOVER_DETECTING", "FAILOVER_ELECTED", "FAILOVER_PROMOTING",
		"FAILOVER_COMPLETE", "FAILOVER_WAITING", "RECONNECTING"]
	visible = active and not _peer_rows.is_empty()
	if not active:
		# Clear all peer rows on disconnect.
		for peer_id: int in _peer_rows.keys():
			if is_instance_valid(_peer_rows[peer_id]):
				_peer_rows[peer_id].queue_free()
		_peer_rows.clear()


func _on_peer_connected(peer_id: int) -> void:
	if not _peer_rows.has(peer_id):
		_build_peer_row(peer_id)
	if not _peer_rows.is_empty():
		visible = true


func _on_peer_disconnected(peer_id: int) -> void:
	if _peer_rows.has(peer_id):
		if is_instance_valid(_peer_rows[peer_id]):
			_peer_rows[peer_id].queue_free()
		_peer_rows.erase(peer_id)
	if _peer_rows.is_empty():
		visible = false


func _on_peer_laggy(peer_id: int, is_laggy: bool) -> void:
	if not _peer_rows.has(peer_id):
		return
	var row: HBoxContainer = _peer_rows[peer_id] as HBoxContainer
	var icon: TextureRect = row.get_node_or_null("SignalIcon") as TextureRect
	if icon != null:
		icon.modulate = COLOR_AMBER if is_laggy else Color.WHITE


# ─── Row management ───────────────────────────────────────────────────────────

## Build a per-peer HUD row programmatically and add it to self.
func _build_peer_row(peer_id: int) -> void:
	var row := HBoxContainer.new()
	row.name = "PeerRow_%d" % peer_id
	row.custom_minimum_size = Vector2(0, 24)
	row.add_theme_constant_override("separation", 6)

	# Signal icon (16×16 TextureRect).
	var icon := TextureRect.new()
	icon.name = "SignalIcon"
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Default to lowest icon until first RTT refresh.
	icon.texture = _signal_textures.get(1)
	row.add_child(icon)

	# Username label.
	var username_label := Label.new()
	username_label.name = "UsernameLabel"
	username_label.add_theme_font_size_override("font_size", 14)
	username_label.add_theme_color_override("font_color", Color.WHITE)
	username_label.text = _get_peer_username(peer_id)
	row.add_child(username_label)

	# Relay badge (hidden by default).
	var relay_badge := Label.new()
	relay_badge.name = "RelayBadge"
	relay_badge.add_theme_font_size_override("font_size", 12)
	relay_badge.add_theme_color_override("font_color", COLOR_AMBER)
	relay_badge.text = tr("ui.netstatus.relay_badge")
	relay_badge.visible = false
	row.add_child(relay_badge)

	add_child(row)
	_peer_rows[peer_id] = row


## Get a display username for a peer (max HUD_USERNAME_MAX chars).
func _get_peer_username(peer_id: int) -> String:
	if is_instance_valid(SessionRegistry):
		var peers: Dictionary = SessionRegistry.get_peer_list()
		if peers.has(peer_id):
			var info: Dictionary = peers[peer_id] as Dictionary
			var uname: String = info.get("username", "")
			if not uname.is_empty():
				return uname.left(HUD_USERNAME_MAX)
	return ("P%d" % peer_id).left(HUD_USERNAME_MAX)


# ─── RTT refresh (1 Hz) ───────────────────────────────────────────────────────

func _refresh_rtt_indicators() -> void:
	for peer_id: int in _peer_rows:
		var row: HBoxContainer = _peer_rows[peer_id] as HBoxContainer
		if not is_instance_valid(row):
			continue
		var rtt_ms: float = 0.0
		if is_instance_valid(SessionRegistry) and SessionRegistry.has_method("get_peer_rtt"):
			rtt_ms = SessionRegistry.get_peer_rtt(peer_id)
		var icon: TextureRect = row.get_node_or_null("SignalIcon") as TextureRect
		if icon != null:
			icon.texture = _get_signal_icon(rtt_ms)
			# Tint icon by quality.
			if icon.modulate != COLOR_AMBER:  # Don't override laggy amber.
				icon.modulate = _rtt_color(rtt_ms)


## Get the signal icon texture for a given RTT.
func _get_signal_icon(rtt_ms: float) -> Texture2D:
	if rtt_ms < RTT_EXCELLENT_MS:
		return _signal_textures.get(3)
	elif rtt_ms < RTT_OK_MS:
		return _signal_textures.get(2)
	else:
		return _signal_textures.get(1)


## Get the colour for an RTT value.
func _rtt_color(rtt_ms: float) -> Color:
	if rtt_ms < RTT_EXCELLENT_MS:
		return COLOR_GOOD
	elif rtt_ms < RTT_OK_MS:
		return COLOR_AMBER
	else:
		return COLOR_BAD


# ─── Icon cache ───────────────────────────────────────────────────────────────

## Load signal icon textures once in _ready; store in _signal_textures dict.
func _cache_signal_icons() -> void:
	var paths: Dictionary = {1: ICON_SIGNAL_1, 2: ICON_SIGNAL_2, 3: ICON_SIGNAL_3}
	for n: int in paths:
		var path: String = paths[n]
		if ResourceLoader.exists(path, "Texture2D"):
			_signal_textures[n] = load(path)
		else:
			# Graceful fallback: null (icon will be invisible until texture authored).
			_signal_textures[n] = null


# ─── Public API ───────────────────────────────────────────────────────────────

## Show or hide the Relay badge for a peer row.
## Called by NetworkManager when ICE selected candidate type is "relay" (TURN).
## @param peer_id  The peer whose relay badge to toggle.
## @param show     True to show badge, false to hide.
func show_relay_badge(peer_id: int, show: bool) -> void:
	if not _peer_rows.has(peer_id):
		return
	var row: HBoxContainer = _peer_rows[peer_id] as HBoxContainer
	var badge: Label = row.get_node_or_null("RelayBadge") as Label
	if badge != null:
		badge.visible = show
