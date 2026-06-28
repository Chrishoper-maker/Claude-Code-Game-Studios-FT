# 风险↔回报战利品（②c 重做版）— 设计文档

> Story: risk-reward-loot-roll（多地图/遭遇 epic 子项目②c）
> 日期：2026-06-28 / 引擎：Godot 4.6.3 / GDScript / GdUnit4
> **取代** `2026-06-25-risk-reward-loot-economy-design.md`（那份基于"3 稀有度 + 一人一件、替换即弃"的旧装备模型，已 SUPERSEDED；当前系统为 9 固定槽 + 5 级稀有度 + 套装效果 + 战后 RUN_EQUIPPING 滚 8 选 2）。本文按当前系统重做。

## 1. 概述（Overview）

子项目①让玩家每战前从 3 张海图卡选 1 张（卡上 tier + 敌情 = 风险）。当前战后已有 **RUN_EQUIPPING**：非末岛胜利后为每名出战幸存船员滚 8 件候选装备、玩家各选 ≤2 件装上（`roll_battle_equipment`）。但这 8 件候选的随机回退分支是**全池等概**，与所选地图凶险度无关——风险与回报脱钩。

本子项目把**战后候选的稀有度按"刚通关地图的 island_tier"加权**：越凶险的图，滚出的候选越可能高稀有度（史诗/稀世/传奇）。并在选航卡上预览该图的战利品品阶带，让"赌高 tier 海域换好装备"的取舍在选航时可见。**复用既有 RUN_EQUIPPING 流程，零新阶段、零新数据模型（`rarity` 已存在），零新存档字段。**

## 2. 玩家体验（Player Fantasy）

摊开海图时，不只看到哪片海域更凶险，还看到啃下它能缴获什么品阶的战利品。稳妥取低 tier 图，战后多半是普通/稀有补给；赌一把深渊 tier6，战后候选里更可能蹦出史诗、传奇。风险与回报直接挂钩，选航的取舍有了实在的诱惑。

## 3. 详细规则（Detailed Rules）

### 3.1 tier → 稀有度权重表（新纯助手 `LootRarity`）

新增 `src/data/loot_rarity.gd`（`class_name LootRarity extends RefCounted`，纯静态无状态，仿 `EnemyLoadout` 范式）。

`LootRarity.rarity_weights(island_tier: int) -> Array[int]`：返回该 tier 在 5 个稀有度 [普通0, 稀有1, 史诗2, 稀世3, 传奇4] 上的权重（可调；传奇恒 0，因装备池无传奇件）：

| island_tier | 普通 | 稀有 | 史诗 | 稀世 | 传奇 |
|---|---|---|---|---|---|
| 1 | 60 | 30 | 10 | 0 | 0 |
| 2 | 35 | 40 | 20 | 5 | 0 |
| 3 | 20 | 35 | 30 | 15 | 0 |
| 5 | 10 | 25 | 35 | 30 | 0 |
| 6 | 5 | 15 | 35 | 45 | 0 |
| 其它（未知/0/4） | 60 | 30 | 10 | 0 | 0 |（保守同 tier1）

> 装备池实际稀有度分布：普通 24 / 稀有 24 / 史诗 16 / 稀世 8 / 传奇 0（共 72 件）。权重表对应这些档位；传奇无件故权重 0，`weighted_pick` 的降级保证永不卡死。

### 3.2 加权抽取（`LootRarity.weighted_pick`）

`LootRarity.weighted_pick(pool: Array, island_tier: int, rng: RandomNumberGenerator) -> EquipmentDefinition`：

1. `weights := rarity_weights(island_tier)`。
2. 按**逐件权重**（每件权重 = `weights[piece.rarity]`）求总权重 `total`；`total<=0` 或 `pool` 空 → 返回 null（调用方回退既有随机）。
3. `r := rng.randi_range(0, total - 1)`，沿 pool 累加逐件权重定位命中件 → 返回。
4. 权重 0 的件（如传奇）自然贡献 0、永不被选；某稀有度无件时其权重对 total 无贡献——无需显式降级，逐件加权天然跳过空档。

确定性：`rng` 由调用方注入（RunManager 持有的 `_rng`），`rng_state` 已入存档 → 续航复现同候选。

### 3.3 战后滚装接入（`roll_battle_equipment`）

