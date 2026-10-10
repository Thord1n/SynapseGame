class_name PlayerController
extends CharacterBody2D
## The player's physical actions. Reads project.godot's Input Map actions (Left/Right/Jump/
## Block/Dash/Normal_attack/Special_attack, added directly in the editor): movement, Jump,
## Block (Block + Parry on one button), Dodge (the Dash action), and Normal/Special Attack (a
## timed melee hitbox — see `hitbox`/_on_hitbox_area_entered). Each move works only while its
## ability perk is on the grid (see ability_gate); what the rest of its chain adds is resolved
## when the matching event fires (see the signals below and TriggerRouter,
## scripts/combat/trigger_router.gd).
##
## Distinct from PlayerCharacter (scripts/player/player_character.gd, a child of
## GameGui/MenuLayer) and from AbilityController (scripts/player/ability_controller.gd, which
## resolves an ability's perk chain). Those predate this script and still aren't fully merged
## into one "player".
##
## Defense (receive_hit): the player has Health, and a Guard meter used only by Block. Per the
## Designer's numbers (design/answers-for-programmer.md), all exported so they can be tuned:
## - Parry: Block pressed within `parry_window` before a parryable hit lands. No damage, emits
##   `parried`. Block and Parry are one ability (the Block perk) on one button: hold = block, a
##   press just before impact = parry. Block's level sets max_guard (see set_max_guard).
## - Block: held longer than that. Takes `block_damage_taken` of the damage and drains Guard;
##   Guard at 0 breaks (stunned for `guard_break_stun`). Guard regenerates when not blocking.
## - Unblockable hits ignore Block and Parry entirely: only a dodge avoids them.
## - Dodge: a fixed-length dash in facing_direction with i-frames between `iframe_start` and
##   `iframe_end`, then `dodge_cooldown` before the next one.
## The `attack_landed`/`parried`/`blocked`/`dodged_through`/`hurt`/`dodge_started`/`jump_started`
## signals are the grid's trigger events (on_hit, on_parry, ...); TriggerRouter listens to them.

## Flat placeholder amount the melee hitbox deals directly (see _on_hitbox_area_entered) — not
## routed through the perk system yet. TODO: the "real" version of this reuses AbilityController
## against the Normal_attack perk chain the same way game_gui.gd's own trigger does, once this
## node has a `board` reference to resolve that chain against (see normal_attack()'s TODO) —
## this flat number is a placeholder specifically so the hitbox that already exists does
## *something* observable in the meantime, not a design decision about melee damage.
const PLACEHOLDER_MELEE_DAMAGE := 10.0

signal health_changed(current: float, maximum: float)
signal guard_changed(current: float, maximum: float)
signal hurt(hit: Hit)
signal blocked(hit: Hit)
signal parried(hit: Hit)
signal dodged_through(hit: Hit)
signal dodge_started
## Fires at takeoff (Thomas's call: Jump's grid trigger is on_jump_start, not on landing).
signal jump_started
## The melee hitbox touched an enemy. ability_id is the swing's ability (&"normal_attack" or
## &"special_attack"); TriggerRouter resolves that ability's grid chain against the enemy.
signal attack_landed(enemy: Enemy, ability_id: StringName)
signal guard_broken
## The player tried a move whose ability perk isn't on the grid (see _require).
signal ability_missing(ability_id: StringName)
## Health hit 0. The test level has no game-over yet: the player is restored at their spawn
## point right after this fires (see _die).
signal died

## Movement feel (Designer's design/movement-feel-spec.md, Phase 1: Nine Sols is mostly about
## movement). All first guesses, tuned by feel. Jump and Dash features need their perks.
@export_group("Run")
@export var run_speed: float = 300.0
## Seconds from standing to full speed, and from full speed to stopped with no input.
@export var accel_time: float = 0.06
@export var decel_time: float = 0.05
## Fraction of ground acceleration available in the air.
@export_range(0.0, 1.0) var air_control: float = 0.85

