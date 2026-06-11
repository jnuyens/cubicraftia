# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# world_save.gd — WorldSave autoload: dirty-chunk tracking + checkpoint over world.meta.sqlite.
#
# Phase 5 (Plan 05-10): Added create_world() wrapper that validates the world name via
#   ProfanityFilter.filter_reject() before delegating to open_world(). Returns false if the
#   name is rejected so callers can show "Choose another name." without exposing the rejected
#   input (T-05-P-bypass; ProfanityFilter.filter_reject() contract: callers must NOT echo).
#
# Registered as autoload "WorldSave" in project.godot (after ThermalProbe/AndroidThermal;
# before WorldClock per the Plan 02-05 load-order contract).
#
# Two-file save design (RESEARCH.md §"Pitfall 5" — avoids VoxelStreamSQLite schema collision):
#   world.terrain.sqlite — managed by VoxelStreamSQLite (godot_voxel, Phase 2 later plan)
#   world.meta.sqlite    — managed by this autoload via godot-sqlite addon
#
# world.meta.sqlite schema (schema_version 3 — extended in Phase 4 Plan 04-03):
#   CREATE TABLE world_meta(key TEXT PRIMARY KEY, value BLOB)
#     Rows: schema_version, world_seed, mode, clock_state, weather_state, rain_dance_quota
#   CREATE TABLE stud_grid_chunks(chunk_x INT, chunk_y INT, chunk_z INT, blob BLOB,
#                                  PRIMARY KEY (chunk_x, chunk_y, chunk_z))
#   CREATE TABLE structures_seen(template_id TEXT, anchor_x INT, anchor_y INT, anchor_z INT,
#                                 PRIMARY KEY (template_id, anchor_x, anchor_y, anchor_z))
#   CREATE TABLE builders(id TEXT PRIMARY KEY, blob BLOB)
#   --- v2 tables (Phase 3 Plan 03-01) ---
#   CREATE TABLE inventories(builder_id TEXT PRIMARY KEY, blob BLOB)
#   CREATE TABLE chests(chunk_x INTEGER, chunk_y INTEGER, chunk_z INTEGER,
#                        type TEXT, locked INTEGER, contents_blob BLOB,
#                        double_chest_partner TEXT, PRIMARY KEY (chunk_x, chunk_y, chunk_z))
#   CREATE TABLE dropped_items(entity_id TEXT PRIMARY KEY, kind TEXT,
#                               pos_x REAL, pos_y REAL, pos_z REAL,
#                               contents_blob BLOB, spawn_tick REAL)
#   CREATE TABLE recipes_known(builder_id TEXT PRIMARY KEY, blob BLOB)
#   --- v3 tables (Phase 4 Plan 04-03) ---
#   CREATE TABLE snapshots(snapshot_id TEXT PRIMARY KEY, created_at REAL NOT NULL,
#                           chunk_blob BLOB, inventory_blob BLOB)
#
# Schema migration: _migrate_schema() runs after _create_schema() in open_world().
#   Reads schema_version, dispatches _migrate_1_to_2() if version < 2, _migrate_2_to_3()
#   if version < 3, then bumps to 3.
#   Migration is wrapped in BEGIN/COMMIT/ROLLBACK per T-03-01-MIG-01 mitigation.
#
# Checkpoint sequence (T-03-01 + T-03-02 mitigations):
#   1. For each dirty chunk: serialise BrickInstance list → ChunkCodec.encode_chunk_delta → UPSERT
#   2. db.close_db() (flushes godot-sqlite write buffers — Pitfall 6 flush-before-rename)
#   3. WorldSaveIo.atomic_write_sqlite(meta_path) → .tmp → flush → rename → .atomic
#   4. WorldSaveIo.rotate_backups(meta_path, 3) → bak.1 ← canonical; bak.2 ← bak.1 ...
#   5. db.open_db() (reopen for subsequent reads/writes)
#   6. Clear _dirty_chunks
#
# TECH-4 mitigation: only modified chunks are persisted; procedurally-regenerable chunks
# are not saved here (they are reproduced from the world_seed by VoxelStreamSQLite).
#
# API note: get_world_meta / set_world_meta are used instead of get_meta / set_meta to
# avoid collision with Node.get_meta() / Object.set_meta() built-in methods, which would
# cause a GDScript parse error (method override of built-in is treated as warning-as-error).
#
# References:
#   RESEARCH.md §"Architecture Patterns" lines 296-330 (two-SQLite-file layout)
#   RESEARCH.md §"Pitfall 5" (VoxelStreamSQLite schema collision prevention)
#   RESEARCH.md §"Pitfall 6" (Android/iOS flush-before-rename requirement)
#   02-PATTERNS.md §"src/autoload/world_save.gd" (lifecycle analog: thermal_probe.gd)
#   02-PATTERNS.md Pattern S-4 (autoload registration)
#   02-PATTERNS.md Pattern S-5 (signal-driven StudGrid subscription)

extends Node

const _ProfanityFilter = preload("res://src/networking/profanity_filter.gd")

# ─── Constants ───────────────────────────────────────────────────────────────

## Chunk size in stud-grid cells (same axis on all three dimensions).
## Used to convert a brick's anchor_cell to a chunk coordinate.
const CHUNK_SIZE: int = 16

## Schema version stored in world_meta.schema_version.
## Bumped to 2 in Phase 3 Plan 03-01 (adds inventories, chests, dropped_items, recipes_known).
## Bumped to 3 in Phase 4 Plan 04-03 (adds snapshots table for seamless host failover).
const SCHEMA_VERSION: int = 3

