class_name GameGui
extends Control
## Minimal test GUI: inventory grid (left), 5x5 board (center), memory bar (right), player
## readout (far right). A view+controller over Board/Inventory/MemorySystem/PlayerCharacter —
## all state lives in those nodes, this just renders it and translates input into calls on
## them. Also owns the fixed-named-ability control scheme (ABILITY_ACTIONS/_unhandled_input,
## via AbilityController) — project.godot's Normal_attack/Special_attack/Jump/Dash actions
## (configured in the editor, not runtime-registered here) trigger whichever perk with that
## id is currently placed on the board, wherever that is.

const BOARD_SIZE := 5
const INVENTORY_COLUMNS := 3
const CELL_SIZE := Vector2(72, 72)
const SYMBOL_INSET := 8.0
const COLOR_HELD := Color(1.0, 0.85, 0.3)
const COLOR_NORMAL := Color(1, 1, 1)
## Amplifier with nothing upstream to act on (see _idle_amplifier_positions).
const COLOR_IDLE := Color(1, 1, 1, 0.35)
const PERK_DEFINITIONS_DIR := "res://resources/perks/"

## Board positions restricted to Ability-class perks (see Board.set_cell_restriction).
## A vertical line down the middle for now — easy to change to any other layout.
const ABILITY_SLOT_POSITIONS: Array[Vector2i] = [
	Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4),
]
const ABILITY_SLOT_BORDER := 3.0

## Fixed named abilities (see AbilityController): an input action always means this specific
## perk id, wherever it's currently placed on the board — not a fixed board slot. Shield is
## deliberately absent here; it's a passive stat read by PlayerCharacter, never triggered.
## Keys match project.godot's [input] section exactly (case-sensitive) — these are real,
## editor-configured Input Map actions now, not runtime-registered here (see _ready()).
const ABILITY_ACTIONS := {
	&"Jump": &"jump",
	&"Dash": &"dash",
	&"Normal_attack": &"normal_attack",
	&"Special_attack": &"special_attack",
}

## Emitted instead of writing ability-trigger results to status_label — this panel is a
## Tab-toggled menu now (see main.gd) and is hidden exactly when a trigger can happen (see the
## `visible` guard in _unhandled_input), so the result needs a destination that's on screen
## regardless of menu state. main.gd's on-screen combat log is that destination.
signal ability_triggered(text: String)

## Off by default so test scenes that instance game_gui.tscn on their own keep starting from a
## bare seeded inventory. main.tscn turns it on (see _apply_starting_loadout).
@export var starting_loadout: bool = false
const STARTING_MEMORY_LEVEL := 2 # 8 bytes: the four core moves plus room for a modifier or two
const STARTING_ABILITIES := {
	&"jump": Vector2i(2, 0),
	&"normal_attack": Vector2i(2, 1),
	&"guard": Vector2i(2, 3),
	&"dash": Vector2i(2, 4),
}

## When true (the default, so test scenes that instance game_gui.tscn on its own keep working),
## pressing an ABILITY_ACTIONS key resolves that ability's chain straight away against
## combat_target. main.tscn turns this off: there, TriggerRouter fires each chain on the real
## gameplay event instead (the swing landing, a parry, dodging through a hit, takeoff).
@export var trigger_on_keypress: bool = true

@onready var board: Board = $Board
@onready var inventory: Inventory = $Inventory
@onready var memory_system: MemorySystem = $MemorySystem
@onready var player: PlayerCharacter = $PlayerCharacter

var inventory_grid: GridContainer
var board_grid: GridContainer
var memory_bar: MemoryBar
var memory_label: Label
## The single dedicated Memory slot under the memory bar — separate from _board_buttons/board
## entirely, since a Memory perk never goes on the board (see MemorySystem, Cell.accepts()).
var memory_slot_button: Button
## Shows why the last placement attempt was rejected (occupied/wrong slot/over budget). Cleared
## on a successful placement/pickup so it never lingers past being relevant.
var status_label: Label
var health_label: Label
var shield_label: Label

var tooltip_panel: PanelContainer
var tooltip_name_label: Label
var tooltip_desc_label: Label

var merge_popup: PanelContainer
var merge_popup_label: Label
var merge_count_label: Label

var held_symbol: PerkSymbol
var chain_solver := ChainSolver.new()
var ability_controller := AbilityController.new()
## What ability triggers actually deal damage to. Defaults to a fresh, throwaway DummyTarget so
## this GUI still works standalone (every test scene that instances game_gui.tscn directly,
## without a Main/Enemy present, relies on this) — main.gd overwrites it with the persistent
## Enemy's own target after both are ready, so damage accumulates on something visible in the
## world instead of resetting every trigger. See Enemy (scripts/combat/enemy.gd).
var combat_target := DummyTarget.new()

