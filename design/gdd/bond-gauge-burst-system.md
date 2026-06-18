# 羁绊槽与爆发技系统（Bond Gauge & Burst System）

> **Status**: Approved（R1 修订后放行，无需 R2）
> **Author**: Chris + Claude
> **Last Updated**: 2026-06-16
> **Implements Pillar**: 关键回合的爆发（每场战斗积蓄至1–2次逆转性爆发回合）；羁绊即战术（谁站在谁旁边决定充能速率与爆发搭档）

## Overview

羁绊槽与爆发技系统是《孤帆棋海》核心循环的兑现引擎——它维护一条全队共享的羁绊槽，随着船员发动攻击和承受伤害积累充能，当槽充满后玩家可指定两名相邻船员触发爆发技（Burst Action）。爆发技是两名船员联合发动的特殊行动，其效果超越各自单独出击所能达到的上限。

本系统负责：充能逻辑（充能量、充能来源、每回合上限）、爆发激活资格检查、按职业配对分发爆发效果、爆发后的槽重置。本系统**不负责**：伤害计算（战斗解算系统）、相邻修正器注入（相邻羁绊系统）、爆发演出动画（爆发演出系统）。

充能事件来源：`attack_executed`（普通攻击 + 斩，每命中目标各发一次）、`cannon_executed`（炮手·轰，每次使用发一次）、`damage_dealt`（己方受击，每回合上限 `RECEIVED_CHARGE_CAP`）。爆发激活为玩家主动触发：槽满（`bond_gauge_current >= BOND_GAUGE_MAX = 10`）时，玩家选定 lead 单位（未使用普通攻击）和 partner 单位（未使用职业动词），两者切比雪夫相邻，激活 `BURST_EFFECT_TABLE[lead.class][partner.class]` 对应效果。羁绊槽在战斗内跨回合保留，不跨战斗保留。

## Player Fantasy

玩家不会想"我积了 10 点充能"——他们想的是："剑豪和铁壁并肩战斗了整场，现在该他们出手了。"

情感结构是**预期兑现（Anticipated Payoff）**。从第一回合开始，充能槽就是可见的。每一次攻击都在积累。玩家刻意选择谁站在谁旁边，不只是为了相邻修正器加成，而是因为他们希望**那两个人**在高光时刻一起爆发。爆发不是随手按下的按钮——它是玩家用四到七回合的站位决策写成的故事的结局。

最佳时刻：在敌人即将压垮一名濒死船员时，玩家的积蓄变成了逆转反击——情感的重量来自于由谁来完成这一击（两个一直肩并肩的伙伴）。

设计约束：爆发必须是"挣来的"，不能是"磨出来的"。故意让己方受伤来更快充能会付出真实的 HP 代价；受击充能必须足够有吸引力，但不能成为主策略（通过 `RECEIVED_CHARGE_CAP = 2/回合` 控制）。

## Detailed Design

### Core Rules

**Rule 1：共享羁绊槽（Shared Bond Gauge）**

全队持有单一共享槽。

- 当前值：`bond_gauge_current` ∈ [0, BOND_GAUGE_MAX]
- `BOND_GAUGE_MAX = 10`（原型验证值）
- 每场战斗开始（`battle_started` 信号，由 turn-management-system 在 SETUP → 首次 ROUND_START 转换时发出）：`bond_gauge_current = 0`
- 每个 `ROUND_END`：槽**不重置**（保留至下一回合）
- 槽从 < MAX 变为 MAX 时（**首次**触达上限）：emit `bond_gauge_full()`

---

**Rule 2：攻击充能（Attack Charging）**

订阅 `attack_executed(attacker_id, target_id, final_damage)` 信号（普通攻击和斩每命中一个目标发一次）。

前置过滤（任一条件为真则返回，不充能）：
- 若 `unit_data.get_unit(attacker_id).faction != FACTION.ALLY`：返回

充能步骤：
1. 调用 `grid_board.get_adjacents(attacker.grid_position)`，过滤 `faction == ALLY AND is_alive == true AND unit_id != attacker_id`
2. 若过滤后列表非空：`charge_amount = CHARGE_ADJACENT`（= 2）
3. 若过滤后列表为空：`charge_amount = CHARGE_SOLO`（= 1）
4. `bond_gauge_prev = bond_gauge_current`
5. `bond_gauge_current = min(bond_gauge_current + charge_amount, BOND_GAUGE_MAX)`
6. emit `gauge_charged(attacker_id, charge_amount, bond_gauge_current)`
7. 若 `bond_gauge_prev < BOND_GAUGE_MAX AND bond_gauge_current == BOND_GAUGE_MAX`：emit `bond_gauge_full()`

---

**Rule 3：轰击充能（Cannon Charging）**

