# 航线与招募系统 (Route & Recruitment System)

> **Status**: Approved（R2 复核通过，2026-06-17）
> **Author**: Chris + Claude Code agents
> **Last Updated**: 2026-06-17
> **Implements Pillar**: 羁绊即战术（船员构筑赋予站位决策意义）/ 十分钟一场爽局（run 结构为战斗赋予叙事弧）

## Overview

航线与招募系统是《孤帆棋海》肉鸽 run 结构的骨架，同时也是让单场战斗之间产生叙事意义的粘合剂。它管理一次出航（run）的全部生命周期：从 2 名船员起航、经过 4–6 座岛屿的战斗与招募、最终抵达终点头目战。每座岛屿呈现三张候选船员卡，玩家从中挑选一名加入队伍，逐步将阵容从双人小分队扩展至 8 人满编；系统追踪当前岛屿槽位、已有船员 roster、可用招募池（含悬赏成长解锁的新成员），并在每场战斗后向战斗地图系统请求重置，衔接进入下一岛屿。它不包含任何战斗逻辑——战斗属于其他七个下游系统的职责——它做的是「让每一场战斗都因为上一次的招募决定而不同」。若没有它，《孤帆棋海》退化为单局战棋而非"看着自己的海贼团一步步成型"的肉鸽旅程，「羁绊即战术」支柱失去构筑弧度的支撑。

## Player Fantasy

玩家感受到的核心情绪是**"这支船队是我一步步拼凑起来的"**。每次到岛看到三张候选卡，都是一次微型构筑决策：剑豪+乐手的精英羁绊配对已经成型，现在来了一个炮手——接 TA 意味着射程威胁，但伍里缺一个铁壁来给剑豪吸伤。没有正确答案，只有当下阵容和未来期望的张力。

这是「羁绊即战术」的构筑前戏：战场上的每次爆发技都是招募序列的回声。玩家不是在选一个数值更高的单位，而是在选「这个人加进来之后，我的队伍会打出一种新的羁绊组合」。满编 8 人后回望自己的阵容，能说出"她是第三岛来的，那时候我刚失去了那个铁壁"——**run 结构赋予每名船员一个故事位置**。

本系统也是「十分钟一场爽局」在 run 尺度的体现：每座岛的招募选择快速（< 30 秒决策窗口），不分心战斗节奏；胜利与失败后各有自然停顿，玩家可选择继续或搁置。失败即重航，损失可控，但下一次会带着"应该在第二岛选炮手而不是航海士"的具体教训重来。

## Detailed Design

### Core Rules

**Rule 1：Run 生命周期**

一次 run 由以下阶段序列构成：

```
RUN_INIT → ISLAND_0（战斗前无招募）→ [RECRUIT → ISLAND_1] → … → [RECRUIT → ISLAND_N-1] → ISLAND_N(BOSS) → RUN_END
```

- `ISLAND_0` 是第一场战斗（2 名起航船员直接参战，无前置招募）
- 每场战斗胜利后进入 RECRUIT 阶段，招募结束后推进至下一岛屿
- `ISLAND_N`（第 ISLAND_COUNT_MAX 场，末岛）战后直接进入 RUN_END（无最终招募）
- 垂直切片阶段：`ISLAND_COUNT_MAX = 5`（5 场战斗、4 次招募机会）；末岛为头目战

**Rule 2：起航编制**

- run 开始时，系统从 `recruit_pool_tier = "starting"` 的全部船员中取出所有记录，初始化 `roster`
- `STARTING_CREW = 2`（unit-data 常量；起航编制由单位数据配置决定，本系统不干预具体选择）
- 校验：若 starting tier 船员数 ≠ 2，记录错误并中止 run（单位数据系统负责在加载时校验此约束）

**Rule 3：招募流程**

每次战斗胜利后（非末岛）触发招募阶段：

1. 从当前可用候选池（`recruit_pool_tier = "pool"` 或 `"unlockable"`，且 unit_id 不在 `roster` 且不在 `_excluded_offers`）中**无放回随机抽取 RECRUIT_OFFER_COUNT（= 3）名候选**
2. 同一次三选一中，不允许两名或以上候选具有相同 `unit_class`（防止"全是剑豪"的无效选择），若候选池中某职业不足一名则豁免此约束
3. 候选名单通过 `get_recruit_offers()` 接口提供给航线与招募 UI
4. 玩家通过 `confirm_recruit(unit_id)` 选择其中 1 名加入 roster；其余 2 名候选加入 `_excluded_offers`（本 run 内不再出现）
5. 若 `roster.size() >= MAX_CREW（= 8）`，跳过招募阶段（已满编）
6. 若可用候选数 < RECRUIT_OFFER_COUNT，按实际数量展示；若可用候选 = 0，跳过并提示玩家

