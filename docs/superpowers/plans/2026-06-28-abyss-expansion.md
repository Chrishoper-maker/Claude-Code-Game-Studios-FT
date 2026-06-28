# 深渊扩展（史诗②）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 4 个 tier3 敌方原型 + 2 张 island_tier 5/6 深层地图，并调整路线映射让一局 run 后两岛真正抵达深层硬仗。

**Architecture:** 纯数据增量（4 个 EnemyDefinition `.tres` + 2 个 MapDefinition `.tres`，目录扫描自动纳入）+ 一处路线映射函数调整（`RunManager._target_tiers_for_island`）。零新代码系统。`_allowed_threat_tiers`（已支持 5/6）、`EnemyLoadout`（island_tier≥4→9 件）、Rule3 验证、战斗/AI/解算/crew 全部不改。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。Godot 二进制：`/Applications/Godot.app/Contents/MacOS/Godot`。

## Global Constraints

- 引擎 Godot 4.6.3；测试前必先 `godot --headless --import` 建全局类名缓存。
- 全量测试命令：`godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`。
- gameplay 数值必须数据驱动（`.tres`），不硬编码。
- 测试命名 `test_[scenario]_[expected]`；arrange/act/assert；确定性；自隔离。
- `.tres` 手写格式：`[gd_resource type="Resource" script_class="X" load_steps=N format=3]` + `[ext_resource type="Script" path=...]` + 子资源 `[sub_resource type="Resource" id=...]`；typed array 用 `Array[TerrainCell]([...])`（类名）。Godot 4.6 不为 `.tres` 生成 `.uid` 旁车（只 `.gd` 有）。
- 当前基线：full suite 528/528（含 spec 提交在 feature/abyss-expansion 分支上，base=6c3f8fd）。
- 提交信息引用 `Story: 高threat_tier原型史诗-子项目②`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

---

## File Structure

- Create `assets/data/units/enemy_{melee,ranged,swarmer,guardian}_tier3.tres` — 4 个 tier3 EnemyDefinition。
- Create `assets/data/maps/battle_map_008.tres`（深渊门廊 island_tier5）、`battle_map_009.tres`（渊心王座 island_tier6）。
- Modify `src/autoloads/run_manager.gd`（`_target_tiers_for_island` 函数体，约 298-303 行）。
- Create `tests/unit/enemy_tier3/enemy_tier3_test.gd` — tier3 数据校验。
- Create `tests/unit/battle_map/battle_map_abyss_maps_test.gd` — 008/009 数据 + Rule3 + loadout。
- Modify `tests/unit/run_manager/route_offers_test.gd:58-64` — 诚实更新 `test_target_tiers_mapping` 断言。

---

### Task 1: tier3 敌方原型（4 个 .tres）

**Files:**
- Create: `assets/data/units/enemy_melee_tier3.tres`, `enemy_ranged_tier3.tres`, `enemy_swarmer_tier3.tres`, `enemy_guardian_tier3.tres`
- Test: `tests/unit/enemy_tier3/enemy_tier3_test.gd`

**Interfaces:**
- Consumes: `UnitDataManager.get_unit(id) -> UnitDefinition`（autoload，目录扫描）；`EnemyDefinition` 字段 `max_hp/base_damage/attack_range/move_range/unit_class/behavior_type/threat_tier/faction/display_name`。
- Produces: 4 个可经 `get_unit` 取得的 EnemyDefinition，id 为 `enemy_{melee,ranged,swarmer,guardian}_tier3`，数值见 spec §3.2。供 Task 2 地图 enemy_roster 引用。

- [ ] **Step 1: 写失败测试** `tests/unit/enemy_tier3/enemy_tier3_test.gd`

