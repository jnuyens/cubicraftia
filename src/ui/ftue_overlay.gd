# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ftue_overlay.gd — First-Time User Experience overlay (Plan 06-06).
#
# 4-step in-world tutorial that guides the player through their first 60 seconds:
#   Step 1: Open the starter chest (trigger: ChestEntity.opened)
#   Step 2: Mine a tree (trigger: Inventory.item_added with def_id == "wood_log")
#   Step 3: Place a wooden plank (trigger: StudGrid.placed with definition.brick_id == "wood_plank")
#   Step 4: Completion — "That's it. The world is yours." (auto-dismiss after 3 s)
#
# Non-blocking: CanvasLayer layer=20. The overlay has mouse_filter=IGNORE on all
# background controls so the player can move, build, and interact freely.
#
# NON-DISMISSABLE: Per DOCS §1.4 — no Close or Dismiss affordance anywhere in
# this scene. The tutorial is the first 60 seconds of play; removing it is not an option.
#
# Persistence:
#   On each step completion: WorldSave.set_world_meta("ftue_step_N_complete", true)
#   On full completion:      WorldSave.set_world_meta("ftue_complete", var_to_bytes(true))
#   On scene reload: main_scene checks ftue_complete → does not instantiate this scene.
#
# Night-hint: if WorldClock transitions to DUSK while step < 4, a parallel non-blocking
# label fades in. This does NOT gate step 4 completion.
#
# Threat mitigations:
#   T-06-FTUE1: No tutorial bypass button — enforced by threat-model grep gate.
#   T-06-FTUE2: _find_nearest_tree() runs via call_deferred (one-shot, result cached).
#
# References:
#   06-06-PLAN.md Task 2
#   06-UI-SPEC.md Surface 5 — FTUE Overlay
#   06-CONTEXT.md Area 3 — FTUE Guided Walkthrough

class_name FtueOverlay
extends CanvasLayer

# ─── Constants ────────────────────────────────────────────────────────────────

## Total number of FTUE steps (DOCS §1.2).
const STEP_COUNT: int = 4

## Duration in seconds the completion message remains visible before fading.
const COMPLETION_DISPLAY_S: float = 3.0

## Duration of the fade-out animation when the overlay dismisses.
const FADE_OUT_DURATION_S: float = 0.5

## Duration of the fade-in for the completion label.
const FADE_IN_DURATION_S: float = 0.5

## Arrow bounce amplitude in pixels (UI-SPEC Animation Token FTUE_ARROW_BOUNCE_PERIOD).
const ARROW_BOUNCE_PX: float = 6.0

## Arrow bounce period in seconds.
const ARROW_BOUNCE_PERIOD_S: float = 0.6

## Radius (in voxel cells) to scan for the nearest tree when entering step 2.
const TREE_SCAN_RADIUS: int = 20

## Accent yellow colour (#F5C30D) — FTUE progress bar fill, arrow tint.
const COLOR_ACCENT: Color = Color(0.961, 0.765, 0.051, 1.0)

## Navy background colour (#1B2C56 at 0.92 alpha) — narration strip background.
const COLOR_NAVY: Color = Color(0.106, 0.173, 0.337, 0.92)

## Brick-white colour (#F1F0EA) — all text.
const COLOR_WHITE: Color = Color(0.945, 0.941, 0.918, 1.0)

## Storyboard panel PNGs mapped to each of the 4 FTUE steps.
## step 1 → builder lands on island (arrival moment)
## step 2 → breaks first block (mining)
## step 3 → places block (place plank)
## step 4 → crafts a tool (completion / progression)
const _STEP_PANELS: Array[String] = [
	"res://assets/textures/ftue/panel_01_builder_lands_on_island.png",
	"res://assets/textures/ftue/panel_02_breaks_first_block.png",
	"res://assets/textures/ftue/panel_04_places_block.png",
	"res://assets/textures/ftue/panel_05_crafts_a_tool.png",
]

# ─── Signals ──────────────────────────────────────────────────────────────────

## Emitted when the FTUE reaches the COMPLETE state (step 4 triggers).
## main_scene may connect to this for optional cleanup, though the overlay
## calls queue_free() itself after the fade-out.
signal ftue_complete

# ─── State ────────────────────────────────────────────────────────────────────

