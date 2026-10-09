class_name MemoryBar
extends Control
## Vertical stacked bar: each PerkClass's committed board usage draws as one contiguous
## block in that class's color (grouped, not interleaved by placement order), in a fixed
## CLASS_ORDER so the same class always lands in the same band. A currently-held perk's cost
## previews as a translucent block of its own class color on top — visual only, the numeric
## byte count elsewhere (game_gui.gd's memory_label) doesn't count it until it's actually
## placed (see _refresh_memory_bar). The frame border turns red if the total, including the
## preview, would exceed capacity.

const CLASS_ORDER := [
	PerkDefinition.PerkClass.CORE,
	PerkDefinition.PerkClass.ABILITY,
	PerkDefinition.PerkClass.MODIFIER,
]
const PREVIEW_ALPHA := 0.55

const COLOR_BG := Color(0.15, 0.15, 0.18)
const COLOR_BORDER := Color(0.4, 0.4, 0.45)
const COLOR_BORDER_OVERFLOW := Color(0.85, 0.3, 0.3)

var _usage_by_class: Dictionary = {} # PerkDefinition.PerkClass -> int (bytes)
var _preview_class = null # PerkDefinition.PerkClass, or null if nothing held
var _preview_amount: float = 0.0 # bytes; float-typed purely for the ratio math below
var _capacity: float = 1.0 # bytes; float-typed purely for the ratio math below

func set_usage(usage_by_class: Dictionary, preview_class, preview_amount: float, capacity: float) -> void:
	_usage_by_class = usage_by_class
	_preview_class = preview_class
	_preview_amount = preview_amount
	_capacity = max(capacity, 0.001)
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, COLOR_BG, true)

	var cumulative := 0.0
	for perk_class in CLASS_ORDER:
		var amount: float = _usage_by_class.get(perk_class, 0.0)
		if amount > 0.0:
			cumulative = _draw_segment(cumulative, amount / _capacity, PerkDefinition.class_color(perk_class))

	if _preview_amount > 0.0:
		var preview_color := PerkDefinition.class_color(_preview_class)
		preview_color.a = PREVIEW_ALPHA
		cumulative = _draw_segment(cumulative, _preview_amount / _capacity, preview_color)

	draw_rect(rect, COLOR_BORDER_OVERFLOW if cumulative > 1.0 else COLOR_BORDER, false, 2.0)

## Draws one block spanning [cumulative_ratio, cumulative_ratio + ratio) of the bar's height
## (clamped to the visible [0, 1] range) and returns the new (unclamped) cumulative ratio, so
## overflow past capacity is still detectable after the loop even though nothing draws there.
func _draw_segment(cumulative_ratio: float, ratio: float, color: Color) -> float:
	var clamped_start: float = clamp(cumulative_ratio, 0.0, 1.0)
	var clamped_end: float = clamp(cumulative_ratio + ratio, 0.0, 1.0)
	if clamped_end > clamped_start:
		var y_bottom := size.y * (1.0 - clamped_start)
		var y_top := size.y * (1.0 - clamped_end)
		draw_rect(Rect2(Vector2(0, y_top), Vector2(size.x, y_bottom - y_top)), color, true)
	return cumulative_ratio + ratio
