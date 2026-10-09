extends Node
## Checks the exact scenario: pick an already-placed perk back up, rotate it, place it back
## down at the same cell — the new orientation should stick, not silently revert to the old
## one. Uses game_gui's real _on_board_cell_pressed()/_held so this exercises the actual GUI
## code path, not a reimplementation of it. Run headless:
## Godot --headless --path <project> res://scenes/tests/rotation_persistence_test.tscn --quit-after 5

@onready var game_gui: GameGui = $GameGui

func _ready() -> void:
	# _on_board_cell_pressed()'s placement branch checks memory_system.can_place() — unlike
	# calling Board.place_perk() directly, which doesn't — so the GUI-mediated re-placement
	# below needs real capacity, not just the direct initial placement.
	var memory_perk := _take_from_inventory(&"memory")
	game_gui.memory_system.slot_perk(memory_perk)

	var fire_perk := _take_from_inventory(&"fire")
	var pos := Vector2i(1, 1)
	game_gui.board.place_perk(fire_perk, pos, GridDirection.Value.NORTH, GridDirection.Value.SOUTH)

	# Pick it back up (click on the occupied cell while nothing is held).
	game_gui._on_board_cell_pressed(pos)
	_check(game_gui.board.get_cell(pos).is_empty(), "cell is empty after picking the perk back up")
	_check(int(game_gui._held.get("rotation", -1)) == 0, "rotation seeded from the perk's current orientation (NORTH = 0)")

	# Rotate it twice (same increment _input()'s R handler does): 0 -> 1 -> 2 (SOUTH output).
	game_gui._held["rotation"] = (int(game_gui._held.get("rotation", 0)) + 1) % 4
	game_gui._held["rotation"] = (int(game_gui._held.get("rotation", 0)) + 1) % 4

	# Place it back down at the SAME cell.
	game_gui._on_board_cell_pressed(pos)
	var placed: PlacedPerk = game_gui.board.get_cell(pos).occupant
	_check(placed != null, "perk is placed back at the same cell")
	if placed:
		_check(placed.output_direction == GridDirection.Value.SOUTH, "output_direction reflects the NEW rotation (SOUTH), not the original (NORTH)")
		_check(placed.input_direction == GridDirection.Value.NORTH, "input_direction reflects the NEW rotation (NORTH), not the original (SOUTH)")

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