## DDL for the snapshots table (schema_version 3).
## snapshot_id: caller-supplied opaque string (e.g. session_id + timestamp).
## created_at: Unix timestamp (REAL) for ordering — load_latest_snapshot uses ORDER BY created_at DESC.
## chunk_blob: reserved for Phase 4 Plan 04-10 chunk streaming; empty PackedByteArray for v1.
## inventory_blob: var_to_bytes(Inventory.get_all_state()) — primary failover payload.
const _SNAPSHOT_TABLE_STMT := "CREATE TABLE IF NOT EXISTS snapshots (snapshot_id TEXT PRIMARY KEY, created_at REAL NOT NULL, chunk_blob BLOB, inventory_blob BLOB);"

## Number of rolling backup snapshots to keep on every checkpoint.
const BACKUP_KEEP: int = 3

# ─── Public read-only state ───────────────────────────────────────────────────

## The world_id of the currently-open world, or "" if none.
var world_id: String = ""

# ─── Private state ────────────────────────────────────────────────────────────

## godot-sqlite addon database handle for world.meta.sqlite.
## Typed as Object to avoid a GDScript parse error when the GDExtension
## class "SQLite" is not yet registered at script-parse time.
var _db: Object = null

## Absolute path to the world.meta.sqlite file (set by open_world).
var _meta_path: String = ""

## Set of dirty chunk coordinates (Dictionary[Vector3i, bool]; GDScript has no Set type).
var _dirty_chunks: Dictionary = {}

## StudGrid reference (set by attach_stud_grid; used during checkpoint to serialise bricks).
var _stud_grid: StudGrid = null

# ─── Lifecycle ────────────────────────────────────────────────────────────────

## Autoload _ready: no auto-open. open_world() is called by main_scene or test fixtures.
func _ready() -> void:
	pass


# ─── Public API ───────────────────────────────────────────────────────────────

## Open (or create) a world save directory and meta database.
##
## @param p_world_id    Unique identifier string for the world (used as directory name).
## @param world_seed    Integer seed for procedural generation (stored in world_meta).
## @param mode          "sandbox" or "survival" (stored in world_meta).
## @return              true on success; false if the database could not be opened.
func open_world(p_world_id: String, world_seed: int, mode: String) -> bool:
	if _db != null:
		push_warning("WorldSave.open_world: a world is already open ('%s'). Call close_world() first." % world_id)
		return false

	world_id = p_world_id
	var world_dir_abs := ProjectSettings.globalize_path("user://worlds/%s" % world_id)

	# Ensure the world directory exists.
	var err := DirAccess.make_dir_recursive_absolute(world_dir_abs)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("WorldSave.open_world: could not create world dir '%s' (err %d)." % [world_dir_abs, err])
		world_id = ""
		return false

	_meta_path = world_dir_abs + "/world.meta.sqlite"

	# Crash-mid-rename recovery: load_canonical_or_bak promotes .atomic → canonical if found.
	WorldSaveIo.load_canonical_or_bak(_meta_path)

	# Open (or create) the SQLite database via the godot-sqlite GDExtension.
	if not ClassDB.class_exists("SQLite"):
		push_error("WorldSave.open_world: 'SQLite' class not found — godot-sqlite GDExtension not loaded.")
		world_id = ""
		return false

	# Try to open the canonical file; on failure fall back to bak.1 → bak.2 → bak.3
	# (T-03-01 mitigation: a corrupted canonical file causes open failure; we recover
	#  from the most recent healthy backup automatically.)
	var paths_to_try: Array[String] = [
		_meta_path,
		_meta_path + ".bak.1",
		_meta_path + ".bak.2",
		_meta_path + ".bak.3",
	]
	var opened_path: String = ""
	for candidate: String in paths_to_try:
		if not FileAccess.file_exists(candidate) and candidate != _meta_path:
			continue   # bak files must exist; canonical is allowed to not exist yet
		_db = ClassDB.instantiate("SQLite")
		_db.set("path", candidate)
		_db.set("verbosity_level", 0)   # SQLite.QUIET = 0
		if _db.call("open_db"):
			opened_path = candidate
			break
		_db = null

	if _db == null:
		push_error("WorldSave.open_world: could not open any SQLite db for world '%s'." % world_id)
		world_id = ""
		return false

	# If we opened a backup instead of the canonical, copy it back to canonical.
	if opened_path != _meta_path and opened_path != "":
		push_warning("WorldSave.open_world: canonical corrupted, recovering from '%s'." % opened_path)
		_db.call("close_db")
		_db = null
		# Copy the backup to canonical path.
		var src := FileAccess.open(opened_path, FileAccess.READ)
		var dst := FileAccess.open(_meta_path, FileAccess.WRITE)
		if src != null and dst != null:
			const CHUNK_SZ: int = 65536
			while not src.eof_reached():
				var buf := src.get_buffer(CHUNK_SZ)
				if buf.size() > 0:
					dst.store_buffer(buf)
			src.close()
			dst.flush()
			dst.close()
		elif src != null:
			src.close()
		# Re-open the canonical.
		_db = ClassDB.instantiate("SQLite")
		_db.set("path", _meta_path)
		_db.set("verbosity_level", 0)
		if not _db.call("open_db"):
			push_error("WorldSave.open_world: could not reopen restored canonical '%s'." % _meta_path)
			_db = null
			world_id = ""
			return false

	# Create schema (idempotent — IF NOT EXISTS).
	var ok := _create_schema()
	if not ok:
		_db.call("close_db")
		_db = null
		world_id = ""
		return false

	# Run schema migration (idempotent: reads schema_version and runs migrations as needed).
	# Called after _create_schema() so new-world tables already exist; for existing v1 worlds
	# this upgrades to v2. Per T-03-01-MIG-01 the migration is transactional.
	if not _migrate_schema():
		push_error("WorldSave.open_world: schema migration failed for world '%s'." % world_id)
		_db.call("close_db")
		_db = null
		world_id = ""
		return false

	# Write/update schema_version to the current SCHEMA_VERSION.
	# Uses INSERT OR REPLACE (not IGNORE) so that after a migration the version row is
	# always updated to reflect the actual migrated version, not the stored pre-migration value.
	_db.call("query_with_bindings",
		"INSERT OR REPLACE INTO world_meta(key, value) VALUES (?, ?);",
		["schema_version", var_to_bytes(SCHEMA_VERSION)])
	_db.call("query_with_bindings",
		"INSERT OR IGNORE INTO world_meta(key, value) VALUES (?, ?);",
		["world_seed", var_to_bytes(world_seed)])
	_db.call("query_with_bindings",
		"INSERT OR IGNORE INTO world_meta(key, value) VALUES (?, ?);",
		["mode", var_to_bytes(mode)])

	return true


