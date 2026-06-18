# ADR-0002: Scene Architecture

## Status
Accepted

## Date
2026-06-18

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Core / Scene Management |
| **Knowledge Risk** | LOW — `SceneTree.change_scene_to_packed()` 自 Godot 4.0 起稳定；4.6.3 无相关 breaking changes |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None（`change_scene_to_packed` 为 Godot 4.0 引入，与 4.6.3 完全兼容） |
| **Verification Required** | (1) 确认 `change_scene_to_packed` 的延迟执行语义：旧场景在当前帧结束前存活，新场景 `_ready()` 在下一帧执行 — **引擎专家已验证** ✓；(2) 确认 Autoload 上的 `@export var PackedScene` 在 Project Settings Inspector 中可持久赋值 — **引擎专家已验证** ✓；(3) 运行时加断言：`assert(battle_scene != null)` 防止 null 崩溃 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 — EventBus Architecture（须在此 ADR 实现前 Accept；SceneManager 通过 EventBus 订阅 `run_phase_changed`） |
| **Enables** | ADR-0003（Data Loading Strategy 需要确认 UnitDataManager / MapDataManager 是 autoload）、ADR-0004（State Machine Pattern 需要确认 TurnManager 在 BattleScene 内，RunManager 是 autoload） |
| **Blocks** | 所有 BattleScene / RouteScene 内节点的实现故事（须知道场景结构才能写 `_ready()`）；SceneManager 实现故事 |
| **Ordering Note** | EventBus 必须是 project.godot 的**第一条** autoload（ADR-0001 约束）；SceneManager 必须是**最后一条**（其余 autoload 须先于它就绪，因为 `goto_battle()` 触发后新场景节点的 `_ready()` 会立即访问其他 autoload） |

## Context

### Problem Statement

《孤帆棋海》的游戏流程横跨两个逻辑上独立的阶段——战斗（BattleScene）与航线招募（RouteScene）——以及若干必须在场景切换全程持久存活的系统（RunManager 保存 run 状态，UnitDataManager 缓存单位定义，EventBus 维持信号路由）。需要明确：(1) 使用哪种 Godot API 切换场景；(2) 哪些系统作为 autoload 存在于场景树外；(3) autoload 的初始化顺序；(4) 场景内 UI 层的层级分配；(5) 新加载场景如何获取当前 run 阶段状态。

### Constraints

- 场景切换必须确保 RunManager 的 run 状态（roster、island_index、_downed_this_run）完整保留
- BattleScene 每次战斗后须完全卸载并重新加载（`map_reset_requested` 信号触发后）
- RouteScene 在招募与部署阶段均使用，切换须尽量低延迟
- Autoload 节点必须早于任何场景节点的 `_ready()` 就绪
- `run_phase_changed` 信号的唯一发射方是 RunManager（route-recruitment-system GDD 契约）

### Requirements

- 支持 BattleScene ↔ RouteScene 双向切换，切换后原场景节点完全释放
- Run 状态必须在场景切换全程持久（无 run 数据丢失）
- 5 个 autoload 节点的注册顺序必须保证依赖链正确（EventBus 最先）
- 各 CanvasLayer 层级不得冲突（HUD=5、爆发演出=10、招募UI=20）
- 新加载的场景节点能在 `_ready()` 中获取当前 run 阶段并正确初始化

## Decision

**采用两个独立全屏场景（BattleScene.tscn + RouteScene.tscn）+ 5 个 Autoload 节点的架构。**

SceneManager autoload 封装 `SceneTree.change_scene_to_packed(PackedScene)` 调用，提供类型化接口 `goto_battle()` 和 `goto_route()`。`run_phase_changed` 信号**由 RunManager 在状态转换时发射**，SceneManager 订阅该信号以触发场景切换，或由 RunManager 在发射信号后直接调用 SceneManager 方法（见场景切换序列）。

### Autoload 注册顺序（project.godot [autoload] 节）