订阅 `cannon_executed(attacker_id, direction, hit_target_ids, base_fire_damage)` 信号（炮手·轰不发 `attack_executed`，通过此信号充能）。

前置过滤：
- 若 `unit_data.get_unit(attacker_id).faction != FACTION.ALLY`：返回

充能步骤（与 Rule 2 步骤 1–7 相同，以 attacker_id 为主体）。

**注**：轰击每次使用动词充能**一次**（即使命中多个目标——`cannon_executed` 每次轰只发一个信号）。弹道空置（`hit_target_ids == []`）仍充能：充能奖励行动本身，不奖励命中数量。

---

**Rule 4：受击充能（Received-Damage Charging）**

订阅 `damage_dealt(target_id, final_damage, new_hp)` 信号。

维护状态：`received_charge_this_round: int`（初始 = 0；`ROUND_END` 时重置）。

前置过滤（任一条件为真则返回）：
- 若 `unit_data.get_unit(target_id).faction != FACTION.ALLY`：返回
- 若 `received_charge_this_round >= RECEIVED_CHARGE_CAP`：返回

充能步骤：
1. `bond_gauge_prev = bond_gauge_current`
2. `bond_gauge_current = min(bond_gauge_current + CHARGE_HIT, BOND_GAUGE_MAX)`
3. `received_charge_this_round += 1`
4. emit `gauge_charged(target_id, CHARGE_HIT, bond_gauge_current)`
5. 若 `bond_gauge_prev < BOND_GAUGE_MAX AND bond_gauge_current == BOND_GAUGE_MAX`：emit `bond_gauge_full()`

`ROUND_END` 重置：收到 `ROUND_END` 信号后，`received_charge_this_round = 0`。

---

**Rule 5：爆发技激活条件（Burst Eligibility）**

玩家在己方单位的行动回合可激活爆发技，需同时满足以下全部条件：

| # | 条件 |
|---|------|
| 1 | `bond_gauge_current >= BOND_GAUGE_MAX` |
| 2 | 选定 lead：`faction == ALLY AND is_alive == true AND has_acted == false` |
| 3 | 选定 partner：`faction == ALLY AND is_alive == true AND has_used_verb == false` |
| 4 | `lead_id != partner_id` |
| 5 | `adjacent(lead.grid_position, partner.grid_position) == true`（grid-board 接口：切比雪夫距离 = 1） |

**注**：partner 无需 `has_acted == false`——爆发消耗 partner 的职业动词行动（`has_used_verb`），不影响其普通攻击机会。

---

**Rule 6：爆发技执行（Burst Execution）**

激活确认后，按以下步骤顺序执行：

1. `bond_gauge_current = 0`（**立即清零，先于所有效果**）
2. 调用 `turn_mgmt.mark_has_acted(lead_id)`
3. 调用 `turn_mgmt.mark_has_used_verb(partner_id)`
4. 查询 `BURST_EFFECT_TABLE[lead.unit_class][partner.unit_class]`，执行对应效果
5. emit `burst_executed(lead_id, partner_id, burst_type_id)`
6. emit `burst_presentation_requested(lead_id, partner_id, burst_type_id)`

---

**Rule 7：爆发效果表（BURST_EFFECT_TABLE）**

矩阵对称：`BURST_EFFECT_TABLE[A][B] == BURST_EFFECT_TABLE[B][A]`（调换 lead/partner 效果相同，演出可区分朝向）。

**精英配对爆发技（6种，有专属命名）：**

| 配对 | 爆发技名 | 效果摘要 | 里程碑 |
|------|---------|---------|-------|
| 剑豪+铁壁 | 破阵先锋 (Vanguard Breach) | ①铁壁对自身施放"挡"（获得 GUARDED）；②剑豪对所有相邻敌方发动增强斩，伤害 = `base_damage × BURST_DAMAGE_MULTIPLIER`，**穿透目标 GUARDED**（无视目标减伤） | **MVP** |
| 炮手+航海士 | 瞄准定位 (Guided Salvo) | ①航海士对1名相邻敌方执行"移"（推移 ≤ 2 格）；②炮手立即对该敌人当前位置所在方向发射穿透炮弹，伤害 = `base_damage × BURST_DAMAGE_MULTIPLIER`；推移失败则炮弹取消 | **MVP** |
| 剑豪+乐手 | 热血演奏 (Bardic Fury) | ①乐手对所有相邻存活友方（除自身）施放 AURA_BONUS；②剑豪对所有相邻敌方发动斩，伤害 = `base_damage × BURST_DAMAGE_MULTIPLIER`（AURA_BONUS 已就位，追加 AURA_VALUE）| Alpha |
| 炮手+乐手 | 轰鸣序曲 (Thunder Aria) | ①乐手对所有相邻存活友方（除自身）施放 AURA_BONUS；②炮手向4个基本方向各发射一次穿透炮弹，每条弹道伤害 = `base_damage × BURST_DAMAGE_MULTIPLIER`（炮手·轰不接受 AURA_BONUS，AURA 施放给队友） | Alpha |
| 剑豪+医师 | 护持突破 (Lifeline Slash) | ①剑豪对所有相邻敌方发动斩，伤害 = `base_damage × BURST_DAMAGE_MULTIPLIER`；②斩执行后，医师对剑豪施放"愈"，治疗量 = `HEAL_AMOUNT × BURST_HEAL_MULTIPLIER` | Alpha |
| 铁壁+医师 | 钢铁壁垒 (Iron Sanctum) | ①铁壁对所有存活友方（含自身）施放"挡"（全队 GUARDED）；②医师对所有存活友方施放"愈"（各恢复 HEAL_AMOUNT HP） | Alpha |

