# SynapseGrid — Architecture Overview

This is the code-level companion to
[perk_board_system.md](perk_board_system.md), which documents the *design*. This document
documents the *implementation*: what files exist, how they depend on each other, and how a
click in the GUI turns into board state changing. If you're picking this project up cold,
read the design doc first for the "why," then this for the "where."

Engine: Godot 4.5. Language: GDScript throughout, using `class_name` for every reusable
type so cross-script references never need `preload()`.

---

## 1. Directory layout

```
scripts/
├── board/     — the board/connection/memory subsystem (Node- and RefCounted-based)
├── perks/     — perk data model + inventory (Resource- and RefCounted-based)
├── combat/    — effect application: EffectContext, DummyTarget, AbilityActivator, Enemy
└── player/    — PlayerCharacter (Health), AbilityController (§4), and
				 PlayerController (World/Player's CharacterBody2D — movement/jump/melee-hitbox
				 Normal Attack are real, Special Attack/Dash/Block's actual effect are stubs;
				 ROADMAP.md item 2)
scenes/
├── main/      — main.tscn (the actual run/main_scene: a minimal 2D world +
│                the perk-board GUI as a Tab-toggled menu, §4), the GUI itself,
│                and its two custom-drawn Controls
└── tests/     — 11 scripted-assertion regression scenes (§5) — moved out of scenes/main/
				 once there were enough of them to clutter it
resources/
└── perks/     — the actual perk content (.tres), one subfolder per PerkClass:
				 core/, ability/, modifier/, memory/ — auto-loaded recursively by the GUI
docs/
└── design/systems/ — this doc + the design doc
```

There is no `scripts/ui/` or `scripts/autoload/` in use despite the empty folders some
projects reserve for that — the GUI logic lives directly under `scenes/main/` since it's
scene-specific glue, not a shared system.

---

## 2. Core data model (`scripts/perks/`, `scripts/board/`)

```
PerkDefinition (Resource)          — immutable template: id, display_name, description,
  │                                   icon, perk_class, input_accepts, output_accepts,
  │                                   base_damage, base_memory, complexity, scaling_exponent,
  │                                   tags
  ├── ElementalPerkDefinition       — + element (enum), damage (float)
  ├── AreaPerkDefinition            — + radius, max_radius (float)
  ├── EchoPerkDefinition            — + echoes (int)
  ├── ChainPerkDefinition           — + chains (int)
  ├── ShieldPerkDefinition          — the Block/Parry ability; reuses base_damage as max Guard
  │                                    instead of combat damage (see §4) — apply_effect() is a
  │                                    no-op override so it can never leak into combat math
  └── MemoryPerkDefinition          — same reuse-base_damage pattern as Shield, this time as a
									   memory-capacity amount (see MemorySystem below) —
									   apply_effect() is also a no-op here for the same reason

InventoryPerk (RefCounted)         — definition + level. The mergeable unit. Not tied to
									  the board at all.

PlacedPerk (RefCounted)            — an InventoryPerk at a board Vector2i, plus
									  output_direction/input_direction (chosen by the player
									  at placement — see §4) and a cached
									  connections: Array[PerkConnection]

Cell (RefCounted)                  — position + occupant (PlacedPerk?) + required_class
									  (an Ability-slot restriction, or null)

Board (Node)                       — Dictionary[Vector2i, Cell] + a ConnectionSolver.
									  Signals: perk_placed, perk_removed, board_recomputed.

Inventory (Node)                   — Array[InventoryPerk] + merge logic.
									  Signal: inventory_changed.

MemorySystem (Node)                — capacity (integer bytes) derived from whichever Memory
									  perk is in slotted_perk (0 if none — see below) vs. usage.
									  MemoryUpgrade/base_capacity (an earlier, now-deleted
									  mechanism) used to own this instead.

PlayerCharacter (Node)             — Health (flat). scripts/player/. (Shield is now the
									  Block/Parry ability; its level sets max Guard, see §4.)
```