## Create and open a new world, validating the world name before any SQLite operations.
##
## This is the plan-05-10 creation entry point. It wraps open_world() with a
## ProfanityFilter guard so world names containing blocked words are rejected
## before the filesystem directory is even created.
##
## Callers should show "Choose another name." on false return — per the
## ProfanityFilter.filter_reject() contract, the rejected name must NOT be echoed.
##
## @param world_name  Human-readable name for the world (shown in the world list).
## @param seed        Integer seed for procedural terrain generation.
## @param mode        "sandbox" or "survival".
## @return            true on success; false if name is blocked or open_world() fails.
func create_world(world_name: String, seed: int = 0, mode: String = "sandbox") -> bool:
	# Defensive: reject empty names.
	if world_name.is_empty():
		push_warning("WorldSave.create_world: world_name is empty — rejecting.")
		return false

	# Phase 5 profanity guard (T-05-P-bypass mitigation).
	# filter_reject() returns true if the name contains a blocked word.
	# If rejected, push_warning (no error — this is expected user input) and return false.
	if _ProfanityFilter.filter_reject(world_name):
		push_warning("WorldSave.create_world: world name rejected by profanity filter.")
		return false

	# Use world_name sanitised as the world_id (lowercase, underscores, truncated).
	# Callers that need a stable ID should pass one directly via open_world().
	var world_id: String = world_name.to_lower().replace(" ", "_")
	# Truncate to 64 chars max to stay safe for filesystem paths.
	if world_id.length() > 64:
		world_id = world_id.substr(0, 64)
	# Append a short timestamp suffix to avoid collisions on same-named worlds.
	world_id = world_id + "_" + str(int(Time.get_unix_time_from_system()))

	return open_world(world_id, seed, mode)


## Validate a new world name for an existing world (rename operation).
##
## Returns false if the name contains profanity or is empty; callers must show
## "Choose another name." and MUST NOT echo the rejected name.
## This is a validation-only call — it does NOT rename the filesystem directory
## (world directory names are stable IDs; world_name is a display label stored
## in the world_meta table). Callers that proceed on true must call set_world_meta().
##
## @param new_name  The proposed new display name.
## @return          true if the name is acceptable; false if rejected.
func rename_world(new_name: String) -> bool:
	if new_name.is_empty():
		push_warning("WorldSave.rename_world: new_name is empty — rejecting.")
		return false
	if _ProfanityFilter.filter_reject(new_name):
		push_warning("WorldSave.rename_world: new world name rejected by profanity filter.")
		return false
	return true


## Attach a StudGrid instance for dirty-chunk tracking and checkpoint serialisation.
##
## Called by main_scene (or test fixtures) after open_world() — NOT in _ready(),
## because autoloads are ready before the scene tree is populated.
func attach_stud_grid(sg: StudGrid) -> void:
	if _stud_grid != null:
		# Detach old connections if replacing.
		if _stud_grid.placed.is_connected(_on_stud_placed):
			_stud_grid.placed.disconnect(_on_stud_placed)
		if _stud_grid.removed.is_connected(_on_stud_removed):
			_stud_grid.removed.disconnect(_on_stud_removed)

	_stud_grid = sg
	if _stud_grid != null:
		_stud_grid.placed.connect(_on_stud_placed)
		_stud_grid.removed.connect(_on_stud_removed)


## Mark a chunk as dirty (needs re-serialising on next checkpoint).
##
## @param chunk  Chunk coordinate (anchor_cell / CHUNK_SIZE, integer-divided per axis).
func mark_chunk_dirty(chunk: Vector3i) -> void:
	_dirty_chunks[chunk] = true


