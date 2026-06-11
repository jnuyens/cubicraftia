# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# chunk_codec.gd — Zstd-compress + MD5-checksum a chunk delta blob for SQLite storage.
#
# Design:
#   Blob layout: [16 bytes MD5][4 bytes BE uint32 compressed_len][compressed_bytes]
#
#   Compression: PackedByteArray.compress(FileAccess.COMPRESSION_ZSTD) per RESEARCH.md
#   Contradiction 2 — Godot 4.6 has no LZ4; Zstd gives a better ratio at write-rarely /
#   read-often cadence (RESEARCH.md §"Standard Stack" Phase-2-new table, row COMPRESSION_ZSTD).
#
#   Checksum: MD5 via HashingContext — the "Don't Hand-Roll" table in RESEARCH.md explicitly
#   forbids CRC-32 (not exposed by Godot 4.6) and calls out HashingContext.HASH_MD5 as the
#   correct substitute. FileAccess.get_md5() is file-path-only; we need an in-memory path.
#
#   Security posture (T-03-01): the load path treats every chunk-delta as untrusted; an MD5
#   mismatch on load returns PackedByteArray() (empty) so the caller can fall back to bak.1.
#
# References:
#   RESEARCH.md §"Contradiction 2" — LZ4 → Zstd substitution
#   RESEARCH.md §"Don't Hand-Roll" — CRC-32-not-available row; HashingContext.HASH_MD5
#   RESEARCH.md §"Architecture Patterns" lines 296-330 — blob checksum contract
#   02-PATTERNS.md §"Persistence (net-new)" — S-1/S-2 SPDX + doc-block conventions

class_name ChunkCodec
extends RefCounted

## Maximum uncompressed chunk size in bytes (1 MiB).
## Callers may override via decode_chunk_delta(blob, max_size).
const MAX_UNCOMPRESSED_BYTES: int = 1 * 1024 * 1024   # 1 MiB

## Size of the MD5 digest prepended to every blob (bytes).
const MD5_BYTES: int = 16

## Size of the compressed-length header that follows the MD5 (bytes).
const LEN_BYTES: int = 4


## Encode a raw chunk-delta payload into the canonical blob format:
##   [16 bytes MD5 of compressed_bytes][4 bytes BE uint32 len][compressed_bytes]
##
## @param payload  Uncompressed serialised chunk data (PackedByteArray).
## @return         Encoded blob ready for SQLite BLOB column storage.
##                 Returns empty PackedByteArray if compression fails.
static func encode_chunk_delta(payload: PackedByteArray) -> PackedByteArray:
	if payload.is_empty():
		return PackedByteArray()

	# Zstd-compress the payload (RESEARCH.md Contradiction 2 — no LZ4 in Godot 4.6).
	var compressed := payload.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty():
		push_error("ChunkCodec.encode_chunk_delta: Zstd compression returned empty result.")
		return PackedByteArray()

	# Compute MD5 of the compressed bytes (in-memory; HashingContext is the cross-platform path).
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(compressed)
	var digest: PackedByteArray = ctx.finish()   # 16 bytes

	# Build the 4-byte big-endian uint32 compressed length header.
	var len_header := PackedByteArray()
	len_header.resize(LEN_BYTES)
	var clen: int = compressed.size()
	len_header[0] = (clen >> 24) & 0xFF
	len_header[1] = (clen >> 16) & 0xFF
	len_header[2] = (clen >> 8)  & 0xFF
	len_header[3] =  clen        & 0xFF

	# Concatenate: [MD5 16 bytes][len 4 bytes][compressed bytes]
	var blob := PackedByteArray()
	blob.append_array(digest)
	blob.append_array(len_header)
	blob.append_array(compressed)
	return blob


## Decode a blob produced by encode_chunk_delta.
##
## @param blob              The raw blob from the SQLite column.
## @param max_uncompressed  Ceiling for Zstd decompression (default MAX_UNCOMPRESSED_BYTES).
## @return                  Original payload bytes, or empty PackedByteArray on error/mismatch.
static func decode_chunk_delta(
		blob: PackedByteArray,
		max_uncompressed: int = MAX_UNCOMPRESSED_BYTES) -> PackedByteArray:

	if not verify_checksum(blob):
		# Mismatch logged inside verify_checksum.
		return PackedByteArray()

	# Extract compressed length from bytes 16..19 (big-endian uint32).
	if blob.size() < MD5_BYTES + LEN_BYTES:
		push_error("ChunkCodec.decode_chunk_delta: blob too short for header.")
		return PackedByteArray()

	var clen: int = (blob[MD5_BYTES]     << 24) \
	              | (blob[MD5_BYTES + 1] << 16) \
	              | (blob[MD5_BYTES + 2] << 8) \
	              |  blob[MD5_BYTES + 3]

	var expected_total: int = MD5_BYTES + LEN_BYTES + clen
	if blob.size() < expected_total:
		push_error("ChunkCodec.decode_chunk_delta: blob is shorter than declared compressed_len (%d)." % clen)
		return PackedByteArray()

	# Slice the compressed bytes and decompress.
	var compressed := blob.slice(MD5_BYTES + LEN_BYTES, MD5_BYTES + LEN_BYTES + clen)
	var payload := compressed.decompress(max_uncompressed, FileAccess.COMPRESSION_ZSTD)
	if payload.is_empty():
		push_error("ChunkCodec.decode_chunk_delta: Zstd decompression failed (max=%d)." % max_uncompressed)
		return PackedByteArray()

	return payload


## Verify the MD5 checksum without decompressing.
##
## @param blob  The raw blob from the SQLite column.
## @return      true if the embedded MD5 matches the actual MD5 of the compressed bytes;
##              false on size error or mismatch.
static func verify_checksum(blob: PackedByteArray) -> bool:
	if blob.size() < MD5_BYTES + LEN_BYTES:
		push_error("ChunkCodec.verify_checksum: blob too short (%d bytes)." % blob.size())
		return false

	# Read the stored MD5 (first 16 bytes).
	var stored_md5 := blob.slice(0, MD5_BYTES)

	# Extract compressed_len.
	var clen: int = (blob[MD5_BYTES]     << 24) \
	              | (blob[MD5_BYTES + 1] << 16) \
	              | (blob[MD5_BYTES + 2] << 8) \
	              |  blob[MD5_BYTES + 3]

	var expected_total: int = MD5_BYTES + LEN_BYTES + clen
	if blob.size() < expected_total:
		push_error("ChunkCodec.verify_checksum: declared compressed_len %d exceeds blob size." % clen)
		return false

	# Recompute MD5 over the compressed bytes.
	var compressed := blob.slice(MD5_BYTES + LEN_BYTES, MD5_BYTES + LEN_BYTES + clen)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(compressed)
	var actual_md5: PackedByteArray = ctx.finish()

	if stored_md5 != actual_md5:
		push_error("ChunkCodec.verify_checksum: MD5 mismatch — blob may be corrupted.")
		return false

	return true
