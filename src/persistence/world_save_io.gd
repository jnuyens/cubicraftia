# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# world_save_io.gd — Atomic-rename helper + rolling 3-snapshot backup rotation.
#
# Design:
#   atomic_write_sqlite():
#     Copies the canonical SQLite file to a .tmp file, flushes + closes it, then renames
#     it to .atomic. The .atomic suffix marks a successful atomic rename that was not yet
#     promoted. On the next load, load_canonical_or_bak() detects .atomic and promotes it.
#     This follows the write-temp → flush → rename pattern (RESEARCH.md §"Architecture
#     Patterns" lines 320-330) which ensures the canonical path is never half-written:
#       1. godot-sqlite commits to world.meta.sqlite
#       2. We copy → world.meta.sqlite.tmp
#       3. flush() + close()
#       4. rename_absolute(.tmp → .atomic)
#       5. On next open, .atomic → canonical (crash-mid-step-4 = .atomic missing → bak.1)
#
#   rotate_backups():
#     Rotates: bak.{N-1} → bak.{N} (oldest discarded), ..., bak.1 ← copy of canonical.
#     Ensures 3 snapshots survive after every checkpoint so test_corrupted_canonical_falls_back
#     _to_bak_1 always has a healthy bak.1.
#
#   load_canonical_or_bak():
#     Fallback order: .atomic → canonical → .bak.1 → .bak.2 → .bak.3
#     If .atomic is found, promotes it to canonical before returning canonical path.
#
# Pitfall 6 (RESEARCH.md): Android/iOS require explicit flush() before rename — achieved here
# by closing the FileAccess handle (which flushes the OS write buffer) before rename_absolute.
#
# References:
#   RESEARCH.md §"Architecture Patterns" lines 296-330 — the atomic-rename + rolling-backup
#   RESEARCH.md §"Pitfall 6" — explicit flush before rename on mobile platforms
#   RESEARCH.md §"Contradiction 2" — this module is codec-agnostic; codec is in chunk_codec.gd
#   02-PATTERNS.md §"Persistence (net-new)" — lifecycle analog from thermal_probe.gd

class_name WorldSaveIo
extends RefCounted

## Suffix appended to the canonical path while writing (intermediate temp).
const SUFFIX_TMP:    String = ".tmp"

## Suffix that marks a successfully-renamed file not yet promoted to canonical.
## Detecting this on load allows crash-mid-promotion recovery.
const SUFFIX_ATOMIC: String = ".atomic"

## Backup suffix template — append 1-based index.
const SUFFIX_BAK:    String = ".bak."


## Atomically stage a checkpoint for the SQLite file at canonical_path.
##
## Assumes godot-sqlite has already committed all pending transactions to
## canonical_path. This function copies the file to canonical_path.tmp,
## flushes and closes the copy, then renames .tmp → .atomic.
##
## @param canonical_path  Absolute path to the world.meta.sqlite file.
## @return                true on success; false if any step fails.
static func atomic_write_sqlite(canonical_path: String) -> bool:
	var tmp_path := canonical_path + SUFFIX_TMP
	var atomic_path := canonical_path + SUFFIX_ATOMIC

	# --- Step 1: copy canonical → .tmp ---
	var src := FileAccess.open(canonical_path, FileAccess.READ)
	if src == null:
		push_error("WorldSaveIo.atomic_write_sqlite: cannot open source '%s' (err %d)." % [
			canonical_path, FileAccess.get_open_error()])
		return false

	var dst := FileAccess.open(tmp_path, FileAccess.WRITE)
	if dst == null:
		src.close()
		push_error("WorldSaveIo.atomic_write_sqlite: cannot open dest '%s' (err %d)." % [
			tmp_path, FileAccess.get_open_error()])
		return false

	# Copy in 64 KiB chunks to avoid large memory spikes on mobile.
	const CHUNK_SIZE: int = 65536
	while not src.eof_reached():
		var buf := src.get_buffer(CHUNK_SIZE)
		if buf.size() > 0:
			dst.store_buffer(buf)

	src.close()

	# --- Step 2: flush + close dest (Pitfall 6 — explicit flush on mobile) ---
	dst.flush()
	dst.close()

	# --- Step 3: rename .tmp → .atomic (POSIX rename is atomic within same filesystem) ---
	var err := DirAccess.rename_absolute(tmp_path, atomic_path)
	if err != OK:
		push_error("WorldSaveIo.atomic_write_sqlite: rename_absolute('%s' → '%s') failed (err %d)." % [
			tmp_path, atomic_path, err])
		return false

	return true


