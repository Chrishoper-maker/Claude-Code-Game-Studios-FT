# ADR-0003: Data Loading Strategy

## Status
Accepted

## Date
2026-06-18

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Core / Scripting (Resource Management) |
| **Knowledge Risk** | MEDIUM — ResourceLoader.load() and DirAccess APIs stable since Godot 4.0; Resource system unchanged through 4.6. HIGH risk domains (rendering/UI/physics) are not involved. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | `DirAccess.open()` / `list_dir_begin()` / `get_next()` (stable since 4.0); `ResourceLoader.load()` (stable since 4.0); `Resource.duplicate_deep()` (4.5, NOT used — see Decision) |
| **Verification Required** | (1) Confirm `DirAccess.open("res://assets/data/units/")` correctly enumerates .tres files inside exported .pck builds. (2) Confirm `ResourceLoader.load()` returns `null` (not exception) for malformed .tres files in Godot 4.6.3. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (EventBus autoload must initialize before UnitDataManager), ADR-0002 (autoload order establishes UnitDataManager → MapDataManager → RunManager sequence) |
| **Enables** | ADR-0004 (GDScript State Machine Pattern — state machines in RunManager/TurnManager call UnitDataManager.get_unit() and MapDataManager.get_map()) |
| **Blocks** | All implementation stories for UnitDataManager, MapDataManager, battle load flow, and any system that reads unit or map data at runtime |
| **Ordering Note** | UnitDataManager must initialize before MapDataManager: map validation cross-checks EnemySlotDefinition.unit_definition_id against the loaded unit cache. Both must initialize before RunManager (per ADR-0002 autoload order). |

## Context

### Problem Statement

The game requires two categories of static external data before any battle can start:

1. **Unit definitions** — per the unit-data-system GDD, every combatant (crew and enemy) is defined by a static template (`UnitDefinition`). The GDD explicitly delegates the data carrier format decision to an architecture decision record (Open Question #4: `.tres` vs JSON).
2. **Map definitions** — per the battle-map-system GDD, every battle map is a `MapDefinition` resource loaded at battle start.

The data format (file type) and the loading mechanism (how autoloads discover and load these files) must be decided before any implementation story can begin.

### Constraints

- **Static game data**: Unit and map definitions are read-only at runtime. No runtime mutation of templates is permitted.
- **Fail-fast validation**: The GDD requires structural errors to terminate loading with `push_error()` and signal failure via an empty return array; balance warnings use `push_warning()` and continue.
- **Data-driven**: Adding a new unit or map must not require code changes. GDD principle: "设计师无需改代码即可增删单位与调整平衡".
- **Autoload ordering**: Per ADR-0002, autoload order is: EventBus → UnitDataManager → MapDataManager → RunManager → SceneManager. All data must be available by the time RunManager's `_ready()` fires.
- **Offline PC**: No network; no async loading concerns at MVP data volume.

### Requirements

- Must support `UnitDefinition` / `CrewDefinition` / `EnemyDefinition` inheritance hierarchy as defined in the unit-data-system GDD.
- Must support `MapDefinition` with nested `EnemySlotDefinition` sub-resources.
- Must cache loaded resources in a `Dictionary` keyed by `id` / `map_id` for O(1) lookup at runtime.
- Must expose `get_unit(id) → UnitDefinition` and `get_all_units() → Array[UnitDefinition]` on `UnitDataManager`.
- Must expose `get_map(map_id) → MapDefinition` and `get_maps_for_tier(tier) → Array[MapDefinition]` on `MapDataManager`.
- Validation error messages must match GDD-specified format: `"UnitData parse error: [path] — [detail]"` and `"UnitData validation error: [unit_id] — [field] — [detail]"`.

## Decision

### Data Format: Godot Custom Resource (`.tres`)

All game data types extend `Resource` with typed `@export` fields, stored as `.tres` files.

**Data class hierarchy:**

```gdscript
# res://src/data/unit_definition.gd
class_name UnitDefinition extends Resource

@export var id: String
@export var display_name: String
@export_enum("crew", "enemy") var faction: String
@export_enum("swordsman", "gunner", "bulwark", "medic", "navigator", "musician") var unit_class: String
@export var max_hp: int
@export var move_range: int
@export var attack_range: int
@export var base_damage: int
@export var bond_tags: Array[String]
@export var class_action_id: String  # "" means no class action (equivalent to null)
```

```gdscript
# res://src/data/crew_definition.gd
class_name CrewDefinition extends UnitDefinition

@export var title: String
@export var battle_cry: String
@export var persona_line: String
@export_enum("starting", "pool", "unlockable") var recruit_pool_tier: String
@export var portrait_id: String
@export var model_id: String
@export var named_pair_overrides: Array[NamedPairOverride]  # typed sub-resource array
```

```gdscript
# res://src/data/enemy_definition.gd
class_name EnemyDefinition extends UnitDefinition

@export_enum("MELEE", "RANGED", "GUARDIAN", "SWARMER") var behavior_type: String
@export var home_pos: Vector2i
@export var threat_tier: int
```

```gdscript
# res://src/data/map_definition.gd
class_name MapDefinition extends Resource

@export var map_id: String
@export var display_name: String
@export var terrain_data: Array[TerrainCell]      # typed sub-resource array
@export var deploy_zone: Array[Vector2i]
@export var enemy_roster: Array[EnemySlotDefinition]  # typed sub-resource array
@export var island_tier: int
@export var annotated_engagement_distance: Dictionary  # {min: int, max: int} — design annotation only
@export var map_scene_id: String                  # "" = null (MVP whitebox placeholder)
```

**Data file locations:**

```
res://assets/data/units/     ← all UnitDefinition / CrewDefinition / EnemyDefinition .tres files
res://assets/data/maps/      ← all MapDefinition .tres files
res://src/data/              ← all data class .gd scripts (path must be stable — .tres files store script path references)
```

### Loading Mechanism: Directory Scan at Autoload Startup

`UnitDataManager` and `MapDataManager` each scan their designated directory at `_ready()`, load every `.tres` file found via `ResourceLoader.load()`, validate all definitions, and cache results.

### UnitInstance Separation

`UnitDefinition` resources are **immutable templates** — they are never modified at runtime. All runtime mutable state (`current_hp`, `grid_position`, `has_moved`, `has_acted`, `has_used_verb`, `is_alive`) lives in a separate `UnitInstance` object (plain GDScript class, NOT a Resource). `UnitInstance` holds a read-only reference to its `UnitDefinition` template.

`Resource.duplicate_deep()` (added in Godot 4.5) is **not used** in this pattern: templates are read-only, so sharing them across all `UnitInstance` objects is safe and memory-efficient.

### Architecture Diagram

```
res://assets/data/units/
├── crew_azhan.tres         ← CrewDefinition
├── crew_meri.tres          ← CrewDefinition
├── enemy_melee_tier1.tres  ← EnemyDefinition
└── ...

res://assets/data/maps/
├── battle_map_001.tres     ← MapDefinition
└── ...

[Autoload startup sequence — per ADR-0002]
EventBus._ready()
    ↓
UnitDataManager._ready()
    ├── DirAccess.open("res://assets/data/units/")
    ├── ResourceLoader.load(path) × N files
    ├── _validate_all(): GDD fail-fast rules (duplicate id, enum check, etc.)
    │   ├── Structural error → push_error(), _all.clear(), is_loaded = false
    │   └── Balance warning → push_warning(), continue
    └── On success: populate _cache[def.id] = def, is_loaded = true
    ↓
MapDataManager._ready()
    ├── DirAccess.open("res://assets/data/maps/")
    ├── ResourceLoader.load(path) × N files
    ├── _validate_all(): validate EnemySlotDefinition.unit_definition_id via UnitDataManager.get_unit()
    └── On success: populate _cache[def.map_id] = def, _by_tier[tier].append(def)
    ↓
RunManager._ready()      ← can now safely call UnitDataManager.get_unit()
SceneManager._ready()
```

### Key Interfaces

```gdscript
# src/autoloads/unit_data_manager.gd
class_name UnitDataManager extends Node

const UNITS_DATA_PATH := "res://assets/data/units/"

var _cache: Dictionary = {}            # String id → UnitDefinition
var _all: Array[UnitDefinition] = []
var is_loaded: bool = false            # false if any structural error occurred

func _ready() -> void:
    _scan_and_load()

func get_unit(id: String) -> UnitDefinition:
    return _cache.get(id, null)        # null if id not found

func get_all_units() -> Array[UnitDefinition]:
    return _all if is_loaded else []   # empty array signals load failure to callers

func _scan_and_load() -> void:
    var dir := DirAccess.open(UNITS_DATA_PATH)
    if dir == null:
        push_error("UnitData parse error: %s — 目录无法打开" % UNITS_DATA_PATH)
        return
    dir.list_dir_begin()
    var fname := dir.get_next()
    while fname != "":
        if fname.ends_with(".tres"):
            var path := UNITS_DATA_PATH + fname
            var res := ResourceLoader.load(path)
            if res == null:
                push_error("UnitData parse error: %s — ResourceLoader 返回 null" % path)
            elif not (res is UnitDefinition):
                push_error("UnitData parse error: %s — 非 UnitDefinition 类型" % path)
            else:
                _all.append(res as UnitDefinition)
        fname = dir.get_next()
    _validate_all()

func _validate_all() -> void:
    var seen_ids: Dictionary = {}
    var has_error := false
    for def in _all:
        # Duplicate id check
        if def.id in seen_ids:
            push_error("UnitData validation error: %s — id — 重复 id" % def.id)
            has_error = true
        else:
            seen_ids[def.id] = true
        # Additional GDD validation rules implemented here (unit_class enum, etc.)
    if not has_error:
        for def in _all:
            _cache[def.id] = def
        is_loaded = true
    else:
        _all.clear()   # structural error → expose empty array via get_all_units()
```

```gdscript
# src/autoloads/map_data_manager.gd
class_name MapDataManager extends Node

const MAPS_DATA_PATH := "res://assets/data/maps/"

var _cache: Dictionary = {}            # String map_id → MapDefinition
var _by_tier: Dictionary = {}          # int island_tier → Array[MapDefinition]
var is_loaded: bool = false

func _ready() -> void:
    _scan_and_load()

func get_map(map_id: String) -> MapDefinition:
    return _cache.get(map_id, null)

func get_maps_for_tier(island_tier: int) -> Array[MapDefinition]:
    return _by_tier.get(island_tier, [] as Array[MapDefinition])
```

**Caller contract** — any system that calls `get_all_units()` before entering battle must check for the empty array case:

```gdscript
# 正确用法示例
var units := UnitDataManager.get_all_units()
if units.is_empty():
    push_error("UnitDataManager 加载失败，无法进入战斗")
    return
```

## Alternatives Considered

### Alternative 1: JSON files + FileAccess

- **Description**: Unit and map data stored as JSON; UnitDataManager parses via `FileAccess.open()` + `JSON.parse_string()` into Dictionaries.
- **Pros**: Human-readable outside Godot; portable to other engines; any text editor can author.
- **Cons**: No type safety — field type errors discovered at runtime, not at author time. Must write manual validation for every field. Reference validation (e.g., `class_action_id` points to valid behaviour) not possible until runtime. JSON parser adds boilerplate code per resource type.
- **Rejection Reason**: The GDD's fail-fast validation strategy (structural errors terminate loading with detailed field-level messages) is much harder to implement robustly without type safety. The Godot custom Resource system provides type checking, editor integration, and reference validation for free.

### Alternative 2: `@export var` Arrays (Inspector Assignment)

- **Description**: UnitDataManager and MapDataManager expose `@export var all_units: Array[UnitDefinition]` (etc.) and all resource references are manually assigned in the Godot Inspector, matching the pattern used by SceneManager in ADR-0002.
- **Pros**: Consistent with SceneManager pattern from ADR-0002. Editor validates all references at author time. No directory scanning code needed.
- **Cons**: Every new unit or map requires opening UnitDataManager.tscn/MapDataManager.tscn in the editor and dragging in the new .tres file. With 8+ crew members, multiple enemy types, and 5-8 maps (Vertical Slice target), Inspector maintenance cost is high. Violates GDD principle "无需改代码即可增删单位".
- **Rejection Reason**: Directory scan is more data-driven and scales without Inspector edits.

### Alternative 3: `preload()` with Hardcoded Paths

- **Description**: Each unit definition preloaded at the top of a file: `const CREW_AZHAN = preload("res://assets/data/units/crew_azhan.tres")`.
- **Pros**: Paths validated at editor import time.
- **Cons**: Requires code change to add or remove any unit. Fundamentally not data-driven.
- **Rejection Reason**: Directly contradicts the GDD data-driven principle.

### Alternative 4: `ResourceLoader.load_threaded()` (Async Loading)

- **Description**: Load .tres files asynchronously during a splash/loading screen using `ResourceLoader.load_threaded_request()`.
- **Pros**: No startup blocking; smooth loading screen.
- **Cons**: Significantly more complex implementation; requires a loading state machine; not needed at MVP data volume (< 50 files, estimated < 100ms synchronous load).
- **Rejection Reason**: Premature optimization. If startup load time becomes measurable in profiling, the loading mechanism can be migrated to async without changing the data format or cache API.

## Consequences

### Positive

- **Type-safe**: GDScript compiler and ResourceLoader catch field type mismatches; broken references visible in the Godot editor.
- **Fully data-driven**: Adding a unit or map = create a `.tres` file, drop in the designated directory. No code or Inspector changes.
- **Fail-fast**: Structural errors detected at startup (game launch). `get_all_units()` returns empty array → downstream refuses to start battle. Consistent with GDD validation contract.
- **Editor integration**: Godot Inspector can preview, edit, and validate `.tres` files. Broken sub-resource references appear as editor warnings.
- **Idiomatic Godot 4.x**: Custom Resource with typed `@export` fields is the recommended Godot pattern for game data.
- **Read-only template sharing**: `UnitDefinition` resources shared across multiple `UnitInstance` objects with zero copy cost. Memory footprint is minimal.

### Negative

- **Directory path is a string constant**: If `res://assets/data/units/` is renamed, the error is caught at runtime (startup), not at compile time.
- **`.tres` files not human-readable outside Godot**: Content is parseable text, but the format is Godot-specific and not convenient for external tools.
- **Script path coupling**: `.tres` files store the path of their associated `.gd` script. Moving or renaming a data class script breaks all `.tres` files of that type. Data class scripts in `res://src/data/` must be treated as stable paths.

### Risks

| Risk | Mitigation |
|------|-----------|
| `DirAccess` behavior in exported builds: Godot's .pck virtual filesystem may behave differently than editor filesystem for directory enumeration | Verify explicitly with an exported build during Pre-Production sprint 1. Add dedicated AC for export path validation. |
| Script path instability: moving a `.gd` data class breaks all associated `.tres` files | Treat `res://src/data/` as a stable-path zone. Any refactor that moves a data class must also re-save all associated `.tres` files. Document in control manifest. |
| Data volume growth: if unit/map count grows to hundreds, synchronous startup scan may cause measurable load time | Profile during Pre-Production. If scan time exceeds 200ms, introduce an explicit registry Resource listing all file paths (eliminates directory scan; files still loaded via ResourceLoader). |
| `.tres` format migration between Godot major versions | Engine version is pinned at 4.6.3. Resource format is stable within 4.x. Godot provides migration tooling if format changes on major version upgrade. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| `unit-data-system.md` | Open Question #4: 数据载体格式 `.tres` vs JSON | Resolved: `.tres` Custom Resource selected. |
| `unit-data-system.md` | "数值外置，使设计师无需改代码即可增删单位" | Directory scan: adding a `.tres` file to `res://assets/data/units/` is the only step required to add a new unit. |
| `unit-data-system.md` | `load_all_units() -> Array[UnitDefinition]` contract: structural errors return empty array + push_error(); balance warnings push_warning() + continue | `get_all_units()` returns `[]` when `is_loaded == false`; `_validate_all()` implements the two-tier error/warning strategy. |
| `unit-data-system.md` | Error message format: `"UnitData parse error: [path] — [detail]"` and `"UnitData validation error: [unit_id] — [field] — [detail]"` | Implemented directly in `_scan_and_load()` and `_validate_all()`. |
| `battle-map-system.md` | Rule 1: MapDefinition 静态数据资源，含地形、部署区、敌方编制 | `MapDefinition extends Resource` with typed `@export` fields for all Rule 1 fields. |
| `battle-map-system.md` | Rule 3 Step 1 ⑦: 所有 unit_definition_id 在 unit-data-system 中存在 | `MapDataManager._validate_all()` calls `UnitDataManager.get_unit(slot.unit_definition_id)` and fails if null. |

## Performance Implications

- **CPU**: Startup-only cost. All `.tres` loading and validation occurs in autoload `_ready()`. Zero per-frame overhead at runtime.
- **Memory**: All definitions cached for game lifetime. Estimated < 1 MB at MVP scale (< 50 unit definitions + < 20 map definitions, each ~5–10 KB as text .tres).
- **Load Time**: `ResourceLoader.load()` is synchronous. MVP data volume (< 50 files): estimated < 100 ms total. Acceptable for a non-streaming desktop title.
- **Network**: N/A.

## Migration Plan

N/A — no existing data loading code. This ADR establishes the initial pattern from scratch.

## Validation Criteria

1. `UnitDataManager.get_unit("crew_azhan")` returns a `CrewDefinition` with correct field values after game startup.
2. Dropping a new `.tres` file into `res://assets/data/units/` causes it to appear in `get_all_units()` on next launch — no code or Inspector changes required.
3. A `.tres` file with a duplicate `id` causes `get_all_units()` to return `[]` and `push_error()` to fire with a message matching the GDD format.
4. `MapDataManager.get_maps_for_tier(1)` returns all `MapDefinition` instances with `island_tier == 1`.
5. `DirAccess.open("res://assets/data/units/")` succeeds and correctly enumerates files in an exported PC build (manual verification during Pre-Production sprint 1).

## Related Decisions

- [ADR-0001: EventBus Architecture](adr-0001-eventbus-architecture.md) — autoload ordering context; EventBus must initialize before UnitDataManager
- [ADR-0002: Scene Architecture](adr-0002-scene-architecture.md) — establishes autoload order: UnitDataManager (position 2) and MapDataManager (position 3) before RunManager (position 4)
- [ADR-0004: GDScript State Machine Pattern](adr-0004-gdscript-state-machine-pattern.md) — state machines in RunManager and TurnManager call `UnitDataManager.get_unit()` and `MapDataManager.get_map()` at runtime
- `design/gdd/unit-data-system.md` — closes Open Question #4 (data carrier format)
- `design/gdd/battle-map-system.md` — MapDefinition loading contract
