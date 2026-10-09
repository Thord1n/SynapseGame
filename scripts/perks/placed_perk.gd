class_name PlacedPerk
extends RefCounted

var inventory_perk: InventoryPerk
var position: Vector2i
## Which side is this perk's output/input, chosen by the player at placement time (see
## game_gui.gd's rotation handling). -1 means "none" — always the case for Core perks, and
## for a perk's input if it's an Ability (see PerkDefinition.get_input_accepts).
var output_direction: int = -1
var input_direction: int = -1
## Cached; only meaningful while placed. Populated by ConnectionSolver, never by hand.
var connections: Array[PerkConnection] = []

func _init(p_inventory_perk: InventoryPerk = null, p_position: Vector2i = Vector2i.ZERO, p_output_direction: int = -1, p_input_direction: int = -1) -> void:
	inventory_perk = p_inventory_perk
	position = p_position
	output_direction = p_output_direction
	input_direction = p_input_direction

func get_definition() -> PerkDefinition:
	return inventory_perk.definition if inventory_perk else null

func get_level() -> int:
	return inventory_perk.level if inventory_perk else 0

func has_output() -> bool:
	return output_direction != -1

func has_input() -> bool:
	return input_direction != -1

## Directions (relative to this perk) that currently have a live connection. PerkConnection's
## `direction` is always the OUTPUT side's direction (perk_a -> perk_b, see PerkConnection) —
## when this perk is perk_a that's already its own frame of reference, but when this perk is
## perk_b (the input side), the stored direction points the other way (toward perk_a, out of
## perk_b), so it has to be flipped to land on this perk's own input_direction.
func get_connected_directions() -> Array[GridDirection.Value]:
	var directions: Array[GridDirection.Value] = []
	for connection in connections:
		if connection.perk_a == self:
			directions.append(connection.direction)
		else:
			directions.append(GridDirection.opposite(connection.direction))
	return directions
