# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# wolf.gd — Wolf: a fast ground-chasing melee hostile (v1.1 art pass).
#
# Uses the base HostileMob seek→attack AI unchanged (no special behaviour); only stats
# + the textured Meshy art mesh (creatures/wolf.glb, via _apply_art_mesh) and a
# transform-only procedural idle differ. Spawns in grassland/snow alongside the others.
class_name Wolf
extends HostileMob

const _DEFAULT_MAX_HP: int = 4
const _DEFAULT_MOVE_SPEED: float = 2.8       # faster than most — wolves run you down
const _DEFAULT_ATTACK_DAMAGE: int = 1
const _DEFAULT_DETECT_RADIUS: float = 14.0


func _ready() -> void:
	# Apply stat defaults before super._ready() sets hp = max_hp.
	max_hp = _DEFAULT_MAX_HP
	move_speed = _DEFAULT_MOVE_SPEED
	attack_damage = _DEFAULT_ATTACK_DAMAGE
	detect_radius = _DEFAULT_DETECT_RADIUS
	super._ready()  # loads the wolf art mesh via _apply_art_mesh() + wires base AI
	state = State.IDLE
	_setup_procedural_anim(ProceduralCreatureAnimator.Motion.LAND)


## Loads assets/meshes/creatures/wolf.glb via HostileMob._apply_art_mesh (textured Meshy).
func _art_kind() -> String:
	return "wolf"


func _art_target_height() -> float:
	return 1.0