var _board_buttons: Dictionary = {} # Vector2i -> Button
## {} when empty. Otherwise {"perk": InventoryPerk, "source": "inventory" or Vector2i}.
var _held: Dictionary = {}
## The stack (Array[InventoryPerk], all same definition+level) the open merge popup targets.
var _merge_stack: Array = []
## How many pairs the "Merge" button will consume, 1..._merge_max — see _on_merge_count_step.
var _merge_count: int = 1
var _merge_max: int = 1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.initialize_shape(Board.rectangular_shape(BOARD_SIZE, BOARD_SIZE))
	for pos in ABILITY_SLOT_POSITIONS:
		board.set_cell_restriction(pos, PerkDefinition.PerkClass.ABILITY)
	# base_capacity left at MemorySystem's own default (4 bytes, doubling per MemoryUpgrade).

	_build_ui()
	_seed_inventory()

	board.board_recomputed.connect(func(_dirty): _refresh_ui())
	board.board_recomputed.connect(func(_dirty): player.recompute_shield_from_board(board))
	inventory.inventory_changed.connect(_refresh_ui)

	player.recompute_shield_from_board(board)
	_refresh_ui()

## Keeps the held-perk symbol snapped to the cursor. Driven by _process rather than input
## events so it stays glued to the mouse regardless of what caused it to move.
func _process(_delta: float) -> void:
	if _held.is_empty():
		held_symbol.visible = false
		return
	held_symbol.visible = true
	held_symbol.global_position = get_global_mouse_position() - held_symbol.size / 2.0

## Lets the player choose which side is input/output before placing (see _resolve_orientation)
## — R cycles the held perk's orientation. No-op for Core/Memory (neither ever has a side to
## assign — see _resolve_orientation).
func _input(event: InputEvent) -> void:
	if _held.is_empty():
		return
	# physical_keycode, not keycode — layout-independent. R has no Input Map action of its own
	# (unlike Jump/Dash/Normal_attack/Special_attack, all real project.godot actions — see
	# ABILITY_ACTIONS), so this checks the raw event directly; keycode is remapped by the OS's
	# active keyboard layout, so on a non-QWERTY layout this check could silently stop matching
	# the physical R key.
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		var definition: PerkDefinition = (_held["perk"] as InventoryPerk).definition
		if definition.perk_class == PerkDefinition.PerkClass.CORE or definition.perk_class == PerkDefinition.PerkClass.MEMORY:
			return
		_held["rotation"] = (int(_held.get("rotation", 0)) + 1) % 4
		get_viewport().set_input_as_handled()
		_refresh_held_symbol()

## Deliberately _unhandled_input, not _process/_input: a Button consumes the click it takes
## for its own `pressed` (and the right-click handlers above mark theirs handled explicitly),
## so clicks spent managing the perk board never also trigger an ability — only input that
## reaches "the game" (a click that landed on nothing, or any keyboard/gamepad press) does.
## The `visible` guard is what actually gates triggering on the menu being closed — main.gd
## toggles this Control's visibility on Tab, and hiding it already stops board/inventory
## Buttons from receiving clicks on their own (Godot skips hit-testing invisible Controls); this
## is the one piece that doesn't stop on its own, since _unhandled_input fires regardless of
## visibility. Triggering should only happen while the menu is CLOSED (visible == false) —
## you're "in the game," not managing your loadout.
func _unhandled_input(event: InputEvent) -> void:
	if visible or not trigger_on_keypress:
		return
	for action_name in ABILITY_ACTIONS:
		if event.is_action_pressed(action_name):
			_trigger_named_ability(action_name, ABILITY_ACTIONS[action_name])
			get_viewport().set_input_as_handled()
			return

## Resolves whatever's currently in the named ability's chain (head to tail, see ChainSolver)
## against combat_target and reports it via ability_triggered. Uses activate_with_steps() rather
## than plain activate() so the log can show each connected perk's own contribution, not just
## the aggregate total.
func _trigger_named_ability(action_name: StringName, perk_id: StringName) -> void:
	trigger_ability(perk_id, action_name, combat_target)

## Resolves perk_id's chain against target (null = resolve and log, but hit nothing) and logs
## it via ability_triggered under `label`. Returns the EffectContext, or null if perk_id isn't
## placed. The single trigger path for both the keypress route above and TriggerRouter.
func trigger_ability(perk_id: StringName, label: String, target: DummyTarget) -> EffectContext:
	var placed := ability_controller.find_placed(board, perk_id)
	if placed == null:
		ability_triggered.emit("%s: not placed on the board" % label)
		return null
	var result := ability_controller.ability_activator.activate_with_steps(board, placed.position, target)
	var context: EffectContext = result["context"]
	var steps: Array = result["steps"]

	var details := PackedStringArray()
	if not context.delayed.is_empty():
		details.append("%d echo%s" % [context.delayed.size(), "" if context.delayed.size() == 1 else "es"])
	if context.target_count > 1:
		details.append("%d targets" % context.target_count)
	if context.radius > 0.0:
		details.append("%sm radius" % PerkDefinition.format_number(context.radius))
	var detail_suffix := ", " + ", ".join(details) if not details.is_empty() else ""

	var text := "%s: %s damage%s" % [
		label, PerkDefinition.format_number(context.damage * context.repeat_count), detail_suffix
	]
	for step in steps:
		text += "\n  " + step
	ability_triggered.emit(text)
	return context