## Current FTUE step (1–4). Set to STEP_COUNT + 1 when COMPLETE.
var _current_step: int = 1

## World-space position of the current target entity (chest, tree trunk, etc.).
var _target_world_pos: Vector3 = Vector3.ZERO

## Whether a valid world-space target is currently tracked.
var _has_target: bool = false

## Whether the night-hint label has been shown this session.
var _night_hint_shown: bool = false

## Tween reference for the arrow bounce animation.
var _arrow_tween: Tween = null

## Base position of the arrow TextureRect (updated when target changes).
var _arrow_base_pos: Vector2 = Vector2.ZERO

# ─── Node references (resolved in _setup_nodes) ──────────────────────────────

var _progress_bar: ProgressBar = null
var _progress_label: Label = null
var _narration_label: Label = null
var _arrow_texture: TextureRect = null
var _narration_container: PanelContainer = null
var _night_hint_label: Label = null
var _root_container: Control = null
var _storyboard_panel: TextureRect = null

## World-space objective beacon (Sprite3D) parented to the starter chest so the
## objective is pinned IN THE WORLD near spawn — visible through terrain at a
## distance — instead of only the screen-edge arrow.
var _chest_beacon: Sprite3D = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 20
	_setup_nodes()
	_connect_ftue_signals()
	_activate_step(1)


func _process(_delta: float) -> void:
	# Update arrow direction each frame if we have a valid target.
	if _has_target:
		_update_arrow_direction()

	# Bob the world-space chest beacon so it reads as an active objective marker.
	if is_instance_valid(_chest_beacon):
		var t: float = float(Time.get_ticks_msec()) * 0.003
		_chest_beacon.position.y = 2.2 + sin(t) * 0.25

	# Night-approaching hint: check WorldClock phase.
	if not _night_hint_shown and _current_step < STEP_COUNT:
		if WorldClock.current_phase == WorldClock.Phase.DUSK:
			_show_night_hint()


# ─── Node setup ──────────────────────────────────────────────────────────────

