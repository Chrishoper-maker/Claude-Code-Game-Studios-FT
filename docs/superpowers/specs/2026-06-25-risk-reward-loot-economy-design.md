# 风险↔回报奖励经济（子项目②）设计

> **⚠️ SUPERSEDED（2026-06-25）**：本方案假设「3 级稀有度 + 一人一件、替换即弃」。
> 用户随后把装备系统扩展为 **9 固定槽 + 5 级稀有度 + 套装效果（3/6/9 阈值）**。
> ② 已重新拆分为 ②a 装备地基重构 → ②c 风险回报战利品经济 → ②b 套装效果，
> 顺序 ②a→②c→②b。本文档保留作历史记录，**不再据此实现**。
> 当前生效地基设计见 `2026-06-25-equipment-slots-rarity-foundation-design.md`（②a）。

> Story: risk-reward-loot-economy（多地图/遭遇 epic 子项目②，已 superseded）
> 日期：2026-06-25
> 引擎：Godot 4.6.3 / GDScript / GdUnit4
> 前置：子项目①海图选航骨架（`2026-06-24-chart-course-multi-map-design.md`，已完成 push 5721a8b）

## 1. 概述（Overview）

把选航卡从「只展示风险」升级为「风险↔回报权衡」。子项目①已让玩家每战前从 3 张海图卡选 1 张（卡上展示 tier + 敌情=风险）；本子项目为每张卡**附带一件具体战利品装备**作为回报——越凶险（高 `island_tier`）的图掉越高稀有度的装备。战斗胜利后，玩家选一名幸存船员把战利品装上（替换并丢弃旧装备）。复用现有装备系统，不引入货币/商店。

## 2. 玩家体验（Player Fantasy）

身为船长，摊开海图时不只看到哪片海域更凶险，还看到啃下它能缴获什么宝物。是稳妥取低风险的普通补给，还是赌一把高 tier 海域换一件史诗装备？打赢后再决定让哪名幸存船员吃下这件升级——决策有重量、有取舍。

## 3. 详细规则（Detailed Rules）

### 3.1 装备稀有度梯度
- `EquipmentDefinition` 新增 `rarity: int`（0=普通 / 1=稀有 / 2=史诗）。现有 4 件（弯刀/板甲/望远镜/轻靴）标为**普通**（`rarity=0`）。
- 扩充装备池，新增**稀有**与**史诗**装备（更大或复合增量）。目标分布：每稀有度 ≥3 件，覆盖四类增量需求（血/攻/射程/移动）。参考清单（数值实现期可微调）：
  - 稀有（rarity=1）：强化板甲 +5血、利刃 +2攻、双管 +2射程、疾风靴 +2移动
  - 史诗（rarity=2）：船长披风 +4血+1攻、领航海图 +1射程+1移动、屠龙 +3攻
- 装备仍为只读静态模板，由 `EquipmentDataManager` 扫描缓存；运行时不写回。

### 3.2 tier → 战利品稀有度（确定性滚装）
- 每张选航卡掉落**一件**装备，稀有度由该地图 `island_tier` 决定（可调映射表见 §4）。
- `get_route_offers()` 生成候选时，在既有 Fisher-Yates 之后、按 offer 顺序为每张卡用 `_rng` 滚一件**符合该卡 tier→rarity 的**装备，写入 `_route_loot`（`map_id → equipment_id`）。
  - 滚法仿 `_offer_equipment`（招募装备）：从 `EquipmentDataManager` 按目标 rarity 过滤出子池，`_rng.randi_range` 有放回抽一件。
  - 目标 rarity 子池为空时优雅降级：放宽到相邻较低 rarity；仍空则该卡无战利品（`_route_loot` 不含该 map_id）。
- 全程走 RunManager 持有的 `_rng`，`rng_state` 存档复现 → 续航重抽得同战利品。

### 3.3 卡面预览（CHARTING）
- RouteScene CHARTING 卡在既有「地名/难度/敌情」之外追加一行战利品：
  `战利品：强化板甲（稀有）+5血`（`display_name`（稀有度中文标签）增量摘要）。
- 稀有度中文标签：0→普通 / 1→稀有 / 2→史诗。增量摘要复用装备系统现有格式（仅列非零增量；全零时省略增量段）。
- 该卡无战利品（降级后子池仍空）时显示「战利品：无」。

### 3.4 选航确认携带战利品
- `confirm_route(map_id)`（既有）末尾追加：把 `_route_loot[map_id]` 记入 `_pending_loot`（equipment_id；无则 `""`）。其余既有行为（记 `_chosen_map_id`、标记 visited、清 `_last_route_offers`、转 `RUN_DEPLOYING`）不变。
- 清 `_route_loot`（本批候选已消费）。

