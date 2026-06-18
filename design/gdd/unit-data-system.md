# 单位数据系统 (Unit Data System)

> **Status**: Approved
> **Author**: user + systems-designer + qa-lead
> **Last Updated**: 2026-06-13 (R3 修订)
> **Implements Pillar**: 小棋盘大组合（数据定义的元素互动）；支撑「羁绊即战术」

## Overview

单位数据系统是《孤帆棋海》所有作战单位（船员与敌人）的数据定义层——游戏的"事实源"。它规定每个单位由哪些属性构成（生命、移动力、射程、基础伤害、职业、羁绊标签、个性标识、行为原型引用），并以数据驱动方式外置全部数值，使设计师无需改代码即可增删单位与调整平衡。它自身不含任何玩法逻辑：战斗解算、相邻羁绊、敌人 AI 等七个下游系统按本文档定义的数据形状消费单位数据。玩家从不直接接触本系统，但"每名船员都是独特棋子"的体验完全由它使能——若没有它，8 名船员与 6 种职业的差异只能散落在硬编码里，21 配对羁绊矩阵无从查表，「小棋盘大组合」支柱失去地基。数据文件格式与引擎载体的选型不在本文档范围内，由架构阶段决定。

## Player Fantasy

玩家永远不会"看到"单位数据系统，但他们感受到的一切差异都从这里发源。当玩家说"我的炮手和你的炮手不一样，因为她站在剑豪旁边时会眼睛发光"——那个瞬间的承载物，就是本系统里的职业字段、羁绊标签和个性标识。

本系统服务的间接幻想是概念书核心幻想的物质基础：**"你不是在操控一支军队，而是在组建一艘船上的一家人。"** 数据层面这意味着：船员不是一组裸数值，每条船员记录都必须携带让他成为"伙伴"而非"棋子"的字段——名字、称号、必杀喊名。同样的 HP 和移动力，写成 `unit_07` 是士兵，写成"铁球·梅莉——'要上了哦，船长！'"就是伙伴。参考《Into the Breach》的反例：它的机师有名字但无个性字段，玩家对机师的情感投资远弱于《FTL》给船员起名换装的归属感——本作以 FTL 为情感方向，玩家主权机制计划在功能层（航线与招募）实现。

设计检验：删掉任何一个个性字段后，"组建一家人"的幻想是否受损？受损 → 该字段是核心，不是装饰。

## Detailed Design

### Core Rules

**1. 单位模板（UnitDefinition）——共用基底**。每个单位（船员或敌人）由一条静态模板定义，运行时不可变：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | 唯一标识 | 蛇形命名（如 `crew_azhan`） |
| `display_name` | 文本 | 名字（玩家可见） |
| `faction` | 枚举 | `crew` / `enemy` |
| `unit_class` | 枚举 | 六职业之一（见规则 4） |
| `max_hp` | 整数 | 生命上限 |
| `move_range` | 整数 | 每回合移动格数 |
| `attack_range` | 整数 | 攻击射程（`attack_range=1` 时切比雪夫/八向；`attack_range≥2` 时曼哈顿；度量规则由 grid-board-system 唯一裁决） |
| `base_damage` | 整数 | 基础攻击伤害 |
| `bond_tags` | 标签数组 | 羁绊查表键，默认 = `[unit_class]`，可追加；**多标签优先级契约**：相邻触发时按 `named_pair_overrides > 共有 bond_tags（按标签名字典序取首个匹配）> 各自职业标签` 顺序取**一条**效果，多标签不叠加——字典序保证相同标签组合的触发结果确定性，与单位主被动角色无关；相邻羁绊 GDD 只需实现单效果查表 |
| `class_action_id` | 引用或 `null` | 职业动词的行为引用（行为定义归战斗解算 GDD）；**`null` 合法**——表示该单位无职业动词，校验时跳过悬空引用检查，且生成 UnitInstance 时 `has_used_verb` 初始化为 `true` |

**2. 船员扩展（CrewDefinition）**——基底之上追加：

| 字段 | 类型 | 说明 |
|------|------|------|
| `title` | 文本 | 称号（如"三刀流见习"） |
| `battle_cry` | 文本 | 必杀喊名（爆发演出分镜引用） |
| `persona_line` | 文本 | 个性台词（招募界面展示）；战斗中是否复用（如鼠标悬停 HUD）待 HUD GDD 确认（→ Open Question #9） |
| `named_pair_overrides` | `Array[{partner_id: String, override_effect_id: String}]` | 专属配对覆盖，每条为 `{partner_id, override_effect_id}` 键值对；**查表优先级：专属 > 职业通用**（契约写入相邻羁绊 GDD）；**查找方向**：运行时扫描双方的 named_pair_overrides 列表，任一方持有指向对方的条目即触发——因 AC-13 已确保同一对不同时在双方出现，结果唯一确定；MVP 阶段为空（先验证职业通用羁绊）；垂直切片阶段填充 |
| `recruit_pool_tier` | 枚举 | `starting`（起航 2 人）/ `pool`（招募池）/ `unlockable`（悬赏成长解锁） |
| `portrait_id` / `model_id` | 资产引用 | 立绘与低模占位 |

**3. 敌人扩展（EnemyDefinition）**——基底之上追加：