```
1. EventBus          → src/autoloads/event_bus.gd         （信号总线，必须最先）
2. UnitDataManager   → src/autoloads/unit_data_manager.gd （Resource 缓存）
3. MapDataManager    → src/autoloads/map_data_manager.gd  （地图 Resource 缓存）
4. RunManager        → src/autoloads/run_manager.gd       （run 状态机）
5. SceneManager      → src/autoloads/scene_manager.gd     （场景切换控制，必须最后）
```

### 场景结构

```
autoloads/（跨场景持久，不在 SceneTree 场景节点内）
├── EventBus
├── UnitDataManager
├── MapDataManager
├── RunManager
└── SceneManager

scenes/BattleScene.tscn（战斗阶段活跃）
├── GridBoard          (Node — 8×8 空间逻辑)
├── GridBoard3D        (Node3D — 视觉棋盘) ⚠️ ADR-0006
├── UnitRenderer       (Node3D — 单位 mesh) ⚠️ ADR-0007
├── TurnManager        (Node — 回合状态机)
├── BattleMap          (Node — 地图加载/校验)
├── BattleResolution   (Node — 战斗数学)
├── AdjacencyBond      (Node — 修正器注入)
├── BondGaugeBurst     (Node — 羁绊槽+爆发技)
├── EnemyAI            (Node — 意图计算)
├── CanvasLayer(5)  → BattleHUD.tscn
└── CanvasLayer(10) → BurstPresentation.tscn

scenes/RouteScene.tscn（航线/招募/部署阶段活跃）
└── CanvasLayer(20) → RouteRecruitUI.tscn
```

### 场景切换序列

```
# 战斗胜利 → 航线招募
TurnManager: battle_won.emit()
  → RunManager._on_battle_won():
      current_phase = "RECRUITING"
      EventBus.run_phase_changed.emit("RECRUITING")  ← RunManager 发射（GDD 契约）
      SceneManager.goto_route()                       ← RunManager 调用 SceneManager

SceneManager.goto_route():
    assert(route_scene != null, "SceneManager: route_scene 未在 Inspector 中赋值")
    get_tree().change_scene_to_packed(route_scene)
    # 注：run_phase_changed 已由 RunManager 发射，此处不重复发射

# Godot 延迟执行：当前帧结束后卸载 BattleScene，加载 RouteScene
RouteRecruitUI._ready():
    EventBus.run_phase_changed.connect(_on_run_phase_changed)
    _on_run_phase_changed(RunManager.current_phase)  ← 轮询初始状态（不依赖已过期的信号）

# ─────────────────────────────────────────────────────

# 部署确认 → 战斗
RunManager.confirm_deploy(selected_ids):
    current_island_index += 1
    current_phase = "BATTLE"
    EventBus.run_phase_changed.emit("BATTLE")        ← RunManager 发射
    SceneManager.goto_battle()                        ← RunManager 调用 SceneManager

SceneManager.goto_battle():
    assert(battle_scene != null, "SceneManager: battle_scene 未在 Inspector 中赋值")
    get_tree().change_scene_to_packed(battle_scene)

# Godot 延迟执行：当前帧结束后卸载 RouteScene，加载 BattleScene
BattleScene._ready():
    BattleMap.load_map(RunManager.current_island_index)  ← 读取 autoload 持久状态
```

### Key Interfaces（SceneManager）

```gdscript
class_name SceneManager extends Node

@export var battle_scene: PackedScene   # 在 Project Settings → Autoload Inspector 中赋值
@export var route_scene: PackedScene    # 同上

func goto_battle() -> void:
    assert(battle_scene != null, "SceneManager: battle_scene 未在 Inspector 中赋值")
    get_tree().change_scene_to_packed(battle_scene)
    # 注：run_phase_changed 已由调用方（RunManager）在此前发射，此处不发射

func goto_route() -> void:
    assert(route_scene != null, "SceneManager: route_scene 未在 Inspector 中赋值")
    get_tree().change_scene_to_packed(route_scene)
    # 注：run_phase_changed 已由调用方（RunManager）在此前发射，此处不发射
```

