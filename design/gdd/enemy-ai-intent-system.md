# 敌人 AI 与意图系统 (Enemy AI & Intent System)

> **Status**: Approved
> **Author**: claude-sonnet-4-6 (autonomous)
> **Last Updated**: 2026-06-16
> **Implements Pillar**: 小棋盘大组合 / 十分钟一场爽局

## Overview

敌人 AI 与意图系统是《孤帆棋海》战术深度的核心支撑层。它以**意图全明示（Full Reveal）**契约为设计基准——每个回合开始时，全部敌方单位同步声明本轮行动意图，图标直接显示在棋盘上；玩家拿到一张"完整题面"后，通过站位调整、相邻羁绊充能或爆发技打断来改写结果。AI 不使用随机性：给定相同棋盘状态，意图声明是完全确定的，保证玩家的战术推断有效。MVP 范围内 AI 仅执行移动与普通攻击（不使用职业动词），以 4 种行为原型（贴身型、保距型、驻守型、群攻型）驱动形态各异的战术威胁，与地形和敌方配置联动制造关卡记忆点。本系统直接下游为战斗 HUD（意图图标渲染）和战斗地图（波次摆放与行为类型分配）。

## Player Fantasy

玩家看到所有箭头和图标亮起时，心里响起一句话："我知道它要打谁——那就让它扑空。"

这是《Into the Breach》式的战术快感：不是"能不能赢"的焦虑，而是"我该如何改写这道题"的推演快感。已知的威胁比未知更紧张——因为你必须解决它，而且你知道自己有机会解决它。把乐手拉开一格，炮手就射不到她；把铁壁顶上去，剑豪的斩被 GUARDED 减半；再充满一格槽值就可以爆发，打断三条攻击线——这些决策只有在意图可见的前提下才能实现。

每局战斗结束时，玩家应该感受到的不是"运气不错"，而是"我把局面掰回来了"。

## Detailed Design

### Core Rules

---

#### Rule 1：意图声明（ROUND_START）

系统订阅回合管理的 `ROUND_START` 信号。收到信号后，**同步**按先攻队列顺序对每个 `faction == ENEMY && is_alive == true` 的单位执行以下流程：

1. 读取单位的 `behavior_type`（由战斗地图系统在部署时写入 `UnitInstance`）
2. 运行对应行为原型的决策树（见 Rule 2），返回 `IntentRecord`
3. 将 `IntentRecord` 存入 `intent_registry[unit_id]`
4. Emit `intent_declared(unit_id, intent_record)`

全部敌方单位的意图在 `ROUND_START` 处理完毕后才有任何单位行动，确保玩家在第一个行动单位开始前就能看到完整意图地图。

**IntentRecord 结构：**
```
{
  unit_id:     int,
  action_type: IntentType,   # 枚举值见下
  target_id:   int,          # 攻击目标单位 ID；-1 表示无
  target_pos:  Vector2i,     # 移动目标格；Vector2i(-1,-1) 表示无
  is_stale:    bool          # 执行时判定为过期（目标已死或格子被占）
}
```

**IntentType 枚举：**
- `INTENT_WAIT = 0` — 无行动（无合法目标/移动格）
- `INTENT_MOVE = 1` — 仅移动
- `INTENT_ATTACK = 2` — 原地攻击（已在射程内）
- `INTENT_MOVE_ATTACK = 3` — 移动至最优格后攻击

---

#### Rule 2：行为原型决策树

所有决策树输入为当前棋盘快照，输出确定性 `IntentRecord`。目标选择全部基于 `faction == ALLY && is_alive == true` 的单位。

**2A：BEHAVIOR_MELEE（贴身型）**
```
target ← select_nearest_lowest_hp(self)
if target == null:
    return INTENT_WAIT

if is_valid_attack(self.id, target.id):
    return INTENT_ATTACK(target.id)

staging ← get_attack_staging_cells(self.pos, self.move_range, target.pos, self.attack_range)
if staging.is_empty():
    path ← get_path_to(self.pos, target.pos)
    move_to ← last reachable cell on path within self.move_range
    return INTENT_MOVE(move_to)

return INTENT_MOVE_ATTACK(staging[0], target.id)
```

