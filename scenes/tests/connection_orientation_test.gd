extends Node
## Diagnoses a user report: "connected Fire to Normal Attack" but the combat log only shows
## Normal Attack's own damage, not Fire's. Checks whether that's a code bug or an orientation
## mismatch (a fresh perk defaults to output=NORTH/input=SOUTH — see game_gui.gd's rotation
## comments — so two perks placed as HORIZONTAL neighbors won't connect unless one of them is
## rotated first; VERTICAL neighbors connect with zero rotation, by coincidence of the default).
## Run headless: Godot --headless --path <project> res://scenes/tests/connection_orientation_test.tscn --quit-after 5

@onready var game_gui: GameGui = $GameGui

func _ready() -> void:
	# Case A: vertical neighbors, default rotation (0) on both — should connect, since default
	# output=NORTH and default input=SOUTH line up for a perk placed directly above another.
	var normal_attack_a := _take_from_inventory(&"normal_attack")
	game_gui.board.place_perk(normal_attack_a, Vector2i(2, 2), GridDirection.Value.NORTH)
	var fire_a := _take_from_inventory(&"fire")
	game_gui.board.place_perk(fire_a, Vector2i(2, 1), GridDirection.Value.NORTH, GridDirection.Value.SOUTH)
	var chain_a := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(2, 2))
	_check(chain_a.size() == 2, "vertical neighbors, both default rotation -> connects (chain size 2)")

	# Case B: horizontal neighbors (Ability at a valid ability slot, Modifier one cell west of
	# it — Modifiers can go anywhere, so this is a legal placement), default rotation (0) on
	# both — should NOT connect, since the Ability's output faces north, not west, so nothing
	# is there for Fire's south-facing input to receive from.
	var normal_attack_b := _take_from_inventory(&"normal_attack")
	game_gui.board.place_perk(normal_attack_b, Vector2i(2, 3), GridDirection.Value.NORTH)
	var fire_b := _take_from_inventory(&"fire")
	game_gui.board.place_perk(fire_b, Vector2i(1, 3), GridDirection.Value.NORTH, GridDirection.Value.SOUTH)
	var chain_b := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(2, 3))
	_check(chain_b.size() == 1, "horizontal neighbors, both default rotation -> does NOT connect (chain size 1)")

	# Case C: same horizontal neighbors, but correctly rotated this time (Ability output west,
	# Modifier input east) — should connect.
	game_gui.board.remove_perk(Vector2i(1, 3))
	game_gui.board.place_perk(fire_b, Vector2i(1, 3), GridDirection.Value.NORTH, GridDirection.Value.EAST)
	var chain_c := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(2, 3))
	_check(chain_c.size() == 1, "still not connected after only fixing Fire's input (Ability's output still faces north, not west)")

	game_gui.board.remove_perk(Vector2i(2, 3))
	game_gui.board.place_perk(normal_attack_b, Vector2i(2, 3), GridDirection.Value.WEST)
	var chain_d := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(2, 3))
	_check(chain_d.size() == 2, "horizontal neighbors, BOTH rotated to face each other -> connects (chain size 2)")

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
