# 深渊扩展（tier3 原型 + island_tier 5/6 新地图 + 路线可达）— 设计文档

> 范围：「高 threat_tier 敌方原型」史诗 **子项目 ②**（独立可发）。新增 4 个 tier3 敌方原型，新增 2 张 island_tier 5/6 深层地图，并打通路线可达——让一局 run 的后两岛真正抵达深层硬仗。
> 史诗回顾：① tier2 原型 + 升级 island_tier3 图（已交付，HEAD=6c3f8fd）→ **② 深渊扩展（本文）**。纯数据 + 一处路线映射调整，零新代码系统。

## 1. Overview（概述）

当前一局 run 固定 5 岛（`ISLAND_COUNT_MAX=5`），但 `RunManager._target_tiers_for_island` 的目标 island_tier 最深只到 3（next_idx 3→[2,3]、4→[3]）。而 `BattleMap._allowed_threat_tiers` 早已为 island_tier 5→[2,3]、6→[3] 预留了威胁层槽位，却**没有任何 island_tier 5/6 地图，也没有 tier3 敌人**——后两岛只能靠 `get_route_offers` 的降级分支随机复用浅层图，深度无实质爬升。

本子项目补齐三件事，**纯数据 + 一处路线映射调整，零新代码逻辑**：
1. 新增 4 个 **tier3** 敌方原型（`threat_tier=3`，更高血/攻）。
2. 新增 2 张深层地图：`battle_map_008`（island_tier 5，tier2/tier3 混编）、`battle_map_009`（island_tier 6，全 tier3，6 敌满编）。
3. 调整 `_target_tiers_for_island`，让后两岛真正目标 island_tier 5/6（路线可达）。

## 2. Player Fantasy（玩家体验）

航程不再在第三岛见顶。穿过血色风暴后，海图把你引向**深渊门廊**与**渊心王座**——迎面是更肉更狠的「将官」级精锐，最终岛是六名 tier3 督军的满编恶战，叠加它们身上的 6 件招牌套，给整局 run 一个真正配得上"末岛"二字的收尾。每一岛的敌人都肉眼可辨地比上一岛更难凿穿，深度爬升有了实感。

## 3. Detailed Rules（详细规则）

### 3.1 不变更项

- **沿用 tier1/tier2 的 `unit_class` 与 `behavior_type`**：前者保证 UnitView 渲染（CLASS_VISUAL 按 unit_class）正确，后者保证 EnemyLoadout 招牌套按 behavior_type 仍生效（tier3 敌人在 island_tier 5/6 照获套装）。
- `BattleMap.validate_map` / Rule3 / `_allowed_threat_tiers` 表 / EnemyLoadout / 战斗解算 / AI / 回合管理 / crew **全部不改**。
- `ISLAND_COUNT_MAX`（仍 5 岛）、`get_route_offers` 降级逻辑、`confirm_route`、存档字段 **不改**。

### 3.2 tier3 数值（threat_tier=3）

| id | display_name | unit_class | behavior_type | max_hp | base_damage | attack_range | move_range | threat_tier |
|----|--------------|-----------|---------------|--------|-------------|--------------|------------|-------------|
| `enemy_melee_tier3` | 近战兵·将官 | swordsman | MELEE | 12 | 5 | 1 | 2 | 3 |
| `enemy_ranged_tier3` | 炮击兵·将官 | gunner | RANGED | 11 | 5 | 3 | 2 | 3 |
| `enemy_swarmer_tier3` | 群攻兵·将官 | swordsman | SWARMER | 8 | 4 | 1 | 3 | 3 |
| `enemy_guardian_tier3` | 守卫兵·将官 | bulwark | GUARDIAN | 16 | 4 | 1 | 1 | 3 |

步进依据（tier1→tier2 同 delta 延伸，仅升血/攻，range/move 不变）：

| | guardian | melee | ranged | swarmer |
|---|---|---|---|---|
| tier1 | 8/2 | 6/3 | 5/3 | 4/2 |
| tier2 | 12/3 | 9/4 | 8/4 | 6/3 |
| **tier3** | **16/4** | **12/5** | **11/5** | **8/4** |

