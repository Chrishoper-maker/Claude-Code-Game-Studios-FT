# 装备地基重构：9 槽 + 5 稀有度（子项目②a）设计

> Story: equipment-slots-rarity-foundation（多地图/遭遇 epic 装备线 子项目②a）
> 日期：2026-06-25
> 引擎：Godot 4.6.3 / GDScript / GdUnit4
> 前置：装备系统 MVP（`2026-06-22-equipment-design.md`，一人一件）
> 后续：②b 套装效果系统、②c 风险回报战利品经济（顺序 ②a→②c→②b）
> 取代：`2026-06-25-risk-reward-loot-economy-design.md`（3 级稀有度 + 一人一件的旧 ② 方案，已 superseded）

## 1. 概述（Overview）

把现有「一人一件、替换即弃」的装备 MVP 升级为 **9 固定槽 + 5 级稀有度**的装备地基。本子项目只铺**数据模型 + 有效值累加 + 招募/战斗/存档适配**，是后续套装效果（②b）与选航战利品经济（②c）的共同前提。**不含**套装效果、不含选航战利品经济、不含装备 UI 美术、不含职业限装。

## 2. 玩家体验（Player Fantasy）

身为船长，麾下每名船员都有一整套可逐步武装的装具——主武器、护甲、首饰各就其位。装备分白/蓝/紫/橙/红五级品阶，越稀有越强。本子项目让「多槽 + 品阶」的骨架立起来；收集与套装的乐趣由后续子项目铺陈。

## 3. 详细规则（Detailed Rules）

### 3.1 装备槽（9 固定槽）
- 枚举 `EquipSlot`（int）：`MAIN_WEAPON 主武器 / OFF_WEAPON 副武器 / HEAD 头 / ARMOR 护甲 / GLOVES 护手 / LEGS 绑腿 / BOOTS 靴子 / RING 戒指 / NECKLACE 项链`，共 9。
- 每件装备归属**恰好一个槽**（`EquipmentDefinition.slot`）。
- 每名船员每槽最多装一件；可同时装满 9 槽。
- 装备**职业无关**：任何船员可装任何槽的任何装备（沿用现有纯数值、class-agnostic 模型）。见 §7 可调旋钮。

### 3.2 稀有度（5 级 + 颜色）
- 枚举 `Rarity`（int）：`0 COMMON 普通(白) / 1 RARE 稀有(蓝) / 2 EPIC 史诗(紫) / 3 ANCIENT 稀世(橙) / 4 LEGENDARY 传奇(红)`。
- 颜色用于 UI 品阶标识；白盒阶段用中文标签/文字色即可，不依赖美术资源。

### 3.3 装备数据（31 种，按稀有度 10/8/5/5/3）
- `EquipmentDefinition` 新增字段：
  - `rarity: int`（Rarity）
  - `slot: int`（EquipSlot）
  - `set_id: String`（**②a 留空占位**，②b 填套装归属——预置字段避免二次改全部数据文件）
- 现有 4 件并入并标 `rarity=0`、归槽：弯刀→主武器、板甲→护甲、望远镜→戒指、轻靴→靴子。
- 共造 **31 种**：普通 10 / 稀有 8 / 史诗 5 / 稀世 5 / 传奇 3，分布到 9 槽。
  - 增量随稀有度递增；高稀有度多为复合多属性。
  - **分布原则**：普通铺满 9 槽的多数；高稀有度件数 < 9，故只覆盖部分槽（传奇 3 件 → 仅 3 个槽存在传奇）。具体归属与数值为**实现计划期内容**，本 spec 给目标分布 + 示例，不在此逐条枚举 31 条数据。
  - 示例（非最终）：普通——弯刀(主武器,+1攻)/板甲(护甲,+3血)/望远镜(戒指,+1射程)/轻靴(靴子,+1移动)…；传奇——屠龙(主武器,+4攻)/海神护符(项链,+6血+1射程)/疾风绑腿(绑腿,+2移动+2血)。
- `EquipmentDataManager` 支持按 `rarity` 过滤、按 `slot` 过滤的查询接口。

