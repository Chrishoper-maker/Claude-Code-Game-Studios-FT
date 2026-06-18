# ADR-0004: GDScript State Machine Pattern

## Status
Accepted

## Date
2026-06-18

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Core / Scripting (GDScript Patterns) |
| **Knowledge Risk** | LOW — `enum` and `match` are foundational GDScript features stable since Godot 4.0; no breaking changes in the Godot 4.4–4.6 changelog affect this pattern |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None — enum + match is standard GDScript; no runtime verification needed beyond normal testing |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (EventBus signals are emitted on state transitions); ADR-0002 (RunManager.current_phase public String interface already registered — this ADR implements the backing enum without breaking that contract) |
| **Enables** | All implementation stories for TurnManager, RunManager, and BattleMapSystem |
| **Blocks** | All TurnManager, RunManager, and BattleMapSystem implementation stories — coding cannot begin until the state machine pattern is established |
| **Ordering Note** | ADR-0002 has already registered RunManager.current_phase as a read-only String. This ADR defines the internal enum + String facade that satisfies that registry entry without modifying it. |

## Context

### Problem Statement

Three core systems maintain explicit state machines with defined transition rules:

1. **TurnManager** (`turn-management-system` GDD): 7-state battle state machine  
   SETUP → ROUND_START → ACTIVE_TURN → TURN_END → ROUND_END → BATTLE_WIN / BATTLE_LOSS
2. **RunManager** (`route-recruitment-system` GDD): 5-state run lifecycle  
   RUN_IDLE → RUN_DEPLOYING → RUN_ISLAND_BATTLE → RUN_RECRUITING → RUN_END
3. **BattleMapSystem** (`battle-map-system` GDD): 6-state map loading machine  
   MAP_UNLOADED → MAP_VALIDATING → MAP_LOADING → MAP_READY → MAP_ACTIVE → MAP_RESOLVED

Without a shared convention, each developer may implement state machines differently (strings, booleans, raw integers), making cross-system reasoning inconsistent and creating divergent guard patterns for terminal states and parameterized states.

### Constraints

- **GDScript only** — no C# or GDExtension; must use GDScript-native patterns
- **ADR-0002 contract** — `RunManager.current_phase` is registered as a read-only String interface; the implementation must preserve that public API while using an enum internally
- **ADR-0001 contract** — all state transition events are published via EventBus signals
- **Testability** — state machines must be testable with GUT (unit tests need to set and verify state directly)
- **Terminal state integrity** — BATTLE_WIN and BATTLE_LOSS must not be exitable (TurnManager AC-12)
- **Parameterized states** — ACTIVE_TURN carries an associated `unit_id` that must be accessible during that state

### Requirements

- Define `enum` types for BattleState, RunPhase, and MapState matching GDD state names exactly
- Provide a standard private `_set_[machine](new_state)` method with guard check as the sole transition entry point
- Handle parameterized states (states with associated data) through a companion variable + dedicated setter convention
- Emit EventBus signals on state entry per ADR-0001
- Expose `current_phase: String` on RunManager per ADR-0002 registry contract
- Use typed enum internally to catch state name typos at compile time

## Decision

### Pattern: `enum` + `match` inside Owning Class

Each state machine is implemented as a GDScript `enum` inside its owning class (autoload or scene node). State transitions are handled exclusively through a private `_set_[machine_name](new_state)` method that: (1) enforces terminal state guards, (2) updates the state variable, (3) delegates to an entry handler that emits EventBus signals.

### Enum Definitions

```gdscript
# src/autoloads/turn_manager.gd
enum BattleState {
    SETUP,
    ROUND_START,
    ACTIVE_TURN,   # current unit stored in _current_unit_id
    TURN_END,
    ROUND_END,
    BATTLE_WIN,    # terminal — no exit (AC-12)
    BATTLE_LOSS    # terminal — no exit (AC-12)
}
const BATTLE_TERMINAL_STATES: Array = [BattleState.BATTLE_WIN, BattleState.BATTLE_LOSS]
```

