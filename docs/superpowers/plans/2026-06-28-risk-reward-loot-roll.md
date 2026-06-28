# 风险回报战利品②c Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 战后 8 件候选的稀有度按"刚通关地图 island_tier"加权——越凶险的图战利品越好，并在选航卡预览品阶带。

**Architecture:** 新增纯静态助手 `LootRarity`（tier→稀有度权重表 + 逐件加权抽取 + 品阶带标签）。`roll_battle_equipment` 的随机回退分支改为 tier 加权；`_on_battle_won` 传入刚通关图 tier；RouteScene CHARTING 卡追加品阶带行。零新阶段/数据模型/存档字段。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。Godot：`/Applications/Godot.app/Contents/MacOS/Godot`。

## Global Constraints

- 测试前必先 `godot --headless --import`。全量：`godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`。
- gameplay 数值数据驱动；DI over singletons（rng 注入助手）；静态类型。
- 稀有度枚举：COMMON0/RARE1/EPIC2/ANCIENT3/LEGENDARY4，标签 `["普通","稀有","史诗","稀世","传奇"]`。池分布：普通24/稀有24/史诗16/稀世8/传奇0。
- 基线：full suite 540/540（main HEAD=c497296，本分支 base 同）。spec 已提交本分支。
- 提交引用 `Story: 多地图遭遇epic-子项目②c`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

---

## File Structure

- Create `src/data/loot_rarity.gd` — `class_name LootRarity extends RefCounted`，纯静态：`rarity_weights/weighted_pick/loot_band_label` + `BAND_THRESHOLD`。
- Modify `src/autoloads/run_manager.gd` — `roll_battle_equipment` 加 `island_tier` 参 + 加权回退；`_on_battle_won` 传 tier；新增 `_cleared_island_tier`。
- Modify `src/ui/route_scene.gd` — `_show_route_offers` 卡面追加品阶带。
- Create `tests/unit/loot_rarity/loot_rarity_test.gd` — 助手单测。
- Create `tests/unit/run_equipment/battle_loot_tier_test.gd` — roll_battle 加权 + _cleared_island_tier。
- Create `tests/integration/loot/loot_roll_test.gd` — 端到端 AC-7。

---

### Task 1: LootRarity 纯助手

**Files:**
- Create: `src/data/loot_rarity.gd`
- Test: `tests/unit/loot_rarity/loot_rarity_test.gd`

**Interfaces:**
- Produces: `LootRarity.rarity_weights(island_tier:int) -> Array[int]`（5 元权重）；`LootRarity.weighted_pick(pool:Array, island_tier:int, rng:RandomNumberGenerator) -> EquipmentDefinition`（空池/total<=0→null）；`LootRarity.loot_band_label(island_tier:int) -> String`；`const BAND_THRESHOLD := 15`。

- [ ] **Step 1: 写失败测试** `tests/unit/loot_rarity/loot_rarity_test.gd`

```gdscript
# LootRarity 纯助手：tier→稀有度权重表、逐件加权抽取、品阶带标签。
extends GdUnitTestSuite

func _eq(rarity: int) -> EquipmentDefinition:
	var e := EquipmentDefinition.new()
	e.rarity = rarity
	return e

func test_rarity_weights_known_tiers() -> void:
	assert_array(LootRarity.rarity_weights(1)).is_equal([60, 30, 10, 0, 0])
	assert_array(LootRarity.rarity_weights(2)).is_equal([35, 40, 20, 5, 0])
	assert_array(LootRarity.rarity_weights(3)).is_equal([20, 35, 30, 15, 0])
	assert_array(LootRarity.rarity_weights(5)).is_equal([10, 25, 35, 30, 0])
	assert_array(LootRarity.rarity_weights(6)).is_equal([5, 15, 35, 45, 0])

func test_rarity_weights_unknown_tier_defaults_conservative() -> void:
	assert_array(LootRarity.rarity_weights(4)).is_equal([60, 30, 10, 0, 0])
	assert_array(LootRarity.rarity_weights(99)).is_equal([60, 30, 10, 0, 0])

func test_weighted_pick_empty_pool_returns_null() -> void:
	var rng := RandomNumberGenerator.new()
	assert_object(LootRarity.weighted_pick([], 6, rng)).is_null()

func test_weighted_pick_zero_total_returns_null() -> void:
	# 池只有传奇(权重恒0) → total 0 → null
	var rng := RandomNumberGenerator.new()
	assert_object(LootRarity.weighted_pick([_eq(4)], 6, rng)).is_null()

func test_weighted_pick_single_nonzero_piece_deterministic() -> void:
	# 池只有一件普通，tier6 普通权重 5>0 → 必返回它
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var only := _eq(0)
	assert_object(LootRarity.weighted_pick([only], 6, rng)).is_same(only)

func test_weighted_pick_never_returns_zero_weight_rarity() -> void:
	# 池含普通+传奇，传奇权重恒0 → 永远返回普通
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var common := _eq(0)
	var legend := _eq(4)
	for i in range(20):
		assert_object(LootRarity.weighted_pick([common, legend], 6, rng)).is_same(common)

func test_loot_band_label_thresholded() -> void:
	assert_str(LootRarity.loot_band_label(1)).is_equal("普通~稀有")
	assert_str(LootRarity.loot_band_label(2)).is_equal("普通~史诗")
	assert_str(LootRarity.loot_band_label(3)).is_equal("普通~稀世")
	assert_str(LootRarity.loot_band_label(5)).is_equal("稀有~稀世")
	assert_str(LootRarity.loot_band_label(6)).is_equal("稀有~稀世")
```