@export_group("Jump")
@export var jump_velocity: float = -460.0
@export var gravity_rising: float = 980.0
@export var gravity_falling: float = 1550.0
## Releasing Jump while rising multiplies upward speed by this (tap = short hop).
@export_range(0.0, 1.0) var jump_cut: float = 0.5
## Near the apex (|vertical speed| under apex_speed) gravity is scaled by apex_gravity_scale.
@export var apex_speed: float = 60.0
@export var apex_gravity_scale: float = 0.5
@export var terminal_fall_speed: float = 700.0
## Can still jump this long after walking off a ledge.
@export var coyote_time: float = 0.10
## A Jump press this long before landing still jumps.
@export var jump_buffer: float = 0.12

@export_group("Attack")
## How long the melee hitbox stays on per swing.
@export var swing_duration: float = 0.15
## Horizontal speed multiplier while swinging (attacks don't stop the player).
@export_range(0.0, 1.0) var swing_move_scale: float = 0.6
## An attack pressed this long before the current swing ends chains into the next one.
@export var attack_buffer: float = 0.1

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

@export_group("Special Attack")
@export var special_attack_cooldown: float = 3.0

@export_group("Dodge")
@export var dodge_distance: float = 150.0
@export var dodge_duration: float = 0.22
## I-frames run from iframe_start to iframe_end seconds into the dodge.
@export var iframe_start: float = 0.05
@export var iframe_end: float = 0.20
@export var dodge_cooldown: float = 0.35
## A Dash press this long before the dodge is available again still dodges.
@export var dodge_buffer: float = 0.1
## Dashes allowed per airtime (reset on landing). 0 = ground only.
@export var air_dashes: int = 1

var _is_blocking := false
var facing_direction := 1  # -1 left, 1 right

var health: float
var guard: float
var spawn_position: Vector2

## Own clock advanced in _physics_process, so timing windows behave the same under headless
## tests (which step physics frames) as in real play.
var _time := 0.0
var _block_pressed_at := -INF
var _last_block_released_at := -INF
var _stunned_until := -INF
var _dodge_started_at := -INF
var _dodge_direction := 1
var _special_ready_at := -INF
var _last_on_floor_at := -INF
var _jump_pressed_at := -INF
var _dash_pressed_at := -INF
var _air_dashes_used := 0
var _swing_until := -INF
var _attack_pressed_at := -INF
var _buffered_attack: StringName = &""

## The shared "is this ability equipped" check (Thomas: abilities are perks — no perk on the
## grid, no move). Takes an ability perk id (&"jump", &"block", &"dash", &"normal_attack",
## &"special_attack"). Checked live, so removing a perk mid-action stops that move at once. TriggerRouter points it at the SynapseGrid board; the default allows
## everything so scenes without a board (unit-style tests) still move.
var ability_gate: Callable = func(_ability_id: StringName) -> bool: return true

func has_ability(ability_id: StringName) -> bool:
	return ability_gate.call(ability_id)

## has_ability for a move the player just tried: when the perk is missing, also emits
## ability_missing so the HUD can flash a brief cue (Thomas: on press only, no lasting marker).
func _require(ability_id: StringName) -> bool:
	if has_ability(ability_id):
		return true
	ability_missing.emit(ability_id)
	return false
var _swing_ability: StringName = &"normal_attack"

@onready var hitbox: Area2D = $AttackHitbox_Area2D

func _ready() -> void:
	add_to_group(&"player")
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	health = max_health
	guard = max_guard
	spawn_position = global_position

func _physics_process(delta: float) -> void:
	_time += delta
	if _is_blocking and not has_ability(&"block"):
		block(false) # Block taken off the grid mid-block
	_regen_guard(delta)
	if is_on_floor() and velocity.y >= 0.0: # not the frame we just jumped from
		_last_on_floor_at = _time
		_air_dashes_used = 0
	_end_swing_if_done()
	_run_buffered_inputs()
	if is_dodging():
		_dodge_step(delta)
	elif is_stunned():
		velocity.x = 0.0
		_apply_gravity(delta)
		move_and_slide()
	else:
		move(delta)