**通用爆发（非精英配对的 15 种组合，共用框架）：**

`协力强击 (Combined Strike)`（里程碑：Alpha）：
- lead 执行其职业动词效果（按 battle-resolution 对应 Rule 规则，效果量不加成）
- partner 随后执行其职业动词效果（效果量不加成）
- 两次动词在同一行动内顺序执行

**同职业配对（6种）补充规则**：
- 双剑豪：两轮斩，lead 扫相邻格后 partner 扫相邻格（范围可重叠）
- 双炮手：各选一个方向射击（可同向或异向）
- 其余同职业：动词效果重复执行两次（可作用于不同目标）

### States and Transitions

| 状态 | 描述 | 转入条件 | 转出条件 |
|------|------|---------|---------|
| EMPTY | `bond_gauge_current == 0` | 战斗开始；爆发执行后（步骤 1 清零） | 首次充能事件 |
| CHARGING | `0 < bond_gauge_current < BOND_GAUGE_MAX` | 任意充能事件 | 充能到达 MAX（→ FULL）；爆发执行（→ EMPTY） |
| FULL | `bond_gauge_current == BOND_GAUGE_MAX` | 充能首次触达 MAX，emit `bond_gauge_full()` | 爆发执行（→ EMPTY）；再次充能仍保持 FULL（clamp） |

**注**：无专门的 BURST_EXECUTING 状态——本系统的爆发执行（Rule 6 步骤 1–6）为同步顺序代码，执行完毕即返回 EMPTY；演出时长由爆发演出系统（#8）独立管理，不阻塞本系统状态。

### Interactions with Other Systems

| 系统 | 关系 | 接口细节 |
|------|------|---------|
| 战斗解算系统 | 订阅信号（单向接收） | Rule 2：`attack_executed(attacker_id, target_id, final_damage)`；Rule 3：`cannon_executed(attacker_id, direction, hit_target_ids, base_fire_damage)`；Rule 4：`damage_dealt(target_id, final_damage, new_hp)`。`unit_downed` **不订阅**（充能来源是攻击行为，非 Downed 结果） |
| 回合管理系统 | 信号订阅 + 接口调用 | 订阅 `ROUND_END` 重置 `received_charge_this_round`；爆发执行时调用 `turn_mgmt.mark_has_acted(lead_id)` 和 `turn_mgmt.mark_has_used_verb(partner_id)` |
| 网格棋盘系统 | 只读接口调用 | `grid_board.get_adjacents(pos)` 判断攻击者相邻友方（充能差值计算）；`adjacent(pos_a, pos_b)` 验证爆发激活相邻条件（grid-board 公开接口，返回 bool，等价于 chebyshev==1） |
| 单位数据系统 | 只读接口调用 | 读取 `unit_data.get_unit(id)` 的 `.faction`、`.unit_class`、`.is_alive`、`.has_acted`、`.has_used_verb`、`.grid_position`、`.base_damage` |
| 爆发演出系统 | 发出信号（松耦合） | emit `burst_presentation_requested(lead_id, partner_id, burst_type_id)`；演出系统订阅后独立管理动画时长，**本系统不等待回调** |
| 战斗 HUD 系统 | 发出信号（松耦合） | emit `gauge_charged(attacker_id, charge_amount, bond_gauge_current)` 驱动充能槽动画；emit `bond_gauge_full()` 触发爆发按钮可用提示；emit `burst_executed(lead_id, partner_id, burst_type_id)` |
| 战后结算系统 | 发出信号（松耦合） | `burst_executed` 供结算系统统计本场战斗爆发次数 |
| 相邻羁绊系统 | **无直接连接** | 两系统均订阅 `attack_executed`，各自独立处理（本系统计充能，相邻羁绊系统注入 modifier）；分离设计，无循环依赖 |

