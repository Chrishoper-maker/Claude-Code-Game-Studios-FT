# 相邻羁绊系统（Adjacent Bond System）

> **Status**: Approved（R4 修订后 CD 放行，无需 R5）
> **Author**: Chris + Claude
> **Last Updated**: 2026-06-16
> **Implements Pillar**: 羁绊即战术（站位本身是羁绊机制）；小棋盘大组合（6 职业产生组合效果矩阵）

## Overview

相邻羁绊系统是《孤帆棋海》战术几何的**意义层**——将棋盘上的站位关系翻译为可量化的战斗加成。当某名己方船员发起攻击（普通攻击或剑豪·斩）时，本系统检查其切比雪夫相邻格中是否存在其他己方存活单位；若存在，则依据两者职业组合查询**羁绊效果矩阵**，并在战斗解算执行前调用 `register_attack_modifier(attacker_id, bonus)` 注入伤害修正器（单次攻击总注入上限 `MAX_MODIFIER_SUM = 2`，由战斗解算系统截断）。

玩家感知到的是：让正确的两人并肩出击，攻击就会额外伤害；被迫分散或组合不匹配时则丧失这层加成。"谁站在谁旁边"因此成为每回合最核心的战术决策——不是方位选择，而是战力配置。本系统不掌管棋盘几何（归网格棋盘系统）、不计算伤害（归战斗解算系统）、不维护羁绊槽（归羁绊槽与爆发技系统）；它只负责在"站位事实"与"攻击数值"之间建立语义桥梁，让 6 种职业 × 21 种配对的组合空间在棋盘上真实生效。

## Player Fantasy

玩家不会说"我触发了修正器注入"——他们会说**"我把他们两个逼近，果然加强了！"**

这个系统服务的情感是：**战术预谋的即时验证**。你消耗一次移动行动让医师靠近剑豪，转而让剑豪出手，伤害提升了——这一刻既是计算的回报，也是"我的伙伴让我更强"的情感兑现。对标支柱原文："羁绊即战术——你的战术语言不是技能栏，而是棋盘上的几何关系"。这里的"语言"就是羁绊系统教会玩家的词汇：靠近=加强，分散=削弱，选错搭档=白费站位。

**锚定时刻**：第一次在没有任何提示的情况下"发现"——将某两名船员走到相邻格，攻击数字变大了——玩家会主动反问"为什么？是他们的职业组合吗？如果换一个人靠过去会怎样？"这个自发探索冲动本身就是「小棋盘大组合」支柱实现的标志。

**情感红线**：如果玩家靠近后发现加成比不靠近时还弱（或效果是负面的），且没有明确预告，战术信任会在那一刻破碎。本系统必须保证"靠近友方 = 至少中性，特定组合才有正向加成"——不允许隐藏的惩罚性相邻。

## Detailed Design

### Core Rules

**Rule 1：触发条件**
**前置条件（precondition）**：`attacker.faction == FACTION.ALLY`
（本系统仅处理玩家方发起的攻击；敌方单位执行同类动作时，本系统全部逻辑跳过。）

当己方单位（`attacker`）满足上述前置条件并发起以下动作时，本系统介入：
- 普通攻击（战斗解算 Rule 1）
- 剑豪·斩（战斗解算 Rule 3）

其他职业动词（轰/挡/愈/移/奏）**不触发**本系统，与战斗解算的修正器限制完全对齐。
*（触发动词列表与 battle-resolution-system.md Rule 2 保持一致；若新增职业动词须两处同步更新。）*

**Rule 2：相邻检测（由战斗解算发出 `attack_initiated(attacker_id, verb)` 信号触发；信号在 `is_valid_attack()` 验证通过后、`pending_modifiers` 消耗前发出；Godot 同步信号——本系统回调完成注入后，战斗解算在同一帧继续执行）**
0. **前置过滤（任一条件为真则立即返回，不执行后续步骤）**：
   - 若 `unit_data.get_unit(attacker_id).faction != FACTION.ALLY`：返回。（Rule 1 阵营前置条件显式检查——`attack_initiated` 信号本身无阵营过滤，敌方单位执行攻击同样发出该信号；须在此强制执行"本系统仅处理玩家方发起的攻击"的设计约束。）
   - 若 `verb ∉ {VERB_NORMAL_ATTACK, VERB_SLASH}`：返回。（仅普通攻击和剑豪·斩触发本系统；其他动词不发出 `attack_initiated` 信号，此过滤为信号层防御性保护。）
