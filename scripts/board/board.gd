class_name Board
extends Node

## Emitted whenever a perk is placed, removed, or connections are recomputed.
## GUI layers should treat this as "re-read board state" rather than caching.
signal perk_placed(position: Vector2i, perk: PlacedPerk)
signal perk_removed(position: Vector2i, perk: PlacedPerk)
signal board_recomputed(dirty_positions: Array[Vector2i])

var cells: Dictionary = {} # Vector2i -> Cell

var connection_solver := ConnectionSolver.new()

## Defines the legal grid shape. Call once before placing perks. Supports non-rectangular
## boards since shape is just a list of valid positions, not a fixed 2D array.
func initialize_shape(positions: Array[Vector2i]) -> void:
	cells.clear()
	for pos in positions:
		cells[pos] = Cell.new(pos)

static func rectangular_shape(width: int, height: int) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for x in width:
		for y in height:
			positions.append(Vector2i(x, y))
	return positions

## Restricts a cell to only accept perks of the given PerkDefinition.PerkClass. Pass null to
## clear the restriction. No-op if the position isn't part of the board's shape.
func set_cell_restriction(position: Vector2i, perk_class) -> void:
	var cell := get_cell(position)
	if cell:
		cell.required_class = perk_class

func get_cell(position: Vector2i) -> Cell:
	return cells.get(position)

func is_occupied(position: Vector2i) -> bool:
	var cell := get_cell(position)
	return cell != null and not cell.is_empty()

func get_neighbors(position: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in GridDirection.all():
		var neighbor_pos: Vector2i = position + GridDirection.offset(dir)
		if cells.has(neighbor_pos):
			result.append(neighbor_pos)
	return result

## Returns the resulting PlacedPerk, or null if the position is invalid/occupied/restricted
## to a different perk class. output_direction/input_direction are the sides the player chose
## for this placement (see game_gui.gd's rotation handling) — -1 for whichever side this
## perk's class doesn't have (see PerkDefinition.get_input_accepts/get_output_accepts).
func place_perk(perk: InventoryPerk, position: Vector2i, output_direction: int = -1, input_direction: int = -1) -> PlacedPerk:
	var cell := get_cell(position)
	if cell == null or not cell.is_empty() or not cell.accepts(perk.definition):
		return null
	var placed := PlacedPerk.new(perk, position, output_direction, input_direction)
	cell.occupant = placed
	perk_placed.emit(position, placed)
	_recompute(position)
	return placed

## Returns the freed InventoryPerk, or null if the position was empty/invalid.
func remove_perk(position: Vector2i) -> InventoryPerk:
	var cell := get_cell(position)
	if cell == null or cell.is_empty():
		return null
	var placed := cell.occupant
	cell.occupant = null
	perk_removed.emit(position, placed)
	_recompute(position)
	return placed.inventory_perk

func _recompute(origin: Vector2i) -> void:
	var dirty: Array[Vector2i] = [origin]
	dirty.append_array(get_neighbors(origin))
	connection_solver.recompute(self, dirty)
	board_recomputed.emit(dirty)

func get_all_placed_perks() -> Array[PlacedPerk]:
	var result: Array[PlacedPerk] = []
	for cell: Cell in cells.values():
		if not cell.is_empty():
			result.append(cell.occupant)
	return result

func get_total_memory_used() -> int:
	var total := 0
	for placed in get_all_placed_perks():
		total += placed.inventory_perk.get_memory_cost()
	return total
