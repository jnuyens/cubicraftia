# SPDX-FileCopyrightText: 2026 Cubicraftia contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# test_iap_stub.gd — DOC-00: IAP stub never charges, never persists state
#
# Verifies the three core contracts of the Iap autoload in Phase 1:
#   1. is_available() returns false (no billing SDK wired up)
#   2. get_products() returns an empty Array[Dictionary]
#   3. purchase() returns false (and emits a push_warning internally)
#
# Referenced DOC: DOC-00 — "IAP brick-pack stub exists (typed empty registry)"
# See: DOCS.md §0, RESEARCH.md Code Examples → IAP brick-pack stub
extends GutTest


func test_iap_is_not_available() -> void:
	## In Phase 1, no platform billing SDK is wired — Iap.is_available() is false.
	assert_false(Iap.is_available(), "Iap.is_available() must return false in Phase 1 (DOC-00)")


func test_iap_get_products_returns_empty_array() -> void:
	## In Phase 1, the product registry is empty.
	var products := Iap.get_products()
	assert_not_null(products, "Iap.get_products() must not return null")
	assert_eq(products.size(), 0, "Iap.get_products() must return an empty array in Phase 1")


func test_iap_purchase_returns_false() -> void:
	## Iap.purchase() must return false in Phase 1 — no transaction is ever initiated.
	var result := Iap.purchase("cubicraftia.test_pack")
	assert_false(result, "Iap.purchase() must return false in Phase 1 (DOC-00)")


func test_iap_purchase_any_id_returns_false() -> void:
	## Iap.purchase() returns false for any product ID (not just unknown ones).
	for product_id: String in ["any_pack", "castle_pack", "cubicraftia.space_pack", ""]:
		var result := Iap.purchase(product_id)
		assert_false(
			result,
			"Iap.purchase('%s') must return false in Phase 1" % product_id
		)


func test_iap_product_schema_is_defined() -> void:
	## The PRODUCT_SCHEMA constant must exist on the Iap autoload.
	## This guarantees Plans 05-06 can reference the type shape.
	assert_true(
		"PRODUCT_SCHEMA" in Iap,
		"Iap.PRODUCT_SCHEMA constant must be defined (DOC-00 — typed registry)"
	)
	assert_eq(
		typeof(Iap.PRODUCT_SCHEMA),
		TYPE_DICTIONARY,
		"Iap.PRODUCT_SCHEMA must be a Dictionary"
	)
