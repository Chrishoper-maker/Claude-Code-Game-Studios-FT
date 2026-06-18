# Control Manifest

> **Engine**: Godot 4.6.3
> **Last Updated**: 2026-06-18
> **Manifest Version**: 2026-06-18
> **ADRs Covered**: ADR-0001, ADR-0002, ADR-0003, ADR-0004, ADR-0006, ADR-0007, ADR-0008, ADR-0009
> **Status**: Active — regenerate with `/create-control-manifest update` when ADRs change

`Manifest Version` 是本 manifest 生成日期。Story 文件创建时嵌入此日期；`/story-readiness`
比对 story 嵌入版本与本字段以检测对照过期规则编写的 story。始终等于 `Last Updated`。

本 manifest 是程序员速查表，规则逐条抽取自全部 Accepted ADR、technical-preferences
与引擎参考。每条规则的理由见所注 ADR。**规则按 ADR 原文抽取，未释义改义。**

---

## Foundation Layer Rules

*适用于：场景管理、事件架构、数据加载、引擎初始化*

### Required Patterns
- **所有跨系统通信经 EventBus 信号**（`_ready()` 中 `EventBus.signal_name.connect(callable)` 订阅，`EventBus.signal_name.emit(args)` 发射）— source: ADR-0001
- **所有游戏信号在 `src/autoloads/event_bus.gd` 上静态定义且带类型参数**，单一真实来源 — source: ADR-0001
- **`EventBus` 必须是 project.godot 第一条 autoload** — source: ADR-0001 / ADR-0002
- **`SceneManager` 必须是最后一条 autoload**（其余 autoload 须先于它 `_ready()`）— source: ADR-0002
- **Autoload 注册顺序严格为**：EventBus → UnitDataManager → MapDataManager → RunManager → SceneManager — source: ADR-0002 / ADR-0003
- **场景切换只经 `SceneManager.goto_battle()` / `goto_route()`**（封装 `get_tree().change_scene_to_packed(PackedScene)`）— source: ADR-0002
- **`goto_*` 调用 `change_scene_to_packed` 前必须 `assert(scene != null)`** — source: ADR-0002
- **`run_phase_changed` 信号唯一发射方为 RunManager** — source: ADR-0002
- **在 `_ready()` 中订阅 `run_phase_changed` 的节点必须同时立即轮询 `RunManager.current_phase`**（状态轮询 + 信号订阅双轨；因 `change_scene_to_packed` 延迟执行，新场景 `_ready()` 在下一帧、错过上一帧信号）— source: ADR-0002
- **`goto_*` 调用后不得访问旧场景节点**；如需要用 `await get_tree().process_frame` 延迟 — source: ADR-0002
- **游戏数据 = Godot 自定义 Resource（`.tres`）**，`extends Resource` + 类型化 `@export` 字段 — source: ADR-0003
- **数据文件置于 `res://assets/data/units/` 与 `res://assets/data/maps/`；数据类脚本置于 `res://src/data/`**（稳定路径区——移动/改名会破坏全部 `.tres`）— source: ADR-0003
- **UnitDataManager / MapDataManager 在 `_ready()` 扫描目录**，`ResourceLoader.load()` 加载，校验后缓存进按 `id` / `map_id` 键控的 Dictionary（O(1) 查询）— source: ADR-0003
- **fail-fast 校验**：结构性错误 → `push_error()` + `_all.clear()` + `is_loaded=false`（`get_all_units()` 返回 `[]`）；平衡告警 → `push_warning()` + 继续 — source: ADR-0003
- **校验错误消息格式严格为** `"UnitData parse error: [path] — [detail]"` 与 `"UnitData validation error: [unit_id] — [field] — [detail]"` — source: ADR-0003
- **调用 `get_all_units()` 的系统进入战斗前必须检查空数组情形** — source: ADR-0003
- **`UnitDefinition` 模板运行时只读；可变状态置于独立 `UnitInstance`**（纯 GDScript class，非 Resource），持模板只读引用 — source: ADR-0003

