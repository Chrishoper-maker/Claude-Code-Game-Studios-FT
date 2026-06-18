# ADR-0007: Unit Rendering — 单位视觉节点与白盒占位策略

## Status
Accepted

## Date
2026-06-18（Accepted 2026-06-18 — /architecture-review rerun CONCERNS，无阻断，F-2 引用已修）

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Rendering / Animation |
| **Knowledge Risk** | HIGH — 4.6 为训练截止后版本（D3D12 默认后端、Glow 顺序、Shader 纹理类型 `Texture2D→Texture`(4.4)、SkeletonModifier3D/IK 恢复(4.6) 均后于 LLM 训练数据） |
| **References Consulted** | `docs/engine-reference/godot/modules/rendering.md`, `docs/engine-reference/godot/modules/animation.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None — `MeshInstance3D`、`BoxMesh`/`CapsuleMesh`、`StandardMaterial3D`、`Tween`（`create_tween` + `tween_property`）、`Node3D` 均 stable since 4.0。白盒 MVP 不写自定义 `.gdshader`，规避 4.4 纹理类型变更 |
| **Verification Required** | 验证 6 职业 + 2 阵营配色在 ADR-0006 相机（FOV=60，~55° 仰角）下可清晰辨识；验证单位高度（CapsuleMesh ~1.5）在 CELL_SIZE=2.0 格内不相互穿插；目视确认 Tween 离散补间（~0.2s）在 D3D12 后端无撕裂；确认无骨骼/无 AnimationPlayer 时单位静止帧表现可接受 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0006（3D Board Rendering — 单位位置由 `GridCoordMapper.grid_to_world()` 驱动；资产规格依赖 `CELL_SIZE=2.0`），ADR-0002（BattleScene 结构 — `UnitLayer` 属于 BattleScene 子节点），ADR-0003（Data Loading — `UnitView` 从 `UnitDataManager` 读取 `UnitDefinition` 取视觉属性） |
| **Enables** | BattleScene 单位视觉开发；ADR-0008（爆发演出对单位节点施加 Tween/缩放需要稳定的单位节点契约） |
| **Blocks** | 所有 BattleScene 单位视觉故事（单位放置、选中高亮、移动动画、Downed 视觉、招募/部署预览缩略） |
| **Ordering Note** | 必须在任何单位视觉资产/场景工作开始前 Accepted；`UnitView` 是单位视觉的唯一节点契约，全项目共享。须在 ADR-0006 Accepted 之后（坐标系先于其上的视觉对象定义） |

## Context

### Problem Statement

战斗中每个 `UnitInstance`（运行时数据）需要一个对应的 3D 视觉对象，用于在棋盘上呈现位置、
职业、阵营、存活状态，并响应移动与被选中。本 ADR 决定：**（1）单位视觉用哪种节点类型；
（2）鼠标如何拾取单位；（3）白盒 MVP 阶段六职业/两阵营如何在无美术资产下区分；
（4）单位移动如何表现。** 没有统一的单位节点契约，每个消费系统（战斗、HUD、招募预览、爆发演出）
将各自实例化单位视觉，产生数据—视觉耦合错误与坐标不一致。

### Constraints

- 单位为**离散格子吸附**：位置永远等于某个逻辑格的 `grid_to_world()`，无连续物理移动（`grid-board-system.md`、`turn-management-system.md`）
- `UnitDefinition` 资源运行时**只读**（注册表 `runtime_unit_definition_mutation` 禁止模式；TR-UDS-003）
- 坐标必须经 `GridCoordMapper.grid_to_world()`，禁止内联 `col*CELL_SIZE`（ADR-0006 禁止模式）
- MVP 阶段**无美术资产**——单位视觉必须可用引擎图元 + 纯色材质构造
- Forward+ 渲染，60fps，Draw Calls < 500（`technical-preferences.md`）
- 六职业枚举：`swordsman / gunner / bulwark / medic / navigator / musician`；阵营：`crew / enemy`（`unit-data-system.md`）

### Requirements

- 每个 `UnitInstance` 对应唯一 `UnitView` 视觉节点，由 `unit_id`（字符串）双向关联
- 单位位置由 `GridCoordMapper.grid_to_world(grid_position)` 驱动，与棋盘坐标系零偏差
- 鼠标可拾取单位（选中/查看意图），且拾取路径与 ADR-0006 的 `world_to_grid()` 一致
- 六职业可一眼区分；己方（crew）与敌方（enemy）阵营视觉对比强
- 单位移动有可跟随的视觉反馈（玩家能看清棋子从哪走到哪）
- `UnitView` 只读 `UnitInstance` / `UnitDefinition`，绝不写回模板（保持数据—视觉单向流）

## Decision

**单位视觉采用纯 `Node3D` 视觉节点（`class_name UnitView`），子节点为 `MeshInstance3D`，
无任何物理体。拾取走逻辑路径（`world_to_grid()` + GridBoard 占用查询，复用 ADR-0006）。
白盒 MVP 用引擎图元 + 每职业 albedo 配色 + 阵营色调区分。移动用 `Tween` 对 `global_position`
做约 0.2s 离散补间。**

### 节点结构与契约

文件路径：`src/systems/board/unit_view.gd`

```gdscript
class_name UnitView
extends Node3D

