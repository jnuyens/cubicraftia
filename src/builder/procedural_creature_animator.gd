# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# procedural_creature_animator.gd — Transform-only fallback animator (Phase 8).
#
# Single-mesh TripoSR creatures have no rigid-piece rig and no wobble-shader body,
# so they get a cheap parametric idle: a gentle vertical bob (land/air) plus a
# small side-to-side sway (rotation.z). All motion is computed from a phase
# accumulator — no keyframes, no per-vertex work — so it is mobile-cheap and can
# be frozen by simply skipping update() (the last pose holds).
#
# CRITICAL pitfall (see wildlife.gd::_normalise_creature_mesh): the art mesh's
# -90°X upright + scale + recentre is baked onto the CHILD MeshInstance3D and
# relies on the mesh-root staying at rotation==ZERO / scale==ONE. Therefore this
# helper NEVER writes the mesh-root's rotation.x / rotation.y / scale. It only
# writes:
#   LAND : position.y (bob) + rotation.z (sway)
#   AIR  : rotation.z only  (position is driven by Wildlife._process_air)
#   WATER: rotation.z only  (position is driven by Wildlife._process_water)
#
# This is a stateless helper, not a Node — the owning entity calls update()
# each frame against the mesh-root it already owns. Keeping it a static-style
# helper avoids adding a second _process to every creature.

class_name ProceduralCreatureAnimator
extends RefCounted

const BOB_SPEED: float = 1.4
const BOB_AMPLITUDE_M: float = 0.04
const SWAY_SPEED: float = 1.1
const SWAY_AMPLITUDE_RAD: float = 0.05  # ~2.9°

enum Motion { LAND, AIR, WATER }

var _t: float = 0.0
var _phase_offset: float = 0.0
var motion: Motion = Motion.LAND

func _init(motion_kind: Motion = Motion.LAND) -> void:
	motion = motion_kind
	_phase_offset = randf() * TAU  # de-sync herds


## Advance the idle animation by `delta` seconds and write the pose onto
## `mesh_root`. `walking` lets land animals damp their sway slightly while
## striding (the body's look_at already conveys heading). No-op if null.
func update(mesh_root: Node3D, delta: float, walking: bool = false, base_y: float = 0.0) -> void:
	if mesh_root == null:
		return
	_t += delta
	var phase: float = _t * BOB_SPEED + _phase_offset
	var sway_phase: float = _t * SWAY_SPEED + _phase_offset
	var sway: float = sin(sway_phase) * SWAY_AMPLITUDE_RAD
	match motion:
		Motion.LAND:
			# Bob only while idling; while walking the gait reads from translation.
			# base_y is the ground baseline (feet-on-floor offset for clean models that
			# centre via mesh-root translation); 0 for art meshes that bake it on the child.
			var bob: float = 0.0 if walking else sin(phase) * BOB_AMPLITUDE_M
			mesh_root.position.y = base_y + bob
			mesh_root.rotation.z = sway * (0.4 if walking else 1.0)
		Motion.AIR, Motion.WATER:
			# Position is owned by Wildlife._process_air / _process_water — only rock.
			mesh_root.rotation.z = sway