- [ ] **Step 2: 跑测试验证失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/loot_rarity`
Expected: FAIL（LootRarity 不存在 → 解析错误）

- [ ] **Step 3: 实现** `src/data/loot_rarity.gd`

```gdscript
# 战利品稀有度加权助手（risk-reward ②c）：纯静态无状态。
# 通关地图 island_tier → 稀有度权重 → 战后候选逐件加权抽取。
class_name LootRarity
extends RefCounted

# tier → 5 稀有度 [普通0,稀有1,史诗2,稀世3,传奇4] 权重。传奇恒 0（池无件）。
const TIER_WEIGHTS := {
	1: [60, 30, 10, 0, 0],
	2: [35, 40, 20, 5, 0],
	3: [20, 35, 30, 15, 0],
	5: [10, 25, 35, 30, 0],
	6: [5, 15, 35, 45, 0],
}
const DEFAULT_WEIGHTS := [60, 30, 10, 0, 0]   # 未知 tier 保守
const BAND_THRESHOLD := 15                      # 品阶带显示阈值

static func rarity_weights(island_tier: int) -> Array[int]:
	var raw: Array = TIER_WEIGHTS.get(island_tier, DEFAULT_WEIGHTS)
	var out: Array[int] = []
	for w in raw:
		out.append(int(w))
	return out

# 逐件按其稀有度权重加权随机抽一件；空池 / total<=0 → null。
static func weighted_pick(pool: Array, island_tier: int, rng: RandomNumberGenerator) -> EquipmentDefinition:
	if pool.is_empty():
		return null
	var weights := rarity_weights(island_tier)
	var total := 0
	for piece in pool:
		total += weights[clampi((piece as EquipmentDefinition).rarity, 0, 4)]
	if total <= 0:
		return null
	var r := rng.randi_range(0, total - 1)
	var acc := 0
	for piece in pool:
		acc += weights[clampi((piece as EquipmentDefinition).rarity, 0, 4)]
		if r < acc:
			return piece as EquipmentDefinition
	return pool[pool.size() - 1] as EquipmentDefinition   # 浮点/边界兜底

# 该 tier 权重 ≥ BAND_THRESHOLD 的稀有度区间中文标签（最低~最高，单档显一档）。
static func loot_band_label(island_tier: int) -> String:
	var weights := rarity_weights(island_tier)
	var lo := -1
	var hi := -1
	for i in range(weights.size()):
		if weights[i] >= BAND_THRESHOLD:
			if lo < 0:
				lo = i
			hi = i
	if lo < 0:
		return "无"
	if lo == hi:
		return EquipmentDefinition.rarity_label(lo)
	return "%s~%s" % [EquipmentDefinition.rarity_label(lo), EquipmentDefinition.rarity_label(hi)]
```

- [ ] **Step 4: 跑测试验证通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/loot_rarity`
Expected: PASS（8/8）

- [ ] **Step 5: 提交**

