# tier2 敌方原型 + 升级 island_tier3 图 — 设计文档

> 状态：已审核（用户认可 2026-06-28）
> 范围：「高 threat_tier 敌方原型」史诗 **子项目 ①**（独立可发）。新增 4 个 tier2 敌方原型，把现有 island_tier3 地图（006/007）的敌人升级为 tier2。
> 史诗拆分：① tier2 原型 + 升级 island_tier3 图（本文）→ ② 深渊扩展（tier3 原型 + island_tier 5/6 新地图 + 路线可达，另立 spec）。
> 前置：装备/8 套套装引擎 + 敌方招牌套配装（enemy-loadout，HEAD=022ab93）已完结。

## 1. Overview（概述）

当前 4 种敌方原型全为 threat_tier1 裸数值，全部 7 张地图只用 tier1 敌人。一局 run 能抵达的最深地图是 island_tier3（006/007），经 enemy-loadout 后这些敌人已带 6 件招牌套，但基础数值仍是 tier1，末岛不够硬。本子项目新增 4 个 **tier2** 敌方原型（更高血/攻），并把 006/007 的敌人换成 tier2——纯数据增量，零新代码逻辑。

## 2. Player Fantasy（玩家体验）

打到航程末岛，迎面的不再是开局那批脆皮杂兵，而是更肉更痛的精锐：守卫更难凿穿、近战一刀更重。叠加它们身上的 6 件招牌套，末岛成为真正需要打法与配合的硬仗，给整局 run 一个有分量的收尾。

## 3. Detailed Rules（详细规则）

### 3.1 架构决策

纯数据增量，**零新代码逻辑**：

- 新增 4 个 tier2 敌方 `.tres`（`EnemyDefinition`），`threat_tier=2`、更高基础数值，**沿用 tier1 的 `unit_class` 与 `behavior_type`**——前者保证 UnitView 渲染（CLASS_VISUAL 按 unit_class）正确，后者保证 EnemyLoadout 招牌套按 behavior_type 仍生效。
- `UnitDataManager`（autoload，ADR-0003 目录扫描 `assets/data/units/`）自动纳入新 `.tres`，无需注册改动。
- `battle_map_006.tres` / `battle_map_007.tres`（island_tier3）的 `enemy_roster` 每槽 `unit_definition_id` 由 `enemy_X_tier1` 改为 `enemy_X_tier2`。
- BattleMap 验证 F5：island_tier3 允许威胁层 [1,2]，tier2 ∈ [1,2] → `validate_map` 仍通过；位置/地形/编制数不变 → 其余 Rule3 检查不变。
- EnemyLoadout 不改：island_tier3 → 6 件，按 behavior_type 派招牌套（tier2 敌人照样获 6 件套）。

### 3.2 tier2 数值

| id | display_name | unit_class | behavior_type | max_hp | base_damage | attack_range | move_range | threat_tier |
|---|---|---|---|---|---|---|---|---|
| `enemy_melee_tier2` | 近战兵·精锐 | swordsman | MELEE | 9 | 4 | 1 | 2 | 2 |
| `enemy_ranged_tier2` | 炮击兵·精锐 | gunner | RANGED | 8 | 4 | 3 | 2 | 2 |
| `enemy_swarmer_tier2` | 群攻兵·精锐 | swordsman | SWARMER | 6 | 3 | 1 | 3 | 2 |
| `enemy_guardian_tier2` | 守卫兵·精锐 | bulwark | GUARDIAN | 12 | 3 | 1 | 1 | 2 |

`home_pos` 字段沿用 EnemyDefinition 默认（GUARDIAN 守位锚点由地图 EnemySlotDefinition.home_pos 提供，不在原型上）。数值相对 tier1 约 +50% hp / +1 dmg，其余维持。

⚠️ **叠加效应（设计意识，非本期调参目标）**：tier2 敌人在 island_tier3 图还自动获 6 件招牌套（守卫 ironwall6 首击减半+自愈、近战 bloodthirst6 吸血½、群攻 thorns6 反伤2、炮击 executioner6 斩杀残血≤5）+ 套装件本身属性加成。实际强度高于裸数值，故基础数值保守，最终平衡靠 F5 试玩迭代。

### 3.3 编制改动

- `battle_map_006.tres`、`battle_map_007.tres`：enemy_roster 每个槽 `unit_definition_id` 全替换为对应 tier2（melee→tier2、ranged→tier2、swarmer→tier2、guardian→tier2）。`grid_position` / `behavior_type` / `home_pos` / 编制数量不变。
- `001-005`（island_tier 1/2）不动。

## 4. Formulas（数值/常量）

见 §3.2 数值表。无公式逻辑——纯 Resource 字段。

## 5. Edge Cases（边界）

- island_tier2 图（004/005）不能用 tier2 敌人（F5 仅允许 [1]）——本期不动这两图，无冲突。
- 升级后 006/007 仍须通过完整 Rule3 验证（敌数 ≥ 最小、无位置碰撞、敌位非 BLOCKED、部署区充足、远程走廊）——位置/地形/数量未变，仅 def id 变且 tier2 存在，验证不破。
- 渲染：tier2 沿用 tier1 的 unit_class，UnitView 白盒图元/配色不变，无缺失视觉。
- 招牌套：tier2 behavior_type 与 tier1 同名，EnemyLoadout 映射命中，6 件套照常。

## 6. Dependencies（依赖）

- `assets/data/units/enemy_{melee,ranged,swarmer,guardian}_tier2.tres`（新建，参照对应 tier1 .tres 结构）
- `assets/data/maps/battle_map_006.tres`、`battle_map_007.tres`（改 enemy_roster 引用）
- 复用（不改）：`UnitDataManager`、`EnemyLoadout`、`BattleMap.validate_map`/`load_map_definition`、`EnemyDefinition`。

## 7. Tuning Knobs（可调项）

- 4 原型的 tier2 数值（hp/dmg/range/move）。
- 006/007 编制是否全 tier2 或混编（本期定全替换）。

## 8. Acceptance Criteria（验收标准）

逻辑（BLOCKING 自动化单测）：

- AC-1：4 个 tier2 `.tres` 经 `UnitDataManager.get_unit(id)` 取得到，类型为 `EnemyDefinition`，字段与 §3.2 表一致（threat_tier=2、对应 hp/dmg/range/move、unit_class、behavior_type）。
- AC-2：`battle_map_006`、`battle_map_007` 经 `BattleMap.validate_map`（注入 `UnitDataManager.get_unit`）返回 `&""`（通过）。
- AC-3：006/007 的 enemy_roster 全部引用 `*_tier2`（无残留 `*_tier1`）。
- AC-4：部署 006（或 007）后，敌方 UnitInstance 的 `definition.threat_tier == 2` 且带 6 件 equipment（island_tier3 loadout 生效）。
- AC-5：全量回归绿、零孤儿、零导入错误（既有逐图 Rule3 测试不破）。

可见性（ADVISORY，F5 截图）：

- AC-6：抵达末岛（island_tier3）敌人明显更肉更痛（tier2 数值 + 6 件套）。

## 9. 非目标（本期不做）

- tier3 原型 / island_tier 5/6 新地图 / 路线可达（子项目 ②）。
- 修改 `_allowed_threat_tiers` 映射（不需要）。
- 修改 enemy-loadout `TIER_PIECES`（不需要）。
- 平衡精调（playtest 迭代，ADVISORY）。
- 升级 island_tier 1/2 图（001-005）。