### CanvasLayer 层级分配

| 层级 | 用途 | 场景 |
|------|------|------|
| 5 | BattleHUD | BattleScene |
| 10 | BurstPresentation | BattleScene |
| 20 | RouteRecruitUI | RouteScene |

## Alternatives Considered

### Alternative 1: MasterScene + SubScene（持久根场景）

- **Description**: 一个永不卸载的 MasterScene 作为根节点，BattleScene 和 RouteScene 作为其子场景按需 add_child / remove_child
- **Pros**: 场景切换不触发完整 SceneTree 重建；共享根节点可直接持有跨场景节点
- **Cons**: MasterScene 必须了解所有子场景的生命周期；BattleScene 若不被完全卸载，上一场战斗的状态残留风险增大；Autoload 已能处理跨场景持久性，MasterScene 重复解决了同一问题
- **Rejection Reason**: 职责重叠（Autoload 已处理持久性）且增加场景重载复杂性

### Alternative 2: 单一大场景 + UI 显示切换

- **Description**: BattleScene 和 RouteScene 所有节点同时存在，通过 `visible = true/false` 切换显示
- **Pros**: 无场景切换开销；节点引用永久有效
- **Cons**: 两套系统常驻内存；BattleScene 每场战斗应完全重置——单一大场景无法简单实现
- **Rejection Reason**: 状态重置难以保证，内存占用不必要增加

### Alternative 3: SceneManager 在 goto_* 内发射 run_phase_changed

- **Description**: SceneManager.goto_route() 内部发射 `run_phase_changed("RECRUITING")`，RunManager 不发射
- **Pros**: 接口更简洁，RunManager 不需要直接依赖 SceneManager
- **Cons**: 违反 route-recruitment-system GDD 的信号所有权契约（run_phase_changed 归 RunManager 所有）；同一阶段信号由非状态持有者发射，破坏单一真实来源原则
- **Rejection Reason**: GDD sync 违规；RunManager 作为 run 状态机，应是 run_phase_changed 的唯一发射方

## Consequences

### Positive

- `change_scene_to_packed` 确保每次战斗后 BattleScene 节点完全释放，状态自然重置
- Autoload 模式与 ADR-0001（EventBus）高度一致；不增加新模式
- SceneManager 接口极简（2 个方法），易于测试和 mock
- 预加载 `PackedScene`（@export var）避免运行时 ResourceLoader.load() 延迟
- 信号发射方（RunManager）与状态持有方一致，符合单一真实来源原则

### Negative

- `change_scene_to_packed` 触发完整场景树重建，有约 1-3 帧过渡
- BattleScene 节点的 `_ready()` 必须通过 autoload 接口获取状态，不能用 export var 预设跨场景引用
- RunManager 持有对 SceneManager 的直接调用（`SceneManager.goto_battle()`），形成 autoload 间的直接依赖（不违反 forbidden_patterns，因为 forbidden 模式针对 @onready var 节点引用，autoload 全局访问不在其列）

### Risks

- **Autoload 初始化顺序错误**：若 SceneManager 不是最后一条 autoload，`goto_battle()` 调用时后续 autoload 可能尚未执行 `_ready()`。
  缓解：明确规定 SceneManager 为 autoload 列表最后一条；在 CI 中添加顺序断言测试。

- **@export PackedScene 未赋值崩溃**：`@export var` 若在 Inspector 中未赋值，`change_scene_to_packed(null)` 会导致运行时崩溃。
  缓解：`goto_battle()` / `goto_route()` 开头各加 `assert(x != null)` 防御断言（引擎专家建议，已纳入 Key Interfaces）。