### Forbidden Approaches
- **禁止动态 EventBus**（`add_user_signal` / 按 StringName `emit_signal`）— 丧失类型安全 — source: ADR-0001（拒绝的 Alt 2）
- **禁止 Presentation 层（BattleHUD/BurstPresentation）持有 Core/Feature 层节点的 `@onready var` 引用**（EventBus 除外）— source: ADR-0001
- **唯一允许的直接跨系统调用**：`AdjacencyBond → BattleResolution.register_attack_modifier()`（单向注入，须在 AdjacencyBond 实现文档标注）— source: ADR-0001
- **禁止 MasterScene/持久根场景 或 单一大场景 `visible` 切换** 作为场景切换方案 — source: ADR-0002（拒绝的 Alt 1/2）
- **禁止由 SceneManager 或任何非 RunManager 发射 `run_phase_changed`** — source: ADR-0002（拒绝的 Alt 3）
- **禁止 JSON+FileAccess / `@export` 数组 Inspector 赋值 / `preload` 硬编码路径 / `load_threaded` 异步** 作为数据加载方案 — source: ADR-0003（拒绝的 Alt 1/2/3/4）
- **禁止对模板使用 `Resource.duplicate_deep()`**（模板只读共享，零拷贝）— source: ADR-0003
- **禁止运行时修改 `UnitDefinition`**（forbidden pattern: `runtime_unit_definition_mutation`）— source: ADR-0003

### Engine API Constraints（编码前 Verification）
- **`change_scene_to_packed` 延迟执行语义**（旧场景当帧末存活、新场景 `_ready()` 下一帧）— 引擎专家已验证 ✓ — source: ADR-0002
- **导出 `.pck` 内 `DirAccess` 目录枚举** + **`ResourceLoader.load()` 对损坏 `.tres` 返回 `null`（非异常）** — Pre-Production sprint 1 实测 — source: ADR-0003

---

## Core Layer Rules

*适用于：核心游戏循环、回合/run/地图状态机、棋盘空间逻辑、单位拾取*

### Required Patterns
- **状态机 = 所属类内 `enum` + `match`**；转换仅经私有 `_set_[machine](new_state)` 单一入口 — source: ADR-0004
- **enum 名严格匹配 GDD 状态名**（`BattleState` / `RunPhase` / `MapState`）— source: ADR-0004
- **终态守卫**：`BATTLE_WIN` / `BATTLE_LOSS` 经 `BATTLE_TERMINAL_STATES` 检查拒绝再转出（`push_warning`）— source: ADR-0004
- **参数化状态**：转换前先设伴随变量（`_current_unit_id`）再调 `_set_battle_state(ACTIVE_TURN)`，经 `_begin_active_turn(unit_id)`；访问以 `assert` 守卫 — source: ADR-0004
- **状态进入时在 `_on_[machine]_entered()` 发 EventBus 信号** — source: ADR-0004
- **RunManager 经 `_PHASE_TO_STRING` 常量字典暴露 `current_phase: String` 门面**（ADR-0002 契约）；`_ready()` 断言映射完整 — source: ADR-0004
- **全部 grid↔world 坐标转换经 `GridCoordMapper.grid_to_world()` / `world_to_grid()`**（全项目唯一坐标权威）；`CELL_SIZE=2.0` 单一常量 — source: ADR-0006
- **单位鼠标拾取走逻辑链**：射线-平面 Y=0 解析交点 → `world_to_grid()` → `GridBoard.get_unit_at()` → `UnitLayer.get_view()` — source: ADR-0007

### Forbidden Approaches
- **禁止字符串常量状态 + if-else 链 / 每状态一类 / Node-based 逻辑状态机** — source: ADR-0004（拒绝的 Alt 1/2/3）
- **禁止在 `GridCoordMapper` 以外内联 `col*CELL_SIZE` 或 `/CELL_SIZE`** — source: ADR-0006
- **禁止为拾取给单位加物理体**（`StaticBody3D`/`Area3D`/`CharacterBody3D`/`CollisionShape3D`）— 用 `world_to_grid` + `GridBoard` 占用查询 — source: ADR-0007
- **禁止单位用 `CharacterBody3D` / `move_and_slide`**（离散格吸附，无物理移动）— source: ADR-0007（拒绝的 Alt 2）

---

## Feature Layer Rules

*适用于：次级机制、AI 系统、相邻羁绊/羁绊槽/敌人意图*

> 多数 Feature 系统（AdjacencyBond、BondGaugeBurst、EnemyAI、BattleResolution 公式）
> 的专属 ADR（如 ADR-0005 战斗解算）尚未立项，将在 Pre-Production / Production 阶段补充。
> 现阶段约束源自 Foundation/Core ADR 的跨层契约。

