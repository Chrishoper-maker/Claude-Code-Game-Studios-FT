# 战斗地图系统 (Battle Map System)

> **Status**: Approved
> **Author**: user + agents (autonomous)
> **Last Updated**: 2026-06-17
> **Implements Pillar**: 羁绊即战术（地形作为战术变量）；小棋盘大组合（地图多样性放大元素互动）；十分钟一场爽局（波次规模约束战斗长度）

## Overview

战斗地图系统是《孤帆棋海》每场战斗的"场景定义层"——它加载地形、部署敌方单位、划定玩家部署区，并把这些信息交给下游系统使战斗得以开始。每张战斗地图是一份静态数据资源（MapDefinition），包含：地形格阵列（哪些格子是障碍/掩体）、敌方波次定义（哪些敌人、部署在哪里、使用哪种行为原型、驻守型的 home_pos）、以及玩家部署区格子集合。地图系统在战斗开始时依次执行：①将地形写入网格棋盘；②为每个敌方单位实例化 UnitInstance 并写入 behavior_type 和 home_pos；③将敌方单位部署到棋盘；④对外暴露部署区供玩家放置船员。**本系统是修复远程职业身份的主要工具**（原型课题）：地形设计直接影响交战距离经济，地图即平衡，须遵守严格的设计约束（最小分离距离 ≥ 3、地形密度 ≤ 25%、远程走廊设计规范）。

## Player Fantasy

玩家看到地形后，第一个念头不是"这张地图好难"，而是"嘿，这有意思"。

地形是游戏的第三维度——前两维是职业选择和站位充能，第三维是地图给出的这道题的形状。一张有窄道的地图让铁壁的阻截价值倍增；一张有掩体走廊的地图让炮手能蛰伏角落、把三格长管指向出口候命；一张开阔地图让航海士的强制位移能把敌人推进险境。玩家不是在被动承受地形，而是在把地形当作自己的工具。

这是支柱"**羁绊即战术**"与"**小棋盘大组合**"的融合点：地形不增加规则，它只改变几何，但改变几何就改变了所有羁绊效果的价值排序——同样一对炮手+航海士，在开放地图是弱组合，在有走廊的地图是最强组合。每场战斗的独特地形使"最优阵容"这个问题本身随之改变，重玩才有意义。

## Detailed Design

### Core Rules

**Rule 1：MapDefinition 数据结构**

每张地图是一份静态数据资源，包含以下字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `map_id` | String | 蛇形命名唯一标识（如 `battle_map_001`） |
| `display_name` | String | 玩家可见地图名（如"狭窄港湾"） |
| `terrain_data` | Array[{pos: Vector2i, terrain_type: String}] | 仅列出非 EMPTY 格；`terrain_type` ∈ {"BLOCKED", "COVER"} |
| `deploy_zone` | Array[Vector2i] | 玩家可放置船员的候选格集合（含被地形覆盖的格，加载时过滤） |
| `enemy_roster` | Array[EnemySlotDefinition] | 见 Rule 2 |
| `island_tier` | int | 适用岛屿槽位 ∈ {1,2,3,4,5,6}；航线与招募系统按此筛选 |
| `annotated_engagement_distance` | {min: int, max: int} | 设计师标注的预期交战曼哈顿距离带；供平衡审查参考，不参与代码校验 |
| `map_scene_id` | String or null | 3D 场景资源引用；MVP 白盒阶段为 null，使用占位网格 |

**Rule 2：EnemySlotDefinition 结构**

```
EnemySlotDefinition:
  unit_definition_id: String   // 引用 EnemyDefinition.id（来自 unit-data-system）
  grid_position: Vector2i      // 敌方单位的初始部署格
  behavior_type: String        // "MELEE" / "RANGED" / "GUARDIAN" / "SWARMER"
  home_pos: Vector2i           // 驻守型（GUARDIAN）的守卫格；非守卫型设为 Vector2i(-1,-1)
```

`behavior_type` 和 `home_pos` 是地图层的设计决策，不从 EnemyDefinition 读取——同一敌人定义可在不同地图中扮演不同行为原型。这使地图设计师拥有完整的敌方配置自主权。

