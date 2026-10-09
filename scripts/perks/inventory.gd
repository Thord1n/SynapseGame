class_name Inventory
extends Node

## Emitted after any add/remove/merge. GUI layers should treat this as "re-read perks".
signal inventory_changed

var perks: Array[InventoryPerk] = []

func add_perk(perk: InventoryPerk) -> void:
	perks.append(perk)
	inventory_changed.emit()

func remove_perk(perk: InventoryPerk) -> bool:
	var idx := perks.find(perk)
	if idx == -1:
		return false
	perks.remove_at(idx)
	inventory_changed.emit()
	return true

func find_mergeable_partner(perk: InventoryPerk) -> InventoryPerk:
	for other in perks:
		if other != perk and perk.can_merge_with(other):
			return other
	return null

## Merges two matching perks in place, replacing both with the leveled-up result.
func merge(a: InventoryPerk, b: InventoryPerk) -> InventoryPerk:
	if not a.can_merge_with(b):
		return null
	var merged := a.merge_with(b)
	perks.erase(a)
	perks.erase(b)
	perks.append(merged)
	inventory_changed.emit()
	return merged
