# ADR-0001: EventBus Architecture

## Status
Accepted

## Date
2026-06-17（2026-06-18 修订：信号签名修正 8 处 + 补入 4 个缺失信号，依据架构评审 BLOCKER-1/BLOCKER-2）

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Core / GDScript Signals |
| **Knowledge Risk** | LOW — Signal.connect(Callable) pattern stable since Godot 4.0, in training data |
| **References Consulted** | `docs/engine-reference/godot/deprecated-apis.md`, `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Confirm EventBus is first entry in project.godot `[autoload]` section; verify signal.connect(callable) syntax works in Godot 4.6.3 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0002 (SceneManager emits run_phase_changed through EventBus), ADR-0004 (state machines emit/subscribe through EventBus), ADR-0008 (BurstPresentation subscribes to burst_presentation_requested) |
| **Blocks** | All 12 system implementations (each system's `_ready()` must register signals; EventBus must be ready first) |
| **Ordering Note** | EventBus must be the first autoload in project.godot to ensure it is ready before any scene node's `_ready()` fires |

## Context

### Problem Statement

《孤帆棋海》的 12 个游戏系统需要跨层通信（战斗解算→羁绊槽、AI→HUD、爆发技→演出等）。
直接节点引用会将 Presentation 层与 Core 层耦合，产生跨层循环依赖，
并在场景重载时因节点引用失效而崩溃。需要一个统一的信号路由模式。

### Constraints

- 所有系统在同一场景树中共存（BattleScene）或跨场景（autoload）
- Presentation 层（BattleHUD、BurstPresentation）不应持有 Core 层节点的 `@onready var` 引用
- 游戏无网络层，所有通信在本地进程内
- 必须与 Godot 4.6.3 的原生 Signal 系统集成（不引入第三方库）

### Requirements

- 任意两个系统可以通信，无需直接引用对方的节点
- 信号参数必须带类型注解（编译期检查，IDE 自动补全）
- 场景卸载时信号连接必须能安全清理（不产生悬空回调）
- 所有游戏信号必须有单一真实来源（防止分散定义和名称拼写错误）

## Decision

**采用单一 `EventBus` autoload Node**，在其上静态定义所有游戏信号（带类型参数）。
所有系统在 `_ready()` 中通过 `EventBus.signal_name.connect(callable)` 订阅；
通过 `EventBus.signal_name.emit(args)` 发射。系统之间不持有对方的 `@onready var` 引用。

### EventBus.gd 结构

文件路径：`src/autoloads/event_bus.gd`  
Autoload 注册名：`EventBus`（project.godot 第一条 autoload）

```gdscript
extends Node

# ── 战斗信号 ──
signal attack_initiated(attacker_id: String, verb: String)          # ★ verb 用于 AdjacencyBond 过滤触发条件
signal attack_executed(attacker_id: int, target_id: int, damage: int)
signal damage_dealt(target_id: int, final_damage: int, new_hp: int) # ★ 含后处理后伤害与残余 HP
signal unit_downed(unit_id: int)
signal heal_executed(target_id: int, amount: int)
signal guard_applied(unit_id: int)
signal aura_performed(caster_id: String, buffed_ids: Array[int], aura_value: int) # ★ 支持群体光环
signal slash_executed(attacker_id: String, target_ids: Array[int], pre_guard_damage: int) # ★ 支持多目标斩击
signal cannon_executed(attacker_id: String, direction: int, hit_target_ids: Array[int], base_fire_damage: int) # ★ 方向+命中列表
signal displacement_executed(unit_id: int, from_pos: Vector2i, to_pos: Vector2i)
signal unit_moved(unit_id: int, from_pos: Vector2i, to_pos: Vector2i) # ★ 主动移动（HUD 行动点 pip）
signal terrain_changed(pos: Vector2i, type: String)                 # ★ 地形变化（视觉系统响应）

# ── 回合信号 ──
signal battle_started()
signal battle_won()
signal battle_lost()
signal round_started(round_count: int)
signal round_ended()                                                 # ★ 轮末结算（羁绊充能 / 受击计数重置）
signal unit_turn_started(unit_id: int)
signal unit_turn_ended(unit_id: int)
signal enemy_turn_started(unit_id: int)
signal enemy_actions_completed(unit_id: int)                        # ★ TurnManager 需知哪个敌人完成行动
signal last_round_warning(round_count: int)
signal intent_declared(unit_id: int, intent: IntentRecord)

