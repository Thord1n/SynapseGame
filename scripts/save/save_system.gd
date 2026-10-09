class_name SaveSystem
extends RefCounted
## Saves and restores the player's perk state: every InventoryPerk in the Inventory, every
## PlacedPerk on the Board (position + the orientation the player chose), and whatever is in
## MemorySystem's slot. Perks are stored by PerkDefinition.id + level, never by resource path,
## so moving .tres files around under resources/perks/ doesn't break existing saves.
##
## Format is plain JSON (user:// file), versioned so a later format change can migrate or
## refuse old saves instead of misreading them:
## {
##   "version": 1,
##   "inventory": [{"id": "fire", "level": 2}, ...],
##   "board": [{"x": 2, "y": 0, "id": "jump", "level": 1, "output": 1, "input": -1}, ...],
##   "memory": {"id": "memory", "level": 1}  # or null when the slot is empty
## }

const FORMAT_VERSION := 1

## extra_inventory: perks that currently belong nowhere (e.g. one the player lifted off the
## board or the memory slot and is still holding) — saved as inventory so they're never lost.
static func serialize(inventory: Inventory, board: Board, memory_system: MemorySystem, extra_inventory: Array[InventoryPerk] = []) -> Dictionary:
	var inventory_data: Array = []
	for perk in inventory.perks + extra_inventory:
		inventory_data.append(_perk_to_dict(perk))

	var board_data: Array = []
	for placed in board.get_all_placed_perks():
		var entry := _perk_to_dict(placed.inventory_perk)
		entry["x"] = placed.position.x
		entry["y"] = placed.position.y
		entry["output"] = placed.output_direction
		entry["input"] = placed.input_direction
		board_data.append(entry)

	var memory_data = null
	if memory_system.slotted_perk != null:
		memory_data = _perk_to_dict(memory_system.slotted_perk)

	return {
		"version": FORMAT_VERSION,
		"inventory": inventory_data,
		"board": board_data,
		"memory": memory_data,
	}

## Replaces the current contents of inventory/board/memory_system with data. Expects them to
## be freshly set up (board shape initialized, nothing placed) — doesn't clear them first.
## Placement goes straight through Board.place_perk, deliberately skipping the memory-budget
## check: a soft-locked board (usage over capacity) is a legal state the player can save in,
## and loading it must not silently drop perks. Entries whose id no longer exists, or whose
## cell is gone/occupied, are skipped with a warning rather than failing the whole load.
static func apply(data: Dictionary, definitions: Dictionary, inventory: Inventory, board: Board, memory_system: MemorySystem) -> void:
	var memory_entry = data.get("memory")
	if memory_entry is Dictionary:
		var memory_perk := _perk_from_dict(memory_entry, definitions)
		if memory_perk and memory_system.can_slot(memory_perk):
			memory_system.slot_perk(memory_perk)

	for entry in data.get("board", []):
		var perk := _perk_from_dict(entry, definitions)
		if perk == null:
			continue
		var pos := Vector2i(int(entry.get("x", -1)), int(entry.get("y", -1)))
		if board.place_perk(perk, pos, int(entry.get("output", -1)), int(entry.get("input", -1))) == null:
			push_warning("SaveSystem: couldn't restore %s at %s, returning it to inventory" % [perk.definition.id, pos])
			inventory.add_perk(perk)

	for entry in data.get("inventory", []):
		var perk := _perk_from_dict(entry, definitions)
		if perk:
			inventory.add_perk(perk)

static func save_to_file(data: Dictionary, path: String) -> bool:
	# Write to a temp file first and swap it in, so a crash mid-write can't leave a
	# truncated save behind in place of the last good one.
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: can't write %s (%s)" % [tmp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("SaveSystem: can't move save into place at %s (%s)" % [path, error_string(err)])
		return false
	return true

## Returns {} when there's no save, or it's unreadable / from an unknown format version.
static func load_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("SaveSystem: %s isn't valid save data, ignoring it" % path)
		return {}
	if int(parsed.get("version", 0)) != FORMAT_VERSION:
		push_warning("SaveSystem: %s has unsupported version %s, ignoring it" % [path, parsed.get("version")])
		return {}
	return parsed

static func delete_save(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## id -> PerkDefinition, the lookup apply() needs.
static func index_definitions(definitions: Array[PerkDefinition]) -> Dictionary:
	var result := {}
	for definition in definitions:
		result[String(definition.id)] = definition
	return result

static func _perk_to_dict(perk: InventoryPerk) -> Dictionary:
	return {"id": String(perk.definition.id), "level": perk.level}

static func _perk_from_dict(entry, definitions: Dictionary) -> InventoryPerk:
	if not entry is Dictionary:
		return null
	var id := String(entry.get("id", ""))
	var definition: PerkDefinition = definitions.get(id)
	if definition == null:
		push_warning("SaveSystem: unknown perk id '%s' in save, skipping it" % id)
		return null
	return InventoryPerk.new(definition, max(1, int(entry.get("level", 1))))