`input_accepts`/`output_accepts` are `Array[PerkClass]` — which classes that side will link
to. `PerkDefinition.get_input_accepts()`/`get_output_accepts()` wrap the raw exported arrays
and force an empty list for Core (both sides only — Ability and Modifier both use their
accept-lists as-is) regardless of what's set, the same defensive pattern `has_prong()` used to
enforce for Core under the old prong system (now retired — see `perk_board_system.md`
§1/§2/§6/§7 for the prong → input/output change this session).

**Why the split between `InventoryPerk` and `PlacedPerk`?** So the merge/crafting system
never has to know about the board, and vice versa — merging never touches `ConnectionSolver`
or the combat layer (`scripts/combat/`). `Board.place_perk()` takes an `InventoryPerk` plus
the output/input directions the player chose and wraps them in a `PlacedPerk`;
`Board.remove_perk()` unwraps it back (discarding the chosen orientation — it's re-chosen on
the next placement).

**Why is `Board` a `Node` but `Cell`/`PlacedPerk`/`PerkConnection` are `RefCounted`?**
`Board`/`Inventory`/`MemorySystem` need signals and a place in the scene tree (so a GUI can
just do `$Board`, `$Inventory`); the data they contain doesn't.

**Extending the perk type system.** Adding a new *instance* of an existing perk type (e.g.
another Ability) is purely content — a new `.tres` file in the matching PerkClass subfolder
(`resources/perks/core|ability|modifier/`), no code.
Adding a new perk *type* with its own stat (like `damage` or `radius`) means a new
`PerkDefinition` subclass, overriding whichever of these it needs:

```gdscript
func get_display_color() -> Color        # defaults to class_color(perk_class)
func get_tooltip_extra(level: int) -> String  # defaults to "" (no extra tooltip text)
```

`get_tooltip_extra` takes `level` because level only exists on `InventoryPerk`, not on the
level-less `PerkDefinition` — any level-scaled stat has to be computed from a
`get_scaled_X(level)` method on the subclass and formatted into that string.

---

## 3. Solvers (`scripts/board/`) and combat (`scripts/combat/`)

Two stateless-ish `RefCounted` classes in `scripts/board/`, each taking a `Board` reference
rather than owning one:

| Solver | Called | Does |
|---|---|---|
| `ConnectionSolver` | Pushed — `Board._recompute()` calls it after every place/remove | Recomputes `PlacedPerk.connections` for the dirty cell + its neighbors (dirty-set incremental, per the design doc's §9). Directional now — `can_connect(from, to, dir)` checks `from`'s output faces `to`'s input, plus both sides' accept-lists (design doc §7) |
| `ChainSolver` | Pulled — called on demand, e.g. from the GUI tooltip or `AbilityActivator` | `resolve_chain(board, from_position)` — **head to tail** (design doc §7): walks backward (`_find_prev`) from `from_position` to the chain's true head (nothing feeds into it), then forward (`_find_next`) to the tail. No perk-class distinction anywhere — an Ability can sit anywhere in the chain, not just the head, and resolving from any position in a chain finds the same order |

`scripts/combat/` builds on top of both:

| Class | Does |
|---|---|
| `EffectContext` | Shared mutable result (`damage`, `target_count`, `repeat_count`, `radius`) folded over a resolved chain |
| `PerkDefinition.apply_effect(level, context)` | Virtual method, one per perk in the chain — default adds `base_damage`; subclasses override to add their own field (design doc §11) |
| `DummyTarget` | Minimum viable target — a name + a damage-taken counter |
| `Enemy` | A `RefCounted`-free wrapper around a `DummyTarget`: an `Area2D` scene node (`main.tscn`'s `World`) with a visual, a damage label, and `take_damage()` — a persistent, positioned, invincible dummy instead of a throwaway target. Detectable by `PlayerController`'s melee hitbox via `area_entered` |
| `AbilityActivator` | `activate(board, ability_position, target)` — resolves the chain via `ChainSolver`, folds `apply_effect` over it, applies the result to `target`. `activate_with_steps(board, ability_position, target)` does the same but also returns a per-perk breakdown of what each step contributed (`{"context": EffectContext, "steps": Array[String]}`), by snapshotting `EffectContext` before/after each `apply_effect()` call — `activate()` is a thin wrapper that discards the `steps` half |

`ConnectionSolver` is the only one `Board` owns directly (`Board.connection_solver`),
because it has to run automatically on every mutation. Everything else is instantiated
wherever needed (`game_gui.gd`, `test_harness.gd`) since nothing needs it to run
automatically yet — it's all read on demand, never cached.

**Data flow for a placement:**
```
GUI click → Board.place_perk(perk, pos, output_direction, input_direction)
	→ Cell.accepts() check (perk_class vs. required_class — unrelated to input/output)
	→ cell.occupant = new PlacedPerk(perk, pos, output_direction, input_direction)
	→ perk_placed signal
	→ _recompute(pos): ConnectionSolver.recompute(board, [pos] + neighbors)
	→ board_recomputed signal
	→ (GUI) connected to board_recomputed → _refresh_ui()
```
`output_direction`/`input_direction` come from the GUI's held-perk rotation state (§4), not
from the definition — that's the core difference from the old prong system, where the sides a
perk could connect on were fixed per perk type.

Nothing pushes effect or chain recomputation — a caller (GUI tooltip, `AbilityActivator`)
just re-pulls `ChainSolver`/`apply_effect` output on demand, since none of it is cached.

---

## 4. GUI (`scenes/main/game_gui.gd`, `perk_symbol.gd`, `memory_bar.gd`)

**`main.tscn`/`main.gd` is the actual `run/main_scene`** (new this session) — `GameGui` is no
longer the whole game, it's a menu instanced under a `CanvasLayer` (`MenuLayer`), hidden by
default and toggled by a runtime-registered `toggle_menu` action (Tab + `JOY_BUTTON_START`,
same "keyboard and gamepad together" pattern as `game_gui.gd`'s own `_setup_input_actions()`).
`main.tscn`'s `World` (`Node2D`) is a placeholder 2D scene — `Ground` is a `StaticBody2D` +
`Polygon2D`, `Player` a `CharacterBody2D` + `Polygon2D` running `PlayerController`
(`scripts/player/`, gravity/floor collision/`move()`/`jump()` genuinely work; `normal_attack()`/
`special_attack()`/`dodge()`/`block()` are stubs — see ROADMAP.md item 3). A second
`CanvasLayer` (`HudLayer`, drawn below
`MenuLayer`) holds `CombatLogLabel`, a rolling 5-line log fed by `GameGui`'s
`ability_triggered(text)` signal (see below) — the natural on-screen destination for a trigger
result now that `GameGui` (and its `status_label`) is hidden exactly when a trigger can happen.
`GameGui` gained a `class_name` (`GameGui`) this session specifically so `main.gd` can hold a
statically-typed reference to it instead of a bare `Control`.

`scenes/main/game_gui.tscn` is deliberately minimal — just the root `Control` with `Board`,
`Inventory`, `MemorySystem`, `PlayerCharacter` as children. Every panel, button, and layout
container is built
in `_build_ui()` and its helpers, in code, rather than hand-authored in the `.tscn`. This
was a scope decision, not a Godot limitation: hand-editing `.tscn` resource-text-format
files (containers, anchors, unique names) without the ability to open the editor and verify
visually was judged too failure-prone; building the tree in GDScript is ordinary,
reviewable code instead.

**Layout**: `HBoxContainer` of four panels — Inventory (left), Board (center, 5x5
`GridContainer`), Memory, Player (right, Health/max Guard + the control legend). Plus two
floating overlays added directly to the root `Control`: a hover tooltip and a "held perk"
symbol that snaps to and
follows the cursor.

**Grid cells** (`_make_grid_cell()`) are a fixed-size, non-`Container` `Control` wrapper
holding a `Button` — not the `Button` sitting directly in the `GridContainer`. This matters:
a `Button`'s minimum size grows to fit its content, so a cell showing a two-line perk name
would be a different size than an empty cell unless something gives it a size the
`GridContainer` can't override. The wrapper does that; `GridContainer` sizes cells off the
wrapper (fixed), not the button (variable).

**`PerkSymbol`** (a custom `_draw()`-based `Control`, the same pattern `MemoryBar` uses) is
what actually renders a perk: a flat-colored chip (`PerkDefinition.get_display_color()`), its
icon inset to stop where the ticks start, and up to two tick marks — one for the input side
(if assigned), one for the output side (if assigned) — each a distinct base color (blue for
input, orange for output), overridden to green when `PlacedPerk.get_connected_directions()`
says that specific side currently has a live connection. Orientation only exists once a perk
is placed (chosen by the player, see below), so inventory chips show no ticks at all —
a visible consequence of moving orientation from the definition to the placed instance, not a
bug.

**Interaction model**: a single `_held: Dictionary` (`{}` when empty, else
`{"perk": InventoryPerk, "source": "inventory" | Vector2i, "rotation": int}`) drives
pick-up/place/put-down uniformly across the inventory and board — see the inline comments in
`game_gui.gd` for the exact state machine (`_held_is_from_inventory()`,
`_return_held_to_origin()`, etc.). `rotation` (0-3) is new this session: pressing **R** while
holding a perk cycles it, and `_resolve_orientation()` maps it to concrete output/input
directions (Ability and Modifier alike: output cycles N/E/S/W with input always on the
opposite side — a Modifier can feed into an Ability, not just receive from one; Core: no-op).
Picking a perk up off the board seeds `rotation`
from its current orientation so a quick pick-up/put-down doesn't silently re-orient it.
Inventory perks are grouped into stacks (same definition + level) for display; merging is a
right-click on a stack opening a small popup to choose how many pairs (always in twos) to
merge at once. `SESSION_SUMMARY.md` (in `docs/`) has the list of GDScript-specific gotchas
hit while building this, including a `Vector2i == String` comparison that throws at runtime
rather than returning false.

**Merge popup**: the pair-count control is a hand-built `-`/count/`+` stepper
(`_merge_count`/`_merge_max`, `_on_merge_count_step()`), not a `SpinBox` — `SpinBox` clamps
silently at its bounds with no signal to hook, so there was nothing to make it wrap. This one
does: at 1, `-` goes to the max; at the max, `+` wraps to 1. A "Max Merge" button
(`_on_max_merge_pressed()`) cascades every possible pair within *just* the stack the popup was
opened for — buckets perks by level, repeatedly merges the lowest level with 2+ available and
feeds the result into its own (next) level's bucket, until no level has a pair left. A stack of
4 level-1s becomes one level-3, not two level-2s; a true odd-one-out (no same-level partner at
whatever level it lands on) is left unmerged, same rule the plain "Merge" button already
followed.

**Seeding**: `_seed_inventory()` (via `_load_perk_definitions_from()`, which recurses) scans
every `.tres` under `resources/perks/` — including its `core/`/`ability/`/`modifier/`/`memory/`
subfolders — and adds one `InventoryPerk` per definition found (four for Modifier-class perks,
so there's something mergeable to test with immediately; everything else, including Memory,
gets one). This means the GUI never hardcodes which perks exist, or where under
`resources/perks/` they live — content and code are fully decoupled.

**Memory slot** (new this session): a single dedicated slot under the memory bar
(`_build_memory_panel()`), built with the same `_make_grid_cell()` helper as board/inventory
cells (now taking a `slot_marker_color` instead of a bare `is_ability_slot` bool, so the
Ability-slot gold frame and this slot's teal frame share one code path) — but it is *not* a
`Board`/`Cell` at all. It's backed directly by `MemorySystem.slotted_perk`
(`can_slot()`/`slot_perk()`/`unslot_perk()`), and `Cell.accepts()` separately rejects
`PerkClass.MEMORY` on every real board cell, so a Memory perk structurally can never end up
anywhere but this one slot. `_held`'s `"source"` gained a third case for this
(`"inventory"` / `"memory_slot"` / a `Vector2i` board position) — `_held_is_from_inventory()`
had to stop treating "any String" as "from inventory" once a second String source existed, and
gained a sibling `_held_is_from_memory_slot()`; both type-check with `is String` before ever
comparing against a literal, same reasoning as the existing `Vector2i == String` crash note
just above.

**Ability controls** (new this session): `ABILITY_ACTIONS` maps 4 input-action names to 4
fixed `PerkDefinition.id`s — `jump`→`jump`, `dash`→`dash`, `attack_normal`→`normal_attack`,
`attack_special`→`special_attack`. This is the "fixed named abilities" model: an action always
means that specific perk, wherever it's currently placed among the 5 Ability slots (not a
fixed board position). Shield isn't in this map: it's the Block button's ability, handled by
PlayerController, its chain fires on a parry (TriggerRouter), and its scaled `base_damage` is
read as max Guard (`ShieldPerkDefinition.max_guard_on()`), never as damage.
- `_setup_input_actions()` registers each action on Godot's `InputMap` singleton *at runtime*
  (`InputMap.add_action()` + `action_add_event()`) rather than hand-editing `project.godot`'s
  `[input]` section — every action gets both a keyboard/mouse binding and a gamepad binding
  (`JOY_BUTTON_A`/`X`/`Y`/`LEFT_SHOULDER`) up front, so controller support falls out of using
  Input Map actions instead of hardcoded key checks. Trade-off: these won't appear in Project
  Settings → Input Map (that UI reflects `project.godot`, not runtime `InputMap` state) — only
  a discoverability gap, not a functional one.
- `_unhandled_input()`, not `_process()`/`_input()`: a `Button` consumes the click it takes for
  its own `pressed` signal, and the two right-click handlers (`_on_board_cell_gui_input`,
  `_on_inventory_stack_gui_input`) now call `set_input_as_handled()` explicitly, since a
  `Button` doesn't auto-consume a right click the way it does a left one — both matter because
  `attack_special` is also bound to the right mouse button. This is also why every purely
  decorative layout `Container`/`PanelContainer` built in `_build_ui()` and its helpers has
  `mouse_filter = MOUSE_FILTER_IGNORE` set explicitly: left at the Godot default, they'd swallow
  clicks that land on empty background before `_unhandled_input` ever saw them. Every dynamically
  created `Button` also gets `focus_mode = FOCUS_NONE`, so a stray Space/Enter can't re-trigger
  whatever was last clicked (Godot's default focused-button behavior) instead of firing `jump`.
  `_unhandled_input()` now also opens with `if not visible: return` — the other half of the
  menu-toggle from `main.tscn`'s perspective (see above): `main.gd` only toggles `visible`,
  this guard is what actually makes triggering menu-closed-only.
- `AbilityController` (`scripts/player/ability_controller.gd`, `RefCounted`) does the actual
  lookup-and-activate: `find_placed(board, perk_id)` scans `board.get_all_placed_perks()` for a
  matching `id`. `game_gui.gd._trigger_named_ability()` calls `find_placed()` once, then
  `ability_controller.ability_activator.activate_with_steps(board, placed.position,
  combat_target)` — against `combat_target` (a settable `DummyTarget`, defaulting to a fresh
  throwaway one so `game_gui.tscn` still works instanced standalone, e.g. by most of
  `scenes/tests/`; `main.gd` overwrites it with the persistent `Enemy`'s own target once both
  are ready — see `Enemy`, `scripts/combat/enemy.gd`). `activate_with_steps()` returns both the
  final `EffectContext` and a per-perk breakdown string array, which `_trigger_named_ability()`
  combines into one `ability_triggered` line: the total plus whichever of `EffectContext`'s
  fields are non-default, then each step indented on its own line (`"Normal Attack: 15
  damage\n  Normal Attack: +10 damage\n  Fire: +5 damage"`) — or a not-placed message if
  `find_placed` returned `null`.

---

## 5. Practical notes for continuing this project

- **New `class_name` scripts need Project → Reload Current Project** in the editor before
  cross-references to them resolve. This bit repeatedly during this build. Headlessly, the
  equivalent is `Godot_v4.5.1-stable_win64_console.exe --headless --editor --quit --path
  <project>` — forces the same global-class rescan without opening a window.
- **The project's `run/main_scene` is `scenes/main/main.tscn`** (§4) — press Play to get the
  2D game view with the perk-board GUI as a Tab-toggled menu.
- **A headless Godot binary is available**: `C:\Program Files (x86)\Godot\
  Godot_v4.5.1-stable_win64_console.exe` (found and confirmed working partway through this
  project — earlier notes claiming otherwise are stale). Use the `_console.exe` variant, not
  the plain `.exe` — the plain one is a windowed-subsystem binary that won't stream
  stdout/stderr to a terminal.
  - `--headless --path <project> --quit` — loads `run/main_scene`, runs one frame (so every
	`_ready()` in the initial tree executes), quits. Confirms the project loads and compiles
	without errors.
  - `--headless --path <project> res://scenes/tests/<name>.tscn --quit-after N` — runs one of
	the 11 scripted-assertion scenes below instead of `run/main_scene`. `N` needs to be
	generous for anything that `await`s real time passing (physics settling, simulated key
	presses) — `--quit-after` counts main-loop iterations, which race far ahead of wall-clock
	time in headless mode, so a test with a few frames of `await` needs `N` in the hundreds or
	low thousands, not single digits, or the engine quits before the coroutine ever resumes.
- **`scenes/tests/`** holds 11 scripted-assertion regression scenes (moved out of
  `scenes/main/` once there were enough to clutter it), all `print()`ing `[PASS]`/`[FAIL]`
  lines and a final `Result: N passed, M failed` — 61 assertions total, all passing as of this
  writing. Most instance `game_gui.tscn` directly and drive it through its real methods/`_held`
  state (a few instance the full `main.tscn` instead, where the check needs `World`/`Enemy`/
  `PlayerController` too):
  - `test_harness.tscn` — the original Board/Inventory/MemorySystem/`AbilityActivator` smoke
	test (predates the GUI). Converted from print-only output to real assertions along with
	the rest of this list.
  - `input_flow_test.tscn` — ability-trigger gating (`GameGui.visible`) via real simulated
	`Input.parse_input_event()` clicks, and the per-Modifier combat-log breakdown.
  - `memory_slot_test.tscn` — Memory perk/slot mechanics (capacity 0 empty, doubling per
	level, `Cell.accepts()` rejecting `PerkClass.MEMORY` everywhere on the board).
  - `connection_orientation_test.tscn` — proves connections are genuinely directional:
	vertical neighbors connect at default rotation (coincidence of the defaults), horizontal
	neighbors need both perks actively rotated to face each other.
  - `rotation_connection_test.tscn` — same question via *real* `KEY_R` presses end to end;
	caught a real bug (see below) where the two didn't agree.
  - `rotation_persistence_test.tscn` — picking an already-placed perk back up, rotating it,
	and placing it back at the same cell keeps the *new* orientation.
  - `upstream_modifier_test.tscn` — a Modifier connected to an Ability's *input* side (not
	just its output) still contributes — and, since the `ChainSolver` rework (§3), resolves
	*before* the Ability rather than after it, because it's genuinely the head of that chain.
  - `three_perk_chain_test.tscn` — a straight 3-perk chain (Ability → Fire → Fire) resolves
	and applies all three steps when properly oriented.
  - `max_merge_test.tscn` — the merge popup's cascading "Max Merge" (below) actually cascades
	(4 level-1s → one level-3, not two level-2s) and leaves a true odd-one-out unmerged.
  - `player_controller_test.tscn` — `PlayerController`'s gravity/floor collision actually
	settles the body on `World/Ground` rather than falling through it, and `jump()` sets an
	upward velocity while grounded.
  - `enemy_test.tscn` — `main.gd` correctly wires `GameGui.combat_target` to the persistent
	`Enemy`'s own `DummyTarget` (damage accumulates across multiple triggers instead of
	resetting), and the melee hitbox actually deals damage to an `Enemy` it overlaps.

  Bugs found only because of these (all fixed): `_unhandled_input`'s `visible` guard had its
  boolean inverted (blocked triggering exactly when the menu was closed); the R-key rotation
  handler checked `event.keycode` (layout-dependent) instead of `event.physical_keycode` (the
  convention every other binding in the file already used); `ChainSolver` originally only
  walked forward from an Ability's own *output*, so a Modifier connected to its *input* side
  formed a real connection that silently contributed nothing (fixed once, then superseded by
  the full head-to-tail rework, §3); and the melee hitbox's `CollisionShape2D` had a static
  `disabled = true` baked into `main.tscn` that `normal_attack()`'s `Area2D.monitoring` toggle
  never touched, so the hitbox could never detect anything regardless of the attack timing —
  fixed by moving the resting-state gate onto `monitoring` alone (`disabled` removed).