# ── 羁绊/爆发信号 ──
signal gauge_charged(attacker_id: String, charge_amount: int, bond_gauge_current: int) # ★ HUD 动画需知攻击者
signal bond_gauge_full()
signal burst_executed(lead_id: int, partner_id: int)
signal burst_presentation_requested(lead_id: int, partner_id: int, effect_id: StringName)
signal burst_presentation_started()
signal burst_presentation_ended()

# ── Run 信号 ──
signal run_phase_changed(phase: String)
signal crew_member_downed(unit_id: int)
signal run_completed(won: bool, island_count: int, roster_snapshot: Array) # ★ MetaProgression 需要花名册快照
signal map_loaded(map_id: String)                                    # ★ 航线招募系统等待此信号再触发战斗
signal map_reset_requested()
signal map_load_failed(reason: StringName)
```

### 系统使用模式

```gdscript
# ── 订阅（在任意系统的 _ready() 中）──
func _ready() -> void:
    EventBus.attack_executed.connect(_on_attack_executed)
    EventBus.round_started.connect(_on_round_started)

func _on_attack_executed(attacker_id: int, target_id: int, damage: int) -> void:
    # 处理逻辑
    pass

# ── 发射（在任意系统中）──
EventBus.attack_executed.emit(attacker_id, target_id, final_damage)
EventBus.unit_downed.emit(target_id)

# ── 场景切换时断开（可选——Godot 4 在 Node.free() 时自动断开）──
func _exit_tree() -> void:
    EventBus.attack_executed.disconnect(_on_attack_executed)
```

### 允许的直连例外

**AdjacencyBond → BattleResolution.register_attack_modifier()** 是唯一允许的直接跨系统调用。
这是单向功能注入（AdjacencyBond 写入 BattleResolution 的修正器队列），
不构成循环依赖（BattleResolution 不持有 AdjacencyBond 的任何引用）。
此例外须在 AdjacencyBond 的实现文档中明确标注。

### Architecture Diagram

```
所有系统通过 EventBus 通信，不持有彼此 @onready 引用：

BattleResolution ──emit──▶ EventBus.attack_executed ──▶ BondGaugeBurst._on_attack_executed()
                                                     ──▶ BattleHUD._on_attack_executed()

AdjacencyBond ──subscribe──▶ EventBus.attack_initiated
              ──call──▶ BattleResolution.register_attack_modifier()  [唯一直连例外]

BurstPresentation ──subscribe──▶ EventBus.burst_presentation_requested
TurnManager ──emit──▶ EventBus.round_started ──▶ EnemyAI._on_round_started()
                                              ──▶ BondGaugeBurst._on_round_started()
                                              ──▶ BattleHUD._on_round_started()

禁止模式：
  BurstPresentation ─✗─▶ BondGaugeBurst (直接 @onready var)
  BattleHUD ─✗─▶ TurnManager (直接 @onready var)
  任何 Presentation 层 ─✗─▶ 任何 Core/Feature 层节点（EventBus 除外）
