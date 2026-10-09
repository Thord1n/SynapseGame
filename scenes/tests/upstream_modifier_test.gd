extends Node
## Regression check for a real user-reported gap: Special Attack in an ability slot, rotated
## once (R); Shock placed adjacent on its LEFT (west), also rotated once (R) — with matching
## rotation on both, Shock's OUTPUT faces east (toward the ability) and the Ability's INPUT
## faces west (toward Shock). A connection forms, but with the Ability on the INPUT side of it
## (Shock feeds the Ability, not the other way around).
##
## ChainSolver.resolve_chain() originally only walked forward from an Ability's own output, so
## this connection was invisible to it — Shock never contributed. A first fix made the
## Ability's own first hop bidirectional (checked both sides), which caught this case but still
## forced the Ability to resolve first always. That's been replaced again: resolve_chain() now
## finds the true HEAD of the whole chain (walking backward until nothing feeds in) and resolves
## head-to-tail, so here Shock is genuinely first (it's upstream, nothing feeds into IT) and the
## Ability second — not because of an Ability-specific rule, just because that's where each one
## sits in the chain. See ChainSolver's docstring for why this generalization matters beyond
## just this one case (future position-sensitive perks, e.g. a pre-Ability damage amplifier).
## Run headless: Godot --headless --path <project> res://scenes/tests/upstream_modifier_test.tscn --quit-after 5

@onready var game_gui: GameGui = $GameGui

func _ready() -> void:
	game_gui.memory_system.slot_perk(_take_from_inventory(&"memory"))

	# Special Attack in an ability slot (column x=2), rotated once: rotation 0 -> 1 (EAST
	# output, WEST input).
	var special_attack := _take_from_inventory(&"special_attack")
	game_gui.board.place_perk(special_attack, Vector2i(2, 2), GridDirection.Value.EAST, GridDirection.Value.WEST)

	# Shock placed one cell to the LEFT (west) of the ability, i.e. at (1, 2), also rotated
	# once the same way: output EAST, input WEST.
	var shock := _take_from_inventory(&"shock")
	game_gui.board.place_perk(shock, Vector2i(1, 2), GridDirection.Value.EAST, GridDirection.Value.WEST)

	var ability_placed: PlacedPerk = game_gui.board.get_cell(Vector2i(2, 2)).occupant
	var shock_placed: PlacedPerk = game_gui.board.get_cell(Vector2i(1, 2)).occupant

	# Does a connection form at all between them?
	var connected := ability_placed.connections.size() > 0 and shock_placed.connections.size() > 0
	_check(connected, "a connection DOES form between them (both show a live connection)")

	# Is the Ability the perk_a (output/from) side, or the perk_b (input/to) side, of it?
	var ability_is_output_side := false
	for c in ability_placed.connections:
		if c.perk_a == ability_placed:
			ability_is_output_side = true
	_check(not ability_is_output_side, "the Ability is the INPUT side of that connection (Shock feeds it, not the other way around)")

	# The resolved chain should include Shock, and — since it's upstream, genuinely the head of
	# this 2-perk chain — Shock resolves FIRST now, the Ability second. Resolving from either
	# perk's position should agree, since resolve_chain() always finds the same head regardless
	# of where in the chain you start from.
	var chain := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(2, 2))
	var chain_from_shock := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(1, 2))
	_check(chain.size() == 2, "resolve_chain() includes Shock (chain size 2) even though it's connected to the Ability's input side")
	if chain.size() == 2:
		_check(chain[0] == shock_placed, "Shock resolves first (it's the head — nothing feeds into it)")
		_check(chain[1] == ability_placed, "the Ability resolves second, since Shock feeds into it")
	_check(chain_from_shock == chain, "resolving from Shock's own position finds the identical chain")

	var result := game_gui.ability_controller.ability_activator.activate_with_steps(game_gui.board, Vector2i(2, 2), DummyTarget.new())
	var steps: Array = result["steps"]
	print("Steps: %s" % [steps])
	_check(steps.size() == 2 and ("Shock" in steps[0]), "Shock's own contribution shows up first in the activation steps")

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

var _pass_count := 0
var _fail_count := 0

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		print("[FAIL] %s" % label)

func _take_from_inventory(id: StringName) -> InventoryPerk:
	for perk in game_gui.inventory.perks:
		if perk.definition.id == id:
			game_gui.inventory.remove_perk(perk)
			return perk
	assert(false, "%s not found in seeded inventory" % id)
	return null
