# 网格棋盘系统 (Grid Board System)

> **Status**: Reviewed — Revised
> **Author**: user + agents
> **Last Updated**: 2026-06-13
> **Implements Pillar**: 小棋盘大组合（棋盘本体）；羁绊即战术（站位几何的物理载体）

## Overview

网格棋盘系统是《孤帆棋海》一切空间逻辑的事实源——一个 8×8 的纯逻辑格子层。它管理格子的占用状态（哪个单位站在哪格、哪格被地形阻挡）、回答全部空间查询（两格的曼哈顿距离、某单位以 `move_range` 能到达哪些格、谁与谁相邻），并裁决位置合法性（一格至多一个单位，越界与占用格不可进入）。**"相邻"的几何定义由本系统唯一拥有**——相邻羁绊、战斗解算、敌人 AI 全部引用本系统的判定，不得自行实现几何。它自身不含玩法规则：移动消耗行动、攻击造成伤害、相邻触发羁绊都归下游系统；本系统只回答"空间上是否成立"。玩家从不直接感知"棋盘系统"，但每一次站位权衡——安全格还是羁绊格——都发生在它划定的几何里；没有它，四个下游系统会各自发明互相矛盾的距离与相邻算法。逻辑格坐标与 3D 低模舞台世界坐标的映射属实现层（→ becomes an ADR），本文档只定义逻辑格行为。

## Player Fantasy

玩家不会说"我喜欢这个棋盘系统"——他们会说"**我喜欢每一步都有讲究**"。本系统服务的幻想是间接的：它让"站位"成为一个值得反复咀嚼的决策。支柱原文："**羁绊即战术**——你的战术语言不是技能栏，而是棋盘上的几何关系"；"**小棋盘大组合**——8×8 的方寸之间，每一格都承载选择的重量"。这两句话能否兑现，取决于本系统的几何是否**绝对可信**：玩家俯瞰棋盘的瞬间就该读懂"谁挨着谁、谁够得到谁、我能走到哪"——零歧义、零惊讶。一次相邻判定与玩家直觉不符（"他们明明挨着，为什么羁绊没亮？"），战术幻想就碎一次。因此本系统的体验目标是**隐形**：规则简单到玩家从不思考规则本身，全部心智都花在规则之上的组合谋划里。参照系是国际象棋的棋盘——没人讨论它，所有人都在它上面思考。

**情感反例**（设计红线）：玩家感到"被棋盘背叛"——可达范围预览与实际可走不一致、相邻定义在不同系统间不统一。这类瞬间产生的不是挑战感而是不信任，直接违背"计算得到热血回报"的核心假设。

> *creative-director 未参与本节起草 — Lean mode。生产前请人工复核。*

## Detailed Design

### Core Rules

1. **棋盘几何**
   - 8 行 × 8 列逻辑格；坐标为 `(col, row)`，均从 0 起（`(0,0)` 到 `(7,7)`）
   - 坐标系唯一，全部下游系统引用同一份；逻辑格 ↔ 3D 世界坐标映射为实现层关切（→ 独立 ADR）

2. **占用规则**
   - 一格至多一个单位；`OCCUPIED` 格、`TERRAIN_BLOCKED` 格、越界格均不可进入
   - Downed 单位立即移出棋盘，其格子变为 `EMPTY`，**不阻挡**穿越

3. **相邻定义（八向）**
   - 两格**相邻**当且仅当切比雪夫距离 = 1：`max(|Δcol|, |Δrow|) = 1`
   - 八个方向，含四角斜格；一格最多 8 个邻格（角格 3 个，边格 5 个，内格 8 个）
   - **本系统是"相邻"的唯一权威**；羁绊系统、AI 全部调用本系统接口，不得自行实现

4. **攻击距离**
   - **近战（`attack_range = 1`）**：使用**切比雪夫距离** ≤ 1，与相邻定义完全对齐——可攻击八向所有邻格
   - **远程（`attack_range ≥ 2`）**：使用**曼哈顿距离** ≤ `attack_range`，攻击覆盖菱形区域
   - 全系统两套度量：近战与相邻触发羁绊共用切比雪夫；移动步数与远程攻击共用曼哈顿——各自内部一致，无跨度量歧义

