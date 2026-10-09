extends Node
## Scripted regression check for Thomas's modifier order rule and Shock buildup, against the
## real main.tscn: sources (Fire/Ice/Shock) work anywhere; amplifiers (Echo, Linger) only
## act on source effects earlier in the chain and are flagged as no-ops otherwise; Explosion
## and Chain work on the plain hit; Echo repeats upstream source effects as fading bounces; enough Shock
## stuns an enemy, cancelling its telegraph, then grants stun immunity. Run headless:
## Godot --headless --path <project> res://scenes/tests/modifier_order_test.tscn --quit-after 3000

const ROW := 1
const ABILITY_POS := Vector2i(2, ROW)

@onready var game_gui: GameGui = $Main/MenuLayer/GameGui
@onready var enemy: Enemy = $Main/World/Enemy
@onready var attacker: EnemyAttacker = $Main/World/Enemy/Attacker
@onready var router: TriggerRouter = $Main/TriggerRouter

var _pass_count := 0
var _fail_count := 0

func _ready() -> void:
	$Main.hitstop_seconds = 0.0 # frame-counted waits below assume normal time
	for e in [$Main/World/Enemy, $Main/World/RedEnemy]: e.patrol_distance = 0.0 # fixed positions
	attacker.active = false
	$Main/World/RedEnemy/Attacker.active = false
	await _frames(5)

	# --- Echo before any source does nothing, and is flagged.
	_build_chain([&"echo", &"fire"])
	var ctx := router.fire(&"normal_attack", null)
	_check(_noop_ids(ctx) == [&"echo"], "Attack -> Echo -> Fire: Echo is a flagged no-op")
	_check(ctx.delayed.is_empty() and is_equal_approx(ctx.damage, 15.0), "Attack -> Echo -> Fire: just the hit + Fire (15), no echo")
	_check(game_gui.ability_controller.ability_activator.find_noop_perks(game_gui.board, ABILITY_POS).size() == 1,
		"find_noop_perks() reports the idle Echo for the UI")
	game_gui._refresh_ui()
	_check(game_gui._board_buttons[ABILITY_POS + Vector2i(1, 0)].modulate == GameGui.COLOR_IDLE, "the board greys out the idle Echo")

	# --- Echo after a source repeats it at 70% after a delay.
	_build_chain([&"fire", &"echo"])
	var before := enemy.dummy_target.damage_taken
	ctx = router.fire(&"normal_attack", enemy)
	_check(ctx.noop_perks.is_empty() and ctx.delayed.size() == 1, "Attack -> Fire -> Echo: Echo schedules one repeat")
	_check(is_equal_approx(enemy.dummy_target.damage_taken - before, 15.0), "the hit itself lands immediately (15)")
	await _seconds(0.2)
	_check(is_equal_approx(enemy.dummy_target.damage_taken - before, 15.0), "the echo hasn't landed before its delay")
	await _seconds(0.2)
	_check(is_equal_approx(enemy.dummy_target.damage_taken - before, 18.5), "the echo lands Fire again at 70% (+3.5) after ~0.3 s")

	# --- Level N = N fading bounces; a second Echo doesn't echo the first one's bounces.
	var echo_def: EchoPerkDefinition = load("res://resources/perks/modifier/echo.tres")
	var probe := EffectContext.new()
	probe.add_effect(&"fire", ElementalPerkDefinition.Element.FIRE, 10.0)
	echo_def.apply_effect(3, probe)
	var bounces: Array = probe.delayed.map(func(d): return snappedf(d["effects"][0]["damage"], 0.001))
	_check(bounces == [7.0, 4.9, 3.43] and is_equal_approx(probe.delayed[2]["delay"], 0.9),
		"level-3 Echo: 3 bounces at 70%%, 49%%, 34.3%%, 0.3 s apart (%s)" % [bounces])
	var twice := EffectContext.new() # Fire -> Echo -> Echo (the board is too narrow for it)
	twice.add_effect(&"fire", ElementalPerkDefinition.Element.FIRE, 5.0)
	echo_def.apply_effect(1, twice)
	echo_def.apply_effect(1, twice)
	bounces = twice.delayed.map(func(d): return snappedf(d["effects"][0]["damage"], 0.001))
	_check(bounces == [3.5, 3.5], "Fire -> Echo -> Echo: each Echo bounces the Fire once, no echo of an echo (%s)" % [bounces])
	var costs: Array = range(1, 7).map(func(lv): return InventoryPerk.new(echo_def, lv).get_memory_cost())
	_check(costs == [2, 3, 5, 8, 12, 21], "Echo costs 2, 3, 5, 8, 12, 21 bytes at levels 1-6 (%s)" % [costs])

	# --- Chain and Explosion work on the plain hit; Linger needs a source.
	_build_chain([&"chain"])
	ctx = router.fire(&"normal_attack", null)
	_check(ctx.noop_perks.is_empty() and ctx.target_count == 2, "Attack -> Chain: the plain hit chains to a second target")
	_build_chain([&"fire", &"chain"])
	ctx = router.fire(&"normal_attack", null)
	_check(ctx.noop_perks.is_empty() and ctx.target_count == 2, "Attack -> Fire -> Chain: chains the fire hit to a second target")
	_build_chain([&"explosion"])
	ctx = router.fire(&"normal_attack", null)
	_check(ctx.noop_perks.is_empty() and ctx.radius > 0.0, "Attack -> Explosion: explodes on the plain hit")
	_build_chain([&"linger"])
	ctx = router.fire(&"normal_attack", null)
	_check(_noop_ids(ctx) == [&"linger"] and ctx.radius == 0.0, "Attack -> Linger: no-op (nothing upstream)")
	_build_chain([&"ice", &"linger"])
	ctx = router.fire(&"normal_attack", null)
	_check(ctx.noop_perks.is_empty() and ctx.radius > 0.0, "Attack -> Ice -> Linger: lingers")

	# --- Shock buildup: 35 per application, stun at 100.
	_build_chain([&"shock"])
	attacker.interval = 0.05
	attacker.telegraph_time = 5.0 # stays telegraphing so the cancel is observable
	attacker.active = true
	await attacker.telegraph_started
	router.fire(&"normal_attack", enemy)
	_check(is_equal_approx(enemy.shock_buildup, 35.0), "one Shock adds 35 buildup")
	router.fire(&"normal_attack", enemy)
	_check(not enemy.is_stunned(), "70 buildup: not stunned yet")
	router.fire(&"normal_attack", enemy)
	_check(enemy.is_stunned() and enemy.shock_buildup == 0.0, "third Shock fills it: stunned, buildup reset")
	_check(not attacker.is_telegraphing(), "stun cancels the enemy's telegraphed attack")
	router.fire(&"normal_attack", enemy)
	_check(enemy.shock_buildup == 0.0, "no buildup while stunned")
	await _seconds(enemy.stun_duration + 0.1)
	_check(not enemy.is_stunned(), "stun wears off after ~1.5 s")
	router.fire(&"normal_attack", enemy)
	_check(enemy.shock_buildup == 0.0 and enemy.is_stun_immune(), "stun immunity: Shock doesn't build up right after a stun")
	attacker.active = false
	await _seconds(enemy.stun_immunity)

	# --- Buildup decays after 2 s without Shock; Echo's bounce adds 70% buildup.
	router.fire(&"normal_attack", enemy)
	_check(is_equal_approx(enemy.shock_buildup, 35.0), "buildup again once immunity ends")
	await _seconds(enemy.shock_decay_delay + 0.1)
	_check(enemy.shock_buildup == 0.0, "buildup resets after 2 s without Shock")
	_build_chain([&"shock", &"echo"])
	router.fire(&"normal_attack", enemy)
	await _seconds(0.4)
	_check(is_equal_approx(enemy.shock_buildup, 35.0 + 24.5), "Shock -> Echo: the bounce adds 70% buildup (+24.5)")

	await _seconds(0.5)
	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

## Clears the board and lays Normal Attack at ABILITY_POS followed east by `modifiers` in order.
func _build_chain(modifiers: Array) -> void:
	for placed in game_gui.board.get_all_placed_perks():
		game_gui.inventory.add_perk(game_gui.board.remove_perk(placed.position))
	_place(&"normal_attack", ABILITY_POS, GridDirection.Value.EAST, GridDirection.Value.WEST)
	for i in modifiers.size():
		_place(modifiers[i], ABILITY_POS + Vector2i(i + 1, 0), GridDirection.Value.EAST, GridDirection.Value.WEST)

func _place(id: StringName, pos: Vector2i, output: int, input: int) -> void:
	for perk in game_gui.inventory.perks:
		if perk.definition.id == id and perk.level == 1:
			game_gui.inventory.remove_perk(perk)
			assert(game_gui.board.place_perk(perk, pos, output, input) != null, "couldn't place %s" % id)
			return
	assert(false, "%s not in inventory" % id)

func _noop_ids(ctx: EffectContext) -> Array:
	return ctx.noop_perks.map(func(p): return p.get_definition().id)

func _seconds(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))

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
