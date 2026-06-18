# 回合管理系统 (Turn Management System)

> **Status**: Approved
> **Author**: user + agents
> **Last Updated**: 2026-06-13
> **Implements Pillar**: 关键回合的爆发（计时骨架）；十分钟一场爽局（节奏约束）

## Overview

回合管理系统是《孤帆棋海》战斗的时序仲裁者——一个显式状态机，回答"谁在何时行动、能做什么、战斗何时结束"。它维护两条并行时间线：**轮次（Round）层**在每轮开始时按 `move_range` 降序建立全体单位（己方 + 敌方）的先攻队列，速度高者优先；**行动（Action）层**管理当前单位的三个独立行动点——**移动**、**攻击**、**职业动词**，每点消耗后本轮不可复用，可以任意顺序使用。轮次结束时，本系统重置所有单位的行动状态并推进轮次计数器；当敌方全员 Downed 时宣告胜利，当轮次计数达到上限时宣告失败。本系统不含任何战斗逻辑：伤害归战斗解算，几何判定归棋盘，AI 决策归意图系统——它只发出"你的回合开始 / 结束"事件，不关心事件期间发生了什么。没有它，下游四个系统会各自定义时序并产生竞态冲突；有了它，"等待关键回合引爆羁绊"才有了可计划的时间坐标。

> ⚠️ **原型基线偏差**：原型采用玩家先行 + 攻击即结束整个行动的简化模型。本 GDD 升级为速度先攻 + 三部分行动模型——**需在引擎垂直切片中验证节奏感，尤其是三行动点对"十分钟一场爽局"的影响。**

## Player Fantasy

本系统是纯基础设施——玩家永远不会说"我喜欢这个回合管理系统"。他们说的是：**"我知道这一回合我还能做什么。"**

本系统服务的幻想是**可预期的爆发窗口**：因为先攻顺序由移动力决定且每轮公开，玩家可以提前计算"我的炮手会在铁壁之前还是之后行动"，并以此构建"下一回合那一瞬间"的战术预谋。支柱"**关键回合的爆发**"依赖的正是这种可计划性——如果时序不可知，爆发就无法被精心等待，计算的热血变成碰运气的惊喜。

三行动点模型（移动 + 攻击 + 职业动词）为每个单位创造了一条微型决策序列：先移动还是先用职业动词？把攻击留给最有羁绊价值的位置，还是先清掉眼前威胁？这条决策序列是"小棋盘大组合"在单个行动层面的映射——每格、每个行动点都承载选择的重量。

**体验红线**：先攻顺序对玩家不透明（"为什么那个敌人先动了？"），或行动点消耗状态在 UI 上不清晰——两者都会打破对"可预期"的信任，让精心规划感觉无意义。

> *creative-director 未参与本节起草 — Lean mode。生产前请人工复核。*

## Detailed Design

### Core Rules

1. **战斗层级**
   - 战斗由若干**轮次（Round）**组成；每轮次内所有在场单位（己方 + 敌方）依先攻顺序各行动一次

2. **先攻队列**
   - 每轮次开始时，将所有在场存活单位按 `move_range` 降序排序，建立本轮**先攻队列**
   - **平局规则**：相同 `move_range` 时己方单位优先于敌方单位（己方战胜）
   - 队列一旦建立，本轮内不重建；轮次中途 Downed 的单位跳过其未到来的行动

3. **三行动点模型**
   - 轮到某单位时，拥有三个**独立行动点**，可任意顺序使用：
     - **移动**（`has_moved`）：最多移动 `move_range` 步（委托网格棋盘系统）
     - **攻击**（`has_acted`）：发动一次攻击（委托战斗解算系统）
     - **职业动词**（`has_used_verb`）：职业专属动作——治疗/守护/光环/位移/演奏（效果归战斗解算系统）
   - 三点可任意组合，可只用部分点结束回合；**未使用的点本轮作废，不结转**
   - 决策层级：**攻击行动是爆发核心**，移动与职业动词服务于取得最优攻击位置；玩家感知到的主决策是"这一轮我要打谁"

4. **行动点重置**
   - 每轮次开始时，全部在场单位的三个行动标记重置为 `false`

