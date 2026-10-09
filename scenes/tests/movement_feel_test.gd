extends Node
## Scripted regression check for the Phase 1 movement feel (design/movement-feel-spec.md):
## run acceleration/deceleration, coyote time, jump buffer, variable jump height, faster
## falls, flat dash in the held direction with one air dash per airtime, slowed movement and a
## chained buffered attack while swinging, and the camera leading the player. Run headless:
## Godot --headless --path <project> res://scenes/tests/movement_feel_test.tscn --quit-after 3000

@onready var player: PlayerController = $Main/World/Player
@onready var camera: FollowCamera = $Main/Camera2D

var _pass_count := 0
var _fail_count := 0

func _ready() -> void:
	$Main.hitstop_seconds = 0.0
	for e in [$Main/World/Enemy, $Main/World/RedEnemy]: e.patrol_distance = 0.0
	await _frames(40)

	# --- Run: snappy acceleration, quick stop.
	Input.action_press(&"Right")
	await _frames(2)
	_check(player.velocity.x > 0.0 and player.velocity.x < player.run_speed, "accelerates toward run speed (%.0f)" % player.velocity.x)
	await _frames(4)
	_check(is_equal_approx(player.velocity.x, player.run_speed), "reaches run speed within ~0.06 s")
	_check(camera.global_position.x < player.global_position.x + camera.lead + 1.0, "camera follows (limited to the level)")
	Input.action_release(&"Right")
	await _frames(4)
	_check(player.velocity.x == 0.0, "stops within ~0.05 s of releasing")

	# --- Full jump vs tapped hop; falls are faster than rises.
	var floor_y := player.global_position.y
	var full := await _jump_peak(false)
	var hop := await _jump_peak(true)
	_check(full > 95.0 and full < 125.0, "full jump is ~110 px (%.0f)" % full)
	_check(hop < full * 0.75, "releasing early gives a short hop (%.0f vs %.0f)" % [hop, full])
	_check(player.gravity_falling > player.gravity_rising, "falls faster than it rises")

	# --- Coyote time: just off a ledge, a jump still works; later it doesn't. (Teleporting up
	# stands in for walking off a ledge; the first frame after still counts as grounded.)
	var jumps := [0]
	player.jump_started.connect(func(): jumps[0] += 1)
	await _drop_from(150.0)
	await _frames(3)
	player.jump()
	_check(jumps[0] == 1, "coyote time: jump ~0.05 s after leaving the floor works")
	await _land()
	await _drop_from(150.0)
	await _frames(12)
	player.jump()
	_check(jumps[0] == 1, "...but not ~0.2 s after")

	# --- Jump buffer: a press just before landing jumps on landing.
	await _land()
	await _drop_from(80.0)
	while player.global_position.y < floor_y - 15.0:
		await get_tree().physics_frame
	player.jump()
	_check(jumps[0] == 1, "buffered press in the air doesn't jump yet")
	await _frames(8)
	_check(jumps[0] == 2, "...and jumps on landing")
	await _land()

	# --- Dash: held direction, flat, one air dash per airtime.
	Input.action_press(&"Left")
	await _frames(1)
	player.facing_direction = 1
	var x0 := player.global_position.x
	_check(player.dash(), "dash starts")
	Input.action_release(&"Left")
	await _frames(16)
	_check(player.global_position.x < x0 - 100.0, "dashes toward the held direction (%.0f px)" % (player.global_position.x - x0))
	await _frames(30)
	player.jump()
	await _frames(5)
	_check(player.dash(), "one air dash")
	var y_mid := player.global_position.y
	await _frames(6)
	_check(is_equal_approx(player.global_position.y, y_mid), "the dash is flat (no gravity)")
	await _frames(20)
	_check(not player.is_on_floor() and not player.dash(), "no second air dash before landing")
	await _land()
	await _frames(25)
	_check(player.dash(), "landing resets the air dash")
	await _frames(40)

	# --- Attacking while moving: slowed, not stopped; a mid-swing press chains.
	Input.action_press(&"Right")
	await _frames(8)
	player.normal_attack()
	await _frames(2)
	_check(is_equal_approx(player.velocity.x, player.run_speed * player.swing_move_scale), "moving at 60%% speed mid-swing (%.0f)" % player.velocity.x)
	await _frames(5)
	player.normal_attack() # near the end of the first swing
	await _frames(int(player.swing_duration * 60) - 3)
	_check(player.is_swinging(), "a press near the end of a swing chains into a second swing")
	Input.action_release(&"Right")
	await _frames(20)

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

## Jumps from the floor and returns the peak height; `tap` releases after 3 frames.
func _jump_peak(tap: bool) -> float:
	await _land()
	var start := player.global_position.y
	var peak := start
	player.jump()
	for i in 90:
		await get_tree().physics_frame
		if tap and i == 3:
			player.release_jump()
		peak = minf(peak, player.global_position.y)
		if i > 5 and player.is_on_floor():
			break
	return start - peak

## Puts the player `height` px above the floor, falling from rest.
func _drop_from(height: float) -> void:
	player.global_position.y -= height
	player.velocity = Vector2.ZERO
	await get_tree().physics_frame

func _land() -> void:
	for i in 120:
		if player.is_on_floor() and player.velocity.y >= 0.0:
			break
		await get_tree().physics_frame
	await _frames(2)

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