## Rotate the rolling backups, keeping at most `keep` snapshots.
##
## Rotation order (keep=3 example):
##   bak.3 is discarded (overwritten / replaced by bak.2)
##   bak.2 ← bak.1
##   bak.1 ← copy of canonical
##
## @param canonical_path  Absolute path to the world.meta.sqlite file.
## @param keep            Number of backup snapshots to retain (default 3).
static func rotate_backups(canonical_path: String, keep: int = 3) -> void:
	if keep < 1:
		return

	# Shift existing backups: bak.(keep-1) → bak.keep, ..., bak.1 → bak.2
	var idx := keep
	while idx > 1:
		var older := canonical_path + SUFFIX_BAK + str(idx)
		var newer := canonical_path + SUFFIX_BAK + str(idx - 1)
		if FileAccess.file_exists(newer):
			# Remove older slot before rename to avoid "file exists" error on Windows.
			if FileAccess.file_exists(older):
				DirAccess.remove_absolute(older)
			DirAccess.rename_absolute(newer, older)
		idx -= 1

	# bak.1 ← copy of canonical (if canonical exists)
	if not FileAccess.file_exists(canonical_path):
		return

	var bak1 := canonical_path + SUFFIX_BAK + "1"
	# Remove stale bak.1 if still present (shouldn't be after the loop, but defensive).
	if FileAccess.file_exists(bak1):
		DirAccess.remove_absolute(bak1)

	var src := FileAccess.open(canonical_path, FileAccess.READ)
	if src == null:
		push_error("WorldSaveIo.rotate_backups: cannot open source '%s' (err %d)." % [
			canonical_path, FileAccess.get_open_error()])
		return

	var dst := FileAccess.open(bak1, FileAccess.WRITE)
	if dst == null:
		src.close()
		push_error("WorldSaveIo.rotate_backups: cannot open bak.1 '%s' (err %d)." % [
			bak1, FileAccess.get_open_error()])
		return

	const CHUNK_SIZE: int = 65536
	while not src.eof_reached():
		var buf := src.get_buffer(CHUNK_SIZE)
		if buf.size() > 0:
			dst.store_buffer(buf)

	src.close()
	dst.flush()
	dst.close()


## Return the best available path for loading the world SQLite file.
##
## Fallback order:
##   1. canonical_path + ".atomic"  — crash-mid-promotion: promote to canonical, return canonical
##   2. canonical_path              — healthy last checkpoint
##   3. canonical_path + ".bak.1"   — one checkpoint back
##   4. canonical_path + ".bak.2"
##   5. canonical_path + ".bak.3"
##
## @param canonical_path  Absolute path to the world.meta.sqlite file.
## @return                The best existing path to open, or "" if nothing found.
static func load_canonical_or_bak(canonical_path: String) -> String:
	var atomic_path := canonical_path + SUFFIX_ATOMIC

	# Crash-mid-promotion recovery: .atomic exists → promote to canonical.
	if FileAccess.file_exists(atomic_path):
		# Remove old canonical before rename (Windows requires this).
		if FileAccess.file_exists(canonical_path):
			DirAccess.remove_absolute(canonical_path)
		var err := DirAccess.rename_absolute(atomic_path, canonical_path)
		if err == OK:
			return canonical_path
		else:
			push_error("WorldSaveIo.load_canonical_or_bak: could not promote .atomic (err %d); trying bak.1." % err)

	# Canonical path (healthy last checkpoint).
	if FileAccess.file_exists(canonical_path):
		return canonical_path

	# Rolling backups.
	for i in range(1, 4):   # bak.1, bak.2, bak.3
		var bak := canonical_path + SUFFIX_BAK + str(i)
		if FileAccess.file_exists(bak):
			return bak

	return ""
