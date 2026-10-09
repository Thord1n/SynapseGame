class_name EffectContext
extends RefCounted
## Shared mutable state folded over an Ability's resolved chain (see AbilityActivator,
## ChainSolver). Each perk's apply_effect() reads and adds to whatever's already here, in
## chain order — so a perk can act on what came before it (Thomas's order rule).
##
## Two kinds of modifier (design/answers-for-programmer.md):
## - Sources (Fire, Ice, Shock) add an entry to `effects` and work anywhere.
## - Amplifiers (Echo, Linger) only act on `effects` added earlier in the chain. With
##   none upstream they do nothing and mark themselves in `noop_perks`, so the UI can grey
##   them out. The Ability's own base hit is NOT an effect (it only adds to `damage`).
## Explosion and Chain are neither: they work on the plain hit and carry whatever is upstream.

## Immediate damage: the Ability's base hit plus every source's damage, in one hit.
var damage: float = 0.0
## How many targets the final effect hits. Recorded but inert until a real target model
## (Roadmap Priority 4) exists to hit more than the one DummyTarget.
var target_count: int = 1
## Kept for callers that still multiply by it; nothing raises it any more (Echo now schedules
## delayed repeats instead, see `delayed`).
var repeat_count: int = 1
## Recorded but inert until Priority 4 gives it something spatial to act on.
var radius: float = 0.0

## Source effects added so far, in chain order. Each: {"id": StringName, "element": int,
## "damage": float, "strength": float}. strength scales on-hit side effects like Shock buildup.
var effects: Array[Dictionary] = []
## Effects to re-apply later (Echo). Each: {"delay": float, "effects": Array[Dictionary]}.
var delayed: Array[Dictionary] = []
## Amplifier perks that had nothing upstream to act on (PlacedPerk, filled by AbilityActivator).
var noop_perks: Array = []
## Set by an amplifier's apply_effect when it found nothing to act on; AbilityActivator reads
## and clears it after each perk.
var last_was_noop := false

func add_effect(id: StringName, element: int, effect_damage: float, strength: float = 1.0) -> void:
	effects.append({"id": id, "element": element, "damage": effect_damage, "strength": strength})
	damage += effect_damage

func has_upstream_effects() -> bool:
	return not effects.is_empty()