```gdscript
# tier3 敌方原型数据校验：经 UnitDataManager 取得、类型/字段正确（spec §3.2）。
extends GdUnitTestSuite

func _enemy(id: String) -> EnemyDefinition:
	return UnitDataManager.get_unit(id) as EnemyDefinition

func test_melee_tier3_fields() -> void:
	var e := _enemy("enemy_melee_tier3")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(3)
	assert_int(e.max_hp).is_equal(12)
	assert_int(e.base_damage).is_equal(5)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(2)
	assert_str(e.unit_class).is_equal("swordsman")
	assert_str(e.behavior_type).is_equal("MELEE")

func test_ranged_tier3_fields() -> void:
	var e := _enemy("enemy_ranged_tier3")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(3)
	assert_int(e.max_hp).is_equal(11)
	assert_int(e.base_damage).is_equal(5)
	assert_int(e.attack_range).is_equal(3)
	assert_int(e.move_range).is_equal(2)
	assert_str(e.unit_class).is_equal("gunner")
	assert_str(e.behavior_type).is_equal("RANGED")

func test_swarmer_tier3_fields() -> void:
	var e := _enemy("enemy_swarmer_tier3")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(3)
	assert_int(e.max_hp).is_equal(8)
	assert_int(e.base_damage).is_equal(4)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(3)
	assert_str(e.unit_class).is_equal("swordsman")
	assert_str(e.behavior_type).is_equal("SWARMER")

func test_guardian_tier3_fields() -> void:
	var e := _enemy("enemy_guardian_tier3")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(3)
	assert_int(e.max_hp).is_equal(16)
	assert_int(e.base_damage).is_equal(4)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(1)
	assert_str(e.unit_class).is_equal("bulwark")
	assert_str(e.behavior_type).is_equal("GUARDIAN")
```

