extends Node
## Checks the Enemy wiring added this session: ability triggers now deal damage to a
## persistent Enemy in the world (main.gd wires game_gui.combat_target = enemy.dummy_target)
## instead of a fresh throwaway DummyTarget every press — damage should accumulate across
## multiple triggers, not reset. Also checks the melee hitbox actually deals damage to an
## Enemy it overlaps. Run headless:
## Godot --headless --path <project> res://scenes/tests/enemy_test.tscn --quit-after 200

@onready var main: Node = $Main
@onready var game_gui: GameGui = $Main/MenuLayer/GameGui
@onready var enemy: Enemy = $Main/World/Enemy
@onready var player: PlayerController = $Main/World/Player

var _pass_count := 0
var _fail_count := 0

func _ready() -> void:
	$Main.hitstop_seconds = 0.0 # frame-counted waits below assume normal time
	for e in [$Main/World/Enemy, $Main/World/RedEnemy]: e.patrol_distance = 0.0 # fixed positions
	_check(game_gui.combat_target == enemy.dummy_target, "main.gd wired GameGui.combat_target to the Enemy's own target")

	game_gui.memory_system.slot_perk(_take_from_inventory(&"memory"))
	var ability := _take_from_inventory(&"normal_attack")
	game_gui.board.place_perk(ability, Vector2i(2, 2), GridDirection.Value.EAST)

	game_gui._trigger_named_ability(&"Normal_attack", &"normal_attack")
	var after_first := enemy.dummy_target.damage_taken
	_check(after_first > 0.0, "first trigger dealt damage to the persistent Enemy")

	game_gui._trigger_named_ability(&"Normal_attack", &"normal_attack")
	var after_second := enemy.dummy_target.damage_taken
	_check(after_second == after_first * 2.0, "second trigger ACCUMULATES on the same Enemy rather than resetting (%s -> %s)" % [after_first, after_second])

	# Melee hitbox: move the player next to the Enemy and swing.
	player.global_position = enemy.global_position - Vector2(70, 0)
	player.facing_direction = 1
	var before_melee := enemy.dummy_target.damage_taken
	player.normal_attack()
	for i in 10:
		await get_tree().physics_frame
	_check(enemy.dummy_target.damage_taken > before_melee, "melee hitbox dealt damage to the Enemy it overlapped")

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

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