### 3.5 战后发放流程
新增 `RUN_LOOT`（战利品分配）阶段，插在战斗胜利与招募之间：
```
首岛/中段岛(idx 0-3)胜:  BATTLE胜 → RUN_LOOT 分配 → RECRUITING → CHARTING → ...
末岛(idx 4)胜:           BATTLE胜 → RUN_END（不进 LOOT；既有通关+解锁逻辑不变）
```
- `_on_battle_won()`：
  - **末岛胜**：走既有 `RUN_END` 分支（含 `MetaProgress.unlock_next`）；清 `_pending_loot`（终局装备消失，发放无意义）。
  - **非末岛胜**：若 `_pending_loot != ""` 且其定义存在 → 转 `RUN_LOOT`；否则直接转 `RECRUITING`（保持既有行为，无战利品不空转一屏）。

### 3.6 战利品分配（RUN_LOOT，白盒 UI）
- `assign_loot(crew_id)`：把 `_pending_loot` 写入 `_roster_equipment[crew_id]`（覆盖该船员原装备 = 旧装备丢弃），清 `_pending_loot`，转 `RUN_RECRUITING`。
  - `crew_id` 不在当前 roster：`push_error` 且不改状态（仿 `confirm_recruit` 坏 id）。
- `skip_loot()`：不改任何装备，清 `_pending_loot`，转 `RUN_RECRUITING`。
- RouteScene `RUN_LOOT` 分支：
  - 顶部展示战利品（名+稀有度+增量）。
  - 列出**幸存 roster** 船员按钮（`职业·名` + 当前装备摘要，无装备显「空手」），点选 → `assign_loot(crew_id)` → 进 RECRUITING 分支。
  - 一个「放弃此战利品」按钮 → `skip_loot()`。
  - 全交互按钮，无自由输入。roster 为空（理论不会发生，全灭走 `battle_lost`→`RUN_END`）→ 自动 `skip_loot()` 不崩。

### 3.7 招募装备限普通
- 招募候选随机装备（`_offer_equipment` 滚装）**只从普通（rarity=0）子池抽**——使稀有/史诗装备只能经冒险高 tier 图缴获，保住风险→回报主通道。
- 实现：`get_recruit_offers` 滚装处把 `EquipmentDataManager.get_all_equipment()` 换为「过滤 rarity==0」。可调旋钮（见 §7）。

## 4. 公式 / 数据结构（Formulas / Data）

- `island_tier → 战利品 rarity` 映射（可调）：
  | island_tier | 战利品 rarity |
  |---|---|
  | 1 | 0（普通） |
  | 2 | 1（稀有） |
  | 3 | 2（史诗） |
- RunManager 新增字段：
  - `_route_loot: Dictionary`（`map_id: String → equipment_id: String`）——本批选航候选各自的战利品。
  - `_pending_loot: String`（equipment_id）——所选图待发放的战利品；`""`=无。
- RunManager 新增/改动接口：
  - `get_route_loot_for(map_id: String) -> EquipmentDefinition`（卡面预览读；无则 null）。
  - `get_pending_loot() -> EquipmentDefinition`（LOOT 页读；无则 null）。
  - `assign_loot(crew_id: String) -> void`（装上+清+转 RECRUITING）。
  - `skip_loot() -> void`（清+转 RECRUITING）。
  - `confirm_route` 末尾记 `_pending_loot`、清 `_route_loot`。
  - `get_route_offers` 末尾滚 `_route_loot`。
  - `_on_battle_won` 加 RUN_LOOT 分支。
- `RunPhase` 枚举新增 `RUN_LOOT`；`_PHASE_TO_STRING` 加 `"LOOT"`；`EventBus.run_phase_changed` 可发 `"LOOT"`。

## 5. 边界情况（Edge Cases）

- **目标 rarity 子池为空**：降级到相邻较低 rarity；仍空则该卡无战利品（`_route_loot` 不含该 map_id，卡面显「无」，胜后直接进 RECRUITING）。
- **战利品定义缺失（旧档/数据删除）**：`_pending_loot` 还原时若定义不存在则视为空（不发放）；`_route_loot` 同理双过滤。
- **末岛胜**：不进 LOOT，清 `_pending_loot`；既有 RUN_END 逻辑不受影响。
- **roster 全灭**：走既有 `battle_lost → RUN_END`，永不进 RUN_LOOT。
- **assign_loot 坏 crew_id**：`push_error`，状态不变（停在 RUN_LOOT，UI 不应产生该输入）。
- **续航在 CHARTING / LOOT**：`route_loot`/`pending_loot` 入存档；`_ready` 重入对应分支，CHARTING 经相同 `rng_state` 重抽得同战利品。
- **替换升级是亏的**：玩家可「放弃此战利品」不被迫做亏的替换。

