class_name AreaPerkDefinition
extends PerkDefinition
## Perks whose effect spreads within a radius (Explosion, Linger, and future area-effect
## modifiers) share this base and just set their own radius.
##
## Explosion works on the plain hit and carries anything upstream (Thomas). Linger is an
## amplifier by default (Designer, may change): set needs_upstream_effect and it does nothing
## unless a source effect comes earlier in the chain.

## In meters — the radius at level 1. Not wired into any actual board-space calculation yet.
@export var radius: float = 0.0
## The ceiling get_scaled_radius approaches as level increases (e.g. Explosion aims for 20,
## Linger for 10) — approached asymptotically, never exceeded.
@export var max_radius: float = 20.0
## True for amplifiers (Linger): no source effect upstream means no effect at all.
@export var needs_upstream_effect: bool = false

func get_tooltip_extra(level: int) -> String:
	return "\n%s radius: %sm" % [display_name, get_scaled_radius(level)]

func apply_effect(level: int, context: EffectContext) -> void:
	super(level, context)
	if needs_upstream_effect and not context.has_upstream_effects():
		context.last_was_noop = true
		return
	context.radius += get_scaled_radius(level)

## Approaches max_radius as level increases (exactly `radius` at level 1, closing the
## remaining gap to max_radius by a factor of Power^scaling_exponent each step), rounded up
## to the nearest integer.
func get_scaled_radius(level: int) -> int:
	var power := PerkDefinition.power_for_level(level)
	var value := max_radius - (max_radius - radius) / pow(float(power), scaling_exponent)
	return int(ceil(value))