### 3.4 UnitInstance 多槽有效值累加
- 字段 `equipment: EquipmentDefinition` → `equipment: Dictionary`（`slot(int) → EquipmentDefinition`），最多 9 项。
- 4 个访问器 `get_max_hp / get_base_damage / get_attack_range / get_move_range`：返回 `maxi(0, 基值 + 所有已装槽对应增量之和)`。空槽不计入。
- `from_definition(def, equipment)`：`equipment` 参数改为 `Dictionary`（slot→def），默认空 `{}`。敌方/起始船员恒空。
- `current_hp` 初始仍 = `get_max_hp()`（含全部已装槽）。

### 3.5 招募获取：滚 8 选 2（加权稀有度）
- **每次招募某船员后**，为其滚出 **8 件**装备候选，玩家从中**选 2 件**装上。
- **8 件的稀有度按权重抽**（每件独立）：

  | 稀有度 | 权重 |
  |---|---|
  | 传奇(红) | 2% |
  | 稀世(橙) | 8% |
  | 史诗(紫) | 15% |
  | 稀有(蓝) | 25% |
  | 普通(白) | 50% |

  先按权重定稀有度，再从该稀有度子池**等概率**抽一件（有放回）；该稀有度子池为空时降级到相邻较低稀有度。
- 抽样全程走 RunManager 持有的 `_rng`（确定性，存档 `rng_state` 复现）。
- 玩家选 2 件 → 各按其 `slot` 装入该船员对应槽。**两件须为不同槽**（UI 禁止选第二件落入已占槽）；其余槽空。
- 起始船员仍无装备（全槽空），不走滚 8 选 2。
- 招募候选**船员卡不再各自携带装备**（与装备 MVP 不同）——装备改由本步骤独立滚出、玩家选 2。

### 3.6 RunManager 账本
- `_roster_equipment: Dictionary`：`crew_id → { slot(int): equipment_id }`（由单 id 升级为按槽字典）。
- `get_equipment_for(crew_id) -> Dictionary`：返回该船员的 `{ slot(int): EquipmentDefinition }`（部署构 UnitInstance 多槽）；无装备返回空 `{}`。
- `confirm_recruit`：把滚到的普通装备按 slot 记入新船员槽字典。
- permadeath：擦除该 crew_id 整份槽账本（语义不变）。

### 3.7 战斗接入
- 部署处（BattleScene/BattleMap）把 `get_equipment_for(crew_id)` 的槽字典传入 `from_definition`。
- 其余战斗代码已统一走 `get_*()` 访问器（装备 MVP 已改 ~19 处），无需再动。

## 4. 公式 / 数据结构（Formulas / Data）

- 有效值：`effective = maxi(0, base + Σ_slot(equipped[slot].<bonus>))`，bonus ∈ {hp_bonus, damage_bonus, range_bonus, move_bonus}。
- `EquipmentDefinition`：`id, display_name, hp_bonus, damage_bonus, range_bonus, move_bonus`（现有）+ `rarity:int, slot:int, set_id:String`（新增）。
- `EquipSlot`：9 值枚举（§3.1）。`Rarity`：5 值枚举（§3.2）。
- RunManager `_roster_equipment`：`{ crew_id: String → { slot: int → equipment_id: String } }`。
- 稀有度件数目标：`{0:10, 1:8, 2:5, 3:5, 4:3}`，合计 31。
- 招募滚装稀有度权重：`{传奇:2, 稀世:8, 史诗:15, 稀有:25, 普通:50}`（百分比，合计 100）。每次招募滚 8 件、玩家选 2 件（不同槽）。

## 5. 边界情况（Edge Cases）

- **某槽无装**：访问器跳过该槽，不计增量。
- **高稀有度不覆盖全槽**：合法——某些槽无传奇/稀世装备。
- **招募滚装稀有度子池为空**：按权重选中的稀有度若无任何装备，降级到相邻较低稀有度抽取（保证 8 件都滚得出）。
- **选的 2 件同槽**：UI 禁止选中落入已占槽的第二件；玩家只能选 2 个不同槽的件。
- **8 件含重复（有放回滚出同一 id）**：允许；玩家仍按槽选 2 件（同 id 必同槽，受不同槽规则约束）。
- **旧档迁移**：旧 `roster_equipment` 为 `crew_id → equipment_id`（单 id）；读时查该装备 `slot`，放进新结构 `{slot: id}`；装备定义缺失则跳过该件。
- **装备定义缺失**：还原时双过滤（roster 成员 + 定义存在）；缺失件不还原、不崩。
- **同槽重复（数据错误）**：每槽字典键唯一，后写覆盖；数据校验保证一件一槽。
- **职业无关装备**：任何船员任何装备合法，无禁装路径（②a 范围）。

