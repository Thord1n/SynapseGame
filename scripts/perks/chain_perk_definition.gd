class_name ChainPerkDefinition
extends PerkDefinition
## Chain (and any future spread-the-incoming-effect-to-more-targets modifiers) share this
## base and just set their own chain count.

## How many nearby enemies the incoming effect chains to, at level 1. Scales linearly (+1 per
## level, no Power/exponent curve) — same choice as EchoPerkDefinition.echoes, since both are
## "repeat count" style values rather than a magnitude like damage/radius.
@export var chains: int = 1

func get_tooltip_extra(level: int) -> String:
	return "\nChains: %d" % get_scaled_chains(level)

## An amplifier (default per the Designer, may change): only spreads effects added earlier in
## the chain; with none upstream it does nothing.
func apply_effect(level: int, context: EffectContext) -> void:
	super(level, context)
	if not context.has_upstream_effects():
		context.last_was_noop = true
		return
	context.target_count += get_scaled_chains(level)

func get_scaled_chains(level: int) -> int:
	return chains + (level - 1)