5. **移动范围**
   - BFS 展开，以 `move_range`（1–4）为步数上限
   - 障碍格、`OCCUPIED` 格不可穿越；越界视作障碍
   - Downed 单位的格子可穿越（已为 `EMPTY`）

6. **部署限制**
   - `DEPLOY_LIMIT = 4`：同时在场的己方单位上限；部署区格位由战斗地图系统指定，本系统验证是否合法（`EMPTY` + 在部署区内）

7. **地形**
   - 每格可附带地形属性：`NONE`、`BLOCKED`、`COVER`（可拓展）
   - 地形属性由本系统维护；初始布局由**战斗地图系统（#10）** 加载时写入

### States and Transitions

**格子状态**

| 状态 | 描述 | 可进入 |
|---|---|---|
| `EMPTY` | 空，无占用，无地形 | ✅ |
| `OCCUPIED(unit_id)` | 被单位占用 | ❌ |
| `TERRAIN_BLOCKED` | 地形阻挡（墙/障碍） | ❌ |
| `TERRAIN_MODIFIED(type)` | 地形修饰（如 COVER），可进入但附属性 | ✅ |

**单位棋盘状态**

| 状态 | grid_position | 触发条件 |
|---|---|---|
| `OFF_BOARD` | null | 未部署 / Downed 后 |
| `ON_BOARD` | `(col, row)` | 部署或移动后 |

**主要转换**

- **移动**：`EMPTY[目标] → OCCUPIED`；原格 `OCCUPIED → EMPTY`；单位 `grid_position` 更新
- **击倒**：原格 `OCCUPIED → EMPTY`（立即）；单位 `ON_BOARD → OFF_BOARD`，`grid_position = null`
- **部署**：单位 `OFF_BOARD → ON_BOARD`；目标格必须 `EMPTY` 且在部署区；`EMPTY → OCCUPIED`

### Interactions with Other Systems

| 调用方 | 接口 | 说明 |
|---|---|---|
| 羁绊系统 | `get_adjacents(pos) → Array[unit_id]` | 八向邻格的占用单位列表 |
| 战斗解算系统 | `in_attack_range(a, b, range) → bool` | 攻击距离裁决（近战切比雪夫/远程曼哈顿） |
| 战斗解算系统 | `get_cells_in_attack_range(pos, range) → Array[Vector2i]` | 从 pos 可攻击的格子集合（内聚查询，AI 与战斗均可用） |
| 回合管理系统（移动） | `get_reachable_cells(pos, move_range) → Array[Vector2i]` | 4向BFS 可达格集合 |
| 回合管理系统（移动） | `get_path_to(start, goal) → Array[Vector2i]` | 从 start 到 goal 的最短移动路径（BFS 前驱字典复用） |
| 敌人 AI | `get_attack_staging_cells(mover_pos, move_range, target_pos, attack_range) → Array[Vector2i]` | 可移动到并攻击目标的格子集合（一次 BFS + 过滤，AI 侧零嵌套） |
| 敌人 AI | 上述所有接口 | 不得自行实现几何逻辑 |
| 单位数据系统 | 读取 `UnitInstance.grid_position` | 棋盘是唯一写入方 |
| 战斗地图系统（部署） | `get_deploy_zone_available() → Array[Vector2i]` | 部署区内可用空格列表 |
| 战斗地图系统 | 写入初始地形 | 加载时调用 `set_terrain(pos, type)` |

## Formulas

### 变量定义

| 变量 | 类型 | 取值范围 | 说明 |
|---|---|---|---|
| `pos` | `Vector2i(col, row)` | col, row ∈ [0, 7] | 逻辑格坐标 |
| `A`, `B` | `Vector2i` | — | 任意两格坐标 |
| `move_range` | `int` | 1–4 | 单位移动步数上限（来自 UnitInstance） |
| `attack_range` | `int` | 1–4 | 单位攻击距离上限（来自 UnitInstance） |

