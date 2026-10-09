class_name MemorySystem
extends Node
## Capacity comes solely from whichever Memory perk (PerkClass.MEMORY) is currently in
## slotted_perk — MemorySystem's own dedicated slot, entirely separate from the board (see
## MemoryPerkDefinition, and game_gui.gd's memory slot UI). With nothing slotted, capacity is
## 0: no perk can be placed on the board at all until a Memory perk is slotted (or, same
## effect from the other direction, until enough perks are removed that usage drops to 0 too).
## Perks already on the board are never force-removed just because capacity dropped below
## usage — see is_soft_locked/can_place — only new placements are blocked.

signal capacity_changed
signal soft_locked_changed(is_soft_locked: bool)

## The equipped Memory perk, or null if the slot is empty. Set via slot_perk()/unslot_perk(),
## not directly, so capacity_changed always fires when it changes.
var slotted_perk: InventoryPerk = null

var _was_soft_locked := false

func get_capacity() -> int:
	if slotted_perk == null:
		return 0
	return slotted_perk.definition.get_scaled_base_damage(slotted_perk.level)

## Class-eligibility only — mirrors Cell.accepts()'s split from occupancy (cell.is_empty() is
## checked separately by callers there; slotted_perk == null is checked separately here) so a
## caller can give a distinct reason for "wrong perk type" vs. "slot already has one in it".
func can_slot(perk: InventoryPerk) -> bool:
	return perk != null and perk.definition.perk_class == PerkDefinition.PerkClass.MEMORY

func slot_perk(perk: InventoryPerk) -> void:
	slotted_perk = perk
	capacity_changed.emit()

## Returns the freed InventoryPerk, or null if the slot was already empty.
func unslot_perk() -> InventoryPerk:
	var freed := slotted_perk
	slotted_perk = null
	capacity_changed.emit()
	return freed

func get_used(board: Board) -> int:
	return board.get_total_memory_used()

func is_soft_locked(board: Board) -> bool:
	return get_used(board) > get_capacity()

func can_place(perk: InventoryPerk, board: Board) -> bool:
	return get_used(board) + perk.get_memory_cost() <= get_capacity()

## Call after board changes (e.g. connected to Board.board_recomputed) to get soft-lock
## transition notifications instead of polling is_soft_locked() every frame.
func notify_board_changed(board: Board) -> void:
	var locked := is_soft_locked(board)
	if locked != _was_soft_locked:
		_was_soft_locked = locked
		soft_locked_changed.emit(locked)