## Build the overlay node hierarchy programmatically.
## This matches the layout specified in ftue_overlay.tscn.
func _setup_nodes() -> void:
	# Root container — full viewport, mouse-passthrough so the player can interact.
	_root_container = Control.new()
	_root_container.name = "RootContainer"
	_root_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_container)

	# ── Progress strip (top, full-width, 28px height) ──
	var progress_strip: HBoxContainer = HBoxContainer.new()
	progress_strip.name = "ProgressStrip"
	progress_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	progress_strip.custom_minimum_size = Vector2(0.0, 28.0)
	progress_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_container.add_child(progress_strip)

	_progress_bar = ProgressBar.new()
	_progress_bar.name = "ProgressBar"
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = float(STEP_COUNT)
	_progress_bar.step = 1.0
	_progress_bar.value = 1.0
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.custom_minimum_size = Vector2(0.0, 8.0)
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bar.add_theme_color_override("fill_color", COLOR_ACCENT)
	progress_strip.add_child(_progress_bar)

	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.add_theme_color_override("font_color", COLOR_WHITE)
	_progress_label.add_theme_font_size_override("font_size", 14)
	_progress_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pl_margin: MarginContainer = MarginContainer.new()
	pl_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pl_margin.add_theme_constant_override("margin_right", 16)
	pl_margin.add_theme_constant_override("margin_left", 8)
	pl_margin.add_child(_progress_label)
	progress_strip.add_child(pl_margin)

	# ── Narration strip (bottom-third, centred) ──
	_narration_container = PanelContainer.new()
	_narration_container.name = "NarrationContainer"
	_narration_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	# Position 32% from bottom (approximately — fine-tuned via offset).
	_narration_container.anchor_top = 0.68
	_narration_container.anchor_bottom = 0.68
	_narration_container.anchor_left = 0.1
	_narration_container.anchor_right = 0.9
	_narration_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_narration_container.grow_vertical = Control.GROW_DIRECTION_END
	_narration_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_NAVY
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_top = 12.0
	panel_style.content_margin_right = 16.0
	panel_style.content_margin_bottom = 12.0
	_narration_container.add_theme_stylebox_override("panel", panel_style)
	_root_container.add_child(_narration_container)

	# Storyboard panel (above narration row — shows a contextual illustration for each step).
	_storyboard_panel = TextureRect.new()
	_storyboard_panel.name = "StoryboardPanel"
	_storyboard_panel.custom_minimum_size = Vector2(256, 144)
	_storyboard_panel.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_storyboard_panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_storyboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narration_container.add_child(_storyboard_panel)

	var narration_row: HBoxContainer = HBoxContainer.new()
	narration_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	narration_row.add_theme_constant_override("separation", 8)
	_narration_container.add_child(narration_row)

	# Arrow TextureRect (right-pointing; rotated at runtime to point at target).
	_arrow_texture = TextureRect.new()
	_arrow_texture.name = "ArrowTexture"
	_arrow_texture.custom_minimum_size = Vector2(24.0, 24.0)
	_arrow_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_arrow_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_texture.modulate = COLOR_ACCENT
	# Texture is loaded at runtime from assets; graceful no-op if missing.
	var arrow_tex: Texture2D = load("res://assets/textures/icons/ftue_arrow.png") if ResourceLoader.exists("res://assets/textures/icons/ftue_arrow.png") else null
	if arrow_tex != null:
		_arrow_texture.texture = arrow_tex
	_arrow_texture.pivot_offset = Vector2(12.0, 12.0)
	narration_row.add_child(_arrow_texture)

	# Narration label.
	_narration_label = Label.new()
	_narration_label.name = "NarrationLabel"
	_narration_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narration_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_narration_label.add_theme_color_override("font_color", COLOR_WHITE)
	_narration_label.add_theme_font_size_override("font_size", 16)
	_narration_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	narration_row.add_child(_narration_label)

	# Night-hint label (below narration container, initially hidden).
	_night_hint_label = Label.new()
	_night_hint_label.name = "NightHintLabel"
	_night_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_night_hint_label.anchor_top = 0.74
	_night_hint_label.anchor_bottom = 0.74
	_night_hint_label.anchor_left = 0.1
	_night_hint_label.anchor_right = 0.9
	_night_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_night_hint_label.grow_vertical = Control.GROW_DIRECTION_END
	_night_hint_label.add_theme_color_override("font_color", Color(COLOR_WHITE.r, COLOR_WHITE.g, COLOR_WHITE.b, 0.7))
	_night_hint_label.add_theme_font_size_override("font_size", 16)
	_night_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_night_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_night_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night_hint_label.modulate = Color(1.0, 1.0, 1.0, 0.0)  # Hidden initially.
	_root_container.add_child(_night_hint_label)


# ─── Signal wiring ────────────────────────────────────────────────────────────

## Wire FTUE signal connections to game systems.
## Gracefully handles missing nodes (retry deferred for the chest group).
func _connect_ftue_signals() -> void:
	# Inventory.item_added — step 2 (wood_log) and step 3 (wood_plank via stud_grid).
	if is_instance_valid(Inventory) and Inventory.has_signal("item_added"):
		Inventory.item_added.connect(_on_item_added)

	# StudGrid.placed — step 3 (filter by definition.brick_id == "wood_plank").
	var stud_grid: Node = get_tree().get_first_node_in_group("stud_grid")
	if stud_grid != null and stud_grid.has_signal("placed"):
		stud_grid.placed.connect(_on_stud_placed)
	else:
		# StudGrid may not be in a group; fall back to searching by class name.
		stud_grid = _find_stud_grid()
		if stud_grid != null and stud_grid.has_signal("placed"):
			stud_grid.placed.connect(_on_stud_placed)

	# ChestEntity.opened — step 1 completion.
	_connect_chest_signals()


## Maximum number of timed retries for connecting chest signals (WR-04).
const _CHEST_RETRY_MAX: int = 10

## Interval in seconds between chest-signal connection retries (WR-04).
const _CHEST_RETRY_INTERVAL_S: float = 0.5

## How many timed retries have been attempted so far.
var _chest_retry_count: int = 0

