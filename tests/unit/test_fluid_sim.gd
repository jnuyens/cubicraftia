# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_fluid_sim.gd — Unit tests for the WATER overhaul finite-volume fluid sim.
#
# Exercises the pure level math WITHOUT a live VoxelTerrain (the sim treats unknown
# cells as open air when no tool is wired — see FluidSim._is_solid). This lets us
# assert the core invariants headlessly:
#   - Volume conservation across settling ticks (no source/sink).
#   - Settling terminates (active set empties).
#   - Water falls straight down before spreading (no vertical walls).
#   - Horizontal spread / equalisation toward a flat surface.
#   - The mine hook seeds and floods.
#
# These guard the behaviours the game owner asked for at the algorithm level. The
# voxel-grid rendering + transparency + underwater fog are validated separately
# (terrain.tscn water-model edit + main_scene fog), which a headless run can't mesh.
#
# Anchors:
#   src/world/fluid_sim.gd — FluidSim (class_name)

extends GutTest

const _MAX_TICKS: int = 4000  # generous termination cap; settling should be far quicker.

const _FLOOR_Y: int = 0  # solid terrain at y < _FLOOR_Y in the mock world.


# ── Mock terrain + tool ──────────────────────────────────────────────────────
# A minimal stand-in for VoxelTerrain + VoxelTool so the sim runs against a bounded
# world: everything at y < _FLOOR_Y reads as solid (stone), everything else is air
# (unless the sim itself wrote water). This floors the water so settling terminates.
class _MockTool:
	extends RefCounted
	var channel: int = 0
	var grid: Dictionary = {}  # Vector3i -> voxel id (sim's writes land here)
	func get_voxel(pos: Vector3i) -> int:
		if pos.y < _FLOOR_Y:
			return 4  # STONE — solid
		return int(grid.get(pos, 0))  # AIR unless sim wrote water
	func set_voxel(pos: Vector3i, v: int) -> void:
		grid[pos] = v


class _MockTerrain:
	extends Node
	var tool: RefCounted = null
	func get_voxel_tool() -> RefCounted:
		return tool


func _new_sim() -> FluidSim:
	# Wire a mock terrain that floors the world at y=0 so water settles (instead of
	# falling forever through infinite air) — settling then provably terminates.
	var sim: FluidSim = FluidSim.new()
	var terrain := _MockTerrain.new()
	terrain.tool = _MockTool.new()
	sim.set_terrain(terrain)
	# Keep the mock terrain alive for the sim's lifetime by parenting it to the sim.
	sim.add_child(terrain)
	return sim


## Drive the sim to a fixed point by calling step() until the active set drains or
## the tick cap is hit. Returns the number of ticks taken (for termination asserts).
func _settle(sim: FluidSim) -> int:
	var ticks: int = 0
	while sim.active_count() > 0 and ticks < _MAX_TICKS:
		sim.step()
		ticks += 1
	return ticks


# ─── Construction ──────────────────────────────────────────────────────────────

func test_fluid_sim_constructs() -> void:
	var sim: FluidSim = _new_sim()
	assert_not_null(sim, "FluidSim should construct")
	assert_eq(sim.total_volume(), 0, "fresh sim holds no water")
	assert_eq(sim.active_count(), 0, "fresh sim has no active cells")
	sim.free()


# ─── Volume conservation ────────────────────────────────────────────────────────

func test_add_water_records_volume() -> void:
	var sim: FluidSim = _new_sim()
	sim.add_water(Vector3i(0, 10, 0), FluidSim.LEVEL_MAX)
	assert_eq(sim.total_volume(), FluidSim.LEVEL_MAX,
		"adding one full cell records LEVEL_MAX volume")
	sim.free()


func test_volume_conserved_through_settling() -> void:
	# A stacked column of water above the mock floor (y=0). After settling onto the
	# floor + spreading, TOTAL volume must be unchanged (water moved, not created).
	var sim: FluidSim = _new_sim()
	sim.add_water(Vector3i(0, 5, 0), FluidSim.LEVEL_MAX)
	sim.add_water(Vector3i(0, 6, 0), FluidSim.LEVEL_MAX)
	sim.add_water(Vector3i(0, 7, 0), FluidSim.LEVEL_MAX)
	var before: int = sim.total_volume()
	var ticks: int = _settle(sim)
	var after: int = sim.total_volume()
	assert_eq(after, before, "total water volume is conserved across settling")
	assert_lt(ticks, _MAX_TICKS, "settling terminates (active set drains)")
	sim.free()


# ─── Settling terminates ─────────────────────────────────────────────────────────

func test_settling_terminates_and_empties_active_set() -> void:
	var sim: FluidSim = _new_sim()
	# Build a small uneven blob; it should equalise/fall and the active set empties.
	for x in range(3):
		for z in range(3):
			sim.add_water(Vector3i(x, 8, z), FluidSim.LEVEL_MAX)
	var ticks: int = _settle(sim)
	assert_lt(ticks, _MAX_TICKS, "settling must terminate")
	assert_eq(sim.active_count(), 0, "active set is empty once settled")
	sim.free()


# ─── Gravity: water falls down before spreading (no vertical walls) ──────────────

func test_water_falls_downward() -> void:
	# In open air a full cell should not stay put at its spawn Y — it must move down.
	var sim: FluidSim = _new_sim()
	var start := Vector3i(0, 20, 0)
	sim.add_water(start, FluidSim.LEVEL_MAX)
	# A handful of ticks is enough to see it leave the spawn cell.
	for _i in range(10):
		sim.step()
	assert_false(sim.has_water_at(start),
		"water should fall out of its spawn cell in open air (gravity before spread)")
	sim.free()


# ─── Horizontal spread / equalisation ────────────────────────────────────────────

func test_water_spreads_to_neighbours() -> void:
	# Two stacked full cells over open air: after settling, the water should have
	# spread out (occupy more than the original single column) rather than forming a
	# 2-high vertical wall in one cell.
	var sim: FluidSim = _new_sim()
	sim.add_water(Vector3i(0, 4, 0), FluidSim.LEVEL_MAX)
	sim.add_water(Vector3i(0, 5, 0), FluidSim.LEVEL_MAX)
	_settle(sim)
	# Volume conserved, and the wet footprint is wider than 1 column (it fell + spread).
	assert_eq(sim.total_volume(), FluidSim.LEVEL_MAX * 2, "volume conserved")
	assert_gt(sim.wet_cell_count(), 1, "water spread beyond its single spawn column")
	sim.free()


# ─── Mine hook seeds + floods ────────────────────────────────────────────────────

func test_notify_block_mined_activates_adjacent_water() -> void:
	# Place a tracked water cell, then mine the cell beside it. The mine hook should
	# activate the bordering water so it begins to flow (active set non-empty).
	var sim: FluidSim = _new_sim()
	sim.add_water(Vector3i(0, 5, 0), FluidSim.LEVEL_MAX)
	# Drain the initial activity so we isolate the mine-trigger effect.
	_settle(sim)
	# Re-seed a static body of water that has settled, then mine an adjacent block.
	sim.add_water(Vector3i(0, 5, 0), FluidSim.LEVEL_MAX)
	_settle(sim)
	sim.notify_block_mined(Vector3i(1, 5, 0))
	assert_gt(sim.active_count(), 0,
		"mining a block beside water re-activates the water (it can now flow)")
	sim.free()