## Perform an atomic checkpoint: serialise all dirty chunks to SQLite, flush to disk,
## rotate backups, and clear the dirty set.
##
## @return  true on success; false if the database is not open.
func checkpoint() -> bool:
	if _db == null:
		push_error("WorldSave.checkpoint: no world is open.")
		return false

	# Serialise each dirty chunk.
	for chunk_coord: Vector3i in _dirty_chunks.keys():
		_save_chunk(chunk_coord)

	# Flush: close the DB so godot-sqlite writes its WAL / page cache to disk.
	# (Pitfall 6 — explicit flush on Android/iOS before rename_absolute.)
	_db.call("close_db")

	# Atomic promote: copy canonical → .atomic via rename chain.
	WorldSaveIo.atomic_write_sqlite(_meta_path)

	# Rolling backups: bak.1 ← canonical; bak.2 ← bak.1; bak.3 ← bak.2
	WorldSaveIo.rotate_backups(_meta_path, BACKUP_KEEP)

	# Reopen the database for subsequent operations.
	if not _db.call("open_db"):
		push_error("WorldSave.checkpoint: could not reopen SQLite db after checkpoint.")
		_db = null
		return false

	_dirty_chunks.clear()
	return true


## Convenience wrapper: perform a checkpoint and then capture a thumbnail deferred 1 frame.
##
## Callers (e.g. main_scene periodic save) should use save_world() instead of checkpoint()
## so the world thumbnail stays current.  capture_thumbnail() is queued deferred so the
## viewport is fully rendered before the screenshot is taken.
##
## @return  true on successful checkpoint; false if the database is not open.
func save_world() -> bool:
	var ok := checkpoint()
	if ok and not world_id.is_empty():
		call_deferred("capture_thumbnail", world_id)
	return ok


## Capture a 256×144 JPEG thumbnail of the current viewport and save it to
## user://worlds/{world_id}/thumbnail.png.
##
## Called via call_deferred from save_world() so the RenderingServer has had one
## additional frame to complete its draw calls — this guarantees the viewport image
## is current rather than a frame-old snapshot.
##
## Gracefully degrades: if the viewport image is null or empty (headless / unit test
## environment), the method returns without writing a file.
##
## @param p_world_id  The world identifier whose directory will receive the thumbnail.
func capture_thumbnail(p_world_id: String) -> void:
	if p_world_id.is_empty():
		return

	RenderingServer.force_draw(false)

	var vp := get_viewport()
	if vp == null:
		return

	var img: Image = vp.get_texture().get_image()
	if img == null or img.is_empty():
		return

	img.resize(256, 144, Image.INTERPOLATE_BILINEAR)

	var dir_path := "user://worlds/%s" % p_world_id
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(dir_path))

	# Save as JPEG.  Note: the method is img.save_jpg() in Godot 4; the path uses
	# the same user:// scheme as the rest of the world data.
	var thumb_path := "%s/thumbnail.jpg" % dir_path
	var err := img.save_jpg(
		ProjectSettings.globalize_path(thumb_path), 0.85)
	if err != OK:
		push_warning("WorldSave.capture_thumbnail: failed to save thumbnail for '%s' (err %d)." % [p_world_id, err])


## Close the world: perform a final checkpoint and close the database.
func close_world() -> void:
	if _db == null:
		return
	checkpoint()
	if _db != null:
		_db.call("close_db")
		_db = null
	world_id = ""
	_meta_path = ""
	_dirty_chunks.clear()
	if _stud_grid != null:
		if _stud_grid.placed.is_connected(_on_stud_placed):
			_stud_grid.placed.disconnect(_on_stud_placed)
		if _stud_grid.removed.is_connected(_on_stud_removed):
			_stud_grid.removed.disconnect(_on_stud_removed)
		_stud_grid = null


## Return true if a world is currently open.
func is_open() -> bool:
	return _db != null


## Read a metadata value from the world_meta table.
## Named get_world_meta (not get_meta) to avoid collision with Node.get_meta() built-in.
##
## @param key  The metadata key (e.g. "world_seed", "mode", "clock_state").
## @return     The stored Variant, or null if the key does not exist.
func get_world_meta(key: String) -> Variant:
	if _db == null:
		return null
	_db.call("query_with_bindings", "SELECT value FROM world_meta WHERE key = ?;", [key])
	var results: Array = _db.get("query_result")
	if results.is_empty():
		return null
	var blob = results[0].get("value", null)
	if blob == null:
		return null
	if blob is PackedByteArray:
		return bytes_to_var(blob as PackedByteArray)
	return blob


## Write a metadata value to the world_meta table.
## Named set_world_meta (not set_meta) to avoid collision with Object.set_meta() built-in.
##
## @param key    The metadata key.
## @param value  The Variant to store (serialised via var_to_bytes).
func set_world_meta(key: String, value: Variant) -> void:
	if _db == null:
		push_error("WorldSave.set_world_meta: no world is open.")
		return
	_db.call("query_with_bindings",
		"INSERT OR REPLACE INTO world_meta(key, value) VALUES (?, ?);",
		[key, var_to_bytes(value)])


## Insert or replace a chest row in the chests table.
## Uses parameterised query_with_bindings — never string concatenation (T-03-02-INV-05).
##
## @param chunk_coord     The chest's chunk coordinate.
## @param tier            Chest type string ("regular", "bronze", "silver", "gold", "diamond").
## @param locked          true if the chest is locked.
## @param contents_blob   var_to_bytes-serialised contents Array.
## @param double_partner  Coord-key string of the double-chest partner, or "" if single.
## @return                true if the query succeeded; false if no world is open.
func save_chest(chunk_coord: Vector3i, tier: String, locked: bool,
                contents_blob: PackedByteArray, double_partner: String) -> bool:
	if _db == null:
		return false
	_db.call("query_with_bindings",
		"""INSERT OR REPLACE INTO chests
		   (chunk_x, chunk_y, chunk_z, type, locked, contents_blob, double_chest_partner)
		   VALUES (?, ?, ?, ?, ?, ?, ?);""",
		[chunk_coord.x, chunk_coord.y, chunk_coord.z,
		 tier, int(locked), contents_blob, double_partner])
	return true