```gdscript
# src/autoloads/run_manager.gd
enum RunPhase {
    RUN_IDLE,
    RUN_DEPLOYING,
    RUN_ISLAND_BATTLE,
    RUN_RECRUITING,
    RUN_END
}
# ADR-0002 registry contract: current_phase is a read-only String
const _PHASE_TO_STRING: Dictionary = {
    RunPhase.RUN_IDLE:           "IDLE",
    RunPhase.RUN_DEPLOYING:      "DEPLOYING",
    RunPhase.RUN_ISLAND_BATTLE:  "BATTLE",
    RunPhase.RUN_RECRUITING:     "RECRUITING",
    RunPhase.RUN_END:            "RUN_END"
}
```

```gdscript
# BattleMapSystem (autoload or scene node — see ADR-0002)
enum MapState {
    MAP_UNLOADED,
    MAP_VALIDATING,
    MAP_LOADING,
    MAP_READY,
    MAP_ACTIVE,
    MAP_RESOLVED
}
```

### Standard Transition Pattern

```gdscript
# TurnManager — full pattern example
var _battle_state: BattleState = BattleState.SETUP
var _current_unit_id: int = -1  # state parameter; valid only when _battle_state == ACTIVE_TURN

func _set_battle_state(new_state: BattleState) -> void:
    if _battle_state in BATTLE_TERMINAL_STATES:
        push_warning("TurnManager: 终态 [%s] 不可转换至 [%s]" % [
            BattleState.keys()[_battle_state], BattleState.keys()[new_state]
        ])
        return
    _battle_state = new_state
    _on_battle_state_entered(new_state)

func _on_battle_state_entered(state: BattleState) -> void:
    match state:
        BattleState.ROUND_START:
            EventBus.round_started.emit(round_count)
        BattleState.ACTIVE_TURN:
            EventBus.unit_turn_started.emit(_current_unit_id)
        BattleState.ROUND_END:
            EventBus.round_ended.emit()
        BattleState.BATTLE_WIN:
            EventBus.battle_won.emit()
        BattleState.BATTLE_LOSS:
            EventBus.battle_lost.emit()
        _:
            pass  # SETUP, TURN_END handled by callers directly
```

### Parameterized State Handling

States with associated data (like `ACTIVE_TURN(unit_id)` from the GDD) use a dedicated
setter that sets the companion variable **before** calling `_set_battle_state`:

```gdscript
# Always set parameters BEFORE the state transition
func _begin_active_turn(unit_id: int) -> void:
    assert(unit_id >= 0, "TurnManager._begin_active_turn: invalid unit_id")
    _current_unit_id = unit_id
    _set_battle_state(BattleState.ACTIVE_TURN)

# Access guard — companion variable is only meaningful in ACTIVE_TURN
func get_current_unit_id() -> int:
    assert(_battle_state == BattleState.ACTIVE_TURN,
        "get_current_unit_id() called outside ACTIVE_TURN state")
    return _current_unit_id
```

### Public String Facade for RunManager (ADR-0002 Compatibility)

RunManager uses `RunPhase` enum internally but exposes `current_phase: String` as registered
in ADR-0002. A constant dictionary is the single source of truth for the mapping:

```gdscript
# src/autoloads/run_manager.gd
var _phase: RunPhase = RunPhase.RUN_IDLE

# ADR-0002 registry contract: read-only String property
var current_phase: String:
    get: return _PHASE_TO_STRING[_phase]

func _ready() -> void:
    # Mapping completeness guard — fires immediately if a new RunPhase lacks a String entry
    assert(_PHASE_TO_STRING.size() == RunPhase.size(),
        "RunManager: _PHASE_TO_STRING mapping is incomplete — update after adding a new RunPhase value")

func _set_run_phase(new_phase: RunPhase) -> void:
    _phase = new_phase
    _on_run_phase_entered(new_phase)

func _on_run_phase_entered(phase: RunPhase) -> void:
    match phase:
        RunPhase.RUN_DEPLOYING:
            EventBus.run_phase_changed.emit("DEPLOYING")
        RunPhase.RUN_ISLAND_BATTLE:
            EventBus.run_phase_changed.emit("BATTLE")
        RunPhase.RUN_RECRUITING:
            EventBus.run_phase_changed.emit("RECRUITING")
        RunPhase.RUN_END:
            EventBus.run_phase_changed.emit("RUN_END")
        RunPhase.RUN_IDLE:
            pass  # no signal for IDLE — no active run phase to announce
```

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                 State Machine Pattern Convention                     │
│                                                                     │
│  ┌──────────────────────┐   ┌──────────────────────────────────┐   │
│  │   Owning Class       │   │         EventBus                 │   │
│  │  ─────────────────── │   │  ──────────────────────────────  │   │
│  │  enum StateEnum { }  │   │  signal round_started(int)       │   │
│  │  var _state          │   │  signal unit_turn_started(int)   │   │
│  │  var _param          │   │  signal battle_won()             │   │
│  │                      │   │  signal battle_lost()            │   │
│  │  _set_state()        │   │  signal round_ended()            │   │
│  │   ├─ terminal guard  │   │  signal run_phase_changed(str)   │   │
│  │   ├─ update _state   │   └──────────────────────────────────┘   │
│  │   └─ _on_entered() ──┼──────────────────► emit on entry         │
│  └──────────────────────┘                                          │
│                                                                     │
│  TurnManager    enum BattleState { SETUP, ROUND_START, ACTIVE_TURN,│
│                   TURN_END, ROUND_END, BATTLE_WIN(*), BATTLE_LOSS(*)}│
│                 (*) terminal state — guarded against re-entry       │
│                                                                     │
│  RunManager     enum RunPhase { RUN_IDLE, RUN_DEPLOYING,           │
│                   RUN_ISLAND_BATTLE, RUN_RECRUITING, RUN_END }      │
│                 public: var current_phase: String (String facade)   │
│                                                                     │
│  BattleMap      enum MapState { MAP_UNLOADED, MAP_VALIDATING,      │
│  System           MAP_LOADING, MAP_READY, MAP_ACTIVE, MAP_RESOLVED }│
└─────────────────────────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
# ─── TurnManager public interface ─────────────────────────────────────────────
func get_battle_state() -> BattleState   # typed access for unit tests
func is_in_terminal_state() -> bool      # true if BATTLE_WIN or BATTLE_LOSS
func get_current_unit_id() -> int        # asserts: must be in ACTIVE_TURN

# ─── RunManager public interface (per ADR-0002 registry) ──────────────────────
var current_phase: String                # "IDLE" | "DEPLOYING" | "BATTLE" | "RECRUITING" | "RUN_END"
var current_island_index: int            # read-only int — independent non-state variable (ADR-0002)

