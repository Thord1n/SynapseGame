extends Node
## Scripted regression check for TriggerRouter: each gameplay event resolves the matching
## ability's SynapseGrid chain against the right enemy (the hit landing -> Normal/Special Attack,
## a parry -> Guard, dodging through a hit -> Dash, takeoff -> Jump), keypresses no longer
## resolve chains on their own in main.tscn, and Special Attack is on a cooldown. Run headless:
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

	# --- No Normal Attack on the board: a landed swing falls back to the flat placeholder.
	var dealt := await _swing_and_measure(&"normal_attack")
	_check(is_equal_approx(dealt, PlayerController.PLACEHOLDER_MELEE_DAMAGE), "unplaced Normal Attack falls back to placeholder damage (%s)" % dealt)

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

	# --- Parry fires the Guard chain at the attacker.
	var before := enemy.dummy_target.damage_taken
	_parry_hit_from(enemy)
	_check(is_equal_approx(enemy.dummy_target.damage_taken, before), "no Guard on the board: a parry adds nothing")
	_place(&"guard", Vector2i(2, 2), GridDirection.Value.EAST, -1)
	_place(&"shock", Vector2i(3, 2), GridDirection.Value.EAST, GridDirection.Value.WEST)
	var guard_expected := router.fire(&"guard", null).damage
	before = enemy.dummy_target.damage_taken
	_parry_hit_from(enemy)
	_check(guard_expected > 0.0 and is_equal_approx(enemy.dummy_target.damage_taken - before, guard_expected),
		"Guard -> Shock fires at the attacker on a parry (%s)" % guard_expected)
	before = enemy.dummy_target.damage_taken
	player.block(true)
	await _frames(20)
	player.receive_hit(Hit.new(10.0, Hit.Kind.PARRYABLE, enemy))
	player.block(false)
	_check(is_equal_approx(enemy.dummy_target.damage_taken, before), "a plain block does not fire the Guard chain")

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

	# --- Takeoff fires the Jump chain.
	_place(&"jump", Vector2i(2, 4), GridDirection.Value.EAST, -1)
	_log.clear()
	player.jump()
	_check(_log.any(func(t): return t.begins_with("Jump")), "takeoff resolves the Jump chain")
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