## Load a single chest row from the chests table.
##
## @param chunk_coord  The chest's chunk coordinate.
## @return             {type, locked, contents, double_chest_partner} or {} if absent.
func load_chest(chunk_coord: Vector3i) -> Dictionary:
	if _db == null:
		return {}
	_db.call("query_with_bindings",
		"SELECT type, locked, contents_blob, double_chest_partner FROM chests WHERE chunk_x=? AND chunk_y=? AND chunk_z=?;",
		[chunk_coord.x, chunk_coord.y, chunk_coord.z])
	var results: Array = _db.get("query_result")
	if results.is_empty():
		return {}
	var row: Dictionary = results[0]
	var blob: Variant = row.get("contents_blob", null)
	var contents: Array = []
	if blob is PackedByteArray:
		var decoded: Variant = bytes_to_var(blob as PackedByteArray)
		if decoded is Array:
			contents = decoded as Array
	return {
		"type":                row.get("type", "regular"),
		"locked":              bool(int(row.get("locked", 0))),
		"contents":            contents,
		"double_chest_partner": str(row.get("double_chest_partner", "")),
	}


## Load all chest rows from the chests table.
## Used by Inventory.attach_world() to rehydrate _chests on world open.
##
## @return  Array of {chunk_coord: Vector3i, type, locked, contents, double_chest_partner}.
func load_all_chests() -> Array[Dictionary]:
	if _db == null:
		return []
	_db.call("query", "SELECT chunk_x, chunk_y, chunk_z, type, locked, contents_blob, double_chest_partner FROM chests;")
	var results: Array = _db.get("query_result")
	var out: Array[Dictionary] = []
	for row: Dictionary in results:
		var blob: Variant = row.get("contents_blob", null)
		var contents: Array = []
		if blob is PackedByteArray:
			var decoded: Variant = bytes_to_var(blob as PackedByteArray)
			if decoded is Array:
				contents = decoded as Array
		out.append({
			"chunk_coord":         Vector3i(int(row.get("chunk_x", 0)),
			                                int(row.get("chunk_y", 0)),
			                                int(row.get("chunk_z", 0))),
			"type":                row.get("type", "regular"),
			"locked":              bool(int(row.get("locked", 0))),
			"contents":            contents,
			"double_chest_partner": str(row.get("double_chest_partner", "")),
		})
	return out


## Return all chunk coordinates that have saved stud_grid_chunks rows.
## Used by load logic to know which chunks need to be loaded into the grid.
func get_saved_chunk_coords() -> Array:
	if _db == null:
		return []
	_db.call("query", "SELECT chunk_x, chunk_y, chunk_z FROM stud_grid_chunks;")
	var results: Array = _db.get("query_result")
	var coords: Array = []
	for row: Dictionary in results:
		coords.append(Vector3i(int(row.get("chunk_x", 0)),
		                       int(row.get("chunk_y", 0)),
		                       int(row.get("chunk_z", 0))))
	return coords


## Load bricks for a chunk from the stud_grid_chunks table and add them to a StudGrid.
##
## @param chunk_coord  The chunk coordinate to load.
## @param sg           The StudGrid to populate.
## @param brick_defs   Dictionary[String, BrickDefinition] for resolving def_id strings.
## @return             true if the chunk row existed; false if no row (regenerate from seed).
func load_chunk_into_grid(chunk_coord: Vector3i, sg: StudGrid,
                           brick_defs: Dictionary) -> bool:
	if _db == null:
		return false
	_db.call("query_with_bindings",
		"SELECT blob FROM stud_grid_chunks WHERE chunk_x=? AND chunk_y=? AND chunk_z=?;",
		[chunk_coord.x, chunk_coord.y, chunk_coord.z])
	var results: Array = _db.get("query_result")
	if results.is_empty():
		return false

	var blob = results[0].get("blob", null)
	if blob == null:
		return false

	# blob may come back as PackedByteArray or String depending on the driver version.
	var raw_blob: PackedByteArray
	if blob is PackedByteArray:
		raw_blob = blob as PackedByteArray
	elif blob is String:
		raw_blob = (blob as String).to_utf8_buffer()
	else:
		push_error("WorldSave.load_chunk_into_grid: unexpected blob type %s." % typeof(blob))
		return false

	var payload := ChunkCodec.decode_chunk_delta(raw_blob)
	if payload.is_empty():
		push_error("WorldSave.load_chunk_into_grid: chunk (%d,%d,%d) has corrupted blob — skipping." % [
			chunk_coord.x, chunk_coord.y, chunk_coord.z])
		return false

	# Deserialise the Array of [anchor_cell, def_id] tuples.
	var entries: Variant = bytes_to_var(payload)
	if not entries is Array:
		push_error("WorldSave.load_chunk_into_grid: deserialised payload is not Array.")
		return false

	for entry: Variant in (entries as Array):
		if not entry is Array or (entry as Array).size() < 2:
			continue
		var anchor_cell: Vector3i = (entry as Array)[0]
		var def_id: String        = str((entry as Array)[1])
		var def: BrickDefinition  = brick_defs.get(def_id, null)
		if def == null:
			push_warning("WorldSave.load_chunk_into_grid: unknown def_id '%s' — skipping." % def_id)
			continue
		sg.place(anchor_cell, def)
	return true


