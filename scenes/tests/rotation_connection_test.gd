extends Node
## Reproduces a user report: rotated Special Attack and Ice to "face east/west" but the attack
## log still doesn't show Ice's contribution. Uses REAL simulated key presses (Input.parse_
## input_event with KEY_R), not direct _held dictionary manipulation, to rule out a bug
## specifically in the live rotation-cycling input path. Also checks which of the two ways a
## player might reasonably interpret "rotate both to face each other" actually connects, since
## input is always the OPPOSITE of a perk's own output (not a separate independent choice) —
## a real source of confusion if "rotate the modifier's input to face the ability" is read as
## "set the modifier's rotation dial to point at the ability" rather than "opposite of that".
## Run headless: Godot --headless --path <project> res://scenes/tests/rotation_connection_test.tscn --quit-after 20

@onready var game_gui: GameGui = $GameGui

func _ready() -> void:
	game_gui.memory_system.slot_perk(_take_from_inventory(&"memory"))

	# Special Attack at the ability slot (2,2); Ice one cell east of it, at (3,2).
	var special_attack := _take_from_inventory(&"special_attack")
	game_gui.board.place_perk(special_attack, Vector2i(2, 2))
	var ice := _take_from_inventory(&"ice")
	game_gui.board.place_perk(ice, Vector2i(3, 2))

	# Pick up Special Attack, rotate to EAST (1 R press from default NORTH=0), place it back.
	game_gui._on_board_cell_pressed(Vector2i(2, 2))
	await _press_r(1)
	game_gui._on_board_cell_pressed(Vector2i(2, 2))
	var ability_placed: PlacedPerk = game_gui.board.get_cell(Vector2i(2, 2)).occupant
	_check(ability_placed.output_direction == GridDirection.Value.EAST, "Special Attack rotated to output=EAST via real R presses")

	# Hypothesis A: rotate Ice to the SAME state (EAST) — its input becomes opposite(EAST)=WEST,
	# which is what's actually needed to receive from the ability sitting to its west.
	game_gui._on_board_cell_pressed(Vector2i(3, 2))
	await _press_r(1)
	game_gui._on_board_cell_pressed(Vector2i(3, 2))
	var chain_same := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(2, 2))
	_check(chain_same.size() == 2, "Hypothesis A (Ice rotated to the SAME state, EAST) -> connects")

	# Hypothesis B: rotate Ice to WEST instead (the "point back at the ability" instinct) — its
	# input becomes opposite(WEST)=EAST, which does NOT match the ability's EAST-facing output.
	game_gui._on_board_cell_pressed(Vector2i(3, 2))
	await _press_r(2) # currently EAST(1) -> +2 -> WEST(3)
	game_gui._on_board_cell_pressed(Vector2i(3, 2))
	var chain_mirrored := game_gui.chain_solver.resolve_chain(game_gui.board, Vector2i(2, 2))
	_check(chain_mirrored.size() == 1, "Hypothesis B (Ice rotated to WEST, mirroring the ability) -> does NOT connect")

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

func _press_r(times: int) -> void:
	for i in times:
		var event := InputEventKey.new()
		# Both, like a real hardware key press would populate — game_gui.gd's _input() now
		# checks physical_keycode specifically (see the fix that prompted this test), but
		# setting both here means this test stays valid even if that ever changes back.
		event.physical_keycode = KEY_R
		event.keycode = KEY_R
		event.pressed = true
		Input.parse_input_event(event)
		await get_tree().process_frame
		await get_tree().process_frame

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