## Maps a perk's class and a 0-3 rotation state to concrete output/input directions.
## rotation_state doubles as the output direction's GridDirection.Value directly (their int
## values line up: 0=N, 1=E, 2=S, 3=W); input always sits on the opposite side (see the plan's
## "opposite sides only" simplification). Ability and Modifier both get input+output — an
## Ability doesn't have to be first in a chain, a Modifier can feed into one. Core and Memory
## have neither — see PerkDefinition.get_input_accepts/get_output_accepts, same two classes.
## Named rotation_state, not rotation — Control already declares a `rotation` property (visual
## rotation in radians) and a same-named parameter here would shadow it.
func _resolve_orientation(definition: PerkDefinition, rotation_state: int) -> Dictionary:
	if definition.perk_class == PerkDefinition.PerkClass.CORE or definition.perk_class == PerkDefinition.PerkClass.MEMORY:
		return {"output": -1, "input": -1}
	return {"output": rotation_state, "input": GridDirection.opposite(rotation_state)}

# ---------------------------------------------------------------- UI construction

func _build_ui() -> void:
	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 16)
	# Purely layout, no interaction of its own — left at the default mouse filter it'd swallow
	# clicks that land in the gaps between panels, which now matters: those clicks are supposed
	# to reach _unhandled_input as "Normal_attack"/"Special_attack" (see ABILITY_ACTIONS).
	# Its Button/ScrollContainer/SpinBox descendants are unaffected — they're still hit-tested
	# first regardless of what an ancestor's filter is set to.
	root_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_hbox)

	root_hbox.add_child(_build_inventory_panel())
	root_hbox.add_child(_build_board_panel())
	root_hbox.add_child(_build_memory_panel())
	root_hbox.add_child(_build_player_panel())

	_build_tooltip()
	_build_merge_popup()
	_build_held_symbol() # added last so it draws above everything else

## A plain (non-Container) Control wrapper gives the cell a size fixed to CELL_SIZE
## regardless of the inner Button's content, so placing/clearing a perk never resizes
## the grid the way it would if the Button sat directly in the GridContainer.
## The perk itself renders as an inset color chip with input/output tick marks (PerkSymbol)
## sized off PerkDefinition — all text (name/level/description) lives in the tooltip.
## Button.flat is left at its default (false) here and toggled per-refresh: flat once a
## perk occupies the slot (clean symbol look), themed chrome while empty (so the grid's
## slot outlines stay visible instead of vanishing into the panel background).
## slot_marker_color (alpha 0 = none, the default) draws a permanent frame around the cell in
## that color and insets the button to match, so the frame stays visible regardless of
## occupancy/flat state — used for the Ability slots (gold, ABILITY's class_color) and the
## single Memory slot (MEMORY's class_color). The button is always added first
## (wrapper.get_child(0)) whether or not a marker is present — callers rely on that fixed index.
func _make_grid_cell(slot_marker_color := Color(0, 0, 0, 0)) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = CELL_SIZE
	var has_marker := slot_marker_color.a > 0.0

	var button := Button.new()
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Keyboard focus would otherwise let a stray Space/Enter re-trigger whichever button was
	# last clicked (Godot's default Button behavior) — conflicts with Space being bound to the
	# "Jump" action in project.godot (see ABILITY_ACTIONS/_unhandled_input).
	button.focus_mode = Control.FOCUS_NONE
	if has_marker:
		button.offset_left += ABILITY_SLOT_BORDER
		button.offset_top += ABILITY_SLOT_BORDER
		button.offset_right -= ABILITY_SLOT_BORDER
		button.offset_bottom -= ABILITY_SLOT_BORDER
	wrapper.add_child(button)

	if has_marker:
		var marker := Panel.new()
		marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.z_index = -1
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = slot_marker_color
		style.set_border_width_all(int(ABILITY_SLOT_BORDER))
		marker.add_theme_stylebox_override("panel", style)
		wrapper.add_child(marker)

	var symbol := PerkSymbol.new()
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	symbol.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	symbol.offset_left += SYMBOL_INSET
	symbol.offset_top += SYMBOL_INSET
	symbol.offset_right -= SYMBOL_INSET
	symbol.offset_bottom -= SYMBOL_INSET
	button.add_child(symbol)

	# Stack count badge (inventory only — board refresh never sets its text, so it just
	# stays blank there). Always button.get_child(1); symbol is always get_child(0).
	var badge := Label.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color.WHITE)
	badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override("shadow_offset_x", 1)
	badge.add_theme_constant_override("shadow_offset_y", 1)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.offset_top = 2
	badge.offset_right = -3
	button.add_child(badge)

	return wrapper

func _build_inventory_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE # see root_hbox

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Inventory"
	vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	inventory_grid = GridContainer.new()
	inventory_grid.columns = INVENTORY_COLUMNS
	inventory_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_grid.add_theme_constant_override("h_separation", 4)
	inventory_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(inventory_grid)

	var hint := Label.new()
	hint.text = "Right-click a stack to merge pairs"
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	return panel