# 单位视觉节点：UnitInstance（数据）的 3D 呈现。
# 持有对 unit_id 的引用以与数据层关联；自身不持有可变游戏状态，
# 不写回 UnitDefinition / UnitInstance（单向数据流：数据 → 视觉）。

const MOVE_TWEEN_DURATION: float = 0.2   # 离散补间时长（秒）

var unit_id: String                      # 关联的 UnitInstance.id（字符串持久身份）
var _mesh: MeshInstance3D                # 白盒图元（MVP）/ 未来替换为导入模型根
var _move_tween: Tween                   # 当前移动补间（重入时先 kill）

# 由 UnitLayer 在生成时调用：依据 UnitDefinition 配置白盒外观并放置到初始格
func setup(unit_def: UnitDefinition, grid_pos: Vector2i) -> void:
    unit_id = unit_def.id
    _build_whitebox(unit_def.unit_class, unit_def.faction)
    global_position = GridCoordMapper.grid_to_world(grid_pos)

# 离散补间移动到目标格（玩家可跟随棋子走位）
func move_to(grid_pos: Vector2i) -> void:
    if is_instance_valid(_move_tween):
        _move_tween.kill()
    var target := GridCoordMapper.grid_to_world(grid_pos)
    _move_tween = create_tween()
    _move_tween.tween_property(self, "global_position", target, MOVE_TWEEN_DURATION)

# Downed：MVP 直接隐藏（视觉移除）；最终演出归 burst/feedback 层
func set_downed() -> void:
    visible = false
```

### 拾取策略（复用 ADR-0006，零物理体）

单位**无碰撞体**。鼠标拾取按既有逻辑链：

```
鼠标屏幕坐标
  → Camera3D.project_ray_origin/normal（投射射线）
  → 与棋盘平面 Y=0 求交（平面解析求交，非物理 RayCast3D）
  → GridCoordMapper.world_to_grid(交点) → Vector2i 逻辑格
  → GridBoard.get_unit_at(grid_pos) → unit_id 或空
  → UnitLayer.get_view(unit_id) → 对应 UnitView（如需高亮）
