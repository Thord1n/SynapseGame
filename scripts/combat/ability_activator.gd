class_name AbilityActivator
extends RefCounted
## The "player pressed attack" entry point (Roadmap Priority 2). Resolves the Ability's chain
## via ChainSolver (ability first, then outward along its single output path), folds each
## perk's apply_effect over a shared EffectContext, then applies the final result to a target
## (Roadmap Priority 3 — consuming ChainSolver's output). With no Modifiers connected this is
## just the Ability's own base_damage, which is Priority 2's baseline case.

var chain_solver := ChainSolver.new()

func activate(board: Board, ability_position: Vector2i, target: DummyTarget) -> EffectContext:
	return activate_with_steps(board, ability_position, target)["context"]

## Same as activate(), but also returns a per-perk breakdown of what each step in the chain
## actually contributed — e.g. ["Normal Attack: +10 damage", "Fire: +5 damage", "Chain: +1
## target"] — by snapshotting the shared EffectContext before/after each apply_effect() call.
## Kept separate from activate() (which just discards the "steps" key) so existing callers that
## only want the final result (test_harness.gd) don't have to unpack a Dictionary.
func activate_with_steps(board: Board, ability_position: Vector2i, target: DummyTarget) -> Dictionary:
	var context := EffectContext.new()
	var steps: Array[String] = []
	for placed in chain_solver.resolve_chain(board, ability_position):
		var before_damage := context.damage
		var before_targets := context.target_count
		var before_repeats := context.repeat_count
		var before_radius := context.radius
		placed.get_definition().apply_effect(placed.get_level(), context)
		steps.append(_describe_step(
			placed.get_definition().display_name,
			context.damage - before_damage,
			context.target_count - before_targets,
			context.repeat_count - before_repeats,
			context.radius - before_radius,
		))
	if target:
		target.take_damage(context.damage * context.repeat_count)
	return {"context": context, "steps": steps}

static func _describe_step(perk_name: String, damage_delta: float, target_delta: int, repeat_delta: int, radius_delta: float) -> String:
	var parts := PackedStringArray()
	if damage_delta != 0.0:
		parts.append("+%s damage" % PerkDefinition.format_number(damage_delta))
	if target_delta != 0:
		parts.append("+%d target%s" % [target_delta, "" if target_delta == 1 else "s"])
	if repeat_delta != 0:
		parts.append("+%d hit%s" % [repeat_delta, "" if repeat_delta == 1 else "s"])
	if radius_delta != 0.0:
		parts.append("+%sm radius" % PerkDefinition.format_number(radius_delta))
	if parts.is_empty():
		return "%s: no effect" % perk_name
	return "%s: %s" % [perk_name, ", ".join(parts)]
