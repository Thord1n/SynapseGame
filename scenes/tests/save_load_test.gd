extends Node
## Scripted regression check for SaveSystem / GameGui.save_path: a saved inventory, board
## (positions + chosen orientations) and memory slot come back identical in a fresh GameGui,
## a perk held mid-move isn't lost or duplicated, a soft-locked board loads without dropping
## perks, and bad saves are ignored instead of crashing. Run headless:
## Godot --headless --path <project> res://scenes/tests/save_load_test.tscn --quit-after 10

const GAME_GUI_SCENE := preload("res://scenes/main/game_gui.tscn")
const SAVE_PATH := "user://save_load_test.json"

func _ready() -> void:
	SaveSystem.delete_save(SAVE_PATH)

	# --- No save yet: falls back to the seeded inventory.
	var gui := _spawn_gui()
	var seeded_count := gui.inventory.perks.size()
	_check(seeded_count > 0 and gui.board.get_all_placed_perks().is_empty() and gui.memory_system.slotted_perk == null,
		"with no save file, GameGui starts from the seeded inventory")

	# --- Build up some state through the real GUI handlers.
	var memory_stack := _stack_of(gui, &"memory")
	gui.inventory.merge(memory_stack[0], memory_stack[1]) # level-2 Memory: 8 bytes
	gui._on_inventory_stack_pressed([_find(gui, &"memory", 2)])
	gui._on_memory_slot_pressed()

	gui._on_inventory_stack_pressed([_find(gui, &"jump", 1)])
	gui._held["rotation"] = GridDirection.Value.SOUTH
	gui._on_board_cell_pressed(Vector2i(2, 0))

	# Fire below Jump, input facing NORTH into Jump's SOUTH output: a live connection.
	gui._on_inventory_stack_pressed([_find(gui, &"fire", 1)])
	gui._held["rotation"] = GridDirection.Value.SOUTH
	gui._on_board_cell_pressed(Vector2i(2, 1))

	var fire_stack := _stack_of(gui, &"fire")
	gui.inventory.merge(fire_stack[0], fire_stack[1])
	await get_tree().process_frame # let the queued autosave run

	var before := SaveSystem.serialize(gui.inventory, gui.board, gui.memory_system)
	var connections_before := _connection_count(gui.board)
	_check(connections_before > 0, "test setup has at least one live connection")
	_check(FileAccess.file_exists(SAVE_PATH), "autosave wrote a save file after changes")
	_check(_normalized(SaveSystem.load_from_file(SAVE_PATH)) == _normalized(before),
		"save file matches the live state (no duplicates from mid-action saves)")
	gui.free()

	# --- Fresh GameGui on the same path restores everything.
	gui = _spawn_gui()
	var after := SaveSystem.serialize(gui.inventory, gui.board, gui.memory_system)
	_check(_normalized(after) == _normalized(before), "inventory, board and memory slot round-trip exactly")
	_check(gui.memory_system.get_capacity() == 8, "restored level-2 Memory perk grants 8 bytes")
	var jump: PlacedPerk = gui.board.get_cell(Vector2i(2, 0)).occupant
	_check(jump != null and jump.output_direction == GridDirection.Value.SOUTH,
		"restored perk keeps the orientation the player chose")
	_check(_connection_count(gui.board) == connections_before, "connections are recomputed on load")

	# --- A perk held off the board when the game saves isn't lost.
	gui._on_board_cell_pressed(Vector2i(2, 1)) # pick Fire up, keep holding it
	await get_tree().process_frame
	var held_save := SaveSystem.load_from_file(SAVE_PATH)
	_check(_count_id(held_save, "fire") == _count_id(before, "fire"), "held perk is saved as inventory, not dropped")
	gui._on_board_cell_pressed(Vector2i(2, 1)) # put it back
	await get_tree().process_frame
	_check(_count_id(SaveSystem.load_from_file(SAVE_PATH), "fire") == _count_id(before, "fire"),
		"putting a held perk back doesn't duplicate it in the save")
	gui.free()

	# --- Soft-locked board (usage over capacity) loads without dropping perks.
	var locked := before.duplicate(true)
	locked["memory"] = null
	SaveSystem.save_to_file(locked, SAVE_PATH)
	gui = _spawn_gui()
	_check(gui.board.get_all_placed_perks().size() == before["board"].size() and gui.memory_system.is_soft_locked(gui.board),
		"soft-locked save restores every placed perk")
	gui.free()

	# --- Bad data is ignored, not fatal.
	var unknown := before.duplicate(true)
	unknown["inventory"].append({"id": "no_such_perk", "level": 1})
	SaveSystem.save_to_file(unknown, SAVE_PATH)
	gui = _spawn_gui()
	_check(gui.inventory.perks.size() == before["inventory"].size(), "unknown perk ids are skipped")
	gui.free()

	var future := before.duplicate(true)
	future["version"] = 999
	SaveSystem.save_to_file(future, SAVE_PATH)
	gui = _spawn_gui()
	_check(gui.inventory.perks.size() == seeded_count, "unsupported save version falls back to a fresh start")
	gui.free()

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	gui = _spawn_gui()
	_check(gui.inventory.perks.size() == seeded_count, "corrupt save file falls back to a fresh start")
	gui.free()

	SaveSystem.delete_save(SAVE_PATH)
	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

func _spawn_gui() -> GameGui:
	var gui: GameGui = GAME_GUI_SCENE.instantiate()
	gui.save_path = SAVE_PATH
	add_child(gui)
	return gui

func _stack_of(gui: GameGui, id: StringName) -> Array:
	return gui.inventory.perks.filter(func(p): return p.definition.id == id and p.level == 1)

func _find(gui: GameGui, id: StringName, level: int) -> InventoryPerk:
	for perk in gui.inventory.perks:
		if perk.definition.id == id and perk.level == level:
			return perk
	assert(false, "%s Lv%d not in inventory" % [id, level])
	return null

## Order-independent comparison: inventory/board order isn't meaningful. Round-trips through
## JSON so ints and floats compare the same way they will after loading from disk.
func _normalized(data: Dictionary) -> Dictionary:
	var copy: Dictionary = JSON.parse_string(JSON.stringify(data))
	for key in ["inventory", "board"]:
		var strings: Array = copy[key].map(func(e): return JSON.stringify(e, "", true))
		strings.sort()
		copy[key] = strings
	return copy

func _connection_count(board: Board) -> int:
	var n := 0
	for placed in board.get_all_placed_perks():
		n += placed.connections.size()
	return n

func _count_id(data: Dictionary, id: String) -> int:
	var n := 0
	for key in ["inventory", "board"]:
		for entry in data[key]:
			if entry["id"] == id:
				n += 1
	return n

var _pass_count := 0
var _fail_count := 0

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		print("[FAIL] %s" % label)
