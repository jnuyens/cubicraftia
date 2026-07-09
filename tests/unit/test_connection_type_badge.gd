# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_connection_type_badge.gd: Unit tests for the ICE candidate-type-to-connection-type
# heuristic (RELY-05 backend).
#
# Godot's WebRTCPeerConnection has no selected-candidate-pair / getStats API, so
# get_connection_type() classifies a peer's connection as "direct" or "relay" from the
# set of ICE candidate types (host / srflx / relay) ever seen for that peer. This is an
# explicitly acknowledged heuristic: its real-world accuracy is validated on real
# devices in Phase 12 (NETVAL-04); these tests only prove internal consistency against
# known candidate strings.
#
# Anchors:
#   13-04-PLAN.md Task 2
#   13-UI-SPEC.md Surface C - honest-badge requirement + Phase-12 scope boundary
#   RESEARCH.md ARCHITECTURE.md line ~161 - ICE candidate type instrumentation note

extends GutTest

const NetworkManagerScript := preload("res://src/autoload/network_manager.gd")

var _nm: Node = null


func before_each() -> void:
	# Off-tree: no add_child, mirroring test_keepalive_logic.gd conventions.
	# _track_ice_candidate_type() / get_connection_type() are pure Dictionary logic
	# with no scene-tree or multiplayer dependency.
	_nm = NetworkManagerScript.new()


func after_each() -> void:
	if is_instance_valid(_nm):
		_nm.free()
	_nm = null


## test_host_candidate_classifies_as_direct: a single "typ host" candidate is enough
## to classify the peer's connection as "direct".
func test_host_candidate_classifies_as_direct() -> void:
	_nm._track_ice_candidate_type(5, "candidate:1 1 udp 12345 1.2.3.4 9 typ host")
	assert_eq(_nm.get_connection_type(5), "direct",
		"A host-typed ICE candidate must classify the connection as direct")


## test_relay_only_candidate_classifies_as_relay: a peer that only ever produced a
## relay-typed candidate is classified as "relay".
func test_relay_only_candidate_classifies_as_relay() -> void:
	_nm._track_ice_candidate_type(6, "candidate:1 1 udp 12345 5.6.7.8 9 typ relay raddr 0.0.0.0 rport 0")
	assert_eq(_nm.get_connection_type(6), "relay",
		"A relay-only ICE candidate history must classify the connection as relay")


## test_untracked_peer_classifies_as_unknown: a peer_id with no tracked candidates at
## all returns "unknown" (never alarm the player without evidence).
func test_untracked_peer_classifies_as_unknown() -> void:
	assert_eq(_nm.get_connection_type(99), "unknown",
		"A peer with no tracked ICE candidates must classify as unknown")


## test_srflx_after_relay_still_classifies_as_direct: srflx/host presence always wins
## over relay-only, even if a relay candidate was seen first.
func test_srflx_after_relay_still_classifies_as_direct() -> void:
	_nm._track_ice_candidate_type(7, "candidate:1 1 udp 12345 5.6.7.8 9 typ relay raddr 0.0.0.0 rport 0")
	assert_eq(_nm.get_connection_type(7), "relay",
		"Before the srflx candidate arrives, the peer must classify as relay")
	_nm._track_ice_candidate_type(7, "candidate:2 1 udp 23456 9.9.9.9 10 typ srflx raddr 0.0.0.0 rport 0")
	assert_eq(_nm.get_connection_type(7), "direct",
		"An srflx candidate seen after a relay candidate must upgrade the classification to direct")
