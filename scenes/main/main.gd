extends Node2D
## Top-level scene: a minimal 2D game view (World) plus the perk-board GUI as a Tab-toggled
## menu layered on top (MenuLayer/GameGui), plus an always-on-screen combat log (HudLayer) that
## catches GameGui's ability_triggered signal — GameGui's own status_label lives inside a panel
## that's hidden exactly when a trigger can happen, so it can't be the destination for that.

const TOGGLE_ACTION := &"toggle_menu"
## Entries, not lines — each one is now potentially multi-line (action + per-Modifier
## breakdown, see game_gui.gd's _trigger_named_ability), so fewer of them fit comfortably.
const COMBAT_LOG_MAX_ENTRIES := 3

@onready var game_gui: GameGui = $MenuLayer/GameGui
@onready var combat_log_label: Label = $HudLayer/CombatLogLabel
@onready var enemy: Enemy = $World/Enemy
@onready var player: PlayerController = $World/Player

var _combat_log_lines: Array[String] = []

func _ready() -> void:
	_register_toggle_action()
	game_gui.visible = false
	game_gui.ability_triggered.connect(_on_ability_triggered)
	# Ability triggers now deal damage to the persistent Enemy in the world instead of a
	# throwaway target that reset every press — see GameGui.combat_target's own doc comment.
	game_gui.combat_target = enemy.dummy_target
	player.menu = game_gui

## Not in project.godot's [input] section (unlike Jump/Dash/Normal_attack/Special_attack/Block/
## Left/Right/Up/Down, all added directly in the editor) — registered at runtime instead, same
## pattern player_controller.gd's block-adjacent bindings used before those existed. A keyboard
## AND a gamepad binding together, so this doesn't need redoing when a controller is tested.
func _register_toggle_action() -> void:
	if InputMap.has_action(TOGGLE_ACTION):
		return
	InputMap.add_action(TOGGLE_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_TAB
	InputMap.action_add_event(TOGGLE_ACTION, key)
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_START
	InputMap.action_add_event(TOGGLE_ACTION, joy)

## Hiding GameGui is the only state this needs to track — see the `visible` guard in
## game_gui.gd's _unhandled_input for the other half (why triggering only fires while closed).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		game_gui.visible = not game_gui.visible
		get_viewport().set_input_as_handled()

func _on_ability_triggered(text: String) -> void:
	_combat_log_lines.push_front(text)
	if _combat_log_lines.size() > COMBAT_LOG_MAX_ENTRIES:
		_combat_log_lines.resize(COMBAT_LOG_MAX_ENTRIES)
	combat_log_label.text = "\n\n".join(PackedStringArray(_combat_log_lines))
