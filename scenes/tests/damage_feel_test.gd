extends Node
## Scripted regression check for the grey-box damage-dealing feedback (Thomas: test dealing
## damage first): enemies patrol but start passive, with F2 toggling their attacks, and each hit an enemy
## takes flashes and knocks its body, pops a damage number (plus a coloured tag per element),
## feeds a DPS readout and triggers a short real-time hitstop. Run headless:
## Godot --headless --path <project> res://scenes/tests/damage_feel_test.tscn --quit-after 3000

@onready var main: Node = $Main
@onready var enemy: Enemy = $Main/World/Enemy

var _pass_count := 0
var _fail_count := 0

func _ready() -> void:
	await _frames(5)
	_check(not ($Main/World/Enemy/Attacker as EnemyAttacker).active and not ($Main/World/RedEnemy/Attacker as EnemyAttacker).active,
		"enemies start passive")
	_press_f2()
	await _idle(3)
	_check(($Main/World/Enemy/Attacker as EnemyAttacker).active, "F2 turns enemy attacks on")
	_press_f2()
	await _idle(3)
	_check(not ($Main/World/Enemy/Attacker as EnemyAttacker).active, "F2 turns them off again")

	var x0 := enemy.position.x
	await _frames(30)
	_check(enemy.position.x != x0, "enemies patrol (moved %s px)" % (enemy.position.x - x0))
	enemy._stun()
	x0 = enemy.position.x
	await _frames(30)
	_check(enemy.position.x == x0, "a Shock stun stops the patrol")
	enemy.patrol_distance = 0.0

	var labels_before := _floating_labels()
	enemy.take_damage(12.0)
	_check(Engine.time_scale < 1.0, "a hit starts hitstop")
	_check(enemy.body.position.x != 0.0 and enemy.body.self_modulate.r > 1.0, "the enemy body flashes and is knocked back")
	_check(_floating_labels() == labels_before + 1, "a damage number pops up")
	_check(enemy.recent_dps() > 0.0 and "DPS" in enemy.damage_label.text, "the label shows DPS (%s)" % enemy.recent_dps())
	await get_tree().create_timer(main.hitstop_seconds + 0.1, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "hitstop ends on its own")
	await _frames(30)
	_check(enemy.body.position == Vector2.ZERO, "the body settles back")

	labels_before = _floating_labels()
	enemy.dummy_target.apply_effect_entry({"id": &"fire", "element": ElementalPerkDefinition.Element.FIRE, "damage": 5.0, "strength": 1.0})
	_check(_floating_labels() == labels_before + 1, "an element tag pops up for Fire")

	# Facing left swings left, and the swing is drawn on screen.
	var player: PlayerController = $Main/World/Player
	var hits := [0]
	enemy.damage_received.connect(func(_a, _t): hits[0] += 1)
	enemy.position = player.position + Vector2(-110, -20)
	await _frames(3)
	player.facing_direction = -1
	player.normal_attack()
	_check(player.swing_visual.visible and player.swing_visual.scale.x == -1.0, "the swing is shown, on the left")
	await _frames(4)
	_check(hits[0] > 0, "facing left hits an enemy on the left")
	await get_tree().create_timer(player.swing_duration + 0.1).timeout
	_check(not player.swing_visual.visible, "the swing visual hides when the swing ends")
	hits[0] = 0
	player.facing_direction = 1
	player.normal_attack()
	await _frames(4)
	_check(hits[0] == 0 and player.swing_visual.scale.x == 1.0, "facing right misses the enemy behind")
	_check(player.facing_arrow.visible and player.facing_arrow.scale.x == 1.0, "the facing arrow points right")
	player.facing_direction = -1
	await _frames(2)
	_check(player.facing_arrow.scale.x == -1.0, "the facing arrow flips left")

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

func _floating_labels() -> int:
	var n := 0
	for child in enemy.get_children():
		if child is Label and child != enemy.damage_label:
			n += 1
	return n

func _press_f2() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F2
	key.pressed = true
	Input.parse_input_event(key)

func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame

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
