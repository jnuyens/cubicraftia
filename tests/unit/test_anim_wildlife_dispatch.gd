# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_anim_wildlife_dispatch.gd — ANIM-01 / ANIM-02 wiring-level dispatch tests.
#
# 08 gap-closure: the ShaderWobbleAnimator (FISH) and QuadrupedAnimator classes were
# VERIFIED-functional, but wildlife.gd's _FISH_TINTS / _QUADRUPED_SETS dicts were empty,
# so the dispatch branches were dead code (fish + panda fell through to the procedural
# fallback). These tests assert the DISPATCH, not just the class:
#   - const-level (no display): the dicts are populated with the right keys.
#   - in-tree (display-gated, pending() on headless): a live Wildlife resolves _anim to
#     the typed animator (ShaderWobbleAnimator FISH / QuadrupedAnimator).

extends GutTest

const WildlifeScript = preload("res://src/world/wildlife.gd")
const WobbleScript = preload("res://src/builder/shader_wobble_animator.gd")
const QuadScript = preload("res://src/builder/quadruped_animator.gd")


func test_fish_tints_has_all_three_fish_kinds() -> void:
	var tints: Dictionary = WildlifeScript._FISH_TINTS
	assert_true(tints.has("fish_blue"), "_FISH_TINTS maps fish_blue (SC1/ANIM-01)")
	assert_true(tints.has("fish_orange"), "_FISH_TINTS maps fish_orange (SC1/ANIM-01)")
	assert_true(tints.has("fish_yellow"), "_FISH_TINTS maps fish_yellow (SC1/ANIM-01)")


func test_fish_tints_are_distinct_colours() -> void:
	# D-RECON-03: fish_orange / fish_yellow must NOT all render blue — distinct tints.
	var tints: Dictionary = WildlifeScript._FISH_TINTS
	assert_ne(tints["fish_blue"], tints["fish_orange"], "blue and orange tints differ")
	assert_ne(tints["fish_blue"], tints["fish_yellow"], "blue and yellow tints differ")
	assert_ne(tints["fish_orange"], tints["fish_yellow"], "orange and yellow tints differ")


func test_quadruped_sets_has_panda() -> void:
	assert_true(WildlifeScript._QUADRUPED_SETS.has("panda"), "_QUADRUPED_SETS maps panda (SC2/ANIM-02)")


func test_animated_glb_has_giraffe() -> void:
	# Skinned Meshy walk-clip registry: the giraffe is the first entry, pointing at its
	# *_walking.glb so wildlife dispatches it to the skinned-GLB AnimationPlayer path.
	var reg: Dictionary = WildlifeScript._ANIMATED_GLB
	assert_true(reg.has("giraffe"), "_ANIMATED_GLB maps giraffe to a skinned walk .glb")
	assert_true(str(reg.get("giraffe", "")).ends_with("giraffe_walking.glb"),
		"_ANIMATED_GLB giraffe path points at giraffe_walking.glb")


func test_in_tree_fish_resolves_to_shader_wobble_fish() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display/GPU for fish .glb + shader load")
		return
	var w = WildlifeScript.new()
	w.kind = "fish_blue"
	add_child_autofree(w)
	await get_tree().process_frame
	assert_true(w._anim is WobbleScript, "fish_blue resolves _anim to ShaderWobbleAnimator")
	assert_eq(int(w._anim.body_type), int(WobbleScript.BodyType.FISH),
		"fish_blue ShaderWobbleAnimator uses BodyType.FISH")


func test_in_tree_panda_resolves_to_quadruped() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display for panda rig .glb load")
		return
	var w = WildlifeScript.new()
	w.kind = "panda"
	add_child_autofree(w)
	await get_tree().process_frame
	assert_true(w._anim is QuadScript, "panda resolves _anim to QuadrupedAnimator")


func test_in_tree_giraffe_resolves_to_skinned_walk_clip() -> void:
	if DisplayServer.get_name() == "headless":
		pending("requires display/GPU for skinned giraffe .glb + skeleton load")
		return
	var w = WildlifeScript.new()
	w.kind = "giraffe"
	add_child_autofree(w)
	await get_tree().process_frame
	assert_not_null(w._skinned_anim, "giraffe resolves an AnimationPlayer (skinned path)")
	if w._skinned_anim != null:
		assert_ne(w._skinned_walk_name, "", "giraffe exposes a walk clip name")
		assert_true(w._skinned_anim.has_animation(w._skinned_walk_name),
			"giraffe AnimationPlayer carries the resolved walk clip")
