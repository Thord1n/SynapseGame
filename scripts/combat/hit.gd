class_name Hit
extends RefCounted
## One incoming attack, as the defender sees it. Enemy attacks build one of these and hand it to
## PlayerController.receive_hit(), which decides how it resolves (see Result). Kept separate
## from DummyTarget/EffectContext (the perk-chain side) because it describes damage flowing
## TO the player, not from a perk chain.

## Telegraph colors from the design doc (design/answers-for-programmer.md §3).
enum Kind {
	PARRYABLE,   ## White flash: can be blocked, parried or dodged.
	UNBLOCKABLE, ## Red flash: must be dodged. Block takes full damage and parry fails.
}

## How receive_hit() resolved the hit.
enum Result { HIT, BLOCKED, PARRIED, DODGED, IGNORED }

var damage: float
var kind: Kind
## Whoever threw it (an Enemy, usually) — lets the defender react back, e.g. posture damage on
## a parry later on. May be null.
var source: Node

func _init(p_damage: float = 0.0, p_kind: Kind = Kind.PARRYABLE, p_source: Node = null) -> void:
	damage = p_damage
	kind = p_kind
	source = p_source

static func result_name(result: Result) -> String:
	return Result.keys()[result].capitalize()
