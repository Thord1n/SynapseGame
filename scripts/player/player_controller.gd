class_name PlayerController
extends CharacterBody2D
## The player's in-game actions (ROADMAP.md item 2 — "no player movement"; the `World/Player`
## node in main.tscn was purely decorative before this). Reads project.godot's real Input Map
## actions (Left/Right/Jump/Block, added directly in the editor — Normal_attack/Special_attack/
## Dash exist there too but aren't read here, see below). Movement, Jump (menu-gated via
## `menu`), Block, and a melee-range Normal Attack (a timed hitbox — see `hitbox`/
## _on_hitbox_area_entered) are real; Special Attack and Dash are still bare stubs, and the
## melee hitbox deals a flat placeholder amount rather than a real perk-resolved number (see
## PLACEHOLDER_MELEE_DAMAGE) — each remaining gap needs an integration decision that isn't made
## yet (see the TODO on each), not just a body to fill in.
##
## Distinct from PlayerCharacter (scripts/player/player_character.gd, Health/Shield stats,
## currently a child of GameGui/MenuLayer rather than of this node's World) and from
## AbilityController (scripts/player/ability_controller.gd, the *perk-triggered* Jump/Dash/
## Normal Attack/Special Attack that already work today via game_gui.gd's ABILITY_ACTIONS,
## reading the same project.godot actions this script does for Jump/Dash but resolving a perk
## effect instead of moving anything — both fire on the same keypress, deliberately, see
## jump()). All three represent "the player" from different angles that predate this script
## and haven't been fully reconciled — see the TODOs below for where they'd
## meet.

const MOVE_SPEED := 200.0
const JUMP_VELOCITY := -400.0
const GRAVITY := 980.0
## Flat placeholder amount the melee hitbox deals directly (see _on_hitbox_area_entered) — not
## routed through the perk system yet. TODO: the "real" version of this reuses AbilityController
## against the Normal_attack perk chain the same way game_gui.gd's own trigger does, once this
## node has a `board` reference to resolve that chain against (see normal_attack()'s TODO) —
## this flat number is a placeholder specifically so the hitbox that already exists does
## *something* observable in the meantime, not a design decision about melee damage.
const PLACEHOLDER_MELEE_DAMAGE := 10.0

var _is_blocking := false
var facing_direction := 1  # -1 left, 1 right

## Set externally by main.gd — this node's own way to check "is the perk-board menu open" so
## physical actions (currently just Jump) can be gated on it being closed, the same as the
## perk-triggered actions in game_gui.gd already are. null (the default, e.g. in a test scene
## that doesn't wire this up) means "always allowed."
var menu: GameGui

@onready var hitbox: Area2D = $AttackHitbox_Area2D

func _ready() -> void:
	hitbox.area_entered.connect(_on_hitbox_area_entered)

func _physics_process(delta: float) -> void:
	move(delta)

## Reads project.godot's real Left/Right actions (added directly in the editor — no
## keyboard-only Up/Down equivalent is read here, since nothing in this script uses vertical
## movement input yet) and applies gravity. get_axis() works the same regardless of whether an
## action is bound to plain keys (as Left/Right currently are) or an analog stick.
func move(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	var direction := Input.get_axis(&"Left", &"Right")
	
	if direction != 0:
		facing_direction = sign(direction)
		
	velocity.x = direction * MOVE_SPEED
	move_and_slide()

## Wired to the "Jump" action in _unhandled_input() below, gated on `menu` being closed. Jump
## also has a separate, working trigger path via game_gui.gd's ABILITY_ACTIONS (resolves the
## perk-board Jump ability's effect on the same keypress) — both fire together deliberately:
## one moves the physical body, the other resolves whatever perk effect is attached, and
## there's no conflict between them the way wiring normal_attack()/dash() to AbilityController
## directly here would cause (see their TODOs) since this method never touches the perk system.
func jump() -> void:
	if is_on_floor():
		velocity.y = JUMP_VELOCITY

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"Block"):
		block(true)
	elif event.is_action_released(&"Block"):
		block(false)
	# Menu-gated (unlike Block above) so the player doesn't jump around in the background while
	# arranging perks — see the `menu` field doc and game_gui.gd's matching `visible` guard.
	elif event.is_action_pressed(&"Jump") and (menu == null or not menu.visible):
		jump()

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area is Enemy:
		(area as Enemy).take_damage(PLACEHOLDER_MELEE_DAMAGE)

## Faces the hitbox toward facing_direction and enables it briefly, dealing
## PLACEHOLDER_MELEE_DAMAGE to whatever Enemy it overlaps (_on_hitbox_area_entered). Not called
## from any input handler yet (unlike jump()) — nothing presses "Normal_attack" to trigger this
## specific method, only game_gui.gd's separate perk-chain resolution. TODO: the real version
## replaces PLACEHOLDER_MELEE_DAMAGE by resolving the actual Normal_attack perk chain here too
## (AbilityController against `board`, the same way game_gui.gd._trigger_named_ability() does —
## see the class doc), once this node has a `board` reference to resolve it against.
func normal_attack() -> void:
	hitbox.position.x = abs(hitbox.position.x) * facing_direction
	hitbox.monitoring = true
	await get_tree().create_timer(0.15).timeout
	hitbox.monitoring = false

## Same TODO as normal_attack(), against the "special_attack" perk id instead.
func special_attack() -> void:
	pass

## TODO: decide whether this IS the perk board's "Dash" (which already triggers a perk effect
## via AbilityController on project.godot's Dash action) or a separate movement burst/i-frame
## mechanic that Dash's perk effect would layer on top of. Not the same question as normal_attack's —
## Dash already has a working trigger path today; this is a design decision, not a wiring gap.
func dash() -> void:
	pass

## Wired to the "Block" action in _unhandled_input() (press to start, release to stop) — the
## input side is real. TODO: nothing currently reduces PlayerCharacter.current_health/shield
## (no damage-to-player system exists yet), so _is_blocking has nothing to mitigate yet; that's
## the remaining gap, not the input wiring.
func block(active: bool) -> void:
	_is_blocking = active