# ─── Private helpers ──────────────────────────────────────────────────────────

## Create all tables if they don't exist (idempotent CREATE TABLE IF NOT EXISTS).
## For fresh worlds this creates both v1 and v2 tables in one pass.
## For existing v1 worlds, _migrate_schema() will add the v2 tables separately.
func _create_schema() -> bool:
	var stmts: Array[String] = [
		"""CREATE TABLE IF NOT EXISTS world_meta (
			key   TEXT PRIMARY KEY,
			value BLOB
		);""",
		"""CREATE TABLE IF NOT EXISTS stud_grid_chunks (
			chunk_x INTEGER NOT NULL,
			chunk_y INTEGER NOT NULL,
			chunk_z INTEGER NOT NULL,
			blob    BLOB,
			PRIMARY KEY (chunk_x, chunk_y, chunk_z)
		);""",
		"""CREATE TABLE IF NOT EXISTS structures_seen (
			template_id TEXT NOT NULL,
			anchor_x    INTEGER NOT NULL,
			anchor_y    INTEGER NOT NULL,
			anchor_z    INTEGER NOT NULL,
			PRIMARY KEY (template_id, anchor_x, anchor_y, anchor_z)
		);""",
		"""CREATE TABLE IF NOT EXISTS builders (
			id   TEXT PRIMARY KEY,
			blob BLOB
		);""",
	]
	# Append v2 table statements so fresh worlds are created at schema_version 2.
	stmts.append_array(_v2_table_stmts())
	# Append v3 table statements so fresh worlds are created at schema_version 3.
	stmts.append(_SNAPSHOT_TABLE_STMT)
	for stmt: String in stmts:
		if not _db.call("query", stmt):
			push_error("WorldSave._create_schema: failed to execute: %s" % stmt)
			return false
	return true


## Return the 4 CREATE TABLE IF NOT EXISTS statements for schema_version 2.
## Shared between _create_schema() (fresh worlds) and _migrate_1_to_2() (existing v1 worlds).
## Per T-03-01-MIG-01: all statements are idempotent (IF NOT EXISTS).
func _v2_table_stmts() -> Array[String]:
	return [
		"""CREATE TABLE IF NOT EXISTS inventories (
			builder_id TEXT PRIMARY KEY,
			blob       BLOB
		);""",
		"""CREATE TABLE IF NOT EXISTS chests (
			chunk_x              INTEGER NOT NULL,
			chunk_y              INTEGER NOT NULL,
			chunk_z              INTEGER NOT NULL,
			type                 TEXT NOT NULL,
			locked               INTEGER NOT NULL,
			contents_blob        BLOB,
			double_chest_partner TEXT,
			PRIMARY KEY (chunk_x, chunk_y, chunk_z)
		);""",
		"""CREATE TABLE IF NOT EXISTS dropped_items (
			entity_id     TEXT PRIMARY KEY,
			kind          TEXT NOT NULL,
			pos_x         REAL,
			pos_y         REAL,
			pos_z         REAL,
			contents_blob BLOB,
			spawn_tick    REAL NOT NULL
		);""",
		"""CREATE TABLE IF NOT EXISTS recipes_known (
			builder_id TEXT PRIMARY KEY,
			blob       BLOB
		);""",
	]


## Run schema migrations from the current DB version up to SCHEMA_VERSION.
## Reads the persisted schema_version, dispatches version-specific migration functions,
## and returns true on success or false if any migration step fails.
##
## Idempotent: if schema_version is already at SCHEMA_VERSION, returns true immediately.
## Per T-03-01-MIG-01: each migration step is transactional (BEGIN/COMMIT/ROLLBACK).
## Per T-03-01-MIG-03: malformed or null schema_version is treated as version 0.
func _migrate_schema() -> bool:
	# Read the persisted schema_version. bytes_to_var handles the PackedByteArray round-trip.
	var raw_version: Variant = get_world_meta("schema_version")
	var current_version: int = 0
	if raw_version is int:
		current_version = raw_version as int
	elif raw_version != null:
		# Malformed value — push_error and treat as 0 (full migration).
		push_error("WorldSave._migrate_schema: malformed schema_version value '%s' — treating as 0." % str(raw_version))

	# Fast path: already at or above current version.
	if current_version >= SCHEMA_VERSION:
		return true

	# Run migrations in order from current_version up to SCHEMA_VERSION.
	while current_version < SCHEMA_VERSION:
		var ok: bool = false
		match current_version:
			2:
				ok = _migrate_2_to_3()
			1:
				ok = _migrate_1_to_2()
			0:
				# v0 has the same base schema as v1; skip directly to v1 and let
				# the next loop iteration run _migrate_1_to_2() exactly once (WR-05).
				ok = true
			_:
				# Completely unknown base version — attempt to run all migrations
				# idempotently and then jump to SCHEMA_VERSION so the loop exits.
				ok = _migrate_1_to_2()
				if ok:
					ok = _migrate_2_to_3()
				if ok:
					current_version = SCHEMA_VERSION - 1
		if not ok:
			return false
		current_version += 1

	return true