```

## Alternatives Considered

### Alternative 1: 直连信号（Direct Signal Connections）

- **Description**: 每个系统暴露自己的 signal；其他系统用 `@onready var` 持有引用后 `.connect()`
- **Pros**: 无 autoload 开销；信号路径可在节点树中直接追踪
- **Cons**: 12 个系统产生至少 6 条跨层引用，其中 4 条形成潜在循环依赖；BattleScene 重载时 `@onready var` 引用失效；Presentation 层需持有 Core 层节点引用（违反层级约定）
- **Rejection Reason**: 循环依赖和跨层耦合不可接受

### Alternative 2: 动态 EventBus（add_user_signal + emit_signal by StringName）

- **Description**: EventBus 不预定义信号；系统运行时调用 `add_user_signal()` 注册，`emit_signal(name, ...)` 发射
- **Pros**: 灵活，新信号无需修改 EventBus.gd
- **Cons**: 无类型检查（StringName 拼写错误静默失败）；IDE 无自动补全；`emit_signal()` 为 string-based 调用（已被 Godot 官方文档标记为 legacy 模式）
- **Rejection Reason**: 类型安全和可读性优先；30 条信号的静态定义是合理的集中管理规模

## Consequences

### Positive

- 任意新系统只需订阅 EventBus，不改动任何现有系统
- Presentation 层与 Core/Feature 层完全解耦
- 全量信号在 EventBus.gd 中集中定义（单一真实来源，可用作信号参考文档）
- Godot 编辑器的 Signal 面板可以列出所有信号（因为是静态定义）
- 单元测试可 mock EventBus，验证每个系统的信号行为

### Negative

- 新增信号必须修改 EventBus.gd（中心文件更新，但修改量小）
- 信号流无法通过节点引用图追踪（需通过信号名在代码中搜索消费者）
- EventBus.gd 是全局单点依赖（若 autoload 加载失败，全局崩溃）

### Risks

- **初始化顺序错误**：若系统的 `_ready()` 早于 EventBus 执行，`EventBus.x.connect()` 会空指针。
  缓解：EventBus 注册为 project.godot 第一条 autoload，保证先于所有场景节点初始化。

- **信号连接泄漏**：若节点在未 disconnect 的情况下被 free，emit 时触发已释放节点的回调。
  缓解：Godot 4 在 `Node.free()` 时自动断开所有该节点的信号连接，无需手动管理。

- **回调顺序非确定性**：多个系统订阅同一信号时，回调执行顺序取决于连接时序（_ready() 执行顺序 = 场景树顺序）。
  缓解：architecture.md §4d 定义了明确的初始化顺序；跨系统回调顺序依赖须在相关系统的注释中标注。

- **Signal 参数类型注解为装饰性（Godot Issue #110573）**：Godot 4.x 中 signal 参数的类型注解（如 `Array[int]`）不在 emit 侧强制执行——传入错误类型不会产生运行时报错。
  缓解：GUT 单元测试须主动断言 emit 参数的实际类型；emit 调用处加注释声明类型契约，例如 `# buffed_ids: Array[int] — unit runtime IDs`。

- **ID 类型二元性风险**：本 ADR 中 `attacker_id` 系列信号使用 `String` ID（来自配置的字符串键），而 `unit_id` 系列信号使用 `int`（运行时实例 ID）。同一战斗单位在不同信号中 ID 类型不同（如 `slash_executed` 的 `attacker_id: String` vs `target_ids: Array[int]`）。
  缓解：String ID 指向 UnitDefinition 的资源键（来自 `.tres` 文件名）；int ID 指向 BattleScene 中的运行时 UnitInstance 句柄。两套体系职责不同，不可混用。实现阶段须在 emit 注释中明确标注 ID 来源。

- **`IntentRecord` 类型引用依赖 class_name**：signal `intent_declared(unit_id: int, intent: IntentRecord)` 要求 `intent_record.gd` 首行声明 `class_name IntentRecord`。若未声明全局类名，EventBus.gd 须在顶部显式 `const IntentRecord = preload("res://src/ai/intent_record.gd")`。
  缓解：实现 `intent_record.gd` 时强制加 `class_name IntentRecord extends Resource`；代码审查检查项之一。

## GDD Requirements Addressed