### 公式 1：越界检查

```
in_bounds(pos) = (0 ≤ pos.col ≤ 7) AND (0 ≤ pos.row ≤ 7)
```

⚠️ **前置约束**：`pos` 坐标必须为整数；传入浮点数为调用方 bug，行为未定义。

示例：`(0,0)` → true；`(8,3)` → false

### 公式 2：切比雪夫距离 / 相邻判定

```
chebyshev(A, B) = max(|A.col - B.col|, |A.row - B.row|)
adjacent(A, B)  = (chebyshev(A, B) == 1)
```

示例：A=(3,3), B=(4,4) → chebyshev=1 → **相邻**（斜格）  
示例：A=(3,3), B=(5,3) → chebyshev=2 → **不相邻**

### 公式 3：攻击范围判定（双度量）

⚠️ **此处度量由 `attack_range` 值决定，与移动 BFS 无关：**

**近战（`attack_range = 1`）——切比雪夫判定（与相邻定义完全对齐）：**

```
in_attack_range_melee(A, B) = (chebyshev(A, B) == 1)    // 即 adjacent(A, B)
```

**远程（`attack_range ≥ 2`）——曼哈顿判定：**

```
manhattan(A, B)              = |A.col - B.col| + |A.row - B.row|
in_attack_range_ranged(A, B) = (manhattan(A, B) ≤ attack_range)
```

**统一签名：**

```
in_attack_range(A, B, range):
  if range == 1: return chebyshev(A, B) <= 1
  else:          return manhattan(A, B) <= range
```

⚠️ **对称性**：两套度量均对称——`in_attack_range(A,B) == in_attack_range(B,A)` 恒成立（方向约束如有需要，归战斗解算 GDD）。

示例：A=(3,3), B=(4,4), range=1 → chebyshev=1 ≤ 1 → **在攻击范围内**（近战可攻斜格 ✓）  
示例：A=(3,3), B=(4,4), range=2 → manhattan=2 ≤ 2 → **在攻击范围内**  
示例：A=(3,3), B=(5,3), range=1 → chebyshev=2 > 1 → **不在攻击范围**

攻击自身：range=1 时 chebyshev(A,A)=0，`in_attack_range_melee` 返回 false（不满足 ==1）；自身攻击豁免由战斗解算上层保证，棋盘系统不另处理。

### 公式 4：BFS 可达格集合（4 向移动）

```
reachable(start, move_range):
  visited = {start: 0}      // pos → 已用步数
  queue   = [start]
  result  = [start]         // 起点始终包含在结果集内
  while queue not empty:
    pos = dequeue(queue)
    for each neighbor in [上, 下, 左, 右]:   // 4 向，含斜格的格子需绕路
      if not in_bounds(neighbor): skip
      if is_movement_blocked(neighbor): skip
      steps = visited[pos] + 1
      if steps > move_range: skip
      if neighbor not in visited:
        visited[neighbor] = steps
        enqueue(queue, neighbor)
        result.append(neighbor)
  return result

is_movement_blocked(pos):
  if terrain[pos] == TERRAIN_BLOCKED: return true
  if pos is OCCUPIED by ally unit: return true   // 友方格：完全阻断
  if pos is OCCUPIED by enemy unit: return true  // 敌方格：不可穿越（可作攻击目标，但非可达格）
  return false
```

示例：move_range=2，无障碍 → 菱形区域，最多 1+4+8=13 格（含起点）  
示例：move_range=1 → 上下左右最多 4 格 + 起点，共最多 5 格

⚠️ **每格移动代价假设为 1**（无加权地形）：此 BFS 不适用于含地形移动代价的场景；如未来引入代价地形须改用 Dijkstra。

⚠️ **敌方格的攻击目标性 ≠ 移动可达性**：`is_movement_blocked` 阻止进入敌方格，但不阻止攻击——战斗系统通过 `in_attack_range` 独立判定是否可攻击，与移动可达无关。

## Edge Cases

