class_name ConnectionSolver
extends RefCounted

## Recomputes cached connections for exactly the given positions (each cell checks its own
## neighbors). Callers are responsible for passing a dirty set that already includes neighbors
## of anything that changed (see Board._recompute) — this does not expand the set further.
func recompute(board: Board, positions: Array[Vector2i]) -> void:
	for pos in positions:
		var cell: Cell = board.get_cell(pos)
		if cell == null or cell.is_empty():
			continue
		cell.occupant.connections = _find_connections(board, cell.occupant)

## Connections are directional (an output feeds a neighbor's input), so unlike the old
## symmetric-prong check, each neighbor direction has to be tested from both perspectives:
## `placed` might be the output/from side, or the input/to side.
func _find_connections(board: Board, placed: PlacedPerk) -> Array[PerkConnection]:
	var result: Array[PerkConnection] = []
	for dir in GridDirection.all():
		var neighbor_pos: Vector2i = placed.position + GridDirection.offset(dir)
		var neighbor_cell: Cell = board.get_cell(neighbor_pos)
		if neighbor_cell == null or neighbor_cell.is_empty():
			continue
		var neighbor := neighbor_cell.occupant
		if can_connect(placed, neighbor, dir):
			result.append(PerkConnection.new(placed, neighbor, dir))
		elif can_connect(neighbor, placed, GridDirection.opposite(dir)):
			result.append(PerkConnection.new(neighbor, placed, GridDirection.opposite(dir)))
	return result

## True if `from`'s output faces `to`'s input in `direction` (from -> to, physically adjacent)
## and each side's accept-list allows the other's PerkClass.
static func can_connect(from: PlacedPerk, to: PlacedPerk, direction: GridDirection.Value) -> bool:
	var def_from := from.get_definition()
	var def_to := to.get_definition()
	if def_from == null or def_to == null:
		return false
	if from.output_direction != direction or to.input_direction != GridDirection.opposite(direction):
		return false
	return def_from.get_output_accepts().has(def_to.perk_class) and def_to.get_input_accepts().has(def_from.perk_class)
