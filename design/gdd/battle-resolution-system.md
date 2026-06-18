# 战斗解算系统 (Battle Resolution System)

> **Status**: In Review
> **Author**: user + systems-designer + qa-lead
> **Last Updated**: 2026-06-14（R2 修订完成）
> **Implements Pillar**: 羁绊即战术（每个行动产生可预期的后果）；小棋盘大组合（职业动词的组合策略空间）

## Overview

战斗解算系统是《孤帆棋海》战斗行为的**执行引擎**——负责将"行动确认"事件转化为可量化的棋盘状态变更。它处理三类核心行为：①**普通攻击**（射程验证 → 伤害计算 → HP 扣减 → Downed 检测）；②**六职业动词执行**（剑豪·斩 / 炮手·轰 / 铁壁·挡 / 医师·愈 / 航海士·移 / 乐手·奏，各自独立语义）；③**击倒解算**（`resolve_unit_downed()`：移除存活列表 → 棋盘清格 → 广播事件，保证顺序）。它从回合管理系统接收"轮到谁行动"的信号，从相邻羁绊系统接收单向修正器注入，向羁绊槽与爆发技系统和战斗 HUD 暴露全量战斗事件信号。

本系统**不负责**：棋盘移动与格子合法性（网格棋盘系统）、行动顺序与先攻（回合管理系统）、相邻效果的具体加成值（相邻羁绊系统）、羁绊槽充能规则与爆发激活（羁绊槽与爆发技系统）、敌人意图生成（敌人 AI 系统）。职责边界：**行动确认后，数值变化、状态更新、事件广播。**

玩家视角：当剑豪的"斩"扫倒三个敌人、当铁壁的"挡"救下队友、当医师在最后一刻将铁壁从死亡线拉回——这些战术瞬间的"结果感"全部由本系统生产。它让 unit-data-system 的属性数字变成有重量的战场后果。

## Player Fantasy

**直接体验：计算有回报，行动有代价。**

玩家在确认每一次行动前，棋盘上的信息是完整的——敌人意图全明示（Into the Breach 设计契约；详见 Core Rules Rule 12）。这不是"感觉会发生什么"，而是"我知道会发生什么"。战斗解算系统的责任是让这种知情的理性选择与其后果之间的转化**无懈可击**：点"攻击"，伤害数就是那个数；点"职业动词"，效果就是声明的效果；没有黑箱，没有随机偏差，只有策略与执行的直接映射。

**家人幻想的战斗地基**：每个动词都有人的属性。剑豪的"斩"是粗暴的前冲；炮手的"轰"是对距离感的精准控制；医师的"愈"是对队友生命的承诺；铁壁的"挡"是为别人挡在前面的那种重量——这些语义不只存在于个性字段，更在每次战斗行动的机制里复现。

**体验红线（违反 = 本系统失职）**：
- 近战判定莫名失败（合法射程内攻击被拒绝，或炮手在射程外被允许）
- 伤害数字与 HP 变化对不上（钳制错误或精度问题）
- 职业动词效果不透明（"奏"到底给谁加了多少没有明确反馈）
- Downed 后单位仍可被选中或计入相邻（移除时序错误，信号前数据未更新）

## Detailed Design

### Core Rules

---

**Rule 1：普通攻击（Normal Attack）**

触发条件（全部为真时才允许执行）：
- `attacker.is_alive == true`
- `attacker.has_acted == false`
- `target.is_alive == true`
- `attacker != target`（不可自伤）
- `attacker.faction != target.faction`（不可攻击同阵营）
- `grid_board.in_attack_range(attacker.grid_position, target.grid_position, attacker.attack_range) == true`
- 若 `attacker.unit_class == gunner`：追加条件 `manhattan_distance(attacker.grid_position, target.grid_position) >= GUNNER_MIN_RANGE`（见 Rule 11）

执行步骤（按序不可跳过）：
0. emit `attack_initiated(attacker_id, "normal_attack")`（**触发通知**：仅在触发条件全部验证通过后发出；Godot 信号同步执行——相邻羁绊系统在信号回调中完成 `register_attack_modifier()` 注入后，步骤 0 返回，步骤 1 随即消费已注入的修正器）
1. 收集修正器：`modifier_sum = min(Σ pending_modifiers[attacker_id], MAX_MODIFIER_SUM)`（截断超额注入，防止两发击杀保证被破坏；见 Formulas Formula 1）
2. 计算光环加成：`aura_bonus = AURA_VALUE if attacker 持有 AURA_BONUS else 0`；若持有则消耗 `AURA_BONUS`
3. `final_damage = attacker.base_damage + modifier_sum + aura_bonus`（见 Formulas Formula 1）
4. 若 `target` 持有 `GUARDED` 状态：`final_damage = floor(final_damage / GUARD_DIVISOR)`；消耗 `GUARDED`
5. `new_hp = max(0, target.current_hp - final_damage)`
6. `target.current_hp = new_hp`（HP 钳制由本规则保证；`0 ≤ current_hp` 不变量）
7. 清空 `pending_modifiers[attacker_id]`（修正器仅对本次攻击有效）
8. emit `attack_executed(attacker_id, target_id, final_damage)`
9. emit `damage_dealt(target_id, final_damage, new_hp)`（供羁绊槽与爆发技系统订阅受击充能）
10. 调用 `turn_mgmt.mark_has_acted(attacker_id)`（见 Rule 13）
11. 若 `new_hp == 0`：调用 `resolve_unit_downed(target_id)`（见 Rule 9）

---

**Rule 2：职业动词执行总则（Class Verb — General）**

触发前提：
- `attacker.is_alive == true`
- `attacker.has_used_verb == false`
- `attacker.class_action_id != null`（`null` 单位 `has_used_verb` 初始为 `true`，不会到达此处）

动词执行后统一操作：`turn_mgmt.mark_has_used_verb(attacker_id)`（见 Rule 13）

职业动词与普通攻击彼此独立，可任意顺序执行（或只执行其中一个）。**修正器注入管道（Rule 10）仅适用于普通攻击（Rule 1）及剑豪·斩（Rule 3，唯一例外）**——其他职业动词的效果由各自规则定义，不受相邻羁绊加成影响。

---

**Rule 3：剑豪·斩（Slash — AoE Melee）**

