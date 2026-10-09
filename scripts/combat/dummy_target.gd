class_name DummyTarget
extends RefCounted
## Minimum viable target (Roadmap Priority 1) — just enough for AbilityActivator to have
## somewhere to apply a result. Real targeting (position, multiple enemies, "nearby" queries
## for Chain/Explosion) is Roadmap Priority 4.

var target_name: String = "Dummy"
var damage_taken: float = 0.0

func take_damage(amount: float) -> void:
	damage_taken += amount
