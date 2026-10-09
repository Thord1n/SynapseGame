class_name EchoPerkDefinition
extends PerkDefinition
## Echo (and any future repeat-the-incoming-effect modifiers) share this base and just set
## their own echo count.

## How many extra times the incoming effect repeats, at level 1. Scales linearly (+1 per
## level, no Power/exponent curve) — deliberately different from damage/radius scaling.
@export var echoes: int = 1

func get_tooltip_extra(level: int) -> String:
	return "\nEchoes: %d" % get_scaled_echoes(level)

func apply_effect(level: int, context: EffectContext) -> void:
	super(level, context)
	context.repeat_count += get_scaled_echoes(level)

func get_scaled_echoes(level: int) -> int:
	return echoes + (level - 1)