- 类型：进攻型范围，`action_weight = 0`
- 有效目标：`attacker` 切比雪夫相邻格（8 向）内所有 `is_alive == true` 且 `faction == enemy` 的单位
- 伤害：`attacker.base_damage + modifier_sum + aura_bonus`（与普通攻击相同计算路径：`modifier_sum = min(Σ pending_modifiers[attacker_id], MAX_MODIFIER_SUM)`；`aura_bonus = AURA_VALUE if AURA_BONUS`；所有命中目标受到相同伤害值）
- **执行前（无论是否有有效目标）**：emit `attack_initiated(attacker_id, "slash")`（Godot 同步信号；相邻羁绊系统在回调中注入修正器后继续；以下快照将捕获已注入的 `modifier_sum`）
- 执行（**若有有效目标**）：预先快照 `pre_guard_damage = base_damage + modifier_sum + aura_bonus`（在循环外计算一次，全部目标共用此基准值）；以 `get_adjacents()` 返回的列表作为遍历源（顺序保证，见 Edge Case 7）；对每个有效目标**独立执行**：① `final_damage = pre_guard_damage`（每次迭代从基准值重新赋值，不复用前一目标的 GUARDED 减伤结果）；② 若目标持 `GUARDED`：`final_damage = floor(final_damage / GUARD_DIVISOR)`，消耗 `GUARDED`；③ `new_hp = max(0, target.current_hp - final_damage)`，`target.current_hp = new_hp`；④ emit `attack_executed(attacker_id, target_id, final_damage)`；⑤ emit `damage_dealt(target_id, final_damage, new_hp)`；⑥ 若 `new_hp == 0`：调用 `resolve_unit_downed(target_id)`；循环结束后（无论目标数量）：⑦ 消耗 `pending_modifiers[attacker_id]`；⑧ 若持有 `AURA_BONUS` 则消耗（**时序说明**：步骤 ⑦⑧ 在所有 `attack_executed` 广播后执行，与 Rule 1 步骤 7/2 在信号前消耗不同——`attack_executed` 回调期间 attacker 的 `AURA_BONUS` 和 `pending_modifiers` 仍可见）
- 若无相邻敌人：动词成功执行但无伤害效果（`has_used_verb = true`，不视为失败）；`pending_modifiers` 和 `AURA_BONUS`（若持有）仍按执行步骤 ⑦⑧ 消耗
- emit `slash_executed(attacker_id, Array[target_ids], pre_guard_damage)`（有效目标存在时：`pre_guard_damage` = base_damage + modifier_sum + aura_bonus，守护减伤前的基础伤害值；**零目标时 pre_guard_damage = 0**（不计算基准值，见 AC-10）；各目标**实际扣血量**（含 GUARDED 减伤后）通过各自的 `damage_dealt` 信号独立携带）
- `turn_mgmt.mark_has_used_verb(attacker_id)`（Rule 2 总则统一操作；Rule 3 中在 `slash_executed` 广播后调用，为本动词流程最后一步）

---

**Rule 4：炮手·轰（Cannonball — Penetrating Line）**

- 类型：进攻型穿透直线，`action_weight = 0`
- 选定方向：4 个基本方向（上 / 下 / 左 / 右）之一
- 弹道：从 `attacker.grid_position` 沿方向延伸 `attacker.attack_range` 格（停于棋盘边界）
- 命中：弹道路径上所有存活单位（友方与敌方均可被命中；**不区分阵营**——炮弹不识友敌，HUD 须提示此风险）；无穿透伤害衰减
- 伤害：`attacker.base_damage`（不接受修正器；不受 AURA_BONUS 影响）
- **执行（对每个命中目标 `target`，按弹道顺序）**：
  1. `final_damage = attacker.base_damage`
  2. 若 `target` 持有 `GUARDED`：`final_damage = floor(final_damage / GUARD_DIVISOR)`；消耗 `GUARDED`
  3. `new_hp = max(0, target.current_hp - final_damage)`；`target.current_hp = new_hp`
  4. emit `damage_dealt(target_id, final_damage, new_hp)`
  5. 若 `new_hp == 0`：调用 `resolve_unit_downed(target_id)`
- **`轰` 不受 `GUNNER_MIN_RANGE` 限制**（近距离炮击穿越相邻格命中远处目标，物理合理且战术有趣）
- 若弹道无存活单位：动词成功执行，无伤害，`has_used_verb = true`
- **不 emit `attack_executed`**（设计意图：轰为穿透型射击动词，语义不同于普通攻击；下游系统通过 `damage_dealt` 处理轰击命中的受击充能，见 Interactions 表注记）
- emit `cannon_executed(attacker_id, direction, Array[hit_target_ids], base_fire_damage)`（`base_fire_damage = attacker.base_damage`；各目标实际受伤值（含 GUARDED 减伤后）通过各自的 `damage_dealt` 信号独立携带）

---

**Rule 5：铁壁·挡（Guard — Damage Shield）**

- 类型：防御型，`action_weight = 1`
- 有效目标：`attacker` 本人，**或** 切比雪夫相邻的友方存活单位
- 效果：目标获得 `GUARDED` 状态
- `GUARDED` 语义：该单位下一次受到伤害时，`final_damage = floor(incoming_damage / GUARD_DIVISOR)`（见 Formulas Formula 3）；伤害执行后 `GUARDED` 消耗
- 持续规则：`GUARDED` 在**被消耗**或 `ROUND_END`（以先发生者为准）时移除；不跨回合保留
- 叠层规则：同一单位同时仅允许一个 `GUARDED` 层；若目标已有 `GUARDED` 则**刷新**（不累积双层）
- **消耗来源**：`GUARDED` 消耗触发**不区分伤害来源阵营**——炮手·轰（Rule 4）的友伤同样消耗 `GUARDED`（设计意图：守护吸收下一次任何伤害，不限来源）；HUD 的炮手弹道预警（UI Requirements 第 5 条）负责提示此风险
- emit `guard_applied(caster_id, target_id)`

---

**Rule 6：医师·愈（Heal）**

- 类型：治疗型，`action_weight = 2`
- 有效目标：`attacker` 本人，**或** 切比雪夫相邻的友方存活单位（`is_alive == true`；无法治疗 Downed 单位）
- 效果：`new_hp = min(target.current_hp + HEAL_AMOUNT, target.max_hp)`（见 Formulas Formula 2）
- `HEAL_AMOUNT = 3`（基线，可调旋钮）
- emit `heal_executed(caster_id, target_id, heal_amount, new_hp)`

---

**Rule 7：航海士·移（Displace — Forced Movement）**

- 类型：位移控制型，`action_weight = 2`
- 有效目标：`attacker` 切比雪夫相邻的任意存活单位（敌方或友方；不含 `attacker` 自身）
- 选定方向：4 个基本方向（上 / 下 / 左 / 右）之一
- 执行：沿方向逐格尝试移动目标，每格检查 `grid_board.is_cell_empty(next_cell)`（须同时检测 UNIT_OCCUPIED 和 TERRAIN_BLOCKED 两种非空状态，详见 grid-board-system GDD 地形节）；撞到棋盘边界、TERRAIN_BLOCKED 地形格或另一单位占格时停止；`actual_distance ∈ [0, PUSH_DISTANCE]`（0 = 无法移动，合法但无效）
- `PUSH_DISTANCE = 2`（基线，可调旋钮）
- 调用 `grid_board.forced_move_unit(target_id, final_destination)`（**新接口需求**，见 Dependencies）
- emit `displacement_executed(caster_id, target_id, direction, actual_distance)`

---

**Rule 8：乐手·奏（Perform — Aura Buff）**

- 类型：光环增益型，`action_weight = 1.5`
- 有效目标：`attacker` 切比雪夫相邻的所有友方存活单位（**不含 attacker 自身**——自奏增益设计过强）
- 效果：每个有效目标获得 `AURA_BONUS` 状态
- `AURA_BONUS` 语义：该单位下一次执行普通攻击（Rule 1）**或斩（Rule 3）**时，`aura_bonus = AURA_VALUE`（`AURA_VALUE = 1`，基线）作为 `final_damage` 的**独立第三项**加入（见 Formula 1）；不经过 `min()` 管道，**不受 `MAX_MODIFIER_SUM` 钳制**；行动执行后消耗 `AURA_BONUS`
- `AURA_BONUS` 与相邻羁绊系统的 `pending_modifiers` 叠加——乐手的光环与羁绊加成可以共同生效，这是设计意图
- 若无相邻友方：动词成功执行但无目标（`has_used_verb = true`）
- `AURA_BONUS` **跨回合保留**，直到单位执行普通攻击（Rule 1）或斩（Rule 3）消耗为止；`ROUND_END` 不清除 `AURA_BONUS`（与 `GUARDED` 不同）
- emit `aura_performed(caster_id, Array[buffed_ids], aura_value)`

