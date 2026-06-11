# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# recipe_book_tab.gd — Recipe book tab for the inventory slide-in Recipes pane.
#
# Implements D-05 progressive reveal (03-CONTEXT.md D-05):
#   A recipe appears in the book when EITHER:
#     (a) the builder has ≥1 of every ingredient in inventory RIGHT NOW, OR
#     (b) the builder has previously crafted it (Inventory.recipes_known[recipe_id] == true).
#   First-craft permanently unlocks the recipe (Inventory.apply_event CRAFT sets recipes_known).
#
# Each row is 56 px tall and contains:
#   - 40×40 result icon (full alpha if revealed; 50% alpha + greyed if locked)
#   - Recipe name label
#   - Ingredient mini-grid (16×16 icons with count)
#   - "Fill grid" button (auto-populates active crafting grid via CRAFT_AUTOFILL)
#
# Auto-fill dispatches Inventory.apply_event({kind: "CRAFT_AUTOFILL", ...}) which validates
# ingredients, removes them from inventory, and writes to the active grid buffer.
#
# Recipe-revealed glow: when a recipe is first revealed, a 600 ms #F5C30D glow stroke
# plays on the corresponding row (UI-SPEC L130). FillGrid flash is 200 ms (UI-SPEC L131).
#
# References:
#   03-CONTEXT.md D-05 — progressive reveal + tap-to-fill
#   03-UI-SPEC.md L75 — recipe-book row spec (56 px, 40×40 result, 16×16 ingredients)
#   03-UI-SPEC.md L130-131 — reveal glow (600 ms) + fill flash (200 ms)
#   03-UI-SPEC.md L195-196 — empty-state copy
#   03-PATTERNS.md L708-738 — brick_palette.gd _refresh_palette_grid analog
#   DOCS.md §4.5 — progressive recipe-book reveal

class_name RecipeBookTab
extends VBoxContainer

# ─── Constants ────────────────────────────────────────────────────────────────

## Row height in pixels (UI-SPEC L75).
const ROW_HEIGHT_PX: int = 56

## Result icon size in pixels (UI-SPEC L75).
const RESULT_ICON_PX: int = 40

## Ingredient icon size in pixels (UI-SPEC L75).
const INGREDIENT_ICON_PX: int = 16

## Alpha for locked (not-yet-revealed) recipes (UI-SPEC L75 "50% alpha").
const COLOR_LOCKED_ALPHA: float = 0.5

## Glow colour for recipe reveal animation (#F5C30D — accent yellow).
const COLOR_REVEAL_GLOW: Color = Color(0.96, 0.76, 0.05, 1.0)

## Auto-fill flash colour (#F5C30D at 0.7α).
const COLOR_FILL_FLASH: Color = Color(0.96, 0.76, 0.05, 0.7)

## Reveal glow duration in seconds (UI-SPEC L130).
const REVEAL_GLOW_DURATION_S: float = 0.6

## Fill flash duration in seconds (UI-SPEC L131).
const FILL_FLASH_DURATION_S: float = 0.2

## Recipe-card art (sliced from art-crafting): a single image showing ingredients → output.
## File name is <recipe_id>.png, except for a few whose card was named differently.
const _RECIPE_CARD_DIR: String = "res://assets/textures/crafting/recipes/"
const _RECIPE_CARD_ALIAS: Dictionary = {
	"recipe_workbench": "recipe_crafting_table",
	"recipe_wooden_plank": "recipe_wood_plank_block",
}

## Displayed size of the recipe card in a row (wide; the card art is ~5:2).
const CARD_WIDTH_PX: int = 148

# ─── State ────────────────────────────────────────────────────────────────────

var _builder_id: String = ""

## Map of recipe_id → row Control for targeted reveal glow.
var _recipe_rows: Dictionary = {}

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Set sizing flags so the tab fills the recipes pane.
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	# Locate the local builder to cache builder_id.
	var builder: Node = null
	if is_inside_tree():
		builder = get_tree().get_first_node_in_group("builder")
	if builder != null and "get_stable_builder_id" in builder:
		_builder_id = builder.call("get_stable_builder_id")

	# Subscribe to Inventory signals for live progressive reveal (D-05).
	if Inventory != null:
		if Inventory.has_signal("inventory_changed") \
				and not Inventory.inventory_changed.is_connected(_on_inventory_changed):
			Inventory.inventory_changed.connect(_on_inventory_changed)
		if Inventory.has_signal("recipe_revealed") \
				and not Inventory.recipe_revealed.is_connected(_on_recipe_revealed):
			Inventory.recipe_revealed.connect(_on_recipe_revealed)

	# Initial render.
	_refresh_book()

