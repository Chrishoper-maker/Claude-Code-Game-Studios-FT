# ADR-0005: Combat Resolution Architecture (BattleResolution)

## Status
Accepted

> **Acceptance basis**: Every decision in this ADR consolidates choices already
> ratified in `architecture.md` (Accepted — §142 interface table, §389
> BattleResolution block, §180-197 combat data flow) and
> `design/gdd/battle-resolution-system.md` (Approved — R1-R4 review rounds). This
> ADR introduces **no novel decision**; it formalizes and justifies the existing
> combat-resolution architecture so implementation stories have a single
> authoritative record. Independent `/architecture-review` remains valuable but
> is not a blocker for a consolidation ADR of LOW knowledge risk.

## Date
2026-06-19

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Gameplay / Combat (GDScript) |
| **Knowledge Risk** | LOW — uses `enum`, `match`, typed `Dictionary`, `StringName`; all foundational GDScript stable since 4.0, unaffected by the 4.4–4.6 changelog |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `architecture.md` §142/§180-197/§389, `design/gdd/battle-resolution-system.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None beyond unit tests (pure logic; no rendering/timing) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (EventBus signals + the documented direct-call exception below); ADR-0004 (enum + match pattern for `VerbType` and the `resolve` flow); GridBoard (geometry/AoE/line — implemented); TurnManager unit registry (`get_unit`/`mark_*`/`remove_from_alive`/alive lists — implemented); UnitInstance runtime class (`current_hp`/`is_alive`/action flags — implemented) |
| **Enables** | BattleResolution implementation story → AdjacencyBond (consumes `register_attack_modifier`) → EnemyAI (consumes `execute_attack`); unblocks BondGaugeBurst burst activation (Rule 5-6) |
| **Blocks** | AdjacencyBond and EnemyAI implementation stories — both call into BattleResolution's interface, which this ADR fixes |
| **Scope Note** | Focused on BattleResolution's internal architecture. The AdjacencyBond direct-call contract is recorded here only as part of BattleResolution's `register_attack_modifier` interface; AdjacencyBond's bond-matrix internals and EnemyAI's intent loop belong to their own ADRs/stories. |

## Context

### Problem Statement

`BattleResolution` is the combat math authority: it validates attacks, computes
damage, executes the six class verbs, applies/queries unit statuses, and runs the
unit-downed sequence. Multiple systems depend on a stable contract:
AdjacencyBond injects damage modifiers, EnemyAI executes attacks, BondGaugeBurst
charges from combat signals, BattleHUD reads results. Without a fixed
architecture, damage ordering, status lifecycle, and signal timing would diverge
across these consumers and produce non-deterministic combat.

### Constraints

- **GDScript only** — pure-logic Node, no C#/GDExtension, no physics.
- **ADR-0001 contract** — combat events publish via EventBus; the lone exception
  (modifier injection) must be explicitly justified, not silently introduced.
- **GDD locks** — damage formula (3-term additive), AURA independence from the
  modifier cap (R2), one-shot-kill exception (R4), 7-step downed sequence, and
  signal-ordering invariants are Approved and may not be re-litigated here.
- **Testability** — every formula and the downed sequence must be unit-testable
  with injected collaborators (no scene tree, no autoload coupling in tests).
- **Determinism** — no randomness; identical inputs yield identical outcomes.

### Requirements

- Fix the public interface: `is_valid_attack`, `execute_attack`, `execute_verb`,
  `register_attack_modifier`, `get_unit_status`, `apply_status`.
- Define `VerbType` enum and dispatch the six verb effects via `match`.
- Specify `pending_modifiers` and `unit_statuses` storage and lifecycle.
- Specify the damage pipeline with the AURA third term outside the cap.
- Specify `resolve_unit_downed` as the 7-step sequence with signal ordering.
- Designate BattleResolution as the sole mutator of `current_hp` and statuses.

## Decision

### D1 — Component shape & injected collaborators

BattleResolution is a stateful `Node` in BattleScene holding two dictionaries:
`unit_statuses` and `pending_modifiers`. Collaborators are **injected** (DI over
singletons, per coding-standards): `GridBoard` (adjacency, attack range, AoE,
piercing line, forced move, cell clearing) and `TurnManager` (`get_unit(battle_id)`,
`mark_has_*`, `remove_from_alive`, alive-list queries). UnitInstances are reached
via `turn_manager.get_unit(id)`. EventBus is used for signal emission.

**BattleResolution is the sole mutator of `current_hp` and `unit_statuses`.**
Action flags and the alive list are owned by TurnManager; BattleResolution calls
TurnManager's interface to mutate them. This keeps a single writer per piece of
mutable battle state.

### D2 — Damage pipeline (3-term additive)

```
modifier_sum = min(pending_modifiers.get(attacker_id, 0), MAX_MODIFIER_SUM)   # cap = 2
aura_bonus   = AURA_VALUE if get_unit_status(attacker_id, &"AURA_BONUS") else 0  # AURA_VALUE = 1
final_damage = attacker.base_damage + modifier_sum + aura_bonus
```

- `aura_bonus` is an **independent third term, NOT clamped by MAX_MODIFIER_SUM**
  (R2 lock). Normal attacks and 斩 both consume AURA_BONUS.
- The combination `3 + 2 + 1 = 6 = max_hp` (one-shot kill) is a permitted
  high-investment exception (R4), not a balance violation.
- A `GUARDED` target halves incoming damage (integer, `final_damage / 2`) and the
  GUARDED status is consumed by the hit (including 斩).
- Gunner normal-attack minimum range: `GUNNER_MIN_RANGE = 2` (manhattan ≥ 2);
  the 轰 verb is not range-limited.

### D3 — Verb dispatch (enum + match, consistent with ADR-0004)

```
enum VerbType { SLASH, CANNON, GUARD, HEAL, MOVE, AURA }
func execute_verb(unit_id, verb: VerbType, target_id):
    match verb:
        VerbType.SLASH:  _verb_slash(...)    # 斩：相邻 AoE，可受修正器
        VerbType.CANNON: _verb_cannon(...)   # 轰：穿透直线，不分阵营，emit cannon_executed
        VerbType.GUARD:  _verb_guard(...)    # 挡：apply GUARDED
        VerbType.HEAL:   _verb_heal(...)     # 愈：+3 HP 固定，可治满血(无溢出收益)
        VerbType.MOVE:   _verb_move(...)     # 移：强制位移 ≤2 格
        VerbType.AURA:   _verb_aura(...)     # 奏：相邻友方 +AURA_BONUS