```

理由：棋盘是单一平面（Y=0），射线—平面解析求交确定且零成本；单位永远吸附格中心，
逻辑格即唯一权威占用源（`GridBoard`）。物理碰撞体在此场景纯属冗余，且会与逻辑占用表产生
"双事实源"风险。**禁止**为单位添加 `StaticBody3D`/`Area3D` 仅为拾取目的。

### 白盒占位策略（MVP，无美术资产）

每职业 = 一种图元形状 + 一个 albedo 主色；阵营 = 色调/明度调制，保证 crew 暖、enemy 冷的强对比。

```gdscript
# 职业 → (图元, 身份色)；色值权威源为 art-bible.md Section 4.4（独立身份调色板，与语义浮字色分离）
const CLASS_VISUAL := {
    "swordsman": { "shape": "box",     "color": Color("#B23A48") },  # 剑豪 — 绯红钢
    "gunner":    { "shape": "cylinder","color": Color("#C0703A") },  # 炮手 — 火药褐橙
    "bulwark":   { "shape": "box",     "color": Color("#5E7488") },  # 铁壁 — 钢青灰
    "medic":     { "shape": "capsule", "color": Color("#4FA68A") },  # 医师 — 薄荷青绿
    "navigator": { "shape": "capsule", "color": Color("#3B4F9E") },  # 航海士 — 靛蓝
    "musician":  { "shape": "cylinder","color": Color("#8E5BA6") },  # 乐手 — 紫罗兰
}
# 阵营调制（art-bible 4.5）：crew → 暖 rim 光 #FFE0B0；enemy → 冷 rim 光 #7FAFFF + albedo 压暗 ~30%
```

- 图元高度约 1.5 世界单位（CapsuleMesh `height≈1.5`，BoxMesh `size≈Vector3(0.9,1.5,0.9)`），底面贴 Y=0，在 CELL_SIZE=2.0 格内有边距、不相互穿插
- 材质为 `StandardMaterial3D`（`albedo_color` 驱动），**不写自定义 shader**（规避 4.4 shader 纹理类型变更风险）
- 敌方 `behavior_type`（MELEE/RANGED/GUARDIAN/SWARMER）MVP **不做**额外视觉标记——意图由 HUD 层呈现（`battle-hud-system.md` / `enemy-ai-intent-system.md`）
- **配色权威源**：`CLASS_VISUAL` 色值取自 `art-bible.md` Section 4.4（独立身份调色板，已与语义浮字色分离以避免战场撞色）；阵营 rim 取自 4.5。art-bible 后续若调色，回填此处一处即可

### 移动表现

`Tween` 对 `global_position` 做约 `MOVE_TWEEN_DURATION=0.2s` 的离散补间（默认 `TRANS_LINEAR`/`EASE_IN_OUT`，垂直切片可调）。无骨骼动画、无 `AnimationPlayer`。重入移动时先 `kill()` 旧 Tween 防止叠加。

> 注：`Tween` 受 `Engine.time_scale` 影响——爆发演出 FREEZE 阶段（ADR-0008，`time_scale=0.05`）会同时减慢移动补间。这是 ADR-0008 的待决交互点；本 ADR 仅声明移动用标准 `Tween`，FREEZE 期不应有单位移动补间在飞（回合制下移动与爆发不并发），故风险低。

### Architecture Diagram

```
BattleScene（ADR-0002）
├── Camera3D                ← ADR-0006 固定透视相机
├── GridBoard               ← 逻辑棋盘（唯一占用事实源：get_unit_at(pos) → unit_id）
├── BoardVisuals            ← 棋盘底板（ADR-0006）
└── UnitLayer  (Node3D)     ← 管理全部 UnitView 子节点 + unit_id↔UnitView 字典
    ├── UnitView (crew_azhan)    Node3D
    │   └── MeshInstance3D       ← 白盒图元 + StandardMaterial3D
    ├── UnitView (enemy_x)       Node3D
    │   └── MeshInstance3D
    └── ...

数据流（单向：数据 → 视觉）：
  战斗放置:  GridBoard.place_unit(id,pos) → UnitLayer.get_view(id).move_to(pos) 或 setup()
  移动:      EventBus.unit_moved(id, old, new) → UnitLayer.get_view(id).move_to(new)
  Downed:    EventBus.unit_downed(id)         → UnitLayer.get_view(id).set_downed()
  拾取:      鼠标 → world_to_grid → GridBoard.get_unit_at(pos) → UnitLayer.get_view(id)

禁止模式：
  ✗ 单位挂 StaticBody3D/Area3D 仅为鼠标拾取（用 world_to_grid + GridBoard 占用查询）
  ✗ 单位用 CharacterBody3D / move_and_slide（离散格吸附，无物理移动）
  ✗ UnitView 写回 UnitDefinition / UnitInstance（单向数据流）
  ✗ 内联 col*CELL_SIZE（必须 GridCoordMapper.grid_to_world）
