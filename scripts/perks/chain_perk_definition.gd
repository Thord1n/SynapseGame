class_name ChainPerkDefinition
extends PerkDefinition
## Chain (and any future spread-the-incoming-effect-to-more-targets modifiers) share this
## base and just set their own chain count.

## How many nearby enemies the incoming effect chains to, at level 1. Scales linearly (+1 per
## level, no Power/exponent curve) — same choice as EchoPerkDefinition.echoes, since both are
## "repeat count" style values rather than a magnitude like damage/radius.
@export var chains: int = 1
## False (Thomas): Chain works on the plain hit and also spreads anything upstream, like
## Explosion. Set true to make it an amplifier that does nothing without a source upstream.
@export var needs_upstream_effect: bool = false

func get_tooltip_extra(level: int) -> String:
	return "\nChains: %d" % get_scaled_chains(level)

func apply_effect(level: int, context: EffectContext) -> void:
	super(level, context)
	if needs_upstream_effect and not context.has_upstream_effects():
		context.last_was_noop = true
		return
	context.target_count += get_scaled_chains(level)

func get_scaled_chains(level: int) -> int:
	return chains + (level - 1)