---

**Rule 9：击倒解算（resolve_unit_downed）**

封装函数，调用方：Rule 1（普通攻击）、Rule 3（斩）、Rule 4（轰）；未来任何造成伤害的机制均须经此函数。

执行步骤（顺序固定，**步骤 1–6 必须在步骤 7 之前全部完成**）：
1. 调用 `turn_mgmt.remove_from_alive_list(unit_id)`（回合管理持有存活列表）
2. `unit.is_alive = false`
3. `unit.grid_position = DOWNED_SENTINEL`（`Vector2i(-1, -1)`，暂定；最终值由 grid-board-system GDD 定义）
4. `grid_board.remove_unit(unit_id)`（棋盘格子变 `EMPTY`）
5. 若 `unit_id` 存在于 `pending_modifiers`：`pending_modifiers.erase(unit_id)`（清理残留修正器，防止反伤场景或 ID 复用时数据污染）
6. 若 `unit_id` 存在于 `unit_statuses`：`unit_statuses.erase(unit_id)`（清理残留 AURA_BONUS/GUARDED；Edge Case 8 场景的 GUARDED 已在步骤 4 之前消耗，此步骤主要针对未消耗的 AURA_BONUS 残留）
7. emit `unit_downed(unit_id)`

**顺序保证（解答 turn-management Open Question #4）**：Godot 信号默认同步执行。任何订阅 `unit_downed` 的系统（如未来的反伤被动）在回调中 `unit.is_alive == false`、格子已为 `EMPTY`、状态字典已清空——不可再选中、攻击或查询 Downed 单位的状态。

---

**Rule 10：攻击修正器注入接口（Attack Modifier Injection）**

供相邻羁绊系统使用（单向注入，本系统不反向引用羁绊系统，防止循环依赖）：

- `register_attack_modifier(attacker_id: String, bonus_damage: int)` — 在目标攻击确认前调用
- 本系统维护 `pending_modifiers: Dictionary`（键：`attacker_id`，值：`Array[int]`）
- 同一 `attacker_id` 可多次注册，多项累加
- 普通攻击（Rule 1 步骤 1）执行时消费并清空

---

**Rule 11：炮手近战禁止规则（Gunner Melee Exclusion）**

`unit_class == gunner` 的单位，其**普通攻击**（Rule 1）有额外验证：

`manhattan_distance(attacker.grid_position, target.grid_position) >= GUNNER_MIN_RANGE`（`GUNNER_MIN_RANGE = 2`）

不满足时，攻击被拒绝（`is_valid_attack()` 返回 `false`）；`has_acted` 不变。

**设计依据**：unit-data-system 明确警告——若炮手可在近战距离自由攻击，其与剑豪的身份差异退化为单纯移动力差异。最小射程约束强制炮手维持战场纵深，使"射程省去走位回合"的行动经济价值真正体现。职业动词**不受此规则约束**（Rule 4 已注明）。

---

**Rule 12：敌人意图可见性（Enemy Intent Visibility）**

设计决策：**全明示（Full Reveal）**。

- 每回合 `ROUND_START` 后，敌人 AI 系统计算并锁定所有敌方单位本轮意图（行动类型 + 目标 + 预期伤害）
- 意图在玩家首个 `ACTIVE_TURN` 开始前由战斗 HUD 完整展示
- 本系统保证执行结果与声明意图一致（无随机偏差；确定性是本系统的核心契约）

**设计依据**：《孤帆棋海》以 Into the Breach 为战棋设计参照——"完全可预测的惩罚，理性的救援"。部分隐藏将品类契约从"逻辑解题"改变为"信息不完整博弈"，MVP 阶段不引入此复杂性。意图内容的计算由敌人 AI GDD 负责；本系统只负责执行。

---

**Rule 13：行动标记接口（Action Flag Interface）**

has_acted / has_used_verb 的所有权归回合管理系统（per unit-data-system + turn-management GDD 约定）。本系统通过以下接口更新：
- `turn_mgmt.mark_has_acted(unit_id)`
- `turn_mgmt.mark_has_used_verb(unit_id)`

具体接口实现形态（直接方法调用 vs 信号通知）归架构决策（→ Open Questions）。

### States and Transitions

本系统引入两个单位状态（Unit Status），均为"单次使用 + 回合末过期"模式：

| 状态 | 持有单位 | 来源 | 消耗触发 | 自然过期 |
|------|---------|------|---------|---------|
| `GUARDED` | 任意友方存活单位 | 铁壁·挡（Rule 5） | 受到下一次伤害时（减伤后消耗） | `ROUND_END` |
| `AURA_BONUS` | 任意友方存活单位（除乐手自身） | 乐手·奏（Rule 8） | 执行下一次普通攻击或斩时（加伤后消耗） | 无（跨轮保留直到消耗） |

**状态存储**：本系统维护 `unit_statuses: Dictionary`（键：`unit_id`，值：`Array[status_enum]`）；状态以枚举值存储，同一单位允许同时持有 `GUARDED` 和 `AURA_BONUS`（两者不互斥）。

**`ROUND_END` 清理**：回合管理系统广播 `ROUND_END` 信号后，本系统仅移除所有单位的 `GUARDED` 残余状态；`AURA_BONUS` 不在此清理中——`AURA_BONUS` 跨轮保留直到被攻击或斩消耗。

**叠层规则**：
- `GUARDED`：单层——同一单位不超过 1 层（Rule 5 刷新规则）
- `AURA_BONUS`：单层——若单位已有 `AURA_BONUS` 再次被"奏"，刷新（不叠加为 +2）

MVP 阶段无其他状态（无负面状态 / debuff 字段——见 Open Questions）。

### Interactions with Other Systems

| 下游系统 | 本系统行为 | 接口方向 |
|----------|----------|---------|
| 回合管理系统 | 订阅 `unit_turn_started(unit_id)` 开始行动处理；订阅 `ROUND_END` 清理状态；调用 `mark_has_acted()` / `mark_has_used_verb()`；调用 `remove_from_alive_list()` | 双向：接收信号 + 调用接口 |
| 网格棋盘系统 | 调用 `in_attack_range()` 验证射程；调用 `get_adjacents()` 获取斩/守护/愈/奏的目标范围；调用 `remove_unit()` 在 `resolve_unit_downed` 中清格；调用 `forced_move_unit()`（新接口需求）用于航海士位移 | 调用接口 |
| 相邻羁绊系统 | 广播 `attack_initiated(attacker_id, verb)` 信号（`verb`: `"normal_attack"` 或 `"slash"`；在 Rule 1 步骤 0 和 Rule 3 执行前发出，触发条件验证通过后、`pending_modifiers` 消耗前）；暴露 `register_attack_modifier(attacker_id, bonus)` 接口供羁绊系统在信号回调中同步注入修正器；本系统不反向引用羁绊系统（防循环依赖） | 发信号（触发通知）+ 被调用接口（单向注入） |
| 羁绊槽与爆发技系统 | 广播 `attack_executed`（Rule 1 普通攻击 + Rule 3 斩，每命中目标一次）、`damage_dealt`（Rule 1/3/4 均发）、`unit_downed`；受击充能通过 `damage_dealt` 触发（炮手·轰不发 `attack_executed`，仍通过 `damage_dealt` 充能）；爆发判定通过 `unit_downed` 触发 | 发出信号 |
| 敌人 AI 系统 | 敌方 `unit_turn_started` 后，从敌人 AI 获取已锁定意图并执行对应行动（普通攻击或职业动词）；执行结果与意图声明保证一致 | 接收意图数据，执行行动 |
| 战斗 HUD 系统 | 广播全量战斗事件（`attack_executed`、`damage_dealt`、`heal_executed`、`guard_applied`、`aura_performed`、`slash_executed`、`cannon_executed`、`displacement_executed`、`unit_downed`）；HUD 订阅渲染伤害数字、状态图标、意图标记；并广播 `status_consumed(unit_id, status_type)` 信号（`status_type`: `"GUARDED"` 或 `"AURA_BONUS"`）以通知 HUD 移除对应状态图标——GUARDED 被伤害消耗时发出，AURA_BONUS 被普通攻击/斩消耗时发出（时序：在消耗后、`damage_dealt`/`attack_executed` 之后；参见 Rule 1 步骤 4 GUARDED 消耗 / Rule 8 AURA_BONUS 消耗） | 发出信号 |