# ─── BattleMapSystem public interface ─────────────────────────────────────────
func get_map_state() -> MapState         # typed access for unit tests
func is_map_ready() -> bool              # convenience: _map_state == MapState.MAP_READY
```

## Alternatives Considered

### Alternative 1: State Object Pattern (One Class per State)

- **Description**: Each state is a separate GDScript class (e.g., `BattleState_RoundStart`, `BattleState_ActiveTurn`) implementing a common protocol with `on_enter()`, `on_exit()`, and `handle_event()` methods. The owning class holds a reference to the current state object and delegates to it.
- **Pros**: Excellent separation of state-specific logic; each state class is independently testable; scales well when states have complex per-state behavior trees.
- **Cons**: 7 extra files per state machine (21 new files for 3 state machines). GDScript has no enforced interface types — the protocol is a convention, not a compiler guarantee. Most states in this project emit 1-2 signals and delegate to other systems; per-state classes would each be 3-5 lines of delegation boilerplate.
- **Rejection Reason**: Over-engineered for this project's state complexity. TurnManager, RunManager, and BattleMapSystem states don't contain logic — they sequence delegation to other systems (BattleResolution, GridBoard, UnitDataManager). The added file count and structural complexity yield no benefit here.

### Alternative 2: String Constants + if-else Chains

- **Description**: States stored as `const ROUND_START := "ROUND_START"` with transitions implemented as `if _state == ROUND_START: ...` chains.
- **Pros**: Human-readable debug output without `.keys()` lookup; no enum boilerplate.
- **Cons**: Typos (`ROUND_STRAT`) are valid at compile time — bugs appear only at runtime. `if-else` chains are less scannable than `match` for exhaustiveness. Violates Godot 4.x typed GDScript direction (static typing is idiomatic since 4.0).
- **Rejection Reason**: GDScript `enum` + `match` is the idiomatic Godot 4.x pattern. String constants provide no advantage over enums while sacrificing type safety.

### Alternative 3: Godot Node-Based State Machine

- **Description**: Each state is a child Node in the scene tree. The owning system holds a reference to `_current_state_node` and calls `current_state_node.enter()` / `exit()` on transitions.
- **Pros**: Visual in the editor; states can use `_process()` and `_physics_process()` naturally.
- **Cons**: TurnManager and RunManager are autoloads — attaching child Node state objects to an autoload is unusual and adds scene-tree overhead. GUT unit tests for Node-based state machines require scene instantiation scaffolding. AnimationTree's state machine (the only built-in one) is designed for animation blending, not game logic.
- **Rejection Reason**: These are logic state machines in autoloads. Node overhead adds no value; enum + match in an autoload is the correct abstraction level.

## Consequences

### Positive

- **Type safety** — GDScript compiler validates all enum values. Misspelled state names are compile errors, not runtime surprises.
- **Readable transition graph** — `match state:` in `_on_[machine]_entered()` enumerates every state entry in one place, making the full transition surface visible at a glance.
- **Testable** — Unit tests can call `_set_battle_state(BattleState.ACTIVE_TURN)` directly, or invoke `_on_battle_state_entered()` with a specific state to verify signal emission without triggering guards.
- **Consistent** — All three state machines follow the same idiom, reducing cognitive overhead when switching between TurnManager, RunManager, and BattleMapSystem implementations.
- **ADR-0002 compatible** — RunManager's public `current_phase: String` property is preserved via `_PHASE_TO_STRING` constant dictionary; zero performance cost (dictionary lookup is O(1)).
- **Terminal state safety** — `BATTLE_TERMINAL_STATES` guard in `_set_battle_state()` prevents re-entry into BATTLE_WIN / BATTLE_LOSS, satisfying AC-12 and AC-13 from the TurnManager GDD.

### Negative

- **Internal vs. public type mismatch for RunManager** — `_phase` is `RunPhase` internally but `current_phase` is `String` publicly. Developers must use `_phase` for internal comparisons and `current_phase` for outward-facing reads. This is a permanent two-surface API dictated by ADR-0002.
- **Parameterized state convention is implicit** — The requirement to set `_current_unit_id` before calling `_set_battle_state(ACTIVE_TURN)` is a convention enforced by `assert`, not by the GDScript type system. A direct call to `_set_battle_state` that skips `_begin_active_turn` would silently leave a stale `_current_unit_id`.

### Risks

| Risk | Mitigation |
|------|------------|
| Developer calls `_set_battle_state(ACTIVE_TURN)` without setting `_current_unit_id` first | `get_current_unit_id()` asserts `_battle_state == ACTIVE_TURN`; `_begin_active_turn()` asserts `unit_id >= 0`. Two assertion layers catch the mistake. |
| `_PHASE_TO_STRING` gets out of sync when a new `RunPhase` value is added | `_ready()` assertion: `_PHASE_TO_STRING.size() == RunPhase.size()` fires immediately on startup if the mapping is incomplete. |
| A new terminal BattleState is added without updating `BATTLE_TERMINAL_STATES` | Comment in the enum marks terminal values explicitly. Code review must verify any new terminal state is added to the constant. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `turn-management-system.md` | States and Transitions: 7 battle states (SETUP, ROUND_START, ACTIVE_TURN, TURN_END, ROUND_END, BATTLE_WIN, BATTLE_LOSS) | `BattleState` enum matches GDD state names exactly |
| `turn-management-system.md` | AC-12: 状态机合法路径——不可从终态回退 | `_set_battle_state()` terminal guard rejects any transition out of BATTLE_WIN or BATTLE_LOSS with `push_warning` |
| `turn-management-system.md` | AC-13: battle_won 仅发一次（即使多个 resolve_unit_downed 几乎同时到达） | Terminal state guard prevents BATTLE_WIN re-entry; `EventBus.battle_won` fires exactly once |
| `turn-management-system.md` | ACTIVE_TURN(unit_id) — state carries the acting unit's identity | Parameterized state pattern: `_current_unit_id` companion variable set via `_begin_active_turn(unit_id)` |
| `route-recruitment-system.md` | States and Transitions: 5 run lifecycle states | `RunPhase` enum matches GDD state names exactly (RUN_IDLE, RUN_DEPLOYING, RUN_ISLAND_BATTLE, RUN_RECRUITING, RUN_END) |
| `route-recruitment-system.md` | `run_phase_changed(phase: String)` emits "BATTLE" / "RECRUITING" / "DEPLOYING" / "RUN_END" | `_on_run_phase_entered()` match block emits the correct String value for each RunPhase enum entry |
| `battle-map-system.md` | States and Transitions: 6 map loading states | `MapState` enum matches GDD state names exactly (MAP_UNLOADED, MAP_VALIDATING, MAP_LOADING, MAP_READY, MAP_ACTIVE, MAP_RESOLVED) |
| `battle-map-system.md` | EC-9: MAP_ACTIVE 状态拒绝新加载请求 | `_set_map_state()` guard rejects MAP_VALIDATING transition when `_map_state == MapState.MAP_ACTIVE` |

## Performance Implications

- **CPU**: GDScript enum comparison is integer comparison — zero overhead versus string comparison. `match` compiles to a jump table for dense enums — O(1) regardless of state count.
- **Memory**: Three enums + three state variables + one dictionary constant (`_PHASE_TO_STRING`, 5 entries). Negligible (< 200 bytes total).
- **Load Time**: No impact.
- **Network**: N/A.

## Migration Plan

N/A — no existing state machine code in any of the three systems. This ADR establishes the initial pattern before implementation begins.

## Validation Criteria

1. **Terminal state guard**: `TurnManager` enters `BATTLE_WIN`; calling any subsequent `_set_battle_state()` leaves state at `BATTLE_WIN` and logs a `push_warning`. (Satisfies AC-12.)
2. **String facade**: `RunManager.current_phase` returns `"BATTLE"` when internal `_phase == RunPhase.RUN_ISLAND_BATTLE`. Returns `"DEPLOYING"` when `_phase == RunPhase.RUN_DEPLOYING`.
3. **Parameterized state**: Calling `_begin_active_turn(42)` sets `_current_unit_id = 42` then transitions to `BattleState.ACTIVE_TURN`; `get_current_unit_id()` returns `42`.
4. **Mapping completeness guard**: Adding a new `RunPhase` value without updating `_PHASE_TO_STRING` triggers the `_ready()` assertion on the first game launch.
5. **Signal emission**: Entering `BattleState.BATTLE_WIN` emits exactly one `EventBus.battle_won` signal, even if `_set_battle_state(BATTLE_WIN)` is called twice consecutively.

## Related Decisions

- [ADR-0001: EventBus Architecture](adr-0001-eventbus-architecture.md) — state transitions emit signals via `EventBus.signal_name.emit()`
- [ADR-0002: Scene Architecture](adr-0002-scene-architecture.md) — `RunManager.current_phase` String interface; `run_phase_changed` signal ownership
- [ADR-0003: Data Loading Strategy](adr-0003-data-loading-strategy.md) — state machines call `UnitDataManager` and `MapDataManager` during transitions
- `design/gdd/turn-management-system.md` — BattleState definitions, AC-12, AC-13
- `design/gdd/route-recruitment-system.md` — RunPhase definitions, run_phase_changed signal values
- `design/gdd/battle-map-system.md` — MapState definitions, EC-9