func _build_board_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE # see root_hbox

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Board (right-click to return to inventory) — gold border = Ability-only slot"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var grid_center := CenterContainer.new()
	grid_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(grid_center)

	board_grid = GridContainer.new()
	board_grid.columns = BOARD_SIZE
	board_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_grid.add_theme_constant_override("h_separation", 4)
	board_grid.add_theme_constant_override("v_separation", 4)
	grid_center.add_child(board_grid)

	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var pos := Vector2i(x, y)
			var ability_color := PerkDefinition.class_color(PerkDefinition.PerkClass.ABILITY)
			var wrapper := _make_grid_cell(ability_color if ABILITY_SLOT_POSITIONS.has(pos) else Color(0, 0, 0, 0))
			var button := wrapper.get_child(0) as Button
			button.pressed.connect(_on_board_cell_pressed.bind(pos))
			button.gui_input.connect(_on_board_cell_gui_input.bind(pos))
			button.mouse_entered.connect(_on_board_cell_mouse_entered.bind(pos, button))
			button.mouse_exited.connect(_hide_tooltip)
			board_grid.add_child(wrapper)
			_board_buttons[pos] = button

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.95, 0.5, 0.4))
	vbox.add_child(status_label)

	return panel

func _build_memory_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(140, 0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE # see root_hbox

	var header := Label.new()
	header.text = "Memory"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var bar_center := CenterContainer.new()
	bar_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_center)

	memory_bar = MemoryBar.new()
	memory_bar.custom_minimum_size = Vector2(48, 320)
	memory_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE # purely a _draw()'d readout
	bar_center.add_child(memory_bar)

	var slot_center := CenterContainer.new()
	slot_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(slot_center)

	var memory_color := PerkDefinition.class_color(PerkDefinition.PerkClass.MEMORY)
	var slot_wrapper := _make_grid_cell(memory_color)
	memory_slot_button = slot_wrapper.get_child(0) as Button
	memory_slot_button.pressed.connect(_on_memory_slot_pressed)
	memory_slot_button.gui_input.connect(_on_memory_slot_gui_input)
	memory_slot_button.mouse_entered.connect(_on_memory_slot_mouse_entered.bind(memory_slot_button))
	memory_slot_button.mouse_exited.connect(_hide_tooltip)
	slot_center.add_child(slot_wrapper)

	memory_label = Label.new()
	memory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(memory_label)

	return vbox

## Health/Shield readout plus the control scheme, so the Ability-perk-to-control wiring (see
## ABILITY_ACTIONS/_unhandled_input) is discoverable without reading source.
func _build_player_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(160, 0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE # see root_hbox — also the natural place to
	# click-test attack_normal/attack_special, being the least button-dense panel

	var header := Label.new()
	header.text = "Player"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	health_label = Label.new()
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(health_label)

	shield_label = Label.new()
	shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(shield_label)

	var controls := Label.new()
	controls.text = "\nControls\nLeft click: Normal Attack\nRight click: Special Attack\nSpace: Jump\nShift: Dash"
	controls.add_theme_font_size_override("font_size", 11)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(controls)

	return vbox

func _build_tooltip() -> void:
	tooltip_panel = PanelContainer.new()
	tooltip_panel.visible = false
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_panel.z_index = 100

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(180, 0)
	tooltip_panel.add_child(vbox)

	tooltip_name_label = Label.new()
	tooltip_name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(tooltip_name_label)

	tooltip_desc_label = Label.new()
	tooltip_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(tooltip_desc_label)

	add_child(tooltip_panel)

## Right-clicking a stack of 2+ opens this instead of merging immediately, so the player
## picks how many pairs to consume at once (always in twos — see _open_merge_popup).
func _build_merge_popup() -> void:
	merge_popup = PanelContainer.new()
	merge_popup.visible = false
	merge_popup.z_index = 100

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(190, 0)
	merge_popup.add_child(vbox)

	merge_popup_label = Label.new()
	merge_popup_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(merge_popup_label)

	# A hand-built stepper instead of SpinBox — SpinBox clamps at min/max (no signal fires on
	# an attempted out-of-range step, so there's nothing to hook to make it wrap), and a wrap
	# is exactly what's wanted here: at 1, pressing "-" goes to the max, and vice versa.
	var stepper := HBoxContainer.new()
	stepper.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(stepper)

	var decrement := Button.new()
	decrement.text = "-"
	decrement.focus_mode = Control.FOCUS_NONE # see _make_grid_cell's button.focus_mode
	decrement.pressed.connect(_on_merge_count_step.bind(-1))
	stepper.add_child(decrement)

	merge_count_label = Label.new()
	merge_count_label.custom_minimum_size = Vector2(32, 0)
	merge_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stepper.add_child(merge_count_label)

	var increment := Button.new()
	increment.text = "+"
	increment.focus_mode = Control.FOCUS_NONE
	increment.pressed.connect(_on_merge_count_step.bind(1))
	stepper.add_child(increment)

	var max_merge := Button.new()
	max_merge.text = "Max Merge"
	max_merge.focus_mode = Control.FOCUS_NONE
	max_merge.pressed.connect(_on_max_merge_pressed)
	vbox.add_child(max_merge)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)

	var confirm := Button.new()
	confirm.text = "Merge"
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(_on_merge_confirm_pressed)
	buttons.add_child(confirm)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_hide_merge_popup)
	buttons.add_child(cancel)

	add_child(merge_popup)

func _build_held_symbol() -> void:
	held_symbol = PerkSymbol.new()
	held_symbol.size = CELL_SIZE - Vector2(SYMBOL_INSET, SYMBOL_INSET) * 2.0
	held_symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held_symbol.visible = false
	held_symbol.z_index = 101
	add_child(held_symbol)