**2B：BEHAVIOR_RANGED（保距型）**
```
in_range_target ← select_target_in_attack_range(self)   # Rule 5 子程序
if in_range_target != null and manhattan_distance(self.pos, in_range_target.pos) >= RANGED_RETREAT_THRESHOLD:
    return INTENT_ATTACK(in_range_target.id)             # 在舒适距离内且可攻击，原地射击

target ← select_nearest_lowest_hp(self)
if target == null:
    return INTENT_WAIT

if manhattan_distance(self.pos, target.pos) < RANGED_RETREAT_THRESHOLD:
    # 目标过近：遍历 get_reachable_cells，选使 manhattan_distance(cell, target.pos) 最大的格
    reachable ← get_reachable_cells(self.pos, self.move_range)
    retreat_pos ← argmax over reachable cells of manhattan_distance(cell, target.pos)
    # 平局时选 unit_id 最小的格（按 col×8+row 顺序升序）
    if retreat_pos != self.pos:                          # 确实能后退
        return INTENT_MOVE(retreat_pos)                  # 后退，本回合不攻击
    # 无法后退时退化：若在射程内攻击，否则等待
    if in_range_target != null:
        return INTENT_ATTACK(in_range_target.id)
    return INTENT_WAIT

staging ← get_attack_staging_cells(self.pos, self.move_range, target.pos, self.attack_range)
if staging.is_empty():
    path ← get_path_to(self.pos, target.pos)
    move_to ← last reachable cell on path within self.move_range
    return INTENT_MOVE(move_to)
return INTENT_MOVE_ATTACK(staging[0], target.id)
```
`ally_in_preferred_range`（辅助说明）= 存在 ally 使 `manhattan_distance ∈ [RANGED_RETREAT_THRESHOLD, self.attack_range]`；保距型优先通过 `select_target_in_attack_range` + 距离下限检测实现此判断，不单独维护标志。

**2C：BEHAVIOR_GUARDIAN（驻守型）**
```
target ← select_target_in_attack_range(self)   # 仅考虑当前射程内的 ally
if target != null:
    return INTENT_ATTACK(target.id)             # 已在射程内，原地攻击

# 无射程内目标时，若被位移则尝试归位（攻击始终优先于归位，见 EC-6）
if self.pos != self.home_pos:
    return INTENT_MOVE(closest_reachable_to(self, self.home_pos))

return INTENT_WAIT
```
`home_pos` 为战斗地图部署时写入 `UnitInstance` 的字段；若未定义，驻守型退化为 BEHAVIOR_MELEE。

**2D：BEHAVIOR_SWARMER（群攻型）**
```
target ← select_highest_stack_count(self)
if target == null:
    target ← select_nearest_lowest_hp(self)
if target == null:
    return INTENT_WAIT

if is_valid_attack(self.id, target.id):
    return INTENT_ATTACK(target.id)

staging ← get_attack_staging_cells(self.pos, self.move_range, target.pos, self.attack_range)
if staging.is_empty():
    path ← get_path_to(self.pos, target.pos)
    move_to ← last reachable cell on path within self.move_range
    return INTENT_MOVE(move_to)
return INTENT_MOVE_ATTACK(staging[0], target.id)
```

---

#### Rule 3：意图执行（ACTIVE_TURN）

订阅回合管理的 `enemy_turn_started(unit_id)` 信号。收到时：

1. 取 `intent_registry[unit_id]`
2. **过期检测**（见 Rule 4）：若 `is_stale == true` → 执行 stale_fallback
3. 按 `action_type` 执行：

| action_type | 执行步骤 |
|-------------|---------|
| `INTENT_WAIT` | 标记 `mark_has_acted(unit_id)` 保持状态一致性（回合由 `enemy_actions_completed` 信号推进，mark 仅用于 has_acted 调试可见性）；无任何攻击/移动 |
| `INTENT_MOVE` | 调用 grid-board 更新位置 → `mark_has_moved(unit_id)` |
| `INTENT_ATTACK` | 调用 `execute_attack(unit_id, target_id)` → `mark_has_acted(unit_id)` |
| `INTENT_MOVE_ATTACK` | 移动至 `target_pos` → `mark_has_moved(unit_id)` → `execute_attack(unit_id, target_id)` → `mark_has_acted(unit_id)` |

4. Emit `enemy_actions_completed(unit_id)`

**MVP 限制**：AI 不执行职业动词（`has_used_verb` 保持 `false`）。

---

#### Rule 4：过期检测（Staleness Detection）

在执行前检查以下条件。任一为 true 则标记 `is_stale = true`：

- `INTENT_ATTACK` / `INTENT_MOVE_ATTACK`：`target.is_alive == false`
- `INTENT_ATTACK` / `INTENT_MOVE_ATTACK`：`is_valid_attack(unit_id, target_id) == false`（覆盖"目标在声明后移出射程"的场景；此检查在上一条之后执行，确保目标存活再做射程验证）
- `INTENT_MOVE_ATTACK`：staging cell（`target_pos`）已被其他单位占据
- `INTENT_MOVE`：`target_pos` 已被占据