## Connect to all ChestEntity nodes currently in the "chest_entity" group.
## If the group is empty (chests not spawned yet), starts a timer-backed retry
## loop capped at _CHEST_RETRY_MAX × _CHEST_RETRY_INTERVAL_S seconds (WR-04).
func _connect_chest_signals() -> void:
	var chests: Array = get_tree().get_nodes_in_group("chest_entity")
	if chests.is_empty():
		if _chest_retry_count < _CHEST_RETRY_MAX:
			_chest_retry_count += 1
			var retry_timer: Timer = Timer.new()
			retry_timer.name = "_chest_retry_timer_%d" % _chest_retry_count
			retry_timer.one_shot = true
			retry_timer.wait_time = _CHEST_RETRY_INTERVAL_S
			retry_timer.timeout.connect(_on_chest_retry_timer.bind(retry_timer))
			add_child(retry_timer)
			retry_timer.start()
		else:
			push_warning("FtueOverlay._connect_chest_signals: no chest_entity found after %d retries — step 1 will not trigger." % _CHEST_RETRY_MAX)
		return
	_chest_retry_count = 0  # Reset counter on success.
	for chest: Node in chests:
		if chest.has_signal("opened") and not chest.opened.is_connected(_on_chest_opened):
			chest.opened.connect(_on_chest_opened)


## Timer callback for chest-signal connection retry (WR-04).
func _on_chest_retry_timer(timer: Timer) -> void:
	if is_instance_valid(timer):
		timer.queue_free()
	_connect_chest_signals()


## Find the StudGrid node by class name traversal if not in a group.
func _find_stud_grid() -> Node:
	return _find_node_of_class(get_tree().get_root(), "StudGrid")


func _find_node_of_class(node: Node, class_name_str: String) -> Node:
	if node.get_class() == class_name_str or (node.get_script() != null and node.get_script().get_class() == class_name_str):
		return node
	# Also check by script class_name via is — use a more robust check.
	if node is StudGrid:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_node_of_class(child, class_name_str)
		if found != null:
			return found
	return null


# ─── Step lifecycle ───────────────────────────────────────────────────────────

## Activate a new FTUE step: update narration text, progress bar, and targeting.
func _activate_step(step: int) -> void:
	_current_step = step
	_progress_bar.value = float(step)
	_progress_label.text = tr("ui.ftue.progress_label").format({"n": step, "total": STEP_COUNT})

	# Load the storyboard panel illustration for this step.
	var panel_idx: int = clamp(step - 1, 0, _STEP_PANELS.size() - 1)
	var panel_path: String = _STEP_PANELS[panel_idx]
	if _storyboard_panel != null:
		if ResourceLoader.exists(panel_path):
			_storyboard_panel.texture = load(panel_path) as Texture2D
		else:
			_storyboard_panel.texture = null

	match step:
		1:
			_narration_label.text = tr("ui.ftue.step_1")
			_narration_label.add_theme_font_size_override("font_size", 16)
			# Point arrow at the starter chest.
			var chest_pos: Vector3 = _find_starter_chest()
			if chest_pos != Vector3.ZERO:
				_target_world_pos = chest_pos
				_has_target = true
			# Activate chest highlight (ftue_highlight uniform on ChestEntity mesh).
			_set_chest_ftue_highlight(true)
			# Pin a world-space beacon above the chest so the objective stays anchored
			# near spawn (visible in the distance) as the player explores.
			_create_chest_beacon()
			_start_arrow_bounce()

		2:
			_narration_label.text = tr("ui.ftue.step_2")
			_narration_label.add_theme_font_size_override("font_size", 16)
			_set_chest_ftue_highlight(false)
			_remove_chest_beacon()
			# Find nearest tree (deferred to avoid frame hitch per T-06-FTUE2).
			_has_target = false
			call_deferred("_find_nearest_tree")
			_start_arrow_bounce()

		3:
			_narration_label.text = tr("ui.ftue.step_3")
			_narration_label.add_theme_font_size_override("font_size", 16)
			_has_target = false
			_arrow_texture.visible = false
			# Highlight the wood_plank slot in the brick palette.
			_set_palette_highlight("wood_plank", true)

		4:
			# Step 4 == COMPLETE.
			_has_target = false
			_arrow_texture.visible = false
			_set_palette_highlight("wood_plank", false)
			_show_completion()


