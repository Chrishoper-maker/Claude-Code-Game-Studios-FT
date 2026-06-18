# ADR-0006: 3D Board Rendering — 逻辑格到世界坐标映射

## Status
Accepted

## Date
2026-06-18（Accepted 2026-06-18 — /architecture-review rerun CONCERNS，无阻断，F-4 命名已修）

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Rendering / 3D |
| **Knowledge Risk** | HIGH — D3D12 默认后端（4.6）、Glow 顺序变化（4.6）、Shader 纹理类型变化（4.4）均为训练截止后变化 |
| **References Consulted** | `docs/engine-reference/godot/modules/rendering.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | None — `Camera3D.PROJECTION_PERSPECTIVE`、`Node3D.look_at()`、`roundi()` 均 stable since 4.0 |
| **Verification Required** | 确认 project.godot 中 `rendering/renderer/rendering_method = "forward_plus"`；验证 Camera3D FOV=60 在 8×8 棋盘下全格可见；确认 Windows 开发环境 GPU 驱动支持 D3D12（WDDM 2.0+）；目视检查透视畸变在边缘格可接受范围内 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002（BattleScene 结构定义；Camera3D 属于 BattleScene 子节点） |
| **Enables** | ADR-0007（Unit Rendering — 单位模型使用 `grid_to_world()` 定位）|
| **Blocks** | 所有 BattleScene 视觉开发（单位模型放置、格子高亮、地形资源、光标）|
| **Ordering Note** | 必须在任何 BattleScene 艺术/视觉工作开始前 Accepted；`GridCoordMapper.grid_to_world()` 是全项目坐标共享接口 |

## Context

### Problem Statement

GridBoard 系统以逻辑格坐标 `(col, row)` 管理所有空间逻辑。BattleScene 需要将这些坐标转换为
Godot 3D 世界坐标才能放置单位模型、格子高亮、地形资源和光标。没有共享的转换公式和相机规格，
每个系统将各自实现映射，产生不一致和集成错误。本 ADR 关闭 grid-board-system.md Open Question 1。

### Constraints

- 8×8 逻辑格棋盘（`grid-board-system.md` 定义）
- Forward+ 渲染管线（`technical-preferences.md`）
- PC Desktop 目标平台（Steam / Epic）
- Godot 4.6.3（Windows 运行时默认 D3D12 后端）
- 60fps 性能预算，Draw Calls < 500

### Requirements

- 全部系统（GridBoard、BattleHUD、EnemyAI 高亮、BurstPresentation）使用相同的 `grid_to_world()` 函数
- 逻辑格坐标与世界坐标双向可转换（grid ↔ world）
- 相机在 BattleScene 中以固定角度俯视整块 8×8 棋盘
- 爆发演出时相机可通过 Tween 调整（zoom/pan）而不破坏坐标映射
- 格子高亮必须精确对齐逻辑格边界，无肉眼可见偏移

## Decision

**采用透视相机（Perspective）+ XZ 平面 8×8 网格 + CELL_SIZE = 2.0 的线性坐标映射。**

### 坐标映射公式（GridCoordMapper）

文件路径：`src/systems/board/grid_coord_mapper.gd`

```gdscript
# 全局工具类，无状态，可在任意系统中静态调用
class_name GridCoordMapper

const CELL_SIZE: float = 2.0
const BOARD_SIZE: int = 8

# 逻辑格 → 世界坐标
# col=0,row=0 → (0, 0, 0)；col=7,row=7 → (14, 0, 14)
# row=0 为对方阵地（屏幕远端）；row=7 为玩家阵地（屏幕近端）
# col=0 为左侧；col=7 为右侧（与屏幕 X 轴方向一致）
static func grid_to_world(grid_pos: Vector2i) -> Vector3:
    return Vector3(
        grid_pos.x * CELL_SIZE,
        0.0,              # 棋盘等高；地形高度变化通过视觉资产本地偏移实现，不修改此公式
        grid_pos.y * CELL_SIZE
    )