**Stale Fallback**：重新运行本单位的行为原型决策树（使用当前棋盘状态）。
1. 若得到有效新意图（≠ INTENT_WAIT）→ emit `intent_declared(unit_id, new_intent)` 更新 HUD → 执行新意图
2. 若决策树仍返回 INTENT_WAIT → 直接执行 INTENT_WAIT 路径（mark_has_acted + emit enemy_actions_completed）

**注意**：EC-9 描述的"is_valid_attack 返回 false"情形现由上方第 2 条过期条件覆盖，stale_fallback 将自动重新评估，不会遗留未处理的拒绝攻击状态。

---

#### Rule 5：目标选择子程序

**`select_nearest_lowest_hp(self)`**
1. 过滤：`faction == ALLY && is_alive == true` 的全部单位
2. 排序 1（升序）：`chebyshev_distance(self.pos, ally.pos)`
3. 排序 2（升序）：`ally.current_hp`
4. 排序 3（升序）：`ally.unit_id`（确定性平局决策）
5. 返回第一项；列表为空返回 null

**`select_target_in_attack_range(self)`**（驻守型专用）
1. 过滤：`faction == ALLY && is_alive == true && is_valid_attack(self.id, ally.id) == true`
2. 排序：`ally.current_hp` 升序；平局 `ally.unit_id` 升序
3. 返回第一项；列表为空返回 null

**`select_highest_stack_count(self)`**（群攻型专用）
1. 过滤：`faction == ALLY && is_alive == true` 的全部 ally
2. 对每个 ally 计算 `stack_count = count of (enemy_k where enemy_k.id ≠ self.id && enemy_k.is_alive && adjacent(enemy_k.pos, ally.pos))`
3. 过滤：仅保留 `stack_count >= SWARMER_STACK_THRESHOLD`（默认 1）
4. 排序 1（降序）：`stack_count`；排序 2（升序）：`ally.current_hp`；排序 3（升序）：`ally.unit_id`
5. 返回第一项；列表为空返回 null（调用方 fallback 至 `select_nearest_lowest_hp`）

---

#### Rule 6：确定性保证

AI 不使用任何随机函数。给定相同的 `UnitInstance` 状态与棋盘占用状态，相同单位的 `IntentRecord` 在每次运行中完全一致。所有平局通过 `unit_id` 升序打破。

### States and Transitions

#### 系统生命周期

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| `AI_IDLE` | 战斗外，intent_registry 为空 | 初始化；收到 `battle_started` | 收到下一轮 `ROUND_START` |
| `AI_DECLARING` | 正在同步声明全部敌方意图 | `ROUND_START` 信号到达 | 所有敌方单位的 `intent_declared` 发出完毕 |
| `AI_WAITING` | 意图已提交，等待各单位的 ACTIVE_TURN | `AI_DECLARING` 完成 | 所有敌方单位 `enemy_actions_completed` 发出；或收到下一 `ROUND_START` |
| `AI_EXECUTING` | 正在执行某个敌方单位的意图 | 收到 `enemy_turn_started(unit_id)` | 发出 `enemy_actions_completed(unit_id)` |

战斗结束（`battle_won` 或 `battle_lost`）时系统返回 `AI_IDLE` 并清空 `intent_registry`。

#### 单条 IntentRecord 生命周期

```
PENDING → [ROUND_START 评估] → COMMITTED → [board state changes] → STALE (optional)
COMMITTED / STALE → [enemy_turn_started 执行] → RESOLVED
```

### Interactions with Other Systems