`roll_battle_equipment(crew_id: String, island_tier: int = 1)` 加 `island_tier` 形参（默认 1 保向后兼容）。函数体唯一改动：随机回退分支
```
# 旧：pick = all[_rng.randi_range(0, all.size() - 1)]
# 新：pick = LootRarity.weighted_pick(all, island_tier, _rng)
#     若 weighted_pick 返回 null（total<=0/空池）→ 退回旧的全池等概抽
```
**80% 偏向主套分支（`BIAS_CHANCE`）完全不变**——套装补全是核心循环，不应被 tier 门控；只有那 20%（及主套池空）的随机回退改为 tier 加权。

### 3.4 通关地图 tier 传入（`_on_battle_won`）

`_on_battle_won` 非末岛分支（line 407）把 `roll_battle_equipment(c.id)` 改为 `roll_battle_equipment(c.id, _cleared_island_tier())`。

新增私有 `_cleared_island_tier() -> int`：读 `MapDataManager.get_map(_chosen_map_id)`，非空返 `island_tier`，否则返 1（缺图/未选图的保守回退）。`_chosen_map_id` 已是本场所选图、已入存档。

### 3.5 选航卡战利品品阶预览（RouteScene CHARTING）

`route_scene.gd` 的 `_show_route_offers`（line 203）卡面文本在「地名 · 难度N · 敌情摘要」末尾追加战利品品阶带：
`地名 · 难度3 · 近战×2 远程×1 · 战利品：稀有~稀世`

品阶带由 `LootRarity.loot_band_label(island_tier) -> String` 给出：取该 tier 权重表中权重 ≥ `BAND_THRESHOLD`（默认 15）的稀有度区间，用 `EquipmentDefinition.rarity_label` 转中文，返回 `"最低档~最高档"`（单档时只显一档）。例：tier6 权重 [5,15,35,45,0] → ≥15 的是 稀有/史诗/稀世 → `"稀有~稀世"`。

### 3.6 不变更项

- 战后 RUN_EQUIPPING 流程（滚 8 / 选 ≤2 / `equip_piece` / `finish_crew_equip`）骨架不变，只换候选稀有度分布。
- 招募/起始直发（`roll_initial_equipment`，80% 同套 3 件）**不改**——风险回报只走战后通道，招募保持中性，避免双通道稀有度失衡。
- 末岛胜（RUN_END + 解锁）不变，不滚战利品（终局装备无意义）。
- `EquipmentDefinition` / `EquipmentDataManager` / 套装引擎 / 战斗解算 / 存档结构 **零改动**。

## 4. 公式 / 数据结构（Formulas / Data）

- `LootRarity.rarity_weights(island_tier) -> Array[int]`（§3.1 表）。
- `weighted_pick`：`total = Σ weights[piece.rarity]`；`r ∈ [0, total)`；累加定位。
- `loot_band_label`：`{rarity : weights[rarity] >= BAND_THRESHOLD}` 的最小~最大 `rarity_label`。
- `RunManager._cleared_island_tier()`：`get_map(_chosen_map_id).island_tier`，缺则 1。
- 常量：`LootRarity.BAND_THRESHOLD := 15`。
- **无新 RunManager 字段、无新存档键、无新 RunPhase**。

## 5. 边界情况（Edge Cases）

- **weighted_pick 空池 / total<=0**：返 null，`roll_battle_equipment` 退回既有全池等概（不崩、有产出）。
- **某稀有度无件（传奇）**：逐件加权天然不选（权重×0 件数=0 贡献）；无显式降级路径。
- **`_chosen_map_id` 缺图 / 空**：`_cleared_island_tier` 返 1（保守低 tier 权重）。
- **续航在 EQUIPPING**：`_pending_battle_equip` 已入存档（候选 eid 直存，不重滚）→ 复现同候选；本期不改存档。
- **未知 tier（如理论上的 4）**：`rarity_weights` 默认分支返 tier1 保守权重。
- **既有调用方/测试**：`roll_battle_equipment` 加形参（默认 1）→ 旧单参调用仍编译；显式断言战后候选的测试可能需补 island_tier 参数与新分布预期（诚实更新）。

## 6. 依赖（Dependencies）