## Formulas

> ✅ *systems-designer 复核于 2026-06-13，verdict: ENDORSE WITH CHANGES——本节已按其 3 项 bug 级修正（modifier_sum 上限、Formula 2 前提断言、守护 0 伤设计意图说明）与 2 项文档级修正（医师低端触底备注、治疗定价依据）修订。*

### Formula 1：普通攻击最终伤害（Final Damage）

```
modifier_sum = min(Σ registered_attack_modifiers, MAX_MODIFIER_SUM)
final_damage = base_damage + modifier_sum + (AURA_VALUE if AURA_BONUS else 0)
```

若 target 持有 `GUARDED`：
```
final_damage_after_guard = floor(final_damage / GUARD_DIVISOR)
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 基础伤害 | `base_damage` | int | 1–4 | 攻击者 UnitDefinition 中的字段（由 unit-data-system 锁定） |
| 修正器总和 | `modifier_sum` | int | 0–MAX_MODIFIER_SUM | `min()` 钳制防止相邻羁绊系统高额注入破坏两发击杀保证（见修正说明） |
| 修正器上限 | `MAX_MODIFIER_SUM` | int | **2**（基线；由相邻羁绊 GDD 同步确认） | 超出此值的注册修正被截断；相邻羁绊 GDD 须声明单次攻击总注入 ≤ 2 |
| 光环加成 | `AURA_VALUE` | int | 1（基线可调） | 攻击者持有 `AURA_BONUS` 时追加；执行后消耗 |
| 守护除数 | `GUARD_DIVISOR` | int | 2（基线可调） | 目标持有 `GUARDED` 时生效；`floor()` 保证结果为整数 |

**Boundary check:**

| Case | Calc | Result | 备注 |
|------|------|--------|------|
| 最小伤害（无修正，无光环） | base=1, ms=0, no aura | final=1 | 医师攻击目标 |
| 最大伤害（无守护） | base=3, ms=2, aura=1 | final=6 | 原型两发击杀保证（6 伤 2 发 = 12 HP，等于铁壁上限）✓ |
| GUARD 对最大伤害 | floor(6/2)=3 | final=3 | 守护将重击减半 |
| GUARD 对最小伤害 | floor(1/2)=0 | final=0 | **GUARDED 仍消耗**（设计意图：见下方说明）|
| base=0 | 不可能 | — | unit-data-system Edge Cases 确保 base_damage≥1 |
| 负值 | 不可能 | — | modifier_sum（min≥0）、AURA_VALUE（≥0）、base_damage（≥1）均无负值路径 |

> **守护"0 伤吸收"的设计意图**：当 final_damage=1 时，GUARD 后结果为 0，GUARDED 状态被消耗但目标 HP 不变。这是**预期行为而非 bug**——铁壁选择在 dmg=1 的弱攻击者到来时使用"挡"属于战术过度消耗，这种取舍是铁壁行动经济的一部分（guard 在 dmg≥3 的攻击者到来时价值最大）。若调参发现 dmg=1 的攻击频率过高导致铁壁动词常被"浪费消耗"，可通过降低 `GUARD_DIVISOR`（如改为 3，floor(1/3)仍为 0）或重新设计 GUARDED 为"最低 1 点穿透"来调整——调参决策归 QA 试玩阶段，不是设计 bug。

---

### Formula 2：治疗结果（Heal Result）

**前提（调用方须保证）**：`target.is_alive == true`（即 `target.current_hp > 0`）。若 `is_alive == false`，Rule 6 已在目标合法性检查阶段拒绝，本公式永不对 Downed 单位执行。运行时实现须 `assert target.current_hp > 0`，违反即为系统级 bug（不是调参边界）。

```
new_hp = min(target.current_hp + HEAL_AMOUNT, target.max_hp)
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 当前 HP | `current_hp` | int | **1**–max_hp | 前提保证下限为 1（Downed 单位被 Rule 6 拦截在调用前） |
| 治疗量 | `HEAL_AMOUNT` | int | 3（基线可调） | 按**绝对值**定价，非百分比——这是 `action_weight=2` 的定价依据：3 HP 治疗的行动经济价值由稀缺性（每轮一次）而非修复比例决定。若改为百分比治疗将改变 action_weight 的意义，须重走设计评审 |
| 生命上限 | `max_hp` | int | 4–12 | 目标 UnitDefinition.max_hp（unit-data-system 锁定） |

**Boundary check:**

| Case | Calc | Result | 备注 |
|------|------|--------|------|
| 最小 HP + 治疗 | 1+3=4，max=9 | new_hp=4 | |
| 满血治疗 | 9+3=12，max=9 | new_hp=9（钳制正确） | |
| max_hp=4（最低） | 1+3=4，max=4 | new_hp=4 | |
| 过量治疗 | 10+3=13，max=10 | new_hp=10 | min() 保证不超上限 |
| **医师低端（HP=8，W=2，带底）** | power_score=13.0 | 恰好触带下限 | 调参时医师为所有职业中最接近带底的——HEAL_AMOUNT 减小会使医师 action_weight 定价过高，须同步重算 |

---

### Formula 3：守护减伤（Guard Damage Reduction）