## Formulas

**Formula 1：充能量计算（Attack Charging）**

```
adjacents_count = count(u for u in get_adjacents(attacker.pos)
                        if u.faction == ALLY and u.is_alive and u.id != attacker.id)

charge_amount = CHARGE_ADJACENT if adjacents_count > 0 else CHARGE_SOLO
bond_gauge_new = min(bond_gauge_current + charge_amount, BOND_GAUGE_MAX)
```

| 变量 | 类型 | 基线值 | 安全范围 | 来源 |
|------|------|-------|---------|------|
| `CHARGE_ADJACENT` | int | 2 | 1–4 | 本系统 |
| `CHARGE_SOLO` | int | 1 | 0–3 | 本系统 |
| `BOND_GAUGE_MAX` | int | 10 | 5–20 | 本系统（原型验证） |

示例：
- 剑豪相邻友方，发动普通攻击：gauge += 2
- 剑豪无相邻友方，发动普通攻击：gauge += 1
- 剑豪相邻友方，斩命中 2 名敌人（2次 `attack_executed`）：gauge += 2 + 2 = 4
- 炮手相邻友方，轰击命中 3 名敌人（1次 `cannon_executed`）：gauge += 2（不×3）
- 槽已满时充能：`min(10 + 2, 10) = 10`（无溢出）

---

**Formula 2：爆发技伤害（精英配对爆发）**

```
burst_damage = attacker.base_damage × BURST_DAMAGE_MULTIPLIER
```

（仅适用于精英配对爆发技的伤害输出；通用爆发 Combined Strike 使用原版伤害）

| 变量 | 类型 | 基线值 | 安全范围 | 来源 |
|------|------|-------|---------|------|
| `base_damage` | int | 1–4（各职业不同） | — | unit-data-system |
| `BURST_DAMAGE_MULTIPLIER` | int | 2 | 1–3 | 本系统 |

示例：
- 剑豪（base_damage=3）破阵先锋：burst_damage = 3 × 2 = 6 = max_hp → 可一击击杀满血目标（高投入组合的设计意图）
- 炮手（base_damage=2，推测）瞄准定位：burst_damage = 2 × 2 = 4

边界值：
- `base_damage = 1, BURST_DAMAGE_MULTIPLIER = 1`：burst_damage = 1（最小爆发伤害）
- `base_damage = 4, BURST_DAMAGE_MULTIPLIER = 3`：burst_damage = 12（上限测试；远超 max_hp = 6，削减上界时须更新）

---

**Formula 3：爆发治疗量（护持突破 / 钢铁壁垒）**

```
burst_heal = HEAL_AMOUNT × BURST_HEAL_MULTIPLIER
new_hp = min(target.current_hp + burst_heal, target.max_hp)
```

| 变量 | 类型 | 基线值 | 安全范围 | 来源 |
|------|------|-------|---------|------|
| `HEAL_AMOUNT` | int | 3 | — | battle-resolution-system（owned，read-only） |
| `BURST_HEAL_MULTIPLIER` | int | 2 | 1–4 | 本系统 |

示例：`HEAL_AMOUNT(3) × BURST_HEAL_MULTIPLIER(2) = 6 = max_hp`（全量治疗）

---

**Formula 4：首次爆发预计回合数（平衡参考）**

MVP 标准场景（2名友方相邻循环出手，受击充能忽略）：
```
攻击次数/回合 ≈ 2（2名单位各出手一次，全相邻）
充能/回合 ≈ 2 × CHARGE_ADJACENT = 4
首次爆发回合 ≈ BOND_GAUGE_MAX / 4 = 10/4 = 2.5 → 约第3回合
含受击充能（cap=2/round）：实际约 2–3 回合
```

目标：每8回合上限战斗可爆发 2–3 次，符合"每场战斗1–2次逆转性爆发"支柱。调参时以此公式校验 `BOND_GAUGE_MAX`。

## Edge Cases

**EC-1：充能槽已满时再充能**
`min()` 钳制，`bond_gauge_current` 维持 BOND_GAUGE_MAX；emit `gauge_charged(..., BOND_GAUGE_MAX)`（数值不变，HUD 可用此刷新显示）；`bond_gauge_full()` **不重复触发**——仅在槽从 < MAX 跨越到 MAX 时触发一次（通过 `bond_gauge_prev` 判断）。

**EC-2：爆发激活后 lead 在效果执行中被击倒**
Godot 信号同步执行，Rule 6 步骤 1–6 连续运行，无异步断点。爆发属于"已确认行动"，不在执行中撤销。激活**前**（Rule 5 条件检查时）若 lead 已 Downed，激活失败（is_alive = false）。

