extends Node
## Scripted regression check for the player's defensive kit (PlayerController.receive_hit,
## block/parry, Guard, dodge i-frames, death) and for EnemyAttacker's telegraph -> strike loop
## against the real main.tscn. Timing is driven by stepping physics frames, the same clock
## PlayerController uses. Run headless:
## Godot --headless --path <project> res://scenes/tests/combat_defense_test.tscn --quit-after 3000

@onready var player: PlayerController = $Main/World/Player
@onready var white_attacker: EnemyAttacker = $Main/World/Enemy/Attacker
@onready var red_attacker: EnemyAttacker = $Main/World/RedEnemy/Attacker

var _pass_count := 0
var _fail_count := 0

func _ready() -> void:
	white_attacker.active = false
	red_attacker.active = false
	await _frames(30) # settle on the floor

	# --- Plain hit
	var r := player.receive_hit(Hit.new(15.0))
	_check(r == Hit.Result.HIT and is_equal_approx(player.health, 85.0), "unblocked hit takes full damage")

	# --- Parry: Block pressed right before impact
	player.block(true)
	r = player.receive_hit(Hit.new(15.0))
	_check(r == Hit.Result.PARRIED, "Block pressed within the parry window parries")
	_check(is_equal_approx(player.health, 85.0) and is_equal_approx(player.guard, player.max_guard), "parry takes no damage and costs no Guard")
	player.block(false)

	# --- Block: held longer than the window
	player.block(true)
	await _frames(20) # ~0.33 s > 0.15 s window
	r = player.receive_hit(Hit.new(10.0))
	_check(r == Hit.Result.BLOCKED, "Block held past the parry window blocks")
	_check(is_equal_approx(player.health, 82.0), "block lets 30% of the damage through")
	_check(is_equal_approx(player.guard, 75.0), "block drains 25 Guard")

	# --- Unblockable ignores Block and Parry
	player.block(false)
	player.block(true)
	r = player.receive_hit(Hit.new(20.0, Hit.Kind.UNBLOCKABLE))
	_check(r == Hit.Result.HIT and is_equal_approx(player.health, 62.0), "unblockable hit ignores a fresh block (no parry, full damage)")

	# --- Guard break
	await _frames(20)
	for i in 3:
		player.receive_hit(Hit.new(0.0))
	_check(player.guard <= 0.0 and player.is_stunned() and not player.is_blocking(), "Guard at 0 breaks guard: stunned and no longer blocking")
	_check(not player.dash(), "can't dodge while guard-broken")
	await _frames(60) # 1 s > 0.8 s stun
	_check(not player.is_stunned(), "guard-break stun wears off")
	var guard_before := player.guard
	await _frames(60)
	_check(player.guard > guard_before, "Guard regenerates when not blocking")

	# --- Dodge: movement, i-frames, cooldown
	player.health = player.max_health
	var start_x := player.global_position.x
	player.facing_direction = 1
	_check(player.dash(), "dodge starts")
	r = player.receive_hit(Hit.new(10.0))
	_check(r == Hit.Result.HIT, "no i-frames in the first 0.05 s of a dodge")
	await _frames(6) # 0.1 s in
	_check(player.is_invulnerable(), "i-frames active mid-dodge")
	r = player.receive_hit(Hit.new(25.0, Hit.Kind.UNBLOCKABLE))
	_check(r == Hit.Result.DODGED and is_equal_approx(player.health, 90.0), "unblockable hit during i-frames is dodged")
	await _frames(12)
	_check(not player.is_dodging(), "dodge ends after its duration")
	_check(absf(player.global_position.x - start_x - player.dodge_distance) < 15.0,
		"dodge covers ~dodge_distance (%.0f px)" % (player.global_position.x - start_x))
	_check(not player.dash(), "dodge cooldown blocks an immediate second dodge")
	await _frames(25)
	_check(player.dash(), "dodge is available again after the cooldown")
	await _frames(20)

	# --- Death respawns at spawn
	var died := [false]
	player.died.connect(func(): died[0] = true, CONNECT_ONE_SHOT)
	player.global_position.x += 50
	player.receive_hit(Hit.new(1000.0))
	_check(died[0] and is_equal_approx(player.health, player.max_health) and player.global_position == player.spawn_position,
		"lethal hit emits died and restores the player at spawn with full health")

	# --- Real enemy: white telegraph, parried on reaction
	player.global_position = white_attacker.global_position - Vector2(70, 0)
	await _frames(10)
	white_attacker.interval = 0.1
	white_attacker.active = true
	await white_attacker.telegraph_started
	_check(white_attacker.flash_target.modulate.r > 1.0, "white attacker flashes white while telegraphing")
	# Wait until just inside the parry window, then press Block.
	await _frames(int((white_attacker.telegraph_time - 0.1) * 60))
	player.block(true)
	var struck: Array = await white_attacker.struck
	_check(struck[1] == Hit.Result.PARRIED, "Block timed against the white telegraph parries the real strike")
	_check(white_attacker.get_node("Reach").position.x < 0.0, "attacker turned its reach toward a player on its left")
	player.block(false)
	white_attacker.active = false

	# --- Real enemy: red telegraph, eaten while blocking
	player.health = player.max_health
	player.global_position = red_attacker.global_position + Vector2(70, 0)
	await _frames(10)
	red_attacker.interval = 0.1
	red_attacker.active = true
	await red_attacker.telegraph_started
	_check(red_attacker.flash_target.modulate == EnemyAttacker.COLOR_UNBLOCKABLE, "red attacker flashes red while telegraphing")
	player.block(true)
	struck = await red_attacker.struck
	_check(struck[1] == Hit.Result.HIT and is_equal_approx(player.health, 75.0), "red strike goes through Block for full damage (25)")
	player.block(false)
	red_attacker.active = false

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

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
