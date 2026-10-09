extends Node2D
## Top-level scene: a minimal 2D game view (World) plus the perk-board GUI as a Tab-toggled
## menu layered on top (MenuLayer/GameGui), plus an always-on-screen combat log (HudLayer) that
## catches GameGui's ability_triggered signal — GameGui's own status_label lives inside a panel
## that's usually closed when a trigger happens, so it can't be the destination for that. The
## menu never pauses the game or blocks the player: the grid is live (Thomas).

const TOGGLE_ACTION := &"toggle_menu"
## Entries, not lines — each one is now potentially multi-line (action + per-Modifier
## breakdown, see game_gui.gd's _trigger_named_ability), so fewer of them fit comfortably.
const COMBAT_LOG_MAX_ENTRIES := 3

@onready var game_gui: GameGui = $MenuLayer/GameGui
@onready var combat_log_label: Label = $HudLayer/CombatLogLabel
@onready var enemy: Enemy = $World/Enemy
@onready var player: PlayerController = $World/Player
@onready var player_status_label: Label = $HudLayer/PlayerStatusLabel

## How long the "missing perk" cue stays on screen.
const MISSING_CUE_SECONDS := 1.2

var _combat_log_lines: Array[String] = []
var _missing_cue: Label
var _missing_cue_timer: SceneTreeTimer

func _ready() -> void:
	_register_toggle_action()
	game_gui.visible = false
	game_gui.ability_triggered.connect(_on_ability_triggered)
	# Ability triggers now deal damage to the persistent Enemy in the world instead of a
	# throwaway target that reset every press — see GameGui.combat_target's own doc comment.
	game_gui.combat_target = enemy.dummy_target
	_wire_player_hud()

## HP/Guard readout plus a combat-log line for each defensive outcome, so block/parry/
## dodge timing can be judged while playing without a debugger.
func _wire_player_hud() -> void:
	for sig in [player.health_changed, player.guard_changed]:
		sig.connect(func(_a, _b): _refresh_player_status())
	player.parried.connect(func(_hit): _on_ability_triggered("PARRY!"))
	player.blocked.connect(func(hit: Hit): _on_ability_triggered("Blocked (%s dmg through)" % PerkDefinition.format_number(hit.damage * player.block_damage_taken)))
	player.dodged_through.connect(func(_hit): _on_ability_triggered("Dodged through"))
	player.hurt.connect(func(hit: Hit): _on_ability_triggered("Hit for %s%s" % [PerkDefinition.format_number(hit.damage), " (unblockable)" if hit.kind == Hit.Kind.UNBLOCKABLE else ""]))
	player.guard_broken.connect(func(): _on_ability_triggered("GUARD BROKEN"))
	player.died.connect(func(): _on_ability_triggered("Died, back to spawn"))
	player.ability_missing.connect(_show_missing_cue)
	_refresh_player_status()

## Pressing a move whose perk isn't on the grid flashes a short cue naming the perk (Thomas:
## only when the action is pressed, no permanent marker).
func _show_missing_cue(ability_id: StringName) -> void:
	if _missing_cue == null:
		_missing_cue = Label.new()
		_missing_cue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_missing_cue.offset_top = 120.0
		_missing_cue.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_missing_cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_missing_cue.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
		$HudLayer.add_child(_missing_cue)
	_missing_cue.text = "No %s perk on the grid" % String(ability_id).capitalize()
	_missing_cue.visible = true
	var timer := get_tree().create_timer(MISSING_CUE_SECONDS)
	_missing_cue_timer = timer
	timer.timeout.connect(func():
		if _missing_cue_timer == timer:
			_missing_cue.visible = false)

func _refresh_player_status() -> void:
	player_status_label.text = "HP %d / %d\nGuard %d / %d" % [
		player.health, player.max_health, player.guard, player.max_guard
	]

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

## Showing/hiding GameGui is the only state this needs to track. Nothing pauses while it's open.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		game_gui.visible = not game_gui.visible
		get_viewport().set_input_as_handled()

func _on_ability_triggered(text: String) -> void:
	_combat_log_lines.push_front(text)
	if _combat_log_lines.size() > COMBAT_LOG_MAX_ENTRIES:
		_combat_log_lines.resize(COMBAT_LOG_MAX_ENTRIES)
	combat_log_label.text = "\n\n".join(PackedStringArray(_combat_log_lines))
