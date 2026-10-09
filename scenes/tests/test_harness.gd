extends Node
## Scene-specific glue: exercises Board/Inventory/MemorySystem/AbilityActivator end-to-end
## against known-good hand-computed numbers — a scripted regression check, same PASS/FAIL
## pattern as every other scene in scenes/tests/ (this one predates them; converted to match
## rather than left as print()-only output a human had to eyeball against the scaling formulas
## by hand, see ROADMAP.md). Run headless:
## Godot --headless --path <project> res://scenes/tests/test_harness.tscn --quit-after 5

@onready var board: Board = $Board
@onready var inventory: Inventory = $Inventory
@onready var memory_system: MemorySystem = $MemorySystem

var ability_activator := AbilityActivator.new()
var _pass_count := 0
var _fail_count := 0

func _ready() -> void:
	board.initialize_shape(Board.rectangular_shape(3, 3))
	# Capacity comes solely from a slotted Memory perk now (see MemorySystem) — a level-2 one
	# (Power=2, doubling curve) gives 8 bytes: ceil(4 * 2^1.0) = 8, comfortably above the
	# 5-byte demo usage checked below.
	memory_system.slot_perk(InventoryPerk.new(_make_memory_perk(), 2))
	# Ability perks only ever accept placement on an explicit Ability slot (Cell.accepts).
	board.set_cell_restriction(Vector2i(0, 0), PerkDefinition.PerkClass.ABILITY)

	var spark_core := _make_spark_core()
	var relay_node := _make_relay_node()

	var perk_a := InventoryPerk.new(spark_core, 1)
	var perk_b := InventoryPerk.new(spark_core, 1)
	var perk_c := InventoryPerk.new(relay_node, 1)

	inventory.add_perk(perk_a)
	inventory.add_perk(perk_b)
	inventory.add_perk(perk_c)
	_check(inventory.perks.size() == 3, "inventory has 3 perks after seeding")
	_check(inventory.find_mergeable_partner(perk_a) != null, "Spark Core mergeable pair found")

	var merged := inventory.merge(perk_a, perk_b)
	_check(merged.level == 2, "merge produces a level-2 Spark Core")
	_check(merged.get_power() == 2, "level-2 Spark Core has Power 2")

	# Moving a perk onto the board is the coordinator's job (Inventory and Board don't
	# reference each other directly, per the design doc's separation of concerns).
	inventory.remove_perk(merged)
	# Output only, for this demo — Spark Core has an input too (Ability does, same as Modifier)
	# but nothing feeds into it here, so it's left at -1 (unassigned).
	board.place_perk(merged, Vector2i(0, 0), GridDirection.Value.EAST)
	_check(board.get_cell(Vector2i(0, 0)).occupant.connections.is_empty(), "Spark Core alone has 0 connections")

	inventory.remove_perk(perk_c)
	# East of the Spark Core, input facing back west so it links up; output east is a dead end
	# here (nothing placed at (2, 0)), which is fine — just demonstrates a 2-perk chain.
	board.place_perk(perk_c, Vector2i(1, 0), GridDirection.Value.EAST, GridDirection.Value.WEST)
	_check(board.get_cell(Vector2i(0, 0)).occupant.connections.size() == 1, "Spark Core has 1 connection once Relay Node is placed")
	_check(board.get_cell(Vector2i(1, 0)).occupant.connections.size() == 1, "Relay Node has 1 connection back to Spark Core")

	# Spark Core L2: base_memory=1 * complexity=1.0 * 2^(1*0.75) -> ceil(1.682) = 2 bytes.
	# Relay Node L1: base_memory=2 * complexity=1.2 * 2^(0*0.7) -> ceil(2.4) = 3 bytes. Total 5.
	_check(memory_system.get_used(board) == 5, "memory used is 5 bytes (Spark Core 2 + Relay Node 3)")
	_check(memory_system.get_capacity() == 8, "memory capacity is 8 bytes (level-2 Memory perk)")
	_check(not memory_system.is_soft_locked(board), "not soft-locked (5 used <= 8 capacity)")

	# Spark Core L2: ceil(5.0 * 2^0.75) = 9. Relay Node contributes 0 (plain PerkDefinition,
	# base_damage defaults to 0 — it's a pass-through modifier, not a damage source).
	var result := ability_activator.activate(board, Vector2i(0, 0), DummyTarget.new())
	_check(is_equal_approx(result.damage, 9.0), "activating Spark Core deals 9 damage (ceil(5 * 2^0.75), Relay Node contributes 0)")

	var freed := board.remove_perk(Vector2i(1, 0))
	if freed:
		inventory.add_perk(freed)
	_check(inventory.perks.size() == 1, "inventory has 1 perk after removing Relay Node from the board")

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		print("[FAIL] %s" % label)

func _make_spark_core() -> PerkDefinition:
	var def := PerkDefinition.new()
	def.id = &"spark_core"
	def.display_name = "Spark Core"
	def.description = "Basic damage ability."
	def.perk_class = PerkDefinition.PerkClass.ABILITY
	def.base_damage = 5.0
	def.base_memory = 1
	def.complexity = 1.0
	def.scaling_exponent = 0.75
	return def

func _make_relay_node() -> PerkDefinition:
	var def := PerkDefinition.new()
	def.id = &"relay_node"
	def.display_name = "Relay Node"
	def.description = "Support modifier. Passes an Ability's effect through untouched."
	def.perk_class = PerkDefinition.PerkClass.MODIFIER
	def.base_memory = 2
	def.complexity = 1.2
	def.scaling_exponent = 0.7
	return def

func _make_memory_perk() -> PerkDefinition:
	var def := MemoryPerkDefinition.new()
	def.id = &"memory"
	def.display_name = "Memory"
	def.description = "Passive. Raises board memory capacity while slotted."
	def.perk_class = PerkDefinition.PerkClass.MEMORY
	def.base_damage = 4.0
	def.base_memory = 0
	def.scaling_exponent = 1.0
	return def
