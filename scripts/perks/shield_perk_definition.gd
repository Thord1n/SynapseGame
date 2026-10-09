class_name ShieldPerkDefinition
extends PerkDefinition
## Shield (and any future perk that grants a passive character stat rather than a combat
## effect) shares this base. base_damage/get_scaled_base_damage still does the level-scaling
## math — PlayerCharacter.recompute_shield_from_board reads that same scaled number directly
## (matched by PerkDefinition.id, not by this subclass) and treats it as a shield amount. This
## subclass exists for two things only: correct tooltip wording ("Shield" instead of "Damage"),
## and making sure a Shield perk never contributes to combat math if a chain ever happens to
## route through it (see apply_effect) — it's a stat source, not a triggerable effect.

func get_tooltip_extra(level: int) -> String:
	return "\nShield: %s" % format_number(get_scaled_base_damage(level))

func apply_effect(_level: int, _context: EffectContext) -> void:
	pass
