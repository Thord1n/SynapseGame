class_name ChainSolver
extends RefCounted
## Given any placed perk's position, walks the single directed chain it belongs to and returns
## every perk in it, head to tail — whichever perk has nothing feeding into its input first,
## then each perk in turn following outputs forward to the end. The perk at the *given*
## position doesn't have to be the head, and doesn't have to be an Ability: an Ability can sit
## anywhere in a chain (start, middle, or end) depending on how the player wired it, and the
## chain resolves the same way regardless of which position in it triggered the resolve.
##
## This matters beyond ordering-for-its-own-sake: it's what lets a perk's effect depend on
## *what already happened earlier in the chain* (AbilityActivator folds apply_effect() over a
## shared EffectContext in this order) — e.g. a future damage-amplifier Modifier connected
## directly upstream of an Ability could scale whatever the Ability contributes, but only if
## the amplifier is guaranteed to resolve before the Ability it's modifying, regardless of the
## Ability being the thing that actually triggered the resolve.
##
## Worked example: Fire(output) -> Ability(input/output) -> Chain(input) resolves to
## [Fire, Ability, Chain] whether you resolve from Fire's position, the Ability's, or Chain's —
## Fire's contribution exists before the Ability's own effect runs, and Chain still runs last.
## (Earlier this session this same layout resolved to [Ability, Fire] with Chain unreachable —
## the Ability was always forced first. That's what this change replaces.)
##
## Since every perk has at most one input and one output, this is always a single straight
## path, never a tree or a cycle — branching is structurally impossible, so there's no tiebreak
## to resolve and no risk of the backward walk looping (see the `visited` guards below, cheap
## insurance rather than a real possibility given the current one-input/one-output model).

func resolve_chain(board: Board, from_position: Vector2i) -> Array[PlacedPerk]:
	var cell := board.get_cell(from_position)
	if cell == null or cell.is_empty():
		return []

	var head := _find_head(cell.occupant)
	var chain: Array[PlacedPerk] = [head]
	var visited := {head.position: true}
	var next := _find_next(head)
	while next != null and not visited.has(next.position):
		chain.append(next)
		visited[next.position] = true
		next = _find_next(next)
	return chain

## Walks backward (via each perk's input side) from `from` until reaching a perk with nothing
## feeding into it — the start of the chain `from` belongs to. Returns `from` itself if it's
## already the head (including the common case of an Ability with nothing connected upstream).
func _find_head(from: PlacedPerk) -> PlacedPerk:
	var current := from
	var visited := {current.position: true}
	var prev := _find_prev(current)
	while prev != null and not visited.has(prev.position):
		current = prev
		visited[current.position] = true
		prev = _find_prev(current)
	return current

## The perk feeding into `placed`'s input, if any (the connection where `placed` is the
## input/to side) — null if nothing connects there.
func _find_prev(placed: PlacedPerk) -> PlacedPerk:
	for connection in placed.connections:
		if connection.perk_b == placed:
			return connection.perk_a
	return null

## The perk `placed`'s output feeds into, if any (the connection where `placed` is the
## output/from side) — null at a chain's dead end.
func _find_next(placed: PlacedPerk) -> PlacedPerk:
	for connection in placed.connections:
		if connection.perk_a == placed:
			return connection.perk_b
	return null