## 6. 依赖（Dependencies）

- `RunManager`（autoload，run 状态机 + 存档）。
- `EquipmentDefinition`（加 rarity 字段）/ `EquipmentDataManager`（autoload，按 rarity 过滤查询）。
- `MapDefinition`（读 `island_tier`，不加新字段）。
- `RouteScene`（新增 LOOT 分支 + CHARTING 卡战利品行）。
- `EventBus.run_phase_changed`（新增发 `"LOOT"`）。
- 既有 UnitInstance 有效值访问器（`get_max_hp` 等，装备增量已生效，无需改）。
- 子项目①的 `get_route_offers` / `confirm_route` / 选航存档（在其上扩展）。

## 7. 可调旋钮（Tuning Knobs）

- `island_tier → rarity` 映射表。
- 每 rarity 的装备件数与增量数值。
- 每卡战利品件数（默认 1）。
- 招募装备是否限普通（默认是；放开则招募可滚全 rarity）。
- 子池空时的降级策略（默认降相邻较低 rarity）。
- 末岛是否发战利品（默认否）。

## 8. 验收标准（Acceptance Criteria）

- **AC-1**：`EquipmentDefinition` 有 `rarity`；装备池含普通/稀有/史诗各 ≥3 件，`EquipmentDataManager` 扫描零校验错、id 唯一、增量可解析。
- **AC-2**：`get_route_offers()` 为每卡确定性滚一件符合该卡 `island_tier→rarity` 的战利品（记入 `_route_loot`）；同 `rng_state` + 同 `_visited_map_ids` 重复调用得同战利品（续航复现）。
- **AC-3**：`get_route_loot_for(map_id)` 返回该卡战利品定义（无则 null）；卡面预览渲染名+稀有度+增量摘要（无战利品显「无」）。
- **AC-4**：`confirm_route(map_id)` 把所选图战利品记入 `_pending_loot`、清 `_route_loot`；其余既有行为不变。
- **AC-5**：非末岛胜 → `RUN_LOOT`；`assign_loot(crew_id)` 把 `_pending_loot` 写入该船员装备（旧丢弃）、清 pending、转 RECRUITING；`skip_loot()` 不改装备、清 pending、转 RECRUITING；坏 crew_id `push_error` 状态不变。
- **AC-6**：末岛胜 → `RUN_END`，不进 LOOT，`_pending_loot` 清空。
- **AC-7**：存档往返保留 `route_loot`/`pending_loot`；缺定义/旧档优雅降级（不崩、不报错）。
- **AC-8**（集成）：端到端经 EventBus/RunManager 驱动——选高 tier 路 → 胜 → `RUN_LOOT` 分配 → 装备增量在后续战斗的有效值（`get_max_hp`/`get_base_damage`/`get_attack_range`/`get_move_range`）中反映。
- **AC-9**（ADVISORY）：F5 人眼——CHARTING 卡战利品预览行 + RUN_LOOT 分配页（战利品展示 + 幸存船员选人 + 放弃按钮）。

## 9. 测试策略（Test Strategy）

- **逻辑（BLOCKING，单测）**：
  - `get_route_offers` 滚战利品：每卡 rarity 匹配 tier、子池空降级、确定性（同 seed 同结果）。
  - `confirm_route`：记 `_pending_loot`、清 `_route_loot`。
  - `assign_loot`/`skip_loot`：装备替换、清 pending、转阶段、坏 id。
  - `_on_battle_won`：非末岛有/无 loot 分支、末岛清 pending 不进 LOOT。
  - `get_recruit_offers` 装备限普通（滚出的 eid 均 rarity==0）。
  - `to_save_dict`/`load_from_save_dict`：`route_loot`/`pending_loot` 往返 + 双过滤。
- **集成（BLOCKING）**：选高 tier 路 → 胜 → 分配 → 后续战斗有效值反映装备增量（AC-8）。
- **数据（ADVISORY smoke）**：新增稀有/史诗装备导入 + `EquipmentDataManager` 校验（AC-1）。
- **UI（ADVISORY）**：RouteScene CHARTING 战利品行 + RUN_LOOT 分配页 F5 人眼（AC-9，沿用白盒惯例，不自动化视觉）。

## 10. 范围边界（Scope）

本子项目**仅**②：装备 rarity 梯度 + tier→rarity 战利品滚装 + 卡面战利品预览 + 战后 RUN_LOOT 分配 + 招募限普通 + 存档。**不含**：③ 新敌人类型/AI（继续用现有 4 种敌人与现有地图），货币/商店/装备买卖，多装备槽/库存（仍一人一件、替换即弃）。