| 系统 | 接口 / 信号 | 方向 | 说明 |
|------|------------|------|------|
| 回合管理系统 (#3) | `ROUND_START` | 接收信号 | 触发所有敌方意图声明；本系统订阅此信号 |
| 回合管理系统 (#3) | `enemy_turn_started(unit_id)` | 接收信号 | 触发指定敌方单位意图执行 |
| 回合管理系统 (#3) | `battle_started()` | 接收信号 | 清空 intent_registry，初始化新战斗 |
| 回合管理系统 (#3) | `enemy_actions_completed(unit_id)` | 发出信号 | 执行完毕后通知回合管理推进队列（**跨 GDD 合同**：turn-management 须订阅此信号以结束敌方 ACTIVE_TURN，等价于玩家点击"结束回合"） |
| 回合管理系统 (#3) | `mark_has_moved(unit_id)` / `mark_has_acted(unit_id)` | 调用接口 | 执行移动/攻击后标记行动点消耗 |
| 网格棋盘系统 (#2) | `get_attack_staging_cells(mover_pos, move_range, target_pos, attack_range) → Array[Vector2i]` | 调用接口 | 计算可移动后攻击目标的最优格集合（BFS + 过滤，AI 侧零嵌套） |
| 网格棋盘系统 (#2) | `get_reachable_cells(pos, move_range) → Array[Vector2i]` | 调用接口 | 验证移动目标合法性；stale 检测时再次调用 |
| 网格棋盘系统 (#2) | `get_path_to(start, goal) → Array[Vector2i]` | 调用接口 | 计算最短路径；无法完全到达时选路径最末可达格 |
| 网格棋盘系统 (#2) | `adjacent(A, B) → bool` | 调用接口 | 群攻型 stack_count 计算；驻守型归位判断 |
| 战斗解算系统 (#4) | `is_valid_attack(attacker_id, target_id) → bool` | 调用接口 | 执行前合法性验证（射程、阵营、has_acted 等）；用于决策树判断"能否原地攻击" |
| 战斗解算系统 (#4) | `execute_attack(attacker_id, target_id)` | 调用接口 | 敌方普通攻击执行（触发完整信号链：attack_executed / damage_dealt / unit_downed） |
| 单位数据系统 (#1) | `UnitInstance.behavior_type`、`home_pos`、`move_range`、`attack_range`、`grid_position`、`current_hp`、`faction`、`is_alive` | 读取 | 意图生成与执行时读取所有单位状态；`behavior_type` 和 `home_pos` 由战斗地图系统在部署时写入 |
| 战斗 HUD 系统 (#9) | `intent_declared(unit_id, intent_record)` | 发出信号 | HUD 订阅以在棋盘上渲染意图图标和移动箭头 |
| 战斗地图系统 (#10) | `UnitInstance.behavior_type` / `UnitInstance.home_pos` | 写入（下游） | 战斗地图在部署敌方单位时设定 behavior_type 和 home_pos；本系统在运行时读取，不写入 |

## Formulas

### 公式 1：目标优先级排序（贴身型 / 群攻型回退）

```
distance_score(ally) = chebyshev_distance(self.pos, ally.pos)
hp_score(ally) = ally.current_hp
id_score(ally) = ally.unit_id

sort key = (distance_score ASC, hp_score ASC, id_score ASC)
```

示例：self 在 (3,3)，ally_A 在 (4,4)（距离=1，hp=3），ally_B 在 (4,4) 不可能（同格），ally_C 在 (5,5)（距离=2，hp=1）→ 选 ally_A（距离优先）

---

### 公式 2：群攻堆叠计数

```
stack_count(target_id) = Σ { 1 : enemy_k.is_alive == true
                                   && enemy_k.id ≠ self.id
                                   && adjacent(enemy_k.pos, target.pos) }
```

输入范围：`count(alive_enemies) ∈ [0, 5]`（8×8 棋盘敌方最多 6 个减去自身）
输出范围：`[0, 5]`

---

### 公式 3：保距型后退检测

```
is_too_close(self, target) = manhattan_distance(self.pos, target.pos) < RANGED_RETREAT_THRESHOLD
```

`RANGED_RETREAT_THRESHOLD` 默认 2；`manhattan_distance` 使用 `|Δcol| + |Δrow|`（与 grid-board 攻击距离度量一致）

---

### 公式 4：保距型射程检测（引用网格棋盘系统公式）

```
can_attack_at_range(self, target) = manhattan_distance(self.pos, target.pos) <= self.attack_range
                                    && manhattan_distance(self.pos, target.pos) >= 1
```

敌方单位在 MVP 中无最小射程约束（GUNNER_MIN_RANGE 仅适用于玩家炮手职业）。is_valid_attack() 仍会执行完整验证。

---

### 公式 5：敌方战力带（注册于 entities.yaml，非本系统所有）

```
enemy_power_band = 10 + 2 × (tier - 1)  ±1 容差
tier ∈ {1, 2, 3}（MVP）
输出范围 [9, 15]
```

本系统不计算此公式；行为逻辑通过 `base_damage`（unit-data 存储）读取结果，不得重新计算或覆盖。

---

### 公式 6：最优格选择（staging_cells 排序）

`get_attack_staging_cells` 返回的数组须经 AI 系统排序后再取 `[0]`，不依赖棋盘侧返回顺序：

```
staging_sort_key(cell) = (chebyshev_distance(self.pos, cell) ASC, col*8+row ASC)
staging_cells.sort_custom(staging_sort_key)
best_staging = staging_cells[0]
```

平局（等距 staging cell）按 `col×8+row` 升序（确定性）。AI 系统始终执行此排序，与棋盘侧是否已排序无关。

## Edge Cases

**EC-1：无存活 ally 时声明意图**
若 `ROUND_START` 时所有 ally 均 `is_alive == false`（理论上 battle-resolution 应已判断战斗胜负），AI 对所有敌方单位输出 `INTENT_WAIT`，不发出任何攻击信号。`battle_won` 信号已由回合管理 / 战斗解算处理，本系统不重复判断。

**EC-2：意图声明后目标被击倒（过期意图）**
己方在敌方行动前将目标击倒（如爆发技）。AI 执行时触发 Rule 4 过期检测 → stale_fallback 重新评估当前棋盘 → 若有新目标则执行新意图，否则 `INTENT_WAIT`。过期意图的旧 `intent_declared` 信号已发出；HUD 须在 `unit_downed` 时清除对应意图图标（HUD GDD 负责）。

**EC-3：staging cell 被其他敌方单位占据**
多个敌方单位同时意图移动至同一格（在声明阶段棋盘状态未更新）。执行时先行动的单位占据该格；后执行的单位收到 `is_stale = true` → stale_fallback 重新找 staging_cells → 若无其他可达 staging → `INTENT_MOVE`（尽量接近）或 `INTENT_WAIT`。

**EC-4：`move_range == 0` 的敌方单位（减益导致速度归零）**
`get_reachable_cells(pos, 0)` 返回仅含起点的集合。AI 不尝试移动；若 `is_valid_attack` 返回 true（已在射程内）→ `INTENT_ATTACK`，否则 `INTENT_WAIT`。

**EC-5：驻守型 home_pos 未定义**
若 `UnitInstance.home_pos` 为默认值 `Vector2i(-1, -1)`（战斗地图未赋值），驻守型退化为 BEHAVIOR_MELEE 逻辑。AI 在决策树入口检查 `home_pos != Vector2i(-1,-1)`；条件不成立时走 BEHAVIOR_MELEE 分支。

**EC-6：驻守型被位移后仍处于射程内**
即使被马力纳推离 home_pos，若推后位置仍能 `is_valid_attack` 命中 ally → 优先攻击（Rule 2C 第一步），不先归位。归位仅在无目标时执行。

**EC-7：保距型后退空间被阻断（四面皆有单位或边界）**
`find_retreat_cell` 遍历 `get_reachable_cells` 内所有格，选 `manhattan_distance(cell, target.pos)` 最大者。若全部可达格距离均小于等于当前位置距离（无法后退），退化为原地 `INTENT_ATTACK`（若在射程内）或 `INTENT_WAIT`。

**EC-8：群攻型堆叠计数为 0（所有 ally 均无友邻）**
`select_highest_stack_count` 返回 null → fallback 至 `select_nearest_lowest_hp`，退化为 BEHAVIOR_MELEE 逻辑。群攻型在首轮（无友邻堆叠的初始状态）等同于贴身型。

**EC-9：ally 在声明后、执行前移出射程（高先攻 ally 移动导致）**
ally 具有比本敌方单位更高的先攻值，在本敌方单位意图声明后移动出射程。Rule 4 的第二条过期检测（`is_valid_attack == false`）捕获此情形 → `is_stale = true` → stale_fallback 重新评估当前棋盘 → 若 ally 仍可在新位置被攻击或到达的 staging_cells 中攻击 → 执行新意图；否则 INTENT_WAIT。`has_acted` 不会因 execute_attack 被拒绝而错误消耗（stale_fallback 在调用 execute_attack 之前介入）。

**EC-10：同一 ROUND_START 中多个 `BEHAVIOR_SWARMER` 竞争同一目标**
两者独立声明意图，均指向同一 ally。执行时先行动者成功攻击；后行动者检查 `is_valid_attack`（攻击本身仍可能有效，stack_count 只影响目标选择不影响攻击合法性），照常执行。不视为冲突。

**EC-11：`battle_started` 发出前即有残留 intent_registry 数据**
系统订阅 `battle_started()` 信号后立即清空 `intent_registry = {}`。若因 session 崩溃等原因信号未收到，`ROUND_START` 时强制清空并重新声明（幂等保护）。

**EC-12：敌方职业动词**
MVP 范围内 AI 不执行职业动词。若单位 `has_used_verb == false` 且 AI 执行完毕后 `has_used_verb` 未被标记 → 回合管理不因此阻塞（turn-management 不要求三行动点全部消耗才结束回合，等待 `enemy_actions_completed` 信号即可）。

## Dependencies

### 上游依赖（本系统读取/调用）

| 系统 | GDD | 依赖内容 | 状态 |
|------|-----|---------|------|
| 单位数据系统 (#1) | unit-data-system.md | `UnitInstance` 字段（behavior_type, home_pos, move_range, attack_range, grid_position, current_hp, faction, is_alive, has_acted） | Approved |
| 网格棋盘系统 (#2) | grid-board-system.md | `get_attack_staging_cells`、`get_reachable_cells`、`get_path_to`、`adjacent` 四个公开接口 | Approved |
| 回合管理系统 (#3) | turn-management-system.md | 信号：`ROUND_START`、`enemy_turn_started`、`battle_started`；接口：`mark_has_moved`、`mark_has_acted` | Approved |
| 战斗解算系统 (#4) | battle-resolution-system.md | 接口：`is_valid_attack(attacker_id, target_id)`、`execute_attack(attacker_id, target_id)` | Approved |

### 下游依赖（本系统发出信号供下游消费）

| 系统 | GDD | 依赖内容 | 状态 |
|------|-----|---------|------|
| 战斗 HUD 系统 (#9) | — | 订阅 `intent_declared(unit_id, intent_record)` 渲染意图图标 | Not Started |
| 战斗地图系统 (#10) | — | 在部署时向 `UnitInstance` 写入 `behavior_type` 和 `home_pos`；本系统运行时读取 | Not Started |

### 跨 GDD 合同（本 GDD 产生的接口变更，需回写上游文档）

**合同 1 — turn-management-system.md 须新增**：
- 在 Interactions 表中加入：`enemy_actions_completed(unit_id)` 信号，由本系统发出，turn-management 订阅以结束敌方单位的 ACTIVE_TURN（等价于玩家点击"结束回合"）。
- 状态机说明：`ACTIVE_TURN(enemy)` → 收到 `enemy_actions_completed(unit_id)` → `TURN_END`

**合同 2 — unit-data-system.md 须新增字段**：
- `UnitInstance.behavior_type: String`（枚举 "MELEE" / "RANGED" / "GUARDIAN" / "SWARMER"；玩家单位无此字段或设为 "NONE"）
- `UnitInstance.home_pos: Vector2i`（守卫型初始部署格；非守卫型设为 `Vector2i(-1,-1)`）

这两个合同与 bond-gauge-burst-system 的 `battle_started` 合同同级——属于文档补全而非设计变更，评审时优先确认修复。

## Tuning Knobs

| 常量名 | 默认值 | 安全范围 | 游戏效果 | 注册位置 |
|--------|--------|---------|---------|---------|
| `RANGED_RETREAT_THRESHOLD` | 2 | [1, 3] | 保距型最小接受曼哈顿距离；低=攻击性强（敌方允许近身），高=保守（主动拉开更大距离） | entities.yaml（建议） |
| `SWARMER_STACK_THRESHOLD` | 1 | [1, 3] | 群攻型触发堆叠优先选目标所需的最低 stack_count；1=只需有1个友邻即优先，2=需2个以上才切换目标 | entities.yaml（建议） |

**调优影响分析：**
- `RANGED_RETREAT_THRESHOLD = 1`：保距型仅在曼哈顿距离 < 1（不可能）时才后退，实际等同于 BEHAVIOR_MELEE — 危险极端值
- `RANGED_RETREAT_THRESHOLD = 3`：保距型在距离 1–2 格时均主动后退，给玩家更大的追击压力，强化炮手职业的交战距离优势价值
- `SWARMER_STACK_THRESHOLD = 1`：首轮所有 ally 均无堆叠，群攻型退化为贴身型；第二轮起堆叠效果才生效
- `SWARMER_STACK_THRESHOLD = 2`：群攻型需等到2个友军已相邻才切换目标，堆叠雪球效应更慢但更明显

## Visual/Audio Requirements

### 意图图标系统（HUD 系统实现，本系统发出数据）

本系统通过 `intent_declared(unit_id, intent_record)` 提供渲染所需的全部数据。HUD 系统基于 `action_type` 展示不同视觉元素：

| action_type | 视觉元素 |
|-------------|---------|
| `INTENT_WAIT` | 单位头顶显示 "Z" 或空闲图标（灰色） |
| `INTENT_MOVE` | 从当前格到 `target_pos` 的虚线箭头（蓝色/中性色） |
| `INTENT_ATTACK` | 单位头顶显示剑/拳图标（红色）；线段连接至 `target_id` 所在格 |
| `INTENT_MOVE_ATTACK` | 移动箭头（到 staging cell）+ 攻击图标（到最终目标）组合显示 |

### 意图失效视觉

当目标被击倒（`unit_downed` 信号）时，HUD 须清除所有指向该目标的意图图标（斜杠划掉或淡出）。**本系统不重新发出 intent_declared；HUD 自行订阅 unit_downed 处理清除逻辑。**

### 音频钩子

本系统无独立音频触发。战斗音效（攻击命中、移动）由战斗解算系统的 `attack_executed`、`damage_dealt` 等信号驱动，音频系统订阅。意图声明本身无声效（视觉静默，保持战术清晰感）。

## UI Requirements

| 信息 | 触发时机 | 可见要求 | 设计理由 |
|------|---------|---------|---------|
| 所有敌方意图图标（行动类型 + 目标/方向） | `intent_declared` 每次发出后立即更新 | 必须在任何单位行动前完全可见 | 全明示契约核心：玩家须在第一个行动点之前拿到完整情报 |
| 意图失效标记（目标被击倒） | `unit_downed` 信号 | 须视觉区分（划掉 / 淡出）；不能完全消失（玩家需知道威胁已解除） | 信息完整性：已解除的威胁也是战场信息 |
| Stale Fallback 后新意图 | stale_fallback 执行后，重新发出 `intent_declared` | 须覆盖旧图标（同 unit_id → 替换，不叠加） | 玩家需知道敌方找到了新目标 |

**UI 优先级说明（供 HUD GDD 参考）：**
- 敌方意图图标在视觉层级上须高于地图纹理，但低于己方行动高亮（当前玩家行动单位的可达格 / 可攻击格高亮）
- 意图箭头不得遮挡单位模型主体（建议偏上方或透明度 80%）

## Acceptance Criteria

*所有 AC 以 GDScript + GUT 框架描述。"发出信号"= GUT signal monitor 捕获。*

---

**AC-1：ROUND_START 触发全部敌方意图声明**
- Given: 战斗中有 3 个 alive enemy 单位，`ROUND_START` 发出
- Then: `intent_declared` 信号恰好发出 3 次（各 unit_id 各一次）；每次携带合法 `IntentRecord`（action_type ∈ 有效枚举，target_id 或 target_pos 在对应 action_type 下有效）

**AC-2：BEHAVIOR_MELEE 选择最近 ally，平局选低 HP**
- Given: 敌方 MELEE 单位 E 在 (4,4)；ally_A 在 (4,3)（距离=1，hp=4），ally_B 在 (4,5)（距离=1，hp=2）
- Then: intent_registry[E] = IntentRecord(action_type=INTENT_ATTACK, target_id=ally_B.id)（距离相同，低 HP 优先）

**AC-3：BEHAVIOR_MELEE 不在射程内时选择 INTENT_MOVE_ATTACK**
- Given: MELEE 单位 E 在 (1,1)，move_range=2，attack_range=1；唯一 ally A 在 (5,5)；get_attack_staging_cells 返回非空
- Then: intent_registry[E].action_type == INTENT_MOVE_ATTACK；target_pos ∈ get_attack_staging_cells 返回值；target_id == A.id

**AC-4：BEHAVIOR_RANGED 退后逻辑**
- Given: RANGED 单位 E 在 (4,4)，attack_range=3；ally A 在 (5,4)（manhattan=1 < RANGED_RETREAT_THRESHOLD=2）
- Then: intent_registry[E].action_type == INTENT_MOVE；target_pos 使得 manhattan_distance(target_pos, A.pos) > manhattan_distance(E.pos, A.pos)；无 INTENT_ATTACK

**AC-5：BEHAVIOR_GUARDIAN 无射程内 ally 时 INTENT_WAIT**
- Given: GUARDIAN 单位 E 在 home_pos，attack_range=1；最近 ally 距离 = 2（超出射程）
- Then: intent_registry[E].action_type == INTENT_WAIT

**AC-6：BEHAVIOR_GUARDIAN 被位移后归位**
- Given: GUARDIAN 单位 E 被马力纳动词推离 home_pos（当前位置 ≠ home_pos）；无 ally 在射程内
- Then: intent_registry[E].action_type == INTENT_MOVE；target_pos 是 `get_path_to(E.pos, home_pos)` 上不超过 move_range 的最远点

**AC-7：BEHAVIOR_SWARMER 选择 stack_count 最高目标**
- Given: SWARMER 单位 E；ally_A 有 2 个友邻敌军（stack_count=2）；ally_B 更近但 stack_count=0
- Then: intent_registry[E].target_id == ally_A.id（stack_count 优先于距离）

**AC-8：意图执行——INTENT_ATTACK**
- Given: enemy_turn_started(E.id) 发出；E 的 intent 为 INTENT_ATTACK(target=A)；A.is_alive==true；is_valid_attack(E.id, A.id)==true
- Then: execute_attack(E.id, A.id) 被调用；attack_executed 信号从战斗解算系统发出；mark_has_acted(E.id) 被调用；enemy_actions_completed(E.id) 随后发出

**AC-9：意图执行——INTENT_MOVE_ATTACK**
- Given: enemy_turn_started(E.id)；intent = INTENT_MOVE_ATTACK(target_pos=(3,3), target_id=A.id)
- Then: E 的 grid_position 更新为 (3,3)；mark_has_moved(E.id) 在攻击前被调用；execute_attack(E.id, A.id) 随后被调用；mark_has_acted(E.id) 被调用；enemy_actions_completed(E.id) 发出

**AC-10：过期意图——目标被击倒**
- Given: ROUND_START 时 E 声明 INTENT_ATTACK(target=A)；随后 A 被击倒（A.is_alive=false）；enemy_turn_started(E.id) 发出
- Then: E 执行 stale_fallback；若场上有其他存活 ally B → execute_attack(E.id, B.id) 被调用；若无存活 ally → mark_has_acted(E.id) 调用（INTENT_WAIT 效果）；enemy_actions_completed(E.id) 发出

**AC-11：确定性保证**
- Given: 相同棋盘状态（unit positions, hp, is_alive），对同一 BEHAVIOR_MELEE 单位执行两次独立意图评估
- Then: 两次返回的 IntentRecord 完全相同（action_type, target_id, target_pos 均一致）

**AC-12：已死亡敌方不声明意图**
- Given: ROUND_START；enemy E 的 is_alive == false
- Then: intent_declared 信号不携带 E.id；intent_registry 中无 E.id 条目

**AC-13：enemy_actions_completed 触发回合推进**
- Given: E 的 INTENT_WAIT 执行完毕，enemy_actions_completed(E.id) 发出
- Then: 回合管理系统推进队列至下一单位（`enemy_turn_started` 不再次为 E 触发；同一 ROUND 中 E 只行动一次）

**AC-14：battle_started 清空 intent_registry**
- Given: 上一场战斗结束后 intent_registry 含残留数据；新战斗 battle_started 发出
- Then: intent_registry 清空为空字典；下一 ROUND_START 正常声明新意图

**AC-15：stale_fallback 补发 intent_declared**
- Given: E 声明 INTENT_ATTACK(target=A)；A 在己方回合移出射程（is_valid_attack=false）；enemy_turn_started(E.id) 发出；E 的 stale_fallback 找到新目标 B
- Then: `intent_declared(E.id, new_intent_with_target_B)` 信号在 execute_attack 之前发出；new_intent 的 target_id == B.id；enemy_actions_completed(E.id) 在 execute_attack 之后发出

**AC-16：BEHAVIOR_RANGED 无法后退时退化为攻击**
- Given: RANGED 单位 E；ally A 在 manhattan=1（过近）；get_reachable_cells 返回的所有格距 A 均 ≤ 1（无法拉开距离）；is_valid_attack(E.id, A.id)==true
- Then: intent_registry[E].action_type == INTENT_ATTACK(A)（退化为就地攻击，不发出 INTENT_MOVE）

## Open Questions

**OQ-1（Alpha 试玩后决策）：敌方职业动词**
MVP 中 AI 不使用职业动词。Alpha 阶段是否为部分敌方原型引入动词使用（如守卫型使用"挡"自保）？影响 has_used_verb 消耗逻辑和 AC 覆盖范围。

**OQ-2（战斗地图设计阶段决策）：behavior_type 的精细度**
当前 4 种原型是否足够覆盖所有关卡设计需求？若战斗地图设计者需要"主动追击但不打最近单位（打最孤立单位）"等混合行为，是否拆分原型或引入优先级权重系统？

**OQ-3（垂直切片后决策）：多意图声明（每轮2次行动的精英敌人）**
精英或 Boss 单位是否需要在单回合内声明多条意图（move + attack + verb）？若引入，IntentRecord 须改为 IntentSequence，影响 HUD 显示复杂度和 AC 覆盖范围。不在 MVP 范围内。

**OQ-4（性能评估后决策）：意图预计算时机**
当前设计在 `ROUND_START` 同步声明全部意图。若单位数量增多（e.g., 12 个敌人）且决策树复杂，是否需要异步逐帧分摊（Godot `await` 或协程）？需性能测试后决定。