1. 调用 `grid_board.get_adjacents(attacker.grid_position)` 获取相邻格中的单位
2. 过滤出满足 `faction == ally AND is_alive == true` 的单位列表（己方存活相邻单位）
3. 对每个相邻友方，查询羁绊效果矩阵：`bond_bonus = BOND_MATRIX[attacker.unit_class][ally.unit_class]`
4. 对每个 `bond_bonus > 0` 的相邻友方，调用 `register_attack_modifier(attacker_id, bond_bonus)`
5. 若无相邻友方或所有 `bond_bonus == 0`：不调用 `register_attack_modifier()`，攻击照常进行

*（注：修正器的实际消耗时序由战斗解算系统管理——普通攻击在 `attack_executed` 广播前消耗（battle-resolution Rule 1 步骤 7），斩在所有 `attack_executed` 广播后消耗（battle-resolution Rule 3 步骤 ⑦）；此时序差异不影响本系统的注入行为。）*

**Rule 3：羁绊效果矩阵（BOND_MATRIX）**
矩阵为对称矩阵（`BOND_MATRIX[A][B] == BOND_MATRIX[B][A]`）。两层结构：
- **通用羁绊**（`BOND_BASE = 1`）：大多数职业配对
- **精英羁绊**（`BOND_ELITE = 2`）：特定职业配对，一名精英伙伴即可达到 `MAX_MODIFIER_SUM` 上限

**精英羁绊配对（6 对）：**

| 配对 | 戏剧性逻辑 |
|------|-----------|
| 剑豪 + 乐手 | 光环直接强化近战主力 |
| 炮手 + 乐手 | 光环直接强化远程主力（⚠ 精英加成仅在炮手使用**普通攻击**时生效；炮手·轰不接受修正器，见 battle-resolution Rule 4） |
| 剑豪 + 医师 | 前线+治疗：医师让剑豪敢冲 |
| 炮手 + 航海士 | 位移控制 + 射程发挥（航海士先推移敌人，炮手普通攻击打出精英加成） |
| 铁壁 + 医师 | 盾+愈经典搭档 |
| 剑豪 + 铁壁 | 坦克护卫突破手 |

同职业配对（6 种）及未列出的异职业配对均为通用羁绊（`BOND_BASE = 1`）。**同职业配对设计说明**：同职业船员仍有通用默契（+1），但不形成专属精英化学反应——避免双剑豪叠加在加成上过度收益，保持6职业间构筑多样性。

**Rule 4：修正器上限兼容性**
本系统的单次攻击总注入设计不超过 `MAX_MODIFIER_SUM = 2`——精英羁绊本身 = 2 = 上限，单伙伴即封顶。若攻击者有多名相邻友方（如 1 精英 + 1 通用），总注入 = 2+1 = 3，由战斗解算截断至 2，行为符合预期。

### States and Transitions

**本系统无持久状态**。不维护任何跨攻击或跨回合的数据——每次攻击均独立查询当前棋盘格局，即时反映站位变动。

### Interactions with Other Systems

| 系统 | 方向 | 接口 |
|------|------|------|
| 网格棋盘系统 | 调用 | `get_adjacents(pos) → Array[unit_id]`（获取相邻单位） |
| 单位数据系统 | 读取 | `unit.unit_class`、`unit.faction`、`unit.is_alive`（判断配对与合法性） |
| 战斗解算系统 | 信号订阅 + 注入（单向） | 订阅 `attack_initiated(attacker_id, verb)` 信号（触发 Rule 2 扫描）；扫描后对每个 bond_bonus > 0 的相邻友方调用 `register_attack_modifier(attacker_id, bond_bonus)` |

**单向依赖约定**：本系统仅调用战斗解算的注入接口；战斗解算不回调本系统，防止循环依赖。

## Formulas

### Formula 1：Bond Modifier 计算

