class_name AreaPerkDefinition
extends PerkDefinition
## Perks whose effect spreads within a radius (Explosion, Linger, and future area-effect
## modifiers) share this base and just set their own radius.

## In meters — the radius at level 1. Not wired into any actual board-space calculation yet.
@export var radius: float = 0.0
## The ceiling get_scaled_radius approaches as level increases (e.g. Explosion aims for 20,
## Linger for 10) — approached asymptotically, never exceeded.
@export var max_radius: float = 20.0

func get_tooltip_extra(level: int) -> String:
	return "\n%s radius: %sm" % [display_name, get_scaled_radius(level)]

func apply_effect(level: int, context: EffectContext) -> void:
	super(level, context)
	context.radius += get_scaled_radius(level)

## Approaches max_radius as level increases (exactly `radius` at level 1, closing the
## remaining gap to max_radius by a factor of Power^scaling_exponent each step), rounded up
## to the nearest integer.
func get_scaled_radius(level: int) -> int:
	var power := PerkDefinition.power_for_level(level)
	var value := max_radius - (max_radius - radius) / pow(float(power), scaling_exponent)
	return int(ceil(value))
