class_name FollowCamera
extends Camera2D
## Follows the player, leading slightly in the facing direction and trailing vertically, so
## the view stays ahead of fast movement (Designer's movement-feel-spec.md, section 5). Use
## Camera2D's own limit_* properties to keep it inside the level.

@export var target: PlayerController
## Pixels ahead of the player in their facing direction.
@export var lead: float = 40.0
## How quickly the camera catches up (higher = snappier), horizontally and vertically.
@export var horizontal_follow: float = 10.0
@export var vertical_follow: float = 5.0

func _ready() -> void:
	if target:
		global_position = target.global_position

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var goal := target.global_position + Vector2(lead * target.facing_direction, 0.0)
	global_position.x = lerpf(global_position.x, goal.x, minf(1.0, horizontal_follow * delta))
	global_position.y = lerpf(global_position.y, goal.y, minf(1.0, vertical_follow * delta))