**EC-3：爆发激活后 partner 在效果执行中被击倒**
同 EC-2。激活后不再验证 partner 存活。效果中"partner 使用动词"对象为已 Downed 单位时，该动词效果跳过——爆发 lead 部分仍生效。**跨 GDD 合同**：此行为依赖 battle-resolution-system 在执行任何职业动词前检查目标/施放者的 `is_alive` 状态（Rule 3–8 各动词的施放者须 `is_alive == true`）；battle-resolution 当前 GDD 已隐含此约束（Downed 处理后 `is_alive = false` 且从存活列表移除），但未明文作为"施放者 is_alive 前置合同"——若 battle-resolution R2 起实现时发现此路径，须在其 GDD 中补充说明。

**EC-4：轰击无命中目标时仍充能**
`cannon_executed(attacker_id, direction, [], base_fire_damage)` 携带空列表。Rule 3 仍执行充能（炮手成功发射，奖励行动本身而非命中数量），充能量取决于炮手相邻友方存在与否。

**EC-5：受击充能每回合上限触发**
本回合第 RECEIVED_CHARGE_CAP+1 次（及之后）的己方受击 `damage_dealt` 信号：前置过滤拦截，`bond_gauge_current` 不变，`received_charge_this_round` 不增加。计数在 `ROUND_END` 重置为 0。

**EC-6：瞄准定位中推移失败（无合法落点）**
航海士推移（Rule 4 battle-resolution）失败时（边界 / 阻挡）：炮弹**取消**（不执行炮击）。爆发仍被视为已执行（gauge 已清零、has_acted / has_used_verb 已消耗）。HUD 须在推移前预警可能的失败风险。

**EC-7：瞄准定位中推移导致弹道穿透命中多名敌人**
炮手·轰穿透，按 battle-resolution Rule 4 逻辑：弹道上所有存活单位均受穿透爆发伤害（含推移过来的目标 A 和原本在弹道上的目标 B）。这是允许的「高技巧回报」场景，非 bug。

**EC-8：爆发激活 gauge 清零时机 vs. 充能事件时序**
Rule 6 步骤 1 先于效果执行清零 gauge。若爆发效果本身产生 `damage_dealt`（如爆发斩伤害），触发的受击充能（Rule 4）将从 0 重新积累，**不产生"爆发即刻又半满"**效果。

**EC-9：破阵先锋中目标已持有 GUARDED**
爆发斩**穿透目标 GUARDED**（Rule 7 破阵先锋效果说明），但铁壁自身获得的 GUARDED 依然保护铁壁本身——穿透是对攻击目标的特性，不影响铁壁的防御。

**EC-10：战斗结束时 gauge 未充满**
`battle_ended` 信号触发后，`bond_gauge_current = 0`（或在 `battle_started` 时重置）。进度不跨战斗保留。

**EC-11：爆发激活条件中 partner 与 lead 同一格（不可能路径）**
`lead_id != partner_id`（条件 4）且 `adjacent() == true`（条件 5，chebyshev==1）共同保证，同一单位无法同时为 lead 和 partner（同一单位自身 chebyshev==0，不满足相邻条件）。

**EC-12：热血演奏 / 轰鸣序曲中乐手自身的 AURA_BONUS 处理**
乐手对"所有相邻存活友方（除自身）"施放 AURA_BONUS——乐手不给自身 AURA。炮手·轰不接受 AURA_BONUS（battle-resolution Rule 4 设计意图：轰不经 aura_bonus 路径）；热血演奏中剑豪持 AURA_BONUS 后斩，AURA 额外追加 AURA_VALUE（合法叠加）。

## Dependencies

**上游（本系统依赖）：**

| 系统 | 依赖内容 | GDD 状态 |
|------|---------|---------|
| 战斗解算系统 | 信号：`attack_executed`、`cannon_executed`、`damage_dealt`；常量参考：`HEAL_AMOUNT = 3`（爆发治疗量基准） | Approved ✓ |
| 回合管理系统 | 接口：`mark_has_acted(unit_id)`、`mark_has_used_verb(unit_id)`；信号：`ROUND_END`（= `round_ended()`）、`battle_started()`（已补入 turn-management Interactions 表） | Approved ✓ |
| 网格棋盘系统 | 接口：`get_adjacents(pos)`、`adjacent(pos_a, pos_b)` | Approved ✓ |
| 单位数据系统 | 读取：`faction`、`unit_class`、`is_alive`、`has_acted`、`has_used_verb`、`grid_position`、`base_damage` | Approved ✓ |

**下游（依赖本系统的系统）：**

