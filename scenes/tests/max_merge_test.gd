extends Node
## Checks _on_max_merge_pressed()'s cascading behavior: a stack of N identical level-1 perks
## should merge all the way up (4 -> one level-3, not two level-2s), leaving any perk with no
## same-level partner untouched. Run headless:
## Godot --headless --path <project> res://scenes/tests/max_merge_test.tscn --quit-after 5

@onready var game_gui: GameGui = $GameGui

func _ready() -> void:
	# Fire is seeded with 4 copies (Modifier class) — exactly the "4 level-1s -> 1 level-3"
	# case, cascading through an intermediate two level-2s.
	var fire_stack: Array = []
	for perk in game_gui.inventory.perks:
		if perk.definition.id == &"fire":
			fire_stack.append(perk)
	_check(fire_stack.size() == 4, "4 Fire perks seeded to start")

	game_gui._merge_stack = fire_stack
	game_gui._on_max_merge_pressed()

	var remaining: Array = []
	for perk in game_gui.inventory.perks:
		if perk.definition.id == &"fire":
			remaining.append(perk)
	print("Remaining Fire perks: %s" % [remaining.map(func(p): return "Lv%d" % p.level)])
	_check(remaining.size() == 1, "exactly 1 Fire perk remains after max merge")
	if remaining.size() == 1:
		_check(remaining[0].level == 3, "it's level 3 (cascaded all the way, not stopped at level 2)")

	# Now test the "odd one out" case: 5 identical level-1s -> 1 level-3 + 1 level-1 leftover.
	var shock_stack: Array = []
	for perk in game_gui.inventory.perks:
		if perk.definition.id == &"shock":
			shock_stack.append(perk)
	_check(shock_stack.size() == 4, "4 Shock perks seeded to start")
	# Merge one pair first via the normal path to leave an odd count (3), then add back an
	# unrelated 4th-of-a-different-batch isn't available, so instead: take 3 of the 4 (odd
	# count) to exercise the leftover case directly.
	var odd_stack: Array = shock_stack.slice(0, 3)
	game_gui._merge_stack = odd_stack
	game_gui._on_max_merge_pressed()

	var shock_remaining: Array = []
	for perk in game_gui.inventory.perks:
		if perk.definition.id == &"shock":
			shock_remaining.append(perk)
	print("Remaining Shock perks: %s" % [shock_remaining.map(func(p): return "Lv%d" % p.level)])
	# Started with 4 total, took 3 into the max-merge (odd_stack), left 1 level-1 untouched
	# outside odd_stack. odd_stack's 3 level-1s -> 1 pair merges to level-2, 1 level-1 left
	# over from odd_stack itself. So total remaining: 2 level-1 (1 untouched + 1 leftover) + 1
	# level-2.
	var level_counts := {}
	for p in shock_remaining:
		level_counts[p.level] = level_counts.get(p.level, 0) + 1
	_check(level_counts.get(1, 0) == 2, "2 level-1 Shock perks remain (1 never included, 1 odd-one-out from the merge stack)")
	_check(level_counts.get(2, 0) == 1, "1 level-2 Shock perk from merging the remaining pair")

	print("Result: %d passed, %d failed" % [_pass_count, _fail_count])
	get_tree().quit()

var _pass_count := 0
var _fail_count := 0

func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("[PASS] %s" % label)
	else:
		_fail_count += 1
		print("[FAIL] %s" % label)
