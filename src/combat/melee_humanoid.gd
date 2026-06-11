# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# melee_humanoid.gd — Generic humanoid melee hostile (art-figures sheet 3: zombie, skeleton,
# goblin, orc). One script, one scene per kind: each .tscn sets `kind_id` (and optional stat
# overrides) so we don't duplicate near-identical mob classes.
#
# Loads its mesh from assets/meshes/creatures/<kind_id>.glb via HostileMob._apply_art_mesh
# (the textured Meshy figures take the "clean upright model" path — scale + ground, no flip).
#
# References: wolf.gd (minimal HostileMob subclass analog), hostile_mob.gd (base AI).

class_name MeleeHumanoid
extends HostileMob

## Creature mesh kind — file name (no .glb) under assets/meshes/creatures/. Set per .tscn.
@export var kind_id: String = "zombie"
## World height (m) the figure is scaled to.
@export var target_height: float = 1.8

## Stat defaults (overridable per .tscn via the exported HostileMob vars).
@export var default_max_hp: int = 4
@export var default_move_speed: float = 2.2
@export var default_attack_damage: int = 2
@export var default_detect_radius: float = 11.0


func _ready() -> void:
	# Apply stat defaults before super._ready() sets hp = max_hp.
	max_hp = default_max_hp
	move_speed = default_move_speed
	attack_damage = default_attack_damage
	detect_radius = default_detect_radius
	super._ready()  # loads the art mesh via _apply_art_mesh() + wires base AI
	state = State.IDLE
	_setup_procedural_anim(ProceduralCreatureAnimator.Motion.LAND)


func _art_kind() -> String:
	return kind_id


func _art_target_height() -> float:
	return target_height
