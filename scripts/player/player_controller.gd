class_name PlayerController
extends CharacterBody2D
## The player's in-game actions (ROADMAP.md item 2 — "no player movement"; the `World/Player`
## node in main.tscn was purely decorative before this). Reads project.godot's real Input Map
## actions (Left/Right/Jump/Block/Dash/Normal_attack, added directly in the editor —
## Special_attack exists there too but isn't read here yet). Movement, Jump (menu-gated via
## `menu`), Block/Parry, Dodge (the Dash action) and a melee-range Normal Attack (a timed
## hitbox — see `hitbox`/_on_hitbox_area_entered) are real; Special Attack is still a stub, and the
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
##
## Defense (receive_hit): the player has Health, and a Guard meter used only by Block. Per the
## Designer's numbers (design/answers-for-programmer.md), all exported so they can be tuned:
## - Parry: Block pressed within `parry_window` before a parryable hit lands. No damage, +1
##   Charge, emits `parried`.
## - Block: held longer than that. Takes `block_damage_taken` of the damage and drains Guard;
##   Guard at 0 breaks (stunned for `guard_break_stun`). Guard regenerates when not blocking.
## - Unblockable hits ignore Block and Parry entirely: only a dodge avoids them.
## - Dodge: a fixed-length dash in facing_direction with i-frames between `iframe_start` and
##   `iframe_end`, then `dodge_cooldown` before the next one.
## The `parried`/`blocked`/`dodged_through`/`hurt`/`dodge_started` signals are the trigger events
## perks will hook later ("on_parry" etc.) — nothing listens to them for perk effects yet.

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

signal health_changed(current: float, maximum: float)
signal guard_changed(current: float, maximum: float)
signal charge_changed(current: int, maximum: int)
signal hurt(hit: Hit)
signal blocked(hit: Hit)
signal parried(hit: Hit)
signal dodged_through(hit: Hit)
signal dodge_started
signal guard_broken
## Health hit 0. The test level has no game-over yet: the player is restored at their spawn
## point right after this fires (see _die).
signal died

@export_group("Health")
@export var max_health: float = 100.0

@export_group("Block & Parry")
## Seconds before impact that a Block press still counts as a parry.
@export var parry_window: float = 0.15
## Fraction of a parryable hit's damage that still gets through a (non-parry) block.
@export_range(0.0, 1.0) var block_damage_taken: float = 0.3
@export var max_guard: float = 100.0
@export var guard_drain_per_block: float = 25.0
@export var guard_regen_per_second: float = 30.0
## Not blocking for this long before Guard starts regenerating.
@export var guard_regen_delay: float = 0.5
@export var guard_break_stun: float = 0.8
@export var max_charge: int = 3

@export_group("Dodge")
@export var dodge_distance: float = 120.0
@export var dodge_duration: float = 0.25
## I-frames run from iframe_start to iframe_end seconds into the dodge.
@export var iframe_start: float = 0.05
@export var iframe_end: float = 0.20
@export var dodge_cooldown: float = 0.35

var _is_blocking := false
var facing_direction := 1  # -1 left, 1 right

var health: float
var guard: float
var charge: int = 0
var spawn_position: Vector2

## Own clock advanced in _physics_process, so timing windows behave the same under headless
## tests (which step physics frames) as in real play.
var _time := 0.0
var _block_pressed_at := -INF
var _last_block_released_at := -INF
var _stunned_until := -INF
var _dodge_started_at := -INF
var _dodge_direction := 1

## Set externally by main.gd — this node's own way to check "is the perk-board menu open" so
## physical actions (currently just Jump) can be gated on it being closed, the same as the
## perk-triggered actions in game_gui.gd already are. null (the default, e.g. in a test scene
## that doesn't wire this up) means "always allowed."
var menu: GameGui

@onready var hitbox: Area2D = $AttackHitbox_Area2D

func _ready() -> void:
	add_to_group(&"player")
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	health = max_health
	guard = max_guard
	spawn_position = global_position

func _physics_process(delta: float) -> void:
	_time += delta
	_regen_guard(delta)
	if is_dodging():
		_dodge_step(delta)
	elif is_stunned():
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
	else:
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
	if is_on_floor() and not is_stunned():
		velocity.y = JUMP_VELOCITY

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"Block"):
		block(true)
	elif event.is_action_released(&"Block"):
		block(false)
	# Menu-gated (unlike Block above) so the player doesn't jump around in the background while
	# arranging perks — see the `menu` field doc and game_gui.gd's matching `visible` guard.
	elif menu != null and menu.visible:
		return
	elif event.is_action_pressed(&"Jump"):
		jump()
	elif event.is_action_pressed(&"Dash"):
		dash()
	elif event.is_action_pressed(&"Normal_attack"):
		normal_attack()

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area is Enemy:
		(area as Enemy).take_damage(PLACEHOLDER_MELEE_DAMAGE)

