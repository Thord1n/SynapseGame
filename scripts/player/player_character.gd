class_name PlayerCharacter
extends Node
## Core player attributes. Health is a flat starting stat — nothing changes it yet, since no
## damage-to-player system exists. Shield has no base of its own; its only source is a placed
## Shield perk (a passive Core perk, Thomas: "a physical shield"; blocking is the separate Block
## ability). recompute_shield_from_board re-derives it fresh from current
## board state rather than storing it speculatively, the same pattern MemorySystem's capacity
## and EffectSolver's old per-perk math both already used.

signal shield_changed(current: int)

const SHIELD_PERK_ID := &"shield"

@export var max_health: int = 100
var current_health: int = max_health

var shield: int = 0

## Sums get_scaled_base_damage() (read here as a shield amount, not damage) across every placed
## perk with id "shield" — ordinarily just 0 or 1 of them, but summed generically rather
## than assuming exactly one. No-ops (no signal) if the total hasn't actually changed.
func recompute_shield_from_board(board: Board) -> void:
	var total := 0
	for placed in board.get_all_placed_perks():
		var definition := placed.get_definition()
		if definition.id == SHIELD_PERK_ID:
			total += definition.get_scaled_base_damage(placed.get_level())
	if total != shield:
		shield = total
		shield_changed.emit(shield)
