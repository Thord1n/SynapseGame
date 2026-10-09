class_name Enemy
extends Area2D
## A basic, invincible test dummy — the "real target" ROADMAP.md's item 1 was missing. Extends
## Area2D (not just Node2D) specifically so PlayerController's melee hitbox (also an Area2D)
## can detect it via area_entered — see _on_hitbox_area_entered there. Unlike
## the throwaway DummyTarget.new() every ability trigger used to create and discard, this is a
## persistent, visible, positioned entity in the game world: damage taken accumulates across
## every trigger instead of resetting each time, and it's visible in main.tscn's World rather
## than existing only as a number in the combat log. "Invincible" is literal — nothing here
## checks health or ever removes it; take_damage() just keeps accumulating.
##
## Wraps a DummyTarget (scripts/combat/dummy_target.gd) rather than being one, since
## AbilityActivator.activate()/activate_with_steps() take a `target: DummyTarget` specifically,
## and DummyTarget is a RefCounted (no position/visuals of its own) while this needs to be a
## scene node. Composition over trying to make one class do both jobs.

signal damage_received(amount: float, total: float)

var dummy_target := DummyTarget.new()

@onready var damage_label: Label = $DamageLabel

func _ready() -> void:
	dummy_target.target_name = "Test Dummy"
	_refresh_label()

## Thin passthrough so callers that only have an Enemy reference (not its dummy_target) can
## still deal damage the same way AbilityActivator does internally.
func take_damage(amount: float) -> void:
	dummy_target.take_damage(amount)
	damage_received.emit(amount, dummy_target.damage_taken)
	_refresh_label()

## Redraws the damage readout. Public for callers that damage dummy_target directly (e.g.
## AbilityActivator via TriggerRouter) rather than through take_damage().
func refresh() -> void:
	_refresh_label()

func _refresh_label() -> void:
	damage_label.text = "%s\n%s dmg taken" % [dummy_target.target_name, PerkDefinition.format_number(dummy_target.damage_taken)]
