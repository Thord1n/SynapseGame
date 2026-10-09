class_name DummyTarget
extends RefCounted
## Minimum viable target (Roadmap Priority 1) — just enough for AbilityActivator to have
## somewhere to apply a result. Real targeting (position, multiple enemies, "nearby" queries
## for Chain/Explosion) is Roadmap Priority 4.

## Fired for every hit, including delayed ones (Echo), so whatever owns this target (Enemy) can
## react without polling.
signal damaged(amount: float)
## A source effect (EffectContext.effects entry) landed: {"id", "element", "damage",
## "strength"}. Enemy uses it for Shock buildup.
signal effect_applied(effect: Dictionary)

var target_name: String = "Dummy"
var damage_taken: float = 0.0

func take_damage(amount: float) -> void:
	damage_taken += amount
	damaged.emit(amount)

func apply_effect_entry(effect: Dictionary) -> void:
	effect_applied.emit(effect)
