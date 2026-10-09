extends Node
## Checks a 3-perk chain: Ability -> Fire -> Fire (two separate Fire instances chained in
## sequence). User report: the second Fire doesn't apply. Run headless:
## Godot --headless --path <project> res://scenes/tests/three_perk_chain_test.tscn --quit-after 5

@onready var game_gui: GameGui = $GameGui

func _ready() -> void:
	game_gui.memory_system.slot_perk(_take_from_inventory(&"memory"))

	# Ability at (2,2), output EAST -> Fire1 at (3,2), input WEST/output EAST -> Fire2 at
	# (4,2), input WEST. A straight horizontal line, each perk's output facing the next one's
	# input correctly.
	var ability := _take_from_inventory(&"normal_attack")
	game_gui.board.place_perk(ability, Vector2i(2, 2), GridDirection.Value.EAST, GridDirection.Value.WEST)

	var fire1 := _take_from_inventory(&"fire")
	game_gui.board.place_perk(fire1, Vector2i(3, 2), GridDirection.Value.EAST, GridDirection.Value.WEST)

	var fire2 := _take_from_inventory(&"fire")
	game_gui.board.place_perk(fire2, Vector2i(4, 2), GridDirection.Value.EAST, GridDirection.Value.WEST)

	var ability_placed: PlacedPerk = game_gui.board.get_cell(Vector2i(2, 2)).occupant
	var fire1_placed: PlacedPerk = game_gui.board.get_cell(Vector2i(3, 2)).occupant
	var fire2_placed: PlacedPerk = game_gui.board.get_cell(Vector2i(4, 2)).occupant

	_check(ability_placed.connections.size() == 1, "Ability has exactly 1 connection")
	_check(fire1_placed.connections.size() == 2, "Fire1 has exactly 2 connections (one to Ability, one to Fire2)")
	_check(fire2_placed.connections.size() == 1, "Fire2 has exactly 1 connection (to Fire1)")

	var chain := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(2, 2))
	_check(chain.size() == 3, "resolve_chain size is 3 (Ability, Fire1, Fire2)")
	if chain.size() == 3:
		_check(chain[0] == ability_placed, "chain[0] is the Ability")
		_check(chain[1] == fire1_placed, "chain[1] is Fire1")
		_check(chain[2] == fire2_placed, "chain[2] is Fire2")

	var result := game_gui.ability_controller.ability_activator.activate_with_steps(game_gui.board, Vector2i(2, 2), DummyTarget.new())
	var steps: Array = result["steps"]
	print("Steps: %s" % [steps])
	_check(steps.size() == 3, "3 activation steps")
	var context: EffectContext = result["context"]
	print("Total damage: %s" % context.damage)

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
