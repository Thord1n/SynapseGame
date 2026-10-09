class_name GridDirection
extends RefCounted

enum Value { NORTH, EAST, SOUTH, WEST }

const OFFSETS := {
	Value.NORTH: Vector2i(0, -1),
	Value.EAST: Vector2i(1, 0),
	Value.SOUTH: Vector2i(0, 1),
	Value.WEST: Vector2i(-1, 0),
}

static func opposite(direction: Value) -> Value:
	match direction:
		Value.NORTH: return Value.SOUTH
		Value.SOUTH: return Value.NORTH
		Value.EAST: return Value.WEST
		Value.WEST: return Value.EAST
	return direction

static func offset(direction: Value) -> Vector2i:
	return OFFSETS[direction]

static func all() -> Array[Value]:
	return [Value.NORTH, Value.EAST, Value.SOUTH, Value.WEST]
