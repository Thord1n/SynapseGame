class_name PerkSymbol
extends Control
## Draws a perk's chip (color from PerkDefinition.get_display_color — class color by default,
## overridable per subclass, e.g. ElementalPerkDefinition colors by element instead), its icon
## (if any), and a tick mark for its input side and/or output side (if assigned — see
## PlacedPerk.input_direction/output_direction). Each tick starts at the chip's own edge and
## reaches PRONG_REACH of the way to center; the icon is inset by that same fraction so it
## never overlaps the ticks.
##
## Orientation only exists once a perk is placed (chosen by the player at placement time), so
## an inventory chip — or a perk that hasn't been rotated into an orientation yet — simply
## draws no ticks at all; that's expected, not a bug.

const PRONG_REACH := 0.25
const PRONG_WIDTH := 3.0
const INPUT_COLOR := Color(0.4, 0.7, 1.0, 0.95)
const OUTPUT_COLOR := Color(1.0, 0.75, 0.3, 0.95)
const CONNECTED_COLOR := Color(0.3, 1.0, 0.5, 1.0)

var _chip_color := Color(0, 0, 0, 0)
var _definition: PerkDefinition
var _input_direction: int = -1
var _output_direction: int = -1
var _input_connected: bool = false
var _output_connected: bool = false

## input_direction/output_direction are -1 when that side isn't assigned (always true for
## inventory perks, and for whichever side a perk's class doesn't have). The *_connected flags
## only matter when the corresponding direction is assigned.
func set_perk(definition: PerkDefinition, input_direction: int = -1, output_direction: int = -1, input_connected: bool = false, output_connected: bool = false) -> void:
	_definition = definition
	_chip_color = definition.get_display_color()
	_input_direction = input_direction
	_output_direction = output_direction
	_input_connected = input_connected
	_output_connected = output_connected
	queue_redraw()

func clear() -> void:
	_definition = null
	_chip_color = Color(0, 0, 0, 0)
	_input_direction = -1
	_output_direction = -1
	_input_connected = false
	_output_connected = false
	queue_redraw()

func _draw() -> void:
	if _chip_color.a <= 0.0 or _definition == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), _chip_color, true)

	var center := size / 2.0
	var margin := center * PRONG_REACH # distance from each edge to where a tick ends

	if _definition.icon:
		draw_texture_rect(_definition.icon, Rect2(margin, size - margin * 2.0), false)

	if _input_direction != -1:
		var color := CONNECTED_COLOR if _input_connected else INPUT_COLOR
		_draw_tick(_input_direction, center, color)
	if _output_direction != -1:
		var color := CONNECTED_COLOR if _output_connected else OUTPUT_COLOR
		_draw_tick(_output_direction, center, color)

func _draw_tick(direction: GridDirection.Value, center: Vector2, color: Color) -> void:
	var edge_point := center + Vector2(GridDirection.offset(direction)) * center
	var inner_point := edge_point.lerp(center, PRONG_REACH)
	draw_line(edge_point, inner_point, color, PRONG_WIDTH)