## Every PerkDefinition .tres anywhere under PERK_DEFINITIONS_DIR is seeded automatically
## (recursing into the per-PerkClass subfolders — core/, ability/, modifier/, memory/) — adding
## a new perk to the game is just adding a resource in the right subfolder (Inspector: New
## Resource > PerkDefinition), no script changes required. Modifiers and Memory perks get 4
## copies each so there's something mergeable to test with (a Memory perk levels up like any
## other, doubling capacity each time — see MemorySystem); Core and Ability get 1.
func _seed_inventory() -> void:
	var definitions := _load_perk_definitions()
	if definitions.is_empty():
		push_warning("No PerkDefinition resources found under %s" % PERK_DEFINITIONS_DIR)
		return
	for definition in definitions:
		var gets_one_copy := definition.perk_class == PerkDefinition.PerkClass.CORE
		var copies := 1 if gets_one_copy else 4
		for i in copies:
			inventory.add_perk(InventoryPerk.new(definition, 1))
	if starting_loadout:
		_apply_starting_loadout()

## Abilities are perks and cost memory like any other, so with an empty board the player
## couldn't even move. This slots a Memory perk and pre-places the core moves (taken from the
## seeded inventory) down the Ability column, each outputting east so modifiers can chain to
## the right. (2, 2) is left free for Special Attack.
func _apply_starting_loadout() -> void:
	var memory := _take_seeded(&"memory")
	if memory:
		inventory.remove_perk(memory)
		memory_system.slot_perk(InventoryPerk.new(memory.definition, STARTING_MEMORY_LEVEL))
	for id in STARTING_ABILITIES:
		var perk := _take_seeded(id)
		if perk:
			inventory.remove_perk(perk)
			var orientation := _resolve_orientation(perk.definition, GridDirection.Value.EAST)
			board.place_perk(perk, STARTING_ABILITIES[id], orientation["output"], orientation["input"])

func _take_seeded(id: StringName) -> InventoryPerk:
	for perk in inventory.perks:
		if perk.definition.id == id and perk.level == 1:
			return perk
	push_warning("Starting loadout: no %s perk in the seeded inventory" % id)
	return null

func _load_perk_definitions() -> Array[PerkDefinition]:
	var result: Array[PerkDefinition] = []
	_load_perk_definitions_from(PERK_DEFINITIONS_DIR, result)
	return result