**Rule 4：船员 Downed 永久性（run 内）**

- 船员在战斗中触发 `unit_downed(unit_id)` 信号 → 本系统将其从 `roster` 中移出并加入 `_downed_this_run` 集合
- 该船员在本次 run 后续岛屿中**不参与部署、不进入招募候选**
- 永久死亡**不跨 run 持久化**：下一次 run 开始时，所有船员恢复完整状态
- 船员死亡的视觉/叙事反馈归**航线与招募 UI 系统**（本系统仅发出 `crew_member_downed(unit_id)` 信号）

**Rule 5：上场编制**

- 每场战斗前（含第一岛 ISLAND_0），系统进入 `RUN_DEPLOYING` 状态，等待出战编制确认
- 若 `roster.size() <= DEPLOY_LIMIT`，全员强制参战：系统自动调用 `confirm_deploy`（填入全员存活船员），不展示选择界面；`RUN_DEPLOYING` 立即转入 `RUN_ISLAND_BATTLE`
- 若 `roster.size() > DEPLOY_LIMIT`，系统在 `RUN_DEPLOYING` 等待玩家通过 UI 调用 `confirm_deploy(selected_ids)`（最多 4 人）
- 选定编制通过 `confirm_deploy(selected_ids)` 确认；本系统将该编制传递给战斗地图系统（用于 deploy zone 的初始化逻辑）

**Rule 6：战斗衔接**

1. 本系统调用 `battle_map_system.get_map_for_island(island_index) → MapDefinition` 获取地图定义
2. 发出 `map_load_requested(map_definition)` 触发地图加载，等待 `map_loaded` 信号
3. 发出 `battle_started`，战斗正式开始；本系统进入 `RUN_ISLAND_BATTLE` 状态，监听战斗结果信号
4. **战斗胜利（`battle_won`）**：
   - 处理 Downed 记录（更新 roster）
   - 发出 `map_reset_requested`（触发战斗地图系统清理）
   - `island_index += 1`
   - 末岛 → `RUN_END`；否则 → 触发 Rule 3 招募流程，随后进入 `RUN_DEPLOYING`
5. **战斗失败（`battle_lost`）**：
   - 发出 `map_reset_requested`
   - 触发 `RUN_END`（失败路径）

**信号顺序约束（接口契约）**：回合管理系统保证在同一战斗内，所有 `unit_downed` 信号必须在 `battle_won` / `battle_lost` 信号之前发出（Godot 同步信号链保证帧内顺序）。本系统在收到 `battle_won` 时依赖 `_downed_this_run` 已完整更新。若回合管理系统变更为异步发出战斗结果信号，须优先通知本系统。

**Rule 7：Run 结束**

- **胜利**：末岛战斗胜利 → 清理 run 状态 → 发出 `run_completed(won=true, island_count, roster_snapshot)`
- **失败**：任意战斗失败 → 清理 run 状态 → 发出 `run_completed(won=false, island_count, roster_snapshot)`
- **放弃**（玩家主动）：发出 `run_abandoned`；由存档系统处理持久化
- Run 状态清理内容：`roster` 重置、`island_index = 0`、`_excluded_offers` 清空、`_downed_this_run` 清空

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| `RUN_IDLE` | 无进行中的 run | 初始状态 / 上次 run 结束后 | 接收 `run_started` → `RUN_DEPLOYING` |
| `RUN_DEPLOYING` | 等待本岛出战编制确认 | `run_started`（首岛）/ 招募阶段完成后 | `roster.size() ≤ DEPLOY_LIMIT`（含 ISLAND_0 首局 roster=2）→ 系统自动调用 `confirm_deploy`（全员参战）→ `RUN_ISLAND_BATTLE`；`roster.size() > DEPLOY_LIMIT` → 收到 `confirm_deploy(selected_ids)` → `RUN_ISLAND_BATTLE` |
| `RUN_ISLAND_BATTLE` | 等待当前岛战斗结果 | `confirm_deploy` 处理完毕后（含首岛自动部署）| `battle_won` → 末岛? `RUN_END` : `RUN_RECRUITING`；`battle_lost` → `RUN_END` |
| `RUN_RECRUITING` | 呈现三选一候选，等待玩家决策 | 战斗胜利（非末岛）且 roster 未满编 | 玩家调用 `confirm_recruit` 或系统判定跳过（满编 / 无候选）→ `RUN_DEPLOYING` |
| `RUN_END` | run 已结算，等待清理与信号发出 | 末岛胜利 / 任意岛失败 | `run_completed` / `run_abandoned` 信号发出后 → `RUN_IDLE` |