### Required Patterns
- **AdjacencyBond 订阅 `attack_initiated(attacker_id: String, verb: String)`** 并同步调用 `BattleResolution.register_attack_modifier()`（唯一直连例外）— source: ADR-0001
- **EnemyAI 经 `enemy_actions_completed(unit_id: int)` 通知 TurnManager** 推进队列 — source: ADR-0001 / ADR-0004
- **状态机系统（含 BattleMapSystem）遵循 Core 层 enum+match 约定** — source: ADR-0004

### Forbidden Approaches
- **禁止 Feature 系统持有彼此或 Core 层节点 `@onready var` 引用**（EventBus 除外；AdjacencyBond 直连为唯一例外）— source: ADR-0001

---

## Presentation Layer Rules

*适用于：3D 棋盘渲染、单位视觉、爆发演出计时、相机震动、HUD*

### Required Patterns
- **Camera3D**：`PROJECTION_PERSPECTIVE`、`fov=60`、参考 `position=(7,16,22)`、初始化 `look_at(Vector3(7,0,7), Vector3.UP)` — source: ADR-0006
- **project.godot `[rendering]` 显式声明** `renderer/rendering_method="forward_plus"` — source: ADR-0006
- **棋盘底板 PlaneMesh 法线 +Y**（不得旋转至朝下）；**格子高亮 y=0.01** 防 z-fighting — source: ADR-0006
- **单位视觉 = 纯 `Node3D`（`class_name UnitView`）+ `MeshInstance3D`，无任何物理体** — source: ADR-0007
- **单位位置由 `GridCoordMapper.grid_to_world()` 驱动；数据→视觉单向，绝不写回 `UnitDefinition`/`UnitInstance`** — source: ADR-0007
- **白盒占位**：每职业图元+albedo 取自 art-bible §4.4，阵营 rim 取自 §4.5；`CLASS_VISUAL` 字典为单一回填点 — source: ADR-0007
- **单位移动 = `Tween` 对 `global_position`，`MOVE_TWEEN_DURATION=0.2s`，走 scaled 时间**；重入先 `kill()` 旧 Tween — source: ADR-0007
- **演出 Tween 走 unscaled**：`create_tween().set_ignore_time_scale(true).set_process_mode(Tween.TWEEN_PROCESS_IDLE)`（按墙钟）；世界对象走 scaled — source: ADR-0008
- **`Engine.time_scale` 仅由 BurstPresentation 写入**（单写者）— source: ADR-0008
- **time_scale 钳制**：加载期 `_freeze_scale()` 钳至 ≥0.01（+`push_warning`）；P4 末 ==1.0；skip/重入 → `kill()` + `Engine.time_scale=1.0` 立即恢复 — source: ADR-0008
- **相机震动**：`Tween` 经 `transform.basis` 往复 Camera3D **局部** position 偏移（不动 `global_transform` / 不改 `look_at`）；末段 tween 精确回 rest（无累积漂移）；入口 `is_instance_valid(camera)` 守卫 — source: ADR-0009
- **震动 pixel→世界换算**：`world_per_pixel = (2·distance·tan(fov/2)) / viewport_height` 单函数封装 — source: ADR-0009
- **震动确定性**：无随机偏移（确定性往复波形）— source: ADR-0009

### Forbidden Approaches
- **禁止正交等轴测 / 90° 直顶相机**（丧失爆发 zoom 弹性）— source: ADR-0006（拒绝的 Alt 1/2）
- **禁止 `CELL_SIZE=1.0`**（低模单位相互穿插）— source: ADR-0006（拒绝的 Alt 3）
- **禁止白盒单位写自定义 `.gdshader`**（规避 4.4 shader 纹理类型变更）— source: ADR-0007
- **禁止单位仅靠灰模/形状区分**（阵营必须靠颜色/色调承载）— source: ADR-0007（拒绝的 Alt 3）
- **禁止仅 vignette 不改 time_scale**（违反 GDD AC-4）；**禁止 `get_tree().paused` 冻结**（需慢动作非全暂停）— source: ADR-0008（拒绝的 Alt 1/3）
- **禁止 `FastNoiseLite` / 每帧随机 trauma 震动**（非确定性，单测难写）— source: ADR-0009（拒绝的 Alt 1/2）
- **禁止多源写 `Engine.time_scale`** — source: ADR-0008