## Reads project.godot's Left/Right actions, accelerating toward run_speed (accel_time /
## decel_time, scaled by air_control in the air and swing_move_scale mid-swing), then applies
## gravity. get_axis() works for keys and analog sticks alike.
func move(delta: float) -> void:
	var direction := Input.get_axis(&"Left", &"Right")
	if direction != 0:
		facing_direction = signi(int(signf(direction)))
	var target := direction * run_speed * (swing_move_scale if is_swinging() else 1.0)
	var step := run_speed / (accel_time if direction != 0 else decel_time) * delta
	if not is_on_floor():
		step *= air_control
	velocity.x = move_toward(velocity.x, target, step)
	_apply_gravity(delta)
	move_and_slide()

## Rising and falling gravity differ (falls are faster), with a float near the apex and a
## capped fall speed.
func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity_rising if velocity.y < 0.0 else gravity_falling
	if absf(velocity.y) < apex_speed:
		g *= apex_gravity_scale
	velocity.y = minf(velocity.y + g * delta, terminal_fall_speed)

## Wired to the "Jump" action in _unhandled_input() below. Jumps on the floor or within
## coyote_time of leaving it; otherwise the press is buffered for jump_buffer seconds.
## Emits jump_started at takeoff, which TriggerRouter turns into the Jump chain.
func jump() -> void:
	if not _require(&"jump"):
		return
	_jump_pressed_at = _time
	_try_buffered_jump()

func can_jump() -> bool:
	return not is_stunned() and (is_on_floor() or _time - _last_on_floor_at <= coyote_time)

func _try_buffered_jump() -> void:
	if _time - _jump_pressed_at > jump_buffer or not can_jump() or not has_ability(&"jump"):
		return
	_jump_pressed_at = -INF
	_last_on_floor_at = -INF # no second coyote jump
	velocity.y = jump_velocity
	jump_started.emit()

## Releasing Jump while rising cuts the jump short (variable jump height).
func release_jump() -> void:
	if velocity.y < 0.0:
		velocity.y *= jump_cut

func _run_buffered_inputs() -> void:
	_try_buffered_jump()
	if _time - _dash_pressed_at <= dodge_buffer and _can_dash() and has_ability(&"dash"):
		_start_dash()
	if _buffered_attack != &"" and not is_swinging():
		var id := _buffered_attack
		_buffered_attack = &""
		if _time - _attack_pressed_at <= attack_buffer:
			_swing(id)

## Not gated on the perk-board menu: the grid is live (Thomas), so every move keeps working
## while it's open.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"Block"):
		block(true)
	elif event.is_action_released(&"Block"):
		block(false)
	elif event.is_action_pressed(&"Jump"):
		jump()
	elif event.is_action_released(&"Jump"):
		release_jump()
	elif event.is_action_pressed(&"Dash"):
		dash()
	elif event.is_action_pressed(&"Normal_attack"):
		normal_attack()
	elif event.is_action_pressed(&"Special_attack"):
		special_attack()

func _on_hitbox_area_entered(area: Area2D) -> void:
	if not area is Enemy:
		return
	if attack_landed.get_connections().is_empty():
		# Nothing resolves the perk chain (e.g. a test scene with no TriggerRouter): fall back to
		# the flat placeholder so a swing still does something observable.
		(area as Enemy).take_damage(PLACEHOLDER_MELEE_DAMAGE)
	else:
		attack_landed.emit(area as Enemy, _swing_ability)

## Faces the hitbox toward facing_direction and enables it briefly. Each Enemy it touches emits
## attack_landed(enemy, &"normal_attack"); TriggerRouter resolves the Normal Attack chain from
## the SynapseGrid against that enemy. Called from the "Normal_attack" input.
func normal_attack() -> void:
	_swing(&"normal_attack")