| GDD 系统 | TR ID | 需求摘要 | 此 ADR 如何满足 |
|---------|-------|---------|--------------|
| turn-management-system.md | TR-TMS-005 | battle_started/round_started/round_ended/unit_turn_*/battle_won/battle_lost/last_round_warning 信号协议 | 在 EventBus 上静态定义对应 signal（含类型参数）；补入 `round_ended()` |
| turn-management-system.md | TR-TMS-006 | unit_downed 必须在 battle_won 之前 dispatch | EventBus 保证同帧 emit 顺序由调用方控制（TurnManager 职责保证）|
| bond-gauge-burst-system.md | TR-BGBS-005 | gauge_charged(attacker_id,charge_amount,bond_gauge_current)/bond_gauge_full/burst_executed/burst_presentation_requested/* | 在 EventBus 上静态定义；★ 修正 gauge_charged 签名以携带 attacker_id（HUD 动画需要）|
| route-recruitment-system.md | TR-RRS-005 | run_phase_changed/crew_member_downed/run_completed(won,island_count,roster_snapshot)/map_reset_requested/map_loaded | 在 EventBus 上静态定义；★ 修正 run_completed 签名，补入 map_loaded |
| battle-map-system.md | TR-BMS-002 | map_load_failed(reason) / map_loaded(map_id) 信号 | `signal map_load_failed(reason: StringName)` + ★ 新增 `signal map_loaded(map_id: String)` |
| adjacency-bond-system.md | TR-ABS-003 | attack_initiated(attacker_id: String, verb: String) — verb 用于 AdjacencyBond 过滤哪条羁绊响应本次行动 | ★ 修正签名：`signal attack_initiated(attacker_id: String, verb: String)` |
| battle-resolution-system.md | TR-BRS-006 | 战斗信号完整列表（slash/cannon/aura/damage_dealt 正确参数）| 所有战斗信号在 EventBus 静态定义；★ 修正 slash/cannon/aura/damage_dealt 签名以携带多目标、方向、后处理伤害 |
| enemy-ai-intent-system.md | TR-EAIS-002 | ROUND_START 时声明意图（intent_declared 信号）| `signal intent_declared(unit_id: int, intent: IntentRecord)` |
| enemy-ai-intent-system.md | TR-EAIS-003 | enemy_actions_completed 须携带 unit_id（TurnManager 需知哪个敌人完成行动）| ★ 修正：`signal enemy_actions_completed(unit_id: int)` |
| grid-board-system.md | — | unit_moved 信号（HUD 更新 has_moved 行动点 pip；battle-hud Rule 2）| ★ 新增 `signal unit_moved(unit_id: int, from_pos: Vector2i, to_pos: Vector2i)` |
| grid-board-system.md | — | terrain_changed 信号（视觉系统响应地形变化；grid-board UI Requirements）| ★ 新增 `signal terrain_changed(pos: Vector2i, type: String)` |
| bond-gauge-burst-system.md | — | round_ended 信号（轮末羁绊充能结算；受击计数重置；bond-gauge-burst Rule 4）| ★ 新增 `signal round_ended()` |

## Performance Implications

- **CPU**: 可忽略 — Godot 原生 Signal dispatch 是直接函数调用，无队列无反射
- **Memory**: < 1 KB — 30 个信号定义对象，零运行时元数据开销
- **Load Time**: EventBus autoload 在引擎启动时一次性初始化（< 1 ms）
- **Network**: 不适用（本游戏无网络）

## Migration Plan

首次实现，无现有代码需要迁移。

1. 创建 `src/autoloads/event_bus.gd`（完整信号定义见上方）
2. 在 project.godot `[autoload]` 节添加第一条：`EventBus="*res://src/autoloads/event_bus.gd"`
3. 在 `src/` 目录下所有系统的 `_ready()` 中替换任何直接节点引用为 EventBus 连接
4. 运行 `tests/unit/` 中的信号相关测试验证正确性

## Validation Criteria

1. **架构合规**（代码审查）：所有 12 个系统的 `_ready()` 仅连接 EventBus，不持有其他游戏系统的 `@onready var` 引用（AdjacencyBond 例外已记录）
2. **功能正确**（GUT 单元测试）：mock EventBus，验证 BattleResolution 执行攻击后 emit `attack_executed`
3. **信号链集成**（集成测试）：完整战斗回合，验证 `attack_initiated → modifier 注入 → attack_executed → gauge 充能` 信号链顺序正确
4. **初始化顺序**：在 BattleScene._ready() 最早点 assert `EventBus != null`（自动满足，autoload 在场景前初始化）

## Related Decisions

- [architecture.md §4b](architecture.md) — 信号名单（此 ADR 定义其静态实现，并将占位模式升级为类型化 Signal）
- ADR-0002 — Scene Architecture（SceneManager 通过 EventBus 广播 `run_phase_changed`）
- ADR-0004 — GDScript State Machine Pattern（状态机 emit/subscribe 通过 EventBus）
- ADR-0008 — Burst Presentation Timing（BurstPresentation 订阅 `burst_presentation_requested`）
