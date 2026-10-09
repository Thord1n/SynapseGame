# SynapseGrid — Perk Board System Design

Dev-facing name: **SynapseGrid**
Player-facing name (flavor): Core Matrix / Neural Array (TBD, not locked in)

This document captures the design decisions for the grid-based perk/board system:
placement, connections, effects, leveling via merges, and memory-capacity budgeting.
Intended as reference context for implementation work.

> **Implementation status**: a working Godot 4.5 GUI test harness now exists for everything in
> this document, including a first pass at effect application (§7, §8, §11). Code lives under
> `scripts/board/`, `scripts/perks/`, `scripts/combat/`, and `scenes/main/`; see
> `docs/design/systems/architecture_overview.md` for the code-level map. Sections below are
> updated in place where implementation settled an open question (most significantly: prongs
> were replaced with a directed input/output model, §1/§2/§6/§7); net-new systems are called
> out as new sections.
>
> A first player-character layer now sits on top of this system, outside this document's own
> scope (it's about the board, not the character): `scripts/player/` — `PlayerCharacter`
> (Health, and Shield derived from a placed Shield perk of PerkClass Ability) and
> `AbilityController` (maps left click/right click/space/shift to the Ability perk with a
> matching `id`, wherever it's currently placed, and activates it via §11's
> `AbilityActivator`). See `architecture_overview.md` §4 for the full wiring.
>
> §4's memory-capacity model was replaced a second time, most recently by a `PerkClass.MEMORY`
> perk slotted into its own dedicated UI slot (not the board) — see §4 and §6 below for the
> current model; the original `MemoryUpgrade` item mechanism it replaced was deleted outright.

---

## 1. Core Concepts

- **Board**: a grid (up to 10x10, sizes may vary up to ~2x smallest board) where perks are placed.
  *Implemented as a 5x5 test board.*
- **Perk**: has a fixed `Definition` (template) and a `Level` (from merging).
- **Input/Output** *(replaces the original "Prongs" concept — see §6/§7)*: every non-Core
  perk — Ability and Modifier alike — has exactly one input side and one output side. Unlike
  the original fixed-per-definition prongs, which side is which is chosen by the player at
  placement time (rotatable), not baked into the definition. An output only links to a
  neighbor's input; each side declares which `PerkClass`es it accepts. Because Abilities have
  an input too, a Modifier can feed its output into an Ability, not just receive from one.
- **Connections**: formed when an output physically faces an adjacent perk's input and both
  sides' accept-lists allow the other's class. Directional, unlike the old symmetric prong
  match.
- **Effects**: derived from a perk's level and its position in the chain its output/input
  connections form. Never stored permanently — always recalculated from board state. See §7
  for how the chain is walked and §11 for how each perk's effect is actually applied.
- **Memory**: a capacity budget. Placing perks consumes memory; capacity comes from upgrades found/
  purchased during play (not from player stats).
- **Perk Class** *(added during implementation, not in the original design pass — see §6)*:
  every perk is Core, Ability, or Modifier. This governs input/output rules and board
  placement rules, and is orthogonal to the merge/leveling system above.

---

## 2. Data Model

### PerkDefinition (immutable template)
```
PerkDefinition
-------------------------
ID
Name
Description
Icon
PerkClass          // Core | Ability | Modifier — see §6

InputAccepts    : PerkClass[]   // which classes this perk's input will accept
OutputAccepts   : PerkClass[]   // which classes this perk's output will accept
	// Core resolves to no input/output at all regardless of these values — enforced, not a
	// data-entry convention (see §6). Ability and Modifier both use them as-is. Which
	// physical side is the input and which is the output isn't defined here at all — see
	// PlacedPerk below.

BaseDamage        // baseline effect at level 1 — see §11
BaseMemory        // integer bytes at level 1 — see §4
Complexity        // multiplier used in memory cost formula
ScalingExponent    // used in both effect and memory scaling
Tags
```

**Subclassing for perk-type-specific stats.** Rather than growing `PerkDefinition` with
fields only some perks use, perk *types* that need their own stat extend it as a Resource
subclass:

```
ElementalPerkDefinition extends PerkDefinition   // Fire, Shock, Ice
	Element : enum { Fire, Shock, Ice }
	Damage  : float   // unbounded scaling — see §8

AreaPerkDefinition extends PerkDefinition        // Explosion, Linger
	Radius    : float   // level-1 value
	MaxRadius : float   // asymptotic ceiling — see §8

EchoPerkDefinition extends PerkDefinition        // Echo
	Echoes : int   // linear scaling — see §8

ChainPerkDefinition extends PerkDefinition       // Chain
	Chains : int   // linear scaling — see §8
```

A new perk *instance* of an existing type (e.g. a new elemental perk) is just a new data
resource — no code changes. A new perk *type* with its own stat is a new subclass. Both
`GetDisplayColor()` and `GetTooltipExtra(level)` are virtual on `PerkDefinition` (default:
class-based color, no extra tooltip text) so each subclass only overrides what it needs.

### InventoryPerk (unplaced, mergeable)
```
InventoryPerk
-------------------------
Definition
Level
```

### PlacedPerk (on the board)
```
PlacedPerk
-------------------------
InventoryPerk     // Definition + Level
Position
OutputDirection   // chosen by the player at placement — which side is this instance's output
InputDirection    // chosen by the player at placement — which side is this instance's input
Connections       // cached, only meaningful while placed
```

`OutputDirection`/`InputDirection` live on the *instance*, not the definition — this is the
input/output model's core difference from the old prong system, where connection sides were
fixed per perk type. Core is the only class that never has either assigned.

Splitting `InventoryPerk` from `PlacedPerk` keeps the merge/crafting system fully decoupled from
the board/connection/effect system. Merging never touches `ConnectionSolver` or the combat
layer (§11).

### Board
```
Board
----------------------
Dictionary<Vector2, Cell>

Cell
	Position
	Occupant (PlacedPerk?)
```

Using a dictionary rather than a fixed 2D array supports non-rectangular board shapes without
wasted/empty cells.

### Connection
```
Connection
--------------------
PerkA   // the output/from side
PerkB   // the input/to side
Direction   // from PerkA to PerkB, i.e. PerkA.OutputDirection
```

Because sides are chosen per-instance (not per-definition), compatibility now depends on
placement state, not just the two definitions — it's still cheap to check on demand rather
than cache:

```
CanConnect(from, to, direction):
	return from.OutputDirection == direction
	   and to.InputDirection == Opposite(direction)
	   and from.Definition.OutputAccepts.Contains(to.Definition.PerkClass)
	   and to.Definition.InputAccepts.Contains(from.Definition.PerkClass)
```

*Implementation note*: `ConnectionSolver.can_connect()` just calls this directly per candidate
pair — an O(1) check, so there's no cache layer to maintain.

---

## 3. Leveling via Merges (off-board)

Merging happens in the inventory, not on the board. Two identical perks (same definition, same
level) combine into one perk at the next level:

```
Merge(a: InventoryPerk, b: InventoryPerk) -> InventoryPerk:
	require a.Definition == b.Definition
	require a.Level == b.Level
	return new InventoryPerk(a.Definition, a.Level + 1)
```

Progression is binary: Level N = 2^(N-1) equivalent Level-1 perks ("Power").

| Level | Power (equiv. Lvl 1) |
|-------|----------------------|
| 1     | 1                    |
| 2     | 2                    |
| 3     | 4                    |
| 4     | 8                    |
| 5     | 16                   |
| 6     | 32                   |

Placing a perk moves it from `InventoryPerk` → `PlacedPerk` (triggers board recompute, see §5).
Removing a perk reverses this (also triggers recompute for the vacated cell + neighbors).

---

## 4. Stat & Memory Scaling

Avoid hand-balancing every level individually — derive everything from `Power = 2^(Level-1)`.

**Effect scaling** (sub-linear, so doubling perks doesn't double power indefinitely):
```
EffectValue = BaseValue × Power^ScalingExponent
```
Different attributes can use different exponents (e.g. damage 0.78, health 0.9, crit additive).

**Memory scaling** — hard-drive-style storage, so cost is modeled in whole bytes, not a
fractional unit:
```
Memory = ceil(BaseMemory × Complexity × 2^((Level-1) × ScalingExponent))
```
- `BaseMemory` is an integer (bytes) on `PerkDefinition`; the scaling math is still done in
  float and rounded up at the end, same as the level-scaled subclass stats in §8.
- `Complexity` lets simple perks stay cheap and mechanically-rich perks cost more, tuned per
  perk definition independent of level.
- A sub-linear exponent (~0.6–0.8) avoids double-punishing high-level perks (they're already rare
  due to merge cost — memory shouldn't also scale a full 32x at level 6).

**Memory capacity** (separate from usage) *(revised twice during implementation — see below)*:
```
MemoryCapacity = SlottedMemoryPerk.ScaledValue if a Memory perk is slotted, else 0
MemoryUsed     = Sum(PlacedPerk.MemoryCost for all placed perks)
```
The original design's `MemoryUpgrade`/`base_capacity` mechanism (capacity doubling per owned
upgrade item) was replaced with a **Memory perk**: `PerkClass.MEMORY`, a perk like any other —
levels via merging, placed via the board's normal inventory flow — except it never goes on the
board itself. It goes in `MemorySystem`'s own single dedicated slot instead (a UI element under
the memory bar, not a board `Cell`), and capacity is read directly off whichever perk currently
occupies that slot: `4 × 2^(Level-1)` (level 1 = 4 bytes, doubling per level after that, via the
same `Power` curve as everything else — `ScalingExponent = 1.0` gives a pure doubling with no
sub-linear falloff). **With nothing slotted, capacity is 0** — no perk can be placed on the
board at all until a Memory perk is slotted (or, from the other direction, until enough perks
are removed from the board that usage drops back to 0 too). This is a harder requirement than
the old design's "capacity might be below usage" case: here capacity legitimately starts at
zero, not just at risk of dropping there.

`MemoryUpgrade` is retired, not just superseded — the class and its file were deleted rather
than left unused. `Cell.accepts()` rejects `PerkClass.MEMORY` unconditionally, on any board
cell, restricted or not: a Memory perk isn't merely "board-eligible everywhere" like Core, it's
never board-eligible at all. Same reasoning that gave Core no input/output (see §6) applies to
Memory: neither ever participates in a connection.

Capacity being slot-perk-driven (not derived from player stats, not summed from arbitrary
upgrade items) keeps the "think of it as buying a bigger hard drive" framing from the original
design. If capacity ever drops below current usage (a higher-level Memory perk swapped for a
lower one, or unslotted entirely), **soft-lock** new placements rather than force-unequipping
perks already on the board — less punishing, avoids surprising the player, unchanged from the
original design's intent.

---

## 5. Incremental Board Updates

Board size is small (max 100 cells), so a simple dirty-set approach is sufficient — no need for
spatial partitioning or other heavy optimization.

```
OnPerkPlaced(perk, position):
    dirty = { position } + Neighbors(position)   // up to 4 cells

    for cell in dirty:
        RecomputeConnections(cell)

    affected = dirty + TransitiveNetworkMembers(dirty)  // only if effects care about whole networks
    for perk in affected:
        RecomputeEffects(perk)

    RecalculatePlayerStats()   // only if affected set is non-empty
```

Connections are inherently local: a placement can only change links touching itself, so only the
placed cell and its immediate neighbors need re-checking. Effects only need recomputation for
perks whose connection state actually changed. Full-board recompute is affordable as a fallback
given the board size, but the dirty-set version should be the default.

Same removal logic applies in reverse when a perk is taken off the board.

---

## 6. Perk Classification & Board Slots

*(Added during implementation — not part of the original design pass.)*

Every `PerkDefinition` has a `PerkClass`:

- **Core** — linked to core player functionality (stats, base kit). Never has an input or
  output, enforced at the code level regardless of what a definition's accept-list fields
  say — a Core perk can never form a connection, on either side.
- **Ability** — a player ability (Jump, Normal Attack, Special Attack, Dash, ...). Has both an
  input and an output (each chosen by the player at placement), same as Modifier — a Modifier
  can feed its output into an Ability, so an Ability doesn't have to be the first thing in a
  chain. What triggers is still whichever Ability position the player activates (see §7); the
  input just means a chain can run through it rather than always starting there.
- **Modifier** — has both an input and an output (each chosen by the player at placement),
  so it can sit mid-chain: receives whatever's accumulated so far on its input side, applies
  its own effect, passes the result on via its output (see §7 for how this becomes an ordered
  chain).
- **Memory** *(added later still — see §4)* — grants board memory capacity while equipped in
  `MemorySystem`'s own dedicated slot, a UI element entirely separate from the board. Like
  Core, never has an input or output. Unlike Core, it isn't merely "welcome anywhere" on the
  board — it's never board-eligible at all (see the slot-restriction rule immediately below).

**Board slot restriction** is asymmetric, not a simple exact-match filter: a cell can be
marked Ability-only, in which case only Ability perks may occupy it — but every other
board-eligible class (Core, Modifier) can be placed on *any* cell, ability slots included. The
rule exists to guarantee a board always has room for its Abilities without blocking Modifiers
from also using those same cells if nothing else needs them. (Test implementation: the middle
column of the 5x5 board is marked Ability-only.) Memory perks sit outside this rule entirely —
every board cell rejects `PerkClass.MEMORY` unconditionally, since they only ever go in the
memory slot (§4), never the board.

---

## 7. Modifier Chains & Ordering

*(Added during implementation, extending the original "Connections" concept in §1/§2 — not
part of the original design pass. Revised twice since: first after the prong → input/output
change (§1/§2/§6) flipped the original farthest-first order; then again, replacing an
Ability-always-first rule with the head-to-tail resolution below — see "Resolved" further
down.)*

A chain of perks connected in sequence determines what happens when an Ability *in* that
chain is triggered — and **order matters**. Because every perk has exactly one input and one
output (§6), a chain is always a single straight path, and resolution walks it **head to
tail**: whichever perk has nothing feeding into its input goes first, then each perk in turn
following outputs forward to the end. The Ability doesn't have to be the head — it can sit
anywhere in the chain depending on how the player wired it — and resolving from any perk's
position in a given chain finds the same head and the same order. Given
`Fire(output) -> Ability(input/output) -> Chain(input)`, resolution is `[Fire, Ability,
Chain]` regardless of whether you resolve from Fire's position, the Ability's, or Chain's.

```
ResolveChain(board, fromPosition) -> PlacedPerk[]:
	// Walk backward via each perk's input side, starting from fromPosition, until reaching a
	// perk with nothing feeding into it — the chain's head. Then walk forward from the head via
	// each perk's output side, appending every perk in turn until a dead end. No perk-class
	// distinction anywhere in this walk — an Ability is just whichever perk happens to be
	// wherever it is in the chain, not a structurally special starting point.
```

This is currently **ordering only** in the sense that ChainSolver itself doesn't apply
effects — folding the resolved chain into an actual result is AbilityActivator's job (§11).
The reason order is worth getting right beyond aesthetics: a future position-sensitive perk
(e.g. a damage-amplifier Modifier meant to scale whatever the Ability contributes) needs a
guarantee that whatever's upstream of the Ability actually resolves *before* it, which an
Ability-always-first rule could never provide.

**Resolved** (was an open question earlier in implementation, resolved twice): an Ability can
have a Modifier feeding into its input (e.g. `Fire -> Ability`), since Ability has an input
like Modifier does. A real user report surfaced this concretely — connecting a Modifier to the
"wrong" side of an Ability formed a real connection that silently contributed nothing, since
the original `ResolveChain` only walked forward from the Ability's own output and never looked
backward. A first fix made the Ability's own first hop check both sides, which caught this
case but still forced the Ability to resolve first, always — `Fire -> Ability` resolved as
`[Ability, Fire]`, Fire's effect applied right *after* the Ability's own rather than before it.
That's been replaced by the head-to-tail walk above: `Fire -> Ability` now resolves as
`[Fire, Ability]`, matching where each perk actually sits in the chain rather than treating
the Ability as structurally privileged.

**Branching is no longer an open question.** The original design had prongs on up to 4 sides,
so a Modifier could have more than one unvisited Modifier neighbor — a branch with no defined
meaning. With exactly one output per perk, that's structurally impossible: a chain is always
a single straight path, never a tree. This resolves what was previously an explicitly
unresolved design question, as a side effect of the input/output model rather than a decision
made on its own terms.

---

## 8. Level Scaling Curves

*(Added during implementation. §4 establishes `EffectValue = BaseValue × Power^ScalingExponent`
for generic effects and memory cost; the perk-type-specific stats introduced by the
subclasses in §2 needed their own scaling decisions, since a straight application of that
formula doesn't fit every kind of stat.)*

All three curves below round up to the nearest integer for display. `Power = 2^(Level-1)`
throughout, same as §3/§4.

**Unbounded** (Elemental `Damage`) — the original §4 formula, unchanged, just rounded:
```
Damage(level) = ceil(BaseDamage × Power^ScalingExponent)
```

**Asymptotic, approaching a per-instance cap** (Area `Radius`) — grows quickly at first,
then flattens out toward `MaxRadius` without ever reaching it exactly. Exactly `Radius` at
level 1:
```
Radius(level) = ceil(MaxRadius - (MaxRadius - Radius) / Power^ScalingExponent)
```
Explosion aims for 20 (base 3); Linger aims for 10 (base 2) — both reach ~95% of their cap
by level 5-6.

**Linear** (Echo `Echoes`, Chain `Chains`) — deliberately *not* on the Power curve; a flat
`+1` per level:
```
Echoes(level) = BaseEchoes + (level - 1)
```
Chosen because these are repeat/target *counts*, not magnitudes — a fractional echo doesn't
mean anything, and exponential count growth would spiral quickly (level 6 would be 13+
echoes under the Power curve vs. 6 under linear).

---

## 9. Incremental Board Updates

Board size is small (max 100 cells), so a simple dirty-set approach is sufficient — no need for
spatial partitioning or other heavy optimization.

```
OnPerkPlaced(perk, position):
	dirty = { position } + Neighbors(position)   // up to 4 cells

	for cell in dirty:
		RecomputeConnections(cell)

	affected = dirty + TransitiveNetworkMembers(dirty)  // only if effects care about whole networks
	for perk in affected:
		RecomputeEffects(perk)

	RecalculatePlayerStats()   // only if affected set is non-empty
```

Connections are inherently local: a placement can only change links touching itself, so only the
placed cell and its immediate neighbors need re-checking. Effects only need recomputation for
perks whose connection state actually changed. Full-board recompute is affordable as a fallback
given the board size, but the dirty-set version should be the default.

Same removal logic applies in reverse when a perk is taken off the board.

---

## 10. System Responsibilities (summary)

```
Board
│
├── Cells (Dictionary<Vector2, Cell>)
│    └── PlacedPerk
│
├── ConnectionSolver
│    └── Connection[] (dirty-set incremental recompute) — directional, see §7
│
└── ChainSolver
	 └── Ordered Modifier chain per Ability, ability-first (recalculated on demand), see §7

Inventory (separate system)
└── InventoryPerk merge logic — no dependency on Board/ConnectionSolver

Combat (separate system, see §11)
├── EffectContext
│    └── Shared mutable result, folded over a resolved chain
├── PerkDefinition.ApplyEffect(level, context)
│    └── Per-perk contribution — the level-scaling formulas from §8, applied to the context
└── AbilityActivator
	 └── Resolves a chain via ChainSolver, folds ApplyEffect over it, applies the result to
		 a target
```

- **Board**: where are the perks? Also owns cell-level Ability-slot restrictions (§6).
- **PerkDefinition**: what is this perk? (immutable template; subclassed per perk type, §2)
- **InventoryPerk / PlacedPerk**: a specific perk instance, unplaced or placed
- **ConnectionSolver**: which perks are connected? (local, incremental, directional)
- **ChainSolver**: in what order does a connected chain of Modifiers resolve? (§7)
- **AbilityActivator**: what actually happens when an Ability triggers? (§11)
- **MemorySystem**: capacity vs. usage, upgrade-driven, soft-lock on overflow

This separation of concerns should make it straightforward to add mechanics later (network-wide
effects, new perk tags, additional upgrade sources) without rewriting board or connection logic.

---

## 11. Effect Application

*(Added during implementation, after §7's chain ordering existed but nothing consumed it.)*

Applying an effect produces a small set of **heterogeneous** results, not one uniform number —
Chain and Echo are multipliers (how many targets, how many repeats), not damage. These are
carried on a shared `EffectContext` folded over the chain in ChainSolver's order:

```
EffectContext
-------------------------
Damage
TargetCount    // how many targets the final effect hits — inert until a real target model
			   // exists (see below)
RepeatCount    // how many extra times the final effect repeats (Echo)
Radius         // inert until a real target model exists (see below)
```

Each perk contributes via a virtual method on `PerkDefinition`:

```
ApplyEffect(level, context):
	context.Damage += ScaledBaseDamage(level)   // base PerkDefinition's contribution

// Subclasses override, calling the base version first, then adding their own field:
ElementalPerkDefinition.ApplyEffect: context.Damage += ScaledDamage(level)
AreaPerkDefinition.ApplyEffect:      context.Radius += ScaledRadius(level)
ChainPerkDefinition.ApplyEffect:     context.TargetCount += ScaledChains(level)
EchoPerkDefinition.ApplyEffect:      context.RepeatCount += ScaledEchoes(level)
```

`AbilityActivator.Activate(board, abilityPosition, target)` resolves the chain, folds
`ApplyEffect` over each perk in order, and applies `Damage × RepeatCount` to `target` — the
minimum viable target model is a single hardcoded dummy (a name + damage-taken counter), just
enough for a number to land somewhere. `TargetCount`/`Radius` are recorded on the context but
don't do anything spatial yet since there's only ever the one target; Chain "hitting nearby
enemies" and Explosion's radius becoming a real area query both need a real target/enemy model,
which is intentionally out of scope here (this is one perk-board prototype's effect layer, not
the combat system it'll eventually feed into). Linger, mechanically an `AreaPerkDefinition`
like Explosion, behaves identically to it for now — its damage-over-time behavior needs a
time-based update loop that doesn't exist anywhere in the codebase yet.