| 情形 | 处理规则 |
|---|---|
| **移动目标 = 当前位置** | 合法（原地不动），消耗行动但不改变棋盘状态 |
| **move_range = 0** | `reachable` 返回仅含起点的集合；单位无法移动 |
| **单位被击倒时恰好有另一单位将移动至同格** | 先处理击倒（格子变 EMPTY），再处理移动——时序由回合系统保证，棋盘系统不需感知 |
| **部署时部署区已被全部占用** | 部署操作被拒绝，返回空可用格集合；战斗系统负责处理此状态 |
| **DEPLOY_LIMIT = 4 已满时尝试再部署** | 棋盘系统直接拒绝，不修改任何状态 |
| **地形格被击倒单位占用**（不可能情形） | TERRAIN_BLOCKED 格不可进入，故此情形不应发生；防御性断言即可 |
| **两格坐标相同传入 adjacent()** | `chebyshev(A,A)=0 ≠ 1` → 返回 false（一格不与自身相邻） |
| **两格坐标相同传入 manhattan()** | 返回 0；攻击自身由战斗系统上层禁止，棋盘系统不特殊处理 |
| **近战攻击范围与羁绊范围重叠** | 两者均为切比雪夫=1（八向），高亮完全对齐——无视觉混淆；UI 无需区分两种高亮 |
| **BFS 中障碍格将可达区域分割成孤岛** | 合法结果，BFS 自然处理；无法到达的格子不进入 result |
| **角格/边格的相邻数量不足 8** | 合法，`get_adjacents` 只返回存在且在棋盘内的邻格，调用方不假设固定数量 |

## Dependencies

**本系统依赖（输入方）**

| 系统 | 依赖内容 | 方向 |
|---|---|---|
| 单位数据系统（#1） | `UnitInstance.grid_position`、`move_range`、`attack_range` | 读取 |
| 战斗地图系统（#10） | 初始地形布局（`set_terrain` 调用） | 被调用 |

**本系统被依赖（输出方）**