## Migrate a v1 world schema to v2 by creating the 4 new tables.
## Wrapped in BEGIN/COMMIT with ROLLBACK on any failure (T-03-01-MIG-01).
func _migrate_1_to_2() -> bool:
	# Normal operation (also runs on fresh-world creation to build the v2 tables), so this
	# is an informational print, NOT a push_warning — warnings should flag real problems.
	print("WorldSave._migrate_1_to_2: building schema v2 tables for world '%s'." % world_id)

	if not _db.call("query", "BEGIN;"):
		push_error("WorldSave._migrate_1_to_2: could not BEGIN transaction.")
		return false

	var stmts := _v2_table_stmts()
	var table_names: Array[String] = ["inventories", "chests", "dropped_items", "recipes_known"]
	for i: int in stmts.size():
		if not _db.call("query", stmts[i]):
			push_error("WorldSave._migrate_1_to_2: failed to create '%s' table — rolling back." % table_names[i])
			_db.call("query", "ROLLBACK;")
			return false
		print("WorldSave._migrate_1_to_2: created table '%s'." % table_names[i])

	if not _db.call("query", "COMMIT;"):
		push_error("WorldSave._migrate_1_to_2: could not COMMIT transaction — rolling back.")
		_db.call("query", "ROLLBACK;")
		return false

	print("WorldSave._migrate_1_to_2: schema v2 ready for world '%s'." % world_id)
	return true


## Migrate a v2 world schema to v3 by creating the snapshots table.
## Wrapped in BEGIN/COMMIT with ROLLBACK on any failure (T-04-03 mitigation).
## snapshots table stores inventory + chunk blobs for seamless host failover (Phase 4 Plan 04-10).
func _migrate_2_to_3() -> bool:
	# Informational (also runs on fresh-world creation); not a push_warning. See _migrate_1_to_2.
	print("WorldSave._migrate_2_to_3: building schema v3 tables for world '%s'." % world_id)

	if not _db.call("query", "BEGIN;"):
		push_error("WorldSave._migrate_2_to_3: could not BEGIN transaction.")
		return false

	if not _db.call("query", _SNAPSHOT_TABLE_STMT):
		push_error("WorldSave._migrate_2_to_3: failed to create 'snapshots' table — rolling back.")
		_db.call("query", "ROLLBACK;")
		return false
	print("WorldSave._migrate_2_to_3: created table 'snapshots'.")

	if not _db.call("query", "COMMIT;"):
		push_error("WorldSave._migrate_2_to_3: could not COMMIT transaction — rolling back.")
		_db.call("query", "ROLLBACK;")
		return false

	print("WorldSave._migrate_2_to_3: schema v3 ready for world '%s'." % world_id)
	return true


## Write a failover snapshot to the snapshots table.
##
## The snapshot captures the current inventory state (via Inventory.get_all_state()) and
## a Zstd-compressed delta of the currently-dirty chunk set.
##
## snapshot_id is an opaque caller-supplied string; typically session_id + "_" + timestamp.
## NetworkManager.get_session_id() is used for session_id by callers where a multiplayer
## session is active (A3 cleanup completed in Plan 04-09 — no bare timestamp fallback here).
##
## TODO(04-11): Update DOCS §6.8.5 to document the snapshots table addition when Phase 4
##   is complete (deferred to Plan 04-11 DOCS sync checkpoint).
##
## @param snapshot_id  Opaque identifier for this snapshot row (TEXT PRIMARY KEY).
## @return             true on success; false if the database is not open.
func save_world_snapshot(snapshot_id: String) -> bool:
	if _db == null:
		return false

	# Inventory blob: full serialisation of in-RAM inventory state.
	var inventory_blob := PackedByteArray()
	if is_instance_valid(Inventory):
		inventory_blob = var_to_bytes(Inventory.get_all_state())

	# Chunk blob: Zstd-compressed serialisation of the dirty-chunk set.
	# Captures all modified chunk coordinates and their on-disk blob data.
	# If no chunks are dirty, saves an empty PackedByteArray (fast path).
	var chunk_blob: PackedByteArray = PackedByteArray()
	if not _dirty_chunks.is_empty():
		# Build a Dictionary of chunk coordinate strings → raw chunk data.
		# Each entry serialises the bricks in that chunk via var_to_bytes so the
		# receiver can call bytes_to_var to reconstruct the Array[anchor, def_id] list.
		var chunk_dict: Dictionary = {}
		for coord: Vector3i in _dirty_chunks.keys():
			# Serialise the list of bricks for this chunk (same path as _save_chunk).
			var entries: Array = []
			if _stud_grid != null:
				for anchor_cell: Vector3i in _stud_grid.get_all_anchors():
					if _cell_to_chunk(anchor_cell) != coord:
						continue
					var instance: StudGrid.BrickInstance = _stud_grid.query(anchor_cell)
					if instance == null:
						continue
					entries.append([anchor_cell, instance.definition.brick_id])
			chunk_dict[str(coord)] = entries
		# Serialise the whole map, then compress with Zstd via ChunkCodec.
		var raw_bytes := var_to_bytes(chunk_dict)
		chunk_blob = ChunkCodec.encode_chunk_delta(raw_bytes)

	_db.call("query_with_bindings",
		"INSERT OR REPLACE INTO snapshots(snapshot_id, created_at, chunk_blob, inventory_blob) VALUES (?, ?, ?, ?);",
		[snapshot_id, Time.get_unix_time_from_system(), chunk_blob, inventory_blob])
	return true