```bash
git add src/data/loot_rarity.gd tests/unit/loot_rarity/
git commit -m "feat(loot): LootRarity 纯助手 — tier→稀有度权重 + 加权抽取 + 品阶带

Story: 多地图遭遇epic-子项目②c
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: roll_battle_equipment tier 加权 + _on_battle_won 传 tier

**Files:**
- Modify: `src/autoloads/run_manager.gd`（`roll_battle_equipment` line 249-273、`_on_battle_won` line 407、新增 `_cleared_island_tier`）
- Test: `tests/unit/run_equipment/battle_loot_tier_test.gd`

**Interfaces:**
- Consumes: Task 1 `LootRarity.weighted_pick`。
- Produces: `roll_battle_equipment(crew_id:String, island_tier:int=1)`；`_cleared_island_tier() -> int`。

- [ ] **Step 1: 写失败测试** `tests/unit/run_equipment/battle_loot_tier_test.gd`

```gdscript
# 战后滚装 tier 加权 + 通关图 tier 解析。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()

func _rarity_sum(eids: Array) -> int:
	var s := 0
	for eid in eids:
		var def := EquipmentDataManager.get_equipment(eid)
		if def != null:
			s += def.rarity
	return s

func test_high_tier_rolls_higher_rarity_than_tier1() -> void:
	# c1 无装备 → dominant="" → 8 件全走加权回退（无主套偏向干扰）。
	RunManager._rng.seed = 777
	var low := RunManager.roll_battle_equipment("c1", 1)
	RunManager._rng.seed = 777
	var high := RunManager.roll_battle_equipment("c1", 6)
	assert_int(_rarity_sum(high)).is_greater(_rarity_sum(low))

func test_roll_still_returns_eight_with_tier() -> void:
	RunManager._rng.seed = 777
	assert_int(RunManager.roll_battle_equipment("c1", 6).size()).is_equal(8)

func test_cleared_island_tier_reads_chosen_map() -> void:
	RunManager._chosen_map_id = "battle_map_009"   # island_tier 6
	assert_int(RunManager._cleared_island_tier()).is_equal(6)

func test_cleared_island_tier_missing_map_defaults_one() -> void:
	RunManager._chosen_map_id = ""
	assert_int(RunManager._cleared_island_tier()).is_equal(1)
```

- [ ] **Step 2: 跑测试验证失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_equipment/battle_loot_tier_test.gd`
Expected: FAIL（`roll_battle_equipment` 不接受第 2 参 / `_cleared_island_tier` 不存在）

- [ ] **Step 3: 改实现** `src/autoloads/run_manager.gd`

(a) `roll_battle_equipment` 签名与回退分支：
```gdscript
func roll_battle_equipment(crew_id: String, island_tier: int = 1) -> Array[String]:
```
把回退分支（原 `if pick == null: pick = all[_rng.randi_range(0, all.size() - 1)]`）改为：
```gdscript
		if pick == null:
			pick = LootRarity.weighted_pick(all, island_tier, _rng)
			if pick == null:
				pick = all[_rng.randi_range(0, all.size() - 1)]
```

(b) `_on_battle_won` 非末岛分支（line 407）：
```gdscript
			_pending_battle_equip[c.id] = roll_battle_equipment(c.id, _cleared_island_tier())
```

(c) 新增私有助手（置于 `roll_battle_equipment` 附近）：
```gdscript
# 刚通关地图的 island_tier（战利品加权用）；缺图/未选图 → 1。
func _cleared_island_tier() -> int:
	var m := MapDataManager.get_map(_chosen_map_id)
	return (m as MapDefinition).island_tier if m != null else 1
```

- [ ] **Step 4: 跑测试验证通过**

