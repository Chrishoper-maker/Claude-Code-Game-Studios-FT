# 孤帆棋海 (Grand Line Gambit) — Master Architecture

## Document Status

| Field | Value |
|-------|-------|
| **Version** | 1.0 |
| **Last Updated** | 2026-06-17 |
| **Engine** | Godot 4.6.3 / GDScript |
| **GDDs Covered** | unit-data, grid-board, turn-management, battle-resolution, adjacency-bond, bond-gauge-burst, enemy-ai-intent, burst-presentation, battle-hud, battle-map, route-recruitment-system, route-recruitment-ui (12 total) |
| **ADRs Referenced** | None (0 existing — 12 Required ADRs listed in §7) |
| **Technical Director Sign-Off** | 2026-06-17 — APPROVED WITH CONDITIONS (ADR-0001~0004 须在编码前 Accept) |
| **Lead Programmer Feasibility** | SKIPPED — Lean mode |

---

## 1. Engine Knowledge Gap Summary

**引擎版本**: Godot 4.6.3  
**LLM 训练数据涵盖至**: ~Godot 4.3  
**盲区版本**: 4.4（NEAR-CUTOFF）、4.5（HIGH）、4.6（HIGH）

### HIGH RISK 域（架构决策须人工交叉核对引擎参考文档）

| 域 | 关键变化 | 影响本项目的系统 |
|----|---------|----------------|
| **渲染 Rendering** | D3D12 默认（Windows）；Glow 在 tone mapping 前执行；SMAA 1x；Stencil Buffer 可用（4.5） | 爆发演出系统（#8）、战斗地图 3D 渲染（#10） |
| **GDScript** | `@abstract` 装饰器（4.5）；variadic args（4.5）；信号连接须 Callable 语法 | 所有系统的类定义 |
| **UI Focus（4.6）** | 鼠标焦点与键盘/手柄焦点分离（Dual-focus） | 战斗 HUD（#9）、招募 UI（#12）、部署界面 |
| **Animation/Tween + time_scale** | Tween 受 Engine.time_scale 影响；IK 系统恢复（SkeletonModifier3D） | 爆发演出系统（#8）⚠️ 待定 ADR-0008 |

### MEDIUM RISK 域

| 域 | 关键变化 | 影响 |
|----|---------|------|
| **Shader 纹理类型（4.4）** | uniform 从 `Texture2D` 改为 `Texture` | 爆发演出 2D 面板 shader |
| **FileAccess（4.4）** | `store_*` 方法返回 bool（不再 void）| 存档系统（Alpha 阶段，不影响 VS）|
| **Physics（4.6）** | Jolt 成为新项目默认 3D 物理引擎 | 本游戏物理使用极少，影响可忽略 |

### LOW RISK 域

Audio、Navigation（游戏用自写 BFS）、Input（动作 API 不变）、核心 Signal/Callable 模式。

---