## Remove old snapshots beyond the keep limit for a session.
## Prunes the oldest rows (by created_at) keeping only the most recent keep_count rows.
##
## @param session_prefix  Common prefix used in snapshot_ids for this session (e.g. "snap_").
##                        Pass "" to prune all snapshots globally.
## @param keep_count      Number of most-recent snapshots to retain (default 3).
func prune_old_snapshots(session_prefix: String = "", keep_count: int = 3) -> void:
	if _db == null:
		return
	# Find the created_at timestamp of the Nth most-recent snapshot (the cutoff).
	# Any row older than this cutoff is deleted.
	var query: String
	var params: Array
	if session_prefix.is_empty():
		query = "SELECT created_at FROM snapshots ORDER BY created_at DESC LIMIT 1 OFFSET ?;"
		params = [keep_count]
	else:
		# WR-05: Escape LIKE wildcards in session_prefix so a prefix containing
		# '%' or '_' does not accidentally match unrelated snapshots. Session IDs
		# are UUIDs so this is low-probability, but the escape is cheap insurance.
		var safe_prefix: String = session_prefix \
			.replace("\\", "\\\\") \
			.replace("%", "\\%") \
			.replace("_", "\\_")
		query = "SELECT created_at FROM snapshots WHERE snapshot_id LIKE ? ESCAPE '\\' ORDER BY created_at DESC LIMIT 1 OFFSET ?;"
		params = [safe_prefix + "%", keep_count]
	_db.call("query_with_bindings", query, params)
	var results: Array = _db.get("query_result")
	if results.is_empty():
		return  # Fewer than keep_count snapshots — nothing to prune.
	var cutoff_at: float = float(results[0].get("created_at", 0.0))
	# Delete rows strictly older than the cutoff timestamp.
	if session_prefix.is_empty():
		_db.call("query_with_bindings",
			"DELETE FROM snapshots WHERE created_at < ?;",
			[cutoff_at])
	else:
		# Re-escape the prefix for the DELETE query as well.
		var safe_prefix_del: String = session_prefix \
			.replace("\\", "\\\\") \
			.replace("%", "\\%") \
			.replace("_", "\\_")
		_db.call("query_with_bindings",
			"DELETE FROM snapshots WHERE snapshot_id LIKE ? ESCAPE '\\' AND created_at < ?;",
			[safe_prefix_del + "%", cutoff_at])


## Load the most-recent snapshot from the snapshots table.
##
## @return  Dictionary with keys: snapshot_id (String), created_at (float),
##          chunk_blob (PackedByteArray), inventory_blob (PackedByteArray).
##          Returns {} if no snapshot exists or the database is not open.
func load_latest_snapshot() -> Dictionary:
	if _db == null:
		return {}
	_db.call("query", "SELECT * FROM snapshots ORDER BY created_at DESC LIMIT 1;")
	var results: Array = _db.get("query_result")
	if results.is_empty():
		return {}
	var row: Dictionary = results[0]
	return {
		"snapshot_id":    str(row.get("snapshot_id", "")),
		"created_at":     float(row.get("created_at", 0.0)),
		"chunk_blob":     row.get("chunk_blob", PackedByteArray()) if row.get("chunk_blob") is PackedByteArray else PackedByteArray(),
		"inventory_blob": row.get("inventory_blob", PackedByteArray()) if row.get("inventory_blob") is PackedByteArray else PackedByteArray(),
	}


## Return all snapshot_id values ordered by created_at DESC.
## Used by roll-back UI (Phase 4 Plans 04-09/04-10) to list snapshots.
##
## @return  Array of snapshot_id strings, newest first.
func get_snapshot_ids() -> Array:
	if _db == null:
		return []
	_db.call("query", "SELECT snapshot_id FROM snapshots ORDER BY created_at DESC;")
	var results: Array = _db.get("query_result")
	var ids: Array = []
	for row: Dictionary in results:
		ids.append(str(row.get("snapshot_id", "")))
	return ids


## Serialise a single chunk from the attached StudGrid into the stud_grid_chunks table.
func _save_chunk(chunk_coord: Vector3i) -> void:
	if _stud_grid == null:
		return

	# Collect all bricks in this chunk.
	var entries: Array = []
	for anchor_cell: Vector3i in _stud_grid.get_all_anchors():
		var chunk := _cell_to_chunk(anchor_cell)
		if chunk != chunk_coord:
			continue
		var instance: StudGrid.BrickInstance = _stud_grid.query(anchor_cell)
		if instance == null:
			continue
		# Store [anchor_cell, def_id] tuple (colour_index added in Phase 2 extension).
		entries.append([anchor_cell, instance.definition.brick_id])

	var payload := var_to_bytes(entries)
	var blob := ChunkCodec.encode_chunk_delta(payload)

	_db.call("query_with_bindings",
		"INSERT OR REPLACE INTO stud_grid_chunks(chunk_x, chunk_y, chunk_z, blob) VALUES (?, ?, ?, ?);",
		[chunk_coord.x, chunk_coord.y, chunk_coord.z, blob])


## Convert a brick anchor cell to a chunk coordinate.
## Uses floored division so that negative coords map correctly (e.g. -1 → chunk -1, not 0).
func _cell_to_chunk(cell: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(cell.x) / float(CHUNK_SIZE)),
		floori(float(cell.y) / float(CHUNK_SIZE)),
		floori(float(cell.z) / float(CHUNK_SIZE)),
	)


# ─── StudGrid signal handlers ─────────────────────────────────────────────────

func _on_stud_placed(anchor_cell: Vector3i, _definition: BrickDefinition,
		_colour_index: int, _rotation: int) -> void:
	mark_chunk_dirty(_cell_to_chunk(anchor_cell))


func _on_stud_removed(anchor_cell: Vector3i) -> void:
	mark_chunk_dirty(_cell_to_chunk(anchor_cell))