```

One private method per verb keeps each effect independently readable and testable.
`target_id` is the primary target for targeted verbs (斩/轰/愈/移); for self/aoe
verbs (挡 on self, 奏 on adjacent allies) the method derives its own targets and
may ignore `target_id`.

### D4 — `pending_modifiers` storage & lifecycle

`pending_modifiers: Dictionary[int attacker_id → int accumulated_bonus]`. Populated
by `register_attack_modifier(attacker_id, bonus)` (see D5). Read once by
`execute_attack`/斩 (capped at MAX_MODIFIER_SUM), then **cleared for that attacker
at the end of the attack** — a per-attack buffer, never carried across attacks.
Also cleared for a unit in `resolve_unit_downed` step 5.

### D5 — `register_attack_modifier` direct-call exception (key architectural decision)

AdjacencyBond, on receiving `attack_initiated`, **calls
`BattleResolution.register_attack_modifier` directly** rather than emitting a
return signal. This is the **only sanctioned exception** to ADR-0001's
"all cross-system communication via EventBus" rule.

**Justification**: the modifier must be synchronously present *before*
`execute_attack` reads `pending_modifiers`. The ordering is
`attack_initiated → (AdjacencyBond registers) → execute_attack`. A signal
round-trip provides no cheap ordering guarantee that registration completes
before the read; a direct synchronous call does. The coupling is narrow
(one method, one direction, AdjacencyBond → BattleResolution) and documented in
both ADR-0001 and the control manifest as the explicit carve-out.

### D6 — `unit_statuses` storage & lifecycle

`unit_statuses: Dictionary[int unit_id → Dictionary[StringName → bool]]` holding
`&"GUARDED"` and `&"AURA_BONUS"`. Accessors `get_unit_status(id, status) -> bool`
and `apply_status(id, status)`. Lifecycle (GDD-locked):

- `GUARDED`: halves the next incoming hit's damage, consumed on hit (incl. 斩);
  any residual cleared at ROUND_END.
- `AURA_BONUS`: consumed by the holder's normal attack and 斩; **retained across
  rounds** (R2) — not cleared at ROUND_END.

### D7 — `resolve_unit_downed` 7-step sequence & invariants

When a unit's `current_hp` reaches 0:

1. `turn_manager.remove_from_alive(id)`
2. `instance.is_alive = false`
3. `instance.grid_position = sentinel` (`Vector2i(-1, -1)`)
4. `grid_board.remove_unit(id)` (clear board cell)
5. clear `pending_modifiers[id]`
6. clear `unit_statuses[id]`
7. `EventBus.unit_downed.emit(id)`

**Invariants**: (a) `unit_downed` must be emitted before `battle_won`
(TurnManager observes `unit_downed` to update the alive list, then decides
victory); (b) `is_valid_attack` must be called before `execute_attack` (caller
contract). Combat signals emitted via EventBus per ADR-0001: `attack_executed`,
`cannon_executed`, `damage_dealt`, `unit_downed`.

## Consequences

### Positive

- Single authoritative interface for all combat consumers; deterministic ordering.
- Single-writer discipline (current_hp/statuses here; flags/alive in TurnManager)
  prevents cross-system write races.
- Pure-logic + DI makes the entire system unit-testable without a scene tree.
- Per-verb private methods keep the six effects small and independently testable.

### Negative / Costs

- The `register_attack_modifier` direct call is a deliberate seam in the otherwise
  EventBus-decoupled architecture; it must stay narrow and remain documented or it
  invites further bypasses.
- BattleResolution accumulates several responsibilities (damage, verbs, statuses,
  downed). Mitigated by per-verb method extraction; if it grows further, verb
  effects could move to a dedicated module.

### Risks

- LOW. Pure GDScript, no post-cutoff APIs. The main risk is contract drift between
  this ADR and consumers (AdjacencyBond/EnemyAI), mitigated by the fixed interface
  and the invariant that `is_valid_attack` precedes `execute_attack`.

## Alternatives Considered

1. **Modifier injection via EventBus return signal** (no direct call) — Rejected:
   cannot cheaply guarantee the modifier is registered before `execute_attack`
   reads it; would require an explicit two-phase signal handshake, more complex
   than the narrow direct call.
2. **Stateless damage calculator (pure function)** — Rejected: GUARDED/AURA_BONUS
   statuses and pending_modifiers are inherently stateful per-unit; threading them
   through every call signature is noisier than a small stateful Node.
3. **Verb effects as a strategy/dispatch table of Callables** — Rejected for MVP:
   `match` on a `VerbType` enum is simpler, matches ADR-0004's established pattern,
   and the six verbs are fixed; a dispatch table adds indirection without benefit.

## Verification

- Unit tests cover: damage pipeline (base + capped modifier + independent aura),
  GUARDED halving + consumption, each verb effect, status lifecycle, and the
  7-step downed sequence with `unit_downed`-before-`battle_won` ordering.
- No runtime/engine verification required (pure logic).
