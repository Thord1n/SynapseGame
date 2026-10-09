class_name ElementalPerkDefinition
extends PerkDefinition
## Fire, Shock, and Ice share every PerkDefinition field as their common base — input/output
## accepts, memory cost, complexity, scaling exponent, tags. The only thing that distinguishes
## one instance from another is which element it represents.

enum Element { FIRE, SHOCK, ICE }

@export var element: Element = Element.FIRE
## Base damage at level 1. Scales up with level via the same Power/scaling_exponent curve as
## the rest of the system (get_scaled_damage) — this is the unscaled starting value.
@export var damage: float = 0.0

func get_display_color() -> Color:
	return element_color(element)

func get_tooltip_extra(level: int) -> String:
	return "\n%s Damage: +%d" % [element_name(element),get_scaled_damage(level)]

func apply_effect(level: int, context: EffectContext) -> void:
	super(level, context)
	context.damage += get_scaled_damage(level)

## damage * Power^scaling_exponent, rounded up to the nearest integer.
func get_scaled_damage(level: int) -> int:
	var power := PerkDefinition.power_for_level(level)
	return int(ceil(damage * pow(float(power), scaling_exponent)))

static func element_color(element: Element) -> Color:
	match element:
		Element.FIRE: return Color(0.85, 0.2, 0.15)
		Element.ICE: return Color(0.82, 0.86, 0.88)
		Element.SHOCK: return Color(0.55, 0.8, 1.0)
	return Color.WHITE

static func element_name(element: Element) -> String:
	match element:
		Element.FIRE: return "Fire"
		Element.SHOCK: return "Shock"
		Element.ICE: return "Ice"
	return "Unknown"