```
bond_modifier_total = Σ BOND_MATRIX[attacker.unit_class][ally.unit_class]
                      （对所有满足 faction==ally AND is_alive==true 的相邻单位求和）
```

**变量：**

| 变量 | 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|------|
| 攻击者职业 | `attacker.unit_class` | Enum | 6 种值 | 查矩阵的行键 |
| 相邻友方职业 | `ally.unit_class` | Enum | 6 种值 | 查矩阵的列键 |
| 矩阵值 | `BOND_MATRIX[a][b]` | int | 1 或 2 | 1=通用羁绊；2=精英羁绊（当前矩阵无 0 值；`bond_bonus > 0` 过滤为扩展保留——若未来新增"无羁绊"配对可设 0 而无需修改执行逻辑） |
| 通用基础值 | `BOND_BASE` | int | **1**（基线，安全范围 0–2；见 Tuning Knobs） | 大多数配对的 modifier 值 |
| 精英加成值 | `BOND_ELITE` | int | **2**（基线，安全范围 BOND_BASE–2；见 Tuning Knobs） | 精英配对在矩阵中直接存储为 2；查表即得最终值，无需额外运算（非"叠加 BOND_BASE"，矩阵已包含全部语义） |
| 总注入值 | `bond_modifier_total` | int | 0–N×BOND_ELITE | 传入 `register_attack_modifier()` 的累计值；战斗解算截断至 MAX_MODIFIER_SUM=2 |

**输出范围**：0（无相邻友方）到理论上限 N×BOND_ELITE（N 名相邻精英友方）；由战斗解算的 MAX_MODIFIER_SUM=2 截断，实际有效范围 0–2。

**示例：**
- 剑豪 + 1 名相邻乐手（精英）：`BOND_MATRIX[swordsman][musician] = 2` → 注入 2 → modifier_sum = min(2, 2) = **+2**
- 炮手 + 1 名相邻铁壁（通用）：`BOND_MATRIX[gunner][bulwark] = 1` → 注入 1 → modifier_sum = **+1**
- 医师 + 1 名相邻剑豪（精英 2）+ 1 名相邻炮手（通用 1）：注入 3 → modifier_sum = min(3, 2) = **+2**
- 任何单位，无相邻友方：注入 0 → modifier_sum = **+0**

### Formula 2：完整 BOND_MATRIX（6×6 对称矩阵）

|  | 剑豪 | 炮手 | 铁壁 | 医师 | 航海士 | 乐手 |
|--|------|------|------|------|--------|------|
| **剑豪** | 1 | 1 | **2** | **2** | 1 | **2** |
| **炮手** | 1 | 1 | 1 | 1 | **2** | **2** |
| **铁壁** | **2** | 1 | 1 | **2** | 1 | 1 |
| **医师** | **2** | 1 | **2** | 1 | 1 | 1 |
| **航海士** | 1 | **2** | 1 | 1 | 1 | 1 |
| **乐手** | **2** | **2** | 1 | 1 | 1 | 1 |

粗体 = `BOND_ELITE = 2`；普通 = `BOND_BASE = 1`；同职业对角线 = `BOND_BASE = 1`（通用，非专属）。

## Edge Cases

