extends Node
## Scripted regression check for game_gui.gd's ability-trigger input gating (the `visible`
## guard in _unhandled_input): triggering must fire while the menu is closed and must NOT fire
## while it's open. Added after a real bug where that guard's boolean was inverted, silently
## blocking every trigger exactly when the menu was closed — a static read missed it; an actual
## simulated click didn't. Run headless:
## Godot --headless --path <project> res://scenes/tests/input_flow_test.tscn --quit-after 10

@onready var game_gui: GameGui = $GameGui

var _last_triggered_text := ""

func _ready() -> void:
	game_gui.ability_triggered.connect(func(text): _last_triggered_text = text)

	var normal_attack_perk := _take_from_inventory(&"normal_attack")
	game_gui.board.place_perk(normal_attack_perk, Vector2i(2, 0), GridDirection.Value.EAST)

	# Fire connected onto Normal Attack's output (its input facing back west) — the chain
	# should now be [Normal Attack, Fire], and the log should show both perks' own
	# contributions, not just the aggregate total (see AbilityActivator.activate_with_steps).
	var fire_perk := _take_from_inventory(&"fire")
	game_gui.board.place_perk(fire_perk, Vector2i(3, 0), GridDirection.Value.EAST, GridDirection.Value.WEST)

	await _check_trigger(true, false, "menu open, left-click")
	await _check_trigger(false, true, "menu closed, left-click")

	var has_step_breakdown := "Normal Attack: +10 damage" in _last_triggered_text and "Fire: +5 damage" in _last_triggered_text
	print("[%s] chain step breakdown present -- %s" % ["PASS" if has_step_breakdown else "FAIL", _last_triggered_text])

	get_tree().quit()

func _take_from_inventory(id: StringName) -> InventoryPerk:
	for perk in game_gui.inventory.perks:
		if perk.definition.id == id:
			game_gui.inventory.remove_perk(perk)
			return perk
	assert(false, "%s not found in seeded inventory" % id)
	return null

func _check_trigger(menu_visible: bool, expect_trigger: bool, label: String) -> void:
	game_gui.visible = menu_visible
	_last_triggered_text = ""
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	# parse_input_event() queues the event; it's processed at the start of the next frame(s).
	await get_tree().process_frame
	await get_tree().process_frame
	var got_trigger := _last_triggered_text != ""
	var status := "PASS" if got_trigger == expect_trigger else "FAIL"
	print("[%s] %s -> triggered=%s (expected %s) -- %s" % [status, label, got_trigger, expect_trigger, _last_triggered_text])