## Faces the hitbox toward facing_direction and enables it briefly, dealing
## PLACEHOLDER_MELEE_DAMAGE to whatever Enemy it overlaps (_on_hitbox_area_entered). Called
## from the "Normal_attack" input, on the same keypress as game_gui.gd's separate perk-chain
## resolution (which still only logs its number). TODO: the real version
## replaces PLACEHOLDER_MELEE_DAMAGE by resolving the actual Normal_attack perk chain here too
## (AbilityController against `board`, the same way game_gui.gd._trigger_named_ability() does —
## see the class doc), once this node has a `board` reference to resolve it against.
func normal_attack() -> void:
	if is_stunned() or is_dodging():
		return
	hitbox.position.x = abs(hitbox.position.x) * facing_direction
	hitbox.monitoring = true
	await get_tree().create_timer(0.15).timeout
	hitbox.monitoring = false

## Same TODO as normal_attack(), against the "special_attack" perk id instead.
func special_attack() -> void:
	pass

## The dodge. Per the Designer, Dash IS the dodge: this is the physical movement + i-frames,
## always available; the perk board's "Dash" ability (AbilityController, same keypress) is what
## perks will hang extra effects on. Returns false if it couldn't start (cooldown, stunned,
## already dodging).
func dash() -> bool:
	if is_dodging() or is_stunned():
		return false
	if _time < _dodge_started_at + dodge_duration + dodge_cooldown:
		return false
	_dodge_started_at = _time
	_dodge_direction = facing_direction
	block(false)
	dodge_started.emit()
	return true

func is_dodging() -> bool:
	return _time < _dodge_started_at + dodge_duration

func is_invulnerable() -> bool:
	var t := _time - _dodge_started_at
	return t >= iframe_start and t < iframe_end

func is_stunned() -> bool:
	return _time < _stunned_until

func is_blocking() -> bool:
	return _is_blocking

func _dodge_step(_delta: float) -> void:
	velocity = Vector2(_dodge_direction * dodge_distance / dodge_duration, 0.0)
	move_and_slide()

## Wired to the "Block" action in _unhandled_input() (press to start, release to stop). The
## press time is what receive_hit() checks against parry_window. Can't start while stunned or
## dodging.
func block(active: bool) -> void:
	if active == _is_blocking:
		return
	if active:
		if is_stunned() or is_dodging():
			return
		_block_pressed_at = _time
	else:
		_last_block_released_at = _time
	_is_blocking = active

## The single entry point for damage to the player. Returns how the hit resolved; see the class
## doc for the rules.
func receive_hit(hit: Hit) -> Hit.Result:
	if health <= 0.0:
		return Hit.Result.IGNORED
	if is_invulnerable():
		dodged_through.emit(hit)
		return Hit.Result.DODGED
	if hit.kind == Hit.Kind.PARRYABLE and _is_blocking:
		if _time - _block_pressed_at <= parry_window:
			_set_charge(charge + 1)
			parried.emit(hit)
			return Hit.Result.PARRIED
		_set_guard(guard - guard_drain_per_block)
		_take_damage(hit.damage * block_damage_taken)
		blocked.emit(hit)
		if guard <= 0.0:
			_break_guard()
		return Hit.Result.BLOCKED
	_take_damage(hit.damage)
	hurt.emit(hit)
	return Hit.Result.HIT

## Spends Charge (the Special Attack's cost per the design doc). False if there isn't enough.
func spend_charge(amount: int = 1) -> bool:
	if charge < amount:
		return false
	_set_charge(charge - amount)
	return true

func _take_damage(amount: float) -> void:
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()

func _break_guard() -> void:
	block(false)
	_stunned_until = _time + guard_break_stun
	guard_broken.emit()

func _regen_guard(delta: float) -> void:
	if _is_blocking or guard >= max_guard or is_stunned():
		return
	if _time - _last_block_released_at < guard_regen_delay:
		return
	_set_guard(guard + guard_regen_per_second * delta)

func _set_guard(value: float) -> void:
	var clamped := clampf(value, 0.0, max_guard)
	if clamped != guard:
		guard = clamped
		guard_changed.emit(guard, max_guard)

func _set_charge(value: int) -> void:
	var clamped := clampi(value, 0, max_charge)
	if clamped != charge:
		charge = clamped
		charge_changed.emit(charge, max_charge)

## No game-over screen in the test level yet: announce it, then put the player back at the
## spawn point with full Health and Guard.
func _die() -> void:
	died.emit()
	block(false)
	global_position = spawn_position
	velocity = Vector2.ZERO
	_stunned_until = -INF
	_dodge_started_at = -INF
	health = max_health
	health_changed.emit(health, max_health)
	_set_guard(max_guard)