# ─── Public API ───────────────────────────────────────────────────────────────

## Refresh the recipe book: re-read revealed state and rebuild all rows.
## Called by InventorySlideIn._refresh_recipes_tab on inventory_changed.
func _refresh_book() -> void:
	# Clear existing rows.
	_recipe_rows.clear()
	for child in get_children():
		child.queue_free()

	# Fetch revealed recipes from Inventory (D-05 source of truth — T-03-07b-UI-01 mitigation).
	var revealed_list: Array = []
	if Inventory != null and Inventory.has_method("get_revealed_recipes"):
		revealed_list = Inventory.get_revealed_recipes(_builder_id)
	var revealed_set: Dictionary = {}
	for recipe_id: String in revealed_list:
		revealed_set[recipe_id] = true

	# Fetch the full recipe registry.
	var registry: Dictionary = {}
	if Inventory != null and "_recipe_registry" in Inventory:
		registry = Inventory._recipe_registry

	if registry.is_empty():
		_show_empty_state()
		return

	var any_visible: bool = false

	for recipe_id: String in registry:
		var recipe: Resource = registry[recipe_id]
		if recipe == null:
			continue

		var is_revealed: bool = revealed_set.has(recipe_id)
		var row: Control = _build_recipe_row(recipe_id, recipe, is_revealed)
		if row != null:
			add_child(row)
			_recipe_rows[recipe_id] = row
			any_visible = true

	if not any_visible:
		_show_empty_state()


## Return the recipe-card Texture2D for a recipe_id, or null if no card art exists.
## Maps recipe_id → <recipe_id>.png (with a small alias table for cards named differently).
func _recipe_card_texture(recipe_id: String) -> Texture2D:
	var base: String = _RECIPE_CARD_ALIAS.get(recipe_id, recipe_id)
	var path: String = _RECIPE_CARD_DIR + base + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## Build a single recipe row Control.
func _build_recipe_row(recipe_id: String, recipe: Resource, revealed: bool) -> Control:
	# Outer HBoxContainer row.
	var row := HBoxContainer.new()
	row.name = "Row_" + recipe_id
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT_PX)
	row.add_theme_constant_override("separation", 8)

	# ── Recipe visual ─────────────────────────────────────────────────────────
	# Prefer the full recipe-card art (ingredients → output in one image). When a card
	# exists it IS the crafting graphic, so the separate ingredient mini-grid below is
	# skipped. Falls back to a 40×40 result-icon slot when no card art is present.
	var card_tex: Texture2D = _recipe_card_texture(recipe_id)
	var result_icon := TextureRect.new()
	result_icon.name = "ResultIcon"
	result_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if card_tex != null:
		result_icon.texture = card_tex
		result_icon.custom_minimum_size = Vector2(CARD_WIDTH_PX, ROW_HEIGHT_PX - 6)
		result_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	else:
		result_icon.custom_minimum_size = Vector2(RESULT_ICON_PX, RESULT_ICON_PX)
		result_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	if not revealed:
		result_icon.modulate = Color(0.5, 0.5, 0.5, COLOR_LOCKED_ALPHA)
	row.add_child(result_icon)

	# ── Recipe name label ─────────────────────────────────────────────────────
	var name_label := Label.new()
	name_label.name = "NameLabel"
	var display_key: String = str(recipe.get("display_name_key") if recipe.get("display_name_key") != null else "recipes." + recipe_id + ".name")
	name_label.text = tr(display_key)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 14)
	if not revealed:
		name_label.modulate = Color(0.7, 0.7, 0.7, 0.6)
	row.add_child(name_label)

	# ── Ingredient mini-grid (only when there is no full card to show) ─────────
	var inputs: Variant = recipe.get("inputs")
	if inputs != null and inputs is Array and card_tex == null:
		var ingredients_container := HBoxContainer.new()
		ingredients_container.name = "Ingredients"
		ingredients_container.add_theme_constant_override("separation", 2)

		# Aggregate ingredient counts for display.
		var ingredient_counts: Dictionary = {}
		for inp: Dictionary in (inputs as Array):
			var did: String = inp.get("def_id", "")
			if not did.is_empty():
				ingredient_counts[did] = ingredient_counts.get(did, 0) + inp.get("count", 1)

		for did: String in ingredient_counts:
			var ingr_box := VBoxContainer.new()
			ingr_box.name = "Ingr_" + did
			ingr_box.add_theme_constant_override("separation", 0)

			var ingr_icon := TextureRect.new()
			ingr_icon.custom_minimum_size = Vector2(INGREDIENT_ICON_PX, INGREDIENT_ICON_PX)
			ingr_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			ingr_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if not revealed:
				ingr_icon.modulate = Color(0.5, 0.5, 0.5, COLOR_LOCKED_ALPHA)
			ingr_box.add_child(ingr_icon)

			var count_lbl := Label.new()
			count_lbl.text = str(ingredient_counts[did])
			count_lbl.add_theme_font_size_override("font_size", 10)
			count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ingr_box.add_child(count_lbl)

			ingredients_container.add_child(ingr_box)

		row.add_child(ingredients_container)

	# ── "Fill grid" button (40×40) ─────────────────────────────────────────────
	var fill_btn := Button.new()
	fill_btn.name = "FillGridBtn"
	fill_btn.text = "→⬛"
	fill_btn.tooltip_text = tr("ui.recipes.fill_grid")
	fill_btn.custom_minimum_size = Vector2(RESULT_ICON_PX, RESULT_ICON_PX)
	fill_btn.disabled = not revealed
	fill_btn.pressed.connect(_on_fill_grid_pressed.bind(recipe_id, fill_btn))
	row.add_child(fill_btn)

	return row