| 字段 | 类型 | 说明 |
|------|------|------|
| `behavior_type` | 枚举 String | 行为原型枚举，取值 `"MELEE"` / `"RANGED"` / `"GUARDIAN"` / `"SWARMER"`（定义归敌人 AI 与意图系统 GDD #7，已锁定）；玩家单位无此字段 |
| `home_pos` | `Vector2i` | 驻守型（`GUARDIAN`）的初始部署格，战斗地图在部署时写入；非驻守型单位设为 `Vector2i(-1, -1)`（哨兵值，同 grid_position Downed 哨兵定义一致） |
| `threat_tier` | 整数 | 悬赏等级分层（航线难度递增消费）；tier ∈ {1, 2, 3}（MVP） |

**4. 六职业定义——每职业一个棋盘动词**，数值倾向带保证剪影差异：

| 职业 | 动词 | 数值倾向（带，非定值） | 战术身份 |
|------|------|------------------------|----------|
| 剑豪 (swordsman) | 斩 | 射程 1｜伤害高｜移动中 | 近战单体爆发 |
| 炮手 (gunner) | 轰 | 射程 3+｜伤害中（与剑豪同锁 3，但炮手的价值是**行动经济**：射程省去走位回合 = 每回合多一次有效输出）｜移动低 | 远程压制；**战斗解算依赖约束**：若战斗解算允许炮手在近战距离正常攻击，则炮手与剑豪的角色差异将被压缩至移动力，须设计补偿机制 |
| 铁壁 (bulwark) | 挡 | HP 高｜伤害低｜守护动作 | 吸收与保护 |
| 医师 (medic) | 愈 | 伤害极低｜治疗动作 | 续航支援 |
| 航海士 (navigator) | 移 | 伤害低｜推拉敌我位移 | 位移控制——**远程身份修复工具**（原型课题） |
| 乐手 (musician) | 奏 | 伤害2｜光环增幅 | 范围增益 |

动词的具体效果与数值归战斗解算 GDD；本表锁定的是枚举成员与数值倾向带。

> **医师与乐手的招募博弈**：两者均属低伤害支援职业，但招募时的选择标准不同——医师提供续航（`action_weight=2` 的治疗优先稳住残血核心），乐手提供爆发放大（光环附着队伍，单轮削峰更强但不修复已发生的伤害）。两者的 power_score 带相同（13–16），`battle_cry` 与 `bond_tags` 是招募差异化的重要信号——设计师必须保证两者的个性字段足够清晰，让玩家在 2 人招募席中能做出有意义的选择，而非数值替代。**⚠️ 制作阻断标注**：本段区分依赖 `action_weight` 暂定值；若战斗解算 GDD 调整 `action_weight` 导致两者 power_score 等同，须同步修订本段以维持招募差异化的设计意图。

**5. 运行时实例（UnitInstance）**。战斗开始时由模板生成，引用模板 + 可变状态：`current_hp`（初始 = `max_hp`）、`grid_position: Vector2i`（格坐标；Downed 时设为 sentinel，sentinel 值由 grid-board-system GDD 定义）、`has_moved`、`has_acted`、`has_used_verb`、`is_alive`。字段清单归本系统；**变更规则归回合管理与战斗解算**（本系统不含任何改值逻辑）。

> **初始化规则（回合管理系统 GDD 同步锁定）**：无职业动词的单位（`class_action_id = null`）出生时令 `has_used_verb = true`；有职业动词的单位初始值为 `false`。`has_moved` 与 `has_acted` 一律初始为 `false`。

**6. 结构常量**（非调参，违反即 bug）：`MAX_CREW = 8`（反支柱锁定）、`CLASS_COUNT = 6`、`DEPLOY_LIMIT = 4`（单场上场数）、`STARTING_CREW = 2`（起航编制）。

> **DEPLOY_LIMIT=4 设计意图**：8 名船员每场上场 4 人，另 4 人留守——"上场哪 4 名船员"是 game-concept.md 明确列出的三大核心决策之一。留守不是弃置：它制造了每场前的情感裁决时刻（"今天让谁留下？"），这是实现"家人幻想"的关键场景。**情感机制的落地由 deployment-system GDD 负责**——本系统通过 `unit_id` 为其提供查询基础，不在 UnitInstance 中定义留守状态字段。deployment-system GDD 须将"留守状态"设计为有情感重量的状态，而非无差别的池外区域。

### States and Transitions

| 状态机 | 状态 | 转换 | 变更所有者 |
|--------|------|------|-----------|
| 行动状态 | 三独立 bool：`has_moved` / `has_acted` / `has_used_verb` | 每轮 `ROUND_START` 时全部重置为 `false`（无动词单位 `has_used_verb` 保持 `true`）；各 bool 在对应行动执行后由回合管理系统置 `true` | 回合管理系统 |
| 存活状态 | Alive → Downed | `current_hp ≤ 0` 时触发 | 战斗解算系统 |

模板本身无状态（静态数据，运行时只读）。**船员 Downed 后是 run 内永久死亡还是战后归队——未决**，归航线与招募 GDD 裁决（→ Open Questions，影响 `is_alive` 是否需要跨战斗持久化）。

> **跨系统字段契约**：Downed 状态由 `is_alive == false` 表达（`is_alive` 是 UnitInstance 的唯一存活标志，true=存活，false=Downed）。turn-management-system 和 battle-resolution-system 统一使用 `is_alive == false` 检测 Downed 状态；不另设 `is_downed` 字段。

### Interactions with Other Systems