| 系统 | 依赖本系统的内容 | 本系统须保证 |
|------|----------------|------------|
| 爆发演出系统（#8） | `burst_presentation_requested(lead_id, partner_id, burst_type_id)` 信号 | 爆发激活后 Rule 6 步骤 6 必须 emit |
| 战斗 HUD 系统（#9） | `gauge_charged`、`bond_gauge_full`、`burst_executed` 信号 | 每次充能及满槽时必须 emit |
| 战后结算系统（#15） | `burst_executed(lead_id, partner_id, burst_type_id)` 统计 | burst_type_id 须为已注册枚举值 |

**双向依赖修订待办（评审时须验证）：**
- `turn-management-system.md` Interactions 表须增加本系统为 `mark_has_acted` / `mark_has_used_verb` 的调用方
- `battle-resolution-system.md` Interactions 表已列出本系统为信号订阅方（Approved GDD 已注记，无需修改）

## Tuning Knobs

| 参数 | 基线值 | 安全范围 | 影响的游戏感 |
|------|-------|---------|------------|
| `BOND_GAUGE_MAX` | 10 | 5–20 | 首次爆发的回合数；越低越频繁（= 高 juice 节奏），越高越稀缺（= 高策略压力）|
| `CHARGE_ADJACENT` | 2 | 1–4 | 相邻站位的充能奖励；越高越强制紧密站位 |
| `CHARGE_SOLO` | 1 | 0–3 | 单独作战的充能速率；设为 0 则完全依赖相邻站位才能充能 |
| `CHARGE_HIT` | 1 | 0–2 | 受击充能量；设为 0 可完全禁用"挨打充能"机制 |
| `RECEIVED_CHARGE_CAP` | 2 | 0–5 | 每回合受击充能上限；越低越压制"故意挨打"策略 |
| `BURST_DAMAGE_MULTIPLIER` | 2 | 1–3 | 精英爆发技伤害倍率；2 = 剑豪爆发可一击必杀满血目标 |
| `BURST_HEAL_MULTIPLIER` | 2 | 1–4 | 爆发治疗倍率；2 = `HEAL_AMOUNT × 2 = 6 = max_hp`（全量治疗） |

**原型锚定值（调参前须重新验证"每场战斗 1–2 次爆发"的支柱目标）**：
- `BOND_GAUGE_MAX = 10` 为原型验证值，不可随意调低（否则爆发变成每回合例行操作，失去"关键逆转"感）
- `BURST_DAMAGE_MULTIPLIER = 2` 使剑豪爆发等于 max_hp，是"高投入换击杀保证"的设计意图；降为 1 则爆发伤害与普通攻击相同，需重新定义爆发的价值主张

**不属于调参的值（架构约束，修改需跨 GDD 评审）**：
- `HEAL_AMOUNT`：由 battle-resolution-system 拥有（read-only）
- `AURA_VALUE`：由 battle-resolution-system 拥有（read-only）
- `MAX_MODIFIER_SUM`：由 battle-resolution-system 拥有（read-only）

## Visual/Audio Requirements

（具体实现由爆发演出系统 #8 承接；本系统仅定义信号接口约定）

**本系统发出的演出触发信号：**

| 信号 | 接收方 | 演出需求 |
|------|-------|---------|
| `gauge_charged(attacker_id, charge_amount, bond_gauge_current)` | 战斗 HUD | 充能槽填充动画；差值可视化 |
| `bond_gauge_full()` | 战斗 HUD | 满槽提示（闪烁 / 音效）；爆发按钮激活状态 |
| `burst_presentation_requested(lead_id, partner_id, burst_type_id)` | 爆发演出系统 | 对应配对的爆发动画（每个 burst_type_id 一套） |
| `burst_executed(lead_id, partner_id, burst_type_id)` | 战斗 HUD + 战后结算 | 爆发结束后的 UI 状态更新；结算统计 |

**本系统对演出的约束**：
- `burst_presentation_requested` 在 Rule 6 步骤 6 发出（逻辑效果已执行完毕）；演出系统不得依赖"演出完成回调"来触发伤害——伤害在演出**之前**已计算完毕
- 演出可跳过（例如调试模式）：跳过演出不影响本系统的逻辑状态
- MVP 阶段至少需要 2 套爆发演出（对应破阵先锋 + 瞄准定位）

## UI Requirements

（具体 UI 实现由战斗 HUD 系统 #9 承接；本系统仅定义所需数据接口）

| UI 元素 | 数据来源 | 更新触发时机 |
|---------|---------|------------|
| 充能槽（Bond Gauge Bar）| `gauge_charged(…, new_gauge_value)` | 每次充能 |
| 满槽提示 / 爆发按钮激活 | `bond_gauge_full()` 信号 | 槽首次达到 MAX |
| 爆发类型预览（选定搭档时）| HUD 查询 `BURST_EFFECT_TABLE[lead.class][partner.class]` | 玩家选定 lead + partner 交互时 |
| 爆发激活结果 | `burst_executed(lead_id, partner_id, burst_type_id)` | 每次爆发完成 |

