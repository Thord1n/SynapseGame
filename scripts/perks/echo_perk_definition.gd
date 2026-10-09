class_name EchoPerkDefinition
extends PerkDefinition
## Echo (and any future repeat-the-incoming-effect modifiers) share this base and just set
## their own echo count.
##
## An amplifier (Thomas's order rule): it repeats the source effects added EARLIER in the chain
## — not the Ability's own base hit — at `echo_strength` of their damage, `echo_delay` seconds
## apart. With nothing upstream it does nothing. Attack -> Fire -> Echo repeats the Fire;
## Attack -> Echo -> Fire repeats nothing.

## How many extra times the incoming effect repeats, at level 1. Scales linearly (+1 per
## level, no Power/exponent curve) — deliberately different from damage/radius scaling.
@export var echoes: int = 1
## Fraction of each upstream effect's damage (and side-effect strength) an echo carries.
@export var echo_strength: float = 0.6
## Seconds between the hit and the first echo, and between consecutive echoes.
@export var echo_delay: float = 0.3

func get_tooltip_extra(level: int) -> String:
	return "\nEchoes: %d" % get_scaled_echoes(level)

func apply_effect(level: int, context: EffectContext) -> void:
	super(level, context)
	if not context.has_upstream_effects():
		context.last_was_noop = true
		return
	var echoed: Array[Dictionary] = []
	for effect in context.effects:
		var copy := effect.duplicate()
		copy["damage"] = effect["damage"] * echo_strength
		copy["strength"] = effect["strength"] * echo_strength
		echoed.append(copy)
	for i in get_scaled_echoes(level):
		context.delayed.append({"delay": echo_delay * (i + 1), "effects": echoed})

func get_scaled_echoes(level: int) -> int:
	return echoes + (level - 1)