## Recurses into subfolders (e.g. the per-PerkClass core/ability/modifier split) rather than
## assuming a flat directory, so reorganizing resources/perks/ never silently drops content.
func _load_perk_definitions_from(path: String, result: Array[PerkDefinition]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			_load_perk_definitions_from(path.path_join(file_name), result)
		elif file_name.ends_with(".tres"):
			var definition := load(path.path_join(file_name)) as PerkDefinition
			if definition:
				result.append(definition)
		file_name = dir.get_next()
	dir.list_dir_end()

# ---------------------------------------------------------------- Input handling

## Picks up (or puts back down) one instance from a stack — which specific instance doesn't
## matter, they're interchangeable, so this always takes stack[0].
func _on_inventory_stack_pressed(stack: Array) -> void:
	var perk: InventoryPerk = stack[0]
	if _held.is_empty():
		_held = {"perk": perk, "source": "inventory", "rotation": 0}
	elif _held_is_from_inventory() and stack.has(_held.get("perk")):
		_held = {}
	else:
		_return_held_to_origin()
		_held = {"perk": perk, "source": "inventory", "rotation": 0}
	status_label.text = ""
	_refresh_ui()

func _on_inventory_stack_gui_input(event: InputEvent, stack: Array, anchor: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# See _on_board_cell_gui_input — right clicks aren't auto-consumed by Button the way
		# left clicks are, so this has to explicitly stop it from also firing "Special_attack".
		get_viewport().set_input_as_handled()
		_open_merge_popup(stack, anchor)

## Only opens if at least one pair is available; max pairs is floor(stack size / 2) — the
## remainder (an odd perk out) always stays unmerged, per design.
func _open_merge_popup(stack: Array, anchor: Control) -> void:
	var max_merges := stack.size() / 2
	if max_merges < 1:
		return
	_merge_stack = stack
	var perk: InventoryPerk = stack[0]
	merge_popup_label.text = "%s Lv%d (%d available)\nMerge how many pairs?" % [
		perk.definition.display_name, perk.level, stack.size()
	]
	_merge_max = max_merges
	_merge_count = 1
	merge_count_label.text = str(_merge_count)
	merge_popup.visible = true
	merge_popup.global_position = anchor.global_position + Vector2(anchor.size.x + 8, 0)

## Wraps instead of clamping: at 1, "-" goes to _merge_max; at _merge_max, "+" goes to 1. delta
## is always exactly +-1 (one button press), so a plain step-and-wrap is enough — no need for
## modular arithmetic (and GDScript's % doesn't do the sign-normalizing wrap that'd need
## anyway, it follows C-style truncation, not Python-style flooring).
func _on_merge_count_step(delta: int) -> void:
	_merge_count += delta
	if _merge_count < 1:
		_merge_count = _merge_max
	elif _merge_count > _merge_max:
		_merge_count = 1
	merge_count_label.text = str(_merge_count)

## Repeatedly takes 2 perks out of the targeted stack and merges them, count times. Works off
## a local copy so it's unaffected by _refresh_ui() rebuilding inventory_grid mid-loop (each
## Inventory.merge() call emits inventory_changed).
func _on_merge_confirm_pressed() -> void:
	var count := _merge_count
	var pool := _merge_stack.duplicate()
	for i in count:
		if pool.size() < 2:
			break
		var a: InventoryPerk = pool.pop_back()
		var b: InventoryPerk = pool.pop_back()
		inventory.merge(a, b)
	_hide_merge_popup()

## Cascades: repeatedly merges the lowest-level available pair (within this one stack's own
## lineage — never pulling in perks from a different stack) until no level has 2+ left, so a
## stack of 4 level-1s ends up as a single level-3 rather than stopping at two level-2s. A perk
## that ends up with no same-level partner (an odd one out at whatever level it lands on) is
## left unmerged, same "merging never crosses mismatched levels" rule _on_merge_confirm_pressed
## already follows.
func _on_max_merge_pressed() -> void:
	var by_level: Dictionary = {} # int level -> Array[InventoryPerk]
	for perk in _merge_stack:
		var lvl: int = perk.level
		if not by_level.has(lvl):
			by_level[lvl] = []
		by_level[lvl].append(perk)

	while true:
		var levels_with_pairs: Array = []
		for lvl in by_level:
			if by_level[lvl].size() >= 2:
				levels_with_pairs.append(lvl)
		if levels_with_pairs.is_empty():
			break
		levels_with_pairs.sort()
		var bucket: Array = by_level[levels_with_pairs[0]]
		var a: InventoryPerk = bucket.pop_back()
		var b: InventoryPerk = bucket.pop_back()
		var merged := inventory.merge(a, b)
		var next_lvl: int = merged.level
		if not by_level.has(next_lvl):
			by_level[next_lvl] = []
		by_level[next_lvl].append(merged)

	_hide_merge_popup()

func _hide_merge_popup() -> void:
	merge_popup.visible = false
	_merge_stack = []

## The trailing empty inventory slot: a drop target for whatever's currently held,
## regardless of whether it came from the board or was already loose in-hand.
func _on_inventory_empty_slot_pressed() -> void:
	if _held.is_empty():
		return
	if not _held_is_from_inventory():
		inventory.add_perk(_held["perk"])
	_held = {}
	status_label.text = ""
	_refresh_ui()

func _on_board_cell_pressed(pos: Vector2i) -> void:
	var cell := board.get_cell(pos)
	if _held.is_empty():
		if cell and not cell.is_empty():
			# Seed rotation from the current orientation so a quick pick-up/put-down
			# round-trip (e.g. switching to a different held perk) doesn't silently re-orient it.
			var placed_before: PlacedPerk = cell.occupant
			var seeded_rotation: int = placed_before.output_direction if placed_before.output_direction != -1 else 0
			var perk := board.remove_perk(pos)
			_held = {"perk": perk, "source": pos, "rotation": seeded_rotation}
			status_label.text = ""
	else:
		var held_perk: InventoryPerk = _held["perk"]
		# Check acceptance (empty + right class) and memory budget BEFORE touching inventory —
		# otherwise a rejected placement (e.g. a non-Ability perk on an Ability-only slot, or
		# one that would blow the memory budget) would remove the perk from inventory with
		# nowhere for it to end up. Each rejection reason is surfaced in status_label instead of
		# silently ignoring the click — a budget rejection in particular is otherwise invisible
		# (nothing about a full board looks different from a merely-restricted one).
		if cell == null or not cell.is_empty():
			status_label.text = "That cell is occupied."
		elif not cell.accepts(held_perk.definition):
			status_label.text = "%s only goes in an Ability slot (gold border)." % held_perk.definition.display_name
		elif not memory_system.can_place(held_perk, board):
			status_label.text = "Not enough memory: %d B used, %d B needed, %d B capacity." % [
				memory_system.get_used(board), held_perk.get_memory_cost(), memory_system.get_capacity()
			]
		else:
			status_label.text = ""
			if _held_is_from_inventory():
				inventory.remove_perk(held_perk)
			var orientation := _resolve_orientation(held_perk.definition, int(_held.get("rotation", 0)))
			board.place_perk(held_perk, pos, orientation["output"], orientation["input"])
			_held = {}
	_refresh_ui()

func _on_board_cell_gui_input(event: InputEvent, pos: Vector2i) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# A Button only auto-consumes left clicks (for its own `pressed`), so a right click here
		# has to be marked handled explicitly — otherwise it falls through to _unhandled_input
		# and would also fire the "Special_attack" action bound to the same mouse button.
		get_viewport().set_input_as_handled()
		var cell := board.get_cell(pos)
		if cell and not cell.is_empty():
			var perk := board.remove_perk(pos)
			inventory.add_perk(perk)
			_refresh_ui()

func _on_board_cell_mouse_entered(pos: Vector2i, anchor: Control) -> void:
	var cell := board.get_cell(pos)
	if cell and not cell.is_empty():
		_show_tooltip(cell.occupant.inventory_perk, anchor, _describe_chain(pos, cell.occupant))

## Mirrors _on_board_cell_pressed's pick-up/place logic but for MemorySystem's single dedicated
## slot instead of a Board position — no orientation/rotation (a Memory perk never connects to
## anything) and no memory-budget check (it doesn't cost board memory, it grants it).
func _on_memory_slot_pressed() -> void:
	if _held.is_empty():
		if memory_system.slotted_perk != null:
			var perk := memory_system.unslot_perk()
			_held = {"perk": perk, "source": "memory_slot"}
			status_label.text = ""
	else:
		var held_perk: InventoryPerk = _held["perk"]
		if memory_system.slotted_perk != null:
			status_label.text = "Memory slot is occupied."
		elif not memory_system.can_slot(held_perk):
			status_label.text = "Only a Memory perk goes in the memory slot."
		else:
			status_label.text = ""
			if _held_is_from_inventory():
				inventory.remove_perk(held_perk)
			memory_system.slot_perk(held_perk)
			_held = {}
	_refresh_ui()

func _on_memory_slot_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		get_viewport().set_input_as_handled() # see _on_board_cell_gui_input
		if memory_system.slotted_perk != null:
			var perk := memory_system.unslot_perk()
			inventory.add_perk(perk)
			_refresh_ui()

func _on_memory_slot_mouse_entered(anchor: Control) -> void:
	if memory_system.slotted_perk != null:
		_show_tooltip(memory_system.slotted_perk, anchor)

## Ability cells show their resolved chain order so the framework is actually checkable from
## the GUI; anything else (or an ability with no connected modifiers) shows nothing extra.
func _describe_chain(pos: Vector2i, placed: PlacedPerk) -> String:
	if placed.get_definition().perk_class != PerkDefinition.PerkClass.ABILITY:
		return ""
	var chain := chain_solver.resolve_chain(board, pos)
	if chain.size() <= 1:
		return ""
	return "\nChain: " + _format_chain_names(chain)

## "Fire -> Chain" style, no prefix — shared by _describe_chain's tooltip text (which adds its
## own "\nChain: ") and _trigger_named_ability's combat-log line.
func _format_chain_names(chain: Array[PlacedPerk]) -> String:
	var names := PackedStringArray()
	for placed in chain:
		names.append(placed.get_definition().display_name)
	return " -> ".join(names)

## "source" is the String "inventory", the String "memory_slot", or a Vector2i board position —
## Vector2i's == throws on a type mismatch (unlike Object comparisons), so both helpers below
## type-check with `is` before ever comparing against a string literal, rather than comparing
## directly against "inventory"/"memory_slot".
func _held_is_from_inventory() -> bool:
	var source = _held.get("source")
	return source is String and source == "inventory"

func _held_is_from_memory_slot() -> bool:
	var source = _held.get("source")
	return source is String and source == "memory_slot"

## Used when switching what's held without an explicit "put down" click (e.g. picking a
## different inventory perk while already holding one lifted off the board or the memory slot).
func _return_held_to_origin() -> void:
	if _held.is_empty():
		return
	var source = _held.get("source")
	var held_perk: InventoryPerk = _held["perk"]
	if source is Vector2i:
		var orientation := _resolve_orientation(held_perk.definition, int(_held.get("rotation", 0)))
		board.place_perk(held_perk, source, orientation["output"], orientation["input"])
	elif _held_is_from_memory_slot():
		memory_system.slot_perk(held_perk)
	_held = {}

# ---------------------------------------------------------------- Rendering

func _refresh_ui() -> void:
	_hide_tooltip() # any state change invalidates whatever was being shown
	_hide_merge_popup()
	_refresh_inventory_grid()
	_refresh_board_grid()
	_refresh_memory_bar()
	_refresh_memory_slot()
	_refresh_player_panel()
	_refresh_held_symbol()

func _refresh_memory_slot() -> void:
	var symbol := memory_slot_button.get_child(0) as PerkSymbol
	var slotted := memory_system.slotted_perk
	if slotted:
		symbol.set_perk(slotted.definition)
		memory_slot_button.flat = true
	else:
		symbol.clear()
		memory_slot_button.flat = false
	var is_held_here: bool = _held_is_from_memory_slot()
	memory_slot_button.modulate = COLOR_HELD if is_held_here else COLOR_NORMAL

func _refresh_player_panel() -> void:
	health_label.text = "Health: %d / %d" % [player.current_health, player.max_health]
	shield_label.text = "Shield: %d" % player.shield

func _refresh_held_symbol() -> void:
	if _held.is_empty():
		held_symbol.clear()
		return
	var definition: PerkDefinition = (_held["perk"] as InventoryPerk).definition
	var orientation := _resolve_orientation(definition, int(_held.get("rotation", 0)))
	held_symbol.set_perk(definition, orientation["input"], orientation["output"])

## Groups inventory.perks into stacks of identical (definition, level) — the perks that would
## satisfy InventoryPerk.can_merge_with each other — preserving first-seen order. A linear
## scan is plenty for inventory sizes this small, and sidesteps any doubt about using a
## Resource + int pair as a Dictionary key.
func _build_inventory_stacks() -> Array:
	var stacks: Array = []
	for perk in inventory.perks:
		var found := false
		for stack in stacks:
			var first: InventoryPerk = stack[0]
			if first.definition == perk.definition and first.level == perk.level:
				stack.append(perk)
				found = true
				break
		if not found:
			stacks.append([perk])
	return stacks

func _refresh_inventory_grid() -> void:
	for child in inventory_grid.get_children():
		child.queue_free()

	for stack in _build_inventory_stacks():
		var is_held_here: bool = _held_is_from_inventory() and stack.has(_held.get("perk"))
		# The held instance is still in inventory.perks (only removed on final placement), so
		# subtract it here for a count that reflects what's actually left in the slot.
		var display_count: int = stack.size() - (1 if is_held_here else 0)
		if display_count <= 0:
			continue # everything in this stack is in-hand; nothing left to show here

		var wrapper := _make_grid_cell()
		var button := wrapper.get_child(0) as Button
		var symbol := button.get_child(0) as PerkSymbol
		var badge := button.get_child(1) as Label

		var representative: InventoryPerk = stack[0]
		symbol.set_perk(representative.definition)
		button.flat = true
		button.modulate = COLOR_HELD if is_held_here else COLOR_NORMAL
		badge.text = ("x%d" % display_count) if display_count > 1 else ""
		button.pressed.connect(_on_inventory_stack_pressed.bind(stack))
		button.gui_input.connect(_on_inventory_stack_gui_input.bind(stack, button))
		button.mouse_entered.connect(_show_tooltip.bind(representative, button))
		button.mouse_exited.connect(_hide_tooltip)
		inventory_grid.add_child(wrapper)

	# Trailing empty slot: always present, a drop target for whatever's currently held.
	var empty_wrapper := _make_grid_cell()
	var empty_button := empty_wrapper.get_child(0) as Button
	empty_button.flat = false
	empty_button.pressed.connect(_on_inventory_empty_slot_pressed)
	inventory_grid.add_child(empty_wrapper)

func _refresh_board_grid() -> void:
	var idle := _idle_amplifier_positions()
	for pos in _board_buttons:
		var button: Button = _board_buttons[pos]
		var symbol := button.get_child(0) as PerkSymbol
		var cell := board.get_cell(pos)
		if cell and not cell.is_empty():
			var placed: PlacedPerk = cell.occupant
			var connected := placed.get_connected_directions()
			var input_connected: bool = placed.has_input() and connected.has(placed.input_direction)
			var output_connected: bool = placed.has_output() and connected.has(placed.output_direction)
			symbol.set_perk(placed.get_definition(), placed.input_direction, placed.output_direction, input_connected, output_connected)
			button.flat = true
		else:
			symbol.clear()
			button.flat = false
		var board_source: Variant = _held.get("source")
		var is_held_here: bool = board_source is Vector2i and board_source == pos
		button.modulate = COLOR_HELD if is_held_here else (COLOR_IDLE if idle.has(pos) else COLOR_NORMAL)

## Positions of amplifier perks (Echo, Linger) that currently do nothing because no source
## effect comes before them in their chain — greyed out on the board so the player can see it.
func _idle_amplifier_positions() -> Dictionary:
	var result := {}
	var activator := ability_controller.ability_activator
	for placed in board.get_all_placed_perks():
		if placed.get_definition().perk_class != PerkDefinition.PerkClass.ABILITY:
			continue
		for idle in activator.find_noop_perks(board, placed.position):
			result[idle.position] = true
	return result

## The bar still shows a translucent preview of a held perk's cost (visual-only, helps judge a
## placement before committing) but the byte count in memory_label does not — it only counts
## what's actually placed on the board right now, updating on real placement/removal, not on
## pickup. Picking a perk up off the board does immediately drop the *actual* total (it's
## genuinely not on the board anymore for that moment), which the label reflects but the
## preview segment visually papers back over.
func _refresh_memory_bar() -> void:
	var usage_by_class := {}
	for placed in board.get_all_placed_perks():
		var perk_class = placed.get_definition().perk_class
		usage_by_class[perk_class] = usage_by_class.get(perk_class, 0) + placed.inventory_perk.get_memory_cost()

	var preview_class = null
	var preview_amount := 0
	if not _held.is_empty():
		var held_perk: InventoryPerk = _held["perk"]
		preview_class = held_perk.definition.perk_class
		preview_amount = held_perk.get_memory_cost()

	var capacity := memory_system.get_capacity()
	memory_bar.set_usage(usage_by_class, preview_class, preview_amount, capacity)

	var used := memory_system.get_used(board)
	memory_label.text = "%d / %d B" % [used, capacity]

func _show_tooltip(perk: InventoryPerk, anchor: Control, extra_text: String = "") -> void:
	if perk == null or perk.definition == null:
		return
	tooltip_name_label.text = "%s (Lv%d)" % [perk.definition.display_name, perk.level]
	tooltip_desc_label.text = perk.definition.description + perk.definition.get_tooltip_extra(perk.level) + extra_text
	tooltip_panel.visible = true
	tooltip_panel.global_position = anchor.global_position + Vector2(anchor.size.x + 8, 0)

func _hide_tooltip() -> void:
	tooltip_panel.visible = false
