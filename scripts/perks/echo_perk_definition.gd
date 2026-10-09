class_name EchoPerkDefinition
extends PerkDefinition
## Echo (and any future repeat-the-incoming-effect modifiers) share this base and just set
## their own echo count.
##
## An amplifier (Thomas's order rule): it repeats the source effects added EARLIER in the chain
## — not the Ability's own base hit, and never another Echo's bounces (those live in
## `context.delayed`, not `context.effects`, so two Echoes add up instead of compounding).
## With nothing upstream it does nothing. Attack -> Fire -> Echo repeats the Fire;
## Attack -> Echo -> Fire repeats nothing.
##
## Like a real echo (Thomas): level N gives N bounces, `echo_delay` seconds apart. Bounce 1
## carries `echo_strength` of the source effect and each later bounce `echo_decay` of the one
## before (70%, 49%, 34%, ...).

## Bounces at level 1. Scales linearly (+1 per level, no Power/exponent curve) — deliberately
## different from damage/radius scaling.
@export var echoes: int = 1
## Fraction of each upstream effect's damage (and side-effect strength) the first bounce carries.
@export var echo_strength: float = 0.7
## Each later bounce carries this fraction of the previous one.
@export var echo_decay: float = 0.7
## Seconds between the hit and the first bounce, and between consecutive bounces.
@export var echo_delay: float = 0.3

func get_tooltip_extra(level: int) -> String:
	return "\nEchoes: %d" % get_scaled_echoes(level)

func apply_effect(level: int, context: EffectContext) -> void:
	super(level, context)
	if not context.has_upstream_effects():
		context.last_was_noop = true
		return
	for i in get_scaled_echoes(level):
		var factor := bounce_factor(i)
		var echoed: Array[Dictionary] = []
		for effect in context.effects:
			var copy := effect.duplicate()
			copy["damage"] = effect["damage"] * factor
			copy["strength"] = effect["strength"] * factor
			echoed.append(copy)
		context.delayed.append({"delay": echo_delay * (i + 1), "effects": echoed})

## Fraction of the source effect bounce `index` (0 = first) carries.
func bounce_factor(index: int) -> float:
	return echo_strength * pow(echo_decay, index)

func get_scaled_echoes(level: int) -> int:
	return echoes + (level - 1)