- **若攻击者在攻击时已无相邻友方（相邻单位在本回合更早被 Downed）**：扫描相邻格结果为空，`bond_modifier_total = 0`，不调用 `register_attack_modifier()`，攻击按无修正器执行。
- **若相邻单位在扫描瞬间 `is_alive == false`（Downed 但 `unit_downed` 信号尚未处理完）**：过滤条件 `is_alive == true` 保证 Downed 单位不计入相邻，无论信号处理顺序。
- **若攻击者与己方铁壁相邻，铁壁持有 GUARDED 状态**：GUARDED 是铁壁的防御状态，不影响本系统对铁壁的判定——仍按 `BOND_MATRIX[attacker][bulwark]` 正常计算。
- **若攻击者持有 AURA_BONUS（乐手·奏所赋）且同时有精英相邻友方**：AURA_BONUS 是 `final_damage` 的独立第三项，与 `modifier_sum` 路径分离，两者合法叠加。`base_damage(3) + modifier_sum(2) + aura_bonus(1) = 6 = max_hp`，在无 GUARDED 的满血目标上可**一击必杀**。这是高投入设计意图：需要乐手先行使用·奏（消耗 `has_used_verb`），攻击者再维持精英相邻站位才能触发此组合，属于两回合资源换击杀保证的许可例外路径。"常规路径两发击杀"目标适用于 `base_damage` 独立攻击的标准场景。
- **若航海士·移将攻击者强制位移后改变了相邻关系**：本系统在攻击**确认时**查询当前格局——位移已完成则以新位置为准；位移尚未发生则以旧位置为准。两个行动彼此独立，无中间状态。
- **若 `get_adjacents()` 返回混合阵营单位（敌我混杂）**：步骤 2 的 `faction == ally` 过滤保证仅计算己方单位；敌方单位物理相邻不贡献修正器。
- **若炮手普通攻击因 `GUNNER_MIN_RANGE` 约束被战斗解算拒绝**：`attack_initiated` 信号仅在 `is_valid_attack()` 验证**通过后**发出（见 Rule 2 说明及 battle-resolution Rule 1 步骤 0），因此被拒绝的攻击根本不触发本系统，`register_attack_modifier()` 不被调用，`pending_modifiers` 无残留污染。（**时序已确认**：信号在验证后发出。）
- **若剑豪在同一回合先使用职业动词·斩再使用普通攻击（或反之）**：两次动作均独立触发 Rule 2 扫描，各按当时棋盘格局查询一次 BOND_MATRIX，各自调用 `register_attack_modifier()`。若全程与精英伙伴相邻，单回合最多触发两次 +2 注入（各次被战斗解算截断至 max=2）。此为**设计意图**：斩与普通攻击受独立行动点约束（`has_used_verb` / `has_acted`），正确序列使用是玩家策略选择，不视为漏洞。

## Dependencies

### 上游依赖（本系统依赖）

