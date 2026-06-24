# 海图选航骨架 + 多地图（子项目①）设计

> Story: chart-course-multi-map（多地图/遭遇 epic 子项目①）
> 日期：2026-06-24
> 引擎：Godot 4.6.3 / GDScript / GdUnit4

## 1. 概述（Overview）

把战斗地图从写死的单图（`battle_map_001`）改造成**玩家驱动的多地图选航**。一次 run 的每场战斗前，玩家从 3 张目的地（海图）卡中选 1 张，决定本岛打哪张地图、面对什么敌情。这是"多战斗地图/遭遇"epic 的脊柱（子项目①），后续②风险↔回报奖励经济、③新敌人类型挂靠其上。本子项目**用现有 4 种敌人**，端到端走通选航循环。

## 2. 玩家体验（Player Fantasy）

身为船长，在每段航程出发前摊开海图，在数条航线中权衡——哪片海域更凶险、敌情如何——亲手为这次远征选定目的地。run 之间因随机航点而各不相同，决策有重量。

## 3. 详细规则（Detailed Rules）

### 3.1 阶段与流程
新增 `CHARTING`（选航）阶段。**全程选航**——每场战斗前都经选航。每岛序列：

```
首岛(index 0):    start_run → CHARTING → DEPLOYING → BATTLE
其余岛(index 1-4): BATTLE胜 → RECRUITING → 选员 → CHARTING → DEPLOYING → BATTLE
末岛(index 4)胜:   → RUN_END（既有逻辑：通关+解锁，不变）
```

- 招募候选/确认逻辑（`get_recruit_offers`/`confirm_recruit` 的 roster/装备/排除处理）完全不动，**仅改其末尾的目标阶段**：原 `confirm_recruit` 末转 `DEPLOYING`，现改为转 `CHARTING`。
- 同理 `start_run` 原末转 `DEPLOYING`，现改为转 `CHARTING`（首岛无招募，直接进选航）。
- 选航插在招募之后、部署之前；在 RouteScene 内串场，与现有"招募→部署"同模式（同一次 RouteScene 访问内推进）。
- 转阶段链总览：`start_run → CHARTING`；`confirm_recruit → CHARTING`；`confirm_route → DEPLOYING`；`confirm_deploy → BATTLE`（递增 index，不变）。

### 3.2 选航候选生成（确定性）
- 即将抵达的岛号 `next_idx = current_island_index + 1`（首岛 = 0；`confirm_deploy` 才递增 `current_island_index`，故选航期 `next_idx` 指向即将打的岛）。
- 由 `next_idx` 定**目标 tier**（可调）：
  | next_idx | 目标 tier |
  |---|---|
  | 0 | t1 |
  | 1, 2 | t1–t2 |
  | 3 | t2–t3 |
  | 4 | t3 |
- 从地图池按目标 tier 过滤 → `_rng` Fisher-Yates 洗牌 → 取前 3 张，且**互不为本 run 已访问**（`_visited_map_ids`）。
- 合规候选不足 3 张时：放宽到相邻 tier 补足，再不足则允许少于 3 张（优雅降级，小池不崩、不报错）。
- 全程走 RunManager 持有的 `_rng`，存档 `rng_state` 复现 → 续航重抽得到同 3 张。

### 3.3 选航确认
- `confirm_route(map_id)`：记 `_chosen_map_id = map_id`、把 `map_id` 加入 `_visited_map_ids`、清 `_last_route_offers`、转 `RUN_DEPLOYING`。
- 非法 `map_id`（不在本批候选/无定义）：`push_error` 且不改状态（仿 `confirm_recruit` 坏 id 处理）。

### 3.4 战斗读图
- `battle_map.load_map()` 改读 `RunManager.get_chosen_map_id()`；为空时回退 `MVP_MAP_ID = "battle_map_001"`（保测试与异常安全）。
- 其余部署/校验流程（`load_map_definition`）不变。

### 3.5 RouteScene 选航 UI（白盒，ADVISORY）
- `_ready()` 的 `match RunManager.current_phase` 新增 `"CHARTING"` 分支 → `_show_route_offers()`。
- 每张卡白盒显示：地名（`display_name`）、难度（`island_tier`）、敌情摘要（按 `enemy_roster` 的 `behavior_type` 计数，如"近战×2 远程×1 守卫×1"）、一个"选择"按钮。
- 选择 → `RunManager.confirm_route(map_id)` → `_enter_deploy()`（与招募后同路径）。
- 全部交互通过按钮完成，无自由输入。

## 4. 公式 / 数据结构（Formulas / Data）