### Engine API Constraints（编码前 Verification — HIGH RISK）
- **`set_ignore_time_scale(true)` 的 4.6.3 行为必须编码前实测**（架构评审标注 4.5 改动 Tween PROCESS_IDLE；注：项目 `animation.md` 未佐证此变化，建议核对）；若不符回退 Alternative 2（自管 unscaled delta 控制器）— source: ADR-0008
- **`world_per_pixel` 分母 viewport 高度待 project.godot 建立后以实际值重算**（算例按 1080：8px≈0.1875 世界单位）— source: ADR-0009
- **Camera FOV=60 在 8×8 棋盘全格可见性 + 边缘透视畸变（~3%）目视确认**；D3D12 驱动需 WDDM 2.0+ — source: ADR-0006

---

## Global Rules (All Layers)

### Naming Conventions
| Element | Convention | Example |
|---------|-----------|---------|
| Classes | PascalCase | `CrewMember`, `BondGauge` |
| Variables | snake_case | `bond_charge`, `grid_position` |
| Signals/Events | snake_case 过去式 | `bond_gauge_filled`, `crew_recruited` |
| Files | snake_case（与类名对应） | `crew_member.gd` |
| Scenes/Prefabs | PascalCase（与根节点对应） | `CrewMember.tscn` |
| Constants | UPPER_SNAKE_CASE | `MAX_CREW_SIZE`, `CELL_SIZE` |

source: `.claude/docs/technical-preferences.md`

### Performance Budgets
| Target | Value |
|--------|-------|
| Framerate | 60 fps |
| Frame budget | 16.6 ms |
| Draw calls | < 500（2D 战棋单屏，含爆发演出峰值） |
| Memory ceiling | < 1 GB |

source: `.claude/docs/technical-preferences.md`
> 实测参考（ADR-0006/0007）：棋盘 + ≤16 单位 + ≤64 高亮 + 地形估计 Draw Calls < 200。

### Approved Libraries / Addons
- **None**（无第三方库/addon 获批；新增须经架构决策）— source: technical-preferences.md

### Forbidden APIs (Godot 4.6.3)
以下 API 已废弃，建议时必须替换（source: `docs/engine-reference/godot/deprecated-apis.md`）：

| 禁用 | 改用 | Since |
|------|------|-------|
| `TileMap` | `TileMapLayer` | 4.3 |
| `VisibilityNotifier2D/3D` | `VisibleOnScreenNotifier2D/3D` | 4.0 |
| `YSort` | `Node2D.y_sort_enabled` | 4.0 |
| `Navigation2D/3D` | `NavigationServer2D/3D` | 4.0 |
| `yield()` | `await signal` | 4.0 |
| `connect("signal", obj, "method")` | `signal.connect(callable)` | 4.0 |
| `instance()` / `PackedScene.instance()` | `instantiate()` | 4.0 |
| `get_world()` | `get_world_3d()` | 4.0 |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` | 4.0 |
| `Skeleton3D.bone_pose_updated` | `skeleton_updated` | 4.3 |
| `AnimationPlayer.method_call_mode` / `.playback_active` | `AnimationMixer.callback_mode_method` / `.active` | 4.3 |
| `Texture2D`（shader 参数） | `Texture` 基类型 | 4.4 |

### Cross-Cutting Constraints
- **静态类型 everywhere**：`Array[Type]`、类型化变量（GDScript 编译器优化；禁止裸 `Array`/`Dictionary` 用于类型化场景）— source: deprecated-apis.md（Patterns）
- **仅类型化信号连接**（禁止字符串 `connect()`）— source: ADR-0001 / deprecated-apis.md
- **`res://src/data/` 为稳定路径区**：移动数据类脚本须同步重存全部关联 `.tres` — source: ADR-0003
- **`$NodePath` 不得在 `_process()` 内**：用 `@onready var` 缓存引用 — source: deprecated-apis.md
- **新 3D 物理用 Jolt**（4.6 默认；本作物理使用极少）— source: deprecated-apis.md
- **signal 参数类型注解为装饰性**（Godot Issue #110573，emit 侧不强制）：发射方须自行保证类型正确 — source: ADR-0001（Risks）
- **`IntentRecord` 须 `class_name` 或 EventBus 顶部 `const ... = preload(...)`**（`intent_declared` 信号类型引用依赖）— source: ADR-0001（Risks）
