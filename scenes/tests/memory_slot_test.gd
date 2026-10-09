extends Node
## Scripted regression check for the Memory perk / memory slot mechanics: capacity is 0 (and
## board placement of anything is blocked) with nothing slotted, slotting a level-N Memory perk
## grants exactly 4 * 2^(N-1) bytes, and a Memory perk itself can never go on the board. Run
## headless: Godot --headless --path <project> res://scenes/tests/memory_slot_test.tscn --quit-after 5

@onready var game_gui: GameGui = $GameGui

func _ready() -> void:
	_check(game_gui.memory_system.get_capacity() == 0, "capacity is 0 with nothing slotted")

	var jump_perk := _take_from_inventory(&"jump")
	_check(not game_gui.memory_system.can_place(jump_perk, game_gui.board),
		"can_place() false for any perk with nothing slotted")
	game_gui.inventory.add_perk(jump_perk)

	var memory_perk := _take_from_inventory(&"memory")
	_check(game_gui.memory_system.can_slot(memory_perk), "can_slot() true for a Memory-class perk")
	game_gui.memory_system.slot_perk(memory_perk)
	_check(game_gui.memory_system.get_capacity() == 4, "level-1 Memory perk grants 4 bytes")

	game_gui.memory_system.slot_perk(InventoryPerk.new(memory_perk.definition, 2))
	_check(game_gui.memory_system.get_capacity() == 8, "level-2 Memory perk grants 8 bytes (doubled)")

	var jump_perk_2 := _take_from_inventory(&"jump")
	_check(game_gui.memory_system.can_place(jump_perk_2, game_gui.board),
		"can_place() true once slotted with enough capacity")
	game_gui.inventory.add_perk(jump_perk_2)

	var another_memory := InventoryPerk.new(memory_perk.definition, 1)
	var some_cell := game_gui.board.get_cell(Vector2i(0, 0))
	_check(not some_cell.accepts(another_memory.definition),
		"Cell.accepts() rejects Memory-class perks outright, even on an unrestricted cell")

	_check(memory_perk.get_memory_cost() == 0, "Memory perk's own board memory cost is 0")

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