- **新加载场景节点错过已发射的信号**：`change_scene_to_packed` 是延迟执行，新场景的 `_ready()` 在下一帧触发。`run_phase_changed` 信号在上一帧已发射，新场景节点（如 RouteRecruitUI）无法捕获它。
  缓解：所有在 `_ready()` 中订阅 `run_phase_changed` 的节点必须**同时调用 `_on_run_phase_changed(RunManager.current_phase)`** 进行初始化（状态轮询 + 信号订阅双轨模式）。此模式须写入实现故事的 AC。

- **`change_scene_to_packed` 帧延迟边界**：若在切换调用后、新场景加载前有代码尝试访问旧场景节点，可能出现已释放引用。
  缓解：`goto_battle()` / `goto_route()` 调用后不执行任何依赖旧场景节点的逻辑；若需要，使用 `await get_tree().process_frame` 延迟。

## GDD Requirements Addressed

| GDD 系统 | TR ID | 需求摘要 | 此 ADR 如何满足 |
|---------|-------|---------|--------------|
| turn-management-system.md | TR-TMS-001 | 战斗状态机必须有明确的初始化入口点 | TurnManager 在 BattleScene 内；BattleScene._ready() → BattleMap.load_map(RunManager.current_island_index) → TurnManager.start_battle() |
| route-recruitment-system.md | TR-RRS-001 | RunManager（run 状态机）必须跨战斗场景和航线场景持久存活 | RunManager 注册为 autoload（第 4 条），在 `change_scene_to_packed` 全程持久；roster / island_index / _downed_this_run 不存在于任何 Scene 节点内 |
| battle-map-system.md | TR-BMS-004 | 地图加载必须在战斗场景节点树就绪后才触发 | BattleMap 作为 BattleScene 内节点，其 `_ready()` 在整个 SceneTree 重建后执行；`load_map()` 在此时读取 `RunManager.current_island_index` 并调用，保证 GridBoard 等依赖系统已就绪 |

## Performance Implications

- **CPU**: `change_scene_to_packed` 触发 O(n) 节点释放+重建，BattleScene 约 12 个游戏节点——预计 <5ms，在战棋回合间歇不可感知
- **Memory**: 场景切换后原场景节点完全释放（GC 回收）；5 个 autoload 常驻约 <50 KB（纯逻辑节点，无 mesh/texture）
- **Load Time**: PackedScene 预加载（@export 在编辑器赋值）= 运行时零加载延迟
- **Network**: 不适用

## Migration Plan

初次实现：直接按此架构创建 `src/autoloads/` 目录，依序实现 5 个 autoload，再实现 BattleScene / RouteScene 骨架。无旧代码迁移需求（绿地项目）。

## Validation Criteria

1. 在 Godot 4.6.3 中验证：`goto_battle()` 调用后，新 BattleScene 的 `_ready()` 在**下一帧**执行（非当帧）
2. 验证 `RunManager.roster` 在 BattleScene → RouteScene → BattleScene 往返后数据完整
3. 验证 CanvasLayer 5/10/20 层级分配无渲染顺序冲突
4. 验证 autoload 初始化顺序：在任意场景节点的 `_ready()` 内 `EventBus` 可用（不空指针）
5. 验证 `RouteRecruitUI._ready()` 轮询 `RunManager.current_phase` 后 UI 状态正确初始化
6. 验证 `assert(battle_scene != null)` 在未赋值时在编辑器中产生可读错误而非静默崩溃

## Related Decisions

- ADR-0001: EventBus Architecture（所有跨系统信号通过 EventBus 路由）
- ADR-0003: Data Loading Strategy（UnitDataManager / MapDataManager 确认为 autoload）
- ADR-0004: GDScript State Machine Pattern（TurnManager / RunManager 状态机实现方式）
- ADR-0006: 3D Board Rendering（GridBoard3D 在 BattleScene 内的视觉实现）
- ADR-0007: Unit Rendering（UnitRenderer 在 BattleScene 内的实现）