```

### Key Interfaces

| 接口 | 签名 | 所有者 |
|------|------|--------|
| `UnitView.setup` | `setup(unit_def: UnitDefinition, grid_pos: Vector2i) -> void` | UnitView |
| `UnitView.move_to` | `move_to(grid_pos: Vector2i) -> void` | UnitView |
| `UnitView.set_downed` | `set_downed() -> void` | UnitView |
| `UnitLayer.get_view` | `get_view(unit_id: String) -> UnitView`（未知 id 返回 null） | UnitLayer |
| `UnitLayer.spawn_view` | `spawn_view(unit_def: UnitDefinition, grid_pos: Vector2i) -> UnitView` | UnitLayer |

## Alternatives Considered

### Alternative 1: StaticBody3D + CollisionShape3D（物理射线拾取）

- **Description**: 每个单位挂 `StaticBody3D` + `CollisionShape3D`，鼠标用 `PhysicsServer3D`/射线拾取
- **Pros**: 拾取无需求平面交点；可支持不规则形状碰撞
- **Cons**: 与 ADR-0006 已提供的 `world_to_grid()` 逻辑拾取冗余；引入"逻辑占用表 vs 物理碰撞"双事实源风险；每单位多一层碰撞配置与同步成本
- **Rejection Reason**: 棋盘是单平面、单位格中心吸附，逻辑拾取确定且零成本；物理体在此纯属冗余且制造同步隐患

### Alternative 2: CharacterBody3D（为物理移动预留）

- **Description**: 单位用 `CharacterBody3D` + `move_and_slide()`，为将来连续物理移动预留
- **Pros**: 若未来引入连续移动/碰撞滑动可直接复用
- **Cons**: 当前为离散格回合制战棋，无连续移动需求；`CharacterBody3D` 的物理积分、碰撞响应全是死开销
- **Rejection Reason**: YAGNI——MVP 无任何物理移动需求；离散补间已满足走位反馈

### Alternative 3: 统一灰模 + 仅图元形状区分

- **Description**: 六职业用不同图元形状但统一灰色，不配色
- **Pros**: 最简单，零配色决策
- **Cons**: 阵营（crew/enemy）无法靠形状区分；调试期玩家难分敌我与职业；与"一眼读懂站位"需求冲突
- **Rejection Reason**: 阵营辨识是战棋可读性底线，必须靠颜色/色调承载

## Consequences

### Positive

- 单位视觉零物理开销；拾取复用 ADR-0006 逻辑路径，无第二套事实源
- `UnitView` 是单位视觉唯一节点契约，招募预览/部署/爆发演出共享同一节点类型
- 白盒图元 + 纯色材质，无美术资产即可进入垂直切片，配色平滑过渡到 art-bible
- 数据—视觉严格单向，杜绝运行时污染 `UnitDefinition` 模板（满足 TR-UDS-003）

### Negative

- 单位无碰撞体 → 任何需要 3D 物理交互的未来特性（如投射物命中体）须另立 ADR
- 白盒配色为占位，art-bible 定稿后须回填 `CLASS_VISUAL`（一处常量，O(1) 成本）
- 无骨骼动画 → 攻击/受击的"动作感"留给爆发演出与反馈层（ADR-0008+），白盒期单位为静止图元

### Risks

- **配色与最终美术不一致**：`CLASS_VISUAL` 占位色与 art-bible 最终配色冲突。
  缓解：色值集中于单一常量字典；art-bible（B3）定稿后一次性回填；ADR 明示占位性质。
- **Tween 受 time_scale 影响（与 ADR-0008 交互）**：FREEZE 期移动补间会被减速。
  缓解：回合制下移动与爆发不并发，FREEZE 期不应有移动补间在飞；由 ADR-0008 统一裁定 time_scale 范围。
- **白盒可辨识度**：6 色 + 2 阵营在 55° 仰角小图元上可能不够分明。
  缓解：垂直切片用 ADR-0006 相机截图验证；阵营加边光/明度调制强化对比；必要时加职业首字母 Label3D（后备）。
- **命名对齐**：ADR-0006 架构图将单位视觉节点松散标注为 "UnitInstance3D"，与数据类 `UnitInstance` 撞名。
  缓解：本 ADR 正式命名视觉节点为 `UnitView`，作为权威；ADR-0006 图中标签应在其 Accept 前/时对齐为 `UnitView`（见 Related Decisions）。

## GDD Requirements Addressed

| GDD 系统 | TR ID | 需求摘要 | 此 ADR 如何满足 |
|---------|-------|---------|--------------|
| unit-data-system.md | TR-UDS-001 | UnitDefinition schema 含 `faction` / `unit_class` | `CLASS_VISUAL` 依 `unit_class` 取图元/配色，阵营调制依 `faction` |
| unit-data-system.md | TR-UDS-003 | UnitInstance 可变状态与 UnitDefinition 模板严格分离，模板只读 | `UnitView` 单向只读数据，禁止写回；列入禁止模式 |
| grid-board-system.md | TR-GBS-006 | 逻辑格 ↔ 3D 世界坐标映射 | 单位位置全程经 `GridCoordMapper.grid_to_world()`；拾取经 `world_to_grid()` |
| battle-hud-system.md | TR-BHS-008 | 站位/高亮可一眼读懂、敌我清晰 | 职业配色 + 阵营冷暖对比保证白盒期可读性 |

> 注：本 ADR 主要为 ADR-0006/unit-data 既有 TR 的**视觉实现**，无专属"白盒单位渲染"TR。建议 `/architecture-review` 为 Unit Rendering 视觉契约登记一条新 TR（如 TR-REN-001）。

## Performance Implications

- **CPU**: 移动 Tween 为内置插值，单位数 < 16，开销可忽略；拾取为一次射线—平面解析交点，无物理查询
- **Memory**: 每 UnitView = 1 Node3D + 1 MeshInstance3D + 1 共享/实例材质；白盒图元顶点数极低
- **Draw Calls**: 单位 < 16 个 MeshInstance3D；同职业可共享材质资源，叠加 ADR-0006 估算总 Draw Calls < 200，远低于 500 预算
- **Load Time**: 白盒图元程序化生成（无导入资产），场景初始化 < 1ms

## Migration Plan

首次实现，无现有单位渲染需迁移。

1. 创建 `src/systems/board/unit_view.gd`（`class_name UnitView`，含 `setup/move_to/set_downed` 与 `CLASS_VISUAL` 字典）
2. 创建 `src/systems/board/unit_layer.gd`（`UnitLayer`，管理 `unit_id → UnitView` 字典 + `spawn_view/get_view`）
3. `UnitView._build_whitebox()` 按 `unit_class` 生成 BoxMesh/CapsuleMesh/CylinderMesh + StandardMaterial3D albedo，按 `faction` 调制色调
4. 鼠标拾取链接入 BattleScene 输入处理：`project_ray` → 平面 Y=0 交点 → `world_to_grid` → `GridBoard.get_unit_at` → `UnitLayer.get_view`
5. 订阅 `EventBus.unit_moved` → `move_to`；`EventBus.unit_downed` → `set_downed`
6. 垂直切片阶段用 ADR-0006 相机截图校验 6 职业 + 2 阵营可辨识度
7. art-bible（B3）定稿后回填 `CLASS_VISUAL` 配色为权威值

## Validation Criteria

1. **数据—视觉分离**（代码审查 + 单测）：`grep` 确认 `unit_view.gd` 无对 `UnitDefinition`/`UnitInstance` 字段的写操作；模板对象在生成 UnitView 前后字段不变
2. **坐标一致**（单测）：`UnitView.setup(def, Vector2i(7,7))` 后 `global_position == GridCoordMapper.grid_to_world(Vector2i(7,7))`（== Vector3(14,0,14)）
3. **拾取正确**（集成测试）：模拟点击格 `(c,r)` 中心 → `world_to_grid` 还原为 `(c,r)` → `GridBoard.get_unit_at` 命中预期 unit_id
4. **无物理体**（代码审查）：`grep -rn "StaticBody3D\|Area3D\|CharacterBody3D\|CollisionShape3D" src/systems/board/` 在单位渲染范围内无结果
5. **可辨识度**（目视，垂直切片）：ADR-0006 相机下 6 职业 + crew/enemy 两阵营截图可区分
6. **移动补间**（目视）：单位走位为约 0.2s 平滑补间，重复触发不叠加/抖动

## Related Decisions

- ADR-0006 — 3D Board Rendering（提供 `grid_to_world`/`world_to_grid` + `CELL_SIZE`；其架构图 "UnitInstance3D" 标签应对齐为本 ADR 的 `UnitView`）
- ADR-0002 — Scene Architecture（`UnitLayer` 属于 BattleScene）
- ADR-0003 — Data Loading（`UnitView` 经 `UnitDataManager` 读取 `UnitDefinition`）
- ADR-0008 — Burst Presentation Timing（爆发演出对单位节点施加 Tween/缩放；`Engine.time_scale` 与移动 Tween 的交互由其裁定）
- `design/gdd/unit-data-system.md` — 六职业枚举与 UnitInstance/UnitDefinition 契约权威来源
- `design/art/art-bible.md`（待创建，B3 门控）— 最终职业/阵营配色权威源，回填 `CLASS_VISUAL`
