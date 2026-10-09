class_name EffectContext
extends RefCounted
## Shared mutable state folded over an Ability's resolved chain (see AbilityActivator,
## ChainSolver). Each perk's apply_effect() reads and adds to whatever's already here, in
## chain order — heterogeneous fields rather than one uniform number, since Chain/Echo are
## multipliers, not damage.

var damage: float = 0.0
## How many targets the final effect hits. Recorded but inert until a real target model
## (Roadmap Priority 4) exists to hit more than the one DummyTarget.
var target_count: int = 1
## How many extra times the final effect repeats (Echo).
var repeat_count: int = 1
## Recorded but inert until Priority 4 gives it something spatial to act on.
var radius: float = 0.0