```
guarded_damage = max(0, floor(final_damage / GUARD_DIVISOR))
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 原伤害 | `final_damage` | int | 1–N | Formula 1 未减伤前结果 |
| 守护除数 | `GUARD_DIVISOR` | int | 2 | 基线；调低 = 更强守护 |

**Boundary check:**

| Case | Calc | Result | 备注 |
|------|------|--------|------|
| 1 伤被挡 | floor(1/2)=0 | 0 | 铁壁完全吸收，GUARDED 消耗 |
| 6 伤被挡 | floor(6/2)=3 | 3 | 重击减半 |
| 假设 GUARD_DIVISOR=4 | floor(6/4)=1 | 1 | 弱守护变体 |
| final_damage=0（理论边界） | floor(0/2)=0 | 0 | 安全，不产生负伤 |

---

### Formula 4：action_weight 最终标定

> **关闭 unit-data-system Open Question #2**——本 GDD 定稿后，unit-data-system 中所有 `action_weight` 暂定值即最终化，含 W 的职业 power_score 不再为 provisional。

| 职业动词 | 职业 | `action_weight` | 标定依据 |
|---------|------|----------------|---------|
| 斩 (slash) | 剑豪 | **0** | 进攻型动词；攻击价值已计入 `base_damage×2`，W 另加会双重计价 |
| 轰 (cannon) | 炮手 | **0** | 同上；穿透战略价值通过空间控制体现，不在预算公式额外加权 |
| 挡 (guard) | 铁壁 | **1** | 防御价值约等于使一次攻击无效；线性折算 ≈ 1 预算单位 |
| 奏 (perform) | 乐手 | **1.5** | 光环覆盖 2–3 友方；4 人棋盘聚集成本高，均摊收益 ≈ 1.5 |
| 愈 (heal) | 医师 | **2** | 3 HP 治疗 ≈ 1.5 预算；时机价值上调至 2 |
| 移 (displace) | 航海士 | **2** | 位移控制难以线性量化；与治疗同级基准 |

**power_score 验证（带中点，crew_power_band = [13, 16]）：**

| 职业 | HP | dmg | range | move | W | power_score | 在带? |
|------|----|-----|-------|------|---|-------------|-------|
| 剑豪 | 10 | 3 | 1 | 3 | 0 | 5+6+1+3+0 = **15.0** | ✓ |
| 炮手 | 7 | 3 | 3.5 | 1.5 | 0 | 3.5+6+3.5+1.5+0 = **14.5** | ✓ |
| 铁壁 | 12 | 1.5 | 1 | 2 | 1 | 6+3+1+2+2 = **14.0** | ✓ |
| 医師 | 8.5 | 1 | 1.5 | 2.5 | 2 | 4.25+2+1.5+2.5+4 = **14.25** | ✓ |
| 航海士 | 8 | 1.5 | 1.5 | 2.5 | 2 | 4+3+1.5+2.5+4 = **15.0** | ✓（[12.5,17.5] 例外区间） |
| 乐手 | 7 | 2 | 1.5 | 2.5 | 1.5 | 3.5+4+1.5+2.5+3 = **14.5** | ✓ |

**已知局限**：`modifier_sum` 上限由相邻羁绊 GDD 声明；若单次攻击修正器超过 3，两发击杀保证在某些组合下可能失效（原型基线假设单次修正 ≤ 2）。

## Edge Cases

**1. 斩（Slash）命中友方**
`get_adjacents()` 返回混合阵营单位；Rule 3 明确目标须 `faction == enemy`，实现须过滤。无相邻敌人时斩成功执行但无伤害（`has_used_verb = true`，不视为失败——玩家知情后果）。

**2. 轰（Cannonball）误伤友方**
轰不区分阵营（Rule 4 注明"友方与敌方均可被命中"）。这是设计意图——HUD 须提示炮弹弹道路径中的友方单位。若弹道完全无单位，成功执行无伤害。

**3. 炮手用轰朝无目标方向**
合法执行，`cannon_executed(…, Array[])` 广播空列表，`has_used_verb = true`。不报错。

**4. GUARDED 叠层**
同一单位已有 `GUARDED`，铁壁再次对其"挡"：状态刷新（非叠加为双层）。铁壁 + 铁壁组合不能形成永久/双重免伤。

**5. GUARDED 被 0 伤消耗**
`floor(1/2)=0`：GUARDED 消耗，目标 HP 不变。设计意图（见 Formulas Formula 3 守护"0 伤吸收"说明）。

**6. AURA_BONUS 未使用到 ROUND_END**
持有 `AURA_BONUS` 的单位本回合未执行普通攻击或斩：`AURA_BONUS` **跨轮保留**，不在 `ROUND_END` 时消失——直到该单位发动普通攻击或斩时才消耗。

**7. 连续 Downed（斩 / 轰同帧杀死多个）**
遍历命中目标列表（Rule 3 按 `get_adjacents()` 返回顺序、Rule 4 按弹道顺序），在各自循环内立即调用 `resolve_unit_downed()`。每次 Downed 均完整执行步骤 1–6（含数据清理，不含信号广播）后，再 emit `unit_downed`，再处理下一个目标。保证每个被击倒单位在其 `unit_downed` 信号广播时已从棋盘移除。

**8. 击倒的 GUARDED 单位**
目标持 `GUARDED`，Rule 1 步骤 4 先消耗 GUARDED 并减伤；步骤 5 计算 new_hp；若 `new_hp == 0`，调用 `resolve_unit_downed()`。GUARDED 在 Downed 处理前已消耗，`resolve_unit_downed` 内无需清理该状态。

**9. 航海士位移目标到棋盘边界**
逐格检查，到边界即停。`actual_distance < PUSH_DISTANCE` 是正常结果，不报错。

**10. 航海士位移到已 Downed 单位的格**
Downed 单位已调用 `grid_board.remove_unit()`，格子为 `EMPTY`，可以正常移入。无特殊处理。

**11. 航海士推友方单位**
Rule 7 允许目标为友方（位移控制同样适用于友方站位调整）。友方被推不触发伤害，但新位置可能打破或建立相邻羁绊——相邻羁绊系统按需在攻击时重新查表，无即时触发。

**12. 医师治疗满血单位**
`min(max_hp + HEAL_AMOUNT, max_hp) = max_hp`，HP 不变，动词成功执行（`has_used_verb = true`）。UI 层可选择提示"已满血"，但不视为非法操作。

**13. 炮手用普通攻击目标在 GUNNER_MIN_RANGE 以内**
`is_valid_attack()` 返回 `false`，攻击被拒绝，`has_acted` 不变，玩家可重新选择目标。这不是"错误"——是炮手射程最小值约束的正常体现。

**14. 修正器注册后攻击者被击倒**
若攻击者在自己 `unit_turn_started` 之前（例如敌方反伤未来实现后）被 Downed，其 `pending_modifiers` 条目由 `resolve_unit_downed()` **步骤 5** 统一清空；`unit_statuses` 条目由**步骤 6** 统一清空。无需调用方额外处理。本路径在 MVP 阶段不可达（无反伤机制），作为 Rule 9 正式步骤已涵盖。

**15. has_acted 接口调用时机**
Rule 1 步骤 10 调用 `turn_mgmt.mark_has_acted()` 发生在 `resolve_unit_downed()` 之前（步骤 11）——即使攻击杀死目标，攻击者的行动标记先完成，保证无论目标是否被 Downed，`has_acted` 都已设置。

## Dependencies

### 上游依赖（本系统依赖谁）

| 系统 | GDD 状态 | 依赖内容 | 契约备注 |
|------|---------|---------|---------|
| 单位数据系统 | **Approved** | UnitDefinition（`base_damage`, `attack_range`, `unit_class`, `max_hp`）；UnitInstance（`current_hp`, `is_alive`, `grid_position`, `has_acted`, `has_used_verb`）；`action_weight` 标定由本 GDD Formula 4 最终化 | unit-data-system Open Question #2 关闭（本 GDD 定稿日） |
| 网格棋盘系统 | **Approved** | `in_attack_range(a, b, range) → bool`；`get_adjacents(pos) → Array[unit_id]`；`remove_unit(unit_id)`；**`forced_move_unit(unit_id, destination) → bool`（新接口需求）** | 前三接口已在 grid-board-system GDD 定义；`forced_move_unit` 须扩充至该 GDD（见下方新接口需求） |
| 回合管理系统 | **Approved** | `unit_turn_started(unit_id)` 信号；`ROUND_END` 信号；`mark_has_acted(unit_id)` / `mark_has_used_verb(unit_id)` 接口；`remove_from_alive_list(unit_id)` 接口 | 接口形态（方法调用 vs 信号）归架构决策（Open Questions）；本 GDD 声明语义需求 |

### 下游依赖（谁依赖本系统）

| 系统 | GDD 状态 | 依赖内容 |
|------|---------|---------|
| 相邻羁绊系统 | Not Started | `register_attack_modifier(attacker_id, bonus)` 接口；`MAX_MODIFIER_SUM = 2` 约束须在该 GDD 中确认 |
| 羁绊槽与爆发技系统 | Not Started | `attack_executed`、`damage_dealt`、`unit_downed` 信号 |
| 敌人 AI 系统 | Not Started | 行动执行服务（execute_attack / execute_class_verb）；Rule 12 全明示约定 |
| 战斗 HUD 系统 | Not Started | 全量战斗事件信号（渲染依赖） |
| 战后结算系统 | Not Started | `unit_downed` 信号（伤亡统计） |

### 新接口需求（须通知 grid-board-system）

`forced_move_unit(unit_id: String, destination: Vector2i) → bool`
- 供航海士·移（Rule 7）调用
- `destination` 须为合法格（EMPTY、未出界）；非法时返回 `false`，位移取消，`displacement_executed` 仍广播（`actual_distance = 0`）
- grid-board-system GDD 须在其 Dependencies 节回指本文档，并在接口列表中补充此函数

`is_cell_empty(pos: Vector2i) → bool`
- 供航海士·移（Rule 7）逐格阻挡检查使用
- **注意**：若 `forced_move_unit` 在 grid-board-system 内部封装此逻辑，则本系统不直接调用 `is_cell_empty`；实现方式由 grid-board-system GDD 确认（两种方案均可接受）。无论哪种，须在该 GDD 接口列表中声明。

### 双向引用义务

上述所有下游系统的 GDD 撰写时**必须**在其 Dependencies 节回指本文档，确认（或质疑）信号与接口契约。

### 解决的 Open Questions

| 来源 GDD | 原 Open Question | 本 GDD 如何关闭 |
|---------|----------------|--------------|
| turn-management | OQ #4：反伤被动触发 ON_UNIT_DOWNED 检测时机 | Rule 9：步骤 1–6 在步骤 7（emit `unit_downed`）前完成，Godot 同步信号保证。关闭 |
| unit-data-system | OQ #2：`action_weight` 标定定稿 | Formula 4 最终化六职业 W 值。关闭 |
| unit-data-system | OQ #6：医师治疗效力独立校验指标 | Formula 2 以绝对值 HEAL_AMOUNT=3 定价，Tuning Knobs 提供独立校验旋钮。部分关闭（试玩验证留给垂直切片） |
| unit-data-system | OQ #8：debuff 字段 | MVP 阶段：无负面状态字段，所有职业动词为正向效果；UnitInstance 不追加 debuff。关闭（MVP 范围内） |

## Tuning Knobs

### 可调旋钮

| 旋钮 | 默认值 | 安全范围 | 影响的玩法面向 |
|------|--------|---------|---------------|
| `HEAL_AMOUNT` | 3 | 1–6 | 医师每次治疗量。↑ → 医师续航能力增强，受伤代价感下降；↓ → 治疗感知不明显，医师战术价值崩塌（action_weight=2 定价基于 HEAL_AMOUNT=3；若大幅下调须重走 power_score 验算） |
| `GUARD_DIVISOR` | 2 | 2–4 | 铁壁守护减伤除数（`floor(dmg/GUARD_DIVISOR)`）。2=减半；3≈减三分之一；4=减四分之一。↑ → 守护弱化；↓ → 守护更强（理论极端：GUARD_DIVISOR=1 = 不减伤，无实际意义） |
| `GUNNER_MIN_RANGE` | 2 | 1–3 | 炮手普通攻击最小曼哈顿距离。1=无限制（炮手退化为移动力差的剑豪）；3=严格远程（操作难度更高）；2 允许斜向站位但禁止正面近战 |
| `PUSH_DISTANCE` | 2 | 1–3 | 航海士单次位移最大格数。1=保守；3=大范围控场（后期关卡可能过强） |
| `AURA_VALUE` | 1 | **1（上限）** | 乐手光环每次攻击加伤。**禁止单独调至 2**：3+2+2=7 伤可一发击杀 max_hp≤7 单位，已知违反两发击杀保证；若须调至 2 则必须同步将 `MAX_MODIFIER_SUM` 调为 1（联动约束，须重走 power_score 验算） |
| `MAX_MODIFIER_SUM` | 2 | 1–3 | 相邻羁绊系统单次攻击最大注入修正值。**高危旋钮**——调高会使重攻击一发暴力，破坏游戏节奏；调低限制羁绊系统的效果空间。须与相邻羁绊 GDD 联动 |

### 不是旋钮的东西

- `action_weight` 值（Formula 4 已最终化）：调整它等于重定义职业的预算价值，须重走所有职业 power_score 验算与设计评审
- `GUARD_DIVISOR = 1`（守护不减伤）和 `GUNNER_MIN_RANGE = 0`（炮手可自伤）是无意义的退化值，不在安全范围内
- `resolve_unit_downed()` 内部步骤顺序：这是架构契约（turn-management OQ #4 的答案），不可调参
- `ROUND_END` 状态清理时机：归回合管理系统的时序，不在本系统调参范围内

## Visual/Audio Requirements

本系统是**逻辑层**，不直接持有视听资产。它通过信号驱动视听系统，以下是本系统对视听的接口约定：

| 信号 | 视听消费方 | 期望表现（归各消费 GDD 具体设计） |
|------|----------|-------------------------------|
| `attack_executed(attacker_id, target_id, final_damage)` | 爆发演出 / 战斗 HUD | 攻击动画触发；伤害数字弹出 |
| `damage_dealt(target_id, damage, new_hp)` | 战斗 HUD | HP 条更新；受击闪烁 |
| `heal_executed(caster_id, target_id, amount, new_hp)` | 战斗 HUD | HP 条恢复动画；治疗数字弹出 |
| `guard_applied(caster_id, target_id)` | 战斗 HUD | GUARDED 状态图标显示 |
| `aura_performed(caster_id, buffed_ids, aura_value)` | 战斗 HUD | AURA_BONUS 图标显示；乐手周围光效 |
| `slash_executed(attacker_id, target_ids, pre_guard_damage)` | 爆发演出 | 范围斩击演出（含多目标） |
| `cannon_executed(attacker_id, direction, hit_ids, base_fire_damage)` | 爆发演出 | 弹道路径可视化；炮击演出 |
| `displacement_executed(caster_id, target_id, direction, dist)` | 战斗 HUD | 位移动画；目标单位移动轨迹 |
| `unit_downed(unit_id)` | 爆发演出 / 战斗 HUD | 倒地演出；棋盘清格 |

**爆发演出系统接口说明**：爆发演出 GDD 须在其 Dependencies 节订阅上述信号，并定义各信号对应的演出资产。本系统只保证信号按序广播，不持有任何演出逻辑。

## UI Requirements

本系统无直接 UI。战斗 HUD 系统通过信号消费战斗事件并渲染。本系统施加以下 UI 约束：

1. **攻击合法性高亮**：`is_valid_attack(attacker_id, target_id)` 须可从 UI 调用（查询用，不执行），供 HUD 系统预高亮合法目标（含炮手最小射程约束的目标排除）
2. **职业动词有效目标查询**：每个动词须提供对应的 `get_valid_verb_targets(unit_id) → Array[unit_id]` 接口，供 HUD 高亮可选目标；**航海士·移额外须提供 `get_valid_displace_directions(caster_id: String, target_id: String) → Array[int]`（返回合法推送方向集合，由本系统内部调用 `is_cell_empty` 判定，避免 HUD 层自行实现方向可行性逻辑），供 HUD 在第二步选方向时灰显无效方向**
3. **全明示意图渲染（Rule 12）**：敌方意图数据由敌人 AI 系统生成，HUD 渲染；本系统保证执行阶段与意图一致——UI 不应显示可能不被执行的"虚假意图"
4. **状态图标管理**：GUARDED 和 AURA_BONUS 状态的图标显示 / 消失须与本系统的状态变更事件同步（signal-driven）；HUD 不轮询状态，订阅 `guard_applied` / `aura_performed` 及 ROUND_END 清理事件
5. **炮手·轰路径预警**：轰路径预览中包含友方存活单位的格须以橙色警告色高亮（有别于敌方目标的红色高亮），确保玩家在知情前提下选择友伤路径，符合"计算有回报，行动有代价"的透明性承诺

## Acceptance Criteria

> 由 qa-lead 子代理起草（2026-06-13），主会话按本文档已锁规则微调。每条均可由 GUT 单元测试或 QA 人工独立验证。

**单元测试约定**：所有 AC 以 GDScript + GUT 框架描述。"发出信号"= GUT signal monitor 捕获；"has_acted=true"= 直接字段断言；"调用 X 函数"= mock 或 spy 验证调用发生。

---

### 加载 / 初始化

**AC-1**
Given 战斗系统初始化完成
When 查询任意单位状态
Then `has_acted=false`，`has_used_verb=false`，`GUARDED=false`，`AURA_BONUS=false`，`pending_modifiers` 字典为空

**AC-2** *(集成级 AC：alive_list 归属回合管理系统，验证须调用 `TurnManager.get_alive_list()`)*
Given 两支队伍各有 N 个单位加载至棋盘
When 查询回合管理系统的 alive_list
Then `TurnManager.get_alive_list().size() == 2N`，每个单位 `is_alive=true`，`grid_position != DOWNED_SENTINEL`

---

### 普通攻击

**AC-3 基本伤害路径**
Given 单位 A（`has_acted=false`, `is_alive=true`）与敌方 B（`is_alive=true`, `in_attack_range=true`），`modifier_sum=0`，B 无 GUARDED，A 无 AURA_BONUS
When A 对 B 执行普通攻击
Then `B.current_hp == B.current_hp_before - A.base_damage`；发出 `attack_executed(A, B, A.base_damage)` 和 `damage_dealt(B, A.base_damage, new_hp)`；`A.has_acted=true`

**AC-4 modifier 上限钳制 + AURA_BONUS**
Given modifier 注册总和为 5（超上限 MAX_MODIFIER_SUM=2），A 持有 AURA_BONUS（AURA_VALUE=1），B 无 GUARDED
When A 攻击 B
Then `final_damage == A.base_damage + 2 + 1 = A.base_damage + 3`（modifier 钳制为 2，AURA_BONUS 叠加）；A 的 AURA_BONUS 状态消耗

**AC-5 GUARDED 减伤与消耗**
Given B 持有 GUARDED，A 攻击 B，`final_damage`（Guard 前）为 5
When 攻击结算
Then `B.current_hp -= floor(5/2) = 2`；B 的 GUARDED 状态移除；`damage_dealt(B, 2, new_hp)` 发出

**AC-5b 斩·命中 GUARDED 目标**
Given 敌方 E 持有 GUARDED，剑豪 S 与 E 相邻（无修正器，S 无 AURA_BONUS）
When S 使用"斩"
Then E 受 `floor(S.base_damage / GUARD_DIVISOR)` 伤害；E 的 GUARDED 消耗；`attack_executed(S, E, floor(S.base_damage / GUARD_DIVISOR))` 发出（携带 GUARDED 减伤后的 final_damage，非 pre_guard_damage）；`slash_executed(S, [E], S.base_damage)` 发出（携带减伤前快照值 pre_guard_damage）；`damage_dealt(E, guarded_dmg, new_hp)` 携带减伤后数值

**AC-6 HP=0 触发 Downed**
Given B 当前 `current_hp=1`，A（`base_damage=3, modifier_sum=2, no AURA, no GUARD`）攻击，`final_damage=5`（系统规则内合法值）
When A 攻击 B
Then `B.current_hp == 0`（`max(0, 1-5)=0`，不为负）；随即调用 `resolve_unit_downed(B)`

---

### 炮手特殊规则

**AC-7 普通攻击被最小射程拒绝**
Given 炮手 G（`has_acted=false`），目标 B 与 G 的 manhattan distance = 1
When G 尝试对 B 执行普通攻击
Then 攻击被拒绝（`is_valid_attack() == false`），`G.has_acted` 保持 `false`，不发出任何伤害信号

**AC-8 轰不受 GUNNER_MIN_RANGE 限制**
Given 炮手 G 使用职业动词"轰"，直线路径上有相邻友方 F（manhattan=1）与远处敌方 E
When 轰结算
Then F 与 E 均受到 `G.base_damage`；信号 `cannon_executed` 包含 [F, E]；`G.has_used_verb=true`

---

### 职业动词

**AC-9 斩·命中相邻敌方（含修正器）**
Given 剑豪 S 相邻 2 个敌方、1 个友方；`register_attack_modifier(S, 2)` 已调用（`modifier_sum=2`）；S 无 `AURA_BONUS`
When S 使用"斩"
Then 2 个敌方各受 `S.base_damage + 2`，友方不受伤；`pending_modifiers[S]` 清空；`attack_executed(S, enemy_a, S.base_damage + 2)` 与 `attack_executed(S, enemy_b, S.base_damage + 2)` 各发出一次（**顺序先于** `slash_executed`）；`slash_executed(S, [enemy_a, enemy_b], S.base_damage + 2)` 发出；`S.has_used_verb=true`

**AC-9b 斩·持 AURA_BONUS 命中（光环消耗）**
Given 剑豪 S 持有 AURA_BONUS（`aura_bonus = AURA_VALUE = 1`），相邻 1 个敌方 E（无 GUARDED）；无 `pending_modifiers`
When S 使用"斩"
Then E 受 `S.base_damage + 1`；`attack_executed(S, E, S.base_damage + 1)` 发出；`slash_executed(S, [E], S.base_damage + 1)` 发出；S 的 AURA_BONUS 已消耗（`unit_statuses[S]` 不含 AURA_BONUS）；`S.has_used_verb=true`

**AC-10 斩·无相邻敌方**
Given 剑豪 S 周围无相邻敌方
When S 使用"斩"
Then 动词成功执行，`S.has_used_verb=true`；`slash_executed(S, [], 0)` 发出；无伤害信号

**AC-10b 斩·持 AURA_BONUS 且无相邻敌方（零目标消耗验证）**
Given 剑豪 S 持有 AURA_BONUS，周围无相邻敌方
When S 使用"斩"
Then `S.has_used_verb=true`；`slash_executed(S, [], 0)` 发出；S 的 AURA_BONUS 已消耗（`unit_statuses[S]` 不含 AURA_BONUS）；无 `attack_executed`，无伤害信号

**AC-11 挡·叠层刷新**
Given 铁壁 T 对目标 U（已有 GUARDED）使用"挡"
When 挡结算
Then U 仍只有 1 层 GUARDED（刷新不叠加）；`guard_applied(T, U)` 发出

**AC-12 愈·治疗量与上限钳制**
Given 医师 H 对友方 U（`current_hp=8, max_hp=10`）使用"愈"（HEAL_AMOUNT=3）
When 愈结算
Then `U.current_hp == min(8+3, 10) == 10`；`heal_executed(H, U, 3, 10)` 发出；`H.has_used_verb=true`

**AC-12b 愈·满血目标**
Given 医师 H 对友方 U（`current_hp == max_hp`）使用"愈"
When 愈结算
Then `U.current_hp` 不变（仍等于 `max_hp`）；`heal_executed(H, U, 3, max_hp)` 发出；`H.has_used_verb=true`（不视为非法操作）

**AC-13 移·位移阻挡停止**
Given 航海士 N 推动目标 T 向右，第 1 格空，第 2 格被另一单位阻挡
When 移结算（PUSH_DISTANCE=2）
Then `actual_distance == 1`；T 停在第 1 格；`displacement_executed(N, T, RIGHT, 1)` 发出

**AC-14 奏·自身不受益**
Given 乐手 M 与友方 A、B 相邻
When M 使用"奏"
Then A、B 各获得 AURA_BONUS；M 自身无 AURA_BONUS；`aura_performed(M, [A, B], 1)` 发出；`M.has_used_verb=true`

---

### 击倒解算

**AC-15a resolve_unit_downed 状态契约**
Given B 的 `current_hp` 降至 0，触发 `resolve_unit_downed(B)` 且执行完毕
When 检查 B 的状态
Then `B.is_alive == false`；`B.grid_position == DOWNED_SENTINEL`；`TurnManager.get_alive_list()` 不含 B；`grid_board` 对 B 原格查询结果为 EMPTY；`pending_modifiers` 中 B 的条目不存在；`unit_statuses` 中 B 的条目不存在

**AC-15b resolve_unit_downed 时序契约（信号前状态保证）**
Given B 的 `current_hp` 降至 0，GUT spy 连接 `unit_downed` 信号
When `unit_downed(B)` 信号回调执行时（在回调内断言）
Then `B.is_alive == false`；`B.grid_position == DOWNED_SENTINEL`；B 已从 `alive_list` 移除；`grid_board` 对 B 原格为 EMPTY；`pending_modifiers` 和 `unit_statuses` 中 B 的条目已清空——以上均在进入回调时已成立（验证步骤 1–6 先于步骤 7 的时序保证）

**AC-15c 斩触发 resolve_unit_downed**
Given 剑豪 S 与敌方 E 相邻，`E.current_hp <= S.base_damage`（斩后必然 Downed）
When S 使用"斩"
Then `E.current_hp == 0`；`resolve_unit_downed(E)` 调用；`E.is_alive == false`；顺序契约与 AC-15b 一致

**AC-15d 轰触发 resolve_unit_downed**
Given 炮手 G 使用"轰"，弹道上有敌方 E（`E.current_hp <= G.base_damage`）
When 轰结算
Then `E.current_hp == 0`；`resolve_unit_downed(E)` 调用；`E.is_alive == false`；顺序契约与 AC-15b 一致

**AC-15e 斩·同帧 Downed 两目标（循环内立即处理顺序）**
Given 剑豪 S 与 enemy_a、enemy_b 均相邻（两者 `current_hp ≤ S.base_damage`，斩后必然 Downed）；GUT spy 记录信号接收顺序
When S 使用"斩"
Then 信号顺序为：`attack_executed(S, enemy_a, ...)` → `damage_dealt(enemy_a, ...)` → `unit_downed(enemy_a)` → `attack_executed(S, enemy_b, ...)` → `damage_dealt(enemy_b, ...)` → `unit_downed(enemy_b)` → `slash_executed(S, [...], ...)`；enemy_a 在 `damage_dealt(enemy_b, ...)` 发出前已从棋盘移除（循环内立即处理，非批量推后）

**AC-16 Downed 单位无法被攻击或治疗**
Given 已击倒单位 B（`is_alive=false`）
When 任意单位尝试对 B 执行普通攻击，或医师尝试对 B 执行"愈"
Then 两者均被拒绝（`is_valid_attack()/is_valid_verb_target()` 返回 false），相关 `has_acted/has_used_verb` 不变

---

### 修正器与状态

**AC-17 modifier 钳制计算**
Given 分两次调用 `register_attack_modifier(A, 1)` 和 `register_attack_modifier(A, 3)`（总和=4）
When 普通攻击执行时计算 `modifier_sum`
Then `modifier_sum == min(4, 2) == 2`；攻击后 `pending_modifiers[A]` 清空

**AC-18 非斩类职业动词不消耗修正器**
Given 已调用 `register_attack_modifier(M, 1)`（M 为乐手），M 使用职业动词"奏"
When 奏执行结算
Then 奏效果照常（AURA_BONUS 分发给相邻友方）；`pending_modifiers[M]` 仍保留 +1 修正器（不消耗）；修正器在 M 下一次普通攻击时才消耗

**AC-19 AURA_BONUS 跨轮保留**
Given 单位 U 持有 AURA_BONUS，本回合内未执行普通攻击或斩
When `ROUND_END` 事件触发
Then `U.AURA_BONUS == true`（跨轮保留，不在 ROUND_END 消失；直到 U 发动普通攻击或斩时才消耗）

**AC-20 GUARDED 0 伤消耗（设计意图验证）**
Given B 持有 GUARDED，A 的 `base_damage=1`，`modifier_sum=0`，无 AURA_BONUS（`final_damage` Guard 前=1，Guard 后=`floor(1/2)=0`）
When A 攻击 B
Then `B.current_hp` 不变（受 0 伤）；B 的 GUARDED 状态**仍消耗**（0 伤攻击视为触发了守护）；`damage_dealt(B, 0, B.current_hp)` 发出

## Open Questions

| # | 问题 | 裁决归属 | 对本系统的影响 |
|---|------|---------|---------------|
| 1 | **`forced_move_unit` 接口**：grid-board-system GDD 尚未定义此函数（供航海士·移调用）。航海士动词实现阻塞于此接口的确认。 | grid-board-system GDD 修订 | 若接口不落地，航海士·移无法实现；MVP 前须解决 |
| 2 | **`has_acted`/`has_used_verb` 写入接口形态**：本系统通过 `turn_mgmt.mark_has_acted()` 等接口更新行动标记，但接口具体形态（直接方法调用 vs 信号通知）未定。选项 A（直接方法调用）符合封装原则；选项 B（战斗解算直接写字段）违反 unit-data-system 的字段所有权声明。 | 架构决策 / turn-management GDD 修订 | 影响两系统的代码边界与测试策略 |
| 3 | **MAX_MODIFIER_SUM 与相邻羁绊 GDD 联动确认**：本 GDD 声明 MAX_MODIFIER_SUM=2，相邻羁绊 GDD 须在其设计中确认单次攻击总注入不超过此值。若相邻羁绊 GDD 设计了 2 种以上同时触发的加成（如"相邻 +1 + 同职业 +1 + 标签匹配 +1"），须与本系统协商上限。 | 相邻羁绊 GDD | 影响 Formula 1 的实际伤害上限 |
| 4 | **敌人阵营是否可以持有 GUARDED/AURA_BONUS**：Rule 5 和 Rule 8 的目标均为"友方"，但未来若敌人 AI 也有"守护同伴"类行为，GUARDED 系统须对敌方单位开放。MVP 阶段仅友方可持有状态。 | 敌人 AI GDD | MVP 不影响；垂直切片前确认 |
| 5 | **过量修正器的截断 vs 拒绝**：当 `Σ modifiers > MAX_MODIFIER_SUM` 时，本 GDD 选择截断（取 MAX_MODIFIER_SUM）而非拒绝注册。若相邻羁绊系统期望"超量注册 = 错误"，须重新协商。 | 相邻羁绊 GDD | 架构约定的一致性 |
