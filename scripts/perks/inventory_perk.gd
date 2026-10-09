class_name InventoryPerk
extends RefCounted

var definition: PerkDefinition
var level: int = 1

func _init(p_definition: PerkDefinition = null, p_level: int = 1) -> void:
	definition = p_definition
	level = p_level

## Power = 2^(level-1), the shared basis for effect and memory scaling.
func get_power() -> int:
	return PerkDefinition.power_for_level(level)

func can_merge_with(other: InventoryPerk) -> bool:
	return other != null and other.definition == definition and other.level == level

func merge_with(other: InventoryPerk) -> InventoryPerk:
	assert(can_merge_with(other), "InventoryPerk.merge_with: perks are not mergeable")
	return InventoryPerk.new(definition, level + 1)

## Rounded up to the nearest whole byte — memory is hard-drive-style storage, so a fractional
## cost doesn't mean anything, same rounding direction as the level-scaled stat getters.
func get_memory_cost() -> int:
	if definition == null:
		return 0
	var scaled := float(definition.base_memory) * definition.complexity * pow(2.0, float(level - 1) * definition.scaling_exponent)
	return int(ceil(scaled))