5. **胜利条件**
   - 任意时刻：所有敌方单位进入 Downed 状态 → 立即发出 `battle_won` 信号，切换至 `BATTLE_WIN`（不等当前轮次结束）

6. **失败条件**
   - 轮次结束时：`round_count` 达到 `ROUND_LIMIT` → 发出 `battle_lost` 信号，切换至 `BATTLE_LOSS`

7. **系统边界**
   - 本系统**不执行**任何移动、攻击、治疗、位移逻辑；所有行动合法性由各自下游系统校验

### States and Transitions

**战斗全局状态**

| 状态 | 描述 | 进入条件 |
|---|---|---|
| `SETUP` | 部署阶段：玩家选择出战单位（上限 `DEPLOY_LIMIT=4`） | 战斗初始化 |
| `ROUND_START` | 构建先攻队列，重置全体行动标记，推进 `round_count` | 部署完成 / `ROUND_END` 未触发胜负 |
| `ACTIVE_TURN(unit_id)` | 当前单位行动中（玩家输入或 AI 执行） | 队列取下一单位 |
| `TURN_END` | 当前单位结束行动，推进队列指针 | 单位主动结束 / 三点均消耗 |
| `ROUND_END` | 队列为空，检测 `round_count` vs `ROUND_LIMIT` | 队列遍历完毕 |
| `BATTLE_WIN` | 胜利终态 | 任意时刻敌方全 Downed |
| `BATTLE_LOSS` | 失败终态 | `ROUND_END` 时计数达 `ROUND_LIMIT` |

**UnitInstance 三行动标记（每轮重置）**

| 标记 | 类型 | 重置时机 |
|---|---|---|
| `has_moved` | bool | `ROUND_START` |
| `has_acted` | bool | `ROUND_START` |
| `has_used_verb` | bool（**新增字段**） | `ROUND_START` |

> ✅ **跨 GDD 冲突已解决（2026-06-13）**：unit-data-system.md 已同步更新，UnitInstance 新增 `has_used_verb` 字段，行动状态模型改为三独立 bool，初始化规则已写入 States and Transitions 节。

### Interactions with Other Systems

