class_name BlockPerkDefinition
extends PerkDefinition
## Block, the Block button's ability (Thomas: one button, hold = block, a press just before a hit
## = parry). Its chain fires on a parry (TriggerRouter). Its level sets the Guard meter's
## maximum: base_damage/get_scaled_base_damage does the level scaling and is read as max Guard,
## never as damage, so apply_effect adds no base hit to the chain. No Block placed: no block,
## no parry. Not to be confused with Shield, a passive Core perk (ShieldPerkDefinition).

const ID := &"block"

func get_tooltip_extra(level: int) -> String:
	return "\nMax Guard: %s" % format_number(get_scaled_base_damage(level))

func apply_effect(_level: int, _context: EffectContext) -> void:
	pass

## Max Guard granted by the Block perks on the board (0 when none is placed).
static func max_guard_on(board: Board) -> float:
	var total := 0.0
	for placed in board.get_all_placed_perks():
		var definition := placed.get_definition()
		if definition.perk_class == PerkDefinition.PerkClass.ABILITY and definition.id == ID:
			total += definition.get_scaled_base_damage(placed.get_level())
	return total
