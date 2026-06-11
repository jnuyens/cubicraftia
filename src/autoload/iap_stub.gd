# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# iap_stub.gd — IAP (In-App Purchase) stub per DOCS.md §0
#
# Registered as autoload "Iap" in project.godot.
#
# Phase 1: typed empty registry + no-op handlers.
# Phase 5 wires actual platform billing SDKs (Apple StoreKit, Google Play Billing).
# This stub NEVER charges the user, NEVER persists state, and always returns false.
#
# Settings menu (Plan 06) renders Iap.get_products() as a "Brick Packs" list
# with a tr("ui.settings.iap.coming_later") subtitle when get_products().size() == 0.
extends Node

## Schema for a brick-pack product (DOCS.md §3.1 IAP brick packs).
## In Phase 1 the registry is empty; the type shape is what matters for
## type-safe code in Plans 05-06.
const PRODUCT_SCHEMA: Dictionary = {
	"product_id":   TYPE_STRING,              # e.g. "cubicraftia.castle_pack"
	"display_name": TYPE_STRING,              # tr() key
	"price_cents":  TYPE_INT,                 # 0 in Phase 1; populated by SDK at runtime
	"currency":     TYPE_STRING,              # "USD" / "EUR" / etc.
	"brick_ids":    TYPE_PACKED_STRING_ARRAY, # brick IDs included in the pack
}

## Empty in Phase 1 — populated by the platform billing SDK in Phase 5.
var products: Array[Dictionary] = []


## Returns true if the in-app purchase system is available on this platform.
## Phase 1: always false (no billing SDK wired up).
func is_available() -> bool:
	return false


## Attempts to purchase the given product.
## Phase 1: always returns false and emits a push_warning.
## Phase 5 replaces this with the real platform flow.
func purchase(_product_id: String) -> bool:
	push_warning("IAP not available in v1 Phase 1 — billing SDK lands in Phase 5.")
	return false


## Returns a copy of the current product registry.
## Phase 1: always returns an empty Array[Dictionary].
func get_products() -> Array[Dictionary]:
	return products.duplicate()
