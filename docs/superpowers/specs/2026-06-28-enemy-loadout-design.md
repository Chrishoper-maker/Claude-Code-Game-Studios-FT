# 敌方招牌套配装 — 设计文档

> 状态：已审核（用户认可 2026-06-28）
> 范围：「难度 + 敌方配装」子项目首个交付 —— 给敌方按原型招牌套 + island_tier 定件数配装，复用既有装备/套装引擎。
> 前置：装备系统 MVP + ②b 套装效果史诗（8 套）已完结（HEAD=62635b6）。

## 1. Overview（概述）

敌方目前一律无装备，全部敌人都是 threat_tier1 裸数值，且 8 套套装机制玩家只能从自己一侧偶尔体验。本子项目给敌方按**原型招牌套**配装、按**地图 island_tier 决定件数**，使高 tier 地图的敌人更强，并让套装机制从敌方侧也可见——全程复用既有装备有效值访问器与 SetEffectSystem/SetReactionSystem，战斗/AI/解算零改动。

## 2. Player Fantasy（玩家体验）

驶入越凶险的海域，敌人不只是数字更高——他们披甲带套：守卫筑起钢铁壁垒难以击穿，近战吸血越打越精神，突进兵满身荆棘反噬围殴，远程狙手专补残血。玩家必须读懂每种敌人的套装特性来调整打法，而非无脑平推。

## 3. Detailed Rules（详细规则）

### 3.1 架构决策

新增**纯数据助手** `EnemyLoadout`（无状态，data-driven）：`for_enemy(behavior_type: String, island_tier: int) -> Dictionary`，返回 `{slot:int → EquipmentDefinition}`（招牌套的前 N 件，N 由 tier 定）。`BattleMap.load_map_definition` 部署每个敌人时调它，把 loadout 传给既有 `UnitInstance.from_definition(enemy_def, loadout)`。

候选对比：A 原型招牌套 + tier 件数（采用，确定性、自动随 tier、复用引擎）；B 地图 .tres 逐敌手写（可控但逐图人工、难度靠手调，否决）；C 部署时按 tier 随机滚装（随机不可控，否决）。

为何此机制开箱即用：`SetEffectSystem`(订阅 round_started) 与 `SetReactionSystem`(订阅 attack_executed) 均遍历 `get_alive_allies()+get_alive_enemies()`、**阵营无关**，且已在 `BattleScene._ready` setup。敌方一旦 `equipment` 非空，其套装效果每轮/每次命中自动触发，无需新增触发逻辑。

### 3.2 招牌套映射（4 原型 → 阵营无关套，避开寒霜）

| behavior_type | set_id | 主题 |
|---|---|---|
| GUARDIAN | `set_ironwall` | 守位坦克、减伤护卫 |
| MELEE | `set_bloodthirst` | 命中回血、贴脸续航 |
| SWARMER | `set_thorns` | 反伤，惩罚围殴 |
| RANGED | `set_executioner` | 补刀残血、狙杀 |

未知 behavior_type → 返回空 loadout（防御性，不崩）。

### 3.3 tier → 件数（按地图 island_tier）

| island_tier | 件数 N | 激活档 |
|---|---|---|
| 1 | 0 | 无（维持现状，零回归） |
| 2 | 3 | 3 档 |
| 3 | 6 | 6 档 |
| ≥4 | 9 | 9 档（预留，现无此图） |

每套 9 件按**固定 slot 顺序**取前 N 件，确定性，`SetBonus.is_tier_active(unit, set_id, N)` 必为真。slot 顺序常量在 `EnemyLoadout` 内定义（与现有 `_SLOTKEYS` 一致：mainweapon/offweapon/head/armor/gloves/legs/boots/ring/necklace）。

### 3.4 数据流

