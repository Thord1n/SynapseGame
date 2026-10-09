class_name TriggerRouter
extends Node
## Connects the player's gameplay events to the SynapseGrid: when an ability's event fires, the
## chain headed by that ability (whatever modifiers are wired to it on the board) is resolved
## and applied to whoever the event involves. This is the "abilities just trigger what's in the
## grid" rule; it replaces resolving chains on raw keypresses (GameGui.trigger_on_keypress).
##
## Event -> ability chain -> target:
## - attack_landed  (on_hit)           -> the swing's ability (normal/special attack) -> the enemy hit
## - parried        (on_parry)         -> block  -> the attacker
## - dodged_through (on_dodge_through) -> dash   -> the attacker
## - jump_started   (on_jump_start)    -> jump   -> every enemy within an area around the
##   takeoff point (jump_radius, widened by Explosion/Linger in the chain)
## on_block, on_dodge_start and hurt are emitted but left unrouted for now (Designer).
##
## Also owns the "is it equipped" rule: it points PlayerController.ability_gate at the board,
## so a move whose ability perk isn't placed doesn't happen at all (Thomas: abilities are perks),
## and keeps the player's max Guard in step with the Block perk's level.

const EVENT_LABELS := {
	&"normal_attack": "Normal Attack hit",
	&"special_attack": "Special Attack hit",
	&"block": "Parry",
	&"dash": "Dodge through",
	&"jump": "Jump",
}

@export var player: PlayerController
@export var game_gui: GameGui

@export_group("Jump area")
## Radius in pixels of Jump's area around the takeoff point, before modifiers.
@export var jump_radius: float = 80.0
## Pixels added per meter of radius from area modifiers (Explosion, Linger), whose radius is
## authored in meters.
@export var pixels_per_meter: float = 16.0

func _ready() -> void:
	player.ability_gate = is_equipped
	player.attack_landed.connect(_on_attack_landed)
	player.parried.connect(func(hit: Hit): fire(&"block", _enemy_of(hit)))
	player.dodged_through.connect(func(hit: Hit): fire(&"dash", _enemy_of(hit)))
	player.jump_started.connect(_on_jump_started)
	game_gui.board.board_recomputed.connect(func(_dirty): _sync_max_guard())
	_sync_max_guard()

## Resolves ability_id's chain against enemy (or nothing when null). Returns the EffectContext,
## or null when that ability isn't on the board.
func fire(ability_id: StringName, enemy: Enemy) -> EffectContext:
	var target: DummyTarget = enemy.dummy_target if enemy else null
	return game_gui.trigger_ability(ability_id, EVENT_LABELS.get(ability_id, String(ability_id)), target)

func is_equipped(ability_id: StringName) -> bool:
	return game_gui.ability_controller.find_placed(game_gui.board, ability_id) != null

## Jump's area in pixels for a resolved Jump chain.
func jump_area_radius(context: EffectContext) -> float:
	return jump_radius + context.radius * pixels_per_meter

## Resolves the Jump chain once at the takeoff point and applies it to every enemy inside the
## area. With nobody inside it still resolves (and logs). Returns the enemies hit.
func fire_jump_area(origin: Vector2) -> Array[Enemy]:
	var hit: Array[Enemy] = []
	var context := fire(&"jump", null)
	if context == null:
		return hit
	var radius := jump_area_radius(context)
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy and enemy.global_position.distance_to(origin) <= radius:
			AbilityActivator.apply_to(enemy.dummy_target, context)
			hit.append(enemy)
	return hit

func _on_jump_started() -> void:
	fire_jump_area(player.global_position)

func _on_attack_landed(enemy: Enemy, ability_id: StringName) -> void:
	fire(ability_id, enemy)

func _sync_max_guard() -> void:
	player.set_max_guard(BlockPerkDefinition.max_guard_on(game_gui.board))

static func _enemy_of(hit: Hit) -> Enemy:
	return hit.source as Enemy