## Same swing as normal_attack(), resolving the Special Attack chain instead, gated by
## special_attack_cooldown (the Designer's plain cooldown, no resource cost). Returns false while
## cooling down, stunned or dodging.
func special_attack() -> bool:
	if _time < _special_ready_at or is_stunned() or is_dodging() or not _require(&"special_attack"):
		return false
	_special_ready_at = _time + special_attack_cooldown
	_swing(&"special_attack")
	return true

func special_attack_cooldown_left() -> float:
	return maxf(0.0, _special_ready_at - _time)

## A swing pressed mid-swing is buffered (attack_buffer) and chains when this one ends.
func _swing(ability_id: StringName) -> void:
	if is_stunned() or is_dodging() or not _require(ability_id):
		return
	if is_swinging():
		_buffered_attack = ability_id
		_attack_pressed_at = _time
		return
	_swing_ability = ability_id
	_swing_until = _time + swing_duration
	hitbox.position.x = abs(hitbox.position.x) * facing_direction
	hitbox.monitoring = true

func is_swinging() -> bool:
	return _time < _swing_until

func _end_swing_if_done() -> void:
	if hitbox.monitoring and not is_swinging():
		hitbox.monitoring = false

## The dodge. Per the Designer, Dash IS the dodge: a flat dash (no gravity) in the held
## direction, or facing if none, with i-frames; the grid's Dash chain fires when a hit is
## dodged through (dodged_through). Usable air_dashes times per airtime. Returns false if it
## couldn't start (cooldown, stunned, already dodging, out of air dashes); a press on cooldown
## is buffered for dodge_buffer seconds.
func dash() -> bool:
	if not _require(&"dash"):
		return false
	if not _can_dash():
		_dash_pressed_at = _time
		return false
	_start_dash()
	return true

func _can_dash() -> bool:
	if is_dodging() or is_stunned():
		return false
	if _time < _dodge_started_at + dodge_duration + dodge_cooldown:
		return false
	return (is_on_floor() and velocity.y >= 0.0) or _air_dashes_used < air_dashes

func _start_dash() -> void:
	_dash_pressed_at = -INF
	if not (is_on_floor() and velocity.y >= 0.0):
		_air_dashes_used += 1
	_dodge_started_at = _time
	var held := Input.get_axis(&"Left", &"Right")
	if held != 0.0:
		facing_direction = signi(int(signf(held)))
	_dodge_direction = facing_direction
	block(false)
	dodge_started.emit()

func is_dodging() -> bool:
	return _time < _dodge_started_at + dodge_duration

func is_invulnerable() -> bool:
	var t := _time - _dodge_started_at
	return t >= iframe_start and t < iframe_end

func is_stunned() -> bool:
	return _time < _stunned_until

func is_blocking() -> bool:
	return _is_blocking

func _dodge_step(delta: float) -> void:
	velocity = Vector2(_dodge_direction * dodge_distance / dodge_duration, 0.0)
	move_and_slide()
	if _time + delta >= _dodge_started_at + dodge_duration:
		velocity.x = 0.0 # last step: stop cleanly, no slide

## Wired to the "Block" action in _unhandled_input() (press to start, release to stop). The
## press time is what receive_hit() checks against parry_window. Can't start while stunned or
## dodging.
func block(active: bool) -> void:
	if active == _is_blocking:
		return
	if active:
		if is_stunned() or is_dodging() or not _require(&"block"):
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

## Max Guard comes from the Block perk's level (TriggerRouter calls this when the board
## changes). A full meter stays full; otherwise Guard is clamped to the new maximum.
func set_max_guard(value: float) -> void:
	var was_full := guard >= max_guard
	max_guard = value
	guard = max_guard if was_full else minf(guard, max_guard)
	guard_changed.emit(guard, max_guard)

func _set_guard(value: float) -> void:
	var clamped := clampf(value, 0.0, max_guard)
	if clamped != guard:
		guard = clamped
		guard_changed.emit(guard, max_guard)

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