**状态守卫**：
- 处于 `RUN_ISLAND_BATTLE` 时拒绝 `run_started`（run 进行中，不允许嵌套）
- 处于 `RUN_IDLE` 时忽略 `battle_won` / `battle_lost`（无 run 上下文）
- 处于 `RUN_DEPLOYING` 时忽略 `battle_won` / `battle_lost`（战斗尚未开始）
- 处于 `RUN_DEPLOYING` 时收到 `confirm_deploy` 包含非法 unit_id → 过滤非法项；若过滤后为空 → 拒绝并通知 UI 重新选择

### Interactions with Other Systems

| 系统 | 接口 / 信号 | 方向 | 说明 |
|------|------------|------|------|
| 单位数据系统 (#1) | `get_all_units_by_tier(tier) → Array[UnitDefinition]` | 调用 | 获取起航编制（"starting"）和可用候选池（"pool" + "unlockable"）的船员定义 |
| 战斗地图系统 (#10) | `get_map_for_island(island_index) → MapDefinition` | 调用 | 进入新岛屿时获取地图定义 |
| 战斗地图系统 (#10) | `map_load_requested(map_definition)` | 发出 | 触发战斗地图系统加载 |
| 战斗地图系统 (#10) | `battle_started` | 发出 | 通知战斗地图系统从 MAP_READY → MAP_ACTIVE |
| 战斗地图系统 (#10) | `map_reset_requested()` | 发出 | 战斗结束后触发地图清理（VS 阶段由本系统负责；MVP 阶段由回合管理系统代理） |
| 回合管理系统 (#3) | `battle_won()` / `battle_lost()` | 接收 | 战斗结果驱动 run 推进或失败 |
| 回合管理系统 (#3) | `unit_downed(unit_id)` | 接收 | 记录 run 内永久阵亡（war-time），战后从 roster 移除 |
| 悬赏成长系统 (#14) | `run_completed(won, island_count, roster_snapshot)` | 发出 | 通知 meta 进度层；具体解锁规则归悬赏 GDD |
| 悬赏成长系统 (#14) | `get_unlocked_units() → Array[String]` | 调用 | 获取当前已解锁的 unlockable tier 船员 id 列表，并入候选池 |
| 存档系统 (#13) | run 状态快照（island_index, roster, _excluded_offers） | 双向 | 存档系统负责序列化/反序列化；具体接口归存档 GDD |
| 航线与招募 UI (#12) | `get_roster() → Array[UnitInstance]` | 提供 | UI 读取当前存活 roster |
| 航线与招募 UI (#12) | `get_recruit_offers() → Array[UnitDefinition]` | 提供 | UI 读取三选一候选名单 |
| 航线与招募 UI (#12) | `confirm_recruit(unit_id: String)` | 接收 | 玩家在 UI 确认招募某船员 |
| 航线与招募 UI (#12) | `confirm_deploy(selected_ids: Array[String])` | 接收 | 玩家在 UI 确认本岛参战编制 |
| 航线与招募 UI (#12) | `crew_member_downed(unit_id: String)` | 发出 | UI 触发阵亡叙事反馈（本系统仅发信号，不控制呈现） |

## Formulas

### 公式 R1：招募候选池有效数量

`available_pool_size = count(u ∈ all_units : u.recruit_pool_tier ∈ {"pool", "unlockable"} AND u.unit_id NOT IN roster AND u.unit_id NOT IN _excluded_offers AND u.unit_id NOT IN _downed_this_run)`

| 变量 | 类型 | 范围 | 描述 |
|------|------|------|------|
| `all_units` | Array[UnitDefinition] | — | 单位数据系统中所有 faction=crew 的定义 |
| `roster` | Set[String] | size ∈ [2,8] | 当前 run 的存活船员 unit_id 集合 |
| `_excluded_offers` | Set[String] | size ∈ [0, n] | 本 run 内已被拒绝（落选）的候选 unit_id 集合 |
| `_downed_this_run` | Set[String] | size ∈ [0, n] | 本 run 内已永久阵亡的船员 unit_id 集合（含 pool tier 船员）；须排除以防止已阵亡的船员重新出现为候选 |

**输出范围**：0 ~ `total_pool_units - roster.size() - _downed_pool_count`  
**关键值**：`available_pool_size < RECRUIT_OFFER_COUNT(=3)` 时候选数量不足，按实际数量展示；`= 0` 时跳过招募

**示例**：全池 12 名 pool/unlockable 船员，roster 含 4 人，_excluded_offers 含 3 人，_downed_this_run 中 pool 船员 1 人 → available_pool_size = 12 - 4 - 3 - 1 = 4 ≥ 3，正常三选一

---

### 公式 R2：岛屿招募机会数

`RECRUIT_OPPORTUNITY_COUNT = ISLAND_COUNT_MAX - 1`

| 变量 | 类型 | 范围 | 描述 |
|------|------|------|------|
| `ISLAND_COUNT_MAX` | int（常量） | [4, 7] | 一次 run 的总岛屿数（含末岛头目战）；垂直切片阶段 = 5 |

**输出范围**：3 ~ 5（垂直切片阶段固定 4）  
**设计意图**：末岛之前的每场战斗胜利都有一次招募；末岛战斗本身无招募——给玩家一个"带着当前阵容完成最后考验"的最终章感

**示例**：ISLAND_COUNT_MAX=5 → 4 次招募机会 → 理论最大 roster = 2 + 4 = 6（未满编）；满编 8 人需要 ISLAND_COUNT_MAX ≥ 7——当前垂直切片版本**不设计满编 8 人**（game-concept 的"6 岛满编"对应 Full Vision 阶段 ISLAND_COUNT_MAX=7 时 STARTING_CREW=2+6次招募=8）

> **设计注意**：game-concept.md 描述"6 岛终局恰好 8 人满编"对应 ISLAND_COUNT_MAX=7、RECRUIT_OPPORTUNITY_COUNT=6。垂直切片阶段 ISLAND_COUNT_MAX=5，最多只能招募 4 名，roster 上限为 6 人——此差异是有意为之（内容量匹配单人开发能力）。

---

### 公式 R3：run 内船员幸存率（设计指标，不代码强制）

`survival_rate = (roster.size() - downed_count) / initial_roster_size`

| 变量 | 类型 | 说明 |
|------|------|------|
| `roster.size()` | int | run 结束时存活船员数 |
| `downed_count` | int | 本 run 内阵亡总数 |
| `initial_roster_size` | int | run 结束前总曾加入 roster 人数（起航 + 招募累计）|

**用途**：垂直切片情感测试指标——若 survival_rate 平均 < 0.5（超过一半船员死亡），说明永久死亡惩罚过重或战斗难度过高；若恒定 = 1.0（无人阵亡），说明死亡规则对玩家行为无压力，需调高战斗难度。目标范围：平均 survival_rate ∈ [0.6, 0.9]。

## Edge Cases

- **如果 roster 中仅剩 1 名存活船员**：游戏规则上不触发立即失败（失败条件归回合管理系统）；本系统允许单人参战（Rule 5：`roster.size()=1 ≤ DEPLOY_LIMIT` → 全员强制参战）。单人残局是合法局面，由战斗 GDD 的失败条件处理（`unit_downed` 后若 alive_list 为空 → `battle_lost`）。
- **如果 roster 中所有船员在单场战斗中全部被 Downed**：本系统在战斗结束时收到 `battle_lost`，执行 Rule 6 失败路径（`RUN_END`）。`_downed_this_run` 记录全员，但 run 已结束，不影响后续流程。
- **如果可用候选池在招募阶段为 0**：跳过招募（Rule 3 第 6 点），直接推进 `island_index` 进入下一岛屿。UI 系统展示"无新船员加入"提示。此情况仅在全部 pool/unlockable 船员均已在 roster 或 _excluded_offers 中时发生（极端情况，pool 极小时）。
- **如果玩家在招募阶段不选择（超时或跳过按钮）**：本系统等待 `confirm_recruit` 或等待 UI 发出 `recruit_skipped` 信号；收到任一信号后推进至下一岛屿。不强制选择（玩家可以主动放弃招募机会）。
- **如果 `get_map_for_island(island_index)` 返回 null**：记录错误，发出 `run_error(reason="no_map_for_island", island_index)` 信号；当前 run 中止并转入 `RUN_END`（视为失败路径，但标记为技术错误，不计入 run_completed 统计）。
- **如果战斗过程中 `battle_won` 和 `battle_lost` 先后都收到**（来自异常状态）：本系统遵循"胜利优先"原则（与回合管理系统的胜利/失败优先级一致）；仅处理第一个收到的信号，忽略后续。
- **如果存档系统恢复 run 状态后，roster 中的 unit_id 在单位数据系统中找不到定义**：记录警告并将该 unit_id 从 roster 移除（防止幽灵船员参战）；若 roster 恢复后大小 = 0，立即触发 `RUN_END`（失败路径）。
- **如果 `confirm_deploy` 传入的 selected_ids 包含不在 roster 中的 unit_id**：过滤非法 id，仅保留合法项；若过滤后为空，拒绝本次 confirm，通知 UI 重新选择（返回 `deploy_invalid` 原因）。
- **如果 `confirm_deploy` 传入的 selected_ids 数量 > DEPLOY_LIMIT（=4）**：截断至前 4 个，发出警告日志。UI 系统应在前端限制选择数量，此 guard 为防御性措施。

## Dependencies

### 上游依赖（本系统依赖）

| 系统 | GDD 存在 | 依赖内容 |
|------|---------|---------|
| 单位数据系统 (#1) | ✓ unit-data-system.md | `UnitDefinition` 数据结构、`recruit_pool_tier` 枚举、`get_all_units_by_tier()` 接口 |
| 战斗地图系统 (#10) | ✓ battle-map-system.md | `get_map_for_island(island_index)` 接口、`map_loaded` / `map_load_failed` 信号、`map_reset_requested` 信号（本系统负责发出）|
| 回合管理系统 (#3) | ✓ turn-management-system.md | `battle_won` / `battle_lost` 信号、`unit_downed(unit_id)` 信号 |
| 悬赏成长系统 (#14) | ✗ 未设计 | `get_unlocked_units()` 接口（待悬赏 GDD 定义）；MVP 阶段暂无 unlockable 船员，此依赖为 Soft（系统在无此接口时仍可运行） |

### 下游被依赖方（依赖本系统）

| 系统 | GDD 存在 | 依赖本系统的内容 |
|------|---------|---------------|
| 航线与招募 UI (#12) | ✗ 未设计 | `get_roster()`、`get_recruit_offers()`、`confirm_recruit()`、`confirm_deploy()` 接口；`crew_member_downed`、`run_completed` 信号 |
| 存档系统 (#13) | ✗ 未设计 | run 状态快照（`island_index`、`roster`、`_excluded_offers`）的读写接口 |
| 悬赏成长系统 (#14) | ✗ 未设计 | `run_completed(won, island_count, roster_snapshot)` 信号，用于触发 meta 进度解锁 |

### 关键接口契约

1. **unit-data → 本系统**：`get_all_units_by_tier("pool")` 和 `get_all_units_by_tier("unlockable")` 必须在 run 开始前可调用；MVP 阶段 unlockable 列表为空时返回空数组（不报错）
2. **本系统 → battle-map**：`map_load_requested` 在 `get_map_for_island` 返回有效 MapDefinition 后立即发出；本系统不缓存 MapDefinition，每岛重新获取
3. **回合管理 → 本系统（信号顺序约束）**：`unit_downed` 可在战斗进行中多次发出；本系统幂等处理（同一 unit_id 重复 downed 不报错）。**关键约束**：回合管理系统必须保证同一战斗内所有 `unit_downed` 在 `battle_won` / `battle_lost` 之前发出（Godot 同步信号默认满足此要求）
4. **本系统 → 悬赏成长**：`roster_snapshot` 是 run 结束时的 UnitDefinition id 数组（含阵亡），用于悬赏 GDD 判断"哪些船员完成了本次 run"（完整参与，不只是存活）
5. **`run_started` 来源**：MVP/VS 阶段由主菜单系统（#18）或临时 run-controller 脚本发出；Alpha 阶段明确归主菜单与设置系统所有。本系统仅监听此信号，不关心来源。

## Tuning Knobs

| 常量名 | 默认值 | 安全范围 | 游戏效果 |
|--------|--------|---------|---------|
| `ISLAND_COUNT_MAX` | 5 | [4, 7] | 一次 run 的总岛屿数（含末岛）；= 4 → run 极短（3 次招募，体验流量不足）；= 7 → run 超过 60 分钟目标；Full Vision 目标 = 7（满编 8 人） |
| `RECRUIT_OFFER_COUNT` | 3 | [2, 4] | 每次招募展示的候选数量；= 2 → 选择感弱（接近二选一），减少构筑分歧；= 4 → 分析瘫痪风险上升 |
| `SAME_CLASS_EXCLUSION` | true（布尔） | true / false | 同一次三选一内不允许重复职业；false 时放开，允许全是剑豪的极端情况（适合测试池极小场景） |
| `STARTING_CREW` | 2 | 固定（unit-data 常量） | 归 unit-data-system 所有，此处仅引用；不可通过本 GDD 修改 |
| `MAX_CREW` | 8 | 固定（unit-data 常量） | 同上；8 人是 DEPLOY_LIMIT=4 的 2 倍，保证满编时仍有阵容切换余地 |
| `DEPLOY_LIMIT` | 4 | 固定（unit-data 常量） | 同上；8×8 棋盘容纳 4 己方 + 最多 6 敌方，合计上限 10 单位仍保持阅读性 |

**招募节奏目标（设计参考，不代码强制）：**

| 岛屿 | island_index | 典型 roster 规模 | 战术意义 |
|------|-------------|----------------|---------|
| 第 1 岛（起航战） | 0 | 2 人 | 验证基础战斗；无构筑选择 |
| 第 2 岛 | 1 | 3 人 | 首次招募后，基础羁绊雏形出现 |
| 第 3 岛 | 2 | 4 人 | 首次满部署（DEPLOY_LIMIT=4 首次达到），部署选择出现 |
| 第 4 岛 | 3 | 5 人 | 阵容分歧拉开（第 5 人是"替补"还是"换核心"？） |
| 末岛（头目战） | 4 | 6 人 | 带全部家当迎接终局；不再招募，以现有阵容决战 |

## Visual/Audio Requirements

本系统为数据/状态层，视觉/音频需求较轻，主要通过信号通知 UI 系统处理。

- **船员 Downed 叙事反馈**：本系统发出 `crew_member_downed(unit_id)` 信号；具体的视觉（船员卡片变灰/消散）和音效（低沉鼓点或角色告别台词）由**航线与招募 UI** 系统实现
- **招募揭示时机**：本系统在 `get_recruit_offers()` 被调用时返回候选列表；UI 系统决定是否有"翻牌"揭示动画——本系统不阻塞在动画期间，仅提供数据
- **Run 结束画面**：本系统发出 `run_completed(won, island_count, roster_snapshot)` 后进入 `RUN_IDLE`；战后结算画面（System #15 战后结算系统）消费此信号并渲染结算 UI
- **背景音乐切换节点**：招募阶段（`RUN_RECRUITING`）vs 战斗阶段（`RUN_ISLAND_BATTLE`）音乐切换由音频系统（#17）监听本系统的状态信号实现；本系统在状态切换时发出 `run_phase_changed(phase: String)` 辅助信号（"BATTLE" / "RECRUITING" / "DEPLOYING" / "RUN_END"）供音频系统和 UI 系统消费。"DEPLOYING" 在进入 `RUN_DEPLOYING` 状态时发出（含首岛自动部署场景）

## UI Requirements

本系统通过接口和信号向**航线与招募 UI（#12）**提供数据。本系统**不负责任何界面渲染**。

**UI 需消费的接口（本系统提供）：**
- `get_roster() → Array[UnitInstance]`：船员列表面板（展示姓名、职业、当前 HP、阵亡标记）
- `get_recruit_offers() → Array[UnitDefinition]`：三选一卡片区（展示职业、倾向数值带、battle_cry 个性台词）
- `confirm_recruit(unit_id)` / `confirm_deploy(selected_ids)`：UI 按钮的后端接口
- `get_current_island_index() → int`：航线进度条显示（"第 2 岛 / 共 5 岛"）

**UI 需监听的信号：**
- `crew_member_downed(unit_id)`：触发船员卡阵亡动画
- `run_completed(won, island_count, roster_snapshot)`：进入战后结算画面
- `run_phase_changed(phase)`：控制背景 UI 氛围切换；"DEPLOYING" 相位触发部署界面（DeployScreen）显示

📌 **UX Flag — 航线与招募系统**：本系统有 UI 需求。在 Pre-Production 阶段，运行 `/ux-design` 为以下界面创建 UX 规范（在撰写 epic 之前）：
- 招募选择界面（三选一卡片布局）
- 部署选择界面（roster 中选 4）
- 航线进度条 / 岛屿地图
- 船员阵亡通知

各界面的故事应引用 `design/ux/route-recruitment.md`，而非直接引用本 GDD。

## Acceptance Criteria

**AC-1：起航编制正确初始化** 【集成测试】
- Given: unit-data-system 中 `recruit_pool_tier="starting"` 的船员恰好 2 名（ID: `crew_start_a`, `crew_start_b`）
- When: `run_started` 信号发出，本系统初始化
- Then: `get_roster()` 返回 `[crew_start_a, crew_start_b]`（顺序无要求）；系统状态为 `RUN_ISLAND_BATTLE`；`island_index = 0`

**AC-2：三选一候选不重复职业** 【单元测试】
- Given: `SAME_CLASS_EXCLUSION=true`；候选池中 unit_class 分布包含至少 3 种不同职业
- When: 调用 `get_recruit_offers()`
- Then: 返回的 3 名候选 `unit_class` 两两不同；无候选 unit_id 在当前 roster 或 `_excluded_offers` 中

**AC-3：招募后 roster 更新，落选者进入排除池** 【单元测试】
- Given: `get_recruit_offers()` 返回 [A, B, C]；玩家调用 `confirm_recruit("A")`
- When: 确认后
- Then: `get_roster()` 包含 A；B 和 C 的 unit_id 加入 `_excluded_offers`；B 和 C 在本 run 后续 `get_recruit_offers()` 中不出现

**AC-4：船员 Downed 后从 roster 永久移出** 【集成测试】
- Given: roster 含 [`crew_a`, `crew_b`, `crew_c`]；战斗中 `unit_downed("crew_b")` 信号触发
- When: 战斗结束（`battle_won`）后
- Then: `get_roster()` 不包含 `crew_b`；`crew_b` 出现在 `_downed_this_run` 中；下一次 `get_recruit_offers()` 也不包含 `crew_b`（已在 _downed_this_run 中）

**AC-5：战斗失败触发 RUN_END** 【集成测试】
- Given: 系统处于 `RUN_ISLAND_BATTLE` 状态
- When: 接收 `battle_lost` 信号
- Then: `map_reset_requested` 信号发出；`run_completed(won=false)` 信号随后发出；系统状态转为 `RUN_IDLE`；`island_index` 重置为 0

**AC-6：战斗胜利后 island_index 递增** 【单元测试】
- Given: 系统 `island_index = 2`，`ISLAND_COUNT_MAX = 5`
- When: 接收 `battle_won` 信号
- Then: `map_reset_requested` 发出；`island_index = 3`；系统进入 `RUN_RECRUITING` 状态

**AC-7：末岛战斗胜利触发 RUN_END** 【集成测试】
- Given: 系统 `island_index = 4`，`ISLAND_COUNT_MAX = 5`
- When: 接收 `battle_won` 信号
- Then: `map_reset_requested` 发出；`run_completed(won=true)` 发出；`island_index` 重置；系统状态 = `RUN_IDLE`

**AC-8：候选池耗尽时跳过招募** 【单元测试】
- Given: `available_pool_size = 0`（所有 pool/unlockable 船员均在 roster 或 _excluded_offers 中）
- When: 战斗胜利（非末岛），进入招募阶段
- Then: `get_recruit_offers()` 返回空数组；系统直接推进至下一岛屿（`RUN_ISLAND_BATTLE`）；UI 收到"无候选"通知

**AC-9：满编时跳过招募** 【单元测试】
- Given: `roster.size() = MAX_CREW = 8`
- When: 战斗胜利（非末岛），进入招募阶段
- Then: 系统直接推进至下一岛屿（不进入 `RUN_RECRUITING`）；`get_recruit_offers()` 不被调用

**AC-10：roster ≤ DEPLOY_LIMIT 时全员强制参战** 【单元测试】
- Given: `roster` 中存活 3 名船员，`DEPLOY_LIMIT = 4`
- When: 进入新岛屿战斗准备阶段
- Then: 本系统自动调用 `confirm_deploy` 传入全部 3 人；不展示部署选择界面（通知 UI 跳过部署选择）

**AC-11：confirm_deploy 过滤非法 unit_id** 【单元测试】
- Given: roster 含 [`a`, `b`, `c`, `d`]；调用 `confirm_deploy(["a", "b", "x"])` 其中 "x" 不在 roster 中
- When: 处理 confirm_deploy
- Then: 实际参战编制为 ["a", "b"]（过滤 "x"）；`deploy_invalid_ids = ["x"]` 记录到警告日志；若过滤后列表为空则返回错误并要求重新选择

**AC-12：RUN_ISLAND_BATTLE 状态下拒绝嵌套 run** 【单元测试】
- Given: 系统处于 `RUN_ISLAND_BATTLE` 状态
- When: 接收 `run_started` 信号
- Then: 信号被忽略；系统状态不变；警告日志记录"run already in progress"

**AC-13：`get_map_for_island` 返回 null 时 run 中止** 【集成测试】
- Given: `battle_map_system.get_map_for_island(island_index)` 返回 null（模拟地图缺失）
- When: 系统尝试推进至下一岛屿
- Then: `run_error(reason="no_map_for_island")` 发出；系统进入 `RUN_END`（失败路径）；`run_completed(won=false)` 发出，附带错误标记

**AC-14：垂直切片阶段本系统负责发出 map_reset_requested** 【集成测试】
- Given: 系统处于 VS 阶段配置（非 MVP 代理模式）；`battle_won` 信号收到
- When: 处理战斗胜利
- Then: 本系统（非回合管理系统）发出 `map_reset_requested`；`battle_map_system` 状态从 `MAP_RESOLVED` 转为 `MAP_UNLOADED`

**AC-15：第一岛（ISLAND_0）跳过招募直接自动部署进入战斗** 【集成测试】
- Given: `run_started` 触发，`island_index = 0`，roster = [crew_start_a, crew_start_b]（roster.size()=2 ≤ DEPLOY_LIMIT=4）
- When: 系统初始化 run
- Then: 不进入 `RUN_RECRUITING` 状态；系统进入 `RUN_DEPLOYING` 后立即自动调用 `confirm_deploy([crew_start_a, crew_start_b])`；随后进入 `RUN_ISLAND_BATTLE`；`get_recruit_offers()` 不被调用

**AC-16（已有 Rule 5 描述，暂挂起）：roster > DEPLOY_LIMIT 时系统在 RUN_DEPLOYING 等待玩家确认** 【集成测试】
- Given: roster.size() = 6（> DEPLOY_LIMIT=4）；战斗胜利（非末岛）且招募完成后
- When: 系统进入 `RUN_DEPLOYING`
- Then: 系统状态保持 `RUN_DEPLOYING`，不发出 `battle_started`；直至收到 `confirm_deploy(selected_ids)` 且 selected_ids.size() ≥ 1；确认后状态切换至 `RUN_ISLAND_BATTLE`；地图加载流程（Rule 6）启动

## Open Questions

| ID | 问题 | 负责方 | 目标解决阶段 | 影响 |
|----|------|--------|------------|------|
| OQ-1 | **落选候选是否本 run 不再出现**（当前规则）vs **仅本次岛屿排除**（下次招募可能重新出现）——"无放回"规则更强迫抉择，但池极小时可能快速耗尽候选；"仅本岛排除"规则更宽松，允许反悔但削弱选择不可逆感 | 本 GDD（已暂定：本 run 不再出现）| 垂直切片情感测试 | 影响 R1 公式的 `_excluded_offers` 语义和 AC-3 |
| OQ-2 | **招募阶段是否有"跳过（不选人）"选项**——允许跳过可给玩家"保存命运、不接受当前三选一"的选择权；禁止跳过则每岛必须招募，强化构筑决策的不可逆性 | 本 GDD | 垂直切片情感测试 | 影响 Rule 3 和 AC-8 |
| OQ-3 | **`map_reset_requested` 的 MVP 代理方**：当前规定 MVP 阶段由回合管理系统代理发出——是否在 MVP 阶段也由本系统发出（简化信号路由，消除 MVP/VS 阶段的行为分叉）？ | 本 GDD + 回合管理 GDD | MVP 实现前 | 影响回合管理 GDD 和 battle-map GDD 的信号所有权描述 |
| OQ-4 | **roster_snapshot 的精确内容**：`run_completed` 携带的 `roster_snapshot` 应包含全部曾加入 roster 的船员（含阵亡者），还是仅存活者？悬赏成长系统需要哪些字段来判断解锁条件？ | 悬赏成长 GDD（#14）设计时裁决 | Alpha 阶段 | 影响 `run_completed` 信号 payload 设计 |