- `next_idx = current_island_index + 1`
- 目标 tier 映射表见 §3.2（`island_tier` 为 1 起的整数）。
- 敌情摘要：对 `map_def.enemy_roster` 中每个 slot 的 `behavior_type` 计数，映射中文标签（MELEE→近战 / RANGED→远程 / SWARMER→突击 / GUARDIAN→守卫）。
- **MapDefinition 不加新字段**：复用 `display_name`、`island_tier`、`enemy_roster`。风险展示由 tier + 敌情计数派生。
- 地图内容：新作 **6 张地图**（`battle_map_002..007`）+ 复用 `battle_map_001`，共 7 张：**tier1×3、tier2×2、tier3×2**（001 计为 tier1）。各图用现有 `enemy_{melee,ranged,swarmer,guardian}_tier1` 改数量/站位/组合做出难度与战术差异（数量与威胁随 tier 升）。具体编成可在实现计划期微调。

## 5. 边界情况（Edge Cases）

- **地图池空 / 不足 3 张**：放宽相邻 tier 补足；仍不足则返回 <3 张候选（UI 渲染实际张数）；池完全空则 `get_chosen_map_id` 为空 → `load_map` 回退 001，不崩。
- **续航在 CHARTING**：存档持 `phase=CHARTING` + `rng_state` + `visited_map_ids` + `last_route_offers`；`_ready` 重入 CHARTING 分支，`get_route_offers` 由相同 rng 重抽得同候选。
- **末岛胜**：仍走既有 `_on_battle_won` 末岛分支（`RUN_END` + `MetaProgress.unlock_next`），选航不介入终局。
- **非法/过期 map_id 确认**：`push_error`，状态不变。
- **已访问导致无新图**：降级允许重复（相邻 tier 也被访问完时），保证仍能继续 run。

## 6. 依赖（Dependencies）

- `RunManager`（autoload，run 状态机 + 存档）。
- `MapDataManager`（autoload，按 id 扫描 MapDefinition）。
- `MapDefinition` / `EnemySlotDefinition` 资源。
- `battle_map.gd`（`load_map`）。
- `RouteScene`（阶段分支 UI）。
- `EventBus.run_phase_changed`（新增发 `"CHARTING"`）。
- 现有 4 种敌人定义（`enemy_*_tier1`）。

## 7. 可调旋钮（Tuning Knobs）

- `next_idx → 目标 tier` 映射表。
- 候选张数（默认 3，常量 `ROUTE_OFFER_COUNT`）。
- 地图总数与各 tier 分布。
- 各地图敌人编成（数量/站位/类型）。
- 是否允许本 run 重复地图（默认不重复，降级时放宽）。

## 8. 验收标准（Acceptance Criteria）

- **AC-1**：`get_route_offers()` 返回 ≤3 张候选，全部属当前 `next_idx` 的目标 tier（池足时），且本 run 互不重复。
- **AC-2**：候选生成确定性——同 `rng_state` + 同 `_visited_map_ids` 重复调用得同结果（续航可复现）。
- **AC-3**：合规候选不足时优雅降级（相邻 tier 补足 / 返回 <3 张），不报错不崩。
- **AC-4**：`confirm_route(map_id)` 记 `_chosen_map_id`、标记已访问、转 `DEPLOYING`；非法 id `push_error` 且状态不变。
- **AC-5**：`battle_map.load_map()` 加载 `get_chosen_map_id()` 指定的图；为空回退 `battle_map_001`。
- **AC-6**：全程选航流程端到端——经 RunManager 驱动可走完首岛 CHARTING→部署→战斗→（胜）招募→CHARTING…直到末岛胜 RUN_END，期间每岛地图由选航决定。
- **AC-7**：存档往返保留 `chosen_map_id` / `visited_map_ids` / `last_route_offers`；在 CHARTING 阶段自动存盘，重载后重入 CHARTING 并重抽同候选。
- **AC-8**（ADVISORY）：F5 人眼——RouteScene 选航页渲染 3 张白盒卡（地名/难度/敌情/选择按钮），选择后进入部署。
- **AC-9**：新增 6 张地图资源经 `MapDataManager` 扫描零校验错误、`map_id` 唯一、敌人 id 均可解析。

## 9. 测试策略（Test Strategy）

- **逻辑（BLOCKING，单测）**：`get_route_offers`（数量/tier 过滤/不重复/降级/确定性）、`confirm_route`（记图+转阶段+排除+坏 id）、`battle_map.load_map`（读所选图+回退）、`to_save_dict`/`load_from_save_dict`（新字段往返）。
- **集成（BLOCKING）**：全程选航端到端经 EventBus/RunManager 驱动走完 5 岛（AC-6）。
- **数据（ADVISORY smoke）**：6 张新图导入 + `MapDataManager` 校验（AC-9）。
- **UI（ADVISORY）**：RouteScene CHARTING 卡 F5 人眼（AC-8，沿用白盒惯例，不自动化视觉）。

## 10. 范围边界（Scope）

本子项目**仅**①：选航阶段 + 候选生成 + 选图接入战斗 + 选航 UI + 多地图数据（现有敌人）。**不含**：②风险↔回报奖励经济（卡仅展示风险，不发奖励）、③新敌人类型/AI。`get_route_offers` 返回结构对②保持可扩展（后续追加 reward 负载）。