| 调用方/接收方 | 接口 | 方向 | 说明 |
|---|---|---|---|
| 网格棋盘系统 | `place_unit / remove_unit` | 调用 | 部署阶段写入单位位置 |
| 单位数据系统 | `UnitInstance.has_moved/acted/verb` | 写入 | 本系统是唯一重置方 |
| 战斗解算系统 | `unit_turn_started(unit_id)` / `unit_turn_ended(unit_id)` | 发出信号 | 通知当前行动单位 |
| 敌人 AI 系统 | `enemy_turn_started(unit_id)` | 发出信号 | AI 接收后生成并执行意图 |
| 敌人 AI 与意图系统 (#7) | `enemy_actions_completed(unit_id)` | 接收信号 | AI 执行完毕后发出；本系统订阅此信号以结束敌方 ACTIVE_TURN（等价于玩家点击"结束回合"）；状态转换：`ACTIVE_TURN(enemy)` → 收到 `enemy_actions_completed` → `TURN_END` |
| 相邻羁绊系统 | `round_ended()` | 发出信号 | 轮末羁绊充能结算时机（归羁绊 GDD 裁决） |
| 爆发演出系统 | `battle_won()` | 发出信号 | 胜利演出触发 |
| 羁绊槽与爆发技系统 (#6) | `battle_started()` | 发出信号 | 部署完成进入战斗（SETUP → 首次 ROUND_START 转换时）；bond gauge 订阅以归零；每场战斗 emit 一次 |
| 羁绊槽与爆发技系统 (#6) | `mark_has_acted(unit_id)` / `mark_has_used_verb(unit_id)` | 接口被调用 | 爆发技激活时消耗 lead.has_acted 和 partner.has_used_verb |
| 测试接口 | `get_event_log() → Array[String]` | 只读 | 每轮记录关键事件名称（至少含 `"last_round_warning"`、`"build_queue"`）；每次 ROUND_START dispatch 时清空，仅保留本轮事件；供 GUT 测试验证信号时序顺序（参见 AC-17）；仅在 debug/test 构建中启用（GUT 测试套件视为 test 构建，该接口在 GUT 环境中始终可用；生产构建禁用） |

## Formulas

### 公式 1：先攻优先值

```
initiative(u) = move_range(u) × 2 + (is_ally(u) ? 1 : 0) + tiebreak(u)
```

- `move_range`：整数，范围 [1, 4]（单位数据系统锁定值）
- `is_ally`：布尔值，己方=1 / 敌方=0
- `tiebreak(u)`：`(unit_id % 1000) * 0.000001`（纯整数取模 + 浮点缩放，结果域 [0, 0.001)；GDScript 安全，无浮点 mod 问题）
- 排序方向：降序（大者先行）
- 值域：[2.000, 9.001]

> **约束**：`move_range` 必须为正整数；`unit_id` 在单场战斗内必须全局唯一且 < 1000（防止 tiebreak 碰撞导致排序不稳定）；`tiebreak` 权重必须 < 0.5（否则颠覆阵营优先规则）。
>
> **运行时防御**：系统初始化时须执行 `assert unit_id < 1000`；违反时拒绝单位加入战斗并抛出配置错误（而非静默降级）。

---

### 公式 2：单位仍可行动判定

```
can_still_act(u) = NOT (u.has_moved AND u.has_acted AND u.has_used_verb)
```

> **初始化契约（归单位数据系统执行）**：无职业动词的单位出生时令 `has_used_verb = true`，防止该单位被误判为"尚可行动"而空跑一轮。公式本身无需修改。

---

### 公式 3（事件钩子）：胜利判定

```
ON_UNIT_DOWNED(unit_id):
    if battle_state == SETUP: return  # 守卫：部署阶段不响应，防止测试/特殊关卡误触发
    if battle_state in {BATTLE_WIN, BATTLE_LOSS}: return  # 终态不可重入
    if count(alive_enemies_on_board) == 0:
        emit battle_won()
        → 切换至 BATTLE_WIN
```

> **注**：这是事件驱动钩子，不是轮次轮询公式。触发点：任意敌方单位进入 Downed 状态后立即执行，不等当前轮次结束。
>
> **实现顺序契约（不可违反）**：必须先将被击倒单位从 `alive_enemies_on_board` 中移除，再广播 `ON_UNIT_DOWNED` 事件。若顺序颠倒，最后一个敌人 Downed 时计数仍为 1，`count == 0` 永不成立，胜利无法触发。
>
> **封装要求**：建议将"移除 + 广播"两步封装在 `resolve_unit_downed(unit_id)` 单一函数内，禁止外部系统直接操作 `alive_enemies_on_board` 后再自行广播。此顺序由 AC-18 进行自动化验证。

---

### 公式 4：失败判定

```
ON_ROUND_END:
    if round_count >= ROUND_LIMIT:
        emit battle_lost()
        → 切换至 BATTLE_LOSS
```

> **初始值约定**：`round_count` 初始值 = 0；`ROUND_START` 时先递增再执行本轮逻辑（第 1 轮结束时 `round_count = 1`，第 8 轮结束时 `round_count = 8`，触发失败）。使用 `>=` 以防御意外跳值。`ROUND_LIMIT` 具体值见 Tuning Knobs 节。

## Edge Cases

| 情形 | 处理规则 |
|---|---|
| **当前行动单位在本轮行动期间被 Downed**（反伤/被动技触发） | 立即结束当前回合 → 推进队列到下一单位；同时触发 `ON_UNIT_DOWNED` 胜利检测 |
| **非当前单位在他方回合被 Downed**（羁绊反伤等） | 标记该单位已 Downed；跳过其在队列中的剩余行动；`ON_UNIT_DOWNED` 即时检测胜负 |
| **最后一个敌方 Downed 时 `round_count` 同时达到 `ROUND_LIMIT`** | 胜利优先：`ON_UNIT_DOWNED` 先于 `ROUND_END` 触发，进入 `BATTLE_WIN`；不进入 `BATTLE_LOSS` |
| **玩家未消耗任何行动点即主动结束回合** | 合法。系统不强制使用行动点；三点均可弃用 |
| **`ROUND_START` 时队列为空**（无任何存活单位） | 防御性处理：直接跳至 `ROUND_END`。实际不应发生——战斗开始须至少有一方单位在场 |
| **轮次建立后有新单位加入**（召唤/增援/特殊技能） | 本系统不处理：队列一旦建立本轮不重建。新单位等下一 `ROUND_START` 才纳入队列。召唤机制归战斗解算系统裁决 |
| **`move_range = 0` 的单位**（被锁链/减益致速度归零） | `initiative = 0×2 + ally_bonus + tiebreak`；排队列末尾。移动步数 = 0，但攻击与职业动词仍可使用 |
| **`ROUND_START` 时 `round_count` 递增后 == `ROUND_LIMIT - 1`**（下一轮即为最后一轮） | 在 build_queue 执行前发出 `last_round_warning()` 信号；HUD 展示"下一轮是最后回合"提示，给玩家完整一轮时间保存关键技能，避免"无预警规则惩罚"的感知 |

## Dependencies

### 上游依赖（本系统依赖这些系统）

| 系统 | 依赖内容 | 接口 | GDD 状态 |
|---|---|---|---|
| 单位数据系统 (#1) | 读取每个单位的 `move_range` 以排序先攻队列；读写 `has_moved / has_acted / has_used_verb` 三行动标记 | `UnitInstance.move_range`, `.has_moved`, `.has_acted`, `.has_used_verb` | Designed — pending review |
| 网格棋盘系统 (#2) | 部署阶段调用放置/移除接口；查询当前在场存活的敌方单位列表（用于胜利检测） | `place_unit(unit_id, cell)`, `remove_unit(unit_id)`, `get_alive_enemies()` | Approved |

### 下游依赖（这些系统依赖本系统）

| 系统 | 依赖内容 | 接收信号 | GDD 状态 |
|---|---|---|---|
| 战斗解算系统 (#4) | 知道"轮到谁"才能执行攻击/技能逻辑 | `unit_turn_started(unit_id)`, `unit_turn_ended(unit_id)` | Not Started |
| 敌人 AI 与意图系统 (#7) | 接收"敌方回合开始"后生成行动意图 | `enemy_turn_started(unit_id)` | Not Started |
| 相邻羁绊系统 (#5) | 在轮末触发羁绊充能结算（是否轮末充能由羁绊 GDD 裁决） | `round_ended()` | Not Started |
| 爆发演出系统 (#8) | 胜利演出触发 | `battle_won()` | Not Started |
| 战后结算系统 (#15) | 失败结算触发 | `battle_lost()` | Not Started |
| 战斗 HUD 系统 (#9) | 最后一轮预警展示 | `last_round_warning()` | Not Started |

### 双向一致性契约

- **单位数据系统**：`has_used_verb` 字段已同步新增至 `UnitInstance`（2026-06-13 解决，unit-data-system.md 已更新）
- **网格棋盘系统**：其 GDD 的 Interactions 节须反向记录"回合管理系统依赖 `get_alive_enemies()`"
- 下游四个系统（战斗解算、AI、羁绊、演出）的 GDD 在撰写时须在其 Dependencies 节声明对本系统的依赖

## Tuning Knobs

| 旋钮 | 位置 | 推荐初始值 | 安全范围 | 影响 |
|---|---|---|---|---|
| `ROUND_LIMIT` | `design/registry/entities.yaml` | 8 | [5, 12] | 主节奏约束——决定一场战斗最长持续多少轮。值越低，玩家压迫感越强但容错率越低；值越高，容错率上升但"十分钟爽局"风险增加。建议以 8 为基线，垂直切片阶段用真实职业数据校准 |
| `DEPLOY_LIMIT` | `design/registry/entities.yaml` | 4（已锁定） | — | 每场战斗己方出战人数上限，影响先攻队列长度和行动总量；已由单位数据系统 GDD 锁定，本系统不可单独修改 |

> **注**：先攻规则（己方平局优先）和三行动点模型为已锁定设计决策，不是旋钮——修改需重新评审本 GDD。

## Visual/Audio Requirements

本系统为纯逻辑层，**不直接驱动任何视觉或音频资源**。演出触发通过信号由下游系统响应。

| 事件 | 信号 | 预期演出归属 |
|---|---|---|
| 单位回合开始 | `unit_turn_started(unit_id)` | 战斗 HUD 高亮当前行动单位；由 HUD 系统响应 |
| 敌方回合开始 | `enemy_turn_started(unit_id)` | AI 意图图标显示（意图系统负责）；HUD 更新 |
| 轮次结束 | `round_ended()` | 轮次计数器 UI 更新；由 HUD 系统响应 |
| 胜利 | `battle_won()` | 胜利演出全屏效果；由爆发演出系统响应 |
| 失败 | `battle_lost()` | 失败结算画面；由战后结算系统响应。`defeat_sequence` 过渡动画须在 `battle_lost` 广播前启动（或并行），避免结算截断最后一刻的演出 |
| 最后一轮预警 | `last_round_warning()` | 回合计数区预警提示（"下一轮是最后回合！"）；由 HUD 系统响应 |

> 本节仅定义信号归属契约。具体演出内容在爆发演出系统 (#8) 和战斗 HUD 系统 (#9) 的 GDD 中详细规划。

## UI Requirements

本系统不实现任何 UI，但定义玩家**必须能读取**的信息契约，由战斗 HUD 系统 (#9) 实现。

| 信息 | 触发时机 | 优先级 | 体验红线 |
|---|---|---|---|
| **先攻队列顺序**：当前轮次所有单位的行动顺序（含己方/敌方）；各单位的 initiative 值须可读取（可选：展开显示"移动力 × 2 + 阵营加成"明细）。**格式指导**：HUD GDD 建议对 initiative 值取整显示（如 `round(initiative)`），内部排序仍使用原始浮点值，避免小数噪声（如 7.000001）直接暴露给玩家 | `ROUND_START` 建立队列时 | 必须可见 | 公式含 ally_bonus 等隐藏权重——若玩家看不到最终 initiative 值，无法反推顺序，破坏"可预期"幻想 |
| **当前行动单位**：高亮标注哪个单位正在行动 | `ACTIVE_TURN(unit_id)` 进入时 | 必须可见 | — |
| **行动点状态**：当前单位三个行动点（移动/攻击/职业动词）的已用/未用状态 | `ACTIVE_TURN` 中每次行动点变化时实时刷新 | 必须可见 | 状态不清晰让玩家无法规划（见 Player Fantasy） |
| **轮次计数**：当前轮次 / `ROUND_LIMIT` | `ROUND_START` 推进时 | 必须可见 | — |
| **胜负状态**：战斗结果（进入 `BATTLE_WIN` / `BATTLE_LOSS`） | 切换终态时 | 全屏覆盖 | — |
| **行动点视觉层级**：攻击行动（`has_acted`）在行动点选择界面中须有视觉区分（高亮或优先位置），与 Core Rules 的"攻击是爆发核心"决策层级声明对齐 | `ACTIVE_TURN` 期间 | 必须有层级 | 三个行动点平等展示会弱化玩家感知"打谁"是主决策（见 Player Fantasy） |
| **先攻 tiebreak 顺序提示**：同阵营同速时，UI 须提供可感知提示说明行动顺序依据（如 tooltip 显示"同速时出场编号较大的单位优先行动"）。此处"出场编号"指部署阶段的部署顺序（1 = 首个部署），具体视觉映射由 HUD GDD 裁决 | `ROUND_START` 建立队列时（tooltip 即时可查） | 建议可见 | 若不提示，玩家无法预判同速同阵营单位的顺序，轻微破坏"可预期"幻想 |

> 展示方式（图标、进度条、队列轴等）由 HUD GDD 决定；本节只规定**必须展示什么**。

## Acceptance Criteria

**AC-01** 先攻队列——基础降序排序
- Given: `ROUND_START` 触发，场上存在单位 A（initiative=8）和单位 B（initiative=5）
- When: 系统生成本轮行动队列
- Then: 队列中 A 排在 B 之前，A 先获得 `ACTIVE_TURN`

**AC-02** 先攻队列——同速平局己方优先
- Given: 己方单位 P（`move_range=3`, `unit_id=1`，initiative = 7.000001）与敌方单位 E（`move_range=3`, `unit_id=2`，initiative = 6.000002）
- When: `ROUND_START` 生成队列
- Then: P 排在 E 之前（`ally_bonus=1` 确保 P > E，即使 move_range 相同）

**AC-02b** 先攻队列——同阵营同速由 tiebreak 决定
- Given: 两个己方单位 P1（`move_range=3`, `unit_id=1`，initiative = 7.000001）和 P2（`move_range=3`, `unit_id=5`，initiative = 7.000005）
- When: `ROUND_START` 生成队列
- Then: P2 排在 P1 之前（unit_id 较大者 tiebreak 值较大，initiative 较高）；结果稳定，不出现随机翻转

**AC-03** 行动点初始化——每轮全部重置
- Given: 上一轮某**存活**单位 X（`is_alive == true`）已消耗 `has_moved=true`、`has_acted=true`、`has_used_verb=true`
- When: 下一个 `ROUND_START` 事件触发
- Then: X 的三个标记全部重置为 `false`（不论上轮使用情况）

**AC-04** 无动词单位——出生时 has_used_verb 预置
- Given: 一个 `class_action_id = null`（即无职业动词能力）的单位实例被创建加入战场
- When: 该单位实例完成初始化
- Then: `has_used_verb == true`，`has_moved == false`，`has_acted == false`

**AC-05** 三行动点独立性——任意顺序使用
- Given: 单位进入 `ACTIVE_TURN`，三标记均为 `false`
- When: 依次执行顺序为"动词 → 移动 → 行动"（非默认顺序）
- Then: 三个标记分别在对应操作后单独置为 `true`，彼此不干扰；回合结束时三标记均为 `true`

**AC-06** 玩家弃用行动点——直接结束合法
- Given: 单位进入 `ACTIVE_TURN`，三标记均为 `false`（尚未使用任何行动点）
- When: 玩家直接触发"结束回合"指令
- Then: 系统接受指令，进入 `TURN_END`，三标记不被消耗（保持 `false`），不报错、不拦截

**AC-07** 轮次中途单位 Downed——跳过队列剩余行动
- Given: 当前轮队列为 [A, B, C]，轮到 B 之前 B 被 Downed
- When: 系统推进到 B 的队列位置
- Then: B 的 `ACTIVE_TURN` 不被触发，队列直接推进至 C

**AC-08** 当前行动单位 Downed——立即结束其回合
- Given: 单位 A 正处于 `ACTIVE_TURN`，`has_moved=true`，`has_acted=false`
- When: A 在本回合内被 Downed
- Then: A 的 `ACTIVE_TURN` 立即结束，进入 `TURN_END`，不等待剩余行动点耗尽

**AC-09** 胜利条件——最后一个敌方 Downed 立即触发
- Given: 场上只剩一个敌方单位，`round_count=3`，`ROUND_LIMIT=8`
- When: 调用 `resolve_unit_downed(enemy_unit)`
- Then: 系统立即发出 `battle_won` 信号，状态进入 `BATTLE_WIN`，不等待 `TURN_END` 或 `ROUND_END`

**AC-10** 失败条件——轮次到达上限触发
- Given: `round_count=ROUND_LIMIT`，至少一个敌方单位仍存活
- When: `ROUND_END` 事件触发
- Then: 系统发出 `battle_lost` 信号，状态进入 `BATTLE_LOSS`

**AC-11** 胜利优先于失败——同时满足两条件取胜利
- Given: `battle_state = ACTIVE_TURN`（队列中最后一个单位正在行动），`round_count == ROUND_LIMIT`，`alive_enemies_on_board.size() == 1`（最后一个敌方单位 hp > 0）；`ROUND_END` 事件尚未 dispatch
- When: 调用 `resolve_unit_downed(last_enemy_id)`
- Then: 系统发出 `battle_won`，进入 `BATTLE_WIN`；后续 `ROUND_END` 到来时 `battle_lost` 不发出，不进入 `BATTLE_LOSS`（终态守卫 AC-12 保障）

**AC-12** 状态机合法路径——不可从终态回退
- Given: 系统已进入 `BATTLE_WIN` 或 `BATTLE_LOSS`
- When: 任意后续事件到达（如 `ON_UNIT_DOWNED`、`ROUND_END`）
- Then: 状态保持 `BATTLE_WIN` 或 `BATTLE_LOSS` 不变，不转移至其他战斗状态

**AC-13** 多敌批量 Downed——battle_won 仅发一次
- Given: 场上剩余 3 个敌方单位（`id_A`, `id_B`, `id_C`）；`handle_downed_batch(ids: Array)` 为测试辅助接口，内部按序对每个 id 调用 `resolve_unit_downed(unit_id)`，通过终态守卫（AC-12）确保 `battle_won` 仅 emit 一次
- When: 调用 `handle_downed_batch([id_A, id_B, id_C])`（绕过帧调度边界，模拟同批次 Downed）
- Then: `battle_won` 信号 emit_count == 1，状态唯一进入 `BATTLE_WIN`，不重复发送

**AC-14** ROUND_END 时 round_count 未达上限——不触发失败
- Given: `round_count=ROUND_LIMIT-1`，存在敌方存活单位
- When: `ROUND_END` 事件触发
- Then: 系统不发出 `battle_lost`，状态进入下一个 `ROUND_START`，`round_count` 递增

**AC-15** Downed 单位——跨轮永久移除
- Given: 单位 B 在第 N 轮被 Downed，第 N 轮队列中已跳过其行动
- When: 第 N+1 轮 `ROUND_START` 建立新队列
- Then: B 不出现在新队列中；B 的 `has_moved`/`has_acted`/`has_used_verb` 在 `ROUND_START` 期间不被重置（Downed 单位跳过行动标记重置遍历）

**AC-16** round_count 递增时机——ROUND_START 前置
- Given: 当前 `round_count = 2`（前两轮已完成）
- When: 第 3 次 `ROUND_START` 事件触发
- Then: `round_count` 在本轮任意单位行动开始之前已变为 3（递增先于行动队列建立）

**AC-17** last_round_warning——倒数第二轮准确触发
- Given: `round_count` 当前值为 `ROUND_LIMIT - 2`（即将进入本轮 `ROUND_START`，递增前）
- When: `ROUND_START` 事件执行，`round_count` 递增为 `ROUND_LIMIT - 1`
- Then: `last_round_warning()` 信号 emit_count == 1；`system.get_event_log().find("last_round_warning") < system.get_event_log().find("build_queue")`（警告在队列建立前发出，玩家在倒数第二轮开始时获得"下一轮是最后回合"预告）

**AC-18** ON_UNIT_DOWNED 处理顺序契约——移除先于胜利检测
- Given: 场上仅剩最后一个敌方单位（`id = last_enemy`），`battle_state != SETUP`，`alive_enemies_on_board.size() == 1`
- When: 调用 `resolve_unit_downed(last_enemy_id)`
- Then: `alive_enemies_on_board.size() == 0` 在 `battle_won` 检查执行时已成立（单位在胜利检测前完成移除）；`battle_won` 信号正确 emit 一次

## Open Questions

1. **ROUND_LIMIT 最终值**：当前建议 8，需垂直切片实测数据（真实职业 + 真实敌人 AI）校准。待解决于：垂直切片阶段前。

2. ~~**has_used_verb 初始化归属**~~：**已解决（2026-06-13）**——unit-data-system.md 已同步更新：UnitInstance 新增 `has_used_verb` 字段，初始化规则写入 States and Transitions 节。

3. **轮次中途召唤/增援**：Edge Cases 节说明新单位等下一轮加入，但"召唤机制"本身由哪个系统裁决（战斗解算？战斗地图？）未定义。待解决于：相关系统 GDD 撰写时。

4. **反伤/被动触发的 ON_UNIT_DOWNED 检测时机**：系统设计上任何来源的 Downed 均应触发胜利检测，但被动触发时机需与战斗解算系统对齐，确保不绕过本系统的胜利判断。待解决于：战斗解算 GDD 撰写时。