- `src/autoloads/run_manager.gd`（`roll_battle_equipment` 加参 + `_on_battle_won` 传 tier + `_cleared_island_tier`）。
- `src/data/loot_rarity.gd`（**新建**，纯静态助手）。
- `src/data/equipment_definition.gd`（读 `rarity` / `rarity_label`，不改）。
- `src/autoloads/equipment_data_manager.gd`（`get_all_equipment`，不改）。
- `src/autoloads/map_data_manager.gd`（`get_map().island_tier`，不改）。
- `src/ui/route_scene.gd`（CHARTING 卡追加品阶带行）。
- 子项目①选航 `_chosen_map_id` + 史诗②深层 tier（5/6 权重已含）。

## 7. 可调旋钮（Tuning Knobs）

- `LootRarity` tier→稀有度权重表（§3.1）。
- `BAND_THRESHOLD`（品阶带显示阈值，默认 15）。
- `BIAS_CHANCE`（主套偏向，沿用既有 80%，本期不动）。
- 是否把招募也接入 tier 加权（默认否）。
- 末岛是否滚战利品（默认否）。

## 8. 验收标准（Acceptance Criteria）

- **AC-1**：`LootRarity.rarity_weights(t)` 对 t∈{1,2,3,5,6} 返回 §3.1 表对应权重；未知 t 返 tier1 保守权重。
- **AC-2**：`LootRarity.weighted_pick(pool, t, rng)`：① 空池/total<=0 返 null；② 权重集中于单一**有件**稀有度时，返回件的 `rarity` 即该档（确定性，seeded rng）；③ 传奇权重 0 → 永不返回传奇件。
- **AC-3**：`roll_battle_equipment(crew_id, island_tier)` 滚 8 件；高 tier 调用相比 tier1 调用，候选高稀有度（rarity≥2）占比显著更高（同 seed 对照，统计可断言阈值）；主套偏向分支行为不变。
- **AC-4**：`_on_battle_won` 非末岛胜把刚通关图 `island_tier` 传入 `roll_battle_equipment`；`_cleared_island_tier` 缺图返 1。
- **AC-5**：末岛胜不滚战利品、走既有 RUN_END；招募/起始直发不受 tier 影响（仍中性）。
- **AC-6**：`LootRarity.loot_band_label(t)` 返回该 tier ≥`BAND_THRESHOLD` 权重稀有度的「最低~最高」中文标签（单档显一档）。
- **AC-7**（集成）：端到端——选高 tier 图 → 胜 → RUN_EQUIPPING 候选稀有度分布偏高 → 装上的高稀有度件增量在后续战斗有效值（`get_max_hp` 等）中反映。
- **AC-8**：全量测试套件绿（含因 `roll_battle_equipment` 加参诚实更新的既有断言），0 errors/failures/orphans，导入零错。
- **AC-9**（ADVISORY，F5 人眼）：CHARTING 卡显示战利品品阶带；高 tier 图战后候选肉眼偏高稀有度。

## 9. 测试策略（Test Strategy）

- **逻辑（BLOCKING，单测）**：
  - `LootRarity.rarity_weights`：5 个已知 tier + 未知 tier 默认（AC-1）。
  - `LootRarity.weighted_pick`：空池→null；单一有件稀有度权重→确定档位；传奇权重 0 不返回（AC-2）。
  - `LootRarity.loot_band_label`：tier1→「普通~稀有」(若阈值含)、tier6→「稀有~稀世」等（AC-6，按阈值精确断言）。
  - `roll_battle_equipment(crew_id, tier)`：高 tier vs tier1 同 seed，高稀有度占比阈值（AC-3）；主套偏向分支不变。
  - `_cleared_island_tier`：选定图返其 tier、缺图返 1（AC-4）。
- **集成（BLOCKING）**：选高 tier 图 → 胜 → EQUIPPING 候选分布偏高 → 装上后有效值反映（AC-7）。
- **UI（ADVISORY）**：RouteScene CHARTING 品阶带 F5 人眼（AC-9）。

## 10. 范围边界（Scope）

本子项目**仅**：tier→稀有度权重表 + 战后候选加权 + 选航卡品阶预览。**不含**：独立掉落物/库存、货币/商店、招募 tier 加权、新阶段/新存档字段、③ 新敌人（已在史诗②深渊扩展交付 tier3）。
