extends Node
## Scripted regression check for the grey-box damage-dealing feedback (Thomas: test dealing
## damage first): enemies start passive with F2 toggling their attacks, and each hit an enemy
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
