# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# fire_breath_vfx.gd — Tom Yum fire-breath visual effect (D-13 signature flavour gag).
#
# A short-lived GPUParticles3D Node3D that emits a small forward-facing flame puff
# when Tom Yum is consumed. Cosmetic only — no damage hitbox, no light source.
#
# Threat mitigations (T-03-09-DR-04):
#   - NO Area3D, NO CollisionShape3D, NO take_damage call anywhere in this script.
#   - Self-destructs via a 0.3 s one-shot timer + 0.5 s tail-off (particles finish dying).
#   - Builder.eat_food verifies the vfx_on_use string against a hard-coded dispatch table
#     before instantiating this scene (T-03-09-DR-05: injection-safe dispatch).
#
# Performance (STATE.md `voxel-time-budget-ms-6`):
#   - amount=30 particles emitted once (one_shot=true); GPU-driven; no main-thread cost
#     beyond one queue_free after 0.8 s.
#   - No continuous _process; uses a one-shot timer for the lifetime gate.
#
# TODO Phase 3 polish: extract dynamite particle shader for direct reuse per CONTEXT D-13
# ("VFX reuses the dynamite particle shader at a much smaller scale for consistency").
# For v1, we ship a self-contained ProcessMaterial mirroring the dynamite settings at ~10% scale.
#
# References:
#   03-CONTEXT.md D-13 — Tom Yum fire-breath: ~0.3 s, no damage, no light, cosmetic-only
#   src/tools/dynamite_handler.gd — GPUParticles3D pattern reference
#   STATE.md `voxel-time-budget-ms-6` — 6 ms main-thread budget constraint

class_name FireBreathVfx
extends Node3D

# ─── Constants ────────────────────────────────────────────────────────────────

## Total emission duration in seconds (D-13: "~0.3 s flame puff").
const LIFETIME_S: float = 0.3

## Extra tail-off time before queue_free — lets in-flight particles finish.
const TAILOFF_S: float = 0.5

# ─── Node references ──────────────────────────────────────────────────────────

@onready var _particles: GPUParticles3D = $Particles

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Start emitting immediately.
	_particles.emitting = true
	# Schedule the end of emission after LIFETIME_S.
	var stop_timer: SceneTreeTimer = get_tree().create_timer(LIFETIME_S)
	stop_timer.timeout.connect(_on_lifetime_end)


## Stop emitting and schedule queue_free after the tail-off window.
func _on_lifetime_end() -> void:
	_particles.emitting = false
	var free_timer: SceneTreeTimer = get_tree().create_timer(TAILOFF_S)
	free_timer.timeout.connect(queue_free)