| 下游系统 | 读取 | 写入/触发 | 接口所有者 |
|----------|------|----------|-----------|
| 战斗解算 | 基底数值、`class_action_id` | `current_hp` 变更 | 本系统定形状，解算定规则；**炮手职业差异**（行动经济：射程省去走位）须在战斗解算 GDD 中实现，否则炮手与剑豪仅靠移动力区分 |
| 相邻羁绊 | `unit_class`、`bond_tags`、`named_pair_overrides` | — | 查表优先级契约：专属 > 通用；bond_tags 字典序首个匹配规则由本系统声明 |
| 羁绊槽与爆发技 | 职业配对（组合技选择） | — | 配对→组合技映射归爆发 GDD |
| 敌人 AI 与意图系统 (#7) | `behavior_type`（枚举，已锁定）、`home_pos`（驻守型部署格）、`move_range`、`attack_range` | — | behavior_type 枚举定名已由 AI GDD #7 锁定（MELEE/RANGED/GUARDIAN/SWARMER）；OQ-3 关闭 |
| 网格棋盘 | `move_range`（BFS 输入） | `grid_position: Vector2i` | 棋盘 owns 位置合法性；Downed sentinel 值由棋盘 GDD 定义 |
| 航线与招募 | `recruit_pool_tier`、个性字段 | roster 增员（2→8） | 招募 GDD owns roster 规则 |
| 部署系统 | `unit_id`、`is_alive`、阵容数据 | 上场/留守决策 | `DEPLOY_LIMIT=4`、`MAX_CREW=8` 由本系统**声明**，由 deployment-system **执行**；留守情感机制（"今天让谁留下"）由 deployment-system 设计，本系统提供 `unit_id` 为其查询基础 |
| 悬赏成长 | `unlockable` 船员清单 | 解锁标记 | meta 进度归悬赏 GDD |
| 战斗 HUD / 爆发演出 | 显示字段（名字/称号/喊名/立绘） | — | 只读 |

玩家约束：玩家不能直接修改任何单位数值；阵容上限 8、上场上限 4 为硬约束。

## Formulas

> ✅ *systems-designer 复核于 2026-06-13，verdict: ENDORSE WITH CHANGES——本节已按其 4 项 bug 级修正（剑豪/炮手/医师伤害锁定、远程保护延伸至 tier 3）与 2 项文档级修正（action_weight 拆分、HP 权重依据）修订。*

### Formula 1：单位强度预算（power_score）

用途：保证六职业互有取舍、无严格上位——所有船员的 power_score 必须落在统一强度带内。

`power_score = max_hp × 0.5 + base_damage × 2 + attack_range × 1 + move_range × 1 + action_weight × 2`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 生命上限 | `max_hp` | int | 4–12 | **HP 权重 0.5 是有意为之**：预算口径优先进攻产出，生存性由站位与回合经济解决，非裸 HP 堆叠（roguelite 减员代价语境） |
| 基础伤害 | `base_damage` | int | 0–4 | 每回合直接影响，权重最高 ×2。已知盲区：线性系数表达不了"一击斩杀阈值"的非线性价值（归战斗解算 GDD 关注） |
| 攻击射程 | `attack_range` | int | 1–4 | 曼哈顿距离。**系数 1 可能低估射程真实价值**（射程 3 覆盖 24 格、省去走位回合）——修远程身份靠伤害下限，别靠调这个系数 |
| 移动力 | `move_range` | int | 1–4 | 每回合格数；5–8 回合战斗中价值在 3 左右饱和 |
| 动词权重 | `action_weight` | float | 0–2（步进 0.5） | 无=0；守护=1；**光环=1.5**（W=2 高估了 4 人上场棋盘上的聚集代价）；治疗/位移=2——标定随战斗解算 GDD 定稿（provisional） |

**Output Range:** 理论 4–26；**船员强度带 = 13–16**（带外即平衡告警）；敌人带见 Formula 2
**Example（阿斩，原型实测剑豪）:** `10×0.5 + 3×2 + 1×1 + 3×1 + 0×2 = 5+6+1+3 = 15` ✓ 带内

### 六职业数值倾向带（systems-designer 复核后修订）

| 职业 | HP | 伤害 | 射程 | 移动 | W | 中点分 |
|------|----|------|------|------|---|--------|
| 剑豪 | 9–11 | **3（锁定）** | 1 | 3 | 0 | 15.0 |
| 炮手 | 6–8 | **3（锁定）** | 3–4 | 1–2 | 0 | 14.5 |
| 铁壁 | **12（锁定）** | 1–2 | 1 | 2 | 1 | 14.0 |
| 医师 | **8–9** | **1（锁定）** | 1–2 | 2–3 | 2 | 14.25 |
| 航海士 | 7–9 | 1–2 | 1–2 | 2–3 | 2 | 15.0 |
| 乐手 | 6–8 | **2（锁定）** | 1–2 | 2–3 | **1.5** | 14.0 |

修订依据（systems-designer 边界代入）：剑豪 dmg=4 全组合 ≥ 16.5 出带 → 锁 3；炮手 dmg=2 最差 11.0 且破坏两发击杀保证 → 锁 3（原型实测 12.5 的"远程存在感弱"课题就此闭环）；医师 dmg=0 全组合 ≤ 12.5 → 锁 1 并提 HP 下限至 8；乐手 dmg=1 最低组合（HP=6/dmg=1/range=1/move=2）= 11.0 系统性出带 → 锁 2；铁壁 HP=11/dmg=1 = 12.5 出带 → HP 锁 12。

**逐项带 ≠ 入带保证**：职业带是逐项必要条件，非充分条件——极端组合（如航海士 9/2/2/3/W2 = 17.5）仍可能出带，**单位级 power_score 13–16 检查才是约束本体**（Edge Cases 平衡告警捕获）。

> **航海士已知例外**：航海士的位移控制价值无法被 power_score 线性表达，其按当前字段范围合法计算的 power_score 区间为 [12.5, 17.5]——超出通用带 [13, 16] 是设计预期，而非平衡警告信号。调参航海士时以 [12.5, 17.5] 为参考范围；加载时产生的平衡警告对此职业属正常噪声，不代表配置错误。**此区间在当前 `action_weight=2`（暂定）时成立**；若 `action_weight` 定稿值变更，须重算航海士 power_score 区间。

**已知公式局限**（不阻断，交下游处理）：公式层面航海士在共享取值区间内严格压制医师（治疗防死的真实价值无法线性表达）——这是预算口径的盲区而非设计意图，医师的治疗效力须在战斗解算 GDD 中以独立指标校验。`attack_range` 在公式中以线性系数计入，但 attack_range=1 使用切比雪夫（8 格覆盖）而 attack_range≥2 使用曼哈顿（覆盖格数不成比例递增）——公式低估了近战与远程射程的覆盖面差异，不影响 power_score 作为预算口径的用途，但不可用于精确比较不同射程的战术价值。

### Formula 2：敌人威胁层级预算（threat_tier）

`enemy_power_band(tier) = 10 + 2 × (tier − 1)，容差 ±1`

| Tier | 强度带 | 验证 |
|------|--------|------|
| 1 | 9–11 | 原型基础敌（HP6/伤2/移2/射1 = 10）✓ |
| 2 | 11–13 | |
| 3（头目护卫层） | 13–15 | **与船员带 13–16 有 3 分重叠——tier-3 敌就是船员级威胁，这是有意的终局压力，不是"接近下沿"的软化表述** |

**远程身份保护约束**（原型课题的硬规则，复核后延伸至 tier 3）：

- `tier ≤ 2` 的敌人 `move_range ≤ 2`
- `move_range = 3` 的快速敌人仅限 tier 2+ 且 `max_hp ≤ 6`
- **tier 3 的 `move_range = 3` 敌人须同时满足 `max_hp ≤ 8` 且 `attack_range ≤ 1`**（否则合法的 13 分快速敌——如 8/2/2/3——两回合贴脸，炮手窗口在最需要的中后期蒸发）

**两发击杀保证的适用范围**（显式声明）：快速敌 `max_hp ≤ 6` 配炮手伤害下限 3 → ceil(6/3) = 2 发成立。炮手伤害锁定 3 是此保证的前提——这正是把伤害下限从"修复建议"升级为"类定义硬约束"的原因。

**Boundary check:** 最小单位（4/0/1/1/0）= 4，最大（12/4/4/4/2）= 26，无零除/负值/发散；`action_weight` 引入 0.5 步进后输出为 0.5 的整数倍，仍确定性。已知依赖：`action_weight` 的标定在战斗解算 GDD 定稿前为暂定值（已标 provisional）。

## Edge Cases

**校验策略总则**：加载时全量校验，分两级——**结构错误**（违反即 bug）立即终止加载并打印明细（文件路径 + 字段 + 期望值）；**平衡告警**（数值合法但带外）打印警告后照常运行。下游 8 个系统据此可假设：**运行时拿到的单位数据永远结构合法**，无需各自写防御代码。

### 结构错误（加载即终止）

- **If `base_damage` < 0**：加载终止（负伤害无实际含义）。`base_damage = 0` 结构上合法（纯辅助型敌人预留）；负值是配置事故。

- **If 两条单位定义使用相同 `id`**：加载终止，报错列出两个冲突资源的路径。

> **`unit_id` 跨系统说明**：本系统的 `id` 是字符串蛇形命名（如 `crew_azhan`）。回合管理系统在战斗内为每个 UnitInstance 分配临时数值型 `battle_id`（断言 `unit_id < 1000`）用于先攻排序与去重——该字段归回合管理系统所有，不写入本系统的模板。两套标识符共存：字符串 `id` 是跨系统的持久身份，数值 `battle_id` 是单场战斗的运行时句柄。
- **If `unit_class` 不在六职业枚举内**：加载终止。新增职业必须先修改 `CLASS_COUNT` 与本 GDD 的职业表（结构常量变更 = 设计变更，不是数据热改）。
- **If `class_action_id` 在行为表中无对应条目**：加载终止（悬空引用）。
- **If `named_pair_overrides.partner_id` 引用不存在的船员 id，或引用了敌人 id**：加载终止。专属配对仅限船员↔船员。
- **If 同一对船员的配对覆盖在双方定义中都出现**：加载终止（歧义）。配对覆盖按**无向对**解释，A↔B 只允许在一侧定义——此规则同时写入相邻羁绊 GDD 的查表契约。
- **If `threat_tier` < 1 或 > 当前定义的最大层级**（MVP 为 3，上限归航线与招募 GDD）：加载终止。
- **If `faction = crew` 但缺失船员扩展字段，或 `faction = enemy` 却携带船员扩展字段**：加载终止（阵营与扩展形状必须匹配）。
- **If `recruit_pool_tier = starting` 的船员总数 ≠ `STARTING_CREW`（2）**：加载终止。起航编制是结构常量，多一个少一个都是配置事故。**校验实现**：加载器统计所有 `faction=crew` 且 `recruit_pool_tier=starting` 的记录数，与 `STARTING_CREW=2` 比对——`recruit_pool_tier` 是起航编制的唯一标记字段，无需额外 `is_starting` 布尔。
- **If `max_hp` ≤ 0、`move_range` ≤ 0 或 `attack_range` ≤ 0**：加载终止（不可行动单位）。注意 `base_damage = 0` **结构上合法**（预留纯辅助型敌人），但当前六职业带最低为 1（医师锁定，见 Formulas 修订）。
- **If 船员的 `bond_tags` 为空数组**：加载终止——无羁绊标签的船员违反"羁绊即战术"支柱。敌人的 `bond_tags` 允许为空（敌人不参与羁绊，相邻羁绊系统忽略敌方标签）。

### 平衡告警（不阻断）

- **If 船员 `power_score` 落在 13–16 带外，或敌人偏离 `enemy_power_band(tier)` 容差**：控制台警告（如"炮手 12.5 < 带下限 13"），游戏照常运行——调参试验本来就会出带。**已知临时状态**：`action_weight` 定稿前，含 W 项的职业（医师/航海士/乐手/铁壁）的 power_score 计算为暂定值，此期间产生的带外警告不具备最终调参参考意义——应在战斗解算 GDD 定稿并锁定 `action_weight` 后重新校验。
- **If 任一字段超出 Formulas 节定义的范围**（如 `max_hp` = 20 > 12）：同上，仅警告。

### 运行时边界

- **If 招募发生时 roster 已满 `MAX_CREW`（8）**：数据层的增员操作返回失败——任何使 roster > 8 的写入都是 bug。招募系统必须在 UI 层预先隐藏招募选项（具体呈现归航线与招募 GDD）。
- **If 可上场船员少于 `DEPLOY_LIMIT`（4）**：上场全部存活船员——2 人起航的首战就是 2 人上场，这是正常路径而非异常。可上场为 0 的战斗不允许发生（航线系统须保证；若 run 内全员不可用即判负，规则归航线 GDD）。
- **If 单位 `current_hp` 降至 ≤ 0**：钳制为 0，`is_alive = false`，单位**立即移出棋盘、格子变空**（与原型一致）——不可选中、不提供相邻羁绊、不阻挡移动。触发与时序归战斗解算 GDD。**`current_hp` 下界为 0，不允许为负**（钳制由战斗解算执行，不变量由本系统声明：任何时刻 0 ≤ current_hp ≤ max_hp）。
- **If 治疗使 `current_hp` 超过 `max_hp`**：钳制为 `max_hp`。不变量：任何时刻 `0 ≤ current_hp ≤ max_hp`（钳制执行归战斗解算，不变量声明归本系统）。
- **If 船员 Downed 后跨战斗的数据归属**：未决（run 内永久死亡 vs 战后归队），归航线与招募 GDD 裁决 → Open Questions。在裁决前，本系统不定义 `is_alive` 的跨战斗持久化。

## Dependencies

### 上游依赖（本系统依赖谁）

**无。** 本系统是 Foundation 层的事实源，不依赖任何其他游戏系统——这是架构硬约束：单位数据若反向依赖任何下游系统即构成循环，违反即架构事故。

唯一的外部依赖是**架构层决策**（非游戏系统）：数据文件格式（自定义 Resource `.tres` vs JSON）与加载管线归 `/architecture-decision` 裁决（→ ADR 待立项）。本文档定义的是数据**形状**，与载体格式无关。

### 下游依赖（谁依赖本系统）

8 个系统消费本系统的数据（接口明细见 Detailed Design 的交互契约表）：

| 下游系统 | GDD 状态 | 契约状态 |
|----------|---------|---------|
| 战斗解算系统 | 未设计 | 暂定（provisional）——`class_action_id` 行为表、`action_weight` 标定、HP 钳制规则待其 GDD 定稿 |
| 相邻羁绊系统 | 未设计 | 暂定——`bond_tags` 查表、专属配对优先级与无向对规则已在本文档预写为契约 |
| 羁绊槽与爆发技系统 | 未设计 | 暂定——职业配对 → 组合技映射归其 GDD |
| 敌人 AI 与意图系统 | 未设计 | 暂定——`behavior_archetype` 枚举定名、`intent_data` 形状归其 GDD |
| 网格棋盘系统 | 未设计 | 暂定——`move_range` 为 BFS 输入、`grid_position` 合法性归棋盘 |
| 航线与招募系统 | 未设计 | 暂定——`recruit_pool_tier` 消费、roster 规则、**船员死亡永久性裁决权在它** |
| 悬赏成长系统 | 未设计 | 暂定——`unlockable` 清单消费 |
| 战斗 HUD / 爆发演出 | 未设计 | 暂定——只读显示字段 |

**双向引用义务**：上述每个系统的 GDD 撰写时**必须**在其 Dependencies 节回指本文档，并确认（或质疑）本文档预写的契约。任何契约变更须同步修订双方文档——本系统是全局瓶颈（系统索引高风险表第 4 项），schema 变更的波及面是全部 8 个消费者。

**对下游的保证**：基于 Edge Cases 的 fail-fast 策略，下游系统可假设运行时单位数据永远结构合法，无需防御性校验。

**加载接口契约**：本系统对外暴露一个加载函数，签名约定为 `load_all_units() -> Array[UnitDefinition]`——成功时返回全量定义数组，任何结构错误时返回空数组并调用 `push_error()`。下游系统必须在消费前检查返回数组是否为空；空数组意味着数据层不可用，下游须拒绝进入战斗。**错误消息格式区分两类错误**：文件解析错误格式为 `"UnitData parse error: [path] — [detail]"`（含文件路径）；数据校验错误格式为 `"UnitData validation error: [unit_id] — [field] — [detail]"`（含单位 id）——调用方通过消息内容区分错误类型。**错误处理顺序**：parse error 立即终止当前文件解析；validation error 收集至全部单位处理完毕后统一 push_error——两类错误在同一次 load 中可共存，日志将按文件路径先、单位 id 后的顺序输出。

**日志级别约定**：本系统使用两级日志——`push_error()` 用于结构错误（加载终止前输出），`push_warning()` 用于平衡告警（加载继续）。调用方不应对 `push_warning()` 抛出的条目做任何逻辑响应，仅供开发者调参时可见。

**制作阻断条件（`action_weight` 暂定）**：`action_weight` 标定须在战斗解算 GDD 定稿后方可最终化。期间所有引用 `action_weight` 的 power_score 计算均为暂定值，任何平衡验算须标注"以暂定 W 值计算"。战斗解算 GDD 定稿前，本系统不冻结含 `action_weight` 的职业数值带。

**resolve_unit_downed 封装声明**：本系统定义 Downed 的数据状态（`current_hp ≤ 0` → `is_alive = false`），但触发时序与业务逻辑（移出棋盘、通知回合管理）封装在战斗解算系统的 `resolve_unit_downed()` 函数内——本系统不调用该函数，也不定义其执行时机。

## Tuning Knobs

### 可调旋钮

| 旋钮 | 默认/基线 | 安全范围 | 影响的玩法面向 |
|------|----------|---------|---------------|
| 单位个体数值（`max_hp` / `base_damage` / `attack_range` / `move_range`，逐单位） | 各职业带中点 | 所属职业的数值倾向带（见 Detailed Design 职业表） | 职业剪影与单卡平衡——出带触发平衡告警但不阻断 |
| 船员强度带上下限 | [13, 16] | 下限 12–14，上限 15–18 | 全队强度预算的松紧；带宽收窄 = 职业更同质，放宽 = 更允许极端特化 |
| `power_score` 各项权重 | hp 0.5 / 伤害 2 / 射程 1 / 移动 1 / 动词 2 | **高危旋钮**——任何改动都重新定义"强度"本身，全部已标定单位须重新验算 | 强度评估的口径；非平衡迭代期不应触碰 |
| `action_weight` 标定 | 守护 1 / 光环 1.5 / 治疗与位移 2（provisional） | 0–2，步进 0.5 | 非攻击动词在预算中的计价；随战斗解算 GDD 定稿 |
| `enemy_power_band` 基准 / 步进 / 容差 | 10 / 2 / ±1 | 基准 9–11，步进 1–3，容差 ±1–2 | 难度曲线的起点与斜率；步进加大 = 后期岛屿压力陡增 |
| `threat_tier` 最大层级 | 3（MVP） | 3–5 | 航线难度档位数；上调须同步航线与招募 GDD |
| `bond_tags` 追加标签 | 默认仅 `[unit_class]` | 每单位 ≤ 3 个标签（≤3 是内容可行性约束：标签数超过 3 时，相邻羁绊 GDD 须同步提供至少 6–10 条新效果定义——MVP 阶段创作成本不允许超额） | 羁绊矩阵的扩展位——**每个新标签 = 矩阵新行**，必须有相邻羁绊 GDD 配套效果，否则是死数据 |
| `recruit_pool_tier` 分配 | starting 2 / 其余 pool | starting 恒为 2（结构常量）；pool/unlockable 配比自由 | 招募节奏与 meta 解锁曲线（消费规则归航线与悬赏 GDD，数据归本系统） |

### 不是旋钮的东西

`MAX_CREW = 8`、`CLASS_COUNT = 6`、`DEPLOY_LIMIT = 4`、`STARTING_CREW = 2` 是**结构常量**——改动它们是设计变更（须修订本 GDD 与概念书并重走评审），不是调参。把它们当旋钮拧是本系统明令禁止的第一件事。

**调参操作约定**：所有旋钮都活在数据文件里（编码标准：数值外置），改动无需碰代码；出带改动会被加载告警捕获，作为"我正在试验"的显式信号而非错误。

## Visual/Audio Requirements

本系统是纯数据层，**无直接视听需求**。它的视听职责是承载资产引用字段并保证其完整性：

- `portrait_id`（立绘）与 `model_id`（低模）——消费归战斗 HUD 与航线/招募 UI；引用悬空按 Edge Cases 结构错误处理（fail-fast）
- `battle_cry`（必杀喊名文本）——爆发演出系统的分镜引用素材
- 占位资产规范（色块/调试形状阶段的命名约定）归各消费系统与资产管线，不归本文档

## UI Requirements

本系统**无直接 UI**。显示字段（`display_name` / `title` / `persona_line` / `battle_cry` / 立绘引用）由战斗 HUD、航线与招募 UI、爆发演出只读消费——具体版式归各自 GDD。

本文档施加的唯一 UI 约束：**`power_score` 是开发期平衡指标，不向玩家展示**。玩家看到的是具体数值（HP/伤害/射程/移动）与个性字段，不是预算分——把预算口径暴露给玩家会把"伙伴"还原成"棋子"，违反 Player Fantasy。

## Acceptance Criteria

> 由 qa-lead 子代理评审起草（2026-06-13），主会话按本文档已锁规则修订。每条均可由单元测试或 QA 人工独立验证。

**单元测试约定**：所有加载校验 AC 均以数据层单元测试语言描述——"调用 `load_all_units()`"、"返回空数组（`== []`）"、"`push_error()` 被调用"均为可在 GUT 框架中直接断言的行为。"加载终止"表达的是同一语义：函数返回空数组并调用 `push_error()`，不涉及应用生命周期。

**加载校验（fail-fast）**

- **AC-1 重复 id 阻断加载**：Given 数据中存在两条 `id` 相同的单位定义，When 调用 `load_all_units()`，Then 返回空数组（`== []`），且 `push_error()` 被调用，消息包含冲突 `id` 与两个资源路径。
- **AC-2 非法职业枚举阻断加载**：Given 某单位的 `unit_class` 不在六职业枚举内，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含违规单位 `id` 与未识别的 `unit_class` 值。
- **AC-3a class_action_id 悬空阻断加载**：Given 某单位的 `class_action_id` 为非 null 值且在行为表中无对应条目，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含违规 id 与悬空的 `class_action_id` 值（`null` 豁免此校验，见 AC-19）。
- **AC-3b partner_id 不存在阻断加载**：Given 某船员的 `named_pair_overrides.partner_id` 引用不存在的 id，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含违规船员 id 与不存在的 `partner_id`。
- **AC-3c partner_id 为敌人阻断加载**：Given 某船员的 `named_pair_overrides.partner_id` 引用敌人 id，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含违规船员 id、`partner_id` 及其 `faction = enemy`（专属配对仅限船员↔船员）。
- **AC-4 起航编制校验**：Given `recruit_pool_tier = starting` 的船员总数 ≠ 2，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含实际数量与期望值 `STARTING_CREW = 2`。
- **AC-13 无向对歧义阻断加载**：Given 同一对船员的 `named_pair_overrides` 在 A 和 B 双方均出现（包括 A 仅声明 `partner_id=B`、B 也仅声明 `partner_id=A` 的对称情况——双边任意形式均视为歧义），When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含歧义配对的两个单位 id。（无向对规则要求配对覆盖仅在一方定义，对称声明不是合法冗余。）
- **AC-14 空 bond_tags 阻断船员加载**：Given 某船员的 `bond_tags` 为空数组，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含违规船员 id（敌人允许为空，不触发此规则）。
- **AC-15 threat_tier 越界阻断加载**：Given 某敌人的 `threat_tier` < 1 或 > 3（MVP 最大层级），When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含违规 id 与越界值。（注：航线 GDD 扩展 tier 时须同步修订本 AC 的上限值 3。）
- **AC-16 faction 与扩展形状一致性**：Given `faction = crew` 的单位缺失船员扩展字段，或 `faction = enemy` 的单位携带船员扩展字段，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含阵营与扩展类型的不匹配信息。
- **AC-17 正数字段约束**：Given 某单位的 `max_hp`、`move_range` 或 `attack_range` ≤ 0，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含违规字段与实际值（`base_damage = 0` 结构上合法，不触发此规则）。
- **AC-18 bond_tags 超上限阻断加载**：Given 某船员的 `bond_tags` 数组长度 > 3，When 调用 `load_all_units()`，Then 返回空数组，且 `push_error()` 消息包含违规船员 id 与实际 tag 数量。

**平衡告警（不阻断）**

- **AC-5 带外强度仅告警**：Given 某船员的 `power_score` 计算值落在 13–16 之外，When 调用 `load_all_units()`，Then 返回非空数组（加载成功），且 `push_warning()` 被调用，消息包含该船员 `id` 与计算值。边界验证：Given `power_score = 12`，Then 触发；Given `power_score = 12.5`（非整数带外），Then 触发；Given `power_score = 13` 或 `= 16`，Then 不触发（边界值在带内）；Given `power_score = 17`，Then 触发。（注：action_weight 定稿前，含 W 项的职业 power_score 为暂定值，此告警在战斗解算 GDD 定稿前不具备最终参考意义。）

**数据驱动**

- **AC-6 改数据不改代码**：Given 在数据文件中将某单位的 `max_hp` 从 8 改为 11，When 调用 `load_all_units()` 并生成该单位的 UnitInstance，Then 实例的 `max_hp = 11` 且 `current_hp = 11`（初始值）——无需重新编译 `.gd` 脚本，热重载或重新调用同一函数即可验证数据驱动特性。
- **AC-7 power_score 从数据实算**：Given 两条仅 `base_damage` 不同的单位定义（A：`max_hp=8, base_damage=2, attack_range=1, move_range=2, action_weight=0` → 期望 11.0；B：同参数但 `base_damage=3` → 期望 13.0），When 加载后读取两者的 `power_score`，Then A.power_score == 11.0，B.power_score == 13.0（公式定义见 Formulas 节 Formula 1；公式对活数据求值，非存储常量）。
- **AC-19 null class_action_id 合法并正确初始化**：Given 某单位的 `class_action_id = null`，When 调用 `load_all_units()` 并生成该单位的 UnitInstance，Then 加载成功（返回非空数组，`push_error()` 不调用），且实例的 `has_used_verb = true`（无职业动词单位视为已使用动词行动）。

**结构常量**

- **AC-8 roster 硬上限（声明性约束）**：`MAX_CREW = 8` 是本系统定义的结构常量；本系统的 `load_all_units()` 加载全量单位定义，不校验当前 roster 人数——roster 增员上限由 deployment-system/roster-management-system 强制执行。本 AC 声明约束值，实现与测试归增员 API 拥有者的系统。
- **AC-9a 上场上限（声明性约束）**：`DEPLOY_LIMIT = 4` 是本系统定义的结构常量；上场确认与阻止逻辑归 deployment-system GDD。本 AC 声明约束值，执行与测试归 deployment-system。
- **AC-9b 不足额上场**：Given 存活船员仅 2 人（起航期），When 进入战斗，Then 2 人全部上场且战斗正常开始（不足额是正常路径，不触发错误）。
- **AC-10 枚举基数一致性**：Given 职业枚举定义于源码，When 断言枚举成员数 == `CLASS_COUNT`，Then 单元测试通过（当前值 = 6）。（注：职业枚举扩展时须同步更新 `CLASS_COUNT` 与本 AC 验证值。）

**运行时不变量**

- **AC-11a HP 下限钳制**：Given 实例 `current_hp = 1, max_hp = 10`，When 受到 999 伤害，Then `current_hp == 0`（钳制为 0，永不为负），不变量 `0 ≤ current_hp` 成立。
- **AC-11b HP 上限钳制**：Given 实例 `current_hp = 5, max_hp = 10`，When 接受 999 治疗，Then `current_hp == 10`（钳制为 max_hp，永不超出），不变量 `current_hp ≤ max_hp` 成立。
- **AC-12 Downed 数据状态**：Given 某单位 `current_hp` 降至 0，When 战斗解算处理完该次伤害，Then 该单位 `is_alive = false`、`grid_position` 设为 sentinel 值（sentinel 由 grid-board-system GDD 定义，暂定 `Vector2i(-1, -1)`；本 AC 依赖 grid-board-system GDD 先行稳定后方可写出完整断言）、不再被相邻羁绊查询计入——此断言仅验证 UnitInstance 数据状态；棋盘格子空闲状态的断言归 grid-board-system 的 AC。

## Open Questions

| # | 问题 | 裁决归属 | 对本系统的影响 |
|---|------|---------|---------------|
| 1 | **🚨 设计分叉（垂直切片前必须解决）：船员 Downed 永久性** — 永久死亡（家人幻想需真实情感代价支撑）vs 战后归队（十分钟爽局支柱优先）。当前无设计意向声明，此问题关乎本 GDD Player Fantasy 的情感承诺。暂定：**垂直切片情感测试后以玩家反馈为准**。 | 航线与招募 GDD（规则）+ 垂直切片情感测试（数据） | 影响 `is_alive` 跨战斗持久化；影响 `persona_line`/`battle_cry` 等个性字段的情感重量（永久死亡时重量高，归队时重量弱） |
| 2 | `action_weight` 标定定稿（守护 1 / 光环 1.5 / 治疗位移 2 均为暂定） | 战斗解算 GDD | 标定变更须重算全部船员 power_score |
| 3 | ~~`behavior_archetype` 枚举定名与 `intent_data` 形状~~ **已关闭（2026-06-16）**：`behavior_type` 枚举 = MELEE/RANGED/GUARDIAN/SWARMER；`home_pos: Vector2i`（驻守型专用）；敌人 AI GDD #7 已锁定，本系统字段已更新 | 敌人 AI 与意图 GDD（已 Done） | EnemyDefinition 表已回填 `behavior_type` 与 `home_pos` |
| 4 | 数据载体格式：自定义 Resource `.tres` vs JSON | /architecture-decision（ADR 待立项） | 不影响数据形状，影响加载校验的实现位置 |
| 5 | `named_pair_overrides` 的内容填充策略（MVP 留空——哪些船员配对值得专属效果、做多少对） | 相邻羁绊 GDD（机制）+ 内容设计 | 字段与查表优先级已锁，填充是内容工作 |
| 6 | 医师治疗效力的独立校验指标（power_score 公式无法表达，systems-designer 标记的公式局限） | 战斗解算 GDD | 在独立指标出来前，医师调参不得仅凭 power_score 判断强弱 |
| 7 | **受击充能与医师治疗的张力**：若充能槽依赖受击事件，医师的治疗（减少受击伤害）会压低己方充能速率——是否需要设计补偿机制（如"治疗触发少量充能"）？ | 羁绊槽与爆发技 GDD | 影响 `class_action_id` 的效果设计与 power_score 中 `action_weight=2` 对医师的定价 |
| 8 | **减益状态字段（如 `move_range` 归零场景）**：若战斗中存在"本轮移动力归零"等减益效果，是否需要在 UnitInstance 追加独立的 `debuff` 字段，还是由执行方直接修改 `move_range`？后者会污染模板语义——此规则须在战斗解算或相邻羁绊 GDD 定稿前决定。 | 战斗解算 GDD / 相邻羁绊 GDD | 若需 debuff 字段，本系统须追加字段定义；若允许直接改值，须声明"UnitInstance 字段在战斗中可被修改"的语义 |
| 9 | **`persona_line` 是否在战斗 HUD 中展示**（如选中船员时显示个性台词）？若是，则本字段也被战斗 HUD 系统消费，需在 HUD GDD 中明确版式。 | 战斗 HUD GDD | 影响 `persona_line` 字段的消费方列表与"家人幻想"的战斗内情感密度 |
