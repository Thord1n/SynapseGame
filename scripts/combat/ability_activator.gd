class_name AbilityActivator
extends RefCounted
## The "player pressed attack" entry point (Roadmap Priority 2). Resolves the Ability's chain
## via ChainSolver (ability first, then outward along its single output path), folds each
## perk's apply_effect over a shared EffectContext, then applies the final result to a target
## (Roadmap Priority 3 — consuming ChainSolver's output). With no Modifiers connected this is
## just the Ability's own base_damage, which is Priority 2's baseline case. Source effects are
## applied to the target as entries too (DummyTarget.apply_effect_entry, e.g. Shock buildup),
## and Echo's repeats land later (EffectContext.delayed).

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
		var before_delayed := context.delayed.size()
		var before_radius := context.radius
		context.last_was_noop = false
		placed.get_definition().apply_effect(placed.get_level(), context)
		if context.last_was_noop:
			context.noop_perks.append(placed)
			steps.append("%s: no effect (nothing upstream to act on)" % placed.get_definition().display_name)
			continue
		steps.append(_describe_step(
			placed.get_definition().display_name,
			context.damage - before_damage,
			context.target_count - before_targets,
			context.delayed.size() - before_delayed,
			context.radius - before_radius,
		))
	if target:
		apply_to(target, context)
	return {"context": context, "steps": steps}

## Same chain walk with nothing applied to any target: which amplifier perks in the chain
## through ability_position currently do nothing (no source upstream). For greying them out.
func find_noop_perks(board: Board, ability_position: Vector2i) -> Array:
	return activate_with_steps(board, ability_position, null)["context"].noop_perks

## Lands the resolved hit on target now, then each delayed echo after its delay. Delayed hits
## need the SceneTree for timing; without one (shouldn't happen in-game) they land immediately.
static func apply_to(target: DummyTarget, context: EffectContext) -> void:
	target.take_damage(context.damage * context.repeat_count)
	for effect in context.effects:
		target.apply_effect_entry(effect)
	var tree := Engine.get_main_loop() as SceneTree
	for echo in context.delayed:
		if tree:
			tree.create_timer(echo["delay"], false).timeout.connect(_land_echo.bind(target, echo["effects"]))
		else:
			_land_echo(target, echo["effects"])

static func _land_echo(target: DummyTarget, effects: Array) -> void:
	var total := 0.0
	for effect in effects:
		total += effect["damage"]
	target.take_damage(total)
	for effect in effects:
		target.apply_effect_entry(effect)

static func _describe_step(perk_name: String, damage_delta: float, target_delta: int, echo_delta: int, radius_delta: float) -> String:
	var parts := PackedStringArray()
	if damage_delta != 0.0:
		parts.append("+%s damage" % PerkDefinition.format_number(damage_delta))
	if target_delta != 0:
		parts.append("+%d target%s" % [target_delta, "" if target_delta == 1 else "s"])
	if echo_delta != 0:
		parts.append("+%d echo%s" % [echo_delta, "" if echo_delta == 1 else "es"])
	if radius_delta != 0.0:
		parts.append("+%sm radius" % PerkDefinition.format_number(radius_delta))
	if parts.is_empty():
		return "%s: no effect" % perk_name
	return "%s: %s" % [perk_name, ", ".join(parts)]
