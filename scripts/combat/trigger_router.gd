class_name TriggerRouter
extends Node
## Connects the player's gameplay events to the SynapseGrid: when an ability's event fires, the
## chain headed by that ability (whatever modifiers are wired to it on the board) is resolved
## and applied to whoever the event involves. This is the "abilities just trigger what's in the
## grid" rule; it replaces resolving chains on raw keypresses (GameGui.trigger_on_keypress).
##
## Event -> ability chain -> target:
## - attack_landed  (on_hit)           -> the swing's ability (normal/special attack) -> the enemy hit
## - parried        (on_parry)         -> guard  -> the attacker
## - dodged_through (on_dodge_through) -> dash   -> the attacker
## - jump_started   (on_jump_start)    -> jump   -> nobody yet (resolved and logged only)
## on_block, on_dodge_start and hurt are left unrouted for now (Designer to confirm whether a
## plain block should fire the Guard chain too).
##
## If an ability isn't on the board, its event still happens physically but adds nothing —
## except attack_landed, which falls back to the swing's flat placeholder damage so a hit always
## does something.

const EVENT_LABELS := {
	&"normal_attack": "Normal Attack hit",
	&"special_attack": "Special Attack hit",
	&"guard": "Parry",
	&"dash": "Dodge through",
	&"jump": "Jump",
}

@export var player: PlayerController
@export var game_gui: GameGui

func _ready() -> void:
	player.attack_landed.connect(_on_attack_landed)
	player.parried.connect(func(hit: Hit): fire(&"guard", _enemy_of(hit)))
	player.dodged_through.connect(func(hit: Hit): fire(&"dash", _enemy_of(hit)))
	player.jump_started.connect(func(): fire(&"jump", null))

## Resolves ability_id's chain against enemy (or nothing when null). Returns the EffectContext,
## or null when that ability isn't on the board.
func fire(ability_id: StringName, enemy: Enemy) -> EffectContext:
	var target: DummyTarget = enemy.dummy_target if enemy else null
	var context := game_gui.trigger_ability(ability_id, EVENT_LABELS.get(ability_id, String(ability_id)), target)
	if context and enemy:
		enemy.damage_received.emit(context.damage * context.repeat_count, enemy.dummy_target.damage_taken)
		enemy.refresh()
	return context

func _on_attack_landed(enemy: Enemy, ability_id: StringName) -> void:
	if fire(ability_id, enemy) == null:
		enemy.take_damage(PlayerController.PLACEHOLDER_MELEE_DAMAGE)

static func _enemy_of(hit: Hit) -> Enemy:
	return hit.source as Enemy