部署敌人（`BattleMap.load_map_definition` 既有循环内，`from_definition` 调用点）：
`behavior_type`（来自 EnemySlotDefinition / EnemyDefinition）+ `map_def.island_tier` → `EnemyLoadout.for_enemy(type, tier)` → `from_definition(enemy_def, loadout)`。
其余部署逻辑（register_unit / place_unit）不变。SetEffectSystem/SetReactionSystem 自动触发；玩家打荆棘敌→反伤飘字、嗜血敌命中→回血飘字，经既有战斗反馈可见。

## 4. Formulas（数值/常量）

- 招牌套映射 dict：`{"GUARDIAN":"set_ironwall","MELEE":"set_bloodthirst","SWARMER":"set_thorns","RANGED":"set_executioner"}`。
- tier→件数 dict：`{1:0, 2:3, 3:6}`，缺失 tier（≥4）取 9，tier≤0 取 0。
- slot 顺序：`["mainweapon","offweapon","head","armor","gloves","legs","boots","ring","necklace"]`（对应 EquipmentDefinition.slot 的 int 值；取该套 `eq_<set>_<slot>` 前 N 件）。

## 5. Edge Cases（边界）

- island_tier 1（及所有现有 tier1 图）→ 0 件 → 敌方 `equipment` 为空 → 与当前行为逐字等价，既有 7 图 + 集成测试零回归。
- 未知/空 behavior_type → 空 loadout。
- 某套某 slot 装备缺失（理论上不会，8 套均 9 件齐全）→ `EquipmentDataManager.get_equipment` 返回 null 时跳过该件（loadout 件数可能 < N，优雅降级不崩）。
- 敌方寒霜：**招牌套不含 set_frost**（玩家无寒霜结算入口，会卡死），本期不开放。
- crew 不受影响：EnemyLoadout 仅在敌方部署路径调用，crew 部署路径（deploy_crew）不变。

## 6. Dependencies（依赖）

- `src/data/enemy_loadout.gd`（新建，纯助手）
- `src/battle/battle_map.gd`（敌方部署 `from_definition` 调用点接入 loadout）
- 复用（不改）：`src/data/unit_instance.gd`（equipment 字段 + 有效值访问器）、`src/battle/set_bonus.gd`、`src/battle/set_effect_system.gd`、`src/battle/set_reaction_system.gd`、`EquipmentDataManager`。

## 7. Tuning Knobs（可调项）

- 原型→套装映射（4 项）。
- tier→件数映射。
- slot 取件顺序（影响"哪几件"，但不影响套装档位计数）。

## 8. Acceptance Criteria（验收标准）

逻辑（BLOCKING 自动化单测）：

- AC-1：`EnemyLoadout.for_enemy(type, tier)` 对 4 原型 × {tier2,tier3} 返回正确 set_id、正确件数（3/6），slot 键正确。
- AC-2：tier1（及 tier≤1）→ 返回空 Dictionary。
- AC-3：未知 behavior_type → 返回空 Dictionary。
- AC-4：BattleMap 部署 island_tier≥2 地图后，敌方 `UnitInstance.equipment` 含招牌套且 `SetBonus.is_tier_active(unit, 招牌套, N)` 为真。
- AC-5：BattleMap 部署 island_tier1 地图后，敌方 `equipment` 为空（既有 7 图回归）。
- AC-6：全量回归绿、零孤儿、零导入错误（既有集成测试不破）。

可见性（ADVISORY，F5 截图）：

- AC-7：高 tier 图敌人触发套装效果——打荆棘敌弹反伤飘字、嗜血敌命中弹回血飘字。

## 9. 非目标（本期不做）

- 高 threat_tier 敌方原型（tier2/tier3 更高基础数值，另立子项目）。
- 敌方头顶套装指示标（YAGNI，靠既有效果反馈可见，后续可加类似寒霜标签）。
- 敌方寒霜套（需玩家侧 CC 结算先落地）。
- 玩家战利品经济（②c，独立子项目）。
- 招牌套之外的多套混搭 / 按敌方个体差异化配装。