## Advance the step counter, emit telemetry, and call _activate_step or _show_completion.
func _advance_step() -> void:
	var completed_step: int = _current_step
	_current_step += 1

	# Telemetry for the completed step.
	match completed_step:
		1:
			OnboardingTelemetry.log(OnboardingTelemetry.FTUE_STEP_1_COMPLETE)
			WorldSave.set_world_meta("ftue_step_1_complete", true)
		2:
			OnboardingTelemetry.log(OnboardingTelemetry.FTUE_STEP_2_COMPLETE)
			WorldSave.set_world_meta("ftue_step_2_complete", true)
		3:
			OnboardingTelemetry.log(OnboardingTelemetry.FTUE_STEP_3_COMPLETE)
			WorldSave.set_world_meta("ftue_step_3_complete", true)

	if _current_step > STEP_COUNT:
		_show_completion()
	else:
		_activate_step(_current_step)


# ─── Signal handlers ──────────────────────────────────────────────────────────

## FTUE step 1: chest opened.
func _on_chest_opened() -> void:
	if _current_step == 1:
		_advance_step()


## FTUE step 2: first wood_log item added to inventory.
func _on_item_added(_builder_id: String, def_id: String, _count: int) -> void:
	if _current_step == 2 and def_id == "wood_log":
		_advance_step()


## FTUE step 3: first wood_plank placed in the stud grid.
## CRITICAL: filters by definition.brick_id (BrickDefinition field), NOT a String def_id param.
func _on_stud_placed(_anchor_cell: Vector3i, definition: BrickDefinition, _colour_index: int, _rotation: int) -> void:
	if _current_step == 3 and definition != null and definition.brick_id == "wood_plank":
		_advance_step()


# ─── Completion ───────────────────────────────────────────────────────────────

## Show the step 4 completion message, persist ftue_complete, then dismiss.
func _show_completion() -> void:
	_current_step = STEP_COUNT + 1  # Mark complete.
	_has_target = false
	_arrow_texture.visible = false

	# Update narration to completion message with Heading font size.
	_narration_label.text = tr("ui.ftue.complete")
	_narration_label.add_theme_font_size_override("font_size", 20)
	_narration_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	# Progress bar shows full.
	_progress_bar.value = float(STEP_COUNT)
	_progress_label.text = tr("ui.ftue.progress_label").format({"n": STEP_COUNT, "total": STEP_COUNT})

	# Fade in the completion label.
	var fade_in_tween: Tween = create_tween()
	fade_in_tween.tween_property(_narration_label, "modulate:a", 1.0, FADE_IN_DURATION_S)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Telemetry + persistence.
	OnboardingTelemetry.log(OnboardingTelemetry.FTUE_COMPLETE)
	WorldSave.set_world_meta("ftue_complete", var_to_bytes(true))
	ftue_complete.emit()

	# Timer: after COMPLETION_DISPLAY_S, fade out and queue_free.
	var dismiss_timer: Timer = Timer.new()
	dismiss_timer.one_shot = true
	dismiss_timer.wait_time = COMPLETION_DISPLAY_S
	dismiss_timer.timeout.connect(_dismiss_overlay)
	add_child(dismiss_timer)
	dismiss_timer.start()


## Fade out the entire overlay and free it.
func _dismiss_overlay() -> void:
	_remove_chest_beacon()
	var fade_out_tween: Tween = create_tween()
	fade_out_tween.tween_property(_root_container, "modulate:a", 0.0, FADE_OUT_DURATION_S)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade_out_tween.tween_callback(queue_free)


# ─── Targeting ────────────────────────────────────────────────────────────────

## Update the arrow direction and position based on the current 3D target.
## Arrow rotates to point at the target; clamps to screen edge when off-screen.
## Called every frame in _process when _has_target is true.
func _update_arrow_direction() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	if not camera.is_position_in_frustum(_target_world_pos):
		# Target is off-screen: clamp arrow to screen edge and rotate to point.
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		var screen_centre: Vector2 = vp_size * 0.5
		var projected: Vector2 = camera.unproject_position(_target_world_pos)
		# Behind-camera guard: unproject_position() mirrors points that are BEHIND
		# the camera, which makes the edge-arrow point the wrong way once you walk
		# past the chest. Reflect the projected point through screen centre so the
		# direction stays correct.
		if camera.is_position_behind(_target_world_pos):
			projected = screen_centre + (screen_centre - projected)
		var dir: Vector2 = (projected - screen_centre).normalized()
		var margin: float = 48.0
		var clamped: Vector2 = _clamp_to_screen_edge(projected, vp_size, margin)
		_arrow_texture.visible = true
		_arrow_texture.global_position = clamped - Vector2(12.0, 12.0)
		# Rotate arrow to face the direction of the off-screen target.
		_arrow_texture.rotation = atan2(dir.y, dir.x)
	else:
		# Target is on-screen: hide the edge arrow (player can see the target directly).
		_arrow_texture.visible = false


