# The demo's inventory: an array of item Resources, filled from the player's
# active Haiven item entitlements.
extends RefCounted

const Item := preload("demo_item.gd")

## The entitlement kind that is an inventory item (the game service KindItem).
const ITEM_KIND := "item"
## The state of a held benefit (the game service StateActive).
const ACTIVE_STATE := "active"

signal changed

var items: Array[Resource] = []


func codes() -> PackedStringArray:
	var result := PackedStringArray()
	for item: Resource in items:
		result.append(item.code)
	return result


## Codes of active item entitlements in an AccountEntitlementsResponse that are
## not in `held`, in response order and once each. Subscriptions and founder
## status are not items.
static func newly_active_items(response: Variant, held: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	if not response is Dictionary or not response.get("entitlements") is Array:
		return result
	for entitlement: Variant in response["entitlements"]:
		if not entitlement is Dictionary:
			continue
		var code := str(entitlement.get("code", ""))
		if code == "" or entitlement.get("kind") != ITEM_KIND or entitlement.get("state") != ACTIVE_STATE:
			continue
		if held.has(code) or result.has(code):
			continue
		result.append(code)
	return result


## Adds every new active item; returns the codes added.
func grant_from(response: Variant) -> PackedStringArray:
	var added := newly_active_items(response, codes())
	for code: String in added:
		var item := Item.new()
		item.code = code
		items.append(item)
	if not added.is_empty():
		changed.emit()
	return added


## Drops every item so the next account does not keep this one's inventory.
func clear() -> void:
	if items.is_empty():
		return
	items.clear()
	changed.emit()