| 系统 | 使用接口 |
|---|---|
| 羁绊系统 (#5) | `get_adjacents(pos)` |
| 战斗解算系统 (#4) | `in_attack_range(a,b,range)`、`get_cells_in_attack_range(pos,range)` |
| 回合管理系统 (#3)（移动） | `get_reachable_cells(pos, move_range)`、`get_path_to(start, goal)` |
| 战斗地图系统 (#10)（部署） | `get_deploy_zone_available()` |
| 敌人 AI 系统 (#7) | `get_attack_staging_cells(...)`、上述所有查询接口 |
| 回合管理系统 (#3) | `place_unit`、`remove_unit`（击倒时） |

## Tuning Knobs

| 参数 | 当前值 | 安全调整范围 | 影响 |
|---|---|---|---|
| `BOARD_SIZE` | 8×8 | 6×6 – 10×10 | 棋盘尺寸；低于 6×6 单位过度拥挤，高于 10×10 羁绊机会稀少 |
| `DEPLOY_LIMIT` | 4 | 3 – 6 | 同时在场友方单位上限；低于 3 羁绊链无法形成，高于 6 棋盘过于拥挤 |
| `move_range`（per unit） | 1–4 | 1–4 | 通过 unit-data-system 调整，不在本系统硬编码 |
| `attack_range`（per unit） | 1–4 | 1–4 | 同上 |
| 地形密度（BLOCKED 格比例） | 由地图决定 | 0%–25% | 超过 25% 棋盘会严重割裂可达区域；低于 10% 无战术地形意义 |

## Visual/Audio Requirements

- 可达格高亮：统一颜色叠加层（蓝色系），由移动系统触发，棋盘系统只提供格子集合
- 攻击范围高亮：独立颜色（红色系），与可达格高亮不重叠显示
- 相邻羁绊高亮：第三种颜色（金色系），区分于移动/攻击范围
- 地形格视觉：`TERRAIN_BLOCKED` 由战斗地图系统提供美术资源，棋盘系统不参与渲染
- 无专属音效：格子状态变化不产生音效，上层系统负责移动音效

## UI Requirements

- 棋盘系统**不持有任何 UI 节点**，所有视觉反馈通过信号通知上层
- 需要暴露的信号：`unit_placed(unit_id, pos)`、`unit_removed(unit_id, pos)`、`terrain_changed(pos, type)`、`unit_moved(unit_id, from_pos, to_pos)`（玩家或 AI 成功移动单位后 emit，供 HUD 更新 has_moved 行动 pip；仅在移动实际发生时 emit，移动失败/无效不 emit）
- 格子坐标与屏幕坐标映射为实现层关切（→ ADR），本文档不规定

## Acceptance Criteria

> *起草：qa-lead — Lean mode。*

**AC-01 越界检查：有效格坐标** 【单元测试】
- **Given** 棋盘已初始化（8×8）
- **When** 调用 `in_bounds(Vector2i(0,0))`、`in_bounds(Vector2i(7,7))`、`in_bounds(Vector2i(3,5))`
- **Then** 三次调用均返回 `true`

**AC-02 越界检查：边界外坐标** 【单元测试】
- **Given** 棋盘已初始化（8×8）
- **When** 分别调用 `in_bounds(Vector2i(-1,0))`、`in_bounds(Vector2i(8,0))`、`in_bounds(Vector2i(0,8))`、`in_bounds(Vector2i(4,-1))`
- **Then** 四次调用均返回 `false`

**AC-03 相邻判定：正交与斜向均视为相邻** 【单元测试】
- **Given** 棋盘已初始化
- **When** 以 A=`(3,3)` 为基准，B 取正上 `(3,2)`、正右 `(4,3)`、右下斜 `(4,4)`、左上斜 `(2,2)`
- **Then** 四次 `adjacent(A, B)` 均返回 `true`

**AC-04 相邻判定：距离大于 1 的格不相邻** 【单元测试】
- **Given** 棋盘已初始化
- **When** 调用 `adjacent(Vector2i(0,0), Vector2i(2,0))` 和 `adjacent(Vector2i(0,0), Vector2i(2,2))`
- **Then** 两次调用均返回 `false`

**AC-05 曼哈顿距离计算正确性** 【单元测试】
- **Given** 棋盘已初始化
- **When** 调用 `manhattan(Vector2i(1,1), Vector2i(4,5))`；并调用 `manhattan(Vector2i(0,0), Vector2i(0,0))`
- **Then** 分别返回 `7` 和 `0`

**AC-06 占用规则：向 OCCUPIED 格放置单位被拒绝** 【单元测试】
- **Given** 格 `(2,2)` 已放置单位 A（状态 OCCUPIED）
- **When** 尝试将单位 B 放置到 `(2,2)`
- **Then** 放置操作返回失败，`(2,2)` 占用单位仍为 A，格状态不变

**AC-07 占用规则：向 TERRAIN_BLOCKED 格放置单位被拒绝** 【单元测试】
- **Given** 格 `(5,5)` 地形为 `TERRAIN_BLOCKED`
- **When** 尝试将任意单位放置到 `(5,5)`
- **Then** 放置操作返回失败，格状态保持 `TERRAIN_BLOCKED`

**AC-08a Downed 单位移出后格子变 EMPTY** 【单元测试】
- **Given** 单位 A 位于 `(3,3)`，格状态为 OCCUPIED
- **When** 将单位 A 标记为 Downed 并触发移出
- **Then** `(3,3)` 格状态立即变为 `EMPTY`；`unit_removed` 信号触发，携带位置 `(3,3)`

**AC-08b EMPTY 格（原 Downed 位置）不阻挡后续 BFS** 【集成测试】
- **Given** AC-08a 已执行，`(3,3)` 为 EMPTY
- **When** 为单位 B 调用 `get_reachable_cells(Vector2i(3,2), 2)`
- **Then** 可达集合包含 `(3,3)`（路径：(3,2)→(3,3)，1步）和 `(3,4)`（路径：(3,2)→(3,3)→(3,4)，2步）

**AC-09 4 向 BFS：起点包含 + 完整 13 格** 【单元测试】
- **Given** 棋盘全格均为 EMPTY，无单位
- **When** 调用 `get_reachable_cells(Vector2i(3,3), 2)`
- **Then** 返回集合恰好包含以下 13 格：
  - 起点：`(3,3)`
  - 曼哈顿距离 1：`(3,2)` `(3,4)` `(2,3)` `(4,3)`
  - 曼哈顿距离 2：`(3,1)` `(3,5)` `(1,3)` `(5,3)` `(2,2)` `(4,4)` `(2,4)` `(4,2)`
  - 不含 `(5,5)`（曼哈顿距离 4，超出范围）

**AC-10 4 向 BFS：障碍格阻断路径** 【集成测试】
- **Given** `(3,4)` 为 `TERRAIN_BLOCKED`，`(3,5)` 为 EMPTY
- **When** 调用 `get_reachable_cells(Vector2i(3,3), 3)`
- **Then** 返回集合不含 `(3,4)`，且不含 `(3,5)`（被障碍切断的纵向路径终止）

**AC-11 DEPLOY_LIMIT：第 5 个单位部署被拒绝** 【集成测试】
- **Given** 已成功部署 4 个单位（部署数 = 4）
- **When** 尝试部署第 5 个单位到任意合法空格
- **Then** 第 5 次部署返回失败，棋盘上单位总数仍为 4

**AC-12 信号 `unit_placed` 在放置单位后触发** 【单元测试】
- **Given** 测试监听器已连接 `unit_placed` 信号，格 `(1,1)` 为 EMPTY
- **When** 成功将单位放置到 `(1,1)`
- **Then** `unit_placed` 触发恰好 1 次，携带位置参数 `(1,1)`

**AC-13 信号 `unit_removed` 在单位移出后触发** 【单元测试】
- **Given** 测试监听器已连接 `unit_removed` 信号，单位 A 位于 `(2,4)`
- **When** 将单位 A 从棋盘移出（含 Downed 触发的移出）
- **Then** `unit_removed` 触发恰好 1 次，携带位置参数 `(2,4)`

**AC-14 信号 `terrain_changed` 在地形变更后触发** 【单元测试】
- **Given** 测试监听器已连接 `terrain_changed` 信号，格 `(6,6)` 当前地形为 EMPTY
- **When** 将 `(6,6)` 地形更改为 `TERRAIN_BLOCKED`
- **Then** `terrain_changed` 触发恰好 1 次，携带参数含位置 `(6,6)` 及新地形类型 `TERRAIN_BLOCKED`

**AC-15 相邻判定：一格不与自身相邻** 【单元测试】
- **Given** 棋盘已初始化
- **When** 调用 `adjacent(Vector2i(3,3), Vector2i(3,3))`
- **Then** 返回 `false`（chebyshev=0 ≠ 1）

**AC-16 BFS：OCCUPIED 格既不可进入也不可穿越** 【集成测试】
- **Given** 单位 X 位于 `(3,4)`（OCCUPIED），`(3,5)` 为 EMPTY
- **When** 调用 `get_reachable_cells(Vector2i(3,3), 3)`
- **Then** 可达集合不含 `(3,4)`（不可进入），且不含 `(3,5)`（被 OCCUPIED 格切断的纵向路径终止）

**AC-17 BFS：move_range=0 只返回起点** 【单元测试】
- **Given** 棋盘全格均为 EMPTY
- **When** 调用 `get_reachable_cells(Vector2i(4,4), 0)`
- **Then** 返回集合恰好包含 1 格：起点 `(4,4)`

## Open Questions

1. **逻辑格 ↔ 3D 世界坐标映射**：等轴测还是正交投影？格子尺寸？→ 独立 ADR，生产前必须裁决
2. **`is_movement_blocked` 敌我区分细节**：敌方格目前定义为"不可穿越"——是否允许特定职业穿越敌方格（如影刺型）？→ 移动系统 GDD 裁决，棋盘系统预留接口参数
