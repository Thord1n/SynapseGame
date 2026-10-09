extends Node
## Scripted regression check for TriggerRouter: each gameplay event resolves the matching
## ability's SynapseGrid chain against the right enemy (the hit landing -> Normal/Special Attack,
## a parry -> Block, dodging through a hit -> Dash, takeoff -> Jump over an area), keypresses no
## longer resolve chains on their own in main.tscn, Special Attack is on a cooldown, Block's
## level sets max Guard, and the grid is live (moves work with it open; removing a perk stops
## its move at once). Run headless:
## Godot --headless --path <project> res://scenes/tests/grid_trigger_test.tscn --quit-after 3000

@onready var game_gui: GameGui = $Main/MenuLayer/GameGui
@onready var player: PlayerController = $Main/World/Player
@onready var enemy: Enemy = $Main/World/Enemy
@onready var router: TriggerRouter = $Main/TriggerRouter

var _pass_count := 0
var _fail_count := 0
var _log: Array[String] = []

func _ready() -> void:
	$Main/World/Enemy/Attacker.active = false
	$Main/World/RedEnemy/Attacker.active = false
	game_gui.ability_triggered.connect(func(text): _log.append(text))
	await _frames(30)

	_check(not game_gui.trigger_on_keypress, "main.tscn resolves chains on events, not raw keypresses")

	# --- Starting loadout: level-2 Memory slotted, the five moves on the grid at 1 byte each.
	_check(game_gui.memory_system.slotted_perk != null and game_gui.memory_system.slotted_perk.level == 2,
		"starting loadout slots a level-2 Memory perk")
	for id in [&"jump", &"normal_attack", &"special_attack", &"block", &"dash"]:
		_check(router.is_equipped(id), "starting loadout places %s" % id)
	_check(game_gui.memory_system.get_used(game_gui.board) == 5 and game_gui.memory_system.get_capacity() == 8,
		"5 abilities use 5 of 8 bytes (%d / %d)" % [game_gui.memory_system.get_used(game_gui.board), game_gui.memory_system.get_capacity()])
	_check(is_equal_approx(player.max_guard, 100.0), "level-1 Block gives max Guard 100 (%s)" % player.max_guard)

	# --- The grid is live: with it open, moves still work.
	game_gui.visible = true
	await _frames(5)
	var jump_key := InputEventAction.new()
	jump_key.action = &"Jump"
	jump_key.pressed = true
	Input.parse_input_event(jump_key)
	await _frames(3)
	_check(not player.is_on_floor(), "grid open: Jump still works")
	await _frames(90)
	game_gui.visible = false

	# --- Removing the Block perk mid-block stops the block at once and zeroes max Guard.
	player.block(true)
	_check(player.is_blocking(), "blocking with the Block perk placed")
	_remove(&"block")
	await _frames(2)
	_check(not player.is_blocking() and player.max_guard == 0.0, "Block perk removed mid-block: block ends, no Guard")

	# --- Abilities are perks: take them off the grid and the moves stop working.
	_clear_board()
	await _frames(10)
	var dealt := await _swing_and_measure(&"normal_attack")
	_check(dealt == 0.0, "no Normal Attack perk: the swing doesn't happen")
	player.jump()
	await _frames(3)
	_check(player.is_on_floor(), "no Jump perk: can't jump")
	_check(not player.dash(), "no Dash perk: can't dodge")
	player.block(true)
	_check(not player.is_blocking(), "no Block perk: can't block or parry")
	_check(not player.special_attack(), "no Special Attack perk: can't use it")
	var missing: Array[StringName] = []
	player.ability_missing.connect(func(id): missing.append(id))
	player.jump()
	player.block(true)
	_check(missing == [&"jump", &"block"], "pressing a missing move reports which perk is missing (%s)" % [missing])
	var cue: Label = $Main._missing_cue
	_check(cue != null and cue.visible and cue.text == "No Block perk on the grid", "...and flashes a cue naming it")
	await _frames(int($Main.MISSING_CUE_SECONDS * 60) + 10)
	_check(not cue.visible, "...which goes away on its own")

	# --- Shield is a passive Core perk: placed anywhere, it raises the flat shield stat.
	_check(game_gui.player.shield == 0, "no Shield perk: no shield")
	_place(&"shield", Vector2i(0, 0), -1, -1)
	_check(game_gui.player.shield == 20, "Shield placed off the ability column: shield 20 (%d)" % game_gui.player.shield)
	_remove(&"shield")

	# --- Normal Attack -> Fire on the board: the landed swing deals the chain's damage.
	_place(&"normal_attack", Vector2i(2, 0), GridDirection.Value.EAST, -1)
	var expected := router.fire(&"normal_attack", null).damage # chain value, applied to nobody
	_place(&"fire", Vector2i(3, 0), GridDirection.Value.EAST, GridDirection.Value.WEST)
	var expected_with_fire := router.fire(&"normal_attack", null).damage
	_check(expected_with_fire > expected, "Fire adds to the Normal Attack chain (%s -> %s)" % [expected, expected_with_fire])
	dealt = await _swing_and_measure(&"normal_attack")
	_check(is_equal_approx(dealt, expected_with_fire), "landed Normal Attack deals its grid chain's damage (%s)" % dealt)

	# --- Special Attack: own chain, plain cooldown.
	_place(&"special_attack", Vector2i(2, 1), GridDirection.Value.EAST, -1)
	var special_expected := router.fire(&"special_attack", null).damage
	dealt = await _swing_and_measure(&"special_attack")
	_check(is_equal_approx(dealt, special_expected), "landed Special Attack deals the Special chain's damage (%s)" % dealt)
	_check(not player.special_attack(), "Special Attack is on cooldown right after use")
	await _frames(int(player.special_attack_cooldown * 60) + 5)
	_check(player.special_attack(), "Special Attack is ready again after its cooldown")
	await _frames(20)

	# --- Parry fires the Block chain at the attacker.
	var before := enemy.dummy_target.damage_taken
	_parry_hit_from(enemy)
	_check(is_equal_approx(enemy.dummy_target.damage_taken, before), "no Block on the board: blocking does nothing, so nothing fires")
	_place(&"block", Vector2i(2, 2), GridDirection.Value.EAST, -1)
	_place(&"shock", Vector2i(3, 2), GridDirection.Value.EAST, GridDirection.Value.WEST)
	var guard_expected := router.fire(&"block", null).damage
	before = enemy.dummy_target.damage_taken
	_parry_hit_from(enemy)
	_check(guard_expected > 0.0 and is_equal_approx(enemy.dummy_target.damage_taken - before, guard_expected),
		"Block -> Shock fires at the attacker on a parry, with no base hit of its own (%s)" % guard_expected)
	before = enemy.dummy_target.damage_taken
	player.block(true)
	await _frames(20)
	player.receive_hit(Hit.new(10.0, Hit.Kind.PARRYABLE, enemy))
	player.block(false)
	_check(is_equal_approx(enemy.dummy_target.damage_taken, before), "a plain block does not fire the Block chain")

	# --- Dodging through a hit fires the Dash chain at the attacker.
	_place(&"dash", Vector2i(2, 3), GridDirection.Value.EAST, -1)
	_place(&"ice", Vector2i(3, 3), GridDirection.Value.EAST, GridDirection.Value.WEST)
	var dash_expected := router.fire(&"dash", null).damage
	await _frames(30)
	player.dash()
	await _frames(6)
	before = enemy.dummy_target.damage_taken
	var r := player.receive_hit(Hit.new(25.0, Hit.Kind.UNBLOCKABLE, enemy))
	_check(r == Hit.Result.DODGED and is_equal_approx(enemy.dummy_target.damage_taken - before, dash_expected),
		"dodging through a hit fires the Dash chain at the attacker (%s)" % dash_expected)
	await _frames(40)

	# --- Takeoff fires the Jump chain over an area around the takeoff point.
	_place(&"jump", Vector2i(2, 4), GridDirection.Value.EAST, -1)
	_place(&"fire", Vector2i(3, 4), GridDirection.Value.EAST, GridDirection.Value.WEST)
	var jump_expected := router.fire(&"jump", null).damage
	var red: Enemy = $Main/World/RedEnemy
	player.global_position = enemy.global_position - Vector2(60, 0)
	await _frames(40)
	before = enemy.dummy_target.damage_taken
	var red_before := red.dummy_target.damage_taken
	_log.clear()
	player.jump()
	_check(_log.any(func(t): return t.begins_with("Jump")), "takeoff resolves the Jump chain")
	_check(is_equal_approx(enemy.dummy_target.damage_taken - before, jump_expected),
		"Jump -> Fire hits the enemy inside the 80 px area (%s)" % jump_expected)
	_check(is_equal_approx(red.dummy_target.damage_taken, red_before), "...and not the one far away")
	var far := router.fire_jump_area(enemy.global_position + Vector2(0, -500))
	_check(far.is_empty(), "nobody inside: the chain still resolves, hitting nothing")
	_place(&"explosion", Vector2i(4, 4), GridDirection.Value.EAST, GridDirection.Value.WEST)
	var ctx := router.fire(&"jump", null)
	_check(router.jump_area_radius(ctx) > router.jump_radius, "Explosion widens Jump's area (%s px)" % router.jump_area_radius(ctx))
	await _frames(20) # let pending swing/jump coroutines finish before quitting

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

