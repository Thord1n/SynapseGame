# SynapseGrid — Open Issues

Replaces the previous numbered-priority tracker (Priorities 1–8 from the session that built
effect application) — that list is now almost entirely done; see "Resolved" below for the
record. This is a fresh list of what's actually unresolved, most important first. Priority
here means "matters most to the project's stated goal — SynapseGrid as a real combat
backend, not just a board editor" — not necessarily easiest or most requested.

See [SESSION_SUMMARY.md](SESSION_SUMMARY.md) for the narrative of how the project got here, and
[design/systems/architecture_overview.md](design/systems/architecture_overview.md) for the
code-level map.

---

## 1. No persistence

Nothing saves or loads inventory, board layout, or the Memory slot between runs. This mattered
less when the project was purely an editor prototype; it matters more now that `main.tscn` is
a real `run/main_scene` with a Tab-toggle menu and an actual game view — every relaunch starts
from the seeded-inventory, empty-board, unslotted-memory state (which also means: no board
placement is possible at all until you re-slot a Memory perk every time).

## 2. Attacks aren't routed through the real perk-damage system yet

Two separate, not-yet-reconciled ways to "attack" both exist now: `game_gui.gd`'s
`ABILITY_ACTIONS` (unchanged, resolves the real perk chain via `AbilityActivator` and reports
exact damage) and `PlayerController`'s new melee hitbox (`normal_attack()`, a timed `Area2D`
that deals a **flat placeholder** `PLACEHOLDER_MELEE_DAMAGE` to whatever `Enemy` it overlaps —
see `scripts/player/player_controller.gd`). Both fire independently; pressing `Normal_attack`
in-game triggers the perk resolution (logged to the combat log) *and*, separately, swinging the
hitbox deals its own unrelated flat number if it happens to connect. The real version replaces
the flat number with `PlayerController` resolving the actual perk chain (needs a `board`
reference this node doesn't have yet — see the TODOs in `normal_attack()`/`special_attack()`).
`special_attack()` and `dash()` are still bare stubs (dash additionally needs a design call:
is it the perk board's already-working "Dash" trigger, or a separate mechanic layered on top of
it?). `block()`'s input side works but has nothing to mitigate — no damage-to-player system
exists yet, so `PlayerCharacter`'s Health/Shield (still living under `GameGui`/`MenuLayer`
rather than `World`, a separate unreconciled "player" piece — see `player_controller.gd`'s
class doc) never actually changes.

## 3. No cooldowns or resource costs on abilities

Neither `AbilityController.trigger()` (perk-triggered) nor `PlayerController`'s hitbox fires
with any cost or cooldown — nothing stops spamming left-click. Not currently implied by any
existing design discussion; flagging so it doesn't get silently assumed one way or the other
whenever this gets addressed.

## 4. Linger's damage-over-time is unimplemented

Linger is an `AreaPerkDefinition` like Explosion and currently behaves identically to it
(contributes `radius` only) — the "becomes a DoT" part of its intended design never got built.
Needs a per-frame or per-tick update loop and a way to track active timed effects, neither of
which exists anywhere in the codebase yet; this is a bigger architectural addition than it
looks, since everything else so far is recompute-on-mutation, not recompute-on-time.

## 5. Manual rotation is failure-prone, and it's caused real confusion repeatedly

Across this project, most "a connected modifier doesn't apply" reports turned out to be
orientation mistakes, not bugs (see `SESSION_SUMMARY.md`'s "Bugs found" section) — connecting
two perks means giving them the *same* rotation state to extend a straight line, not mirroring
them to visually "face" each other, which is the more intuitive-but-wrong instinct. Manual
rotation is a deliberate, explicit choice (no auto-orient wanted), so the fix here isn't
behavioral — it's making the *feedback* better: the green/blue/orange tick-mark system already
exists (`PerkSymbol`) but a lightweight on-screen legend or hint might cut down on this class
of report. Not requested yet; flagging as a candidate, not a plan.

## 6. Content and balance are placeholder-quality throughout

Damage values, memory costs, and capacities (Normal Attack's `base_damage = 10.0`, Memory's
`4` bytes at level 1, `PLACEHOLDER_MELEE_DAMAGE`, etc.) were picked to demonstrate mechanics
correctly, not to feel good to play. Expected to need a real tuning pass once there's enough of
a game loop (items 1–2 above) to actually play through.

---

## Resolved (for the record — see `SESSION_SUMMARY.md` for the full narrative)

- **No real target/enemy model** — `Enemy` (`scripts/combat/enemy.gd`, an `Area2D` in
  `main.tscn`'s `World`) is a persistent, visible, invincible dummy; ability triggers deal
  damage to it via `GameGui.combat_target` instead of a throwaway `DummyTarget` that reset
  every press. `target_count`/`radius` still don't drive real spatial queries (only one target
  exists) — a smaller remaining gap than the original "nothing to target at all."
- **No player movement** — `World/Player` is a real `CharacterBody2D`
  (`scripts/player/player_controller.gd`) with working gravity/floor collision, `move()`/
  `jump()` (menu-gated to match the perk-triggered controls), and a melee hitbox for
  `normal_attack()`. What's left of this is now item 2 above (routing attacks through the real
  perk-damage system) rather than "nothing moves."
- **`ChainSolver`'s bidirectional check only covered the Ability's own first hop** —
  superseded, not just fixed: `resolve_chain()` no longer special-cases the Ability at all. It
  walks backward from whatever position it's given to find the chain's true head (nothing feeds
  into it), then forward head-to-tail — an Ability can sit anywhere in a chain, not just the
  head, and every perk's predecessor is found the same general way. This is also what makes a
  future position-sensitive perk (e.g. a damage-amplifier Modifier meant to apply *before* the
  Ability it's boosting) actually buildable. See `perk_board_system.md` §7.
- **`test_harness.gd`'s coverage was still print-based** — converted to the same PASS/FAIL
  assertion pattern as every other scripted check (12 assertions, all passing).
- **Test scenes were cluttering `scenes/main/`** — all 10 (plus `test_harness`) moved into
  `scenes/tests/`; `scenes/main/` now holds only the three real scenes.
- **Effect/target data contract, baseline Ability effects, consuming `ChainSolver`'s output** —
  `EffectContext`/`apply_effect`/`AbilityActivator`, all real and working.
- **Branching chain semantics** — resolved by construction (one input + one output per perk
  makes a tree structurally impossible), not by a standalone tiebreak decision.
- **`PerkEffectDef`/subclass-fields duplication** — `PerkEffectDef`/`base_effects`/
  `EffectSolver` deleted outright in favor of the subclass fields, which already carried all
  the real content.
- **Regression tooling** — headless Godot was assumed unavailable in earlier notes; it's
  installed and confirmed working (`Godot_v4.5.1-stable_win64_console.exe`). 11 scripted
  scenes now exist in `scenes/tests/`, 61 assertions total, all passing.
- **Memory upgrades never surfaced in the GUI** — replaced, not exposed: `MemoryUpgrade` is
  deleted, capacity now comes from a real `PerkClass.MEMORY` perk in a dedicated slot.
- **The prong connection system** — replaced with the directed input/output model (see
  `perk_board_system.md` §1/§2/§6/§7).
- **An Ability could only be fed by a Modifier connected to its output, not its input** — a
  real user-reported gap, ultimately resolved by the `ChainSolver` rework above.