- [ ] **Step 2: 跑测试验证失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/enemy_tier3`
Expected: FAIL（4 测试 — `_enemy` 返回 null → is_not_null 失败）

- [ ] **Step 3: 创建 4 个 .tres**（参照 `enemy_melee_tier2.tres` 结构，仅改 id/数值/display_name）

`enemy_melee_tier3.tres`:
```
[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/enemy_definition.gd" id="1"]

[resource]
script = ExtResource("1")
unit_id = "enemy_melee_tier3"
display_name = "近战兵·将官"
unit_class = "swordsman"
faction = "enemy"
max_hp = 12
move_range = 2
attack_range = 1
base_damage = 5
class_action_id = ""
behavior_type = "MELEE"
threat_tier = 3
```

`enemy_ranged_tier3.tres`:
```
[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/enemy_definition.gd" id="1"]

[resource]
script = ExtResource("1")
unit_id = "enemy_ranged_tier3"
display_name = "炮击兵·将官"
unit_class = "gunner"
faction = "enemy"
max_hp = 11
move_range = 2
attack_range = 3
base_damage = 5
class_action_id = ""
behavior_type = "RANGED"
threat_tier = 3
```

`enemy_swarmer_tier3.tres`:
```
[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/enemy_definition.gd" id="1"]

[resource]
script = ExtResource("1")
unit_id = "enemy_swarmer_tier3"
display_name = "群攻兵·将官"
unit_class = "swordsman"
faction = "enemy"
max_hp = 8
move_range = 3
attack_range = 1
base_damage = 4
class_action_id = ""
behavior_type = "SWARMER"
threat_tier = 3
```

`enemy_guardian_tier3.tres`:
```
[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/enemy_definition.gd" id="1"]

[resource]
script = ExtResource("1")
unit_id = "enemy_guardian_tier3"
display_name = "守卫兵·将官"
unit_class = "bulwark"
faction = "enemy"
max_hp = 16
move_range = 1
attack_range = 1
base_damage = 4
class_action_id = ""
behavior_type = "GUARDIAN"
threat_tier = 3
```

> ⚠️ 字段名以 `enemy_melee_tier2.tres` 实际内容为准（先 `cat` 对照一份 tier2，逐字段命名一致：`unit_id`/`display_name`/`unit_class`/`faction`/`max_hp`/`move_range`/`attack_range`/`base_damage`/`class_action_id`/`behavior_type`/`threat_tier`）。若 tier2 有额外字段（如 `class_action_id`）一并对齐。

- [ ] **Step 4: 跑测试验证通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/enemy_tier3`
Expected: PASS（4/4）

- [ ] **Step 5: 提交**

```bash
git add assets/data/units/enemy_*_tier3.tres tests/unit/enemy_tier3/
git commit -m "feat(data): tier3 敌方原型（将官级，threat_tier=3）

Story: 高threat_tier原型史诗-子项目②
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: island_tier 5/6 深层地图（008/009）

**Files:**
- Create: `assets/data/maps/battle_map_008.tres`, `assets/data/maps/battle_map_009.tres`
- Test: `tests/unit/battle_map/battle_map_abyss_maps_test.gd`

**Interfaces:**
- Consumes: Task 1 的 tier3 enemy id；`MapDataManager.get_map(id) -> MapDefinition`；`MapDataManager.get_maps_for_tier(t) -> Array[MapDefinition]`；`BattleMap.load_map_definition(map_def, grid_board, turn_manager) -> bool`（true=Rule3 全过）；`UnitInstance.equipment: Dictionary`、`.definition.threat_tier`。
- Produces: 008（island_tier5）/009（island_tier6）两图，供 Task 3 路线映射定向抵达。

- [ ] **Step 1: 写失败测试** `tests/unit/battle_map/battle_map_abyss_maps_test.gd`

```gdscript
# 深层图 008(island_tier5 混编)/009(island_tier6 满编全 tier3)：数据 + Rule3 + loadout。
extends GdUnitTestSuite

func _load_ok(map_id: String) -> bool:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	return bm.load_map_definition(MapDataManager.get_map(map_id), gb, tm)

func _deployed_first_enemy(map_id: String) -> UnitInstance:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	bm.load_map_definition(MapDataManager.get_map(map_id), gb, tm)
	return tm.get_unit(tm.get_alive_enemies()[0])

func test_map_008_is_tier5() -> void:
	var m := MapDataManager.get_map("battle_map_008") as MapDefinition
	assert_object(m).is_not_null()
	assert_int(m.island_tier).is_equal(5)

func test_map_009_is_tier6() -> void:
	var m := MapDataManager.get_map("battle_map_009") as MapDefinition
	assert_object(m).is_not_null()
	assert_int(m.island_tier).is_equal(6)

func test_map_009_roster_all_tier3() -> void:
	var m := MapDataManager.get_map("battle_map_009") as MapDefinition
	for slot in m.enemy_roster:
		assert_str(slot.unit_definition_id).ends_with("_tier3")

func test_map_008_passes_rule3() -> void:
	assert_bool(_load_ok("battle_map_008")).is_true()

func test_map_009_passes_rule3() -> void:
	assert_bool(_load_ok("battle_map_009")).is_true()

func test_get_maps_for_tier_5_contains_008() -> void:
	var ids: Array[String] = []
	for m in MapDataManager.get_maps_for_tier(5):
		ids.append(m.map_id)
	assert_array(ids).contains(["battle_map_008"])

func test_get_maps_for_tier_6_contains_009() -> void:
	var ids: Array[String] = []
	for m in MapDataManager.get_maps_for_tier(6):
		ids.append(m.map_id)
	assert_array(ids).contains(["battle_map_009"])

func test_deployed_009_enemy_is_tier3_with_nine_piece_loadout() -> void:
	var e := _deployed_first_enemy("battle_map_009")
	assert_int(e.definition.threat_tier).is_equal(3)
	assert_int(e.equipment.size()).is_equal(9)
```

- [ ] **Step 2: 跑测试验证失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_abyss_maps_test.gd`
Expected: FAIL（get_map 返回 null）

- [ ] **Step 3: 创建 008/009 .tres**（参照 `battle_map_006.tres` 结构）

`battle_map_008.tres`（深渊门廊 island_tier5，5 敌混编）:
```
[gd_resource type="Resource" script_class="MapDefinition" load_steps=8 format=3]

[ext_resource type="Script" path="res://src/data/map_definition.gd" id="1"]
[ext_resource type="Script" path="res://src/data/enemy_slot_definition.gd" id="3"]

[sub_resource type="Resource" id="s1"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier3"
grid_position = Vector2i(1, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s2"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier3"
grid_position = Vector2i(6, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s3"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier2"
grid_position = Vector2i(0, 1)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s4"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier2"
grid_position = Vector2i(7, 1)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s5"]
script = ExtResource("3")
unit_definition_id = "enemy_guardian_tier3"
grid_position = Vector2i(4, 3)
behavior_type = "GUARDIAN"
home_pos = Vector2i(4, 3)

[resource]
script = ExtResource("1")
map_id = "battle_map_008"
display_name = "深渊门廊"
terrain_data = Array[TerrainCell]([])
deploy_zone = Array[Vector2i]([Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)])
enemy_roster = Array[EnemySlotDefinition]([SubResource("s1"), SubResource("s2"), SubResource("s3"), SubResource("s4"), SubResource("s5")])
island_tier = 5
annotated_engagement_distance = {}
map_scene_id = ""
```

`battle_map_009.tres`（渊心王座 island_tier6，6 敌满编全 tier3）:
```
[gd_resource type="Resource" script_class="MapDefinition" load_steps=9 format=3]

[ext_resource type="Script" path="res://src/data/map_definition.gd" id="1"]
[ext_resource type="Script" path="res://src/data/enemy_slot_definition.gd" id="3"]

[sub_resource type="Resource" id="s1"]
script = ExtResource("3")
unit_definition_id = "enemy_guardian_tier3"
grid_position = Vector2i(3, 2)
behavior_type = "GUARDIAN"
home_pos = Vector2i(3, 2)

[sub_resource type="Resource" id="s2"]
script = ExtResource("3")
unit_definition_id = "enemy_guardian_tier3"
grid_position = Vector2i(4, 2)
behavior_type = "GUARDIAN"
home_pos = Vector2i(4, 2)

[sub_resource type="Resource" id="s3"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier3"
grid_position = Vector2i(1, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s4"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier3"
grid_position = Vector2i(6, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s5"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier3"
grid_position = Vector2i(0, 1)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s6"]
script = ExtResource("3")
unit_definition_id = "enemy_swarmer_tier3"
grid_position = Vector2i(7, 3)
behavior_type = "SWARMER"
home_pos = Vector2i(-1, -1)

[resource]
script = ExtResource("1")
map_id = "battle_map_009"
display_name = "渊心王座"
terrain_data = Array[TerrainCell]([])
deploy_zone = Array[Vector2i]([Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7)])
enemy_roster = Array[EnemySlotDefinition]([SubResource("s1"), SubResource("s2"), SubResource("s3"), SubResource("s4"), SubResource("s5"), SubResource("s6")])
island_tier = 6
annotated_engagement_distance = {}
map_scene_id = ""
```

> ⚠️ 字段名/子资源结构以 `battle_map_006.tres` 实际内容为准（先 `cat` 对照）。`load_steps` = 1(script) + 1(slot script) + N(子资源) + ... 取与 006 同算法；不确定时可设足够大值，Godot 会忽略多余。`TerrainCell` 类名须可解析（006 已用空数组 `Array[TerrainCell]([])`）。

- [ ] **Step 4: 跑测试验证通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_abyss_maps_test.gd`
Expected: PASS（8/8）。若 Rule3 测试失败，读返回的 reason（在 BattleMap.validate_map），按 §3.3 自检表调整敌人位置/部署区，不放宽 Rule3。

- [ ] **Step 5: 提交**

```bash
git add assets/data/maps/battle_map_008.tres assets/data/maps/battle_map_009.tres tests/unit/battle_map/battle_map_abyss_maps_test.gd
git commit -m "feat(data): island_tier 5/6 深层地图 008/009（深渊门廊/渊心王座）

Story: 高threat_tier原型史诗-子项目②
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 路线可达（`_target_tiers_for_island` 爬升到 5/6）

**Files:**
- Modify: `src/autoloads/run_manager.gd`（`_target_tiers_for_island`，约 298-303 行）
- Modify: `tests/unit/run_manager/route_offers_test.gd:58-64`（`test_target_tiers_mapping`）

**Interfaces:**
- Consumes: 无新依赖。
- Produces: `_target_tiers_for_island(next_idx)` 新映射 next_idx 0..4 = [1]/[1,2]/[2,3]/[3,5]/[5,6]。`get_route_offers` 降级逻辑不变。

- [ ] **Step 1: 改测试断言（先改测试 = 新行为规格）** `tests/unit/run_manager/route_offers_test.gd:58-64`

把 `test_target_tiers_mapping` 函数体替换为：
```gdscript
# 目标 tier 映射表（纯函数）— 后两岛爬升到深层 5/6（史诗②）。
func test_target_tiers_mapping() -> void:
	assert_array(RunManager._target_tiers_for_island(0)).is_equal([1])
	assert_array(RunManager._target_tiers_for_island(1)).is_equal([1, 2])
	assert_array(RunManager._target_tiers_for_island(2)).is_equal([2, 3])
	assert_array(RunManager._target_tiers_for_island(3)).is_equal([3, 5])
	assert_array(RunManager._target_tiers_for_island(4)).is_equal([5, 6])
```

- [ ] **Step 2: 跑测试验证失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/route_offers_test.gd`
Expected: `test_target_tiers_mapping` FAIL（next_idx 2/3/4 旧值不匹配新断言）；其余 route_offers 测试仍 PASS。

- [ ] **Step 3: 改实现** `src/autoloads/run_manager.gd` 的 `_target_tiers_for_island`

把函数体替换为：
```gdscript
# 即将抵达岛号 → 目标 island_tier 集合（可调）。next_idx = current_island_index + 1。
# 后两岛爬升到深层 5/6（史诗②深渊扩展）；深层图不足时 get_route_offers 降级兜底。
func _target_tiers_for_island(next_idx: int) -> Array[int]:
	match next_idx:
		0: return [1]
		1: return [1, 2]
		2: return [2, 3]
		3: return [3, 5]
		_: return [5, 6]   # 4 及之后（末岛）→ 深渊
```

- [ ] **Step 4: 跑测试验证通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/route_offers_test.gd`
Expected: PASS（全 route_offers 测试，含 `test_degrades_when_target_tier_insufficient`：next_idx=4 → [5,6] 各 1 张 = 2 张 → 降级补到 3，size==3 仍成立）。

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/route_offers_test.gd
git commit -m "feat(run): 路线目标 tier 爬升到深层 5/6（史诗②路线可达）

Story: 高threat_tier原型史诗-子项目②
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 全量验证（verification only）

**Files:** 无改动。

- [ ] **Step 1: 导入 + 全量测试**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: PASS，0 errors/failures/orphans，导入零错。测试总数应为 528 + 新增（enemy_tier3 4 + abyss_maps 8 = +12 → 540），route_offers 测试数不变（仅断言改）。

- [ ] **Step 2: 确认无回归**

若任何既有测试因深层图/路线映射变更而红，逐一核查是否为诚实的行为变更（如 `test_degrades_*` size 断言）。**不得**放宽不变量或跳过测试。

- [ ] **Step 3: 记录到 progress.md**（追加 final-review + 验证条目，供合并）

---

## Self-Review

**1. Spec coverage：**
- §3.2 tier3 数值 → Task 1 ✓（AC-1）
- §3.3 新图 008/009 → Task 2 ✓（AC-2/AC-3/AC-4/AC-6）
- §3.4 路线映射 → Task 3 ✓（AC-5）
- §3.1 不变更项 → 各 Task 仅碰指定文件，未触战斗/AI/解算/EnemyLoadout/Rule3 ✓
- AC-8 全量绿 → Task 4 ✓
- AC-7（F5 人眼）→ 非自动化，留交付后人眼

**2. Placeholder scan：** 无 TBD/TODO；每个 .tres、测试、实现均给出完整内容。两处 `⚠️ 以实际 .tres 为准` 是「先对照一份已存在的同类文件确认字段名」的操作指示（防字段名漂移），非占位符——实现者执行 `cat enemy_melee_tier2.tres` / `cat battle_map_006.tres` 对照即可。

**3. Type consistency：** `load_map_definition(...) -> bool`、`get_maps_for_tier -> Array[MapDefinition]`、`UnitInstance.equipment: Dictionary`、`.definition.threat_tier` 均与既有 tier2 测试一致；tier3 id 命名 `enemy_X_tier3` 在 Task 1 定义、Task 2 引用一致；`_target_tiers_for_island` 返回 `Array[int]` 与既有签名一致。

**4. 已知风险：** Task 2 新图 Rule3 是唯一非平凡验证点；mitigant = 沿用 006 已验证的「空 terrain + 敌在 0-3 行 + 部署区 6-7 行」范式，§3.3 已逐项自检 Rule3。`load_steps` 计数若写错 Godot 会报错或忽略，Step 4 测试会抓到。
