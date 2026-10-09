class_name EnemyAttacker
extends Area2D
## Gives an Enemy a single repeating melee attack with a telegraph: wait `interval`, flash the
## enemy white (parryable) or red (unblockable) for `telegraph_time`, then strike everything in
## this Area2D's shape that can receive a hit (PlayerController.receive_hit). Add it as a child
## of an Enemy, with its own CollisionShape2D as the strike reach. It turns to face the player
## before each telegraph (see _face_nearest_target).
##
## Deliberately the simplest possible attacker — no movement, no pattern variety — enough to
## test block/parry/dodge timing against. A real enemy AI replaces the loop in _physics_process
## while keeping the telegraph -> strike contract.

signal telegraph_started(kind: Hit.Kind)
signal struck(hit: Hit, result: Hit.Result)

const COLOR_PARRYABLE := Color(1, 1, 1)
const COLOR_UNBLOCKABLE := Color(1, 0.15, 0.15)

@export var kind: Hit.Kind = Hit.Kind.PARRYABLE
@export var damage: float = 15.0
## Seconds between the end of one strike and the start of the next telegraph.
@export var interval: float = 1.5
## Warning time before the strike lands. Design start values: basic 0.6 s, red 0.8 s.
@export var telegraph_time: float = 0.6
## Set false to keep the enemy passive (tests flip it on when they need it).
@export var active: bool = true
## The node whose `modulate` flashes during the telegraph. Defaults to the parent Enemy.
@export var flash_target: CanvasItem

enum State { IDLE, TELEGRAPH }

var _state := State.IDLE
var _timer := 0.0

func _ready() -> void:
	monitoring = true
	monitorable = false
	if flash_target == null:
		flash_target = get_parent() as CanvasItem
	_timer = interval

func _physics_process(delta: float) -> void:
	if not active:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _state == State.IDLE:
		start_telegraph()
	else:
		strike()

func start_telegraph() -> void:
	_face_nearest_target()
	_state = State.TELEGRAPH
	_timer = telegraph_time
	if flash_target:
		flash_target.modulate = COLOR_UNBLOCKABLE if kind == Hit.Kind.UNBLOCKABLE else COLOR_PARRYABLE * 1.6
	telegraph_started.emit(kind)

## Resolves the hit against every receiver currently inside the reach shape.
func strike() -> void:
	_state = State.IDLE
	_timer = interval
	if flash_target:
		flash_target.modulate = Color(1, 1, 1)
	for body in get_overlapping_bodies():
		if body.has_method(&"receive_hit"):
			var hit := Hit.new(damage, kind, get_parent())
			var result: Hit.Result = body.receive_hit(hit)
			struck.emit(hit, result)

func is_telegraphing() -> bool:
	return _state == State.TELEGRAPH

## Mirrors the reach shapes to the player's side (same trick PlayerController uses for its own
## hitbox) rather than flipping this node's scale, which 2D physics handles poorly.
func _face_nearest_target() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return
	var side := -1.0 if player.global_position.x < global_position.x else 1.0
	for child in get_children():
		if child is CollisionShape2D:
			child.position.x = abs(child.position.x) * side