# 世界坐标 → 逻辑格（光标拾取用）
static func world_to_grid(world_pos: Vector3) -> Vector2i:
    return Vector2i(
        roundi(world_pos.x / CELL_SIZE),
        roundi(world_pos.z / CELL_SIZE)
    )
```

棋盘中心 = `Vector3((BOARD_SIZE - 1) / 2.0 * CELL_SIZE, 0, (BOARD_SIZE - 1) / 2.0 * CELL_SIZE)` = `Vector3(7, 0, 7)`

### 相机参考配置

```gdscript
# BattleScene 中 Camera3D 的 Inspector 参考配置（垂直切片时目视校准）
# Camera3D:
#   projection = Camera3D.PROJECTION_PERSPECTIVE   # 0 = Perspective（默认值）
#   fov = 60.0
#   position = Vector3(7.0, 16.0, 22.0)            # ~55° 仰角，从 +Z 侧俯视棋盘
#   # 初始化时调用: look_at(Vector3(7, 0, 7), Vector3.UP)

# 防御写法（若相机位置可能动态变化）
func _setup_camera() -> void:
    const BOARD_CENTER := Vector3(7.0, 0.0, 7.0)
    if camera.global_position.distance_to(BOARD_CENTER) > 0.001:
        camera.look_at(BOARD_CENTER, Vector3.UP)
```

### 格子高亮放置规范

```gdscript
# 高亮节点（MeshInstance3D）放置方法
func highlight_cell(grid_pos: Vector2i) -> void:
    var hl := highlight_pool.get()
    hl.global_position = GridCoordMapper.grid_to_world(grid_pos)
    hl.global_position.y = 0.01    # 略高于格面（y=0），防止 z-fighting
    hl.visible = true

# 注：若未来启用 TAA 或高精度渲染，可升级为：
#   var mat := StandardMaterial3D.new()
#   mat.no_depth_test = true
#   mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
```

### Architecture Diagram

```
BattleScene（根节点）
├── Camera3D              ← 固定透视相机，position≈(7,16,22)，look_at 棋盘中心(7,0,7)
├── GridBoard             ← 逻辑棋盘（纯数据：格子状态、占用表）—— 无 3D 节点
├── BoardVisuals          ← 棋盘底板 MeshInstance3D（PlaneMesh，法线 +Y，16×16 世界单位）
├── UnitLayer             ← 各 UnitView 子节点（Node3D；位置由 grid_to_world() 驱动；节点契约见 ADR-0007）
├── HighlightLayer        ← 格子高亮 MeshInstance3D 池（可达/攻击/羁绊，y=0.01）
└── TerrainLayer          ← 地形资源节点（位置由 grid_to_world() 驱动）

坐标数据流：
  GridBoard.place_unit(unit_id, grid_pos)
    → UnitLayer.get_view(unit_id).global_position = GridCoordMapper.grid_to_world(grid_pos)
    → EventBus.unit_moved.emit(unit_id, old_pos, new_pos)

  GridBoard.get_reachable_cells(pos, range) → Array[Vector2i]
    → HighlightLayer.show_highlights(cells) → grid_to_world() per cell

禁止模式：
  任何系统不得内联实现 col*CELL_SIZE — 必须调用 GridCoordMapper.grid_to_world()
  棋盘底板 PlaneMesh 的 cull_mode 默认 CULL_BACK（法线 +Y）——不得旋转至法线朝下
```

### 项目配置要求

```ini
# project.godot — 显式声明渲染器，不依赖引擎默认值
[rendering]

renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="mobile"
```

Windows 平台运行时后端由 Godot 引擎自动选择（4.6 起默认 D3D12）。D3D12 要求 GPU 驱动支持 WDDM 2.0+（Windows 10 1809+）。

## Alternatives Considered

### Alternative 1: 正交等轴测相机（Orthographic Isometric）

- **Description**: `Camera3D.PROJECTION_ORTHOGONAL`，35.26° 下倾，45° 方位角，经典战术 RPG 外观
- **Pros**: 格子视觉完全均一，无透视畸变；《最终幻想 Tactics》《逃离惑星》等参照
- **Cons**: 爆发演出无法通过相机缩放制造冲击力；3D 低模场景失去景深感和体积感
- **Rejection Reason**: 游戏定位为"风格化低模 3D 小场景"，爆发演出需要相机动效弹性；正交相机无法在不更换相机模式的情况下实现 zoom 效果

### Alternative 2: 正交直顶视角（90° 俯视）

- **Description**: `Camera3D.PROJECTION_ORTHOGONAL`，完全俯视
- **Pros**: 最简单实现，零透视
- **Cons**: 丧失 3D 风格意图；低模单位俯视后无辨识度；与"风格化低模 3D"定义不符
- **Rejection Reason**: 与游戏视觉定位根本矛盾

### Alternative 3: CELL_SIZE = 1.0

- **Description**: 每格 1 个世界单位，棋盘 8×8
- **Pros**: 数字简洁
- **Cons**: 3D 低模单位（高度约 1.5–2.0 单位）在 1.0 格子中相互穿插；格子边距不足
- **Rejection Reason**: 2.0 是低模 3D 战棋类游戏的常见格子尺寸，为单位模型留出展示空间

## Consequences

### Positive

- 全项目唯一坐标映射公式（`GridCoordMapper`），消除跨系统坐标偏差
- `GridCoordMapper` 为无状态工具类，可独立单元测试，零外部依赖
- `CELL_SIZE` 为单一命名常量，调整格子尺寸只需修改一处（垂直切片阶段可快速实验）
- 爆发演出相机自由度高（Tween 调整 position/fov），坐标系定义不受影响

### Negative

- 相机角度固定，艺术层面需在垂直切片阶段确认 55° 仰角满足视觉风格
- 透视相机使棋盘边缘格产生轻微畸变（FOV=60，8×8 棋盘，边缘约 3%），格子高亮轮廓非完全正方

### Risks

- **透视畸变与高亮轮廓不对齐**：高亮是世界空间矩形，透视投影后边缘格视觉上略非方正。
  缓解：8×8 棋盘范围内透视畸变 < 3%，视觉上可接受；垂直切片时用截图确认。

- **CELL_SIZE 后期修改成本**：若垂直切片后格子尺寸不合适，需重新校准相机位置和全部视觉资产。
  缓解：`CELL_SIZE` 为单一常量，修改代价 O(1)；ADR-0007（Unit Rendering）资产规格依赖此值，修改须同步更新。

- **D3D12 驱动要求（Godot 4.6 Windows）**：D3D12 成为 Windows 默认后端，旧驱动可能不支持。
  缓解：Steam minimum spec 标注 Windows 10 1809+ 及 WDDM 2.0 驱动；本地开发环境须保持驱动更新。

- **PlaneMesh 法线方向**：若棋盘底板 PlaneMesh 被错误旋转，法线朝 −Y，在 Forward+ 背面剔除下棋盘不可见。
  缓解：棋盘底板法线必须朝 +Y（PlaneMesh 默认值）；如需支持相机低于棋盘的视角，将材质 `cull_mode` 设为 `CULL_DISABLED`。

- **Y 轴地形高度（未来扩展）**：当前公式假设 `world_y = 0.0`（平面棋盘）。若引入地形高度变化（如 COVER 格视觉隆起），地形资源通过本地 Y 偏移处理，`grid_to_world()` 公式本身不修改。

## GDD Requirements Addressed

| GDD 系统 | TR ID | 需求摘要 | 此 ADR 如何满足 |
|---------|-------|---------|--------------|
| grid-board-system.md | TR-GBS-006 | 逻辑格 ↔ 3D 世界坐标映射（Open Question 1：等轴测 vs 正交；格子尺寸）| 定义 `GridCoordMapper.grid_to_world/world_to_grid`，`CELL_SIZE=2.0`，XZ 平面，透视相机，**关闭 OQ-1** |
| grid-board-system.md | TR-GBS-001 | 8×8 棋盘视觉边界明确，玩家可一眼读懂站位 | 棋盘 16×16 世界单位，Camera FOV=60 从参考位置覆盖全棋盘 |
| battle-map-system.md | TR-BMS-007 | 地形资源节点视觉层与逻辑格坐标对齐 | 地形资源 `position = grid_to_world(terrain_pos)`，与棋盘坐标系一致 |
| battle-hud-system.md | TR-BHS-008 | 格子高亮（可达/攻击/羁绊）与逻辑格精确对齐 | 高亮节点通过 `grid_to_world()` 定位，y=0.01 防 z-fighting |

## Performance Implications

- **CPU**: 可忽略 — `grid_to_world()` 是 2 次乘法，无查表无分支
- **Memory**: `GridCoordMapper` 为无状态工具类，零运行时内存开销
- **Draw Calls**: 格子高亮使用对象池；峰值 64 个高亮 node（8×8 全格高亮）+ 单位 + 地形，估计总 Draw Calls < 200，低于 500 预算
- **Load Time**: Camera3D 和坐标映射均在场景初始化时完成（< 1ms）

## Migration Plan

首次实现，无现有 3D 坐标系统需要迁移。

1. 创建 `src/systems/board/grid_coord_mapper.gd`（`class_name GridCoordMapper`，含 `CELL_SIZE` 常量及两个静态方法，附方向语义 docstring）
2. 在 `project.godot` `[rendering]` 节添加 `renderer/rendering_method="forward_plus"`
3. 在 `BattleScene.tscn` 中配置 `Camera3D`（PERSPECTIVE, fov=60, 参考 position Vector3(7,16,22)，look_at 棋盘中心）
4. 创建 `BoardVisuals` 子节点（PlaneMesh，16×16，法线 +Y，StandardMaterial3D）
5. `GridBoard.place_unit()` / `GridBoard.move_unit()` 调用 `grid_to_world()` 设置 `UnitView.global_position`（单位视觉节点契约见 ADR-0007）
6. 格子高亮系统用 `grid_to_world()` + y=0.01 定位 `MeshInstance3D` 高亮节点
7. 垂直切片阶段目视确认：全棋盘可见性、高亮对齐、透视畸变可接受度
8. 打包时启用 Shader Baker（Export → Shader Baker）消除首次进入 BattleScene 的编译卡顿

## Validation Criteria

1. **坐标映射正确性**（单元测试）：`grid_to_world(Vector2i(0,0))` = `Vector3(0,0,0)`；`grid_to_world(Vector2i(7,7))` = `Vector3(14,0,14)`；`world_to_grid(Vector3(14,0,14))` = `Vector2i(7,7)` — 往返转换无精度损失
2. **全棋盘可见性**（目视检查，垂直切片）：相机以参考配置运行时，8×8 全部格子在屏幕内可见且不被 UI 遮挡
3. **高亮对齐**（目视检查）：格子高亮与逻辑格边界在中心格和四角格均视觉对齐，无肉眼可见偏移
4. **CELL_SIZE 唯一性**（代码审查）：全项目仅 `GridCoordMapper.CELL_SIZE` 一处定义；`grep -rn "* 2.0\|/ 2.0\|CELL = 2"` 在 GridCoordMapper 以外无结果
5. **法线方向**（代码审查）：`BoardVisuals` 的 PlaneMesh 材质 cull_mode 注释标注法线方向约定

## Related Decisions

- ADR-0002 — Scene Architecture（BattleScene 拥有 Camera3D；SceneManager 负责场景加载）
- ADR-0007 — Unit Rendering（单位模型依赖 `grid_to_world()` 确定位置；资产规格依赖 CELL_SIZE）
- ADR-0001 — EventBus（`unit_moved` 信号触发高亮更新）
- `design/gdd/grid-board-system.md` — 棋盘坐标系权威来源，OQ-1 已关闭
