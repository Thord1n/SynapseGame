class_name PerkConnection
extends RefCounted

## The output/from side of this connection — perk_a's output feeds perk_b's input.
var perk_a: PlacedPerk
## The input/to side of this connection.
var perk_b: PlacedPerk
## Direction from perk_a to perk_b (i.e. perk_a's output_direction).
var direction: GridDirection.Value

func _init(p_perk_a: PlacedPerk = null, p_perk_b: PlacedPerk = null, p_direction: GridDirection.Value = GridDirection.Value.NORTH) -> void:
	perk_a = p_perk_a
	perk_b = p_perk_b
	direction = p_direction

func involves(perk: PlacedPerk) -> bool:
	return perk_a == perk or perk_b == perk

func other(perk: PlacedPerk) -> PlacedPerk:
	if perk_a == perk:
		return perk_b
	if perk_b == perk:
		return perk_a
	return null