| 系统 | GDD 状态 | 接口 | 依赖性质 |
|------|---------|------|---------|
| 单位数据系统 (#1) | Approved | `unit.unit_class`、`unit.faction`、`unit.is_alive`（读取） | 硬依赖（无此数据则无法查矩阵）；**初始化顺序约束**：本系统的 `attack_initiated` 信号回调在 Rule 2 Step 0 调用 `unit_data.get_unit(attacker_id).faction`，要求 unit_data 系统在本系统订阅信号前已完成 `_ready()` 初始化；实现时须确保 Godot 场景树中 unit_data 节点位置早于本系统节点，或在回调开始处添加空值防卫断言 |
| 网格棋盘系统 (#2) | Approved | `get_adjacents(pos) → Array[unit_id]`（调用） | 硬依赖（本系统不自行实现几何） |

### 下游系统（依赖本系统输出）

| 系统 | GDD 状态 | 接口 | 依赖性质 |
|------|---------|------|---------|
| 战斗解算系统 (#4) | Approved | `register_attack_modifier(attacker_id, bonus)`（本系统调用此接口） | 本系统注入修正器；战斗解算不回调本系统（防循环依赖） |
| 羁绊槽与爆发技系统 (#6) | Not Started | 订阅 `attack_executed`、`damage_dealt` 信号（由战斗解算发出） | 松耦合——本系统不直接与羁绊槽通信；修正器放大伤害，间接影响充能速度。原型中"相邻攻击充能 +2 / 单独 +1"的差异化充能逻辑**归 System #6 所有**：本系统仅提供伤害修正器，充能倍率逻辑（含相邻检测）须在 #6 GDD 中单独设计。 |

### 双向一致性声明

- grid-board-system.md 的 Dependencies 节已列出本系统为其使用方 ✓
- battle-resolution-system.md 的 Dependencies 节已声明 `MAX_MODIFIER_SUM = 2` 须由本 GDD 确认 → 本 GDD 已在 Formulas 中确认（精英羁绊 = 2 = 上限）✓

## Tuning Knobs

| 旋钮 | 当前值 | 安全范围 | 调高效果 | 调低效果 | 联动约束 |
|------|--------|---------|---------|---------|---------|
| `BOND_BASE` | 1 | 0–2 | 通用相邻更值钱，随机站位也有奖励 | 消除通用相邻奖励，只有精英配对才有意义 | 调至 2：等同 MAX_MODIFIER_SUM，1 名普通友方即封顶，削减精英配对差异化价值 |
| `BOND_ELITE` | 2 | BOND_BASE–2（当前 1–2） | 有效上限受 MAX_MODIFIER_SUM 钳制（>2 被截断等同 2，调高无实际效果；若需突破须同步调高 MAX_MODIFIER_SUM） | 降低精英配对优势，靠近正确的人没那么重要 | 须 ≥ BOND_BASE（**安全范围下限随 BOND_BASE 变动**；调整 BOND_BASE 时须同步修正此范围）；与 MAX_MODIFIER_SUM 强联动，调整须两 GDD 同步 |
| `MAX_MODIFIER_SUM` | 2 | 1–3 | 允许更高修正器总值，可能破坏两发击杀保证 | 压缩羁绊加成上限，精英配对优势下降 | **高危旋钮，只读引用**——此值由 battle-resolution-system.md 拥有和维护；本 GDD 仅展示当前值和影响描述，**调整入口在 battle-resolution-system.md**（在本 GDD 修改此值不产生任何效果）；联动调整须两 GDD 同步 |
| 精英配对数量 | 6（共 21 对中） | 4–10 | 更多精英配对 = 更多"发现感"，但构筑约束减弱 | 更少精英配对 = 核心羁绊更稀有，构筑方向更明确 | 每次修改须更新 BOND_MATRIX 并重跑 `/design-review` 验证两发击杀保证 |

## Visual/Audio Requirements

[To be designed]

## UI Requirements

[To be designed]

## Acceptance Criteria

**AC-1 通用羁绊基础加成**
GIVEN 剑豪 S 与炮手 G 相邻（通用配对），S 无 AURA_BONUS，无其他相邻友方
WHEN S 使用普通攻击
THEN `register_attack_modifier(S, 1)` 被调用**恰好一次**，bonus == 1（本系统职责到此为止；`modifier_sum` 和 `final_damage` 的验证属战斗解算责任域）

**AC-2 精英羁绊加成达到上限**
GIVEN 剑豪 S 与乐手 M 相邻（精英配对），S 无 AURA_BONUS，无其他相邻友方
WHEN S 使用普通攻击
THEN `register_attack_modifier(S, 2)` 被调用**恰好一次**，bonus == 2（本系统职责到此为止）

**AC-2b 精英羁绊 — 炮手+乐手**
GIVEN 炮手 G 与乐手 M 相邻（精英配对），G 无 AURA_BONUS，无其他相邻友方
WHEN G 使用普通攻击
THEN `register_attack_modifier(G, 2)` 被调用**恰好一次**，bonus == 2

**AC-2c 精英羁绊 — 剑豪+医师**
GIVEN 剑豪 S 与医师 H 相邻（精英配对），S 无 AURA_BONUS，无其他相邻友方
WHEN S 使用**普通攻击**（`VERB_NORMAL_ATTACK`，非斩；斩路径见 AC-10）
THEN `register_attack_modifier(S, 2)` 被调用**恰好一次**，bonus == 2

**AC-2d 精英羁绊 — 炮手+航海士**
GIVEN 炮手 G 与航海士 N 相邻（精英配对），G 无 AURA_BONUS，无其他相邻友方
WHEN G 使用普通攻击
THEN `register_attack_modifier(G, 2)` 被调用**恰好一次**，bonus == 2

**AC-2e 精英羁绊 — 铁壁+医师**
GIVEN 铁壁 B 与医师 H 相邻（精英配对），B 无 AURA_BONUS，无其他相邻友方
WHEN B 使用普通攻击
THEN `register_attack_modifier(B, 2)` 被调用**恰好一次**，bonus == 2

**AC-2f 精英羁绊 — 剑豪+铁壁**
GIVEN 剑豪 S 与铁壁 B 相邻（精英配对），S 无 AURA_BONUS，无其他相邻友方
WHEN S 使用普通攻击
THEN `register_attack_modifier(S, 2)` 被调用**恰好一次**，bonus == 2

**AC-3 无相邻友方：零修正器**
GIVEN 剑豪 S 周围无相邻友方（可有相邻敌方）
WHEN S 使用普通攻击
THEN `register_attack_modifier` 未被调用（调用次数 == 0）

**AC-4 多相邻友方：超额截断**
GIVEN 炮手 G 同时相邻乐手 M（精英, +2）和铁壁 B（通用, +1），无其他相邻友方
WHEN G 使用普通攻击
THEN `register_attack_modifier(G, 2)` 被调用**恰好一次**，`register_attack_modifier(G, 1)` 被调用**恰好一次**，两次调用相互独立（**不得合并**为单次 `register_attack_modifier(G, 3)` 调用）；调用顺序不定；共 2 次调用，总注入 = 3；截断（由战斗解算 `min(3, 2) = 2`）属战斗解算责任域

**AC-5a 矩阵对称性 — 医师为攻击者**
GIVEN 医师 H 与剑豪 S 相邻，H 无 AURA_BONUS，无其他相邻友方
WHEN H 使用普通攻击
THEN `register_attack_modifier(H, 2)` 被调用**恰好一次**，bonus == 2（`BOND_MATRIX[medic][swordsman] = 2`）

**AC-5b 矩阵对称性 — 医师为攻击者（铁壁+医师对称）**
GIVEN 医师 H 与铁壁 B 相邻（精英配对），H 无 AURA_BONUS，无其他相邻友方
WHEN H 使用普通攻击
THEN `register_attack_modifier(H, 2)` 被调用**恰好一次**，bonus == 2（`BOND_MATRIX[medic][bulwark] = 2`，与 AC-2e（铁壁为攻击者）结果相同，验证矩阵对称性）

**AC-6 Downed 单位不计入相邻（含存活友方对照）**
GIVEN 剑豪 S 同时与医师 H（`H.is_alive == false`，已 Downed；S–H 为精英配对）和炮手 G（`G.is_alive == true`；S–G 为通用配对）相邻，S 无 AURA_BONUS
WHEN S 使用普通攻击
THEN `register_attack_modifier(S, 1)` 被调用**恰好一次**（G 贡献通用羁绊 +1）；H 因 `is_alive == false` 被步骤 2 过滤，未贡献修正器；`register_attack_modifier` 总调用次数 == 1（可区分"过滤机制生效"与"无候选者"两个逻辑分支）

**AC-7 敌方相邻不贡献修正器**
GIVEN 剑豪 S 与敌方单位 E 相邻，无其他相邻友方
WHEN S 使用普通攻击
THEN `register_attack_modifier` 未被调用（调用次数 == 0；E 因 `faction == enemy` 被步骤 2 过滤）

**AC-8 其他动词不触发 attack_initiated 信号（铁壁·挡为例）**
GIVEN 铁壁 B 与乐手 M 相邻（精英配对），B 使用职业动词"挡"
WHEN B 执行挡（battle-resolution Rule 5 执行）
THEN 战斗解算执行 Rule 5（铁壁·挡）时**不发出** `attack_initiated` 信号（GUT spy 监听 `attack_initiated` 信号发出次数 == 0；`挡` 不在触发动词列表内）；B 获得 GUARDED 状态（`guard_applied(B, B)` 发出）（注：GUARDED 是 battle-resolution Rule 5 的断言，由战斗解算 AC 负责；本 AC 仅验证本系统不介入）

**AC-14 己方单位使用非触发动词——羁绊系统不介入（动词过滤路径独立验证）**
GIVEN 医师 H 与剑豪 S 相邻（精英配对），H 使用职业动词"愈"
WHEN H 执行愈（`VERB_HEAL`，不在 `{VERB_NORMAL_ATTACK, VERB_SLASH}` 内）
THEN `attack_initiated` 信号不发出（GUT spy 次数 == 0）；本系统 Rule 2 未执行；`register_attack_modifier` 未被调用（注：H.faction == ALLY，不触发 Step 0 阵营过滤，动词过滤是唯一有效防线；本 AC 独立验证"阵营合法但动词非法"路径，与 AC-8 解耦）

**AC-9 精英配对 + AURA_BONUS 路径独立叠加** `[集成测试 — 须在包含战斗解算的集成测试环境中验证]`
GIVEN 剑豪 S（`S.base_damage = 3`）持有 AURA_BONUS，与乐手 M 相邻（精英配对），无其他相邻友方
WHEN S 使用普通攻击（无 GUARDED 目标）
THEN `register_attack_modifier(S, 2)` 被调用**恰好一次**，bonus == 2（本系统职责；AURA_BONUS 不经由 `register_attack_modifier` 注入，故 register 总调用次数 == 1，即使 AURA_BONUS 同时激活）；AURA_BONUS 路径由战斗解算独立处理（本系统不干预）；`final_damage = 3 + 2 + 1 = 6`（含一击必杀可能）须在集成测试层验证（战斗解算 Formula 1 责任域）

**AC-10 职业动词·斩触发羁绊检测**
GIVEN 剑豪 S 与医师 H 相邻（精英配对），S 无 AURA_BONUS，相邻有 1 名敌方 E
WHEN S 使用职业动词"斩"
THEN `register_attack_modifier(S, 2)` 被调用**恰好一次**，bonus == 2（`VERB_SLASH` 在触发列表内，Rule 2 正常执行）

**AC-11 炮手射程不足攻击被拒绝——本系统不介入**
GIVEN 炮手 G 与乐手 M 相邻（精英配对），G 尝试对 `manhattan_distance = 1` 的目标执行普通攻击
WHEN 战斗解算 `is_valid_attack()` 返回 `false`（`GUNNER_MIN_RANGE = 2` 约束拒绝）
THEN `attack_initiated` 信号不发出（GUT spy 监听次数 == 0）；`register_attack_modifier` 未被调用；`pending_modifiers[G]` 为空（无残留）；`G.has_acted == false`

**AC-12 同职业配对返回通用羁绊（矩阵对角线）**
GIVEN 剑豪 S1 与剑豪 S2 相邻（同职业，`BOND_MATRIX[swordsman][swordsman] = 1`），S1 无 AURA_BONUS，无其他相邻友方
WHEN S1 使用普通攻击
THEN `register_attack_modifier(S1, 1)` 被调用**恰好一次**，bonus == 1（通用羁绊，非精英；验证对角线值正确，未被误设为 2 或 0）

**AC-13 敌方单位发起普通攻击——本系统不介入**
GIVEN 敌方剑豪 E 与己方医师 H 相邻，E 目标为相邻的己方单位
WHEN E 执行普通攻击（`is_valid_attack()` 通过，战斗解算发出 `attack_initiated(E_id, "normal_attack")`）
THEN 本系统 Rule 2 因 `attacker.faction != FACTION.ALLY` 在 Step 0 立即返回；`register_attack_modifier` 未被调用（GUT spy 监听次数 == 0）；`pending_modifiers[E_id]` 为空（无羁绊加成注入）

**AC-13b 敌方单位发起"斩"——本系统不介入（Step 0 阵营过滤覆盖 VERB_SLASH 路径）**
GIVEN 敌方剑豪 E 与己方医师 H 相邻，E 具备使用斩的条件
WHEN E 执行职业动词"斩"（`is_valid_attack()` 通过，战斗解算发出 `attack_initiated(E_id, "slash")`）
THEN 本系统 Rule 2 Step 0 阵营检查先于动词检查触发，因 `attacker.faction != FACTION.ALLY` 立即返回；`register_attack_modifier` 未被调用（GUT spy 监听次数 == 0）（注：AC-13 覆盖 VERB_NORMAL_ATTACK 路径，本 AC 覆盖 VERB_SLASH 路径，两者共同验证 Step 0 阵营过滤对两个合法动词入口均生效）

## Open Questions

**OQ-1 精英羁绊 vs 通用羁绊的视觉差异化方案（须在原型阶段前完成设计）**
Player Fantasy 的"发现感"依赖玩家能感知"靠近特定伙伴=数字更大"——精英配对（+2）与通用配对（+1）须有可区分的视觉/音效反馈层级（如精英触发专属粒子/音效 vs 通用触发基础闪光）。若两种羁绊使用相同视觉反馈，玩家无法自主发现矩阵配对差异，核心发现动力消失。设计决策须在进入实现前锁定，并更新 Visual/Audio Requirements 和 UI Requirements 节。
