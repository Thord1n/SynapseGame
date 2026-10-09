class_name Enemy
extends Area2D
## A basic, invincible test dummy — the "real target" ROADMAP.md's item 1 was missing. Extends
## Area2D (not just Node2D) specifically so PlayerController's melee hitbox (also an Area2D)
## can detect it via area_entered — see _on_hitbox_area_entered there. Unlike
## the throwaway DummyTarget.new() every ability trigger used to create and discard, this is a
## persistent, visible, positioned entity in the game world: damage taken accumulates across
## every trigger instead of resetting each time, and it's visible in main.tscn's World rather
## than existing only as a number in the combat log. "Invincible" is literal — nothing here
## checks health or ever removes it; take_damage() just keeps accumulating. It can be stunned
## by Shock buildup, which pauses any EnemyAttacker children (see the Shock group below).
##
## Wraps a DummyTarget (scripts/combat/dummy_target.gd) rather than being one, since
## AbilityActivator.activate()/activate_with_steps() take a `target: DummyTarget` specifically,
## and DummyTarget is a RefCounted (no position/visuals of its own) while this needs to be a
## scene node. Composition over trying to make one class do both jobs.

signal damage_received(amount: float, total: float)
signal shock_changed(buildup: float, maximum: float)
signal stunned(duration: float)

## Shock buildup (Thomas: the one exception to "no stagger" — Shock only). Each Shock
## application adds shock_per_application x its strength; at shock_max the enemy is stunned:
## its current attack and telegraph are cancelled for stun_duration, buildup resets, and it
## can't build up again until stun_immunity seconds after the stun ends. Buildup drops back
## to 0 after shock_decay_delay seconds without a new application.
@export_group("Shock")
@export var shock_max: float = 100.0
@export var shock_per_application: float = 35.0
@export var shock_decay_delay: float = 2.0
@export var stun_duration: float = 1.5
@export var stun_immunity: float = 3.0

## Placeholder hit feedback so dealing damage reads on screen (Thomas: test damage dealing
## first). The final per-modifier VFX/SFX signatures are the Artist's; these are grey-box.
@export_group("Hit feedback")
@export var flash_seconds: float = 0.08
@export var knockback_pixels: float = 8.0
@export var number_rise: float = 40.0
@export var number_seconds: float = 0.7
## Window for the DPS readout on the label.
@export var dps_window: float = 5.0

const ELEMENT_COLORS := {
	ElementalPerkDefinition.Element.FIRE: Color(1.0, 0.55, 0.2),
	ElementalPerkDefinition.Element.ICE: Color(0.5, 0.85, 1.0),
	ElementalPerkDefinition.Element.SHOCK: Color(1.0, 0.95, 0.35),
}

var dummy_target := DummyTarget.new()
var shock_buildup: float = 0.0

var _time := 0.0
var _last_shock_at := -INF
var _stunned_until := -INF
var _immune_until := -INF
var _was_stunned := false

@onready var damage_label: Label = $DamageLabel
@onready var body: CanvasItem = get_node_or_null(^"Polygon2D")

## [time, amount] pairs inside dps_window, for the DPS readout.
var _recent_hits: Array = []
var _body_tween: Tween

const GROUP := &"enemies"

func _ready() -> void:
	add_to_group(GROUP)
	dummy_target.target_name = "Test Dummy"
	dummy_target.damaged.connect(_on_damaged)
	dummy_target.effect_applied.connect(_on_effect_applied)
	_refresh_label()

func _physics_process(delta: float) -> void:
	_time += delta
	if shock_buildup > 0.0 and _time - _last_shock_at >= shock_decay_delay:
		_set_shock(0.0)
	if is_stunned() != _was_stunned:
		_was_stunned = is_stunned()
		_set_attackers_paused(_was_stunned)
		_refresh_label()
	elif not _recent_hits.is_empty():
		_refresh_label() # let the DPS readout decay

## Thin passthrough so callers that only have an Enemy reference (not its dummy_target) can
## still deal damage the same way AbilityActivator does internally.
func take_damage(amount: float) -> void:
	dummy_target.take_damage(amount)

func is_stunned() -> bool:
	return _time < _stunned_until

func is_stun_immune() -> bool:
	return is_stunned() or _time < _immune_until

func _on_damaged(amount: float) -> void:
	_recent_hits.append([_time, amount])
	damage_received.emit(amount, dummy_target.damage_taken)
	if amount > 0.0:
		_show_hit(amount)
	_refresh_label()

## DPS over the last dps_window seconds.
func recent_dps() -> float:
	while not _recent_hits.is_empty() and _time - _recent_hits[0][0] > dps_window:
		_recent_hits.pop_front()
	var total := 0.0
	for hit in _recent_hits:
		total += hit[1]
	return total / dps_window

## Flash, a small knock away from the player, and a rising damage number.
func _show_hit(amount: float) -> void:
	_spawn_number(PerkDefinition.format_number(amount), Color.WHITE)
	if body == null:
		return
	var away := 1.0
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player:
		away = signf(global_position.x - player.global_position.x)
		if away == 0.0:
			away = 1.0
	if _body_tween:
		_body_tween.kill()
	body.self_modulate = Color(3, 3, 3)
	(body as Node2D).position = Vector2(knockback_pixels * away, 0)
	_body_tween = create_tween().set_parallel()
	_body_tween.tween_property(body, ^"self_modulate", Color.WHITE, flash_seconds)
	_body_tween.tween_property(body, ^"position", Vector2.ZERO, flash_seconds * 2.0)

func _spawn_number(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(randf_range(-24, 4), -60)
	label.z_index = 10
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, ^"position:y", label.position.y - number_rise, number_seconds)
	tween.tween_property(label, ^"modulate:a", 0.0, number_seconds).set_delay(number_seconds * 0.4)
	tween.chain().tween_callback(label.queue_free)

func _on_effect_applied(effect: Dictionary) -> void:
	var element = effect.get("element")
	if ELEMENT_COLORS.has(element):
		_spawn_number(String(effect.get("id", "")).capitalize(), ELEMENT_COLORS[element])
	if effect.get("element") != ElementalPerkDefinition.Element.SHOCK or is_stun_immune():
		return
	_last_shock_at = _time
	_set_shock(shock_buildup + shock_per_application * float(effect.get("strength", 1.0)))
	if shock_buildup >= shock_max:
		_stun()

func _stun() -> void:
	_stunned_until = _time + stun_duration
	_immune_until = _stunned_until + stun_immunity
	_set_shock(0.0)
	_was_stunned = true
	_set_attackers_paused(true)
	stunned.emit(stun_duration)
	_refresh_label()

func _set_shock(value: float) -> void:
	value = clampf(value, 0.0, shock_max)
	if value != shock_buildup:
		shock_buildup = value
		shock_changed.emit(shock_buildup, shock_max)
		_refresh_label()

func _set_attackers_paused(paused: bool) -> void:
	for child in get_children():
		if child is EnemyAttacker:
			child.set_stunned(paused)

func _refresh_label() -> void:
	var text := "%s\n%s dmg taken\n%s DPS" % [dummy_target.target_name,
		PerkDefinition.format_number(dummy_target.damage_taken), PerkDefinition.format_number(snappedf(recent_dps(), 0.1))]
	if is_stunned():
		text += "\nSTUNNED"
	elif shock_buildup > 0.0:
		text += "\nShock %d%%" % int(100.0 * shock_buildup / shock_max)
	damage_label.text = text
