extends Node
## Checks that PlayerController's minimal movement/jump implementation actually works against
## main.tscn's Ground body — not just that the scene loads without erroring (already confirmed
## headless), but that gravity + collision actually settle the player on the floor rather than
## falling through it, and that is_on_floor()/jump() respond correctly. Run headless:
## Godot --headless --path <project> res://scenes/tests/player_controller_test.tscn --quit-after 3

@onready var player: PlayerController = $Main/World/Player

var _pass_count := 0
var _fail_count := 0

func _ready() -> void:
	$Main.hitstop_seconds = 0.0 # frame-counted waits below assume normal time
	for e in [$Main/World/Enemy, $Main/World/RedEnemy]: e.patrol_distance = 0.0 # fixed positions
	# Let physics settle for a couple seconds of simulated frames before checking anything.
	for i in 120:
		await get_tree().physics_frame

	_check(player.is_on_floor(), "player is resting on the ground after settling")
	_check(is_equal_approx(player.velocity.y, 0.0), "vertical velocity settled near zero, not still falling")
	_check(player.global_position.y < 900.0, "player did not fall through the floor (y stayed near ground level)")

	var pre_jump_y := player.velocity.y
	player.jump()
	_check(player.velocity.y < pre_jump_y, "jump() sets an upward (negative) velocity while grounded")

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		print("[FAIL] %s" % label)