## Clamp a point to the screen boundary with a margin.
func _clamp_to_screen_edge(point: Vector2, vp_size: Vector2, margin: float) -> Vector2:
	return Vector2(
		clampf(point.x, margin, vp_size.x - margin),
		clampf(point.y, margin, vp_size.y - margin)
	)


## Start the looping bounce tween on the arrow TextureRect.
func _start_arrow_bounce() -> void:
	if _arrow_tween != null and _arrow_tween.is_running():
		_arrow_tween.kill()
	_arrow_base_pos = _arrow_texture.position
	_arrow_tween = create_tween()
	_arrow_tween.set_loops()
	_arrow_tween.tween_property(_arrow_texture, "position:x",
			_arrow_base_pos.x + ARROW_BOUNCE_PX, ARROW_BOUNCE_PERIOD_S * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_arrow_tween.tween_property(_arrow_texture, "position:x",
			_arrow_base_pos.x - ARROW_BOUNCE_PX, ARROW_BOUNCE_PERIOD_S * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ─── Entity finders ───────────────────────────────────────────────────────────

## Find the world-space position of the starter chest (closest to Vector3.ZERO).
## Returns Vector3.ZERO if no chest entities are in the scene.
func _find_starter_chest() -> Vector3:
	var chests: Array = get_tree().get_nodes_in_group("chest_entity")
	if chests.is_empty():
		return Vector3.ZERO
	var best_pos: Vector3 = Vector3.ZERO
	var best_dist: float = INF
	for chest: Node in chests:
		if chest is Node3D:
			var dist: float = (chest as Node3D).global_position.distance_to(Vector3.ZERO)
			if dist < best_dist:
				best_dist = dist
				best_pos = (chest as Node3D).global_position
	return best_pos


## Return the starter-chest Node3D nearest world origin (for parenting the beacon).
func _find_starter_chest_node() -> Node3D:
	var chests: Array = get_tree().get_nodes_in_group("chest_entity")
	var best: Node3D = null
	var best_dist: float = INF
	for chest: Node in chests:
		if chest is Node3D:
			var dist: float = (chest as Node3D).global_position.distance_to(Vector3.ZERO)
			if dist < best_dist:
				best_dist = dist
				best = chest as Node3D
	return best


## Create a world-space billboard beacon above the starter chest. Visible through
## terrain (no_depth_test) at a constant screen size, tinted accent yellow, so the
## objective stays pinned in the world near spawn while the player explores.
func _create_chest_beacon() -> void:
	_remove_chest_beacon()
	var chest: Node3D = _find_starter_chest_node()
	if chest == null:
		return
	var beacon := Sprite3D.new()
	beacon.name = "FtueChestBeacon"
	var tex_path := "res://assets/textures/icons/map/marker_waypoint.png"
	if ResourceLoader.exists(tex_path):
		beacon.texture = load(tex_path) as Texture2D
	beacon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Depth-tested + perspective-scaled + small, so it does NOT fill/block the screen
	# at spawn — it reads as a small marker floating above the chest and shrinks with
	# distance / is occluded by terrain.
	beacon.no_depth_test = false
	beacon.fixed_size = false
	beacon.pixel_size = 0.004  # 256px art -> ~1 m marker
	beacon.modulate = COLOR_ACCENT
	beacon.position = Vector3(0.0, 3.2, 0.0)
	chest.add_child(beacon)
	_chest_beacon = beacon


## Remove the world-space chest beacon if present.
func _remove_chest_beacon() -> void:
	if is_instance_valid(_chest_beacon):
		_chest_beacon.queue_free()
	_chest_beacon = null


## Scan a radius around the world spawn for a wood_log voxel.
## Called via call_deferred at step 2 start (T-06-FTUE2 mitigation: one-shot, cached).
## Result is stored in _target_world_pos / _has_target.
func _find_nearest_tree() -> void:
	# Attempt to find a VoxelTool via the terrain node in the "terrain" group.
	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	if terrain == null:
		# Fall back: use world_spawn from WorldSave if available.
		var spawn_raw: Variant = WorldSave.get_world_meta("world_spawn")
		if spawn_raw is PackedByteArray:
			var spawn_variant: Variant = bytes_to_var(spawn_raw as PackedByteArray)
			if spawn_variant is Vector3:
				_target_world_pos = spawn_variant as Vector3
				_has_target = true
				return
		return

	# Try to get a VoxelTool from the terrain node (godot_voxel API).
	if not terrain.has_method("get_voxel_tool"):
		return

	var voxel_tool = terrain.get_voxel_tool()
	if voxel_tool == null:
		return

	# Scan a TREE_SCAN_RADIUS × TREE_SCAN_RADIUS × TREE_SCAN_RADIUS box around spawn.
	var spawn_cell: Vector3i = Vector3i(0, 64, 0)  # Approximate spawn elevation.
	for dx: int in range(-TREE_SCAN_RADIUS, TREE_SCAN_RADIUS + 1):
		for dy: int in range(-4, TREE_SCAN_RADIUS + 1):
			for dz: int in range(-TREE_SCAN_RADIUS, TREE_SCAN_RADIUS + 1):
				var cell: Vector3i = spawn_cell + Vector3i(dx, dy, dz)
				var voxel_id: int = voxel_tool.get_voxel(cell)
				# Check if this voxel is a wood_log (voxel_id > 0 is a solid block;
				# the exact ID depends on the terrain generator config — we use
				# BrickRegistry to map brick_id to channel if available).
				if voxel_id > 0:
					var def: BrickDefinition = BrickRegistry.get_definition_by_voxel_id(voxel_id) if BrickRegistry.has_method("get_definition_by_voxel_id") else null
					if def != null and def.brick_id == "wood_log":
						_target_world_pos = Vector3(float(cell.x), float(cell.y), float(cell.z))
						_has_target = true
						return
	# No tree found in range — target stays unset; step 2 still progresses on item pickup.


# ─── Highlights ───────────────────────────────────────────────────────────────

## Set or clear the ftue_highlight uniform on all ChestEntity meshes.
func _set_chest_ftue_highlight(enabled: bool) -> void:
	var chests: Array = get_tree().get_nodes_in_group("chest_entity")
	for chest: Node in chests:
		# ChestEntity stores its mesh as a child node; find the first MeshInstance3D.
		var mesh_instance: MeshInstance3D = _find_mesh_instance(chest)
		if mesh_instance == null:
			continue
		var mat: Material = mesh_instance.get_active_material(0)
		if mat == null:
			continue
		if mat.has_method("set_shader_parameter"):
			mat.set_shader_parameter("ftue_highlight", enabled)


## Traverse child nodes to find the first MeshInstance3D.
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Set or clear the FTUE highlight on the BrickPalette for the given def_id.
func _set_palette_highlight(def_id: String, enabled: bool) -> void:
	# Find all BrickPaletteUI nodes (sidebar and/or bottomsheet).
	var palette_nodes: Array = get_tree().get_nodes_in_group("brick_palette")
	if palette_nodes.is_empty():
		# Try scene-tree search if group is not set.
		for palette in _find_all_palette_nodes(get_tree().get_root()):
			if palette.has_method("_set_ftue_highlight"):
				palette._set_ftue_highlight(def_id, enabled)
		return
	for palette: Node in palette_nodes:
		if palette.has_method("_set_ftue_highlight"):
			palette._set_ftue_highlight(def_id, enabled)


## Traverse the scene tree to find BrickPaletteUI instances.
func _find_all_palette_nodes(node: Node) -> Array:
	var result: Array = []
	if node is BrickPaletteUI:
		result.append(node)
	for child: Node in node.get_children():
		result.append_array(_find_all_palette_nodes(child))
	return result


# ─── Night hint ───────────────────────────────────────────────────────────────

## Show the non-blocking "Time to sleep. Walk to the bed." hint.
## This is a parallel overlay; it does NOT gate step 4 completion.
func _show_night_hint() -> void:
	_night_hint_shown = true
	_night_hint_label.text = tr("ui.ftue.night_hint")
	var fade_in: Tween = create_tween()
	fade_in.tween_property(_night_hint_label, "modulate:a", 1.0, FADE_IN_DURATION_S)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