**交互流程（HUD 视角）**：
1. 玩家选中 lead 单位 → HUD 高亮所有合法 partner（切比雪夫相邻 + has_used_verb = false + is_alive）
2. 玩家悬停 partner → HUD 预览 burst_type_id 对应的爆发技名和效果摘要
3. 玩家确认 → 本系统 Rule 5 验证 → Rule 6 执行 → HUD 清空选择态，槽归零动画

**不属于本系统的 UI 责任**：
- 充能槽的具体 UI 布局（归 HUD 系统）
- 爆发技效果的详细规则展示（归 HUD 系统 Tooltip）
- 爆发动画期间的输入冻结（归爆发演出系统）

## Acceptance Criteria

> 所有 AC 以 GDScript + GUT 框架描述。"发出信号"= GUT signal monitor 捕获；"字段值"= 直接断言；"调用函数"= spy 验证。

### 充能机制

**AC-1：相邻攻击充能 +2**
Given 己方 A 与另一存活友方 B 切比雪夫相邻，bond_gauge_current = 3
When `attack_executed(A, E, …)` 发出（E 为敌方）
Then `bond_gauge_current == 5`；emit `gauge_charged(A, 2, 5)`

**AC-2：单独攻击充能 +1**
Given 己方 A 无任何相邻存活友方，bond_gauge_current = 3
When `attack_executed(A, E, …)` 发出
Then `bond_gauge_current == 4`；emit `gauge_charged(A, 1, 4)`

**AC-3：斩命中多目标各充能一次**
Given 剑豪 S 有相邻友方，相邻敌方 E1 E2，bond_gauge_current = 0
When `attack_executed(S, E1, …)` 后 `attack_executed(S, E2, …)` 发出（斩的两次信号）
Then `bond_gauge_current == 4`（+2 + 2）

**AC-4：轰击充能一次（无论命中目标数量）**
Given 炮手 G 有相邻友方，bond_gauge_current = 0
When `cannon_executed(G, dir, [E1, E2], …)` 发出（单次信号，2个目标）
Then `bond_gauge_current == 2`（+2，不是 +4）

**AC-5：轰击无相邻友方充能 +1**
Given 炮手 G 无相邻存活友方，bond_gauge_current = 5
When `cannon_executed(G, dir, [], …)` 发出（弹道空置）
Then `bond_gauge_current == 6`（+1）；轰击无命中仍充能

**AC-6：受击充能 +1**
Given 己方 B，received_charge_this_round = 0，bond_gauge_current = 7
When `damage_dealt(B, …)` 发出（B.faction == ALLY）
Then `bond_gauge_current == 8`；received_charge_this_round == 1

**AC-7：受击充能每回合上限（RECEIVED_CHARGE_CAP = 2）**
Given received_charge_this_round = 2，bond_gauge_current = 5
When 第3次 `damage_dealt(B, …)` 发出
Then `bond_gauge_current == 5`（无变化）；received_charge_this_round == 2（不增加）

**AC-8：受击充能计数 ROUND_END 重置**
Given received_charge_this_round = 2
When `ROUND_END` 信号触发
Then `received_charge_this_round == 0`

**AC-9a：充能至槽满时触发 bond_gauge_full**
Given bond_gauge_current = 9
When 充能 +2（`attack_executed`，相邻）
Then `bond_gauge_current == 10`（clamp 正确）；emit `bond_gauge_full()` 恰好 1 次

**AC-9b：槽已满时再充能不重复触发 bond_gauge_full**
Given bond_gauge_current = 10（已满状态）
When 再次充能（任意 `attack_executed` 或 `cannon_executed`）
Then `bond_gauge_current == 10`（无变化）；`bond_gauge_full()` emit_count == 0（不重复触发）

**AC-10：敌方攻击不充能己方槽（阵营过滤）**
Given bond_gauge_current = 5
When `attack_executed(E, A, …)` 发出（E.faction == ENEMY）
Then `bond_gauge_current == 5`（无变化）

**AC-11：ROUND_END 不重置 gauge 值**
Given bond_gauge_current = 7
When `ROUND_END` 信号触发
Then `bond_gauge_current == 7`（充能值跨回合保留）

### 爆发技激活条件

**AC-12：槽未满不能触发爆发**
Given bond_gauge_current = 9（< 10）
When 玩家尝试激活爆发
Then 激活被拒绝；bond_gauge_current 不变；gauge 不清零

**AC-13：lead.has_acted = true 时不能激活**
Given bond_gauge_current = 10，合法 partner，但 lead.has_acted = true
When 玩家尝试以该单位为 lead 激活爆发
Then 激活被拒绝（Rule 5 条件 2 不满足）