## 6. 依赖（Dependencies）

- `EquipmentDefinition`（加 rarity/slot/set_id）/ `EquipmentDataManager`（加 rarity、slot 过滤查询）。
- `UnitInstance`（单件 → 多槽字典 + 访问器求和）。
- `RunManager`（`_roster_equipment` 升级为槽字典、`get_equipment_for`、`confirm_recruit`、permadeath、存档）。
- `BattleScene`/`BattleMap`（部署传槽字典）。
- 装备 MVP（`2026-06-22-equipment-design.md`）现有访问器接入点。

## 7. 可调旋钮（Tuning Knobs）

- 每稀有度件数分布（默认 10/8/5/5/3）。
- 各装备的 slot 归属与增量数值。
- 招募滚装稀有度权重（默认 2/8/15/25/50）、滚出件数（默认 8）、可选件数（默认 2）。
- 是否按职业限装（默认否 / 职业无关）。
- 槽位数与命名（默认 9 槽，§3.1）。

## 8. 验收标准（Acceptance Criteria）

- **AC-1**：`EquipmentDefinition` 有 `rarity`/`slot`/`set_id`；装备池含 31 种（普10/稀8/史5/稀世5/传3），`EquipmentDataManager` 扫描零校验错、`id` 唯一、`slot`/`rarity` 取值合法。
- **AC-2**：`EquipmentDataManager` 按 `rarity` 过滤、按 `slot` 过滤查询返回正确子集。
- **AC-3**：`UnitInstance` 多槽有效值——`get_max_hp/get_base_damage/get_attack_range/get_move_range` 返回基值 + 所有已装槽增量之和并钳零；空槽不影响；多件叠加正确。
- **AC-4**：招募滚 8 件（按权重稀有度抽、子池空降级），玩家选 2 件（限不同槽）各按 slot 装入；选装确定性（同 `rng_state` 滚出同 8 件）。
- **AC-5**：`get_equipment_for(crew_id)` 返回 `{slot: EquipmentDefinition}`；部署构造的 UnitInstance 多槽增量在战斗 `get_*()` 中反映。
- **AC-6**：存档往返保留 `roster_equipment` 槽字典；**旧档单 id 迁移**到对应 slot；缺定义优雅降级（不崩、不报错）。
- **AC-7**（集成）：招募选 2 件 → 部署 → 战斗有效值反映两槽增量，端到端经 RunManager 驱动。
- **AC-8**（ADVISORY smoke）：31 种装备资源导入 + `EquipmentDataManager` 校验。
- **AC-9**（ADVISORY）：F5 人眼——招募「滚 8 选 2」白盒页（8 件按品阶标签展示、选 2 件、同槽禁选第二件、确认装上）。

## 9. 测试策略（Test Strategy）

- **逻辑（BLOCKING，单测）**：
  - `UnitInstance` 多槽求和（0/1/多件、空槽、钳零、多属性叠加）。
  - `EquipmentDataManager` rarity/slot 过滤查询。
  - 招募滚 8 件：权重稀有度分布（大样本统计近似 2/8/15/25/50）、子池空降级、确定性（同 seed 同 8 件）。
  - 招募选 2 件：限不同槽、按 slot 记账、坏选（同槽/越界）拒绝。
  - `get_equipment_for` 返回槽字典。
  - `to_save_dict`/`load_from_save_dict`：槽字典往返 + **旧档单 id 迁移** + 双过滤。
- **集成（BLOCKING）**：招募选 2 件 → 部署 → 战斗有效值反映增量（AC-7）。
- **数据（ADVISORY smoke）**：31 种装备导入 + 校验（AC-8）。
- **UI（ADVISORY）**：RouteScene 招募「滚 8 选 2」页 F5 人眼（AC-9，白盒惯例，不自动化视觉）。

## 10. 范围边界（Scope）

本子项目**仅**②a：9 槽模型 + 5 稀有度 + 31 种装备数据 + 多槽有效值累加 + 招募/战斗/存档适配 + 旧档迁移。**不含**：套装效果与 set_id 归属/阈值 3/6/9（②b）、选航战利品经济/卡面预览/RUN_LOOT 按槽分配/招募限普通由经济取代（②c）、装备 UI 美术与品阶配色资源、职业限装。`EquipmentDefinition.set_id` 字段在 ②a 预置但留空，供 ②b 填充。
