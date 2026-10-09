class_name PerkDefinition
extends Resource

## Structural role. Also drives the placeholder board/inventory symbol color (class_color
## below) until real art exists.
## - CORE: linked to core functionality. Never has an input or output (see get_input_accepts/
##   get_output_accepts) — it never participates in a connection, on either side.
## - ABILITY: a player ability (Jump, Normal Attack, Special Attack, Dash, ...). Has both an
##   input and an output, like Modifier — a Modifier can feed its output into an Ability, not
##   just receive from one. What triggers is still whichever Ability position the player
##   activates (see ChainSolver/AbilityActivator); the input just means it's not required to
##   be the very first thing in a chain.
## - MODIFIER: has both an input and an output, so it can sit mid-chain. Applies its effect to
##   whatever's already accumulated on the EffectContext as the chain is walked (apply_effect).
## - MEMORY: grants board memory capacity while slotted in the dedicated Memory slot (see
##   MemorySystem, MemoryPerkDefinition). Like Core, never has an input or output — it never
##   sits on the board at all, let alone in a chain (Cell.accepts() rejects it outright).
enum PerkClass { CORE, ABILITY, MODIFIER, MEMORY }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var perk_class: PerkClass = PerkClass.ABILITY

@export_group("Connection (side chosen by the player at placement, not here)")
## Which PerkClasses this perk's input side will accept, before class-based enforcement (see
## get_input_accepts). Right default for a Modifier out of the box.
@export var input_accepts: Array[PerkClass] = [PerkClass.ABILITY, PerkClass.MODIFIER]
## Which PerkClasses this perk's output side will accept, before class-based enforcement (see
## get_output_accepts). Right default for a Modifier out of the box.
@export var output_accepts: Array[PerkClass] = [PerkClass.MODIFIER]

@export_group("Effects & Cost")
## Base damage at level 1, scaled via get_scaled_base_damage. This is what gives a plain
## Ability perk (Jump, Normal Attack, ...) its baseline effect; subclasses add their own
## fields on top via apply_effect.
@export var base_damage: float = 0.0
## Memory cost in bytes at level 1 (see InventoryPerk.get_memory_cost) — memory is modeled as
## hard-drive-style storage, so this is a whole number, not a fractional unit.
@export var base_memory: int = 1
## Tunable per definition; lets simple perks stay cheap and mechanically-rich ones cost more.
@export var complexity: float = 1.0
## Sub-linear exponent (~0.6-0.8 recommended). Used for both effect and memory scaling.
@export var scaling_exponent: float = 0.75
@export var tags: Array[StringName] = []

## Core and Memory perks never accept a connection on either side — enforced here rather than
## left as a data-entry convention, so it can't be gotten wrong per-instance. Ability and
## Modifier both have a real input: a Modifier can feed its output into an Ability mid-chain,
## not just the other way around. See get_output_accepts.
func get_input_accepts() -> Array:
	if perk_class == PerkClass.CORE or perk_class == PerkClass.MEMORY:
		return []
	return input_accepts

## Core and Memory perks never accept a connection on either side — see get_input_accepts.
func get_output_accepts() -> Array:
	if perk_class == PerkClass.CORE or perk_class == PerkClass.MEMORY:
		return []
	return output_accepts

## Named perk_class_value, not perk_class — this class already declares an instance property
## called perk_class, and a same-named parameter here (even on a static func, which can't
## actually see instance members) would shadow it.
static func class_color(perk_class_value: PerkClass) -> Color:
	match perk_class_value:
		PerkClass.CORE: return Color(0.75, 0.75, 0.8)
		PerkClass.ABILITY: return Color(0.95, 0.7, 0.2)
		PerkClass.MODIFIER: return Color(0.6, 0.35, 0.85)
		PerkClass.MEMORY: return Color(0.35, 0.85, 0.75)
	return Color.WHITE

## The color PerkSymbol paints this perk's chip. Defaults to the class color; subclasses
## (e.g. ElementalPerkDefinition) override this to show something more specific instead.
func get_display_color() -> Color:
	return class_color(perk_class)

## Extra line(s) appended under the description in the hover tooltip. Shows a Damage line when
## base_damage is set (covers plain Ability perks like Normal Attack); empty otherwise.
## Subclasses (e.g. ElementalPerkDefinition, AreaPerkDefinition) override this entirely to show
## their own type-specific info instead. Takes the owning InventoryPerk's level, since these
## values scale with level but the level itself only exists on InventoryPerk, not here.
func get_tooltip_extra(level: int) -> String:
	if base_damage > 0.0:
		return "\nDamage: %s" % format_number(get_scaled_base_damage(level))
	return ""

## base_damage * Power^scaling_exponent, rounded up to the nearest integer. Same curve as the
## subclass-specific scaled stats (ElementalPerkDefinition.get_scaled_damage, etc).
func get_scaled_base_damage(level: int) -> int:
	var power := power_for_level(level)
	return int(ceil(base_damage * pow(float(power), scaling_exponent)))

## Combat contribution hook: mutates context with this perk's effect at the given level.
## Default just contributes base_damage; subclasses override (calling super() first) to add
## their own field's contribution. Walked by AbilityActivator in ChainSolver's resolved order
## (ability first, then outward along the single output chain).
func apply_effect(level: int, context: EffectContext) -> void:
	context.damage += get_scaled_base_damage(level)

## Clean display formatting for a float — whole numbers show without decimals (5, not
## 5.000000). GDScript's % string operator has no %g specifier, so subclasses should use
## this instead of "%g" % value (which just prints the literal text "%g").
static func format_number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return str(value)

## Power = 2^(level-1), the shared basis for effect/memory/cost scaling across the whole
## perk system (InventoryPerk.get_power(), base_damage scaling, and the level-scaled
## subclass fields like ElementalPerkDefinition.damage).
static func power_for_level(level: int) -> int:
	return 1 << (level - 1)