Run: 全量 `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: 新 4 测试 PASS；既有 `battle_equip_test`（size==8、主套偏向 same>4）仍 PASS（加默认参 + 每迭代 rng 抽取数不变 → 流对齐）。0 errors/failures/orphans。

> 若 `test_high_tier_rolls_higher_rarity_than_tier1` 因 seed 罕见持平而红，换 seed（如 1234）重试——稀有度和（非计数）对 tier 单调，几乎不可能持平；持平即说明 seed 极端，换即可。

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_equipment/battle_loot_tier_test.gd
git commit -m "feat(loot): 战后候选按通关图 island_tier 加权稀有度

Story: 多地图遭遇epic-子项目②c
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 选航卡战利品品阶带（RouteScene）

**Files:**
- Modify: `src/ui/route_scene.gd`（`_show_route_offers` 卡面文本 line ~203）

**Interfaces:**
- Consumes: Task 1 `LootRarity.loot_band_label`。

- [ ] **Step 1: 改实现**（whitebox UI，无自动化断言；F5 ADVISORY）

把卡面文本行：
```gdscript
		btn.text = "%s · 难度%d · %s" % [map_def.display_name, map_def.island_tier, _enemy_summary(map_def)]
```
改为：
```gdscript
		btn.text = "%s · 难度%d · %s · 战利品：%s" % [map_def.display_name, map_def.island_tier, _enemy_summary(map_def), LootRarity.loot_band_label(map_def.island_tier)]
```

- [ ] **Step 2: 导入零错 + 全量绿**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: 导入零错（route_scene 解析过）；全量绿不变（UI 文本改动无既有断言耦合——确认 route_scene 测试不断言 btn.text 完整串；若有则诚实更新）。

- [ ] **Step 3: 提交**

```bash
git add src/ui/route_scene.gd
git commit -m "feat(loot): 选航卡追加战利品品阶带预览（CHARTING，F5 ADVISORY）

Story: 多地图遭遇epic-子项目②c
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 集成端到端 + 全量验证

**Files:**
- Create: `tests/integration/loot/loot_roll_test.gd`

**Interfaces:**
- Consumes: 全链路 RunManager + LootRarity。

- [ ] **Step 1: 写集成测试** `tests/integration/loot/loot_roll_test.gd`

```gdscript
# AC-7：选高 tier 图 → 通关 → 战后候选稀有度偏高（端到端经 RunManager）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()

func _rarity_sum(eids: Array) -> int:
	var s := 0
	for eid in eids:
		var def := EquipmentDataManager.get_equipment(eid)
		if def != null:
			s += def.rarity
	return s

func test_high_tier_clear_yields_richer_candidates() -> void:
	RunManager._rng.seed = 2024
	RunManager._chosen_map_id = "battle_map_001"   # tier1
	var low := RunManager.roll_battle_equipment("hero", RunManager._cleared_island_tier())
	RunManager._rng.seed = 2024
	RunManager._chosen_map_id = "battle_map_009"   # tier6
	var high := RunManager.roll_battle_equipment("hero", RunManager._cleared_island_tier())
	assert_int(_rarity_sum(high)).is_greater(_rarity_sum(low))
```

- [ ] **Step 2: 跑集成 + 全量**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: PASS，0 errors/failures/orphans，导入零错。总数 540 + LootRarity 8 + battle_loot_tier 4 + loot_roll 1 = 553（若 route_scene 测试需改则微调）。

- [ ] **Step 3: 记录 progress.md**（final-review + 验证条目，供合并）

---

## Self-Review

**1. Spec coverage：** §3.1 权重表→T1；§3.2 weighted_pick→T1；§3.3 roll 加权→T2；§3.4 _on_battle_won/_cleared_island_tier→T2；§3.5 卡面品阶带→T3；§3.6 不变更（roll_initial 不碰、末岛不滚、招募中性）→未改即满足；AC-7 集成→T4；AC-8 全量→T4；AC-9 F5→人眼。

**2. Placeholder scan：** 无 TBD/TODO；每步给完整代码。T3「确认 route_scene 测试不断言 btn.text」是核查指令（执行 grep），非占位符。

**3. Type consistency：** `rarity_weights -> Array[int]`、`weighted_pick -> EquipmentDefinition`、`loot_band_label -> String`、`roll_battle_equipment(String, int=1)`、`_cleared_island_tier() -> int` 在 T1/T2/T4 一致；`EquipmentDefinition.rarity_label`（既有静态）在 loot_band_label 复用。

**4. 已知风险：** ① roll_battle_equipment rng 流对齐（每迭代 1 bias 抽 + 1 pick 抽，加权 pick 同样 1 抽 → 既有 battle_equip_test 不破，已分析）；② 加权稀有度和单调对 tier 成立但 seed 罕见持平 → 换 seed（T2/T4 Step 已注）。
