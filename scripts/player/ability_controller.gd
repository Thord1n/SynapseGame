class_name AbilityController
extends RefCounted
## Looks up a named Ability perk (by PerkDefinition.id) wherever it's currently placed on the
## board and activates it — the "fixed named abilities" model: Jump/Normal Attack/Special
## Attack/Dash always mean that specific perk, regardless of which of the 5 Ability slots it's
## in (contrast Shield, which is never looked up this way — see PlayerCharacter). Doesn't touch
## input at all; game_gui.gd's _unhandled_input decides *when* to call trigger().

var ability_activator := AbilityActivator.new()

func find_placed(board: Board, perk_id: StringName) -> PlacedPerk:
	for placed in board.get_all_placed_perks():
		if placed.get_definition().id == perk_id:
			return placed
	return null

## Returns the resolved EffectContext, or null if perk_id isn't currently placed anywhere (the
## perk was taken off the board, or was never placed to begin with).
func trigger(board: Board, perk_id: StringName, target: DummyTarget) -> EffectContext:
	var placed := find_placed(board, perk_id)
	if placed == null:
		return null
	return ability_activator.activate(board, placed.position, target)