## 2. System Layer Map

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  PRESENTATION LAYER                                                          │
│                                                                              │
│  BattleHUD (#9)              CanvasLayer=5   ⚠️ Dual-focus (4.6)            │
│  BurstPresentation (#8)      CanvasLayer=10  ⚠️ Tween+time_scale (ADR-0008) │
│  RouteRecruitUI (#12)        CanvasLayer=20                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│  FEATURE LAYER                                                               │
│                                                                              │
│  BattleResolution (#4)    — combat math, verb execution                      │
│  AdjacencyBond (#5)       — bond matrix lookup, modifier injection            │
│  BondGaugeBurst (#6)      — gauge tracking, burst dispatch                   │
│  EnemyAI (#7)             — intent computation (deterministic)               │
│  RouteRecruitment (#11)   — run state machine (autoload)                     │
├──────────────────────────────────────────────────────────────────────────────┤
│  CORE LAYER                                                                  │
│                                                                              │
│  UnitData (#1)    — data foundation (autoload cache)  ⚠️ schema bottleneck  │
│  GridBoard (#2)   — spatial operations (8×8 grid)                            │
│  TurnManager (#3) — turn/round state machine                                 │
│  BattleMap (#10)  — map loading + validation                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│  FOUNDATION LAYER (Autoloads — cross-scene persistent)                       │
│                                                                              │
│  EventBus        — named signal dispatcher (loose coupling)                  │
│  SceneManager    — BattleScene ↔ RouteScene transitions                      │
│  UnitDataManager — UnitDefinition Resource cache                             │
│  MapDataManager  — MapDefinition Resource cache                              │
│  RunManager      — route-recruitment-system (run state, roster, offers)      │
├──────────────────────────────────────────────────────────────────────────────┤
│  PLATFORM LAYER                                                              │
│  Godot 4.6.3 · GDScript · Forward+ rendering · D3D12 (Win) / Vulkan (Mac)   │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Scene Architecture

```
production/
└── autoloads (persistent across scene changes):
    ├── EventBus.gd          (Node — named signal hub)
    ├── UnitDataManager.gd   (Node — Resource cache)
    ├── MapDataManager.gd    (Node — Resource cache)
    ├── RunManager.gd        (Node — run state machine)
    └── SceneManager.gd      (Node — scene transition controller)

scenes/
├── BattleScene.tscn         (active during combat)
│   ├── GridBoard            (Node — 8×8 spatial logic)
│   ├── GridBoard3D          (Node3D — visual board) ⚠️ ADR-0006
│   ├── UnitRenderer         (Node3D — unit mesh management) ⚠️ ADR-0007
│   ├── TurnManager          (Node — turn state machine)
│   ├── BattleMap            (Node — map load/validate)
│   ├── BattleResolution     (Node — combat math)
│   ├── AdjacencyBond        (Node — modifier injection)
│   ├── BondGaugeBurst       (Node — gauge + burst)
│   ├── EnemyAI              (Node — intent computation)
│   ├── CanvasLayer (layer=5) → BattleHUD.tscn
│   └── CanvasLayer (layer=10) → BurstPresentation.tscn
└── RouteScene.tscn          (active during route/recruit/deploy)
    └── CanvasLayer (layer=20) → RouteRecruitUI.tscn
```

**场景切换流程**:
- `SceneManager.goto_battle(island_index)` → `SceneTree.change_scene_to_packed(BattleScene)` ⚠️ ADR-0002
- `SceneManager.goto_route()` → `SceneTree.change_scene_to_packed(RouteScene)` ⚠️ ADR-0002

---

## 3. Module Ownership Map

### Foundation Layer

| 模块 | Owns | Exposes | Consumes | 引擎 API | 风险 |
|------|------|---------|----------|---------|------|
| **EventBus** | 全局信号注册表 | `emit(name, args)` / `connect(name, callable)` | — | `Object.emit_signal` | LOW |
| **UnitDataManager** | UnitDefinition Resource 缓存 | `get_definition(id)` / `get_all_by_tier(tier)` | `.tres` 文件 | `ResourceLoader.load()` | LOW |
| **MapDataManager** | MapDefinition Resource 缓存 | `get_map(island_index)` | `.tres` 文件 | `ResourceLoader.load()` | LOW |
| **RunManager** | Run 状态机、roster[]、island_index、_downed_this_run | `get_roster()` / `get_recruit_offers()` / `confirm_recruit(id)` / `confirm_deploy(ids)` | UnitDataManager, EventBus | autoload Node | LOW |
| **SceneManager** | 当前活动场景引用 | `goto_battle(idx)` / `goto_route()` | — | `SceneTree.change_scene_to_packed()` ⚠️ | MED |

### Core Layer

| 模块 | Owns | Exposes | Consumes | 引擎 API | 风险 |
|------|------|---------|----------|---------|------|
| **GridBoard** | 格子状态矩阵 [8][8]、unit_pos_map | `get_cell(pos)` / `get_adjacents(pos)` / `get_reachable_cells(id, range)` / `in_attack_range(a,b,range)` / `place_unit(id,pos)` / `remove_unit(id)` / `forced_move_unit(id,dest)` / `grid_to_world(pos)` / `world_to_grid(world)` | — | 纯 GDScript | LOW |
| **TurnManager** | 战斗状态机、alive_list、initiative_queue、round_count、action bools | `mark_has_moved/acted/used_verb(id)` / `remove_from_alive(id)` / `get_alive_allies/enemies()` / `get_current_round()` | GridBoard, EventBus | 纯 GDScript | LOW |
| **BattleMap** | MapDefinition 当前实例、MAP_* 状态机 | `get_deploy_zone_available()` / `get_map_state()` | MapDataManager, GridBoard, UnitDataManager | `Resource` | LOW |

### Feature Layer

| 模块 | Owns | Exposes | Consumes | 引擎 API | 风险 |
|------|------|---------|----------|---------|------|
| **BattleResolution** | unit_statuses dict、pending_modifiers dict | `is_valid_attack(a,t)` / `execute_attack(a,t)` / `execute_verb(id,verb,t)` / `register_attack_modifier(id,bonus)` / `get_unit_status(id,status)` / `apply_status(id,status)` | GridBoard, TurnManager, UnitDataManager, EventBus | 纯 GDScript | LOW |
| **AdjacencyBond** | 羁绊矩阵常量（읽기 전용）| ← 无对外接口（订阅 `attack_initiated`，注入 modifier）| GridBoard, BattleResolution, UnitDataManager, EventBus | 纯 GDScript | LOW |
| **BondGaugeBurst** | bond_gauge_current、received_charge_this_round | `activate_burst(lead_id, partner_id)` / `get_gauge_value()` | UnitDataManager, GridBoard, TurnManager, EventBus | 纯 GDScript | LOW |
| **EnemyAI** | intent_map: dict[unit_id → IntentRecord] | ← 无对外接口（订阅 `round_started`，执行意图）| UnitDataManager, GridBoard, TurnManager, BattleResolution, EventBus | 纯 GDScript | LOW |

### Presentation Layer

| 模块 | Owns | Exposes | Consumes | 引擎 API | 风险 |
|------|------|---------|----------|---------|------|
| **BurstPresentation** | 演出状态机、Tween handles | ← 无对外接口（订阅 `burst_presentation_requested`）| EventBus | `Tween` ⚠️ / `Engine.time_scale` ⚠️ / `Camera3D` ⚠️ | **HIGH** |
| **BattleHUD** | — (纯显示，无持有状态) | `lock_input()` / `unlock_input()` | 所有战斗信号, EventBus | `CanvasLayer`, `Control`, `Camera3D.unproject_position()` ⚠️ | MED |
| **RouteRecruitUI** | — (纯显示，无持有状态) | ← 无对外接口（订阅 `run_phase_changed`，调用 RunManager）| RunManager, EventBus | `CanvasLayer=20`, `Control` | LOW |

### 依赖关系图（自上而下）

```
RouteRecruitUI ──────────────────────────────→ RunManager
BattleHUD ───────────→ [EventBus] ←────────── BurstPresentation
                            ↑
EnemyAI ─────────────────── │ ─────────────── BondGaugeBurst
AdjacencyBond ─────────────  │ ─────────────── BattleResolution
                            │
TurnManager ──────────────── │ ─────────────── BattleMap
GridBoard ─────────────────   │
                             │
UnitDataManager ─────────────┘
MapDataManager ──────────────┘

Foundation (autoloads): EventBus, UnitDataManager, MapDataManager, RunManager, SceneManager
```

---

## 4. Data Flow

### 4a 玩家普通攻击（核心战斗帧序列）

```
[PlayerInput] → 鼠标点击敌方格子
    → BattleHUD: 检查 input_locked == false
    → BattleResolution.is_valid_attack(attacker_id, target_id) → true
    → EventBus.attack_initiated.emit(attacker_id, target_id)
        ← AdjacencyBond 收到：
           get_adjacents(attacker_pos) → [neighbor_ids]
           for neighbor in neighbors:
               lookup bond_matrix[attacker.class][neighbor.class]
               → register_attack_modifier(attacker_id, BOND_BASE / BOND_ELITE)
    → BattleResolution.execute_attack(attacker_id, target_id)
        modifier_sum = min(pending_modifiers[attacker_id], MAX_MODIFIER_SUM=2)
        final_damage = base_damage + modifier_sum + aura_bonus
        target.current_hp -= final_damage
        → EventBus.attack_executed.emit(attacker_id, target_id, final_damage)
            ← BondGaugeBurst: 充能 (+2 adjacent / +1 solo)
            ← BattleHUD: 更新 HP 显示
        → if target.current_hp == 0:
            resolve_unit_downed(target_id) — 7 步序列
            → EventBus.unit_downed.emit(target_id)
                ← TurnManager: remove_from_alive(target_id)
                ← BattleHUD: 标记单位死亡
            → if alive_enemies.is_empty():
                → EventBus.battle_won.emit()
    → TurnManager.mark_has_acted(attacker_id)
    → EventBus.unit_turn_ended.emit(attacker_id)
```

**信号顺序契约**: `unit_downed` 必须在 `battle_won` 之前 dispatch（TR-TMS-006）。

### 4b 信号路由（EventBus 模式）

所有系统只认识 EventBus，不直接持有彼此引用：

```gdscript
# 系统在 _ready() 订阅信号（类型化 Signal，ADR-0001）
func _ready() -> void:
    EventBus.attack_executed.connect(_on_attack_executed)
    EventBus.round_started.connect(_on_round_started)

# 系统通过 EventBus 发射信号
EventBus.attack_executed.emit(attacker_id, target_id, final_damage)
```

**完整信号定义（见 ADR-0001 / src/autoloads/event_bus.gd）**:

```gdscript
# 战斗信号
signal attack_initiated(attacker_id: int, target_id: int)
signal attack_executed(attacker_id: int, target_id: int, damage: int)
signal damage_dealt(target_id: int, amount: int)
signal unit_downed(unit_id: int)
signal heal_executed(target_id: int, amount: int)
signal guard_applied(unit_id: int)
signal aura_performed(caster_id: int, target_id: int)
signal slash_executed(attacker_id: int, target_id: int)
signal cannon_executed(attacker_id: int, target_id: int, damage: int)
signal displacement_executed(unit_id: int, from_pos: Vector2i, to_pos: Vector2i)

# 回合信号
signal battle_started()
signal battle_won()
signal battle_lost()
signal round_started(round_count: int)      # GDD 概念名 "ROUND_START"，GDScript 约定 snake_case
signal unit_turn_started(unit_id: int)
signal unit_turn_ended(unit_id: int)
signal enemy_turn_started(unit_id: int)
signal enemy_actions_completed()
signal last_round_warning(round_count: int) # round_count == ROUND_LIMIT-1 时 emit
signal intent_declared(unit_id: int, intent: IntentRecord)

# 羁绊/爆发信号
signal gauge_charged(amount: int, new_total: int)
signal bond_gauge_full()
signal burst_executed(lead_id: int, partner_id: int)
signal burst_presentation_requested(lead_id: int, partner_id: int, effect_id: StringName)
signal burst_presentation_started()
signal burst_presentation_ended()

# Run 信号
signal run_phase_changed(phase: String)     # "BATTLE"/"RECRUITING"/"DEPLOYING"/"RUN_END"
signal crew_member_downed(unit_id: int)
signal run_completed(won: bool, island_index: int)
signal map_reset_requested()
signal map_load_failed(reason: StringName)
```

### 4c Run 状态机数据流

```
RunManager state: RUN_IDLE
  → run_started()
  → RUN_DEPLOYING
  → EventBus.run_phase_changed.emit("DEPLOYING")
      ← RouteRecruitUI: roster.size() ≤ DEPLOY_LIMIT(4)?
          YES → auto confirm_deploy (无 UI)
          NO  → DeployScreen 呈现
  → confirm_deploy(selected_ids) → RunManager 校验 → SceneManager.goto_battle(island_index)
      → BattleScene.tscn 加载 → BattleMap.load_map(island_index)
      → TurnManager.start_battle() → EventBus.battle_started.emit()
      → ... 战斗 ...
      → EventBus.battle_won.emit() 或 EventBus.battle_lost.emit()
  → SceneManager.goto_route()
  → battle_won + 非末岛: RUN_RECRUITING
  → battle_won + 末岛 (island_index == ISLAND_COUNT_MAX-1): RUN_END
  → battle_lost: RUN_END
  → RUN_RECRUITING → EventBus.run_phase_changed.emit("RECRUITING")
      ← RouteRecruitUI: get_recruit_offers() → 0?
          YES → UI_SKIPPED (auto proceed)
          NO  → RecruitScreen 呈现 3 张牌
      注: RUN_RECRUITING 状态始终进入，在状态内判断 skip（I-01 解决方案）
  → confirm_recruit(id) 或 skip → RUN_DEPLOYING → (循环)
  → RUN_END → EventBus.run_completed.emit(won, island_index)
```

### 4d 初始化顺序

```
1. Autoloads（Godot 按 project.godot 中列出顺序）:
   EventBus → UnitDataManager → MapDataManager → RunManager → SceneManager

2. BattleScene 场景树（_ready 调用顺序 = 节点树从上到下）:
   GridBoard → TurnManager → BattleMap → BattleResolution
   → AdjacencyBond → BondGaugeBurst → EnemyAI
   → BattleHUD (CanvasLayer=5) → BurstPresentation (CanvasLayer=10)

3. 所有系统在 _ready() 中向 EventBus 订阅信号

4. BattleMap._ready() 调用 load_map(island_index) → 校验 → 初始化 GridBoard 地形
   → TurnManager.start_battle() → EventBus.emit(&"battle_started")
```

---

## 5. API Boundaries

```gdscript
# ═══════════════════════════════════════════════════════
# FOUNDATION LAYER
# ═══════════════════════════════════════════════════════

## EventBus (autoload)  [ADR-0001]
## 在此 Node 上静态定义所有游戏信号（类型化 Signal）。
## 系统通过 EventBus.signal_name.connect(callable) 订阅；
## 通过 EventBus.signal_name.emit(args) 发射。
## 不持有游戏状态；只做路由。无需包装方法——直接使用 Godot Signal 对象。
## 完整信号定义见 src/autoloads/event_bus.gd 及 ADR-0001。

## UnitDataManager (autoload)
## 只读缓存。UnitDefinition 为 Resource (.tres)，不可在运行时修改。
## 运行时可变状态在 UnitInstance (RefCounted) 中维护，不在此模块。
func get_definition(unit_id: int) -> UnitDefinition   # null if not found
func get_all_by_tier(tier: int) -> Array[UnitDefinition]
func get_all_recruit_pool() -> Array[UnitDefinition]  # tier 1–3, alive=true 筛选

## MapDataManager (autoload)
func get_map(island_index: int) -> MapDefinition      # null if not found

## RunManager (autoload)
## 持有 run 状态。是 route-recruitment-system 的实现载体。
func get_roster() -> Array[int]                       # 当前 run 中的 unit_id 列表
func get_current_island_index() -> int
func get_recruit_offers() -> Array[int]               # R1 公式输出，≤ RECRUIT_OFFER_COUNT
func confirm_recruit(unit_id: int) -> void
func confirm_deploy(selected_ids: Array[int]) -> void # 校验 DEPLOY_LIMIT，触发 goto_battle

## SceneManager (autoload)
func goto_battle(island_index: int) -> void
func goto_route() -> void

# ═══════════════════════════════════════════════════════
# CORE LAYER
# ═══════════════════════════════════════════════════════

## GridBoard (Node in BattleScene)
## 纯逻辑，无渲染。坐标系：Vector2i(row, col)，[0,7]×[0,7]。
## 格子状态枚举：CellState { EMPTY, UNIT_OCCUPIED, TERRAIN_BLOCKED, COVER }

func get_cell(pos: Vector2i) -> CellState
func get_unit_at(pos: Vector2i) -> int                # -1 if empty
func get_adjacents(pos: Vector2i) -> Array[int]       # Chebyshev-1 邻居的 unit_ids
func get_reachable_cells(unit_id: int, move_range: int) -> Array[Vector2i]  # BFS 4向
func in_attack_range(from: Vector2i, to: Vector2i, range: int) -> bool      # Manhattan
func place_unit(unit_id: int, pos: Vector2i) -> bool  # false if occupied/blocked
func remove_unit(unit_id: int) -> void
func forced_move_unit(unit_id: int, dest: Vector2i) -> bool  # ignore occupation check
func get_deploy_zone() -> Array[Vector2i]             # 委托给 BattleMap.get_deploy_zone_available()
func grid_to_world(grid_pos: Vector2i) -> Vector3     # ⚠️ ADR-0005: grid_size 常量
func world_to_grid(world_pos: Vector3) -> Vector2i

## TurnManager (Node in BattleScene)
func start_battle() -> void                           # 初始化队列，emit battle_started
func mark_has_moved(unit_id: int) -> void
func mark_has_acted(unit_id: int) -> void
func mark_has_used_verb(unit_id: int) -> void
func remove_from_alive(unit_id: int) -> void          # 调用后检查胜负
func get_alive_allies() -> Array[int]
func get_alive_enemies() -> Array[int]
func get_current_round() -> int
func get_current_unit() -> int                        # 当前行动单位

## BattleMap (Node in BattleScene)
func load_map(island_index: int) -> void              # 触发 MAP_VALIDATING → MAP_LOADING → MAP_READY
func get_deploy_zone_available() -> Array[Vector2i]
func get_map_state() -> MapState                      # enum: MAP_UNLOADED/.../MAP_RESOLVED

# ═══════════════════════════════════════════════════════
# FEATURE LAYER
# ═══════════════════════════════════════════════════════

## BattleResolution (Node in BattleScene)
func is_valid_attack(attacker_id: int, target_id: int) -> bool
func execute_attack(attacker_id: int, target_id: int) -> void
func execute_verb(unit_id: int, verb: VerbType, target_id: int) -> void
func register_attack_modifier(attacker_id: int, bonus: int) -> void  # AdjacencyBond 专用
func get_unit_status(unit_id: int, status: StringName) -> bool       # &"GUARDED", &"AURA_BONUS"
func apply_status(unit_id: int, status: StringName) -> void
## 不变式: 调用 execute_attack 前必须先调用 is_valid_attack；
##         resolve_unit_downed 必须在 battle_won 之前 emit unit_downed。

## AdjacencyBond (Node in BattleScene)
## 无公开接口。_ready() 中订阅 EventBus.&"attack_initiated"。
## 内部: lookup bond_matrix → call BattleResolution.register_attack_modifier()

## BondGaugeBurst (Node in BattleScene)
func activate_burst(lead_id: int, partner_id: int) -> void  # 玩家按钮触发，BattleHUD 调用
func get_gauge_value() -> int                                # [0, BOND_GAUGE_MAX=10]
## 充能由 EventBus 信号驱动（attack_executed, cannon_executed, damage_dealt）。

## EnemyAI (Node in BattleScene)
## 无公开接口。订阅 EventBus.round_started，在敌方回合计算意图并 emit EventBus.intent_declared。
## 执行意图时调用 BattleResolution.execute_attack()。

# ═══════════════════════════════════════════════════════
# PRESENTATION LAYER
# ═══════════════════════════════════════════════════════

## BurstPresentation (CanvasLayer=10 in BattleScene)
## 无公开接口。订阅 &"burst_presentation_requested"。
## ⚠️ HIGH RISK: Engine.time_scale=0.05 in FREEZE phase — Tween 行为待 ADR-0008 确认。
## ⚠️ HIGH RISK: Camera3D local offset shake — 待 ADR-0009 确认。
## 5 阶段: FREEZE(60ms) → PANELS_IN → BURST_NAME → IMPACT(200ms) → PANELS_OUT

## BattleHUD (CanvasLayer=5 in BattleScene)
func lock_input() -> void    # 爆发演出期间由 burst_presentation_started 触发
func unlock_input() -> void  # burst_presentation_ended 触发
## 全部显示状态由 EventBus 信号驱动，不持有游戏数据副本。
## ⚠️ HIGH RISK: Dual-focus (4.6) — grab_focus() 只影响键盘焦点，鼠标焦点独立。

## RouteRecruitUI (CanvasLayer=20 in RouteScene)
## 无公开接口。订阅 &"run_phase_changed"，调用 RunManager.confirm_*。
```

### 关键常量（来自 entities.yaml）

```gdscript
const MAX_CREW: int = 8
const STARTING_CREW: int = 2
const DEPLOY_LIMIT: int = 4
const ROUND_LIMIT: int = 8
const ISLAND_COUNT_MAX: int = 5
const RECRUIT_OFFER_COUNT: int = 3
const BOND_GAUGE_MAX: int = 10
const MAX_MODIFIER_SUM: int = 2
const HEAL_AMOUNT: int = 3
const GUARD_DIVISOR: int = 2
const GUNNER_MIN_RANGE: int = 2
const PUSH_DISTANCE: int = 2
const AURA_VALUE: int = 1
const BOND_BASE: int = 1
const BOND_ELITE: int = 2
```

---

## 6. Data Architecture

### UnitDefinition（Resource .tres）

```gdscript
class_name UnitDefinition extends Resource

@export var unit_id: int
@export var unit_class: UnitClass  # enum: SWORDSMAN/GUNNER/PHYSICIAN/...
@export var display_name: String
@export var move_range: int
@export var attack_range: int      # 1=melee(Chebyshev), ≥2=ranged(Manhattan)
@export var base_damage: int
@export var max_hp: int
@export var action_weight: int     # initiative = move_range * 2 + action_weight
@export var recruit_pool_tier: int # 1-3
@export var faction: Faction       # enum: ALLY / ENEMY
@export var behavior_type: BehaviorType  # MELEE/RANGED/GUARDIAN/SWARMER (enemies)
```

### UnitInstance（RefCounted — 运行时可变状态）

```gdscript
class_name UnitInstance extends RefCounted

var unit_id: int
var definition: UnitDefinition  # 只读引用
var current_hp: int
var grid_position: Vector2i
var is_alive: bool
var has_moved: bool
var has_acted: bool
var has_used_verb: bool
var home_pos: Vector2i          # enemy spawn position (set by BattleMap)
var status_dict: Dictionary     # StringName → bool/int
```

### MapDefinition（Resource .tres）

```gdscript
class_name MapDefinition extends Resource

@export var map_scene_id: String         # null = white-box placeholder (MVP)
@export var island_tier: int             # 1-3 (difficulty tier)
@export var terrain_data: Array[Array]   # [row][col] → TerrainType enum
@export var deploy_zone: Array[Vector2i] # 玩家可部署的格子列表
@export var enemy_roster: Array[int]     # unit_ids (from UnitDataManager)
```

### IntentRecord（敌人意图 — 纯数据，无 Resource 需求）

```gdscript
class_name IntentRecord extends RefCounted

var unit_id: int
var action_type: IntentActionType  # MOVE_AND_ATTACK / MOVE_ONLY / GUARD / WAIT
var target_id: int                 # -1 if no target
var target_pos: Vector2i
var move_destination: Vector2i
var is_stale: bool                 # true if target died since declaration
```

---

## 7. ADR Audit

**现有 ADR 数量**: 0（docs/architecture/ 仅有空 tr-registry.yaml）

所有技术决策均未落档。以下为必需 ADR 完整列表。

---

## 8. Required ADRs

### Foundation 层（编码前必须创建并 Accept）

| # | 标题 | 覆盖 TR | 解锁 |
|---|------|--------|------|
| **ADR-0001** | EventBus Architecture（信号总线 vs 直连）| 所有信号 TR | 所有跨系统信号实现 |
| **ADR-0002** | Scene Architecture（BattleScene + RouteScene + 5 Autoloads）| TR-TMS-001, TR-RRS-001, TR-BMS-004 | SceneManager 实现 |
| **ADR-0003** | Data Loading Strategy（Custom Resource .tres for Unit/Map）| TR-UDS-001/002, TR-BMS-001 | UnitDataManager, MapDataManager |
| **ADR-0004** | GDScript State Machine Pattern（enum + match）| TR-TMS-001, TR-BMS-004, TR-RRS-001, TR-RRUI-003 | 所有状态机实现 |

### Core 层（Core 层实现前）

| # | 标题 | 覆盖 TR | 解锁 |
|---|------|--------|------|
| **ADR-0005** | Grid Coordinate System（Vector2i → Vector3 mapping，grid_size 常量）| TR-GBS-001/008 | GridBoard 3D 坐标 |
| **ADR-0006** | 3D Board Rendering（Camera3D overhead，Forward+，white-box mesh MVP）⚠️ HIGH RISK | TR-GBS-008, TR-BMS-005 | GridBoard 3D 视觉 |
| **ADR-0007** | Unit Rendering（CharacterBody3D vs StaticBody3D，placeholder mesh 策略）⚠️ HIGH RISK | TR-GBS-008, TR-BMS-005 | 战斗场景单位视觉 |

### Feature 层（对应系统实现前）

| # | 标题 | 覆盖 TR | 解锁 |
|---|------|--------|------|
| **ADR-0008** | Burst Presentation Timing（Tween + Engine.time_scale=0.05 交互方案）⚠️ HIGH RISK | TR-BPS-001/002/005 | 爆发演出实现 |
| **ADR-0009** | Camera Shake Implementation（Camera3D local offset vs Tween，unscaled 计时）⚠️ HIGH RISK | TR-BPS-006 | 爆发演出 IMPACT 阶段 |
| **ADR-0010** | Input Lock Architecture（全局 bool vs EventBus-driven lock）| TR-BPS-003, TR-BHS-006 | 爆发演出 + HUD 输入管理 |
| **ADR-0011** | Enemy Intent HUD Projection（Camera3D.unproject_position() 世界→屏幕坐标）⚠️ HIGH RISK | TR-BHS-003 | 敌人意图 HUD 渲染 |
| **ADR-0012** | Recruitment Randomization（randi_range，seed 策略，可复现性）| TR-RRS-004 | 招募系统实现 |

---

## 9. Technical Requirements Coverage

### TR Baseline — 68 项需求，按系统分组

| Req ID | 系统 | 摘要 | 架构覆盖 |
|--------|------|------|---------|
| TR-UDS-001 | 单位数据 | UnitDefinition 数据结构 | §5 UnitDefinition + ADR-0003 |
| TR-UDS-002 | 单位数据 | 外部资源加载（非硬编码）| §3 UnitDataManager + ADR-0003 |
| TR-UDS-003 | 单位数据 | UnitInstance 运行时可变副本 | §6 UnitInstance |
| TR-UDS-004 | 单位数据 | 加载时校验 | §3 UnitDataManager |
| TR-UDS-005 | 单位数据 | behavior_type + home_pos | §6 UnitInstance |
| TR-GBS-001 | 棋盘 | 8×8 grid, Vector2i | §5 GridBoard |
| TR-GBS-002 | 棋盘 | CellState enum | §5 GridBoard |
| TR-GBS-003 | 棋盘 | BFS 移动范围 | §5 GridBoard.get_reachable_cells() |
| TR-GBS-004 | 棋盘 | get_adjacents() Chebyshev-1 | §5 GridBoard |
| TR-GBS-005 | 棋盘 | Manhattan 攻击距离 | §5 GridBoard.in_attack_range() |
| TR-GBS-006 | 棋盘 | place/remove/forced_move 接口 | §5 GridBoard |
| TR-GBS-007 | 棋盘 | DEPLOY_LIMIT 校验 | §5 GridBoard / §3 TurnManager |
| TR-GBS-008 | 棋盘 | grid → 3D 坐标映射 | §5 GridBoard.grid_to_world() + ADR-0005/006 |
| TR-TMS-001 | 回合管理 | 战斗状态机 | §5 TurnManager + ADR-0004 |
| TR-TMS-002 | 回合管理 | 先攻队列排序 | §5 TurnManager |
| TR-TMS-003 | 回合管理 | 三行动 bool，ROUND_START 重置 | §5 TurnManager |
| TR-TMS-004 | 回合管理 | ROUND_LIMIT=8 失败 | §5 TurnManager |
| TR-TMS-005 | 回合管理 | 信号协议 | §4b 信号名单 |
| TR-TMS-006 | 回合管理 | unit_downed 先于 battle_won | §4a 信号顺序契约 |
| TR-TMS-007 | 回合管理 | alive_list 维护 | §5 TurnManager |
| TR-BRS-001 | 战斗解算 | is_valid_attack() | §5 BattleResolution |
| TR-BRS-002 | 战斗解算 | 六动词执行 | §5 BattleResolution.execute_verb() |
| TR-BRS-003 | 战斗解算 | register_attack_modifier() | §5 BattleResolution |
| TR-BRS-004 | 战斗解算 | unit_statuses + pending_modifiers | §5 BattleResolution |
| TR-BRS-005 | 战斗解算 | resolve_unit_downed 7 步 | §4a 数据流 |
| TR-BRS-006 | 战斗解算 | 战斗信号 | §4b 信号名单 |
| TR-BRS-007 | 战斗解算 | MAX_MODIFIER_SUM=2 截断 | §5 常量 |
| TR-ABS-001 | 相邻羁绊 | 6×6 矩阵查表 | §3 AdjacencyBond |
| TR-ABS-002 | 相邻羁绊 | ALLY 普通攻击/斩触发 | §5 AdjacencyBond |
| TR-ABS-003 | 相邻羁绊 | attack_initiated 前注入 modifier | §4a + §4b 信号顺序 |
| TR-ABS-004 | 相邻羁绊 | 使用 get_adjacents() | §5 AdjacencyBond |
| TR-BGBS-001 | 羁绊槽 | 共享槽 [0,10] | §5 BondGaugeBurst |
| TR-BGBS-002 | 羁绊槽 | 充能源计算 | §5 BondGaugeBurst |
| TR-BGBS-003 | 羁绊槽 | 爆发激活条件 | §5 BondGaugeBurst.activate_burst() |
| TR-BGBS-004 | 羁绊槽 | BURST_EFFECT_TABLE 查表 | §3 BondGaugeBurst |
| TR-BGBS-005 | 羁绊槽 | 爆发信号 | §4b 信号名单 |
| TR-EAIS-001 | 敌人 AI | 4 行为原型 | §3 EnemyAI + §6 UnitInstance.behavior_type |
| TR-EAIS-002 | 敌人 AI | ROUND_START 意图声明 | §5 EnemyAI + §4b |
| TR-EAIS-003 | 敌人 AI | stale intent 重算 | §6 IntentRecord.is_stale |
| TR-EAIS-004 | 敌人 AI | 确定性，unit_id tiebreak | §3 EnemyAI |
| TR-EAIS-005 | 敌人 AI | MVP 不用动词 | §3 EnemyAI |
| TR-BPS-001 | 爆发演出 | 5 阶段时序 | §5 BurstPresentation |
| TR-BPS-002 | 爆发演出 | Engine.time_scale=0.05 | §5 BurstPresentation ⚠️ ADR-0008 |
| TR-BPS-003 | 爆发演出 | 输入锁信号 | §5 BattleHUD + ADR-0010 |
| TR-BPS-004 | 爆发演出 | CanvasLayer=10 | §2 Scene Architecture |
| TR-BPS-005 | 爆发演出 | Skip 路径 | §5 BurstPresentation |
| TR-BPS-006 | 爆发演出 | Camera shake | §5 BurstPresentation ⚠️ ADR-0009 |
| TR-BHS-001 | 战斗 HUD | CanvasLayer=5 | §2 Scene Architecture |
| TR-BHS-002 | 战斗 HUD | 单位行动指示器 | §5 BattleHUD |
| TR-BHS-003 | 战斗 HUD | 敌方意图 HUD 投影 | §5 BattleHUD ⚠️ ADR-0011 |
| TR-BHS-004 | 战斗 HUD | 羁绊槽进度条 | §5 BattleHUD |
| TR-BHS-005 | 战斗 HUD | 轮次计数 | §5 BattleHUD |
| TR-BHS-006 | 战斗 HUD | 爆发期间输入锁 | §5 BattleHUD + ADR-0010 |
| TR-BMS-001 | 战斗地图 | MapDefinition Resource | §6 MapDefinition |
| TR-BMS-002 | 战斗地图 | 6 约束校验 | §5 BattleMap |
| TR-BMS-003 | 战斗地图 | get_deploy_zone_available() | §5 BattleMap |
| TR-BMS-004 | 战斗地图 | MAP_* 状态机 | §5 BattleMap + ADR-0004 |
| TR-BMS-005 | 战斗地图 | null scene_id → white-box | §5 BattleMap ⚠️ ADR-0006 |
| TR-RRS-001 | 航线招募 | Run 状态机 | §4c + RunManager + ADR-0004 |
| TR-RRS-002 | 航线招募 | _downed_this_run | §3 RunManager |
| TR-RRS-003 | 航线招募 | MAX_CREW=8 校验 | §3 RunManager |
| TR-RRS-004 | 航线招募 | get_recruit_offers() R1 | §5 RunManager + ADR-0012 |
| TR-RRS-005 | 航线招募 | Run 信号 | §4b 信号名单 |
| TR-RRUI-001 | 招募 UI | CanvasLayer=20 | §2 Scene Architecture |
| TR-RRUI-002 | 招募 UI | 三界面 | §3 RouteRecruitUI |
| TR-RRUI-003 | 招募 UI | UI_* 状态机 | §3 RouteRecruitUI + ADR-0004 |
| TR-RRUI-004 | 招募 UI | auto confirm_deploy | §4c 数据流 |
| TR-RRUI-005 | 招募 UI | 岛屿进度条 | §3 RouteRecruitUI |

**覆盖率**: 68/68 — 全部技术需求在架构中有对应节和/或指向 ADR。

---

## 10. Architecture Principles

1. **EventBus 单一信号路由**：所有跨系统通信通过 EventBus 流经，不在系统间建立直接 `@onready` 引用。任何新系统加入只需订阅 EventBus，不修改其他系统。

2. **数据在 Resource 中，状态在 RefCounted 中**：不可变定义（单位属性、地图布局）使用 Custom Resource `.tres` 文件存储；运行时可变状态（血量、位置、行动 bool）放在 `UnitInstance` 等 `RefCounted` 对象中，避免修改 Resource 对象。

3. **HIGH RISK 引擎域须有对应 ADR**：凡涉及 Godot 4.4+ 引入的变化（Tween+time_scale、D3D12 渲染、Dual-focus UI、Shader Texture 类型）的系统，必须在实现前创建并 Accept 对应 ADR，ADR 中包含 Engine Compatibility 节并人工核对引擎参考文档。

4. **格子逻辑与渲染分离**：`GridBoard` 持有纯逻辑格子状态；`GridBoard3D`/`UnitRenderer` 持有渲染。格子坐标转换封装在 `GridBoard.grid_to_world()` 和 `world_to_grid()` 中，其余系统不计算坐标。

5. **Presentation 层不持有游戏状态**：`BattleHUD`、`BurstPresentation`、`RouteRecruitUI` 均为纯显示节点，所有状态从 EventBus 信号读取，不在 Presentation 层维护副本。

---

## 11. Open Questions

| QQ-ID | 摘要 | 优先级 | 解决路径 |
|-------|------|--------|---------|
| QQ-01 | Tween + Engine.time_scale=0.05：演出帧如何计时（PROCESS_MODE_ALWAYS / 手动 Time.get_ticks_msec）| HIGH | ADR-0008 |
| QQ-02 | Camera3D shake：shake 是否应绑定到 Camera 局部偏移，还是用 SubViewport 或 ScreenShake compositor effect | HIGH | ADR-0009 |
| QQ-03 | 敌人意图箭头：使用 `Camera3D.unproject_position()` 还是 Label3D + billboard | MED | ADR-0011 |
| QQ-04 | SceneManager 切换时，BattleScene 内的节点 _exit_tree → BondGaugeBurst 槽值如何跨场景保留 | MED | ADR-0002（运行时状态策略）|
| QQ-05 | RUN_RECRUITING skip 路径：RunManager 是始终进入 RUN_RECRUITING 状态再跳过，还是直接跳 RUN_DEPLOYING | LOW | ADR-0002 / 实现决策（建议：始终进入，I-01 解决方案）|

---

*文档结束*