**视觉区分义务**：当同一 unit_definition_id 在不同地图中被分配不同 behavior_type 时，HUD 系统须在棋盘上为敌方单位叠加行为类型图标（如 MELEE=剑图标，RANGED=弓图标，GUARDIAN=盾图标，SWARMER=群图标），使玩家无需记忆即可识别当前行为模式。具体视觉规范归战斗 HUD 系统 (#9) GDD 负责。

**Rule 3：地图加载序列**

收到 `map_load_requested(map_id)` 后按以下顺序执行：

1. **验证阶段**（**短路顺序执行**——按 ① 至 ⑨ 顺序检查；任一失败则立即 emit map_load_failed 并终止，不执行后续检查，不修改棋盘状态）：
   - ① 地形密度 ≤ TERRAIN_DENSITY_MAX（Formulas F1）
   - ② 敌方数量在 [ENEMY_COUNT_MIN, ENEMY_COUNT_MAX] 内（Formulas F3）
   - ③ 敌方起始格之间无位置冲突
   - ④ 所有敌方起始格不在 terrain_data 的 BLOCKED 格中
   - ⑤ 部署区扣除 BLOCKED 重叠后有效格数 ≥ DEPLOY_ZONE_MIN_CELLS（Formulas F2）**← 必须先于 ⑥ 执行；F2 失败意味着有效部署格集合 D 可能为空，空集合传入 F4 的 min() 会产生未定义行为**
   - ⑥ 最小分离距离 ≥ MAP_SEPARATION_MIN（Formulas F4）**← 依赖 D 非空，由 ⑤ 保证；实现层加 guard：`if D.is_empty(): return FAIL` 作为防御性断言**
   - ⑦ 所有 unit_definition_id 在 unit-data-system 中存在
   - ⑧ 所有敌方单位的 threat_tier 符合 island_tier 允许范围（Formulas F5）
   - ⑨ 地图包含至少一条合法远程走廊（Formulas F6）

2. **地形写入**：遍历 `terrain_data`，对每格调用 `grid_board.set_terrain(pos, terrain_type)`

3. **敌方部署**：遍历 `enemy_roster`，对每个 EnemySlotDefinition：
   a. 从 unit-data-system 加载对应 EnemyDefinition（by unit_definition_id）
   b. 生成 UnitInstance（`current_hp = max_hp`，`has_moved/has_acted = false`，有职业动词时 `has_used_verb = false`）
   c. 写入 `unit_instance.behavior_type = slot.behavior_type`
   d. 写入 `unit_instance.home_pos = slot.home_pos`
   e. 调用 `grid_board.place_unit(unit_instance, slot.grid_position)`

4. **注册部署区**：将 deploy_zone 扣除 BLOCKED 重叠格后存储为 `_valid_deploy_cells`

5. **完成信号**：emit `map_loaded(map_id)`；系统状态转为 MAP_READY

**Rule 4：部署区查询接口**

本系统是 `get_deploy_zone_available` 接口的**唯一所有者**。签名：

`get_deploy_zone_available(occupied_cells: Array[Vector2i] = []) → Array[Vector2i]`

- **返回值** = `_valid_deploy_cells`（加载时存储的地图级有效部署格，已扣除 BLOCKED 重叠）减去 `occupied_cells` 参数中的格子。
- **调用方职责**：棋盘系统或回合管理在查询玩家可放置格时，将当前已被 place_unit 占用的格集合作为参数传入；若无需实时过滤（如加载后静态查询），传入空数组即可（默认值）。
- **棋盘系统无独立副本**：grid-board-system GDD 中对"部署区查询"的引用含义是调用本接口，棋盘系统不另行维护部署区数据。"两个系统共同提供答案"的旧说法已废弃——本系统是唯一事实源。

**Rule 5：远程职业身份保护——地图设计约束**

以下约束是地图作者必须遵守的设计规范。**约束 A（F4）、约束 B（F6）、约束 C（F1）均由系统在加载时硬性校验**；约束 D 为设计师规范（重叠超出容忍阈值才报错）：

- **约束 A（分离保证——系统校验 F4）**：所有敌方起始格与最近部署区格的曼哈顿距离 ≥ MAP_SEPARATION_MIN = 3。原型问题：炮手 range=3，tier-1 敌方 move=2，enemy 从 distance=2 处一步到近战 → 炮手无效窗口。分离≥3 确保炮手第 1 回合即可射击，敌方至少 2 回合才能近战
- **约束 B（远程走廊——系统校验 F6）**：每张地图须包含至少一条合法**远程走廊**（精确定义见公式 F6）。走廊是地形修复炮手身份的核心工具：迫使 MELEE 敌人绕路（有效旅行距离 +2），炮手输出窗口从 1 回合扩展至 3 回合。不满足则加载失败（reason="no_ranged_corridor"）
- **约束 C（地形密度——系统校验 F1）**：TERRAIN_BLOCKED 格 ≤ 25%（≤ 16 格），避免棋盘过度割裂
- **约束 D（部署区隔离——设计师规范）**：deploy_zone 格尽量不与 terrain_data BLOCKED 格重叠；重叠后有效格数 < DEPLOY_ZONE_MIN_CELLS 才触发加载失败（F2 校验）

**Rule 6：地图池与选择**

- **MVP**：唯一固定地图 `battle_map_001`（白盒场景），所有战斗请求均加载此地图。MVP 验证"地形能否延长炮手输出窗口"假设；"不同地图产生不同最优羁绊组合"假设推迟至 Alpha 阶段（至少 3 张对照地图）验证。
- **垂直切片**：5–8 张手工设计地图，每张标注 `island_tier`；各 island_tier 至少 1 张。**地图多样性假设须在此阶段验证**：至少 2 张不同地形结构的地图形成对照，可观测到玩家阵容选择随地形改变。
- 航线与招募系统调用 `get_map_for_island(island_index) → MapDefinition`；本系统从匹配 `island_tier` 的地图池中返回（随机抽取或固定序列由 OQ-3 决定）

#### `battle_map_001` 草案布局（关闭 OQ-1）

```
     C0  C1  C2  C3  C4  C5  C6  C7
R0:  ·   ·   M   ·   ·   ·   ·   R
R1:  ·   ■   ·   ·   ·   ■   ·   ·
R2:  ·   ■   ·   ·   ·   ■   ·   ·
R3:  ·   ·   ·   S   ·   ·   ·   G
R4:  ·   ·   ·   ·   ·   ·   ·   ·
R5:  ·   ·   ·   ·   ·   ·   ·   ·
R6:  D   D   D   D   D   D   ·   ·
R7:  D   D   D   D   D   D   ·   ·

图例：■=TERRAIN_BLOCKED  M=MELEE(2,0)  R=RANGED(7,0)
      S=SWARMER(3,3)    G=GUARDIAN(7,3)  D=deploy_zone
```

| 字段 | 值 |
|------|-----|
| `map_id` | `"battle_map_001"` |
| `display_name` | `"狭窄港湾"` |
| `island_tier` | `1` |
| `map_scene_id` | `null`（MVP 白盒） |
| `terrain_data` | BLOCKED: (1,1),(1,2),(5,1),(5,2)；`n_blocked=4` |
| `deploy_zone` | rows 6–7 × cols 0–5，共 12 格；无 BLOCKED 重叠 |

| 行为原型 | unit_definition_id（占位） | grid_position | home_pos |
|----------|--------------------------|---------------|----------|
| MELEE | `enemy_melee_tier1` | (2,0) | (-1,-1) |
| RANGED | `enemy_ranged_tier1` | (7,0) | (-1,-1) |
| SWARMER | `enemy_swarmer_tier1` | (3,3) | (-1,-1) |
| GUARDIAN | `enemy_guardian_tier1` | (7,3) | (7,3) |

**验证通过确认**（F1–F6 全部满足）：
- F1：n_blocked=4，6% ≤ 25% ✓
- F2：n_deploy=12 ≥ 6 ✓
- F3：n_enemies=4 ∈ [2,6] ✓
- F4：最小分离 = SWARMER(3,3)→deploy(3,6)，manhattan=3 = MAP_SEPARATION_MIN ✓
- F5：island_tier=1，所有敌人 threat_tier=1 ∈ {1} ✓
- F6：列 C0（rows 0–7 全非 BLOCKED，长度 8）+ C0 为左边界列 → 远程走廊成立 ✓

**设计意图**：
- **左翼走廊（C0 列）**：C0 全列无障碍，紧贴左边界——玩家炮手可沿 C0 列纵深机动，MELEE 敌人若要追击须绕过 (1,1)(1,2) 的阻隔，有效绕路 ≥2 格，延长炮手输出窗口
- **中央沙漏（双侧 BLOCKED）**：(1,1)(1,2) 和 (5,1)(5,2) 收窄中路，使 MELEE 和 SWARMER 必须通过窄口进入，产生自然伏击点
- **右翼固守（GUARDIAN + RANGED 敌）**：GUARDIAN 驻守 (7,3) 控制右翼；RANGED 敌从 (7,0) 保距输出，形成两线压力
- **SWARMER 中场压迫**：(3,3) 距部署区恰好 3 格（最小分离下界），第 1 回合即可接近，制造早期威胁

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| `MAP_UNLOADED` | 无地图数据，棋盘为默认空状态 | 初始化；上一场战斗结束后重置 | 收到 `map_load_requested` |
| `MAP_VALIDATING` | 正在校验 MapDefinition 数据 | `map_load_requested` 收到 | 验证通过 → `MAP_LOADING`；验证失败 → `MAP_UNLOADED` |
| `MAP_LOADING` | 正在写地形 + 部署敌方单位 | 验证通过 | 加载完成 → `MAP_READY` |
| `MAP_READY` | 地形已写入，敌方已部署，等待玩家放置船员 | 加载完成，`map_loaded` 已 emit | 收到 `battle_started`（回合管理） |
| `MAP_ACTIVE` | 战斗进行中，地图系统处于监听态 | `battle_started` 信号 | `battle_won` 或 `battle_lost` → `MAP_RESOLVED` |
| `MAP_RESOLVED` | 战斗结束，等待外部重置信号 | `battle_won` 或 `battle_lost` 信号 | 收到 `map_reset_requested` → 执行清理（清空 `_valid_deploy_cells`、地形、已部署单位引用）→ `MAP_UNLOADED` |

### Interactions with Other Systems

| 系统 | 接口 / 信号 | 方向 | 说明 |
|------|------------|------|------|
| 网格棋盘系统 (#2) | `set_terrain(pos, terrain_type)` | 调用 | 地图加载时写入地形；本系统是初始地形的唯一写入者 |
| 网格棋盘系统 (#2) | `place_unit(unit_instance, pos) → bool` | 调用 | 将敌方 UnitInstance 部署到指定格；失败（格被占）视为结构错误 |
| 单位数据系统 (#1) | 读取 EnemyDefinition（by unit_definition_id） | 读取 | 生成敌方 UnitInstance 的数据来源；单位数据 GDD 的 fail-fast 保证数据结构合法 |
| 单位数据系统 (#1) | 写入 UnitInstance.behavior_type, .home_pos | 写入 | 部署时赋值，supply enemy AI 运行时读取；字段定义归 unit-data-system，写入权归本系统 |
| 敌人 AI 与意图系统 (#7) | UnitInstance.behavior_type, .home_pos（被读取） | 下游合同 | AI 在 ROUND_START 时读取这两个字段；本系统在部署阶段写入，确保 AI 初始化前字段已就位 |
| 回合管理系统 (#3) | `map_loaded(map_id)` | 发出信号 | 通知回合管理地图就绪；回合管理系统开始玩家部署阶段 |
| 回合管理系统 (#3) | `battle_started()` | 接收信号 | 系统进入 MAP_ACTIVE 状态 |
| 回合管理系统 (#3) | `battle_won()` / `battle_lost()` | 接收信号 | 系统进入 MAP_RESOLVED 状态 |
| 回合管理系统 (#3) / 航线系统 (#11) | `map_reset_requested()` | 接收信号 | **触发 MAP_RESOLVED→MAP_UNLOADED 转换**；发射方：MVP 阶段由回合管理系统在战斗结算完成后发出，垂直切片阶段改由航线与招募系统负责（run 流程接管后）；收到后本系统清空 `_valid_deploy_cells`、通知 grid_board 清除地形与单位、状态转 MAP_UNLOADED |
| 航线与招募系统 (#11) | `get_map_for_island(island_index) → MapDefinition` | 提供接口 | 垂直切片阶段按岛屿槽位返回地图定义；MVP 阶段此接口始终返回 battle_map_001 |
| 战斗 HUD 系统 (#9) | `display_name`（从 MapDefinition 读取） | 提供数据 | HUD 可读取地图显示名用于战前信息展示 |

## Formulas

### 变量定义

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `n_blocked` | int | 0–64 | 地图 terrain_data 中 TERRAIN_BLOCKED 格总数 |
| `n_deploy` | int | 0–64 | deploy_zone 扣除与 BLOCKED 重叠格后的有效数量 |
| `n_enemies` | int | 0–10 | enemy_roster 中 EnemySlotDefinition 总数 |
| `E` | set of Vector2i | — | 所有 EnemySlotDefinition.grid_position 的集合 |
| `D` | set of Vector2i | — | 有效部署区格集合（扣除 BLOCKED 重叠后） |

### 公式 F1：地形密度检查

```
terrain_density = n_blocked / 64
约束：terrain_density ≤ TERRAIN_DENSITY_MAX = 0.25
等价：n_blocked ≤ 16
```

示例：n_blocked=10 → 15.6% → 通过；n_blocked=17 → 26.6% → 加载失败（reason="terrain_density_exceeded"）

### 公式 F2：部署区有效格数检查

```
n_deploy = count(d ∈ deploy_zone : d 不在 terrain_data 的 BLOCKED 格集合中)
约束：n_deploy ≥ DEPLOY_ZONE_MIN_CELLS = 6
```

示例：deploy_zone 有 8 格，2 格与 BLOCKED 重叠 → n_deploy=6 → 通过（恰好满足，无错误）  
示例：deploy_zone 有 7 格，2 格与 BLOCKED 重叠 → n_deploy=5 < 6 → 加载失败（reason="deploy_zone_insufficient"）

### 公式 F3：敌方数量检查

```
n_enemies = count(enemy_roster)
约束：ENEMY_COUNT_MIN ≤ n_enemies ≤ ENEMY_COUNT_MAX
= 2 ≤ n_enemies ≤ 6
```

示例：n_enemies=4 → 通过；n_enemies=1 → 加载失败（reason="enemy_count_below_minimum"）；n_enemies=7 → 加载失败（reason="enemy_count_above_maximum"）

### 公式 F4：最小分离距离检查

```
min_separation = min over {(e, d) : e ∈ E, d ∈ D} of manhattan_distance(e, d)
约束：min_separation ≥ MAP_SEPARATION_MIN = 3
```

**设计意图**：tier-1 敌人 move_range ≤ 2（unit-data-system 约束）。分离距离 = 3 确保：第 1 回合炮手（attack_range=3–4，在部署区任意格）即可攻击最近敌人；敌方需至少 2 回合（各移动 2 格）才能进入近战范围——炮手拥有至少 1 回合"无代价"输出窗口。

示例：enemy 在 (0,0)，部署区最近格在 (0,2) → manhattan=2 < 3 → 加载失败  
示例：enemy 在 (0,0)，部署区最近格在 (0,3) → manhattan=3 = MAP_SEPARATION_MIN → 通过

### 公式 F5：岛屿等级与敌方威胁层级映射

```
allowed_threat_tiers(island_tier):
  island_tier 1–2 → {1}
  island_tier 3–4 → {1, 2}
  island_tier 5   → {2, 3}
  island_tier 6   → {3}         // 终局 boss 岛
```

地图加载时校验：所有 EnemySlotDefinition 对应的 EnemyDefinition.threat_tier ∈ allowed_threat_tiers(map.island_tier)；不符则加载失败（reason="threat_tier_mismatch"）。

示例：island_tier=1 的地图含 threat_tier=2 的敌人 → 加载失败  
示例：island_tier=4 的地图含 threat_tier=2 的敌人 → 通过

### 公式 F4 实现保护（补充）

F4 在 D（有效部署格集合）为空时执行 `min over empty set` 会产生未定义行为。Rule 3 的验证顺序保证 ⑤（F2）在 ⑥（F4）之前执行并短路；实现层须在 F4 入口加防御性 guard：

```
if D.is_empty():
    emit map_load_failed(reason="deploy_zone_insufficient")   // 与 F2 同 reason
    return
```

### 公式 F6：远程走廊检测

**定义**：合法远程走廊是一条行方向或列方向的连续非 BLOCKED 格序列，长度 ≥ RANGED_CORRIDOR_MIN_LENGTH，且序列中至少一格满足"单侧约束"（该格的垂直方向上存在 BLOCKED 格邻居，或该格位于棋盘边界行/列）。

```
# 变量
RANGED_CORRIDOR_MIN_LENGTH = 3   // 注册于 entities.yaml

# 判断序列的单侧约束（corridor_axis: "ROW" or "COL"）
has_wall_on_side(sequence, axis):
  for each cell c in sequence:
    if axis == "ROW":
      if c.row == 0 or c.row == 7: return true          // 边界行
      if terrain[c.col, c.row-1] == BLOCKED: return true
      if terrain[c.col, c.row+1] == BLOCKED: return true
    if axis == "COL":
      if c.col == 0 or c.col == 7: return true          // 边界列
      if terrain[c.col-1, c.row] == BLOCKED: return true
      if terrain[c.col+1, c.row] == BLOCKED: return true
  return false

# 主检测函数
has_valid_ranged_corridor(terrain_data) -> bool:
  for each row r in [0..7]:
    for each maximal non-BLOCKED sequence in row r:
      if sequence.length >= RANGED_CORRIDOR_MIN_LENGTH:
        if has_wall_on_side(sequence, "ROW"): return true
  for each col c in [0..7]:
    for each maximal non-BLOCKED sequence in col c:
      if sequence.length >= RANGED_CORRIDOR_MIN_LENGTH:
        if has_wall_on_side(sequence, "COL"): return true
  return false

约束：has_valid_ranged_corridor(terrain_data) == true
失败：map_load_failed(reason="no_ranged_corridor")
```

**设计意图**：纯"连续空格≥3"无法区分走廊与开阔地——强制至少一侧有墙或边界，确保走廊具备"敌人必须绕路"的战术属性。

示例：terrain 全空（无 BLOCKED），行 0 全列非 BLOCKED，row=0 为边界行 → has_wall_on_side 返回 true → 通过  
示例：2×2 BLOCKED 方块居中，四周开阔无边界行/列覆盖长度≥3 → 失败（reason="no_ranged_corridor"）  
示例：battle_map_001：列 C0 rows 0–7 全非 BLOCKED，c=0 为左边界列 → has_wall_on_side("COL")=true → 通过

## Edge Cases

| 情形 | 处理规则 |
|------|---------|
| **EC-1：deploy_zone 与 BLOCKED 重叠，剩余 < 6** | 加载失败，emit map_load_failed(reason="deploy_zone_insufficient") |
| **EC-2：deploy_zone 与 BLOCKED 重叠，剩余 ≥ 6** | 加载成功；有效部署区自动缩减为不含 BLOCKED 的子集；不产生警告 |
| **EC-3：敌方起始格为 TERRAIN_BLOCKED** | 验证阶段检测，加载失败（reason="enemy_start_blocked"）；不写入任何地形 |
| **EC-4：两个敌方 slot 共享同一 grid_position** | 验证阶段检测位置冲突，加载失败（reason="enemy_position_collision"） |
| **EC-5：GUARDIAN 的 home_pos == Vector2i(-1,-1)** | 加载成功（不是结构错误）；敌人 AI EC-5 已处理此退化：GUARDIAN 退化为 MELEE 行为 |
| **EC-6：unit_definition_id 在 unit-data-system 中不存在** | 加载失败（reason="unknown_unit_definition: [id]"）；不部署任何单位 |
| **EC-7：island_tier 内含不允许 threat_tier 的敌人** | 加载失败（reason="threat_tier_mismatch"） |
| **EC-8：MapDefinition 文件不存在或无法解析** | emit map_load_failed(reason="file_not_found" 或 "parse_error")；系统维持 MAP_UNLOADED |
| **EC-9：在 MAP_ACTIVE 状态收到 map_load_requested** | 拒绝并记录警告（不中断进行中战斗）；等待 MAP_RESOLVED 后再接受新请求 |
| **EC-10：所有部署区格在加载后均被占用（玩家放置阶段）** | 不可能情形（加载时保证 n_deploy ≥ 6 > DEPLOY_LIMIT=4）；防御性断言即可 |

## Dependencies

### 上游依赖（本系统读取/调用）

| 系统 | GDD 状态 | 依赖内容 |
|------|---------|---------|
| 网格棋盘系统 (#2) | Approved（grid-board-system.md） | `set_terrain(pos, type)`、`place_unit(instance, pos)` 接口；棋盘 owns 格子占用状态与地形事实源 |
| 单位数据系统 (#1) | Approved（unit-data-system.md） | EnemyDefinition 模板（按 unit_definition_id 查询）；UnitInstance 字段定义（behavior_type/home_pos 写入权在本系统） |
| 敌人 AI 与意图系统 (#7) | Approved（enemy-ai-intent-system.md） | 接口合同：AI GDD 已声明"战斗地图在部署时写入 behavior_type 和 home_pos"；本 GDD 实现该合同 |

### 下游依赖（谁依赖本系统）

| 系统 | GDD 状态 | 依赖内容 |
|------|---------|---------|
| 航线与招募系统 (#11) | Not Started | 调用 `get_map_for_island(island_index)` 获取地图定义；依赖本系统的地图池接口和 island_tier 分级 |
| 教学系统 (#16) | Not Started | 使用固定 map_id（如 `tutorial_map_001`）运行脚本化教学残局；依赖本系统的 map_loaded 信号启动战斗 |

### 双向引用状态

- **grid-board-system.md**（Approved）：Dependencies 节已记录"战斗地图系统加载时调用 set_terrain"——与本 GDD 一致，无需回填
- **enemy-ai-intent-system.md**（Approved）：Interactions 表已记录"战斗地图在部署时写入 behavior_type 和 home_pos"——与本 GDD 一致，无需回填

## Tuning Knobs

| 常量名 | 默认值 | 安全范围 | 游戏效果 |
|--------|--------|---------|---------|
| `TERRAIN_DENSITY_MAX` | 0.25（16/64 格） | [0.05, 0.40] | 棋盘可被障碍的最大比例；>40% 严重割裂可达区，<5% 失去地形战术意义 |
| `TERRAIN_BLOCKED_MIN` | 4 | [2, 8] | 每张地图至少含有的 BLOCKED 格数下界；< 2 地形形同虚设，战术决策空间消失；= 8 已产生明显走廊结构 |
| `DEPLOY_ZONE_MIN_CELLS` | 6 | [4, 12] | 玩家部署区最小有效格数；4=刚好满足 DEPLOY_LIMIT，无放置灵活性；12=极宽松 |
| `ENEMY_COUNT_MIN` | 2 | [1, 4] | 每张地图最少敌人数；1=过于轻松；4=总是高压起手 |
| `ENEMY_COUNT_MAX` | 6 | [4, 8] | 每张地图最多敌人数；>6 在 8×8+4 友方同场时易拥挤；=8 接近棋盘饱和临界 |
| `MAP_SEPARATION_MIN` | 3 | [2, 5] | 敌方起始格与部署区最小曼哈顿距离；<3 重现原型炮手身份问题；=5 使第 1–2 回合无压力 |
| `RANGED_CORRIDOR_MIN_LENGTH` | 3 | [2, 5] | 远程走廊最小连续格数（F6）；=2 走廊战术效果不足；=5 过于限制地图设计空间 |
| `MAP_COUNT_MVP` | 1 | 固定 | MVP 单张白盒地图（不作为旋钮，是里程碑约束） |
| `MAP_COUNT_VERTICAL_SLICE` | 5 | [4, 10] | 垂直切片地图池大小；<4 重玩多样性不足；>10 超单人开发内容产出能力 |

**island_tier → 地形设计参考映射**（建议值，不代码校验，供地图作者参考）：

| island_tier | 建议 n_enemies | 建议 BLOCKED 格数 | 建议 MAP_SEPARATION_MIN |
|-------------|--------------|-----------------|------------------------|
| 1–2（新手岛） | 2–3 | 2–8（较开阔） | 3（基线） |
| 3–4（中盘岛） | 3–5 | 4–12（中等密度） | 3–4 |
| 5–6（终局岛） | 4–6 | 6–16（复杂地形） | 3–4 |

## Visual/Audio Requirements

- **地图 3D 场景**：每张 MapDefinition 引用一个 Godot 3D 场景（`map_scene_id`），包含地面网格、TERRAIN_BLOCKED 的墙体/岩石资产、TERRAIN_COVER 的掩体资产、以及环境光照设置。MVP 白盒阶段 `map_scene_id = null`，使用平面 + 色块占位
- **TERRAIN_COVER 当前为 pass-through**：COVER 格对移动无阻挡，战斗效果（减伤/视线遮挡）未定义（见 OQ-2）。**MVP 阶段禁止在 `battle_map_001` 中使用 COVER 格**，避免玩家看到掩体视觉却无减伤效果产生认知误导；垂直切片阶段使用前须先关闭 OQ-2
- **地形视觉精度**：TERRAIN_BLOCKED 格的 3D 资产在世界空间中的位置和尺寸须与逻辑格精确对应（对应关系由逻辑格↔3D 世界坐标 ADR 定义，ADR 待立项）
- **部署区高亮**：MAP_READY 状态下，deploy_zone 有效格以蓝色网格叠层高亮，区别于可达格高亮（同蓝色系但亮度/饱和度不同）
- **地图名称**：`display_name` 在战斗前展示界面（战前信息屏或 HUD 顶栏）显示；具体版式归 HUD GDD 或战前 UI GDD
- **音频**：地图本身无专属音效或 BGM 触发；BGM 由音频系统 (#17) 全局管理

## UI Requirements

- **部署阶段 UI**：玩家在 MAP_READY 状态下看到：棋盘 + 高亮部署区 + 可选船员列表（从当前 roster 中选最多 DEPLOY_LIMIT=4 人）。交互逻辑（点选格子/船员/确认部署）属于部署阶段的回合管理 UI 职责，本系统只提供数据：`get_deploy_zone_available()` 列表和 `display_name`
- **敌方单位可见性**：地图加载后敌方单位已在棋盘上，玩家在部署阶段即可看到敌方布局——这是"全明示"契约的一部分（参考 Into the Breach：部署前即可看到所有威胁）
- **战前信息**：`display_name`（地图名）和 `enemy_roster.size()`（敌方数量）可用于战前信息展示，帮助玩家决策上场阵容

## Acceptance Criteria

**AC-1：地形正确写入棋盘** 【集成测试】
- Given: MapDefinition 含 TERRAIN_BLOCKED 格 (2,2) 和 (5,5)，其余有效
- When: map_load_requested 成功执行（所有验证通过）
- Then: `grid_board.get_terrain(Vector2i(2,2))` 返回 TERRAIN_BLOCKED；`grid_board.get_terrain(Vector2i(5,5))` 返回 TERRAIN_BLOCKED；其余格地形不变（EMPTY）

**AC-2：敌方 behavior_type 和 home_pos 正确写入 UnitInstance** 【集成测试】
- Given: enemy_roster 含 1 个 GUARDIAN（home_pos=Vector2i(5,3)）、1 个 MELEE（home_pos=Vector2i(-1,-1)）；test doubles：unit-data-system 返回对应 EnemyDefinition stub；grid_board.place_unit stub 返回 true
- When: 地图加载完成
- Then: GUARDIAN 对应 UnitInstance：.behavior_type == "GUARDIAN"，.home_pos == Vector2i(5,3)；MELEE 对应 UnitInstance：.behavior_type == "MELEE"，.home_pos == Vector2i(-1,-1)

**AC-3：部署区在加载后可用（正常路径下边界）** 【集成测试】
- Given: deploy_zone = [Vector2i(0,6),(1,6),(2,6),(0,7),(1,7),(2,7)]（恰好 6 格，= DEPLOY_ZONE_MIN_CELLS），无 BLOCKED 格重叠（与 AC-10 区别：AC-10 测试有重叠后缩减；本 AC 测试无重叠的正常路径下边界）
- When: 地图加载完成
- Then: `get_deploy_zone_available([])` 返回恰好包含以上 6 格的数组（顺序无要求）

**AC-4：地形密度超限阻断加载** 【单元测试】
- Given: terrain_data 含 17 个 TERRAIN_BLOCKED 格（> 16）
- When: map_load_requested
- Then: map_load_failed 信号发出，reason 包含 "terrain_density_exceeded"；棋盘地形未被修改；系统状态仍为 MAP_UNLOADED

**AC-5：敌方数量不足阻断加载** 【单元测试】
- Given: enemy_roster 仅含 1 个 EnemySlotDefinition
- When: map_load_requested
- Then: map_load_failed，reason 包含 "enemy_count_below_minimum"

**AC-6：敌方数量超限阻断加载** 【单元测试】
- Given: enemy_roster 含 7 个 EnemySlotDefinition
- When: map_load_requested
- Then: map_load_failed，reason 包含 "enemy_count_above_maximum"

**AC-7：敌方起始格冲突阻断加载** 【单元测试】
- Given: enemy_roster 中两个 slot 的 grid_position 均为 Vector2i(3,3)
- When: map_load_requested
- Then: map_load_failed，reason 包含 "enemy_position_collision"；棋盘无 UnitInstance 部署

**AC-8：分离距离不足阻断加载** 【单元测试】
- Given: 某 enemy grid_position = Vector2i(0,0)；deploy_zone 含 Vector2i(0,2)（manhattan=2 < MAP_SEPARATION_MIN=3）
- When: map_load_requested
- Then: map_load_failed，reason 包含 "separation_constraint_violated"

**AC-9：成功加载触发 map_loaded 信号恰好 1 次** 【集成测试】
- Given: 合法 MapDefinition（通过全部 F1–F6 验证）；**信号监听器在发出 map_load_requested 之前完成 watch_signals(map_loaded) 注册**（确保不遗漏第一次 emit）
- When: map_load_requested
- Then: map_loaded(map_id) 信号发出恰好 1 次（`get_signal_emit_count("map_loaded") == 1`）；系统状态为 MAP_READY

**AC-10：部署区与 BLOCKED 重叠自动缩减，≥6 格时加载成功** 【单元测试】
- Given: deploy_zone 有 8 格，其中 2 格与 TERRAIN_BLOCKED 格重叠
- When: map_load_requested（其余验证通过）
- Then: 加载成功；get_deploy_zone_available() 返回仅含 6 个无重叠格的数组

**AC-11：未知 unit_definition_id 阻断加载** 【单元测试】
- Given: EnemySlotDefinition.unit_definition_id = "enemy_does_not_exist"（unit-data-system 中无此 id）
- When: map_load_requested
- Then: map_load_failed，reason 包含 "unknown_unit_definition"

**AC-12：岛屿等级与威胁等级不匹配阻断加载** 【单元测试】
- Given: island_tier=1 的地图中含 threat_tier=2 的敌人
- When: map_load_requested
- Then: map_load_failed，reason 包含 "threat_tier_mismatch"

**AC-13a：验证阶段失败不修改棋盘状态** 【集成测试】
- Given: MapDefinition 在验证阶段失败（如 n_blocked=17，在步骤 ① 即失败）
- When: map_load_requested
- Then: 棋盘地形全部保持加载前状态（`set_terrain` 未被调用）；无 UnitInstance 被 `place_unit` 到棋盘；`_valid_deploy_cells` 为空；系统状态为 MAP_UNLOADED

**AC-13b：加载阶段中途失败触发棋盘回滚** 【集成测试】
- Given: MapDefinition 通过全部验证（①–⑨），但在地形写入后，`unit_definition_id` 不存在（模拟加载阶段发现数据不一致）
- When: map_load_requested
- Then: 棋盘地形回滚至加载前状态（或系统保证加载失败时 `set_terrain` 写入已撤回）；无 UnitInstance 被部署；`map_load_failed` 信号发出；系统状态为 MAP_UNLOADED  
  *注：此 AC 测试的是"验证通过但加载中途失败"的原子性，与 AC-13a 的"验证阶段失败"互补*

**AC-14：无远程走廊阻断加载（F6）** 【单元测试】
- Given: terrain_data 无任何格子，且 8×8 棋盘均不含边界行/列的连续非 BLOCKED 序列满足 F6（例如：6×6 内部全为 BLOCKED，边角全空但内部空格序列均无 BLOCKED 邻居且不在边界行/列）
- When: map_load_requested
- Then: map_load_failed，reason 包含 "no_ranged_corridor"；棋盘无地形写入

**AC-15：MAP_ACTIVE 状态拒绝新加载** 【集成测试】（对应 EC-9）
- Given: 系统处于 MAP_ACTIVE 状态（地图已加载，battle_started 已收到）
- When: 发出 map_load_requested（任意 map_id）
- Then: 系统状态保持 MAP_ACTIVE；map_load_failed 信号发出，reason 包含 "map_already_active"；棋盘状态无任何修改；进行中的战斗不受影响

**AC-16：map_reset_requested 触发 MAP_RESOLVED→MAP_UNLOADED 及数据清空** 【集成测试】
- Given: 系统处于 MAP_RESOLVED 状态（已收到 battle_won 或 battle_lost）；棋盘含有地形数据和 UnitInstance
- When: 发出 map_reset_requested
- Then: 系统状态切换为 MAP_UNLOADED；`get_deploy_zone_available([])` 返回空数组；棋盘地形已清空（`grid_board.get_terrain` 返回 EMPTY）；无 UnitInstance 残留

**AC-17：battle_started 触发 MAP_READY→MAP_ACTIVE** 【集成测试】
- Given: 系统处于 MAP_READY 状态（map_loaded 已 emit）
- When: 发出 battle_started
- Then: 系统状态切换为 MAP_ACTIVE；不 emit 任何新信号；地图数据保持不变

**AC-18：n_enemies=2 成功加载（最小数量边界）** 【单元测试】
- Given: enemy_roster 恰好含 2 个 EnemySlotDefinition，其余验证均通过
- When: map_load_requested
- Then: 加载成功，map_loaded 信号发出；map_load_failed 不发出

**AC-19：n_enemies=6 成功加载（最大数量边界）** 【单元测试】
- Given: enemy_roster 恰好含 6 个 EnemySlotDefinition（无位置冲突，其余验证均通过）
- When: map_load_requested
- Then: 加载成功，map_loaded 信号发出；map_load_failed 不发出

**AC-20：manhattan=3 分离距离成功通过（最小分离边界）** 【单元测试】
- Given: 某 enemy grid_position = Vector2i(0,0)；deploy_zone 中最近格为 Vector2i(0,3)（manhattan=3 = MAP_SEPARATION_MIN）；其余验证均通过
- When: map_load_requested
- Then: 加载成功，map_loaded 信号发出；`separation_constraint_violated` 不出现在任何 reason 中

## Open Questions

| # | 问题 | 裁决归属 | 影响 |
|---|------|---------|------|
| ~~1~~ | ~~**MVP 地图 battle_map_001 具体布局何时确定**~~ | ~~关卡设计阶段~~  | **已关闭（R1 修订）**：布局草案已写入 Rule 6 "battle_map_001 草案布局"节（display_name="狭窄港湾"，island_tier=1，4 种行为原型坐标均已确定，F1–F6 验证通过）。AC-2 的集成测试前置条件已明确 unit_definition_id 占位标识符（`enemy_melee_tier1` 等） |
| 2 | **TERRAIN_COVER 的实际机制**：grid-board-system GDD 定义了 TERRAIN_MODIFIED(COVER) 类型，但未规定其战斗效果（减伤？视线遮挡？纯视觉？）。若无战斗效果，地图设计中使用 COVER 格仅为美术目的；若有减伤效果须在战斗解算 GDD 中定义并被本系统正确传递 | 战斗解算系统 (#4)（已 Approved——需确认其 GDD 是否有 COVER 规则；若无则须补充） | 影响 MapDefinition 中 COVER 格的设计价值；若无机制效果，本 GDD 的 terrain_data 仅需 BLOCKED |
| 3 | **地图选择策略（垂直切片）**：按 island_tier 从池中随机抽取（重玩多样性高、设计控制弱）还是每次出航固定序列（设计师可控节奏弧线、重玩体验固定）？两者均已在本 GDD 架构内支持 | 航线与招募系统 (#11) 设计阶段 | 影响 `get_map_for_island` 接口实现细节（随机=抽池；固定=顺序查表） |
| 4 | **多波次支持（Alpha+）**：当前设计每张地图单波次敌人。Alpha 阶段若引入"清空第一波后触发第二波"，EnemySlotDefinition 须扩展 `wave_index: int` 字段，MapDefinition 须存多个波次数据，Rule 3 的加载序列须增加波次管理逻辑 | Alpha 设计阶段 | 这是 schema 层变更，引入时须同步修订本 GDD 和 unit-data-system；MVP/垂直切片不需要 |