**AC-14：partner.has_used_verb = true 时不能激活**
Given bond_gauge_current = 10，合法 lead，但 partner.has_used_verb = true
When 玩家尝试以该单位为 partner 激活爆发
Then 激活被拒绝（Rule 5 条件 3 不满足）

**AC-15：非切比雪夫相邻（距离 = 2）不能激活**
Given lead 与 partner `adjacent() == false`（距离 > 1，如切比雪夫距离 = 2）
When 玩家尝试以此组合激活爆发
Then 激活被拒绝（Rule 5 条件 5 不满足）

**AC-16：切比雪夫斜角相邻（距离 = 1，斜向）合法**
Given lead 与 partner 在斜向相邻格（`adjacent() == true`，切比雪夫距离 = 1），其余条件满足
When 玩家激活爆发
Then 激活成功

### 爆发技执行

**AC-17：爆发执行后 gauge 清零**
Given bond_gauge_current = 10，合法 lead + partner
When 爆发成功激活并执行（Rule 6）
Then `bond_gauge_current == 0`；emit `burst_executed`；emit `burst_presentation_requested`

**AC-18：爆发消耗 lead.has_acted（不消耗 has_used_verb）**
Given lead.has_acted = false，lead.has_used_verb = false，爆发执行
Then `lead.has_acted == true`；`lead.has_used_verb == false`（不变）

**AC-19：爆发消耗 partner.has_used_verb（不消耗 has_acted）**
Given partner.has_acted = false，partner.has_used_verb = false，爆发执行
Then `partner.has_used_verb == true`；`partner.has_acted == false`（不变）

**AC-20：精英配对路由正确——破阵先锋（MVP）**
Given lead = 剑豪（SWORDMASTER），partner = 铁壁（BULWARK），合法激活条件满足
When 爆发执行
Then burst_type_id == BURST_VANGUARD_BREACH；铁壁获得 GUARDED；剑豪对所有相邻敌方造成 `swordmaster.base_damage × BURST_DAMAGE_MULTIPLIER` 伤害；目标 GUARDED 状态不减伤（穿透）

**AC-21：精英配对路由正确——瞄准定位（MVP）**
Given lead = 炮手（GUNNER），partner = 航海士（NAVIGATOR），相邻敌方 E 存在，合法激活条件满足
When 爆发执行
Then burst_type_id == BURST_GUIDED_SALVO；E 被推移；炮手向推移后方向发射穿透炮弹；`damage_dealt` 携带 `gunner.base_damage × BURST_DAMAGE_MULTIPLIER`

**AC-22：配对对称性（调换 lead/partner 结果相同）**
Given bond_gauge_current = 10，lead = 铁壁，partner = 剑豪（与 AC-20 反向）
When 爆发执行
Then burst_type_id == BURST_VANGUARD_BREACH（与 AC-20 相同效果）

### 战斗生命周期

**AC-23：战斗开始 gauge 重置**
Given 上场战斗结束时 bond_gauge_current = 7，新战斗开始（`battle_started` 信号）
Then `bond_gauge_current == 0`

## Open Questions

**OQ-1（已关闭）：爆发触发方式 — 玩家主动 vs. 自动**
决策：玩家主动触发（槽满时指定 lead + partner）。理由：战棋游戏需要玩家掌控激活时机（哪一回合、哪对搭档），自动触发会剥夺关键战术决策权。

**OQ-2（已关闭）：爆发演出期间是否暂停游戏逻辑？**
决策：由 burst-presentation-system.md Rule 2 的输入锁定机制关闭。演出期间玩家输入被禁用（emit `burst_presentation_started`）；游戏为回合制架构，逻辑推进的唯一入口为玩家输入，故演出期间游戏状态天然静止。本系统 emit `burst_presentation_requested` 后立即返回，与此设计相容。

**OQ-3（开放）：通用爆发（Combined Strike）是否足够有趣？**
15 种非精英配对共用"各自执行原版动词"的框架，可能缺乏记忆点。Alpha 试玩后评估：若通用爆发"无聊感"过强，可为每个职业定义"爆发动词"（参与爆发时的专属效果变体），将 15 种配对转换为 6 个职业动词的两两组合（设计成本更低）。Alpha 里程碑前决策。

**OQ-4（开放）：爆发激活是否应消耗 partner.has_acted？**
当前设计：只消耗 partner.has_used_verb，不影响 partner.has_acted（partner 爆发后仍可普通攻击）。这可能使爆发的行动经济过于宽松（partner 不受损）。Alpha 试玩验证后决策；保守方向：改为同时消耗 partner.has_acted。
