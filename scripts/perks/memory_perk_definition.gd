class_name MemoryPerkDefinition
extends PerkDefinition
## Memory grants board memory capacity while slotted in MemorySystem's dedicated slot — never
## placed on the board (Cell.accepts() rejects PerkClass.MEMORY outright), never part of a
## chain. Reuses base_damage/get_scaled_base_damage for the level-scaled number rather than
## adding a parallel field — same reuse ShieldPerkDefinition already established — but
## interpreted as "memory capacity granted," not damage. scaling_exponent = 1.0 on the .tres
## content is what makes get_scaled_base_damage() double per level (Power^1.0 = Power exactly);
## this class doesn't hardcode that, content controls the curve like everywhere else.
##
## MemorySystem.get_capacity() reads this value directly off whichever perk is currently
## slotted (0 if none) rather than routing through the chain/apply_effect system at all — a
## Memory perk never participates in a chain, so apply_effect is a no-op override here, same
## pattern as ShieldPerkDefinition, so it can never leak into combat math either.

func get_tooltip_extra(level: int) -> String:
	return "\nMemory: %s bytes" % format_number(get_scaled_base_damage(level))

func apply_effect(_level: int, _context: EffectContext) -> void:
	pass