## Show an empty-state message when no recipes are revealed (D-05 + UI-SPEC L195-196).
func _show_empty_state() -> void:
	var title_lbl := Label.new()
	title_lbl.text = tr("ui.recipes.empty.title")
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 16)
	add_child(title_lbl)

	var body_lbl := Label.new()
	body_lbl.text = tr("ui.recipes.empty.body")
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.add_theme_font_size_override("font_size", 14)
	add_child(body_lbl)


# ─── Private: auto-fill dispatch ──────────────────────────────────────────────

## Dispatch CRAFT_AUTOFILL to Inventory; flash the FillGrid button on success.
## target_grid is derived from the slide-in's active mode (inventory → 2×2, workbench → 3×3).
func _on_fill_grid_pressed(recipe_id: String, fill_btn: Button) -> void:
	# Determine target grid from the parent slide-in's mode.
	var target_grid: String = "crafting_2x2"
	var slide_in: Node = null
	if is_inside_tree():
		slide_in = get_tree().get_first_node_in_group("inventory_slide_in")
	if slide_in != null and "_mode" in slide_in:
		var mode: String = str(slide_in._mode)
		if mode == "workbench":
			target_grid = "crafting_3x3"

	if Inventory == null or _builder_id.is_empty():
		return

	var ok: Variant = Inventory.apply_event({
		"kind":        "CRAFT_AUTOFILL",
		"builder_id":  _builder_id,
		"recipe_id":   recipe_id,
		"target_grid": target_grid,
	})

	# Flash the button yellow for 200 ms on success (UI-SPEC L131).
	if ok:
		_flash_fill_button(fill_btn)


## Play a 200 ms #F5C30D flash on a fill button (UI-SPEC L131).
func _flash_fill_button(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var original_modulate: Color = btn.modulate
	btn.modulate = COLOR_FILL_FLASH
	var tw: Tween = create_tween()
	tw.tween_property(btn, "modulate", original_modulate, FILL_FLASH_DURATION_S)


# ─── Signal handlers ──────────────────────────────────────────────────────────

## Refresh book when any inventory mutation fires (live ingredient-presence check).
func _on_inventory_changed(_builder_id_changed: String) -> void:
	_refresh_book()


## Handle recipe_revealed signal: play 600 ms glow on the corresponding row.
func _on_recipe_revealed(builder_id: String, recipe_id: String) -> void:
	if builder_id != _builder_id:
		return  # Not our builder.

	# Rebuild with new revealed state.
	_refresh_book()

	# Apply glow to the newly-revealed row (UI-SPEC L130).
	if _recipe_rows.has(recipe_id):
		var row: Control = _recipe_rows[recipe_id]
		_play_reveal_glow(row)


## Play a 600 ms #F5C30D glow stroke on a row (UI-SPEC L130).
func _play_reveal_glow(row: Control) -> void:
	if row == null or not is_instance_valid(row):
		return
	var original_modulate: Color = row.modulate
	row.modulate = COLOR_REVEAL_GLOW
	var tw: Tween = create_tween()
	tw.tween_property(row, "modulate", original_modulate, REVEAL_GLOW_DURATION_S)
