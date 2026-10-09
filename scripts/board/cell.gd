class_name Cell
extends RefCounted

var position: Vector2i
var occupant: PlacedPerk = null
## Only meaningful value right now is PerkDefinition.PerkClass.ABILITY ("this is an ability
## slot"); null means unrestricted. See accepts() — the rule is asymmetric, not an exact-match
## filter: Ability perks require an ability slot, but every other board-eligible class is
## welcome anywhere, ability slots included.
var required_class = null

func _init(p_position: Vector2i = Vector2i.ZERO) -> void:
	position = p_position

func is_empty() -> bool:
	return occupant == null

## Memory perks never go on the board at all — they only ever go in MemorySystem's dedicated
## slot (a separate mechanism entirely, see game_gui.gd's memory slot UI), regardless of
## required_class. Ability perks require an ability slot; everything else board-eligible
## (Core, Modifier) is welcome anywhere, ability slots included.
func accepts(definition: PerkDefinition) -> bool:
	if definition.perk_class == PerkDefinition.PerkClass.MEMORY:
		return false
	if definition.perk_class == PerkDefinition.PerkClass.ABILITY:
		return required_class == PerkDefinition.PerkClass.ABILITY
	return true