⚠️ **叠加效应（设计意识，非本期调参目标）**：`EnemyLoadout._pieces_for_tier` 对 island_tier≥4 返回 **9**（满槽），故 tier3 敌人在 island_tier 5/6 自动获**满 9 件招牌套（最高档套装加成）**——守卫满 ironwall、近战满 bloodthirst、群攻满 thorns、炮击满 executioner，外加 9 件套装属性加成。实际强度**远**高于裸数值，故基础数值刻意保守，最终平衡靠 F5 试玩迭代。无需改 EnemyLoadout（既有 tier≥4→9 分支即生效）。

### 3.3 新地图（terrain 空，沿用 006/007 已验证布局范式）

两图均 `terrain_data = Array[TerrainCell]([])`（空地形 = 走廊检测平凡通过、无 BLOCKED 冲突），敌人全在 0-3 行、部署区在 6-7 行（保证每敌到每部署格曼哈顿 ≥3）。

**`battle_map_008` 「深渊门廊」island_tier=5**（threat 允许 [2,3]），5 敌混编：

| slot | unit_definition_id | grid_position | behavior | home_pos |
|---|---|---|---|---|
| s1 | enemy_melee_tier3 | (1,0) | MELEE | (-1,-1) |
| s2 | enemy_melee_tier3 | (6,0) | MELEE | (-1,-1) |
| s3 | enemy_ranged_tier2 | (0,1) | RANGED | (-1,-1) |
| s4 | enemy_ranged_tier2 | (7,1) | RANGED | (-1,-1) |
| s5 | enemy_guardian_tier3 | (4,3) | GUARDIAN | (4,3) |

deploy_zone = 行 6-7 × 列 0-5（12 格）。

**`battle_map_009` 「渊心王座」island_tier=6**（threat 仅 [3]），6 敌满编全 tier3：

| slot | unit_definition_id | grid_position | behavior | home_pos |
|---|---|---|---|---|
| s1 | enemy_guardian_tier3 | (3,2) | GUARDIAN | (3,2) |
| s2 | enemy_guardian_tier3 | (4,2) | GUARDIAN | (4,2) |
| s3 | enemy_melee_tier3 | (1,0) | MELEE | (-1,-1) |
| s4 | enemy_melee_tier3 | (6,0) | MELEE | (-1,-1) |
| s5 | enemy_ranged_tier3 | (0,1) | RANGED | (-1,-1) |
| s6 | enemy_swarmer_tier3 | (7,3) | SWARMER | (-1,-1) |

deploy_zone = 行 6-7 × 列 2-7（12 格）。

Rule3 自检（两图同理）：敌数 5/6 ∈ [2,6] ✓；无位置碰撞 ✓；无 BLOCKED（terrain 空）故敌不踩 BLOCKED + 走廊平凡存在 ✓；部署区 12 格 ≥6 ✓；最近敌（row≤3）到最近部署格（row≥6）曼哈顿 ≥3 ✓；threat_tier ∈ allowed ✓。

### 3.4 路线可达（`_target_tiers_for_island` 调整）

即将抵达岛号 next_idx = current_island_index + 1（一局 next_idx 取 0..4）。把目标 island_tier 映射改为爬升到深层：

| next_idx | 现行 | **新** | 说明 |
|---|---|---|---|
| 0（第1岛） | [1] | [1] | 不变 |
| 1（第2岛） | [1,2] | [1,2] | 不变 |
| 2（第3岛） | [1,2] | [2,3] | 第3岛升到 tier2/3 |
| 3（第4岛） | [2,3] | [3,5] | 第4岛接 tier3/深层5 |
| 4（末岛） | [3] | [5,6] | 末岛进深渊 5/6 |

降级逻辑（`get_route_offers` 内）不变：目标 tier 未访问图 <3 张时放宽到全体未访问、再放宽到全体。深层 tier 每档 1-2 张，故末岛三张候选会自然由 008/009 + 降级补足——这是既有行为，本期复用。

## 4. Formulas（公式）

- tier3 基础数值见 §3.2 表（数据，非运行时公式）。
- 路线目标 tier：`_target_tiers_for_island(next_idx)` 见 §3.4 表。
- 其余战斗公式（伤害管线、招牌套、Rule3 验证 F1–F6）**完全复用，无新公式**。

## 5. Edge Cases（边界）