## Puts the player next to the enemy facing it, swings, and returns how much damage landed.
func _swing_and_measure(ability_id: StringName) -> float:
	player.global_position = enemy.global_position - Vector2(70, 0)
	player.facing_direction = 1
	await _frames(40) # let any previous cooldown/swing finish
	var before := enemy.dummy_target.damage_taken
	if ability_id == &"special_attack":
		player.special_attack()
	else:
		player.normal_attack()
	await _frames(15)
	return enemy.dummy_target.damage_taken - before

func _remove(id: StringName) -> void:
	var placed := game_gui.ability_controller.find_placed(game_gui.board, id)
	game_gui.inventory.add_perk(game_gui.board.remove_perk(placed.position))

func _clear_board() -> void:
	for placed in game_gui.board.get_all_placed_perks():
		game_gui.inventory.add_perk(game_gui.board.remove_perk(placed.position))

func _parry_hit_from(source: Enemy) -> void:
	player.block(false)
	player.block(true)
	player.receive_hit(Hit.new(15.0, Hit.Kind.PARRYABLE, source))
	player.block(false)

func _place(id: StringName, pos: Vector2i, output: int, input: int) -> void:
	for perk in game_gui.inventory.perks:
		if perk.definition.id == id:
			game_gui.inventory.remove_perk(perk)
			assert(game_gui.board.place_perk(perk, pos, output, input) != null, "couldn't place %s" % id)
			return
	assert(false, "%s not in inventory" % id)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		print("[FAIL] %s" % label)