- **island_tier 4 不使用**：路线映射从 tier3 直跳 tier5，无 island_tier 4 地图（`_allowed_threat_tiers` 把 3,4 同组是历史遗留，本期不依赖 4）。无冲突。
- **深层 tier 地图不足 3 张**：`get_route_offers` 降级分支兜底（已存在、已测），末岛候选混入低 tier 图或重复——可接受（MVP，内容深度靠敌人数值，不靠图数量）。
- **tier3 渲染**：沿用 tier1/tier2 的 unit_class，UnitView 白盒图元/配色不变，无缺失视觉。
- **招牌套**：tier3 behavior_type 与 tier1/2 同名，EnemyLoadout 映射命中，island_tier 5/6 → `_pieces_for_tier` 返回 9（满槽全套）。已核查（见 §6）。
- **既有 run_loop / route_offers 测试**：§3.4 改 next_idx 2/3/4 映射 → 断言这些值的测试须诚实更新（行为变更，非削弱不变量）。
- **存档兼容**：未改存档结构；旧档 chosen_map_id 指向 008/009 不存在的情况不会发生（旧档不含这俩 id，新 id 只在新 run 产生）。

## 6. Dependencies（依赖）

- `src/data/enemy_definition.gd`（EnemyDefinition，复用）。
- `src/autoloads/unit_data_manager.gd`（目录扫描，新 .tres 自动纳入）。
- `src/autoloads/map_data_manager.gd`（`get_maps_for_tier` / `get_all_maps`，新图自动纳入 `_by_tier[5]`/`_by_tier[6]`）。
- `src/battle/battle_map.gd`：`_allowed_threat_tiers` 已支持 5/6（不改）；`EnemyLoadout.for_enemy` 在部署循环调用。
- `src/data/enemy_loadout.gd`：**已核查**——`_pieces_for_tier(island_tier)` 对 island_tier≥4 返回 9（满槽），故 island_tier 5/6 敌人获满 9 件招牌套。无需改 EnemyLoadout，本期不动。
- `src/autoloads/run_manager.gd`：`_target_tiers_for_island`（唯一代码改动点）。
- 测试：`tests/unit/enemy_tier2/`（参照新建 enemy_tier3 测试）、`tests/unit/battle_map/`（map_pool / 新图 Rule3）、route_offers 相关测试。

## 7. Tuning Knobs（可调参数）

- 4 个 tier3 原型数值（hp/dmg/range/move）。
- 008/009 编制（敌种类/数量/位置/部署区）。
- `_target_tiers_for_island` 各 next_idx 的目标 tier 集合。
- 新图数量（本期 2 张；后续可加同 tier 图增加多样性）。

## 8. Acceptance Criteria（验收标准）

- **AC-1**：4 个 tier3 `.tres` 经 `UnitDataManager.get_unit(id)` 取得为 `EnemyDefinition`，字段与 §3.2 表一致（threat_tier=3、对应 hp/dmg/range/move、unit_class、behavior_type）。
- **AC-2**：`MapDataManager.get_map("battle_map_008")` / `..._009` 非空，island_tier 分别为 5/6，enemy_roster 组成与 §3.3 表一致。
- **AC-3**：008/009 各自经 `validate_map` 返回 `&""`（全 Rule3 通过）。
- **AC-4**：`MapDataManager.get_maps_for_tier(5)` 含 008、`get_maps_for_tier(6)` 含 009。
- **AC-5**：`_target_tiers_for_island` 返回值与 §3.4 新表一致（next_idx 0..4 = [1]/[1,2]/[2,3]/[3,5]/[5,6]）。
- **AC-6**：部署 009 后，敌方 UnitInstance 的 `definition.threat_tier == 3` 且带 9 件 equipment（island_tier 6 → `_pieces_for_tier`=9 满套 loadout 生效）。
- **AC-7（F5 ADVISORY，人眼）**：跑通整局 5 岛，后两岛肉眼可见目标地图为 008/009（深渊门廊/渊心王座），敌人明显更肉更痛。
- **AC-8**：全量测试套件绿（含因 §3.4 诚实更新的 route 断言），0 errors/failures/orphans，导入零错。

## 9. Non-Goals（非目标，明确不做）

- 不新增敌方 behavior_type / AI 行为（tier3 沿用四原型行为）。
- 不改 EnemyLoadout 件数表（若 island_tier 5/6 取件数需调整，另立 spec）。
- 不加 island_tier 4 地图（路线跳过 4）。
- 不改 ISLAND_COUNT_MAX（仍 5 岛）。
- 不做风险回报战利品经济（②c，独立子项目）/ 敌方头顶套装指示标（独立）。
- 不做手绘地形/美术（terrain 空，白盒）。
